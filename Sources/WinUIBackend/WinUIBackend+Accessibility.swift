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
    public func setAccessibilityLabel(ofWidget widget: Widget, to label: String?) {
        AutomationProperties.setName(widget, label ?? "")
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
    public func setAccessibilityHidden(ofWidget widget: Widget, to hidden: Bool) {
        AutomationProperties.setAccessibilityView(widget, hidden ? .raw : .content)
    }
}
