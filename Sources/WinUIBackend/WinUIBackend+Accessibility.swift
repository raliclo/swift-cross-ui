import SwiftCrossUI
import WinUI

extension WinUIBackend: BackendFeatures.Accessibility {
    /// `AutomationProperties.Name`, which is what a screen reader announces.
    ///
    /// **Cleared with an empty string rather than left alone.** These are
    /// attached properties, so there is no "unset" through this API -- passing
    /// `nil` through as `""` is how a label is removed. Skipping the call
    /// instead would leave the previous label in place, and a control that keeps
    /// announcing a name the view no longer has is worse than one with no name
    /// at all: it is confidently wrong.
    ///
    /// `AutomationProperties.Name`——螢幕閱讀器唸出來的就是它。
    ///
    /// **以空字串清除,而不是略過不處理。** 這些是 attached property,因此經由本 API 沒有「取消設定」
    /// 這個動作——把 `nil` 轉成 `""` 就是移除標籤的方式。若改為跳過該呼叫,先前的標籤會留在原地,
    /// 而一個「持續唸出一個該 view 已經不再擁有的名稱」的控制項,比一個沒有名稱的更糟:它是**有自信地
    /// 錯著**。
    ///
    /// **On a button, the content leaves the automation tree while a label is
    /// set.** Measured 2026-09-17 with an out-of-process UIA dump of P69 in the
    /// CONTROL view, the one Narrator walks, and again in the content view:
    /// `button 'Close'` still had `text 'X'` under it. Same shape and same
    /// conditions as GtkBackend: only for a button, and only while a label is
    /// set, because an unlabelled button's content is what it has to say.
    ///
    /// **在按鈕上,只要設了標籤,內容就離開 automation 樹。** 2026-09-17 以行程外的 UIA dump 量 P69,
    /// 看的是 Narrator 所走的 **control** view,content view 也看了:`button 'Close'` 底下仍有
    /// `text 'X'`。形狀與條件都與 GtkBackend 相同:只針對按鈕,且只在設了標籤時,因為未設標籤的按鈕,
    /// 它要說的正是這些內容。
    public func setAccessibilityLabel(ofWidget widget: Widget, to label: String?) {
        AutomationProperties.setName(widget, label ?? "")
        if let button = widget as? WinUI.Button, let content = button.content as? WinUI.UIElement {
            setAccessibilityView(ofSubtree: content, hidden: label != nil)
        }
    }

    /// `AutomationProperties.HelpText`, the supplementary description.
    /// `AutomationProperties.HelpText`,補充說明。
    public func setAccessibilityHint(ofWidget widget: Widget, to hint: String?) {
        AutomationProperties.setHelpText(widget, hint ?? "")
    }

    /// The current value, through `ItemStatus`.
    ///
    /// **`ItemStatus`, not `FullDescription`**, and the two are easy to confuse
    /// because both are strings that a reader will voice. `FullDescription`
    /// REPLACES the whole announcement, so setting it would silence the label
    /// and the control type along with it; `ItemStatus` is announced in addition
    /// to them and is updated when the state changes, which is what a value is.
    ///
    /// 目前的值,透過 `ItemStatus`。
    ///
    /// **用 `ItemStatus`,不是 `FullDescription`**,而兩者容易混淆,因為它們都是閱讀器會唸出來的字串。
    /// `FullDescription` 會**取代整段**播報,因此設定它會連帶讓標籤與控制項類型一起消音;
    /// `ItemStatus` 則是在它們**之外**被播報,並在狀態改變時更新——而那正是「值」的意思。
    public func setAccessibilityValue(ofWidget widget: Widget, to value: String?) {
        AutomationProperties.setItemStatus(widget, value ?? "")
    }

    /// Removes the widget from the accessibility tree, or puts it back.
    ///
    /// `.raw` is the level BELOW `.content` and `.control`: an element there is
    /// still in the raw tree for tooling, and is skipped by the views a screen
    /// reader walks. That is what "hidden" means here -- not deleted, not
    /// invisible on screen, just not announced.
    ///
    /// 把這個 widget 移出無障礙樹,或放回去。
    ///
    /// `.raw` 是低於 `.content` 與 `.control` 的層級:位於該層的元素仍留在供工具使用的 raw tree 中,
    /// 而會被螢幕閱讀器所走訪的那些檢視略過。那正是此處「隱藏」的意思——不是刪除、不是在畫面上不可見,
    /// 只是不被播報。
    ///
    /// **The whole subtree, not the element.** `AccessibilityView` applies to
    /// the element it is set on, and UIA promotes that element's children into
    /// the control view. Measured 2026-09-17 on P69: the in-process readback
    /// showed the hidden Canvas as `raw`, and the out-of-process dump still had
    /// `text 'decorative'` in the control and content views. The earlier
    /// verification read only the first of those two.
    ///
    /// This runs on every layout pass, so a child added later is covered on the
    /// next pass. Unhiding CLEARS the value rather than writing `.content`. Some
    /// elements default to raw -- this tree's ContentPresenters read back as
    /// raw with nothing setting them -- and writing `.content` would expose
    /// template plumbing that was never announced.
    ///
    /// **整個子樹,而不是那一個元素。** `AccessibilityView` 只作用於被設定的那個元素,而 UIA 會把
    /// 它的子節點提升進 control view。2026-09-17 以 P69 實測:行程內讀回顯示被隱藏的 Canvas 為 `raw`,
    /// 而行程外的 dump 在 control 與 content view 裡仍有 `text 'decorative'`。先前的驗證只讀了前者。
    ///
    /// 這在每一次 layout pass 都會執行,所以之後加入的子節點會在下一次 pass 被涵蓋。取消隱藏時是
    /// **清除**該值,而不是寫入 `.content`:有些元素預設就是 raw(本樹的 ContentPresenter 沒有被任何
    /// 東西設定,讀回卻是 raw),寫入 `.content` 會把從未被播報的 template 管路暴露出來。
    public func setAccessibilityHidden(ofWidget widget: Widget, to hidden: Bool) {
        setAccessibilityView(ofSubtree: widget, hidden: hidden)
    }

    private func setAccessibilityView(ofSubtree element: WinUI.UIElement, hidden: Bool) {
        if hidden {
            AutomationProperties.setAccessibilityView(element, .raw)
        } else {
            try? element.clearValue(AutomationProperties.accessibilityViewProperty)
        }
        for child in scuiChildren(of: element) {
            setAccessibilityView(ofSubtree: child, hidden: hidden)
        }
    }
}
