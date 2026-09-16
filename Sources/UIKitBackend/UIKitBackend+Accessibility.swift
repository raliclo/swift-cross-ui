import SwiftCrossUI
import UIKit

extension UIKitBackend: BackendFeatures.Accessibility {
    /// Sets the label on the widget's view AND on the control inside it.
    ///
    /// The reason is the same one `AppKitBackend+Accessibility.swift` records at
    /// length: a SwiftCrossUI widget is usually a `UIView` wrapping the control
    /// VoiceOver actually lands on, so a label written only on the wrapper is a
    /// label on something VoiceOver never visits.
    ///
    /// **Where UIKit differs from AppKit is the default.** Every `UIView` starts
    /// with `isAccessibilityElement == false` unless it is a control, so
    /// "elements beneath me" cannot be found by filtering on that flag the way
    /// the AppKit version does -- on iOS a plain wrapper and a hidden view look
    /// identical through it. This walks for a `UIControl` or a `UILabel`
    /// instead: the two kinds of subview that carry a spoken name.
    ///
    /// 把標籤同時設在這個 widget 的 view **以及**它裡面的控制項上。
    ///
    /// 理由與 `AppKitBackend+Accessibility.swift` 詳細記載的相同:一個 SwiftCrossUI 的 widget 通常是
    /// 一個 `UIView`,包著 VoiceOver 真正會落在其上的那個控制項;因此只寫在外層包裝上的標籤,是寫在
    /// 一個 VoiceOver 從不造訪的東西上。
    ///
    /// **UIKit 與 AppKit 不同之處在預設值。** 每一個 `UIView` 的 `isAccessibilityElement` 一開始都是
    /// `false`(除非它是 control),因此無法像 AppKit 那一版那樣、靠過濾這個旗標來找出「我底下的元素」
    /// ——在 iOS 上,一個單純的包裝與一個被隱藏的 view,透過它看起來一模一樣。這裡改為尋找 `UIControl`
    /// 或 `UILabel`:那是兩種帶有「可被唸出之名稱」的子 view。
    public func setAccessibilityLabel(ofWidget widget: Widget, to label: String?) {
        widget.view.accessibilityLabel = label
        namedChild(of: widget.view)?.accessibilityLabel = label
    }

    public func setAccessibilityHint(ofWidget widget: Widget, to hint: String?) {
        widget.view.accessibilityHint = hint
        namedChild(of: widget.view)?.accessibilityHint = hint
    }

    public func setAccessibilityValue(ofWidget widget: Widget, to value: String?) {
        widget.view.accessibilityValue = value
        namedChild(of: widget.view)?.accessibilityValue = value
    }

    /// Hides the view and its subtree.
    ///
    /// `accessibilityElementsHidden` already covers the subtree -- that is the
    /// difference between it and `isAccessibilityElement`, and it is why this
    /// one does not have to walk the tree the way AppKit's does.
    ///
    /// 隱藏這個 view 及其子樹。
    ///
    /// `accessibilityElementsHidden` 本身就涵蓋整棵子樹——那正是它與 `isAccessibilityElement` 的差別,
    /// 也是這一個不必像 AppKit 那一版那樣走訪整棵樹的原因。
    public func setAccessibilityHidden(ofWidget widget: Widget, to hidden: Bool) {
        widget.view.accessibilityElementsHidden = hidden
    }

    /// The one subview that carries a spoken name, or `nil`.
    ///
    /// `nil` when there are none and when there are several, for the reason the
    /// AppKit version gives: with two or more there is no way to tell which was
    /// meant, and guessing puts the label on the wrong one silently.
    /// 唯一帶有「可被唸出之名稱」的子 view;若無則為 `nil`。
    ///
    /// 沒有時為 `nil`,有多個時也為 `nil`,理由同 AppKit 那一版:有兩個以上時無從判斷指的是哪一個,
    /// 而猜測會靜默地把標籤放到錯的那一個上。
    private func namedChild(of view: UIView) -> UIView? {
        var found: UIView?
        for subview in view.subviews {
            let candidate: UIView? =
                (subview is UIControl || subview is UILabel)
                ? subview
                : namedChild(of: subview)
            guard let candidate else { continue }
            if found != nil { return nil }
            found = candidate
        }
        return found
    }
}
