#ifndef GTK_NV12_GL_H
#define GTK_NV12_GL_H

// Uploads NV12 frames as two GL textures and converts them to RGB in a
// fragment shader, for drawing inside a GtkGLArea.
//
// Why this exists in C rather than Swift: the conversion needs OpenGL calls,
// and Swift has no GL bindings here. GTK already depends on libepoxy for its
// own renderer, so using it costs no new dependency.
//
// Why NV12 rather than RGBA: transport, not drawing. Measured at 1080p60, an
// RGBA frame is 7.91 MB and needs 475 MB/s through the decoder pipe, while the
// pipe tops out between 247 and 416 MB/s -- which is why playback sat at 30-43
// fps with zero dropped frames. The same frame in NV12 is 2.97 MB and needs
// 178 MB/s, comfortably under that ceiling. Converting NV12 back to RGB on the
// CPU would hand the saving straight back, so the conversion has to happen on
// the GPU, which is what this file is for.

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct SCUINV12Renderer SCUINV12Renderer;

/// Allocates the renderer. No GL calls happen here -- there is no current
/// context yet when a widget is constructed.
SCUINV12Renderer *scui_nv12_renderer_new(void);

/// Frees the renderer. GL objects are released first if a context is current;
/// if none is, they are leaked deliberately rather than deleted against the
/// wrong context, which corrupts unrelated textures.
void scui_nv12_renderer_free(SCUINV12Renderer *renderer);

/// Compiles the program and creates the textures. Call with the GtkGLArea's
/// context current, that is from the `realize` handler or the first `render`.
/// Returns 1 on success, 0 on failure; on failure `scui_nv12_renderer_error`
/// holds the compiler or linker log.
int scui_nv12_renderer_realize(SCUINV12Renderer *renderer);

/// The last failure, or NULL. Owned by the renderer.
const char *scui_nv12_renderer_error(const SCUINV12Renderer *renderer);

/// Copies one NV12 frame into the textures. `y` is width*height bytes and `uv`
/// is width*(height/2) bytes of interleaved Cb/Cr, which is the layout ffmpeg
/// writes for `-pix_fmt nv12`. Requires a current context.
void scui_nv12_renderer_upload(
    SCUINV12Renderer *renderer,
    const unsigned char *y,
    const unsigned char *uv,
    int width,
    int height
);

/// Draws the last uploaded frame over the whole viewport. Requires a current
/// context. Does nothing before the first upload, so a render that arrives
/// before any frame leaves the area at its clear colour rather than drawing
/// uninitialised texture memory.
///
/// Takes no size: GtkGLArea has already bound its framebuffer and set the
/// viewport by the time `render` is emitted. An earlier version took a width
/// and height and called glViewport with them, which drew the picture into the
/// right quarter of the widget.
void scui_nv12_renderer_render(SCUINV12Renderer *renderer);

#ifdef __cplusplus
}
#endif

#endif
