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
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <string.h>
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

#if !defined(G_OS_WIN32) && defined(GDK_WINDOWING_X11)
// The GDK X11 API is deprecated as a whole since 4.18. / GDK 的 X11 API 自 4.18 起整體棄用。
G_GNUC_BEGIN_IGNORE_DEPRECATIONS
// A move to make once the window is mapped; see scui_window_place_in_work_area.
// 視窗映射之後要做的移動；見 scui_window_place_in_work_area。
typedef struct {
    GtkWidget *window;
    int x;
    int y;
} ScuiPlaceAfterMap;

static void scui_x11_move(GtkWidget *window, int x, int y) {
    GdkSurface *surface = gtk_native_get_surface(GTK_NATIVE(window));
    if (surface == NULL || !GDK_IS_X11_SURFACE(surface)) {
        return;
    }
    Display *xdisplay = gdk_x11_display_get_xdisplay(gdk_surface_get_display(surface));
    XMoveWindow(xdisplay, gdk_x11_surface_get_xid(surface), x, y);
    XFlush(xdisplay);
}

static gboolean scui_place_after_map_timeout(gpointer data) {
    ScuiPlaceAfterMap *place = data;
    scui_x11_move(place->window, place->x, place->y);
    g_object_unref(place->window);
    g_free(place);
    return G_SOURCE_REMOVE;
}

static void scui_place_after_map(GtkWidget *window, gpointer data) {
    ScuiPlaceAfterMap *pending = data;
    ScuiPlaceAfterMap *place = g_new0(ScuiPlaceAfterMap, 1);
    place->window = g_object_ref(window);
    place->x = pending->x;
    place->y = pending->y;
    g_timeout_add(100, scui_place_after_map_timeout, place);
    // Frees `pending` through the closure's destroy notify. / 經由 closure 的 destroy notify 釋放 `pending`。
    g_signal_handlers_disconnect_by_func(window, G_CALLBACK(scui_place_after_map), data);
}
G_GNUC_END_IGNORE_DEPRECATIONS
#endif

gboolean scui_window_place_in_work_area(GtkWidget *window, int x, int y) {
#ifdef G_OS_WIN32
    if (!GTK_IS_NATIVE(window)) {
        return FALSE;
    }
    // Realized here, before present, so there is an HWND to move while the
    // window is still hidden; present realizes it anyway.
    // 在這裡、present 之前先 realize,好讓視窗還隱藏時就有 HWND 可移動;present 本來也會 realize。
    if (!gtk_widget_get_realized(window)) {
        gtk_widget_realize(window);
    }
    GdkSurface *surface = gtk_native_get_surface(GTK_NATIVE(window));
    HWND handle = surface != NULL ? gdk_win32_surface_get_handle(surface) : NULL;
    if (handle == NULL) {
        return FALSE;
    }
    HMONITOR monitor = MonitorFromWindow(handle, MONITOR_DEFAULTTOPRIMARY);
    MONITORINFO info;
    info.cbSize = sizeof info;
    if (monitor == NULL || !GetMonitorInfoW(monitor, &info)) {
        return FALSE;
    }
    return SetWindowPos(handle, NULL, info.rcWork.left + x, info.rcWork.top + y, 0, 0,
                        SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE)
               ? TRUE
               : FALSE;
#elif defined(GDK_WINDOWING_X11)
    // The GDK X11 API is deprecated as a whole since 4.18, with no replacement
    // for what this does. / GDK 的 X11 API 自 4.18 起整體棄用，這裡做的事沒有替代品。
    G_GNUC_BEGIN_IGNORE_DEPRECATIONS
    // X11 (Linux, and WSLg's XWayland): move the X window and mark the
    // position as the user's (USPosition), so the window manager keeps it
    // instead of placing the window itself. GDK may rewrite the normal hints
    // when it maps the window, which is why GtkBackend calls this again right
    // after present. Wayland has no way for a client to place a toplevel; an
    // action-file run in CI needs an X server (Xvfb, or WSLg's XWayland).
    // X11(Linux 與 WSLg 的 XWayland):移動 X 視窗，並把位置標成使用者指定的(USPosition),讓視窗管理員保留它而不自己擺。
    // GDK 映射視窗時可能改寫 normal hints,所以 GtkBackend 在 present 之後會再呼叫一次。Wayland 沒有讓 client 擺放頂層視窗
    // 的方法;CI 上的動作檔執行需要 X server(Xvfb,或 WSLg 的 XWayland)。
    if (!GTK_IS_NATIVE(window)) {
        return FALSE;
    }
    if (!gtk_widget_get_realized(window)) {
        gtk_widget_realize(window);
    }
    GdkSurface *surface = gtk_native_get_surface(GTK_NATIVE(window));
    if (surface == NULL || !GDK_IS_X11_SURFACE(surface)) {
        return FALSE;
    }
    GdkDisplay *display = gdk_surface_get_display(surface);
    GdkRectangle area = {0, 0, 0, 0};
    GListModel *monitors = gdk_display_get_monitors(display);
    if (g_list_model_get_n_items(monitors) > 0) {
        GdkMonitor *monitor = g_list_model_get_item(monitors, 0);
        if (GDK_IS_X11_MONITOR(monitor)) {
            gdk_x11_monitor_get_workarea(monitor, &area);
        }
        g_object_unref(monitor);
    }
    Display *xdisplay = gdk_x11_display_get_xdisplay(display);
    Window xid = gdk_x11_surface_get_xid(surface);
    XSizeHints hints;
    long supplied = 0;
    if (!XGetWMNormalHints(xdisplay, xid, &hints, &supplied)) {
        memset(&hints, 0, sizeof hints);
    }
    hints.flags |= USPosition;
    hints.x = area.x + x;
    hints.y = area.y + y;
    XSetWMNormalHints(xdisplay, xid, &hints);
    XMoveWindow(xdisplay, xid, area.x + x, area.y + y);
    XFlush(xdisplay);
    // GDK maps the window at its own idea of the position (0, 0 under WSLg),
    // which overrides a move made before the map: four launches opened at
    // (0, 0) every time (2026-11-14). Moved once more 100 ms after the map,
    // when the window manager takes it as an ordinary ConfigureRequest; an
    // `xdotool windowmove` at that point was honoured.
    // GDK 會以它自己認定的位置映射視窗(WSLg 下為 0, 0),蓋過映射前的移動：啟動 4 次都開在 (0, 0)(2026-11-14)。
    // 映射 100 ms 後再移動一次，這時視窗管理員把它當成一般的 ConfigureRequest;那時的 `xdotool windowmove` 有被採用。
    if (!gtk_widget_get_mapped(window) &&
        g_object_get_data(G_OBJECT(window), "scui-place-after-map") == NULL) {
        g_object_set_data(G_OBJECT(window), "scui-place-after-map", GINT_TO_POINTER(1));
        ScuiPlaceAfterMap *pending = g_new0(ScuiPlaceAfterMap, 1);
        pending->x = area.x + x;
        pending->y = area.y + y;
        g_signal_connect_data(window, "map", G_CALLBACK(scui_place_after_map), pending,
                              (GClosureNotify)g_free, 0);
    }
    return TRUE;
    G_GNUC_END_IGNORE_DEPRECATIONS
#else
    (void)window;
    (void)x;
    (void)y;
    return FALSE;
#endif
}
