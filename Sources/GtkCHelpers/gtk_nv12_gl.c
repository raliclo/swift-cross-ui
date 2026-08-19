#include "gtk_nv12_gl.h"

#include <epoxy/gl.h>
#include <stdlib.h>
#include <string.h>

// Core-profile GL 3.3, matching what GtkGLArea gives on both platforms. A
// compatibility-profile path with immediate mode would be shorter but GTK does
// not offer one, and GL ES differs enough that it is left unhandled rather than
// half-handled.
struct SCUINV12Renderer {
    GLuint program;
    GLuint vao;
    GLuint vbo;
    GLuint texture_y;
    GLuint texture_uv;
    GLint uniform_y;
    GLint uniform_uv;
    int width;
    int height;
    int has_frame;
    char *error;
};

static const char *VERTEX_SOURCE =
    "#version 330 core\n"
    "layout(location = 0) in vec2 position;\n"
    "out vec2 uv;\n"
    "void main() {\n"
    // The quad is in clip space already, so no matrices. Texture V is flipped
    // because GL samples bottom-up while the decoder writes top-down; without
    // this the picture is upside down and nothing else is wrong, which is easy
    // to misread as a decode fault.
    "    uv = vec2((position.x + 1.0) * 0.5, 1.0 - (position.y + 1.0) * 0.5);\n"
    "    gl_Position = vec4(position, 0.0, 1.0);\n"
    "}\n";

// BT.709 limited range. ffmpeg tags HD output as BT.709 and keeps 16-235 for
// luma unless told otherwise, so those are the constants that match what comes
// down the pipe. Getting this wrong does not fail -- it produces washed out or
// green-tinted video that still plays, which is why the numbers are written
// out rather than folded into a single matrix constant.
static const char *FRAGMENT_SOURCE =
    "#version 330 core\n"
    "in vec2 uv;\n"
    "out vec4 colour;\n"
    "uniform sampler2D plane_y;\n"
    "uniform sampler2D plane_uv;\n"
    "void main() {\n"
    "    float y = texture(plane_y, uv).r;\n"
    "    vec2 cbcr = texture(plane_uv, uv).rg;\n"
    "    y = (y - 0.0625) * 1.164383;\n"
    "    float cb = cbcr.x - 0.5;\n"
    "    float cr = cbcr.y - 0.5;\n"
    "    float r = y + 1.792741 * cr;\n"
    "    float g = y - 0.213249 * cb - 0.532909 * cr;\n"
    "    float b = y + 2.112402 * cb;\n"
    "    colour = vec4(clamp(vec3(r, g, b), 0.0, 1.0), 1.0);\n"
    "}\n";

static const GLfloat QUAD[] = {
    -1.0f, -1.0f,
     1.0f, -1.0f,
    -1.0f,  1.0f,
     1.0f,  1.0f,
};

static void set_error(SCUINV12Renderer *renderer, const char *message) {
    free(renderer->error);
    renderer->error = message ? strdup(message) : NULL;
}

static GLuint compile_stage(SCUINV12Renderer *renderer, GLenum kind, const char *source) {
    GLuint shader = glCreateShader(kind);
    glShaderSource(shader, 1, &source, NULL);
    glCompileShader(shader);

    GLint ok = GL_FALSE;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        GLint length = 0;
        glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &length);
        char *log = malloc((size_t)length + 1);
        if (log) {
            glGetShaderInfoLog(shader, length, NULL, log);
            log[length] = '\0';
            set_error(renderer, log);
            free(log);
        }
        glDeleteShader(shader);
        return 0;
    }
    return shader;
}

// One plane, one channel count. GL_R8 for luma and GL_RG8 for the interleaved
// chroma, so the shader reads .r and .rg with no unpacking. GL_LINEAR on the
// chroma plane is what gives free 2x upsampling: NV12 stores it at half
// resolution in both directions and the sampler interpolates it back.
static GLuint make_plane_texture(GLint internal_format) {
    GLuint texture = 0;
    glGenTextures(1, &texture);
    glBindTexture(GL_TEXTURE_2D, texture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    (void)internal_format;
    return texture;
}

SCUINV12Renderer *scui_nv12_renderer_new(void) {
    return calloc(1, sizeof(SCUINV12Renderer));
}

void scui_nv12_renderer_free(SCUINV12Renderer *renderer) {
    if (!renderer) {
        return;
    }
    // Only touched when a context is current. Deleting names against whichever
    // context happens to be bound is how unrelated textures get destroyed, and
    // it is silent.
    if (epoxy_is_desktop_gl() && renderer->program) {
        glDeleteProgram(renderer->program);
        glDeleteBuffers(1, &renderer->vbo);
        glDeleteVertexArrays(1, &renderer->vao);
        glDeleteTextures(1, &renderer->texture_y);
        glDeleteTextures(1, &renderer->texture_uv);
    }
    free(renderer->error);
    free(renderer);
}

int scui_nv12_renderer_realize(SCUINV12Renderer *renderer) {
    if (!renderer) {
        return 0;
    }
    if (renderer->program) {
        return 1;
    }

    GLuint vertex = compile_stage(renderer, GL_VERTEX_SHADER, VERTEX_SOURCE);
    if (!vertex) {
        return 0;
    }
    GLuint fragment = compile_stage(renderer, GL_FRAGMENT_SHADER, FRAGMENT_SOURCE);
    if (!fragment) {
        glDeleteShader(vertex);
        return 0;
    }

    GLuint program = glCreateProgram();
    glAttachShader(program, vertex);
    glAttachShader(program, fragment);
    glLinkProgram(program);
    glDeleteShader(vertex);
    glDeleteShader(fragment);

    GLint ok = GL_FALSE;
    glGetProgramiv(program, GL_LINK_STATUS, &ok);
    if (!ok) {
        GLint length = 0;
        glGetProgramiv(program, GL_INFO_LOG_LENGTH, &length);
        char *log = malloc((size_t)length + 1);
        if (log) {
            glGetProgramInfoLog(program, length, NULL, log);
            log[length] = '\0';
            set_error(renderer, log);
            free(log);
        }
        glDeleteProgram(program);
        return 0;
    }

    renderer->program = program;
    renderer->uniform_y = glGetUniformLocation(program, "plane_y");
    renderer->uniform_uv = glGetUniformLocation(program, "plane_uv");

    glGenVertexArrays(1, &renderer->vao);
    glBindVertexArray(renderer->vao);
    glGenBuffers(1, &renderer->vbo);
    glBindBuffer(GL_ARRAY_BUFFER, renderer->vbo);
    glBufferData(GL_ARRAY_BUFFER, sizeof(QUAD), QUAD, GL_STATIC_DRAW);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 2 * sizeof(GLfloat), NULL);
    glBindVertexArray(0);

    renderer->texture_y = make_plane_texture(GL_R8);
    renderer->texture_uv = make_plane_texture(GL_RG8);

    set_error(renderer, NULL);
    return 1;
}

const char *scui_nv12_renderer_error(const SCUINV12Renderer *renderer) {
    return renderer ? renderer->error : NULL;
}

void scui_nv12_renderer_upload(
    SCUINV12Renderer *renderer,
    const unsigned char *y,
    const unsigned char *uv,
    int width,
    int height
) {
    if (!renderer || !renderer->program || !y || !uv || width <= 0 || height <= 0) {
        return;
    }

    // Rows are tightly packed, which is not the GL default of 4. At 1080p the
    // default happens to be harmless because the width is a multiple of 4, but
    // any odd width shears the picture progressively down the frame.
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);

    const int reallocate = (width != renderer->width || height != renderer->height);
    renderer->width = width;
    renderer->height = height;

    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, renderer->texture_y);
    if (reallocate) {
        glTexImage2D(GL_TEXTURE_2D, 0, GL_R8, width, height, 0, GL_RED, GL_UNSIGNED_BYTE, y);
    } else {
        // glTexSubImage2D on a resident texture rather than reallocating each
        // frame; the allocation is the expensive half and the size only changes
        // when the resolution picker does.
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, width, height, GL_RED, GL_UNSIGNED_BYTE, y);
    }

    glActiveTexture(GL_TEXTURE1);
    glBindTexture(GL_TEXTURE_2D, renderer->texture_uv);
    if (reallocate) {
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RG8, width / 2, height / 2, 0, GL_RG, GL_UNSIGNED_BYTE, uv);
    } else {
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, width / 2, height / 2, GL_RG, GL_UNSIGNED_BYTE, uv);
    }

    renderer->has_frame = 1;
}

void scui_nv12_renderer_render(SCUINV12Renderer *renderer) {
    if (!renderer || !renderer->program || !renderer->has_frame) {
        return;
    }

    // No glViewport here. GtkGLArea binds its framebuffer and sets the viewport
    // before emitting `render`, and overriding it with a size computed from the
    // widget got it wrong: gtk_widget_get_width times the scale factor does not
    // equal the framebuffer size, and the quad came out squeezed into the right
    // quarter of the area with the rest black. That looks like a decode or
    // upload fault and is neither.
    // 此處不呼叫 glViewport。GtkGLArea 會在發出 `render` 之前綁定其 framebuffer 並設定
    // viewport；若以依 widget 計算出的尺寸覆寫它，結果是錯的：gtk_widget_get_width 乘上
    // scale factor 並不等於 framebuffer 尺寸，導致四邊形被擠進區域右側四分之一，其餘全黑。
    // 該現象看起來像解碼或上傳缺陷，但兩者皆非。
    glUseProgram(renderer->program);

    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, renderer->texture_y);
    glUniform1i(renderer->uniform_y, 0);

    glActiveTexture(GL_TEXTURE1);
    glBindTexture(GL_TEXTURE_2D, renderer->texture_uv);
    glUniform1i(renderer->uniform_uv, 1);

    glBindVertexArray(renderer->vao);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    glBindVertexArray(0);
    glUseProgram(0);
}
