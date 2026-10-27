# WinUIBackend: controls that needed their own implementation

Written 2026-10-24 from Sources/WinUIBackend (+LocaleWheels.swift,
+FileDialogs.swift, +Popovers.swift, +StandardCommands.swift), commits 8b34947a,
535d8f69, 4ea1796a, 14b6d6f9, 5bd71616, and results.csv2 (windows, winui: P18,
P62, P75 2026-10-07; P90, P41, P81, P92 2026-10-20; P94 2026-10-23).

## Date and time pickers

WinUI's `DatePicker` and `TimePicker` ignore `FrameworkElement.Language`, even
set before they load, so `\.locale` never reached them (P90). WinUIBackend now
draws its own `LocaleDateWheel` and `LocaleTimeRow` (8b34947a, 2026-10-20):
zh_TW reads 2025 / 8月 / 24 and 上午 09 : 46. `.compact` builds its format from
the locale's numeric pattern.

- A programmatic `TimePicker.selectedTime` raised `timeChanged` and truncated
  the seconds, writing the bound value back at launch; guarded since 2026-09-17.
- Open: the `.graphical` CalendarView grid stays English (known limit, checked
  2026-10-20).

## File dialogs

The shell `IFileOpenDialog`/`IFileSaveDialog` replace the WinRT pickers
(2026-10-07). They honour `initialDirectory` (WinRT could not) and need the STA
start. `ContentType` filters by extension; `conformingFileExtensions` makes a
plain-text dialog list `.swift` as macOS does (P62).

## Popovers

- `FlyoutPlacementMode.auto` shows nothing, so a popover with no arrow edge
  never appeared (4ea1796a).
- Flyout draws no arrow, and TeachingTip is not projected; WinUIBackend draws a
  20x10 arrow in its own Popup from where the panel landed (535d8f69).

## Sheets and covers

A sheet or full-screen cover is a `ContentDialog` Popup. A window capture does
not include it; use a desktop capture or UIA (P81 and P49 fail rows were
corrected that way, 2026-10-20/21).

## Menus and commands

- The menu bar exists only when the app asks for it (`SCUI_P92_MENU=1` in P92;
  without it, no bar on Windows). `SCUI_DEBUG_MENU_DUMP=1` reads the built bar
  back for comparison with `testapp/reference/swiftui-commands` (5bd71616).
- The menu was applied before `WindowGroup` registered its opener, so there was
  no New Window; `_App` re-applies once the openers exist.
- Standard Edit commands act on the text box remembered through
  `FocusManager.gotFocus` (WinUIBackend+StandardCommands.swift).
- `TextBox` redoes on Ctrl+Y only; `LongPressTextBox.onKeyDown` also takes
  Ctrl+Shift+Z (14b6d6f9, P94).

## Limits

- A WinUI window can be taller than the screen at 125%: P41 is 1471 px on a
  1080 px display, so a click at screen y 1490 is clamped (open, 2026-10-20;
  needs 100% or a taller display).

---

# WinUIBackend:需要自己實作的控制項

2026-10-24 依 Sources/WinUIBackend(+LocaleWheels.swift、+FileDialogs.swift、+Popovers.swift、
+StandardCommands.swift)、8b34947a、535d8f69、4ea1796a、14b6d6f9、5bd71616,以及 results.csv2(windows、winui:
P18、P62、P75 於 2026-10-07;P90、P41、P81、P92 於 2026-10-20;P94 於 2026-10-23)寫成。

## 日期與時間選擇器

WinUI 的 `DatePicker` 與 `TimePicker` 不理會 `FrameworkElement.Language`,即使在載入前設定也一樣，所以 `\.locale`
從未到達(P90)。WinUIBackend 現在自己畫 `LocaleDateWheel` 與 `LocaleTimeRow`(8b34947a,2026-10-20):zh_TW 顯示
2025 / 8月 / 24 與 上午 09 : 46。`.compact` 以地區設定的數字樣式組出格式。

- 以程式設定 `TimePicker.selectedTime` 會觸發 `timeChanged` 並截掉秒數，在啟動時就把綁定值寫回；自 2026-09-17 起已
  防範。
- 未解決:`.graphical` 的 CalendarView 格子仍是英文(已知限制，檢查於 2026-10-20)。

## 檔案對話框

shell 的 `IFileOpenDialog`/`IFileSaveDialog` 取代了 WinRT picker(2026-10-07)。它們會遵守 `initialDirectory`
(WinRT 做不到),並需要 STA 啟動。`ContentType` 以副檔名過濾;`conformingFileExtensions` 讓純文字對話框像 macOS
一樣列出 `.swift`(P62)。

## Popover

- `FlyoutPlacementMode.auto` 什麼都不顯示，所以沒有指定箭頭邊的 popover 從未出現(4ea1796a)。
- Flyout 不畫箭頭,TeachingTip 也沒有被 project;WinUIBackend 依面板實際落下的位置，在自己的 Popup 裡畫一個
  20x10 的箭頭(535d8f69)。

## Sheet 與全螢幕覆蓋

sheet 或全螢幕覆蓋是 `ContentDialog` Popup。視窗擷取不包含它；請用桌面擷取或 UIA(P81 與 P49 的失敗列就是這樣更正
的,2026-10-20/21)。

## 選單與命令

- 只有 app 要求時才有選單列(P92 的 `SCUI_P92_MENU=1`;沒有它,Windows 上沒有選單列)。`SCUI_DEBUG_MENU_DUMP=1`
  會讀回建好的選單列，與 `testapp/reference/swiftui-commands` 比對(5bd71616)。
- 選單在 `WindowGroup` 登記其開啟器之前就套用，所以沒有 New Window;`_App` 現在在開啟器存在後重新套用一次。
- 標準 Edit 命令作用於透過 `FocusManager.gotFocus` 記住的文字方塊(WinUIBackend+StandardCommands.swift)。
- `TextBox` 只在 Ctrl+Y 時重做;`LongPressTextBox.onKeyDown` 也接受 Ctrl+Shift+Z(14b6d6f9,P94)。

## 限制

- 在 125% 時 WinUI 視窗可能比螢幕還高:P41 在 1080 px 的顯示器上高 1471 px,螢幕 y 1490 的點擊會被夾限(未解決，
  2026-10-20;需要 100% 或更高的顯示器)。
