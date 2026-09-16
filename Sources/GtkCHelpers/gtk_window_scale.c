// What the DISPLAY says the scale is, as opposed to what GTK laid out at.
//
// See the declaration in include/gtk_helpers.h for the measurement that makes
// this file necessary -- GDK's own two answers were both 1.0 at 125%.

#include "include/gtk_helpers.h"

#ifdef G_OS_WIN32
#include <gdk/win32/gdkwin32.h>
#include <windows.h>
#endif

double scui_window_display_scale(GtkWidget *window) {
#ifdef G_OS_WIN32
    if (!GTK_IS_NATIVE(window)) {
        return 0.0;
    }

    // Realized only: before the window is shown there is no HWND to ask, and
    // there is no per-monitor answer either. 0 rather than a guessed 1.0, so
    // the caller can tell "not available" from "genuinely unscaled".
    // 僅限已 realize:視窗顯示之前既沒有 HWND 可問,也不存在「哪一台顯示器」的答案。回傳 0 而非
    // 猜一個 1.0,讓呼叫端能分辨「取不到」與「確實沒有縮放」。
    GdkSurface *surface = gtk_native_get_surface(GTK_NATIVE(window));
    if (surface == NULL) {
        return 0.0;
    }

    HWND handle = gdk_win32_surface_get_handle(surface);
    if (handle == NULL) {
        return 0.0;
    }

    // GetDpiForWindow, not GetDeviceCaps(LOGPIXELSX): the latter is a
    // process-wide legacy value that does not follow a window between monitors
    // of different scale, which is exactly the case #80 is about.
    //
    // It returns 0 on failure, and 96 when the process is DPI-unaware -- in
    // which case Windows is scaling the window for us and reporting the
    // unscaled DPI is the correct answer, not a missing one.
    //
    // 用 GetDpiForWindow 而非 GetDeviceCaps(LOGPIXELSX):後者是行程層級的舊值,不會跟著視窗在
    // 不同縮放的顯示器之間移動——而那正是 #80 所談的情境。
    //
    // 失敗時回傳 0;行程為 DPI-unaware 時回傳 96——此時是 Windows 代為縮放視窗,回報未縮放的 DPI
    // 才是正確答案,而不是一個缺失的答案。
    UINT dpi = GetDpiForWindow(handle);
    if (dpi == 0) {
        return 0.0;
    }
    return (double)dpi / 96.0;
#else
    // Not a fallback and not a gap: on Wayland and X11 the fraction GDK
    // reports IS the display's, so `gdk_surface_get_scale` already answers
    // this and the caller should keep using it. Only Win32 disagrees.
    //
    // 這不是退路、也不是缺口:在 Wayland 與 X11 上,GDK 回報的小數就是顯示器的,因此
    // `gdk_surface_get_scale` 已經回答了這個問題,呼叫端應繼續使用它。只有 Win32 不一致。
    (void)window;
    return 0.0;
#endif
}

char *scui_window_scale_diagnostics(GtkWidget *window) {
#ifdef G_OS_WIN32
    if (!GTK_IS_NATIVE(window)) {
        return g_strdup("not-native");
    }

    GdkSurface *surface = gtk_native_get_surface(GTK_NATIVE(window));
    HWND handle = surface ? gdk_win32_surface_get_handle(surface) : NULL;
    if (handle == NULL) {
        return g_strdup("no-hwnd");
    }

    // GetAwarenessFromDpiAwarenessContext returns the enum: 0 UNAWARE,
    // 1 SYSTEM_AWARE, 2 PER_MONITOR_AWARE. This is the value that decides
    // whether any of the calls below can follow a setting change at all --
    // Windows freezes the reported DPI for a process that is not per-monitor
    // aware, and sends WM_DPICHANGED only to windows that are.
    //
    // GetAwarenessFromDpiAwarenessContext 回傳那個 enum:0 UNAWARE、1 SYSTEM_AWARE、
    // 2 PER_MONITOR_AWARE。這個值決定了下面每一個呼叫**有沒有可能**跟上設定變更——Windows 會為
    // 非 per-monitor aware 的行程凍結其回報的 DPI,而 WM_DPICHANGED 也只送給 per-monitor aware
    // 的視窗。
    int awareness = (int)GetAwarenessFromDpiAwarenessContext(
        GetWindowDpiAwarenessContext(handle)
    );

    UINT windowDpi = GetDpiForWindow(handle);
    UINT systemDpi = GetDpiForSystem();

    // The physical mode against what this process is told the screen is. For a
    // virtualized process these differ, and their ratio is the scale Windows is
    // hiding -- which is the one number here that cannot be frozen by DPI
    // awareness, because EnumDisplaySettings reports the adapter's mode rather
    // than anything per-process.
    //
    // 實體顯示模式,對上「這個行程被告知螢幕有多大」。對被虛擬化的行程而言兩者不同,而其比值正是
    // Windows 藏起來的那個縮放——也是此處唯一**不可能**被 DPI awareness 凍結的數字,因為
    // EnumDisplaySettings 回報的是顯示卡的模式,而非任何 per-process 的東西。
    DEVMODEW mode;
    memset(&mode, 0, sizeof(mode));
    mode.dmSize = sizeof(mode);
    int haveMode = EnumDisplaySettingsW(NULL, ENUM_CURRENT_SETTINGS, &mode) ? 1 : 0;
    int virtualWidth = GetSystemMetrics(SM_CXSCREEN);

    return g_strdup_printf(
        "awareness=%d windowDpi=%u systemDpi=%u physicalWidth=%lu virtualWidth=%d",
        awareness,
        windowDpi,
        systemDpi,
        haveMode ? (unsigned long)mode.dmPelsWidth : 0UL,
        virtualWidth
    );
#else
    (void)window;
    return g_strdup("not-windows");
#endif
}
