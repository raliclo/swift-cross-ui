// uia_rects.c -- list every element in the UIA control view of the window whose
// title contains argv[1], with its type, name and centre RELATIVE TO THE
// WINDOW'S GetWindowRect origin: the `origin=frame` coordinate an action file
// uses. Built on demand by measure_win.zsh beside it.
//
// uia_rects.c -- 列出標題含 argv[1] 之視窗在 UIA control view 中的每個元素，附上類型、名稱，以及
// **相對於視窗 GetWindowRect 原點**的中心點：也就是動作檔 `origin=frame` 用的座標。由同目錄的
// measure_win.zsh 按需建置。
//
// A TreeWalker over the control view rather than FindAll: FindAll over a WinUI
// island intermittently returned only the seven frame elements (2026-10-07).
// 用 control view 的 TreeWalker 而非 FindAll:對 WinUI island 用 FindAll 時，偶爾只回傳視窗框的七個元素
// (2026-10-07)。
#define COBJMACROS
#include <windows.h>
#include <ole2.h>
#include <UIAutomationClient.h>
#include <stdio.h>
#include <wchar.h>

typedef struct { const wchar_t *needle; HWND found; } FindState;

static BOOL CALLBACK find_window(HWND hwnd, LPARAM lparam) {
    FindState *s = (FindState *)lparam;
    wchar_t t[512];
    if (!IsWindowVisible(hwnd)) return TRUE;
    GetWindowTextW(hwnd, t, 512);
    if (wcsstr(t, s->needle)) { s->found = hwnd; return FALSE; }
    return TRUE;
}

int wmain(int argc, wchar_t **argv) {
    if (argc < 2) { wprintf(L"usage: uia_rects <title substring>\n"); return 2; }
    // Physical pixels for both the window rect and UIA's rects; without this the
    // window rect is DPI-virtualised and UIA's is not.
    // 視窗矩形與 UIA 矩形都取實體像素；少了這行，視窗矩形會被 DPI 虛擬化,UIA 的則不會。
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    FindState st = {argv[1], NULL};
    EnumWindows(find_window, (LPARAM)&st);
    if (!st.found) { wprintf(L"no window\n"); return 3; }
    RECT wr;
    GetWindowRect(st.found, &wr);
    // Action files are in DIPs: Win32Synthesiser divides by the window's DPI
    // over 96 before it places the pointer. So every number below is divided
    // by the same scale; at 125% a raw pixel would aim 25% off.
    // 動作檔以 DIP 為單位:Win32Synthesiser 放指標前會先除以視窗 DPI / 96。所以下面每個數字都除以同一個比例；
    // 在 125% 下直接用像素會偏 25%。
    double scale = GetDpiForWindow(st.found) / 96.0;
    if (scale <= 0) scale = 1.0;
    wprintf(L"window %ldx%ld at %ld,%ld (pixels); scale %.2f, so the centres below are DIPs\n",
        wr.right - wr.left, wr.bottom - wr.top, wr.left, wr.top, scale);
    CoInitializeEx(NULL, COINIT_MULTITHREADED);
    IUIAutomation *a = NULL;
    CoCreateInstance(&CLSID_CUIAutomation, NULL, CLSCTX_INPROC_SERVER, &IID_IUIAutomation, (void **)&a);
    if (!a) { wprintf(L"no UI Automation\n"); return 4; }
    IUIAutomationElement *root = NULL;
    IUIAutomation_ElementFromHandle(a, st.found, &root);
    IUIAutomationTreeWalker *walker = NULL;
    IUIAutomation_get_ControlViewWalker(a, &walker);
    IUIAutomationElement *stack[4096];
    int depth[4096];
    int top = 0;
    stack[top] = root;
    depth[top++] = 0;
    while (top > 0) {
        top--;
        IUIAutomationElement *e = stack[top];
        int d = depth[top];
        BSTR name = NULL, type = NULL;
        RECT r;
        IUIAutomationElement_get_CurrentName(e, &name);
        IUIAutomationElement_get_CurrentLocalizedControlType(e, &type);
        IUIAutomationElement_get_CurrentBoundingRectangle(e, &r);
        wprintf(L"%*ls%ls '%.60ls' centre=%ld,%ld size=%ldx%ld\n", d * 2, L"",
            type ? type : L"?", name ? name : L"",
            (long)(((r.left + r.right) / 2 - wr.left) / scale + 0.5),
            (long)(((r.top + r.bottom) / 2 - wr.top) / scale + 0.5),
            (long)((r.right - r.left) / scale + 0.5), (long)((r.bottom - r.top) / scale + 0.5));
        SysFreeString(name);
        SysFreeString(type);
        // Children pushed in reverse so they print in order.
        // 子元素反向推入，使其依序印出。
        IUIAutomationElement *kids[512];
        int nk = 0;
        IUIAutomationElement *child = NULL;
        IUIAutomationTreeWalker_GetFirstChildElement(walker, e, &child);
        while (child && nk < 512) {
            kids[nk++] = child;
            IUIAutomationElement *next = NULL;
            IUIAutomationTreeWalker_GetNextSiblingElement(walker, child, &next);
            child = next;
        }
        for (int i = nk - 1; i >= 0 && top < 4096; i--) {
            stack[top] = kids[i];
            depth[top++] = d + 1;
        }
    }
    return 0;
}
