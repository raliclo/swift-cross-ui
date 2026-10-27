# macOS: dumping and comparing the menu bar

Written 2026-10-24 from testapp/P92.swift, testapp/reference/swiftui-commands/,
testapp/test_support/compare_menu_dump.py and matrix_coverage/results.csv2
(mac, P92, 2026-10-13 to 2026-10-23).

## What

The menu bar is checked against a real SwiftUI app, not against memory.

- **Reference.** `testapp/reference/swiftui-commands/ref.swift` is a SwiftUI app
  with the same twenty `CommandGroupPlacement`s as P92. Its dumps are
  `base.txt`, `after.txt`, `before.txt`, `replacing.txt`, `dupfile.txt` and
  `two-groups.txt` (P93's two window groups); `ipad/` holds the iPad ones.
- **The app's own dump.** Under `--debug`, P92 (AppKit, and GTK on macOS,
  where GTK's bar is also an `NSMenu`) writes `NSApp.mainMenu` one second after
  `onAppear` to `p92-menu-<mode>.txt` in `SCUI_DEBUG_EVENTS_DIR` (else the
  working directory). Format: one item per line, two spaces per depth, `---`
  for a separator, `[^~$@key]` for a shortcut (control, option, shift,
  command), `(hidden)` for a hidden item. The Window menu's entries for open
  windows (`makeKeyAndOrderFront:`) are skipped.
- **Modes.** `SCUI_P92_MODE` = `after` (default), `before`, `replacing`, `base`,
  `dupfile`. `SCUI_P92_MENU=1` (or `--p92-menu`) also calls `.enableMenu()`.
- **Compare.** `python3 testapp/test_support/compare_menu_dump.py REF.txt DUMP.txt [APP]`
  writes both app names as APP, drops the items AppKit adds to any Edit menu
  by itself (Writing Tools, AutoFill, Start Dictation, Emoji & Symbols) with
  their separators, drops hidden items, and folds runs of separators. Exit 0
  when equal, 1 with a diff.
- **GtkBackend's model.** `SCUI_DEBUG_MENU_DUMP=1` prints the `GMenuModel` GTK
  holds, in `CommandLayout.textDescription` form (`setApplicationMenu`,
  Sources/GtkBackend/GtkBackend.swift). It is how Windows and WSL compare;
  on macOS the NSMenu dump shows what reached the screen.

## The real menu bar through System Events

Reading or pressing the screen-top bar goes through `osascript` and System
Events. That needs the Accessibility grant for the program running it; without
it the call fails with `osascript is not allowed assistive access. (-1719)`
(testapp/mac-test-results-2026-08-26.md). It is the only way to drive GTK's
menus on macOS from outside, and it was used for:

- GtkBackend `CommandGroup` (results.csv2 mac/gtk4 P92, 2026-10-13 and
  2026-10-14): items pressed, Zoom, Minimize/Bring All to Front, Hide, Hide
  Others, Show All, Close All, Undo/Redo in the Edit menu.
- The menu bar before and after 213d9c4e (mac/gtk4 P71 and P92, 2026-10-23).
- Redo on AppKit when a synthesised Shift-Command-Z did nothing
  (mac/appkit P94, 2026-10-14). The synthesiser now builds Command chords from
  a HID-state CGEvent and the key works.

## Results

- AppKit equals the SwiftUI dump in all five modes, line by line with
  shortcuts (mac/appkit P92, 2026-10-13); re-checked identical at 5bd71616
  (2026-10-20).
- GtkBackend on macOS matches in every mode except the app name (menu
  `Application`, items `P92-gtk4`) and macOS's own "No Services Apply", after
  b0d5b639 fixed Command-? (`<Meta>?` does not parse; punctuation uses GDK's key
  name) and a stale accelerator on a rebuilt menu.
- Since 213d9c4e GTK on macOS always carries the standard items
  (`showsStandardMenusByDefault`), so the bar matches AppKit without
  `enableMenu`. GTK's own app menu is replaced by the framework's
  (GtkBackend+MacAppMenu.swift). The app menu is named `debugTarget`, the
  harness bundle, on both backends.

## Other System Events uses, and their limits

- `testapp/window_sizes_mac.zsh` reads `size of window 1` through System Events.
- **Do not resize GTK windows with System Events.** `set size` was reverted on
  the second try by GDK 4.24.1 (`gtk4-widget-factory` undoes every second
  resize), and on P95 the GL area did not redraw (todo.md P2; results.csv2
  mac/gtk4 P95, 2026-10-14 and 2026-10-20). A corner drag with
  `testapp/test_support/measure/drag_at.swift`, or a resize made by the
  program, redraws every time.
- `screenshot.zsh` raises a window through System Events only for its
  whole-screen fallback, and says so when the grant is missing.

---

# macOS:傾印與比對選單列

2026-10-24 依 testapp/P92.swift、testapp/reference/swiftui-commands/、compare_menu_dump.py 與
matrix_coverage/results.csv2(mac、P92、2026-10-13 至 2026-10-23)寫成。

## 內容

選單列以真正的 SwiftUI app 為基準比對，不憑印象。

- **基準。** `testapp/reference/swiftui-commands/ref.swift` 是一支帶有與 P92 相同二十個
  `CommandGroupPlacement` 的 SwiftUI app。傾印為 `base.txt`、`after.txt`、`before.txt`、`replacing.txt`、
  `dupfile.txt` 與 `two-groups.txt`(P93 的兩個視窗群組);`ipad/` 是 iPad 版。
- **app 自己的傾印。** 帶 `--debug` 時,P92(AppKit,以及 macOS 上的 GTK——GTK 的選單列在那裡同樣是
  `NSMenu`)在 `onAppear` 一秒後把 `NSApp.mainMenu` 寫到 `SCUI_DEBUG_EVENTS_DIR`(否則為工作目錄)下的
  `p92-menu-<模式>.txt`。格式：一行一個項目，每層縮排兩個空白,`---` 是分隔線,`[^~$@鍵]` 是快捷鍵
  (control、option、shift、command),`(hidden)` 表示隱藏。Window 選單中代表開啟中視窗的項目略過。
- **模式。** `SCUI_P92_MODE` = `after`(預設)、`before`、`replacing`、`base`、`dupfile`。
  `SCUI_P92_MENU=1`(或 `--p92-menu`)會另外呼叫 `.enableMenu()`。
- **比對。** `compare_menu_dump.py REF.txt DUMP.txt [APP]` 把兩邊的 app 名稱都寫成 APP,移除 AppKit 自行加進
  Edit 選單的項目(Writing Tools、AutoFill、Start Dictation、Emoji & Symbols)及其分隔線，移除隱藏項目，
  合併連續分隔線。相同結束碼 0,不同為 1 並印出差異。
- **GtkBackend 的 model。** `SCUI_DEBUG_MENU_DUMP=1` 以 `CommandLayout.textDescription` 的格式印出 GTK 持有的
  `GMenuModel`。Windows 與 WSL 以它比對;macOS 上則以 NSMenu 傾印看實際上了螢幕的內容。

## 經 System Events 操作真正的選單列

讀取或按下螢幕頂端的選單列要經過 `osascript` 與 System Events,執行它的程式需要「輔助使用」權限；沒有時會以
`osascript is not allowed assistive access. (-1719)` 失敗(testapp/mac-test-results-2026-08-26.md)。這是在 macOS
上從外部驅動 GTK 選單的唯一方式，用於：

- GtkBackend 的 `CommandGroup`(results.csv2 mac/gtk4 P92,2026-10-13 與 10-14):按項目、Zoom、Minimize/
  Bring All to Front、Hide、Hide Others、Show All、Close All、Edit 選單的 Undo/Redo。
- 213d9c4e 前後的選單列(mac/gtk4 P71 與 P92,2026-10-23)。
- 合成的 Shift-Command-Z 沒有作用時，在 AppKit 上做 Redo(mac/appkit P94,2026-10-14)。synthesiser 現在以 HID
  狀態的 CGEvent 建 Command 組合鍵，該鍵已可用。

## 結果

- AppKit 在五種模式下都與 SwiftUI 傾印逐行相同(含快捷鍵)(mac/appkit P92,2026-10-13);5bd71616 時重查仍相同
  (2026-10-20)。
- macOS 上的 GtkBackend 在 b0d5b639 修正 Command-?(`<Meta>?` 無法解析，標點改用 GDK 的鍵名)與重建選單殘留舊快捷鍵
  之後，每種模式都相符，只差 app 名稱(選單 `Application`、項目 `P92-gtk4`)與 macOS 自己的「No Services Apply」。
- 自 213d9c4e 起,macOS 上的 GTK 一律帶標準項目(`showsStandardMenusByDefault`),不需 `enableMenu` 即與 AppKit 相同；
  GTK 自己的 app 選單由框架的取代(GtkBackend+MacAppMenu.swift)。兩個 backend 的 app 選單都叫 `debugTarget`,即 harness 的 bundle。

## System Events 的其他用途與限制

- `testapp/window_sizes_mac.zsh` 以 System Events 讀 `size of window 1`。
- **不要用 System Events 改 GTK 視窗的大小。** `set size` 第二次會被 GDK 4.24.1 復原(`gtk4-widget-factory` 每隔一次被復原),
  P95 上 GL area 也不重繪(todo.md P2;results.csv2 mac/gtk4 P95,2026-10-14 與 10-20)。用
  `testapp/test_support/measure/drag_at.swift` 拖曳視窗角落，或由程式改大小，每次都會重繪。
- `screenshot.zsh` 只在整個螢幕的退路才經 System Events 把視窗帶到前景，缺權限時會明講。
