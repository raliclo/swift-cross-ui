#include "gtk_mesh3d_gl.h"
#include <epoxy/gl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

struct SCUIMesh3DRenderer {
    GLuint program;
    GLuint vao;
    GLuint vbo;
    GLuint ebo;
    GLint u_mvp;
    GLint u_normal;
    GLint u_light;
    GLint u_point_size;
    GLint u_lit;
    GLint u_opacity;
    char name[256];
    char *error;
};

static const char *VERTEX_SOURCE =
    "layout(location = 0) in vec3 aPosition;\n"
    "layout(location = 1) in vec3 aNormal;\n"
    "layout(location = 2) in vec3 aColour;\n"
    "uniform mat4 uMvp;\n"
    "uniform mat4 uNormal;\n"
    "uniform float uPointSize;\n"
    "out vec3 vNormal;\n"
    "out vec3 vColour;\n"
    "void main() {\n"
    "    gl_Position = uMvp * vec4(aPosition, 1.0);\n"
    "    gl_PointSize = uPointSize;\n"
    "    vNormal = (uNormal * vec4(aNormal, 0.0)).xyz;\n"
    "    vColour = aColour;\n"
    "}\n";

static const char *FRAGMENT_SOURCE =
    "uniform vec3 uLight;\n"
    "uniform float uLit;\n"
    "uniform float uOpacity;\n"
    "in vec3 vNormal;\n"
    "in vec3 vColour;\n"
    "out vec4 colour;\n"
    "void main() {\n"
    "    if (uLit < 0.5) { colour = vec4(vColour, uOpacity); return; }\n"
    "    vec3 n = normalize(vNormal);\n"
    "    vec3 l = normalize(-uLight);\n"
    "    float lambert = max(dot(n, l), 0.0);\n"
    "    colour = vec4(vColour * (0.25 + 0.75 * lambert), uOpacity);\n"
    "}\n";

static void set_error(SCUIMesh3DRenderer *renderer, const char *what, const char *detail) {
    free(renderer->error);
    size_t length = strlen(what) + (detail ? strlen(detail) : 0) + 3;
    renderer->error = malloc(length);
    snprintf(renderer->error, length, "%s: %s", what, detail ? detail : "");
}

static GLuint compile(SCUIMesh3DRenderer *renderer, GLenum type, const char *source) {
    GLuint shader = glCreateShader(type);
    // The version line is chosen per context. GTK creates whichever its EGL
    // or GLX layer prefers: desktop GL 3.3 on macOS, but an OpenGL ES 3.0
    // context under WSLg (Mesa d3d12; GDK_DEBUG=opengl: "es:yes"), where a
    // "#version 330 core" shader fails to compile and the view drew nothing,
    // silently (2026-10-07). The bodies are valid GLSL 330 and GLSL ES 300.
    // 版本行依 context 而定。GTK 建立的是其 EGL 或 GLX 層偏好的那種:macOS 上是桌面 GL 3.3,但在 WSLg
    // (Mesa d3d12;GDK_DEBUG=opengl 顯示「es:yes」)下是 OpenGL ES 3.0,「#version 330 core」的 shader 在那裡
    // 編譯失敗，畫面便無聲地什麼都沒畫(2026-10-07)。主體同時是合法的 GLSL 330 與 GLSL ES 300。
    const char *header = epoxy_is_desktop_gl()
        ? "#version 330 core\n"
        : "#version 300 es\nprecision highp float;\n";
    const char *sources[2] = { header, source };
    glShaderSource(shader, 2, sources, NULL);
    glCompileShader(shader);
    GLint ok = 0;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[1024];
        glGetShaderInfoLog(shader, sizeof log, NULL, log);
        set_error(renderer, type == GL_VERTEX_SHADER ? "vertex shader" : "fragment shader", log);
        glDeleteShader(shader);
        return 0;
    }
    return shader;
}

SCUIMesh3DRenderer *scui_mesh3d_renderer_new(void) {
    return calloc(1, sizeof(SCUIMesh3DRenderer));
}

void scui_mesh3d_renderer_free(SCUIMesh3DRenderer *renderer) {
    if (!renderer) return;
    // GL objects die with the GLArea's context; deleting them here would need
    // that context current, which a Swift deinit cannot promise.
    // GL 物件隨 GLArea 的 context 一起消失；在此刪除需要該 context 為 current,而 Swift 的 deinit 無法保證。
    free(renderer->error);
    free(renderer);
}

int scui_mesh3d_renderer_realize(SCUIMesh3DRenderer *renderer) {
    GLuint vertex = compile(renderer, GL_VERTEX_SHADER, VERTEX_SOURCE);
    if (!vertex) return 0;
    GLuint fragment = compile(renderer, GL_FRAGMENT_SHADER, FRAGMENT_SOURCE);
    if (!fragment) { glDeleteShader(vertex); return 0; }
    renderer->program = glCreateProgram();
    glAttachShader(renderer->program, vertex);
    glAttachShader(renderer->program, fragment);
    glLinkProgram(renderer->program);
    glDeleteShader(vertex);
    glDeleteShader(fragment);
    GLint ok = 0;
    glGetProgramiv(renderer->program, GL_LINK_STATUS, &ok);
    if (!ok) {
        char log[1024];
        glGetProgramInfoLog(renderer->program, sizeof log, NULL, log);
        set_error(renderer, "link", log);
        return 0;
    }
    renderer->u_mvp = glGetUniformLocation(renderer->program, "uMvp");
    renderer->u_normal = glGetUniformLocation(renderer->program, "uNormal");
    renderer->u_light = glGetUniformLocation(renderer->program, "uLight");
    renderer->u_point_size = glGetUniformLocation(renderer->program, "uPointSize");
    renderer->u_lit = glGetUniformLocation(renderer->program, "uLit");
    renderer->u_opacity = glGetUniformLocation(renderer->program, "uOpacity");

    glGenVertexArrays(1, &renderer->vao);
    glBindVertexArray(renderer->vao);
    glGenBuffers(1, &renderer->vbo);
    glGenBuffers(1, &renderer->ebo);
    glBindBuffer(GL_ARRAY_BUFFER, renderer->vbo);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, renderer->ebo);
    for (int attribute = 0; attribute < 3; attribute++) {
        glVertexAttribPointer(
            attribute, 3, GL_FLOAT, GL_FALSE, 9 * sizeof(float),
            (const void *)(uintptr_t)(attribute * 3 * sizeof(float))
        );
        glEnableVertexAttribArray(attribute);
    }
    glBindVertexArray(0);

    snprintf(
        renderer->name, sizeof renderer->name, "%s / %s",
        (const char *)glGetString(GL_RENDERER), (const char *)glGetString(GL_VERSION)
    );
    return 1;
}

void scui_mesh3d_renderer_release(SCUIMesh3DRenderer *renderer) {
    if (renderer->ebo) glDeleteBuffers(1, &renderer->ebo);
    if (renderer->vbo) glDeleteBuffers(1, &renderer->vbo);
    if (renderer->vao) glDeleteVertexArrays(1, &renderer->vao);
    if (renderer->program) glDeleteProgram(renderer->program);
    renderer->ebo = renderer->vbo = renderer->vao = renderer->program = 0;
    free(renderer->error);
    renderer->error = NULL;
}

const char *scui_mesh3d_renderer_error(const SCUIMesh3DRenderer *renderer) {
    return renderer->error;
}

const char *scui_mesh3d_renderer_name(const SCUIMesh3DRenderer *renderer) {
    return renderer->name;
}

void scui_mesh3d_renderer_set_geometry(
    SCUIMesh3DRenderer *renderer,
    const float *vertices,
    int vertex_float_count,
    const uint32_t *indices,
    int index_count
) {
    if (!renderer->vao) return;
    glBindVertexArray(renderer->vao);
    glBindBuffer(GL_ARRAY_BUFFER, renderer->vbo);
    glBufferData(GL_ARRAY_BUFFER, (GLsizeiptr)vertex_float_count * sizeof(float), vertices, GL_STATIC_DRAW);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, renderer->ebo);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, (GLsizeiptr)index_count * sizeof(uint32_t), indices, GL_STATIC_DRAW);
    glBindVertexArray(0);
}

static long microseconds_now(void) {
    struct timespec now;
    timespec_get(&now, TIME_UTC);
    return (long)now.tv_sec * 1000000L + now.tv_nsec / 1000;
}

long scui_mesh3d_renderer_render(
    SCUIMesh3DRenderer *renderer,
    int mesh_count,
    const int *modes,
    const int *starts,
    const int *counts,
    const float *point_sizes,
    const int *flags,
    const float *mvps,
    const float *normals,
    const float *light,
    const float *background,
    int measure
) {
    long started = measure ? microseconds_now() : 0;
    glClearColor(background[0], background[1], background[2], background[3]);
    glEnable(GL_DEPTH_TEST);
    glDepthMask(GL_TRUE);
    glDepthFunc(GL_LESS);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    if (renderer->program && renderer->vao) {
        // gl_PointSize is ignored in a core profile unless this is on.
        // 在 core profile 中，除非開啟這項，否則 gl_PointSize 會被忽略。
        // A desktop-GL capability only: in OpenGL ES the enum is invalid and
        // points are always sized by gl_PointSize.
        // 僅限桌面 GL:在 OpenGL ES 中此列舉無效，點的大小一律由 gl_PointSize 決定。
        if (epoxy_is_desktop_gl()) glEnable(GL_PROGRAM_POINT_SIZE);
        glUseProgram(renderer->program);
        glUniform3f(renderer->u_light, light[0], light[1], light[2]);
        glBindVertexArray(renderer->vao);
        /* Opaque meshes first, in scene order; then the translucent ones (flags bits 8-15 hold
           255 x transparency), blended over them with no depth writes. See Mesh3D.opacity.
           先畫不透明的 mesh、依場景順序；再畫半透明的（flags 第 8-15 位存 255 x 透明度），與其混合且
           不寫入深度。見 Mesh3D.opacity。 */
        glBlendFuncSeparate(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
        for (int pass = 0; pass < 2; pass++) {
            if (pass == 1) glEnable(GL_BLEND);
            for (int i = 0; i < mesh_count; i++) {
                if (counts[i] <= 0) continue;
                int transparency = (flags[i] >> 8) & 255;
                if ((transparency != 0) != (pass == 1)) continue;
                glUniform1f(renderer->u_opacity, 1.0f - transparency / 255.0f);
                glUniformMatrix4fv(renderer->u_mvp, 1, GL_FALSE, mvps + i * 16);
                glUniformMatrix4fv(renderer->u_normal, 1, GL_FALSE, normals + i * 16);
                glUniform1f(renderer->u_point_size, point_sizes[i]);
                glUniform1f(renderer->u_lit, (flags[i] & 1) ? 1.0f : 0.0f);
                if (flags[i] & 2) {
                    glDepthFunc(GL_LESS);
                    glDepthMask(pass == 0 ? GL_TRUE : GL_FALSE);
                } else {
                    glDepthFunc(GL_ALWAYS);
                    glDepthMask(GL_FALSE);
                }
                switch (modes[i]) {
                    case 0:
                        glDrawElements(
                            GL_TRIANGLES, counts[i], GL_UNSIGNED_INT,
                            (const void *)(uintptr_t)((size_t)starts[i] * sizeof(uint32_t))
                        );
                        break;
                    case 1: glDrawArrays(GL_LINES, starts[i], counts[i]); break;
                    case 2: glDrawArrays(GL_POINTS, starts[i], counts[i]); break;
                }
            }
        }
        glDisable(GL_BLEND);
        glBindVertexArray(0);
        glDepthMask(GL_TRUE);
        glDepthFunc(GL_LESS);
    }

    if (!measure) return -1;
    glFinish();
    return microseconds_now() - started;
}

void scui_mesh3d_renderer_read_pixels(int width, int height, unsigned char *rgba) {
    size_t row = (size_t)width * 4;
    unsigned char *bottom_up = malloc(row * (size_t)height);
    if (!bottom_up) return;
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, bottom_up);
    for (int y = 0; y < height; y++) {
        memcpy(rgba + (size_t)y * row, bottom_up + (size_t)(height - 1 - y) * row, row);
    }
    free(bottom_up);
}
