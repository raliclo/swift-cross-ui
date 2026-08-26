// A dark or light native title bar for a GTK window on Windows.
//
// See the declaration in include/gtk_helpers.h for why only Windows needs this.

#include "include/gtk_helpers.h"

#ifdef G_OS_WIN32
#include <gdk/win32/gdkwin32.h>
#include <windows.h>
#include <dwmapi.h>

// Named here rather than relied on from the SDK headers: the constant is
// version-gated, so a build against an older SDK would not see it and the file
// would fail to compile for a reason that has nothing to do with the machine it
// will run on.
#define SCUI_DWMWA_USE_IMMERSIVE_DARK_MODE 20
#define SCUI_DWMWA_USE_IMMERSIVE_DARK_MODE_1809 19
#endif

gboolean scui_window_set_dark_titlebar(GtkWidget *window, gboolean dark) {
#ifdef G_OS_WIN32
    if (!GTK_IS_NATIVE(window)) {
        return FALSE;
    }

    // Same as the topmost helper: no surface before the window is realized, so
    // report FALSE and let the caller try again on a later update rather than
    // claiming a success that did not happen.
    GdkSurface *surface = gtk_native_get_surface(GTK_NATIVE(window));
    if (surface == NULL) {
        return FALSE;
    }

    HWND handle = gdk_win32_surface_get_handle(surface);
    if (handle == NULL) {
        return FALSE;
    }

    BOOL value = dark ? TRUE : FALSE;

    // The current attribute first. On a build that does not know it, the call
    // returns a failure code and changes nothing, so falling back costs one
    // more call and never leaves a half-applied state.
    HRESULT result = DwmSetWindowAttribute(
        handle, SCUI_DWMWA_USE_IMMERSIVE_DARK_MODE, &value, sizeof(value)
    );
    if (FAILED(result)) {
        result = DwmSetWindowAttribute(
            handle, SCUI_DWMWA_USE_IMMERSIVE_DARK_MODE_1809, &value, sizeof(value)
        );
    }
    if (FAILED(result)) {
        return FALSE;
    }

    // The bar is not redrawn by the attribute change alone on every build. A
    // no-op SetWindowPos with SWP_FRAMECHANGED asks for the non-client area to
    // be repainted without moving, resizing, reordering or activating anything.
    SetWindowPos(
        handle, NULL, 0, 0, 0, 0,
        SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED
    );
    return TRUE;
#else
    (void)window;
    (void)dark;
    return FALSE;
#endif
}
