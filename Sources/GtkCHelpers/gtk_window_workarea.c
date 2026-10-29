// How much of the screen a window can grow into from where it is.
//
// See the declaration in include/gtk_helpers.h for why GtkBackend caps a
// window at this, and for what was measured.
//
// 視窗從目前的位置起，能在螢幕上長到多大。為何 GtkBackend 以此為上限、量到了什麼，見
// include/gtk_helpers.h 的宣告。

#include "include/gtk_helpers.h"

#ifdef G_OS_WIN32
#include <gdk/win32/gdkwin32.h>
#include <windows.h>
#elif defined(GDK_WINDOWING_X11)
#include <gdk/x11/gdkx.h>
#endif

gboolean scui_window_screen_space(GtkWidget *window, int *width, int *height) {
    if (!GTK_IS_NATIVE(window)) {
        return FALSE;
    }
    GdkSurface *surface = gtk_native_get_surface(GTK_NATIVE(window));

    // The client-side shadow around the window is part of the surface but
    // not of anything the user sees; it is taken off both sides.
    // 視窗四周的 client-side 陰影屬於 surface,卻不是使用者看得到的部分；兩側都扣掉。
    double shadow_x = 0.0;
    double shadow_y = 0.0;
    if (surface != NULL) {
        gtk_native_get_surface_transform(GTK_NATIVE(window), &shadow_x, &shadow_y);
    }

#ifdef G_OS_WIN32
    // Win32 for the work area: GDK has gdk_win32_monitor_get_workarea, but no
    // monitor before the window is shown, and a GDK size on this build is a
    // physical pixel, as the work area is (the display scale is not applied;
    // see scui_window_display_scale).
    // 工作區用 Win32 取：GDK 有 gdk_win32_monitor_get_workarea,但視窗顯示前沒有 monitor;而且在這個建置上
    // GDK 的尺寸就是實體像素，與工作區相同(顯示器縮放不會套用，見 scui_window_display_scale)。
    HWND handle = surface != NULL ? gdk_win32_surface_get_handle(surface) : NULL;
    POINT origin = {0, 0};
    HMONITOR monitor = handle != NULL ? MonitorFromWindow(handle, MONITOR_DEFAULTTONEAREST)
                                      : MonitorFromPoint(origin, MONITOR_DEFAULTTOPRIMARY);
    MONITORINFO info;
    info.cbSize = sizeof info;
    if (monitor == NULL || !GetMonitorInfoW(monitor, &info)) {
        return FALSE;
    }
    RECT work = info.rcWork;
    LONG left = work.left;
    LONG top = work.top;
    RECT frame;
    if (handle != NULL && GetWindowRect(handle, &frame)) {
        left = CLAMP(frame.left, work.left, work.right);
        top = CLAMP(frame.top, work.top, work.bottom);
    }
    *width = (int)(work.right - left);
    *height = (int)(work.bottom - top);
#else
    GdkDisplay *display = gtk_widget_get_display(window);
    GdkMonitor *monitor = NULL;
    if (surface != NULL) {
        monitor = gdk_display_get_monitor_at_surface(display, surface);
        if (monitor != NULL) {
            g_object_ref(monitor);
        }
    }
    if (monitor == NULL) {
        GListModel *monitors = gdk_display_get_monitors(display);
        if (g_list_model_get_n_items(monitors) > 0) {
            monitor = g_list_model_get_item(monitors, 0);
        }
    }
    if (monitor == NULL) {
        return FALSE;
    }
    GdkRectangle area;
    gdk_monitor_get_geometry(monitor, &area);
#ifdef GDK_WINDOWING_X11
    // The panels' struts out, where the window manager publishes them.
    // 扣掉面板保留的區域(視窗管理員有公布時)。
    if (GDK_IS_X11_MONITOR(monitor)) {
        gdk_x11_monitor_get_workarea(monitor, &area);
    }
#endif
    g_object_unref(monitor);
    *width = area.width;
    *height = area.height;
#endif

    *width -= (int)(2.0 * shadow_x);
    *height -= (int)(2.0 * shadow_y);
    return *width > 0 && *height > 0;
}
