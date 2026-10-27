# Menus, keyboard shortcuts and key events on iOS

How `.commands`, `CommandMenu`, `CommandGroup` and key presses reach a
UIKitBackend app on iPhone and iPad. Checked against UIKitBackend.swift,
UIKitBackend+Menu.swift, +CommandLayouts.swift and +KeyEvents.swift on
2026-10-24.

## The menu bar (iPad, Mac Catalyst)

- `BackendFeatures.ApplicationMenus` is compiled for `os(iOS)` too. Before
  2026-09-16 it sat inside `#if targetEnvironment(macCatalyst)`; the framework's
  cast failed, `setApplicationMenu` never ran, and the menu was built correctly
  out of an empty list (`buildMenu system==main: true submenus=0`), so P71's
  shortcut counters read zero while keys arrived.
- `buildMenu(with:)` runs once, early, before the app's body has produced
  anything. `setApplicationMenu` therefore calls `setNeedsRebuild()`.
- The iPad menu bar is built only once a key or the pointer arrives, so it is
  read under the action-file runner.
- `CommandGroup` placements map to UIKit menu identifiers, so `replacing:`
  removes exactly the system's group. Compared with a SwiftUI reference app on
  the iPad simulator (`test_support/compare_ipad_menu_dump.py`, 2026-10-14 to
  2026-10-21): identical except `windowList`/`singleWindowList`, which SwiftUI
  lacks on iOS and UIKitBackend keeps at the end of the Window menu on purpose.
  The Format menu is dropped as SwiftUI does (f9a4d8aa, 2026-10-20).

## iPhone: no menu bar

- **`buildMenu` is never called with `.main` on iPhone** (measured 2026-09-16,
  iPhone 17 Pro Max). Every `UIKeyCommand` made there was absent on the phone.
- Shortcuts are published instead as `ApplicationDelegate.keyCommands`, along
  the responder chain, which a hardware keyboard uses without any menu
  (7d39da12). They are withheld once a main menu has been built
  (`hasBuiltMainMenu`, read at key time), or an iPad would run each shortcut
  twice. They live in their own action table (`FallbackShortcutActions`).
- With `Scene.enableMenu(_:)` a menu button appears at the top left and opens
  the standard menus as submenus. This is the framework's own design (SwiftUI
  shows nothing on iPhone), agreed 2026-10-14; it has no Format menu either
  (89793ac1).
- Verified: P71 PLAIN 1, SHIFTED 1, disabled Cmd-D never fired, on iPhone and
  iPad.

## Key events (`pressesBegan`/`pressesEnded`)

- **A modifier's own release still reports itself.** `UIKey.modifierFlags` on
  `pressesEnded` for Shift contains `.shift`; the backend removes the key's own
  bit on `.up` (P72 printed `MODIFIERS up shift=true`, 2026-09-22). AppKit's and
  Android's synthesisers had the same defect.
- **Arrow keys are words.** `charactersIgnoringModifiers` for the up arrow is
  `"UIKeyInputUpArrow"`; taking its first character produced the letter U
  (P72's readout said `last U`). Named keys are mapped from `UIKey.keyCode`
  (HID usage) to the same private-use scalars AppKit uses.
- Keys reach the simulator only through the XCUITest runner's `typeKey`
  (hardware keyboard). `simctl` has no key verb, `idb` is not installed, and
  CGEvent drivers aimed at the Simulator window failed.
- XCUITest's Escape did not reach `pressesBegan` on the iPhone simulator
  (P49, 2026-10-20); the file closes the sheet with a swipe instead.
- The simulator shows a one-time "Speed up your typing" sheet; it once looked
  like a keyboard raised by a long press (P72, closed 2026-09-29, did not
  reproduce).

---

# iOS 上的選單、鍵盤快捷鍵與按鍵事件

`.commands`、`CommandMenu`、`CommandGroup` 與按鍵如何在 iPhone 與 iPad 上到達 UIKitBackend app。2026-10-24 對照
UIKitBackend.swift、UIKitBackend+Menu.swift、+CommandLayouts.swift 與 +KeyEvents.swift 確認。

## 選單列(iPad、Mac Catalyst)

- `BackendFeatures.ApplicationMenus` 也為 `os(iOS)` 編譯。2026-09-16 之前它位於 `#if targetEnvironment(macCatalyst)`
  之內;框架的轉型失敗,`setApplicationMenu` 從未執行，選單從空清單正確地建了出來(`buildMenu system==main: true
  submenus=0`),所以 P71 的快捷鍵計數器在按鍵確實到達時仍讀到 0。
- `buildMenu(with:)` 只執行一次，而且很早，在 app 的 body 產生任何東西之前。因此 `setApplicationMenu` 會呼叫
  `setNeedsRebuild()`。
- iPad 的選單列要等到按鍵或指標到達後才建立，所以要在動作檔 runner 下讀取。
- `CommandGroup` 的位置對應到 UIKit 的選單識別碼，所以 `replacing:` 移除的正好是系統的那一組。在 iPad 模擬器上與
  SwiftUI 參考 app 比對(`test_support/compare_ipad_menu_dump.py`,2026-10-14 至 2026-10-21):除了
  `windowList`/`singleWindowList` 之外完全相同;SwiftUI 在 iOS 上沒有這兩者，UIKitBackend 刻意把它們放在 Window 選單末端。
  Format 選單如 SwiftUI 一樣被拿掉(f9a4d8aa,2026-10-20)。

## iPhone:沒有選單列

- **iPhone 上 `buildMenu` 從不以 `.main` 呼叫**(2026-09-16 於 iPhone 17 Pro Max 實測)。在那裡產生的每個 `UIKeyCommand`
  在手機上都不存在。
- 快捷鍵改以 `ApplicationDelegate.keyCommands` 沿 responder chain 發布，硬體鍵盤不需要任何選單就會經過它(7d39da12)。
  一旦建立過主選單就不再發布(`hasBuiltMainMenu`,按鍵時讀取),否則 iPad 會讓每個快捷鍵執行兩次。它們有自己的動作表
  (`FallbackShortcutActions`)。
- 使用 `Scene.enableMenu(_:)` 時左上角會出現選單按鈕，以子選單打開標準選單。這是本框架自己的設計(SwiftUI 在 iPhone 上
  什麼都不顯示),2026-10-14 議定;它同樣沒有 Format 選單(89793ac1)。
- 已驗證:P71 在 iPhone 與 iPad 上 PLAIN 1、SHIFTED 1,停用的 Cmd-D 從未觸發。

## 按鍵事件(`pressesBegan`/`pressesEnded`)

- **修飾鍵自己放開時仍回報自己。** Shift 的 `pressesEnded` 中 `UIKey.modifierFlags` 仍含 `.shift`;backend 在 `.up` 時
  移除該鍵自己的位元(P72 印出 `MODIFIERS up shift=true`,2026-09-22)。AppKit 與 Android 的合成器也有同樣的缺陷。
- **方向鍵是一個字。** 向上鍵的 `charactersIgnoringModifiers` 是 `"UIKeyInputUpArrow"`;取第一個字元會得到字母 U
  (P72 的讀數顯示 `last U`)。具名按鍵改由 `UIKey.keyCode`(HID usage)對應到與 AppKit 相同的私用區字元。
- 按鍵只能經由 XCUITest runner 的 `typeKey`(硬體鍵盤)送進模擬器。`simctl` 沒有按鍵動作、沒有安裝 `idb`,瞄準模擬器
  視窗的 CGEvent 驅動程式都失敗了。
- iPhone 模擬器上 XCUITest 的 Escape 沒有到達 `pressesBegan`(P49,2026-10-20);該檔案改以滑動關閉 sheet。
- 模擬器會顯示一次性的「加快打字速度」sheet;它曾看起來像是長按叫出了鍵盤(P72,2026-09-29 結案，未能重現)。
