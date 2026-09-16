// Injects a two-finger touch gesture -- pinch or rotate -- into a named window.
//
//   touch_gesture.exe <title> pinch  <cx> <cy> <startGap> <endGap>        [steps] [ms]
//   touch_gesture.exe <title> rotate <cx> <cy> <radius>  <startDeg> <endDeg> [steps] [ms]
//   touch_gesture.exe <title> drag   <x0> <y0> <x1> <y1>                   [steps] [ms]
//
// `drag` is ONE contact. It exists as the reachability control: if a one-finger
// touch drag does not move WinUIBackend's drag target either, the problem is
// upstream of magnify and rotate -- touch is not reaching the app at all -- and
// debugging the two-finger path first would be debugging the wrong thing.
// `drag` 只有**一個**接觸點。它是可達性的對照組:若單指觸控拖曳連 WinUIBackend 的拖曳目標都移不動,
// 問題就在縮放與旋轉的上游——觸控根本沒進到 app——那時先去除錯兩指路徑,就是在除錯錯的東西。
//
// <title> is a substring of a visible top-level window's title. <cx> <cy> are
// PHYSICAL pixels relative to that window's frame (GetWindowRect), the same
// origin as `frame` in testapp/actions/*.csv. A pinch moves two contacts
// apart along the horizontal axis from <startGap> to <endGap> pixels; a rotate
// keeps two contacts opposite each other on a circle of <radius> and turns
// them from <startDeg> to <endDeg>. Defaults: 20 steps, 16 ms apart.
//
// WHY THIS IS NOT AN ACTION-FILE VERB. InputEvent's `InputAction` is switched
// over exhaustively by three synthesisers, one of which (AppKit) cannot be
// compiled on this machine. A new case would compile here and break the Mac
// build, which has already happened twice in this tree in both directions. So
// two-finger touch lives in its own tool until the other machine can add the
// matching cases.
//
// WHY TOUCH AT ALL. #32's magnify and rotate need two contacts. WinUIBackend
// reads them from `ManipulationDelta`, which a mouse never raises; GtkBackend
// uses GtkGestureZoom and GtkGestureRotate, which need two touch points. A
// synthetic pointer device (Windows 10 1809+) needs no touch hardware.
//
// Every injection's result is printed, success included. A refused injection
// under remote desktop looks exactly like a gesture the app ignored, and only
// the return value tells them apart.
//
// 向指定視窗注入兩指觸控手勢——捏合或旋轉。
//
// <title> 是某個可見頂層視窗標題的子字串。<cx> <cy> 是相對於該視窗外框(GetWindowRect)的**實體**
// 像素,與 testapp/actions/*.csv 中的 `frame` 同一個原點。
//
// **為何不是動作檔的動詞。** InputEvent 的 `InputAction` 被三個 synthesiser 以窮舉 switch 處理,
// 其中 AppKit 那個在本機無法編譯。新增一個 case 會在這裡編過、在 Mac 上編不過——本樹已發生過兩次,
// 雙向各一次。因此兩指觸控放在獨立工具裡,直到另一台機器能補上對應的 case。
//
// **為何非觸控不可。** #32 的縮放與旋轉需要兩個接觸點。WinUIBackend 從 `ManipulationDelta` 讀取,
// 滑鼠從不觸發它;GtkBackend 用 GtkGestureZoom 與 GtkGestureRotate,需要兩個觸控點。合成指標裝置
// (Windows 10 1809 起)不需要觸控硬體。
//
// **每一次注入的結果都會印出,成功也印。** 遠端桌面下被拒絕的注入,看起來與「app 忽略了手勢」
// 一模一樣,只有回傳值分得出來。

#define WINVER 0x0A00
#define _WIN32_WINNT 0x0A00
#define NTDDI_VERSION 0x0A000006
#include <windows.h>

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

typedef struct {
    const wchar_t *needle;
    HWND found;
} FindState;

static BOOL CALLBACK find_window(HWND hwnd, LPARAM lparam) {
    FindState *state = (FindState *)lparam;
    if (!IsWindowVisible(hwnd)) {
        return TRUE;
    }
    wchar_t title[512];
    if (GetWindowTextW(hwnd, title, 512) <= 0) {
        return TRUE;
    }
    if (wcsstr(title, state->needle) != NULL) {
        state->found = hwnd;
        return FALSE;
    }
    return TRUE;
}

static void fill_contact(POINTER_TYPE_INFO *info, UINT32 id, LONG x, LONG y, POINTER_FLAGS flags) {
    memset(info, 0, sizeof(*info));
    info->type = PT_TOUCH;
    POINTER_TOUCH_INFO *touch = &info->touchInfo;
    touch->pointerInfo.pointerType = PT_TOUCH;
    touch->pointerInfo.pointerId = id;
    touch->pointerInfo.ptPixelLocation.x = x;
    touch->pointerInfo.ptPixelLocation.y = y;
    touch->pointerInfo.pointerFlags = flags;
    touch->touchFlags = TOUCH_FLAG_NONE;
    touch->touchMask = TOUCH_MASK_CONTACTAREA | TOUCH_MASK_ORIENTATION | TOUCH_MASK_PRESSURE;
    touch->orientation = 90;
    touch->pressure = 32000;
    touch->rcContact.left = x - 2;
    touch->rcContact.right = x + 2;
    touch->rcContact.top = y - 2;
    touch->rcContact.bottom = y + 2;
}

static int usage(void) {
    fprintf(stderr,
        "usage: touch_gesture <title> pinch  <cx> <cy> <startGap> <endGap> [steps] [ms]\n"
        "       touch_gesture <title> rotate <cx> <cy> <radius> <startDeg> <endDeg> [steps] [ms]\n"
        "       touch_gesture <title> drag   <x0> <y0> <x1> <y1> [steps] [ms]\n"
        "coordinates are physical pixels relative to the window frame\n");
    return 2;
}

int wmain(int argc, wchar_t **argv) {
    if (argc < 2 || wcscmp(argv[1], L"-h") == 0 || wcscmp(argv[1], L"--help") == 0) {
        return usage();
    }
    if (argc < 7) {
        return usage();
    }

    const wchar_t *title = argv[1];
    const wchar_t *mode = argv[2];
    int isPinch = wcscmp(mode, L"pinch") == 0;
    int isRotate = wcscmp(mode, L"rotate") == 0;
    int isDrag = wcscmp(mode, L"drag") == 0;
    if (!isPinch && !isRotate && !isDrag) {
        return usage();
    }
    if ((isRotate || isDrag) && argc < 8) {
        return usage();
    }

    double cx = _wtof(argv[3]);
    double cy = _wtof(argv[4]);
    double a = _wtof(argv[5]);
    double b = _wtof(argv[6]);
    double c = (isRotate || isDrag) ? _wtof(argv[7]) : 0;
    int nextArg = (isRotate || isDrag) ? 8 : 7;
    UINT32 contactCount = isDrag ? 1 : 2;
    int steps = argc > nextArg ? _wtoi(argv[nextArg]) : 20;
    int ms = argc > nextArg + 1 ? _wtoi(argv[nextArg + 1]) : 16;
    if (steps < 1) {
        steps = 1;
    }

    // Per-monitor aware, so GetWindowRect and the injected coordinates are both
    // physical pixels. Without it a DPI-unaware tool is told virtualised
    // coordinates at 125% and every contact lands 20% short.
    // 設為 per-monitor aware,使 GetWindowRect 與注入座標都是實體像素。若不設,在 125% 下一個
    // DPI-unaware 的工具拿到的是虛擬化座標,每個接觸點都會短少 20%。
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);

    FindState state = {title, NULL};
    EnumWindows(find_window, (LPARAM)&state);
    if (state.found == NULL) {
        fwprintf(stderr, L"touch_gesture: no visible window title contains \"%ls\"\n", title);
        return 3;
    }
    RECT frame;
    GetWindowRect(state.found, &frame);
    double ox = frame.left + cx;
    double oy = frame.top + cy;
    printf("window frame %ld,%ld %ldx%ld; centre on screen %.0f,%.0f\n",
        frame.left, frame.top, frame.right - frame.left, frame.bottom - frame.top, ox, oy);

    HSYNTHETICPOINTERDEVICE device =
        CreateSyntheticPointerDevice(PT_TOUCH, contactCount, POINTER_FEEDBACK_DEFAULT);
    if (device == NULL) {
        printf("CreateSyntheticPointerDevice failed, error %lu\n", GetLastError());
        return 4;
    }

    const double pi = 3.14159265358979323846;
    int failures = 0;
    POINTER_TYPE_INFO contacts[2];

    for (int step = 0; step <= steps + 1; step++) {
        // step 0 = down at the start position, 1..steps = moves, steps+1 = up
        // at the end position.
        // step 0 = 在起點按下,1..steps = 移動,steps+1 = 在終點抬起。
        int moveIndex = step == 0 ? 0 : (step > steps ? steps : step);
        double t = (double)moveIndex / steps;
        double x0, y0, x1, y1;
        if (isDrag) {
            // cx,cy is the start and a,b... is not: for a drag the four numbers
            // are x0 y0 x1 y1, read positionally as cx cy a b.
            // 拖曳時四個數字依序是 x0 y0 x1 y1,依位置讀成 cx cy a b。
            x0 = frame.left + cx + (a - cx) * t;
            y0 = frame.top + cy + (b - cy) * t;
            x1 = x0;
            y1 = y0;
        } else if (isPinch) {
            double gap = a + (b - a) * t;
            x0 = ox - gap / 2;
            x1 = ox + gap / 2;
            y0 = oy;
            y1 = oy;
        } else {
            double radians = (b + (c - b) * t) * pi / 180.0;
            x0 = ox + a * cos(radians);
            y0 = oy + a * sin(radians);
            x1 = ox - a * cos(radians);
            y1 = oy - a * sin(radians);
        }

        POINTER_FLAGS flags;
        const char *phase;
        if (step == 0) {
            flags = POINTER_FLAG_DOWN | POINTER_FLAG_INRANGE | POINTER_FLAG_INCONTACT;
            phase = "down";
        } else if (step > steps) {
            flags = POINTER_FLAG_UP;
            phase = "up";
        } else {
            flags = POINTER_FLAG_UPDATE | POINTER_FLAG_INRANGE | POINTER_FLAG_INCONTACT;
            phase = "move";
        }

        fill_contact(&contacts[0], 0, (LONG)lround(x0), (LONG)lround(y0), flags);
        fill_contact(&contacts[1], 1, (LONG)lround(x1), (LONG)lround(y1), flags);
        BOOL ok = InjectSyntheticPointerInput(device, contacts, contactCount);
        DWORD error = ok ? 0 : GetLastError();
        if (!ok) {
            failures++;
        }
        printf("step %d %s (%ld,%ld) (%ld,%ld) -> %s%s\n", step, phase,
            (long)lround(x0), (long)lround(y0), (long)lround(x1), (long)lround(y1),
            ok ? "ok" : "FAILED error ", ok ? "" : "");
        if (!ok) {
            printf("  error %lu\n", error);
        }
        Sleep(ms);
    }

    DestroySyntheticPointerDevice(device);
    printf("%s: %d injection(s) failed\n", failures == 0 ? "done" : "FAILED", failures);
    return failures == 0 ? 0 : 1;
}
