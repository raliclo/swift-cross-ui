// The NSWindow behind a GTK window on macOS, for what GTK does not set on it.
//
// See the declaration in include/gtk_helpers.h for why: GTK 4.24 on macOS leaves
// its windows' pixels untagged, so they are shown in the display's own colour
// space instead of sRGB.
//
// macOS 上 GTK 視窗背後的 NSWindow,用來設定 GTK 沒有設定的東西。原因見 include/gtk_helpers.h 中的宣告:
// macOS 上的 GTK 4.24 不為視窗的像素標記色彩空間，於是它們以螢幕自己的色彩空間顯示，而不是 sRGB。

#include "include/gtk_helpers.h"

#ifdef GDK_WINDOWING_MACOS
#include <gdk/macos/gdkmacos.h>
#endif

void *scui_window_native_macos(GtkWidget *window) {
#ifdef GDK_WINDOWING_MACOS
    // Realized only: before the window is shown there is no surface, and no
    // NSWindow. / 僅限已 realize:視窗顯示之前沒有 surface,也就沒有 NSWindow。
    if (!GTK_IS_NATIVE(window)) {
        return NULL;
    }
    GdkSurface *surface = gtk_native_get_surface(GTK_NATIVE(window));
    if (surface == NULL || !GDK_IS_MACOS_SURFACE(surface)) {
        return NULL;
    }
    return gdk_macos_surface_get_native_window(GDK_MACOS_SURFACE(surface));
#else
    (void)window;
    return NULL;
#endif
}
