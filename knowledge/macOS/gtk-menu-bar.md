# GtkBackend on macOS: the menu bar and keyboard commands

## What

On macOS, `gtkApp.menuBarModel` (set in `GtkBackend.setApplicationMenu`,
`Sources/GtkBackend/GtkBackend.swift`) becomes the screen-top menu bar, an
NSMenu, not a bar inside the window. `menubarHeight(ofWindow:)` is 0 there.

- **GTK's own app menu comes first.** GTK fills the bar's first place from
  `gtkapplication-quartz.ui` (About, Settings…, Services, Hide, Hide Others,
  Show All, Quit) and GTK 4 has no public call to replace it, so an app with an
  application menu showed two menus under its name (P92, 2026-10-14).
  `GtkBackend+MacAppMenu.swift` moves the framework's menu into the first item
  as its submenu and hides the second item; nothing is removed, because GTK
  inserts and removes bar items by position. It is redone each time the model is
  set. Done through the Objective-C runtime: GtkBackend does not link AppKit
  there.
- **Standard items always present.** `BackendFeatures.StandardCommands` is
  implemented in Swift (ef69d6dc, 2026-10-13: editing commands as the actions
  GTK's text widgets install, Close, Close All, Minimize, Zoom, Bring All to
  Front, Quit, About). `showsStandardMenusByDefault` is true on Darwin only
  (213d9c4e, 2026-10-23), and `Commands.apply` treats it as `enableMenu`.
  Before that, without `enableMenu()`, the app's commands replaced the system's:
  P92's app menu held only the `AFTER-*` items (no About, Hide or Quit) and
  File/Edit/Window lacked Close, Undo, Copy and Minimize. Windows and WSL GTK are
  unchanged (no menu bar unless asked).
- The app menu is titled `debugTarget`, the harness bundle's name, as on AppKit.

## Keys

- **Command is GTK's `<Meta>`.** `.command` maps to `<Control>` elsewhere and to
  `<Meta>` on macOS; Quit is `<Meta>q`. Before (P71, 2026-10-14) Command-S fired
  nothing: plain 0, shifted 0; after: plain 1, shifted 1, disabled 0.
- **Punctuation needs GDK's key name.** `gtk_accelerator_parse` rejects
  `"<Meta>?"` (Gtk-CRITICAL "Unable to parse accelerator"), so Help's Command-?
  was never installed. A non-alphanumeric key is now written through
  `gdk_unicode_to_keyval` + `gdk_keyval_name` (`question`, `comma`) (b0d5b639).
- **A rebuilt menu must clear accelerators.** Menu actions are named by
  position; P92's `before` menu is built twice at launch and BEFORE-saveItem
  showed Close's Command-W until `applyShortcut` cleared the accelerator of an
  item without one (b0d5b639).
- **Popover menus start like NSMenu.** `gtk_popover_show` focuses the first item
  when the popover has no focus child, so the first Down reached the second item
  and a reopened menu kept its old focus. `GtkMenuKeyboardStart`
  (`GtkBackend+MenuKeyboard.swift`, d21ad213) clears focus children before each
  opening; Down + Return chooses the first item, Up + Return the last, Return
  alone closes (P19, results.csv2: mac, gtk4, P19, 2026-10-19).
- **Text undo is the framework's history** (`TextUndoHistory`,
  `GtkBackend+TextUndo.swift`): two pastes are two undo steps, keys typed
  together one step (P92, P94, results.csv2 2026-10-14). Ctrl+Y redo is
  Control only, because on macOS Meta is Command and Command-Y is not redo.

## How to check

The in-app dump (`P92 --debug`, `#if canImport(AppKit)`, reads `NSApp.mainMenu`)
works for the GTK build too, and `testapp/test_support/compare_menu_dump.py`
compares it with `testapp/reference/swiftui-commands/`. Items are pressed in the
real bar through System Events (`osascript`), which needs the Accessibility
grant for the calling terminal.

## Evidence

- results.csv2 mac/gtk4 P92, 2026-10-13 and 2026-10-14: menus read and pressed
  through System Events; Zoom 460x648 -> 1920x980 and back, Minimize set
  AXMinimized, Hide Others/Show All visible apps 7 -> 1 -> 7, Close All ended
  the app.
- results.csv2 mac/gtk4 P92, 2026-10-20: all five modes match the references
  except the app name and macOS's "No Services Apply".
- results.csv2 mac/gtk4 P71 and P92, 2026-10-23: bar before and after 213d9c4e;
  P71 > Plain fires, Quit ends the app.

## Limits

- The comparison with SwiftUI always differs in the app name and in macOS's
  own "No Services Apply" item.
- Help opens a dialog, not the system help viewer (results.csv2: mac, gtk4,
  P92, 2026-10-14). ef69d6dc first left Services, the Hide items and Help out;
  the later app-menu rows show them present.

---

# macOS 上的 GtkBackend:選單列與鍵盤指令

## 是什麼

macOS 上 `gtkApp.menuBarModel`(於 `GtkBackend.setApplicationMenu` 設定)會成為螢幕頂端的選單列(NSMenu),不是視窗內的
選單列;`menubarHeight(ofWindow:)` 在那裡為 0。

- **GTK 自己的 app 選單排第一。** GTK 以 `gtkapplication-quartz.ui` 填入第一格(About、Settings…、Services、Hide、
  Hide Others、Show All、Quit),GTK 4 沒有公開的方法取代它，於是有 app 選單的 app 會在自己名字下出現兩個選單(P92,
  2026-10-14)。`GtkBackend+MacAppMenu.swift` 把框架的選單交給第一格當子選單，並隱藏第二格；不刪除任何項目，因為 GTK
  依位置插入與移除。每次設定 model 時重做一次，經由 Objective-C runtime 完成。
- **標準項目一律存在。** `BackendFeatures.StandardCommands` 以 Swift 實作(ef69d6dc,2026-10-13)。
  `showsStandardMenusByDefault` 只在 Darwin 為 true(213d9c4e,2026-10-23),`Commands.apply` 視同 `enableMenu`。
  在那之前，沒有 `enableMenu()` 時 app 的指令會取代系統的:P92 的 app 選單只有 `AFTER-*`(沒有 About、Hide、Quit),
  File/Edit/Window 缺 Close、Undo、Copy、Minimize。Windows 與 WSL 的 GTK 不變。
- app 選單標題是 `debugTarget`(harness bundle 的名稱),與 AppKit 相同。

## 按鍵

- **Command 是 GTK 的 `<Meta>`。** `.command` 在其他平台對應 `<Control>`,在 macOS 對應 `<Meta>`;Quit 是 `<Meta>q`。
  改之前(P71,2026-10-14)Command-S 沒有作用:plain 0、shifted 0;之後 plain 1、shifted 1、disabled 0。
- **標點要用 GDK 的鍵名。** `gtk_accelerator_parse` 不接受 `"<Meta>?"`,Help 的 Command-? 從未裝上；非英數字鍵改經
  `gdk_unicode_to_keyval` + `gdk_keyval_name`(`question`、`comma`)(b0d5b639)。
- **重建的選單要清掉快捷鍵。** 選單 action 依位置命名;P92 的 `before` 選單啟動時建了兩次,BEFORE-saveItem 帶著 Close
  的 Command-W,直到 `applyShortcut` 會清掉沒有快捷鍵的項目(b0d5b639)。
- **popover 選單的鍵盤起點比照 NSMenu。** `GtkMenuKeyboardStart`(d21ad213)每次開啟前清掉 focus child;Down + Return
  選第一項、Up + Return 選最後一項、只按 Return 則關閉(P19,results.csv2:mac、gtk4、P19、2026-10-19)。
- **文字的復原是框架的歷史紀錄**(`TextUndoHistory`):兩次貼上是兩步、一起輸入的字是一步(P92、P94,2026-10-14)。
  Ctrl+Y 重做只認 Control,因為 macOS 上 Meta 是 Command,而 Command-Y 不是重做。

## 怎麼檢查

app 內傾印(`P92 --debug`,`#if canImport(AppKit)`,讀 `NSApp.mainMenu`)對 GTK 建置一樣有效，再以
`compare_menu_dump.py` 與 `testapp/reference/swiftui-commands/` 比對。實際選單項目經 System Events(`osascript`)按下，
呼叫端的終端機需要「輔助使用」權限。

## 證據

- results.csv2 mac/gtk4 P92,2026-10-13 與 10-14:經 System Events 讀取與按下;Zoom、Minimize、Hide Others/Show All、
  Close All 都有作用。
- results.csv2 mac/gtk4 P92,2026-10-20:五種模式除 app 名稱與 macOS 的「No Services Apply」外都與基準相同。
- results.csv2 mac/gtk4 P71、P92,2026-10-23:213d9c4e 前後的選單列;P71 > Plain 有作用,Quit 結束 app。

## 限制

- 與 SwiftUI 的比對永遠差在 app 名稱與「No Services Apply」(macOS 自己的項目)。
- Help 開的是對話框而非系統說明(results.csv2:mac、gtk4、P92、2026-10-14)。ef69d6dc 起初略過 Services、Hide 與 Help,
  之後的 app 選單紀錄顯示它們都已存在。
