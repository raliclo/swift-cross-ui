import ObjectiveC
import SwiftCrossUI
import UIKit

extension UIKitBackend: BackendFeatures.FocusEffects, BackendFeatures.FocusDisabledContainers {
    /// `focusEffect = nil` (iOS 15) on the widget and the views it is made of,
    /// and no ring on a `.focusable()` target, which draws its own.
    ///
    /// The walk stops at a view another node was given, as on AppKit.
    ///
    /// 在 widget 與組成它的 view 上設 `focusEffect = nil`(iOS 15),並讓自己畫焦點環的 `.focusable()` target 不畫。
    /// 走訪與 AppKit 相同，在已交給另一個節點的 view 停下。
    public func setFocusEffectDisabled(_ disabled: Bool, on widget: Widget) {
        UIKitFocusMarks.markNode(widget.view)
        applyFocusEffect(disabled, to: widget.view, isRoot: true)
    }

    private func applyFocusEffect(_ disabled: Bool, to view: UIView, isRoot: Bool) {
        if !isRoot, UIKitFocusMarks.isNode(view) { return }
        if let target = view as? FocusableView {
            target.showsFocusRing = !disabled
        }
        #if !os(tvOS)
            if #available(iOS 15, macCatalyst 15, *) {
                let original = UIKitFocusMarks.originalFocusEffect(of: view)
                view.focusEffect = disabled ? nil : original
            }
        #endif
        for subview in view.subviews {
            applyFocusEffect(disabled, to: subview, isRoot: false)
        }
    }

    /// Marks the container. Its text fields then refuse to begin editing, a
    /// `.focusable()` target in it refuses first responder and focus, and the
    /// Tab of a target outside steps over it.
    ///
    /// 標記容器。之後其中的文字欄位拒絕開始編輯，其中的 `.focusable()` target 拒絕 first responder 與焦點，外面 target 的 Tab
    /// 會跨過它。
    public func setFocusDisabled(_ disabled: Bool, onContainer container: Widget) {
        UIKitFocusMarks.setExcluding(container.view, disabled)
        guard disabled, let responder = UIKitFocusMarks.firstResponder(in: container.view) else {
            return
        }
        responder.resignFirstResponder()
    }
}

/// Marks kept on the views themselves as associated objects.
/// 以 associated object 存在 view 本身上的標記。
@MainActor
enum UIKitFocusMarks {
    nonisolated(unsafe) private static var nodeKey: UInt8 = 0
    nonisolated(unsafe) private static var effectKey: UInt8 = 0
    nonisolated(unsafe) private static var excludingKey: UInt8 = 0

    /// Holds a focus effect that may be nil, which an associated object alone
    /// cannot tell from "not saved yet".
    /// 裝一個可能是 nil 的 focus effect;單靠 associated object 分不出它與「還沒存過」。
    private final class SavedEffect {
        let effect: AnyObject?
        init(_ effect: AnyObject?) { self.effect = effect }
    }

    static func markNode(_ view: UIView) {
        objc_setAssociatedObject(view, &nodeKey, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    static func isNode(_ view: UIView) -> Bool {
        objc_getAssociatedObject(view, &nodeKey) != nil
    }

    #if !os(tvOS)
        @available(iOS 15, macCatalyst 15, *)
        static func originalFocusEffect(of view: UIView) -> UIFocusEffect? {
            if let saved = objc_getAssociatedObject(view, &effectKey) as? SavedEffect {
                return saved.effect as? UIFocusEffect
            }
            let original = view.focusEffect
            objc_setAssociatedObject(
                view, &effectKey, SavedEffect(original), .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
            return original
        }
    #endif

    static func setExcluding(_ container: UIView, _ excluding: Bool) {
        objc_setAssociatedObject(
            container, &excludingKey, excluding ? true : nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    /// Whether `view` is itself a marked container.
    /// `view` 本身是否為被標記的容器。
    static func isExcluding(_ view: UIView) -> Bool {
        objc_getAssociatedObject(view, &excludingKey) != nil
    }

    /// Whether `view` sits in a `.focusDisabled` subtree.
    /// `view` 是否位於 `.focusDisabled` 子樹中。
    static func excludes(_ view: UIView) -> Bool {
        var current: UIView? = view
        while let candidate = current {
            if isExcluding(candidate) { return true }
            current = candidate.superview
        }
        return false
    }

    static func firstResponder(in view: UIView) -> UIView? {
        if view.isFirstResponder { return view }
        for subview in view.subviews {
            if let found = firstResponder(in: subview) { return found }
        }
        return nil
    }
}
