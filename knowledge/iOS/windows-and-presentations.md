# Windows and presentations on iPhone

What a UIKitBackend window, split view, popover, sheet and alert do on a phone,
where several desktop assumptions fail. Checked against
UIKitBackend+WindowClosing.swift, +SplitView.swift, +Popover.swift and
results.csv2 on 2026-10-24. iPad differences are in [ipad.md](ipad.md).

## Windows

- On iPhone `supportsMultipleScenes` is false: a second window is an extra
  `UIWindow` over the main one, not a scene.
- **The app's only window cannot be closed.** `requestSceneSessionDestruction`
  answers "Invalid attempt ... from an unsupported device" and the window stays
  (iOS 27 simulator, P75, 2026-09-30). `close(window:)` leaves it open, logs the
  notice, and does not run the close handler, which would release a window that
  is still on screen. SwiftUI's `dismissWindow` has no effect there either.
  Another window still showing is hidden instead.
- No programmatic window size on iOS (the iOS geometry preferences take only
  orientations); `isWindowProgrammaticallyResizable` is false.
- `preferredColorScheme` applies to the whole window through
  `overrideUserInterfaceStyle`, and the system scheme is read from the window
  scene (b46ae88a, 2026-10-06, P15-DARK).

## NavigationSplitView

A compact-width `UISplitViewController` collapses to a navigation stack
whatever `preferredDisplayMode` says. On a phone `PhoneSplitWidget` lays the two
panes out side by side, using `sidebarWidth(ofSplitView:)`. Before, a
`precondition` killed P13 within a second of launch with no app log line
(2026-09-02).

## Popovers

- On a compact-width iPhone a popover becomes a sheet unless the presentation
  delegate refuses; UIKitBackend refuses, so a popover stays a popover
  (e098fc7d, 2026-09-17). On iPad P50 shows a real popover.
- `permittedArrowDirections` names the side of the ARROW, the opposite of the
  `Edge` asked for (`.top` -> `.down`).
- When the panel does not fit on the requested side (safe area plus 13 pt for
  the arrow), it moves to the other side instead of shrinking.

## Sheets, covers, alerts

- `sheet(onDismiss:)` runs on programmatic dismissal too, as in SwiftUI
  (8a6f2aa8, 2026-10-20; P49: "sheet dismissals: 2" with the change, 1
  without).
- `fullScreenCover` presents as `.fullScreen` on iPhone and iPad (2026-10-21).
- Alerts are stacked; before a162d26d (2026-09-28) every alert after the first
  was dropped.

## Defaults that once crashed

On 2026-09-02, six of 46 apps (P12, P13, P16, P21, P23, P26) died on launch at
`createToggle() not implemented`: only the switch style existed. The
button-style `Toggle` is now a `UIButton` that flips `isSelected` itself.
UIKit's default toggle style is the switch.

---

# iPhone 上的視窗與呈現方式

UIKitBackend 的視窗、分割 view、popover、sheet 與警示在手機上的行為，這裡有好幾個桌面假設不成立。2026-10-24 對照
UIKitBackend+WindowClosing.swift、+SplitView.swift、+Popover.swift 與 results.csv2 確認。iPad 的差異見 [ipad.md](ipad.md)。

## 視窗

- iPhone 上 `supportsMultipleScenes` 為 false:第二個視窗是蓋在主視窗上的另一個 `UIWindow`,不是 scene。
- **app 唯一的視窗無法關閉。** `requestSceneSessionDestruction` 回應「Invalid attempt ... from an unsupported device」,
  視窗留著(iOS 27 模擬器，P75,2026-09-30)。`close(window:)` 讓它保持開啟、記錄提示，且不執行關閉 handler,因為那會釋放
  一個仍在畫面上的視窗。SwiftUI 的 `dismissWindow` 在那裡同樣沒有效果。若還有其他視窗顯示中，則改為隱藏該視窗。
- iOS 上無法以程式設定視窗大小(iOS 的幾何偏好只接受方向);`isWindowProgrammaticallyResizable` 為 false。
- `preferredColorScheme` 透過 `overrideUserInterfaceStyle` 套用到整個視窗，系統配色從 window scene 讀取
  (b46ae88a,2026-10-06,P15-DARK)。

## NavigationSplitView

窄寬度的 `UISplitViewController` 不論 `preferredDisplayMode` 為何都會收合成導覽堆疊。在手機上由 `PhoneSplitWidget` 以
`sidebarWidth(ofSplitView:)` 把兩個窗格並排。之前一個 `precondition` 讓 P13 在啟動一秒內結束，而且沒有任何 app 日誌
(2026-09-02)。

## Popover

- 在窄寬度的 iPhone 上，除非呈現 delegate 拒絕,popover 會變成 sheet;UIKitBackend 會拒絕，所以 popover 仍是 popover
  (e098fc7d,2026-09-17)。iPad 上 P50 顯示的是真正的 popover。
- `permittedArrowDirections` 指的是**箭頭**的那一側，與要求的 `Edge` 相反(`.top` -> `.down`)。
- 面板在要求的那一側放不下時(安全區域加上箭頭的 13 點),會改放到另一側，而不是縮小。

## Sheet、cover、警示

- `sheet(onDismiss:)` 在以程式關閉時也會執行，與 SwiftUI 相同(8a6f2aa8,2026-10-20;P49:有此修改時「sheet dismissals: 2」,
  沒有時 1)。
- `fullScreenCover` 在 iPhone 與 iPad 上都以 `.fullScreen` 呈現(2026-10-21)。
- 警示會堆疊;a162d26d(2026-09-28)之前，第一個之後的每個警示都被丟掉。

## 曾經造成當機的預設

2026-09-02 時 46 支 app 中有 6 支(P12、P13、P16、P21、P23、P26)在啟動時死於 `createToggle() not implemented`:當時只有
開關樣式。按鈕樣式的 `Toggle` 現在是一個自己切換 `isSelected` 的 `UIButton`。UIKit 預設的 toggle 樣式是開關。
