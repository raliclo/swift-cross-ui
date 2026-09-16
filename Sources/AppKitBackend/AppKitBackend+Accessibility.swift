import AppKit
import SwiftCrossUI

extension AppKitBackend: BackendFeatures.Accessibility {
    /// Routes a button's properties through the button, and everything else's
    /// straight onto the view.
    ///
    /// **A SwiftCrossUI widget is often not the element a screen reader
    /// reads, and `NSCustomButton` is the case that proves it.** It is a plain
    /// `NSView` and therefore TRANSPARENT in the accessibility tree -- its own
    /// `accessibilityRole()` and `accessibilityLabel()` overrides are never
    /// consulted, as `AppKitBackend+Button.swift` records from dumping P28,
    /// where the `AXButton` and the label's `AXStaticText` came back as
    /// SIBLINGS. The element is the inner `NSButtonBackground`.
    ///
    /// Two earlier attempts to reach it from out here both failed, and both
    /// failed quietly:
    ///
    /// | attempt | what `ax_dump` said |
    /// | --- | --- |
    /// | the unique subview with `isAccessibilityElement()` | `desc='X'` -- the flag is `false` by default on every `NSView`, `NSButton` included, so there was no candidate |
    /// | the unique `NSControl` descendant | `desc='X'` -- there are two, the inner button and the label's `NSTextField`, so "unique" found neither |
    ///
    /// Even reaching it would not have held: `refreshAccessibilityLabel` runs
    /// from `updateButton` on every layout pass and rewrites the label from the
    /// button's own text. So the override is HANDED to the button and consulted
    /// by that derivation, which removes the race rather than winning it.
    ///
    /// 把按鈕的屬性交由按鈕處理,其餘一切則直接設在 view 上。
    ///
    /// **一個 SwiftCrossUI 的 widget 往往不是螢幕閱讀器所讀的那個元素,而 `NSCustomButton` 正是
    /// 證明這件事的案例。** 它是一個單純的 `NSView`,因此在無障礙樹中是**透明**的——它自己的
    /// `accessibilityRole()` 與 `accessibilityLabel()` override 從不會被詢問,這一點
    /// `AppKitBackend+Button.swift` 已從傾印 P28 記錄下來:那裡的 `AXButton` 與標籤的
    /// `AXStaticText` 回報為**兄弟**。真正的元素是內層的 `NSButtonBackground`。
    ///
    /// 從外面伸手去抓它的兩次嘗試都失敗了,而且都是靜默地失敗:
    ///
    /// | 嘗試 | `ax_dump` 說了什麼 |
    /// | --- | --- |
    /// | 唯一一個 `isAccessibilityElement()` 為真的子 view | `desc='X'`——該旗標在每一個 `NSView` 上的預設值都是 `false`(`NSButton` 也不例外),因此根本沒有候選 |
    /// | 唯一一個 `NSControl` 後代 | `desc='X'`——有**兩個**(內層按鈕與標籤的 `NSTextField`),因此「唯一」兩個都沒找到 |
    ///
    /// 就算抓到了也站不住:`refreshAccessibilityLabel` 會在每一次版面計算時由 `updateButton` 呼叫,
    /// 並用按鈕自己的文字重寫那個標籤。因此覆寫值是**交給**按鈕、由那個推導去參考的——那是**移除**
    /// 這場競賽,而不是去贏它。
    public func setAccessibilityLabel(ofWidget widget: Widget, to label: String?) {
        if let button = widget as? NSCustomButton {
            button.accessibilityLabelOverride = label
        } else {
            widget.setAccessibilityLabel(label)
        }
    }

    public func setAccessibilityHint(ofWidget widget: Widget, to hint: String?) {
        if let button = widget as? NSCustomButton {
            button.accessibilityHintOverride = hint
        } else {
            widget.setAccessibilityHelp(hint)
        }
    }

    public func setAccessibilityValue(ofWidget widget: Widget, to value: String?) {
        if let button = widget as? NSCustomButton {
            button.accessibilityValueOverride = value
        } else {
            widget.setAccessibilityValue(value)
        }
    }

    /// Hides the widget and its whole subtree.
    ///
    /// **`setAccessibilityElement(false)` does not do this, and that was
    /// measured rather than assumed.** `ax_dump` on P67 lists
    /// `AXStaticText 'plain label'` for a text field that
    /// `AppKitBackend+Button.swift` had already called
    /// `setAccessibilityElement(false)` on. The flag says "I am not an element";
    /// it does not stop AppKit deriving one from the view anyway, and for
    /// `NSTextField` it derives one.
    ///
    /// Overriding the children list is what holds. An empty
    /// `accessibilityChildren` gives AppKit nothing to descend into, so the
    /// subtree is gone from the tree rather than merely asked to leave; the flag
    /// is still set so the widget itself is not announced either.
    ///
    /// Restoring passes `nil`, not `[]`. `nil` means "derive them as usual",
    /// which is the state before this was ever called -- handing back a
    /// snapshot of the subviews instead would freeze the list as it was at that
    /// moment and quietly stop tracking anything added later.
    ///
    /// 隱藏這個 widget 及其整棵子樹。
    ///
    /// **`setAccessibilityElement(false)` 做不到這件事,而這是量出來的、不是假設的。** 對 P67 跑
    /// `ax_dump`,會列出 `AXStaticText 'plain label'`——而那個文字欄位,`AppKitBackend+Button.swift`
    /// 早就對它呼叫過 `setAccessibilityElement(false)` 了。那個旗標說的是「我不是一個元素」;它並不會
    /// 阻止 AppKit 仍舊從該 view 推導出一個,而對 `NSTextField` 來說,它就是會推導出一個。
    ///
    /// 真正站得住的是覆寫子元件清單。一個空的 `accessibilityChildren` 讓 AppKit 沒有東西可以往下走,
    /// 於是那棵子樹是從樹上**消失**了,而不只是被請求離開;旗標仍然設著,好讓這個 widget 本身也不會
    /// 被宣讀。
    ///
    /// 還原時傳的是 `nil`,不是 `[]`。`nil` 的意思是「照常推導」,那正是本方法從未被呼叫過時的狀態
    /// ——若改為交回一份子 view 的快照,會把清單凍結在當下那一刻,並靜默地不再追蹤之後加入的任何東西。
    public func setAccessibilityHidden(ofWidget widget: Widget, to hidden: Bool) {
        widget.setAccessibilityElement(!hidden)
        widget.setAccessibilityChildren(hidden ? [] : nil)
    }

}
