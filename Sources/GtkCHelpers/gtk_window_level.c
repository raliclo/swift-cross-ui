// Always-on-top for a GTK window, where the platform has such a thing.
//
// See the declaration in include/gtk_helpers.h for why this cannot be done in
// Swift, and for what was measured about the platforms that cannot do it.

#include "include/gtk_helpers.h"

#ifdef G_OS_WIN32
#include <gdk/win32/gdkwin32.h>
#include <windows.h>
#endif

gboolean scui_window_set_topmost(GtkWidget *window, gboolean topmost) {
#ifdef G_OS_WIN32
    if (!GTK_IS_NATIVE(window)) {
        return FALSE;
    }

    // The surface exists only once the window has been realized, so a call
    // before the window is shown has nothing to act on. Reporting FALSE rather
    // than silently succeeding lets the caller retry, which it does: the level
    // is applied on every update, not once.
    GdkSurface *surface = gtk_native_get_surface(GTK_NATIVE(window));
    if (surface == NULL) {
        return FALSE;
    }

    HWND handle = gdk_win32_surface_get_handle(surface);
    if (handle == NULL) {
        return FALSE;
    }

    // SWP_NOACTIVATE because this must not steal focus. Taking the foreground
    // is a separate thing Windows restricts to the process already in front,
    // whereas raising your own window has no such rule -- which is the whole
    // reason this works from a background-launched process and
    // SetForegroundWindow does not.
    return SetWindowPos(
        handle,
        topmost ? HWND_TOPMOST : HWND_NOTOPMOST,
        0, 0, 0, 0,
        SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE
    ) ? TRUE : FALSE;
#else
    (void)window;
    (void)topmost;
    return FALSE;
#endif
}
