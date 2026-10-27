# macOS: how action files are replayed (AppKitSynthesiser)

Written 2026-10-24 from Sources/InputEvent/AppKitSynthesiser.swift, mistakes.md
(#25, #28) and matrix_coverage/results.csv2 (mac rows).

## What

`-actionfile` on macOS goes through `AppKitSynthesiser`, for AppKitBackend and
for GtkBackend on macOS alike.

- **Default: in-process.** Events are built as NSEvents and posted with
  `NSApp.postEvent`, addressed to a window by number. No Accessibility grant is
  needed, the app need not be frontmost, and nothing leaks into other apps.
- **HID tap when trusted.** Where in-process events cannot reach, a `CGEvent`
  is posted through `.cghidEventTap`, guarded by `AXIsProcessTrusted()`; without
  the grant the row fails with a message.

## Where the HID tap is required

| Case | Why | Evidence |
| --- | --- | --- |
| NSOpenPanel / NSSavePanel | drawn by a separate service process; posted events never cross | P1, P18: Escape and Cancel ignored in every capture since 2026-09-01; fixed 2026-09-28 |
| GDK windows (GtkBackend) | GDK logs press and release, yet no GtkButton fires on a posted click | P84 on GTK 4.24.1, 2026-10-09 |
| Wheel, when trusted | `scrollWheel(with:)` on the hit view sent SwiftCrossUI ScrollViews the wrong way | P8, 2026-09-28 (outer list never moved since 2026-09-17) |
| Trackpad magnify/rotate | no public NSEvent gesture initialiser; a type-30 event is rejected ("unrecognized type is 30") | P65: magnify 1.500, rotate 0.524 rad, 2026-09-30 |

For GDK, wheel notches are posted one event per notch from a background queue
and the main queue is not drained, because GDK reads the event queue itself
(P21, P22, P72, 2026-10-16).

## Rules that were each a bug once

- **Wheel sign**: the file's `dy` is positive downwards, NSEvent's delta follows
  the finger. The fallback for views that ignore a posted wheel runs only after
  pumping the run loop 50 ms, and the target point is clamped (P57, 2026-09-17;
  before, sign and fallback cancelled to zero travel).
- **Command chords** are made from a HID-state CGEvent converted to an NSEvent
  and posted in-process: an `NSEvent.keyEvent` Shift-Command-Z redid nothing on a
  bare NSTextView (P94, 2026-10-14). No grant needed for this one.
- **Release where pressed**: mouse-up and held moves go to the window that had
  the mouse-down; a long press that opened a sheet otherwise left the main
  window's recogniser unfinished (P103, 0694323f, 2026-10-20).
- **Target window**: not a popover (it takes key) unless the row's origin is
  `popover`, whose events go to the popover's own window (P50, 2026-09-11); a
  titled key child window counts, which is how a GTK sheet becomes the target
  while a GTK popover does not (P49, 2026-10-21).
- **`currentWindowIdentity()`** returns `windowNumber`; the protocol default 0
  means "cannot tell", so geometry was never re-measured after a `focus` row
  (P60, 2026-09-09).
- **`move` warps the physical pointer** (since 2026-09-20), so `.cursor`,
  `NSEvent.mouseLocation` and `screencapture -C` see it. `click` does not warp.
- **Modifiers**: a release is built after the flag is cleared; the opposite
  order logged `MODIFIERS up shift=true` (mistakes.md #25, 2026-09-19).

## How to apply

- A pointer or click that "does nothing": photograph where it went first,
  `screencapture -C` during the row, and measure from that image. P72's cursor
  cost five days and ten eliminated candidates because the coordinates came from
  a superview-relative frame (mistakes.md #28, solved 2026-09-27).
- Clicks into a sheet's gesture recognizers were unreachable before 0694323f;
  `measure/real_click.swift` sends one real HID click to separate a tool fault
  from a component fault.
- Files measured on AppKit miss on GTK's taller layout; GTK versions are
  `-gtk4.actions` files (39 misses in the 2026-10-16 gtk4 sweep).

## Limits

- Real touch sequences are not synthesised on macOS.
- Slider drags: AppKit tracks a slider in its own modal loop, and posted moves
  produced one value (P61, 2026-09-10).

---

# macOS:動作檔如何重放(AppKitSynthesiser)

2026-10-24 依 Sources/InputEvent/AppKitSynthesiser.swift、mistakes.md(#25、#28)與 matrix_coverage/results.csv2
(mac 列)寫成。

## 是什麼

macOS 上的 `-actionfile` 經由 `AppKitSynthesiser`,AppKitBackend 與 macOS 上的 GtkBackend 都一樣。

- **預設：行程內。** 事件做成 NSEvent,以 `NSApp.postEvent` 送出，依視窗編號指定對象。不需要輔助使用權限,app 不必在最前面，
  也不會漏到其他 app。
- **授權時走 HID tap。** 行程內事件到不了的地方，以 `.cghidEventTap` 送出 `CGEvent`,由 `AXIsProcessTrusted()` 把關；沒有權限時
  該列會帶著訊息失敗。

## 必須走 HID tap 的情況

| 情況 | 原因 | 證據 |
| --- | --- | --- |
| NSOpenPanel / NSSavePanel | 由另一個服務行程繪製，送出的事件過不去 | P1、P18:自 2026-09-01 起每張擷圖裡 Escape 與 Cancel 都被忽略;2026-09-28 修正 |
| GDK 視窗(GtkBackend) | GDK 記下了按下與放開，但送出的點擊沒有讓任何 GtkButton 觸發 | P84,GTK 4.24.1,2026-10-09 |
| 滾輪(已授權時) | 對命中的 view 呼叫 `scrollWheel(with:)` 會讓 SwiftCrossUI 的 ScrollView 往反方向捲 | P8,2026-09-28(外層清單自 2026-09-17 起從未移動) |
| 觸控板縮放/旋轉 | NSEvent 沒有公開的手勢初始化方法;type 30 的事件被拒絕(「unrecognized type is 30」) | P65:縮放 1.500、旋轉 0.524 rad,2026-09-30 |

對 GDK,滾輪每一格送一個事件、從背景佇列送出，且不清空主佇列，因為 GDK 自己讀事件佇列(P21、P22、P72,2026-10-16)。

## 每一條都曾經是 bug 的規則

- **滾輪正負號**:檔案的 `dy` 向下為正,NSEvent 的位移跟著手指方向。針對忽略合成滾輪之 view 的退路，要先讓 run loop 跑 50 ms
  才判斷，目標點也要夾在範圍內(P57,2026-09-17;之前正負號與退路互相抵消，移動量為零)。
- **Command 組合鍵**由 HID 狀態的 CGEvent 轉成 NSEvent 後在行程內送出:用 `NSEvent.keyEvent` 做的 Shift-Command-Z 在單純的
  NSTextView 上沒有重做任何東西(P94,2026-10-14)。這一項不需要權限。
- **在哪按下就在哪放開**:mouse-up 與按住時的移動送往收到 mouse-down 的視窗；否則一次開出 sheet 的長按會讓主視窗的辨識器
  永遠不結束(P103,0694323f,2026-10-20)。
- **目標視窗**:不取 popover(它會成為 key),除非該列 origin 是 `popover`,那時事件送往 popover 自己的視窗(P50,2026-09-11);
  有標題的 key 子視窗算數，因此 GTK 的 sheet 會成為目標,GTK 的 popover 不會(P49,2026-10-21)。
- **`currentWindowIdentity()`** 回傳 `windowNumber`;協定預設的 0 代表「無法判斷」,於是 `focus` 列之後從不重新量測幾何
  (P60,2026-09-09)。
- **`move` 會移動實體指標**(自 2026-09-20),`.cursor`、`NSEvent.mouseLocation` 與 `screencapture -C` 才看得到。`click` 不移動。
- **修飾鍵**:放開事件要在清掉旗標之後才建立；反過來的順序會記下 `MODIFIERS up shift=true`(mistakes.md #25,2026-09-19)。

## 怎麼用

- 指標或點擊「沒反應」時，先拍下它去了哪裡：在該列執行期間 `screencapture -C`,從那張圖量座標。P72 的游標花了五天、排除十個
  候選，原因是座標取自相對於父 view 的 frame(mistakes.md #28,2026-09-27 解決)。
- 0694323f 之前，點進 sheet 裡的手勢辨識器到不了;`measure/real_click.swift` 送出一次真正的 HID 點擊，用來區分工具問題與元件問題。
- 在 AppKit 上量的檔案，在 GTK 較高的版面上會點偏;GTK 版是 `-gtk4.actions` 檔(2026-10-16 gtk4 sweep 偏了 39 處)。

## 限制

- macOS 上不合成真正的觸控序列。
- Slider 拖曳:AppKit 以自己的 modal loop 追蹤 slider,送出的移動只產生一個值(P61,2026-09-10)。
