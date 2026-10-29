# Action files on Windows: coordinates and the traps

Written 2026-10-24 from testapp/actions/win/ (182 files), testapp/P0-P26-windows-findings.md
(second pass, 2026-08-27), Win32Synthesiser.swift, and results.csv2 (windows rows
of 2026-10-19 to 2026-10-23).

## Coordinates

- Files are in logical points: `scale = layoutScale ?? GetDpiForWindow / 96`.
- **WinUI** passes no layout scale, so rows are DIPs (Win11 runs at 125%).
- **GtkBackend** passes GTK's integer scale, which is 1 at 125%: rows for GTK
  are unscaled pixels off a GTK capture. The same app has different numbers on
  the two backends, and GTK lays out lower and taller (CSD shadow, header bar,
  control heights: about 20 px in P102). Many apps have a separate
  `<app>-*-gtk4.actions`.
- Rows inside a GTK popover use `origin=popover`; frame rows measured from the
  window corner land on the desktop (P19, 2026-10-20). Positions inside a popover
  come from a desktop capture, since a window capture does not contain it.
- Check the display scale before trusting a file: `actions/win/README` still
  says the scale is 1, and older files were measured at 100% or at 125%.

## A file can invalidate its own coordinates

The recurring failure: a step changes the layout, and later rows aim at where
controls used to be. The replay reports success and the capture shows an
unchanged app, which reads as "the app ignores input". It produced both wrong
findings of the first Windows pass (P24, P20) and misses in P9, P13, P26; later,
`wholeLineHeight` moved P17's buttons 69-79 px and the old file landed no click.

Rule: **a step that changes the layout must be the last step that uses that
layout's coordinates.** Put targets that never move last. Judge by the capture
and the app's own log, not by the exit code.

## Other traps

- **`move` rows are `SetCursorPos` jumps**, which WinUI does not see as motion.
  Use `hover` for buttonless pointer rows on WinUI (P88, P92). The GTK P92 file
  keeps `move` rows: `hover` made it worse.
- Replay needs `SCUI_DEBUG` compiled in; without it the file is ignored silently.
- The format is RFC 4180 CSV: an unquoted comma in the note column shifts the
  fields, and the error names the platform column.
- Give the app time to settle: P6's transport row moves after playback starts
  (needs a 6 s start), and test.zsh waits after showtime for `replayed|failed`.
- Not drivable: OLE drag and drop (P25), native file dialogs under the topmost
  pin (P1, P18 need a person), anything needing the window taller than the
  screen (P41 at 125%).
  2026-10-29: P41 is in a ScrollView and SwiftCrossUI caps a window at the
  room on its screen, so P41 fits; what is left is a click whose height
  follows the window's (P41-change-seconds after scrolling to the bottom).
  2026-10-29:P41 改放進 ScrollView,SwiftCrossUI 也依螢幕空間封頂視窗，P41 放得下了；剩下的是點擊高度隨視窗高度變動
  的情況(P41-change-seconds 捲到底後)。

---

# Windows 上的動作檔：座標與陷阱

2026-10-24 依 testapp/actions/win/(182 個檔案)、testapp/P0-P26-windows-findings.md(第二輪,2026-08-27)、
Win32Synthesiser.swift,以及 results.csv2(2026-10-19 至 2026-10-23 的 windows 列)寫成。

## 座標

- 檔案以邏輯點為單位:`scale = layoutScale ?? GetDpiForWindow / 96`。
- **WinUI** 不傳版面縮放，所以各列是 DIP(Win11 以 125% 執行)。
- **GtkBackend** 傳 GTK 的整數縮放，在 125% 時為 1:GTK 的列是取自 GTK 擷圖的未縮放像素。同一支 app 在兩個
  backend 上數字不同，而且 GTK 的版面較低也較高(CSD 陰影、header bar、控制項高度:P102 約 20 px)。許多 app 另有
  `<app>-*-gtk4.actions`。
- GTK popover 內的列使用 `origin=popover`;從視窗角落量的 frame 列會落在桌面上(P19,2026-10-20)。popover 內的
  位置取自桌面擷取，因為視窗擷取不包含它。
- 相信一個檔案之前先確認顯示縮放:`actions/win/README` 仍寫縮放為 1,而較舊的檔案有的在 100%、有的在 125% 量測。

## 檔案可能讓自己的座標失效

反覆出現的失敗：某一步改變了版面，之後的列卻瞄準控制項原本的位置。重放回報成功、擷圖顯示 app 沒變，看起來像
「app 忽略輸入」。它造成了 Windows 第一輪的兩項錯誤發現(P24、P20)以及 P9、P13、P26 的落空；後來
`wholeLineHeight` 讓 P17 的按鈕下移 69–79 px,舊檔一次都沒點中。

規則:**會改變版面的步驟，必須是使用該版面座標的最後一步。** 永遠不動的目標排在最後。以擷圖與 app 自己的 log
判定，不看結束碼。

## 其他陷阱

- **`move` 列是 `SetCursorPos` 跳躍**,WinUI 不把它當成移動。WinUI 上沒按鍵的指標列請用 `hover`(P88、P92)。
  GTK 的 P92 檔保留 `move`:改用 `hover` 反而更糟。
- 重放需要編入 `SCUI_DEBUG`;沒有它，檔案會被靜默忽略。
- 格式是 RFC 4180 CSV:note 欄中未加引號的逗號會讓欄位位移，而錯誤訊息指名的是 platform 欄。
- 給 app 時間穩定:P6 的傳輸列在開始播放後會移動(需要 6 秒的起始等待),test.zsh 在 showtime 之後會等
  `replayed|failed`。
- 驅動不了的:OLE 拖放(P25)、置頂釘選下的原生檔案對話框(P1、P18 需要人)、任何需要視窗高於螢幕的操作
  (125% 下的 P41)。
