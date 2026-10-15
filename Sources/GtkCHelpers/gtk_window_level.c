// Always-on-top for a GTK window, where the platform has such a thing.
//
// See the declaration in include/gtk_helpers.h for why this cannot be done in
// Swift, and for what was measured about the platforms that cannot do it.

#include "include/gtk_helpers.h"

#ifdef G_OS_WIN32
#include <gdk/win32/gdkwin32.h>
#include <windows.h>
#elif defined(__APPLE__)
#include <gdk/macos/gdkmacos.h>
#include <objc/message.h>
#include <objc/runtime.h>
#endif

gboolean scui_window_set_topmost(GtkWidget *window, gboolean topmost) {
#ifdef G_OS_WIN32
    if (!GTK_IS_NATIVE(window)) {
        return FALSE;
    }

    // The surface exists only once the window has been realized, so a call
    // before the window is shown has nothing to act on. Reporting FALSE rather
    // than silently succeeding lets the caller distinguish that from a platform
    // API call that actually succeeded.
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
#elif defined(__APPLE__)
    /* On macOS a GDK surface is an NSWindow in this process, and its level is
     * what .floating means: NSFloatingWindowLevel is 3, NSNormalWindowLevel 0.
     * Set through the Objective-C runtime because this file is C. P37 read
     * "floating is NOT supported" on GtkBackend on macOS until 2026-10-16.
     * macOS 上 GDK surface 就是本行程中的一個 NSWindow,其 level 即 .floating 的意義:
     * NSFloatingWindowLevel 為 3、NSNormalWindowLevel 為 0。本檔是 C,因此經由 Objective-C runtime 設定。 */
    if (!GTK_IS_NATIVE(window)) {
        return FALSE;
    }
    GdkSurface *surface = gtk_native_get_surface(GTK_NATIVE(window));
    if (surface == NULL || !GDK_IS_MACOS_SURFACE(surface)) {
        return FALSE;
    }
    id native = (id)gdk_macos_surface_get_native_window(GDK_MACOS_SURFACE(surface));
    if (native == NULL) {
        return FALSE;
    }
    ((void (*)(id, SEL, long))objc_msgSend)(native, sel_registerName("setLevel:"), topmost ? 3 : 0);
    return TRUE;
#else
    (void)window;
    (void)topmost;
    return FALSE;
#endif
}
