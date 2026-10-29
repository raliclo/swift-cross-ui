// Hide Others and Show All for WinUIBackend: the other applications' windows
// minimised as Win+Home minimises them, and restored by Show All.
//
// The same rules as GtkBackend's gtk_hide_others.c, which GtkBackend uses on
// Windows; the two backends are separate targets and share no C code.
//
// WinUIBackend 的 Hide Others 與 Show All:把其他 app 的視窗像 Win+Home 一樣最小化，再由 Show All 還原。
//
// 規則與 GtkBackend 在 Windows 上所用的 gtk_hide_others.c 相同；兩個 backend 是各自的 target,不共用 C 程式碼。

#ifdef _WIN32

#include "WinUIInterop.h"
#include <vector>

namespace {

// The windows Hide Others minimised, so that Show All restores those and no
// others: a window that was already minimised stays where it was.
// Hide Others 所最小化的視窗，讓 Show All 只還原這些：原本就已最小化的視窗維持原狀。
std::vector<HWND> hiddenWindows;

// DWMWA_CLOAKED, spelled out because the constant is version-gated in the SDK
// headers; dwmapi is opened at run time so this target's link line is unchanged.
// DWMWA_CLOAKED,因為 SDK 標頭中此常數有版本條件而寫成字面值；dwmapi 於執行時開啟，本 target 的連結設定不變。
constexpr DWORD kCloaked = 14;
using GetWindowAttribute = HRESULT(WINAPI *)(HWND, DWORD, PVOID, DWORD);

bool isCloaked(HWND window) {
    static GetWindowAttribute get = [] {
        HMODULE dwm = LoadLibraryW(L"dwmapi.dll");
        return dwm ? reinterpret_cast<GetWindowAttribute>(GetProcAddress(dwm, "DwmGetWindowAttribute"))
                   : nullptr;
    }();
    DWORD cloaked = 0;
    return get && SUCCEEDED(get(window, kCloaked, &cloaked, sizeof cloaked)) && cloaked != 0;
}

// Whether `window` is another application's window that Win+Home would
// minimise: visible, top-level, not owned, not a tool window, not cloaked (a
// suspended UWP app or a window on another virtual desktop), not the desktop or
// the taskbar, and with a minimise box.
// `window` 是否是 Win+Home 會最小化的「其他應用程式的視窗」:可見、頂層、沒有擁有者、不是工具視窗、沒有被 cloak
// (暫停中的 UWP app 或位於其他虛擬桌面的視窗)、不是桌面或工作列，而且有最小化鈕。
bool isOtherApplicationWindow(HWND window) {
    DWORD process = 0;
    GetWindowThreadProcessId(window, &process);
    if (process == GetCurrentProcessId()) return false;
    if (!IsWindowVisible(window) || IsIconic(window) || GetWindow(window, GW_OWNER)) return false;
    LONG_PTR extended = GetWindowLongPtrW(window, GWL_EXSTYLE);
    LONG_PTR style = GetWindowLongPtrW(window, GWL_STYLE);
    if ((extended & WS_EX_TOOLWINDOW) != 0 || (style & WS_MINIMIZEBOX) == 0) return false;
    wchar_t name[64];
    if (GetClassNameW(window, name, 64) > 0) {
        for (const wchar_t *shell : {L"Progman", L"WorkerW", L"Shell_TrayWnd", L"Shell_SecondaryTrayWnd"}) {
            if (lstrcmpW(name, shell) == 0) return false;
        }
    }
    return !isCloaked(window);
}

BOOL CALLBACK hideOne(HWND window, LPARAM count) {
    if (!isOtherApplicationWindow(window)) return TRUE;
    // Asynchronous, so a hung application cannot stall this one, and without
    // activation, so the focus stays on the window the command came from.
    // 非同步，讓沒有回應的 app 拖不住這一個；不啟用，讓焦點留在下指令的視窗上。
    if (ShowWindowAsync(window, SW_SHOWMINNOACTIVE)) {
        bool known = false;
        for (HWND seen : hiddenWindows) known = known || seen == window;
        if (!known) hiddenWindows.push_back(window);
        *reinterpret_cast<int *>(count) += 1;
    }
    return TRUE;
}

}  // namespace

extern "C" int scui_win32_hide_other_applications(void) {
    int count = 0;
    EnumWindows(hideOne, reinterpret_cast<LPARAM>(&count));
    return count;
}

extern "C" int scui_win32_show_hidden_applications(void) {
    int count = 0;
    for (HWND window : hiddenWindows) {
        // Only what is still there and still minimised: a window restored or
        // closed in the meantime is left alone.
        // 只處理仍存在且仍最小化的視窗：期間已被還原或關閉的視窗不去動它。
        if (IsWindow(window) && IsIconic(window) && ShowWindowAsync(window, SW_RESTORE)) count++;
    }
    hiddenWindows.clear();
    return count;
}

#endif  // _WIN32
