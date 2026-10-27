# AppKitBackend: accessibility

Checked from outside the process with `testapp/test_support/measure/ax_dump.swift`,
which reads the real AX tree (see `measure-tools.md`). Every fix below failed
silently at least once, so a change here needs an `ax_dump` reading before and
after.

## What the tree needs

- **The label goes on the inner `NSButton`.** A plain `NSView` wrapper is
  transparent in the AX tree, so an override on the wrapper was never
  consulted: every `AXButton` in P17, P28 and P34 had an empty title and
  description (2026-09-10). `NSCustomButton` now holds the override and its
  own derivation consults it (P69, 2026-09-16).
- **Hiding a child.** `setAccessibilityElement(false)` does not remove an
  `NSTextField` from the tree, so every button was announced twice;
  `setAccessibilityChildren([button])` does remove it (P69, 2026-09-16).
- **`.accessibilityLabel` on a `Text`.** The words on screen sat in the value,
  which a reader takes for static text, while the label went to the
  description. `setAccessibilityValue(_:)` on an `NSTextField` is accepted and
  ignored, because a control's value comes from its cell; `NSCustomTextField`
  answers with an `accessibilityValueOverride` instead (P69, 2026-09-17).
- **Two-text labels** are named from both texts joined by a space, as GTK
  (AT-SPI), WinUI (UIA) and VoiceOver read them: P67 reads
  `plain label / padded label / two texts / (empty)` (2026-09-17).
- **Identifiers.** `accessibilityIdentifier(_:)` reaches the listed element:
  `p32.labelled`, `p32.icon`, `p32.field`, `p32.slider` (628acffa, 2026-10-19).
- A `.disabled(true)` button took keyboard focus because the responder search
  walked past the wrapper to the enabled inner `NSButton` (P70, 2026-09-16).

## How to check

```sh
swiftc -O -o /tmp/axdump testapp/test_support/measure/ax_dump.swift
/tmp/axdump --children "$PWD/testapp/output/P69"
```

`--children` prints what sits under each named button; without it a stray
child (the GTK `X` found over AT-SPI) cannot show up.

## Limits

- Speech (what VoiceOver actually says) has not been recorded on macOS; only
  the tree is checked (queue item 8 covers speech on the Windows side).

---

# AppKitBackend:輔助使用

以 `testapp/test_support/measure/ax_dump.swift` 從行程外讀取真正的 AX 樹檢查(見 `measure-tools.md`)。下面每一項修正都至少
無聲失敗過一次，所以這裡的改動需要改動前後各一次 `ax_dump` 讀數。

## AX 樹需要的東西

- **標籤要放在內層的 `NSButton` 上。** 單純的 `NSView` 包裝在 AX 樹中是透明的，所以包裝上的覆寫從未被查詢:P17、P28、P34
  的每個 `AXButton` 標題與描述都是空的(2026-09-10)。現在由 `NSCustomButton` 持有覆寫，並在它自己的推導中查詢(P69,2026-09-16)。
- **隱藏子節點。** `setAccessibilityElement(false)` 不會把 `NSTextField` 從樹中移除，每顆按鈕因此被唸兩次;
  `setAccessibilityChildren([button])` 才會移除(P69,2026-09-16)。
- **`Text` 上的 `.accessibilityLabel`。** 畫面上的文字留在 value 裡(報讀器把它當靜態文字),標籤卻跑到 description。
  對 `NSTextField` 呼叫 `setAccessibilityValue(_:)` 會被接受但被忽略，因為控制項的 value 來自它的 cell;
  改由 `NSCustomTextField` 以 `accessibilityValueOverride` 回答(P69,2026-09-17)。
- **兩段文字的標籤**以兩段文字加空格命名，與 GTK(AT-SPI)、WinUI(UIA)和 VoiceOver 的讀法相同:P67 讀到
  `plain label / padded label / two texts / (空)`(2026-09-17)。
- **識別碼。** `accessibilityIdentifier(_:)` 會到達列出的元素:`p32.labelled`、`p32.icon`、`p32.field`、`p32.slider`
  (628acffa,2026-10-19)。
- `.disabled(true)` 的按鈕曾拿到鍵盤焦點，因為 responder 搜尋越過包裝、找到了啟用中的內層 `NSButton`(P70,2026-09-16)。

## 怎麼檢查

```sh
swiftc -O -o /tmp/axdump testapp/test_support/measure/ax_dump.swift
/tmp/axdump --children "$PWD/testapp/output/P69"
```

`--children` 會印出每顆具名按鈕底下的東西;少了它，多出來的子節點(GTK 經 AT-SPI 找到的 `X`)不可能顯示出來。

## 限制

- macOS 上還沒有記錄過語音(VoiceOver 實際唸出什麼);目前只檢查樹(語音在 Windows 端由 queue 第 8 項處理)。
