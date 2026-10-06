#ifndef GTK_MESH3D_GL_H
#define GTK_MESH3D_GL_H

// Mesh3DView's renderer for GtkBackend: core-profile GL 3.3 through libepoxy,
// the same footing as gtk_nv12_gl.c. The shaders are AndroidBackend's GLES 2
// pair written for GL 3.3 -- same Lambert term, same 0.25 ambient -- so a scene
// lights the same on every backend.
//
// GtkBackend 的 Mesh3DView 算繪器：經由 libepoxy 的 core-profile GL 3.3,與 gtk_nv12_gl.c 相同的基礎。
// shader 是 AndroidBackend 那對 GLES 2 shader 改寫成 GL 3.3——相同的 Lambert 項、相同的 0.25 環境光——
// 因此同一個場景在每個 backend 上的打光都相同。

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct SCUIMesh3DRenderer SCUIMesh3DRenderer;

SCUIMesh3DRenderer *scui_mesh3d_renderer_new(void);
void scui_mesh3d_renderer_free(SCUIMesh3DRenderer *renderer);

/// Compiles the program and creates the buffers; call with the GLArea's
/// context current. Returns 0 on failure, with the reason in `error`.
int scui_mesh3d_renderer_realize(SCUIMesh3DRenderer *renderer);
const char *scui_mesh3d_renderer_error(const SCUIMesh3DRenderer *renderer);
/// "GL_RENDERER / GL_VERSION", valid after realize.
const char *scui_mesh3d_renderer_name(const SCUIMesh3DRenderer *renderer);

/// Nine floats per vertex (position, normal, colour); indices into them.
void scui_mesh3d_renderer_set_geometry(
    SCUIMesh3DRenderer *renderer,
    const float *vertices,
    int vertex_float_count,
    const uint32_t *indices,
    int index_count
);

/// One frame. Per mesh: mode (0 triangles, 1 lines, 2 points), start (an index
/// offset for triangles, a vertex offset otherwise), count, point size, flags
/// (1 lit, 2 depth-tested), sixteen floats of MVP and of normal matrix.
/// Returns the microseconds until glFinish when `measure` is set, else -1.
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
);

/// The bound framebuffer's pixels, top row first, RGBA8.
void scui_mesh3d_renderer_read_pixels(int width, int height, unsigned char *rgba);

#ifdef __cplusplus
}
#endif

#endif
