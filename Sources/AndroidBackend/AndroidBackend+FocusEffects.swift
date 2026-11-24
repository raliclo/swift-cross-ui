import AndroidKit
import SwiftCrossUI
import SwiftJava

extension AndroidBackend: BackendFeatures.FocusEffects, BackendFeatures.FocusDisabledContainers {
    /// `setDefaultFocusHighlightEnabled` (API 26) on the widget and every view
    /// in it. The default highlight is what Android draws around a focused view
    /// that has no focused state of its own -- a `.focusable()` target, a
    /// button reached by Tab -- and `true` is its default, so restoring is
    /// setting `true`.
    ///
    /// **The walk does not stop at another node's view, unlike AppKit, UIKit
    /// and GTK**: a Java view has no place to keep that mark without an app
    /// resource id. The consequence is narrow: an outer setting that changes
    /// while a view further in keeps an opposite `.focusEffectDisabled` lets
    /// the outer one win for that view until the inner one changes.
    ///
    /// 在 widget 及其中每個 view 上呼叫 `setDefaultFocusHighlightEnabled`(API 26)。預設 highlight 是 Android 在「自身
    /// 沒有聚焦狀態」的已聚焦 view(`.focusable()` target、以 Tab 到達的按鈕)周圍畫的東西，預設為 `true`,所以還原就是設
    /// `true`。**走訪不會在另一個節點的 view 停下，這點與 AppKit、UIKit、GTK 不同**:Java view 沒有 app 資源 id 就沒有地方
    /// 存那個標記。影響很窄：外層設定改變、而更內層有個相反的 `.focusEffectDisabled` 維持不變時，那個 view 會由外層勝出，
    /// 直到內層改變為止。
    public func setFocusEffectDisabled(_ disabled: Bool, on widget: Widget) {
        applyFocusEffect(enabled: !disabled, to: widget)
    }

    private func applyFocusEffect(enabled: Bool, to view: AndroidKit.View) {
        view.setDefaultFocusHighlightEnabled(enabled)
        guard let group = view.as(AndroidKit.ViewGroup.self) else { return }
        for index in 0..<group.getChildCount() {
            if let child = group.getChildAt(index) {
                applyFocusEffect(enabled: enabled, to: child)
            }
        }
    }

    /// `FOCUS_BLOCK_DESCENDANTS` on the container: the focus search behind Tab
    /// and the arrow keys skips its children, and `requestFocus` on one of them
    /// -- a tap, `.focused` -- is refused. `FOCUS_BEFORE_DESCENDANTS`, the
    /// `ViewGroup` default that `CustomContainer` keeps, when unmarked.
    ///
    /// 在容器上設 `FOCUS_BLOCK_DESCENDANTS`:Tab 與方向鍵背後的焦點搜尋會跳過它的子 view,對其中之一的 `requestFocus`
    /// (點按、`.focused`)會被拒絕。取消標記時設回 `FOCUS_BEFORE_DESCENDANTS`,即 `CustomContainer` 保留的 `ViewGroup` 預設值。
    public func setFocusDisabled(_ disabled: Bool, onContainer container: Widget) {
        guard let group = container.as(AndroidKit.ViewGroup.self) else { return }
        // android.view.ViewGroup constants, the same on every API level.
        // android.view.ViewGroup 的常數，各 API 層級相同。
        let focusBeforeDescendants: Int32 = 0x20000
        let focusBlockDescendants: Int32 = 0x60000
        let wanted = disabled ? focusBlockDescendants : focusBeforeDescendants
        if group.getDescendantFocusability() != wanted {
            group.setDescendantFocusability(wanted)
        }
        if disabled, group.hasFocus(), let focused = group.findFocus() {
            focused.clearFocus()
        }
    }
}
