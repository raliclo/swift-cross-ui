# Synthetic touch on Windows: touch_gesture and its hold mode

Written 2026-10-24 from testapp/touch_gesture.c, testapp/touch_gesture.zsh,
commit a422c0b3 (2026-10-23), and results.csv2 (windows: P65, P38, P11
2026-09-17; P88 2026-10-23).

## What

`touch_gesture.zsh` builds `touch_gesture.c` (clang `-municode`, `-luser32`)
into `testapp/helper/bin` and injects touch through
`CreateSyntheticPointerDevice(PT_TOUCH)` and `InjectSyntheticPointerInput`. No
touch hardware is needed. Coordinates are physical pixels relative to the
window's `GetWindowRect` frame.

```
touch_gesture.exe <title> pinch  <cx> <cy> <startGap> <endGap> [steps] [ms]
touch_gesture.exe <title> rotate ...                  (two contacts, P65)
touch_gesture.exe <title> drag   <x0> <y0> <x1> <y1>  [steps] [ms]
touch_gesture.exe <title> hold   <x0> <y0> <x1> <y1> <holdMs> [steps] [ms]
```

It is a separate tool, not an action-file verb, because `InputAction` is
switched over exhaustively by every synthesiser and the AppKit one cannot be
compiled on Windows.

## The hold mode

One contact goes down, rests for `holdMs` sending updates, then moves and lifts.
It drives the touch-hold hover of `onContinuousHover`: a finger resting 0.5 s
within 10 DIPs starts hovering. Results on P88 (2026-10-23): quick drag 0 hovers;
0.8 s hold then move 31 (WinUI) / 30 (GTK) hovers ending on the lift; 0.3 s hold 0.

**The hold is timed by `GetTickCount64`, not by counting sleeps.** `Sleep(16)`
takes about 31 ms, so counting sleeps turned a 300 ms hold into ~500 ms and
produced a false hover.

## Root cause that can come back

Until 2026-09-17 `drag` read its arguments like `rotate`, which has a fifth
number, so `[steps]` came from the `[ms]` slot: a tap became a ~500 ms press.
WebView2 took it as a long press (P38 links did not follow); XAML's ComboBox
accepted it, which hid the bug. The tool prints its step count; check it.

## How to apply

- Before a touch run: minimise other windows, park the cursor away (e.g. 5,5),
  and confirm the target is in front with a desktop capture.
- Injection needs a live session. First check reachability with no app code: a
  one-finger drag on the title bar must move the window (P65, 2026-09-17).
- GTK receives the touch and Windows' emulated mouse for it; see
  [gtk-input.md](gtk-input.md).

---

# Windows 上的合成觸控:touch_gesture 與其 hold 模式

2026-10-24 依 testapp/touch_gesture.c、testapp/touch_gesture.zsh、a422c0b3(2026-10-23),以及 results.csv2
(windows:P65、P38、P11 於 2026-09-17;P88 於 2026-10-23)寫成。

## 內容

`touch_gesture.zsh` 把 `touch_gesture.c`(clang `-municode`、`-luser32`)建置到 `testapp/helper/bin`,透過
`CreateSyntheticPointerDevice(PT_TOUCH)` 與 `InjectSyntheticPointerInput` 注入觸控。不需要觸控硬體。座標是相對於
視窗 `GetWindowRect` 外框的實體像素。用法見上方英文區塊。

它是獨立工具而非動作檔動詞，因為每個合成器都對 `InputAction` 做窮舉 switch,而 AppKit 的那個無法在 Windows 上編譯。

## hold 模式

一個接觸點按下，原地停留 `holdMs` 並持續送出更新，再移動並抬起。它驅動 `onContinuousHover` 的觸控按住 hover:
手指在 10 DIP 內停留 0.5 秒後開始 hover。P88 的結果(2026-10-23):快速拖曳 0 次 hover;按住 0.8 秒再移動 31 次
(WinUI)/ 30 次(GTK),於抬起時結束;按住 0.3 秒 0 次。

**按住的時間以 `GetTickCount64` 計時，不靠數 sleep 次數。** `Sleep(16)` 實際約 31 ms,數 sleep 會把 300 ms 的按住
變成約 500 ms,產生假的 hover。

## 可能再發生的根本原因

2026-09-17 之前,`drag` 依 `rotate`(多一個第五個數字)的方式讀引數，所以 `[steps]` 取自 `[ms]` 的位置：一次輕點
變成約 500 ms 的按壓。WebView2 把它當成長按(P38 的連結沒有跟進);XAML 的 ComboBox 接受長按，因而掩蓋了這個錯誤。
工具會印出步數；要檢查。

## 如何運用

- 觸控執行前：把其他視窗最小化、把游標移開(例如 5,5),並以桌面擷取確認目標在最前面。
- 注入需要活著的工作階段。先做不涉及 app 程式碼的可達性檢查：在標題列上單指拖曳，視窗必須移動(P65,2026-09-17)。
- GTK 會收到觸控，也會收到 Windows 為它模擬的滑鼠；見 [gtk-input.md](gtk-input.md)。
