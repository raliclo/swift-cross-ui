# macOS: window sizes, saved frames and display scale

Written 2026-10-24 from testapp/window_sizes_mac.zsh,
testapp/test_support/test_common.zsh (run_macos),
testapp/test_support/scale_change_mac.zsh and matrix_coverage/results.csv2
(mac/appkit P5, P27, P46, P50, 2026-09-17/18; P42, 2026-09-30).

## What

- `SCUI_DEBUG_WINDOW_SIZE=1` makes every window update print window,
  proposed and minimum size. `WindowReference` opens a window at
  `max(minimumWindowSize, proposedWindowSize)`, clamped by a maximum when the
  scene sets one; the minimum is the content laid out at a `.zero` proposal.
  Binaries built before 2026-09-17 print nothing (`minimum -`).
- `zsh testapp/window_sizes_mac.zsh [P5 P36 ...] [--csv out.csv2]` prints those
  numbers per built app and flags windows set by their minimum. It deletes the
  app's defaults domain before each launch.

## Why: AppKit restores saved frames

AppKitBackend calls `setFrameAutosaveName`, so a saved `NSWindow Frame <id>`
wins over `.defaultSize`, as in SwiftUI. Before 2026-09-01 every test app ran
as one bundle id and shared one domain, keyed on the root view type
(`TupleView1<HotReloadableView>-0`), so a window took the size of whichever app
was resized last: P28 opened 680x448 bare and 1076x907 in the bundle. Now each
Pn has its own bundle id, and `run_macos` drops the saved frames before every
launch (4b268536, 2026-10-22: P41 had opened 1202x799 against GTK's 1340x888,
P92 still held a 460-pt frame). `SCUI_KEEP_WINDOW_FRAME=1` keeps them, to test
restoration.

## Evidence

- 2026-09-18 sweep of 72 apps
  (`testapp/measurements/window-sizes-appkit-sweep-20260918.csv2`): two
  flagged. P5's width is set by its minimum (the Button change); P27's
  `.defaultSize` height 520 was under its 539 minimum and SwiftCrossUI warned
  "vertical stack ran out of space" -- raised to 620. Eight apps with a zero
  minimum height (P21 P22 P46 P47 P48 P51 P52 P54) were forced to 600x300:
  content clipped, nothing squeezed, no warnings. Not a defect.
- P50 root cause (mac/appkit P50, 2026-09-18): `Button.computeLayout` proposed
  its height minus padding to the label, so at a zero proposal the button
  shrank to its padding and the window opened ~150 pt short with buttons as
  three-pixel bars. Fix in shared code: `childProposal.height = nil`. The
  `.frame(minHeight: 1000)` workaround was removed.
- AppKit will not make a window smaller than its content minimum. A 393-pt
  "phone width" capture of P43 was a crop of a 568-pt window
  (`screencapture -R`); System Events read back 568x700 (mistakes.md,
  2026-09-03). **When a capture is evidence for a size, read the size back from
  the window.**

## Display scale change

No synthesised input changes a display's scale. `zsh
testapp/test_support/scale_change_mac.zsh` compiles `vdisplay.m`, a HiDPI
`CGVirtualDisplay` (private CoreGraphics classes, as DeskPad and
BetterDisplay use). On a Mac whose screen is a headless virtual display, it
becomes the only display, so every window goes to 2x and back when it exits.
P42 logged scale 1.0 -> 2.0 -> 1.0; the control run only 1.0 (2026-09-30). It
changes the whole screen, so it runs only under the harness's ui-lock
(test-p42).

## Limits

- On a Mac with a physical display, whether the virtual display takes over
  the same way is not recorded.

---

# macOS:視窗尺寸、儲存的視窗框與顯示縮放

2026-10-24 依 testapp/window_sizes_mac.zsh、test_common.zsh(run_macos)、scale_change_mac.zsh 與
matrix_coverage/results.csv2(mac/appkit P5、P27、P46、P50,2026-09-17/18;P42,2026-09-30)寫成。

## 內容

- `SCUI_DEBUG_WINDOW_SIZE=1` 讓每次視窗更新印出視窗、提議與最小尺寸。`WindowReference` 以
  `max(minimumWindowSize, proposedWindowSize)` 開視窗,scene 設了最大值時再夾住；最小值是內容在 `.zero` 提議下的排版結果。
  2026-09-17 之前建置的執行檔什麼都不印(`minimum -`)。
- `zsh testapp/window_sizes_mac.zsh [P5 P36 ...] [--csv out.csv2]` 逐支印出這些數字，並標出被最小值決定的視窗。每次啟動前刪掉
  該 app 的 defaults domain。

## 原因:AppKit 會還原儲存的視窗框

AppKitBackend 呼叫 `setFrameAutosaveName`,所以儲存的 `NSWindow Frame <id>` 會蓋過 `.defaultSize`,與 SwiftUI 相同。2026-09-01
之前所有測試 app 用同一個 bundle id、共用一個 domain,而鍵是 root view 型別(`TupleView1<HotReloadableView>-0`),於是視窗的尺寸是
「最後被調整的那支 app」的:P28 裸啟動 680x448、在 bundle 裡 1076x907。現在每支 Pn 有自己的 bundle id,`run_macos` 每次啟動前
丟掉儲存的視窗框(4b268536,2026-10-22:P41 開成 1202x799 對 GTK 的 1340x888,P92 仍留著 460 點的視窗框)。
`SCUI_KEEP_WINDOW_FRAME=1` 保留它們，用來測還原本身。

## 依據

- 2026-09-18 掃 72 支 app(`testapp/measurements/window-sizes-appkit-sweep-20260918.csv2`):標出兩支。P5 的寬度由最小值決定
  (Button 的修改);P27 的 `.defaultSize` 高 520 小於最小值 539,SwiftCrossUI 警告「vertical stack ran out of space」——改為 620。
  最小高度為零的八支(P21 P22 P46 P47 P48 P51 P52 P54)強制成 600x300:內容被裁切、沒有被擠壓、沒有警告。不是缺陷。
- P50 的根因(mac/appkit P50,2026-09-18):`Button.computeLayout` 把高度減掉 padding 提議給標籤，提議為零時按鈕縮成只剩
  padding,視窗矮了約 150 點、按鈕成了三像素的細條。修在共用程式碼:`childProposal.height = nil`,並移除
  `.frame(minHeight: 1000)` 的繞道。
- AppKit 不會讓視窗小於內容的最小值。一張 393 點「手機寬度」的 P43 擷圖其實是 568 點視窗的裁切(`screencapture -R`),System Events
  讀回 568x700(mistakes.md,2026-09-03)。**擷圖要作為尺寸的證據時，從視窗讀回尺寸。**

## 顯示縮放變更

沒有任何合成輸入能改變顯示器的縮放。`zsh testapp/test_support/scale_change_mac.zsh` 編譯 `vdisplay.m`——一個 HiDPI 的
`CGVirtualDisplay`(CoreGraphics 的私有類別,DeskPad 與 BetterDisplay 用的機制)。在螢幕本身是 headless 虛擬顯示器的 Mac 上，它成為
唯一的顯示器，所有視窗變成 2x,程式結束時再回來。P42 記到縮放 1.0 -> 2.0 -> 1.0;對照組只有 1.0(2026-09-30)。它改變整個螢幕，
所以只在 harness 持有 ui-lock(test-p42)時執行。

## 限制

- 在有實體顯示器的 Mac 上，虛擬顯示器是否同樣接管，沒有紀錄。
