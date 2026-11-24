import AppKit
import SwiftCrossUI

extension AppKitBackend: BackendFeatures.FocusEffects, BackendFeatures.FocusDisabledContainers {
    /// `focusRingType = .none` on the widget and the views it is made of.
    ///
    /// The walk stops at a view another node was given (see
    /// ``BackendFeatures/FocusEffects``), so a `.focusEffectDisabled(false)`
    /// further in is not undone by an outer node applying after it.
    ///
    /// 在 widget 與組成它的 view 上設 `focusRingType = .none`。走訪在已交給另一個節點的 view 停下(見
    /// ``BackendFeatures/FocusEffects``),所以更內層的 `.focusEffectDisabled(false)` 不會被之後才套用的外層節點蓋掉。
    public func setFocusEffectDisabled(_ disabled: Bool, on widget: NSView) {
        AppKitFocusMarks.markNode(widget)
        applyFocusEffect(disabled, to: widget, isRoot: true)
    }

    private func applyFocusEffect(_ disabled: Bool, to view: NSView, isRoot: Bool) {
        if !isRoot, AppKitFocusMarks.isNode(view) { return }
        let original = AppKitFocusMarks.originalRingType(of: view)
        let wanted: NSFocusRingType = disabled ? .none : original
        if view.focusRingType != wanted {
            view.focusRingType = wanted
            view.noteFocusRingMaskChanged()
        }
        for subview in view.subviews {
            applyFocusEffect(disabled, to: subview, isRoot: false)
        }
    }

    /// Marks the container; ``NSCustomWindow`` then refuses first responder to
    /// anything inside it and steps Tab over it.
    ///
    /// A mark on the container rather than a property on each control, because
    /// controls added to the subtree later must be covered too, and the window
    /// is the one place every way of taking the focus passes through:
    /// `makeFirstResponder` for a click, for `.focused` and for Tab.
    ///
    /// 標記容器;之後 ``NSCustomWindow`` 會拒絕把 first responder 給其中的任何東西，並讓 Tab 跨過它。標記在容器上，而不是在
    /// 每個控制項上設屬性，因為之後才加進子樹的控制項也必須涵蓋;而視窗是每一種取得焦點的方式都會經過的地方:點擊、`.focused`
    /// 與 Tab 都經過 `makeFirstResponder`。
    public func setFocusDisabled(_ disabled: Bool, onContainer container: NSView) {
        AppKitFocusMarks.setExcluding(container, disabled)
        guard disabled, let window = container.window,
            let responder = window.firstResponder as? NSView,
            AppKitFocusMarks.excludes(responder)
        else { return }
        window.makeFirstResponder(nil)
    }
}

/// Marks kept on the views themselves, as associated objects, so that they go
/// away with the view and a reused address cannot inherit one.
/// 標記以 associated object 存在 view 本身上，隨 view 一起消失，重複使用的位址不會繼承到它。
@MainActor
enum AppKitFocusMarks {
    nonisolated(unsafe) private static var nodeKey: UInt8 = 0
    nonisolated(unsafe) private static var ringKey: UInt8 = 0
    nonisolated(unsafe) private static var excludingKey: UInt8 = 0

    static func markNode(_ view: NSView) {
        objc_setAssociatedObject(view, &nodeKey, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    static func isNode(_ view: NSView) -> Bool {
        objc_getAssociatedObject(view, &nodeKey) != nil
    }

    /// The ring type the view had before this file first changed it.
    /// 這個檔案第一次改動之前，view 原本的焦點環類型。
    static func originalRingType(of view: NSView) -> NSFocusRingType {
        if let saved = objc_getAssociatedObject(view, &ringKey) as? UInt {
            return NSFocusRingType(rawValue: saved) ?? .default
        }
        let original = view.focusRingType
        objc_setAssociatedObject(
            view, &ringKey, original.rawValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        return original
    }

    static func setExcluding(_ container: NSView, _ excluding: Bool) {
        objc_setAssociatedObject(
            container, &excludingKey, excluding ? true : nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    /// Whether `responder` sits in a `.focusDisabled` subtree. A field editor
    /// is a subview of the text field it edits, so it is covered too.
    /// `responder` 是否位於 `.focusDisabled` 子樹中。field editor 是它所編輯之文字欄位的子 view,所以也涵蓋在內。
    static func excludes(_ responder: NSResponder) -> Bool {
        var view = responder as? NSView
        while let current = view {
            if objc_getAssociatedObject(current, &excludingKey) != nil { return true }
            view = current.superview
        }
        return false
    }

    /// The last key view in the run of excluded ones that follows (or precedes)
    /// `view`, or `view` itself; selecting the key view after it lands past
    /// the excluded subtree.
    /// 緊接在 `view` 之後(或之前)那一串被排除 key view 中的最後一個，沒有則為 `view` 本身;選它之後的那個 key view,
    /// 就會落在被排除的子樹之外。
    static func lastExcluded(from view: NSView, forward: Bool) -> NSView {
        var current = view
        var seen: Set<ObjectIdentifier> = [ObjectIdentifier(view)]
        while let next = forward ? current.nextValidKeyView : current.previousValidKeyView,
            excludes(next),
            seen.insert(ObjectIdentifier(next)).inserted
        {
            current = next
        }
        return current
    }
}

extension NSCustomWindow {
    /// Refuses first responder inside a `.focusDisabled` subtree: a click, a
    /// `.focused` request and Tab all come through here.
    /// 拒絕把 first responder 給 `.focusDisabled` 子樹內的東西:點擊、`.focused` 要求與 Tab 都經過這裡。
    public override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        if let responder, AppKitFocusMarks.excludes(responder) { return false }
        return super.makeFirstResponder(responder)
    }

    /// Tab: steps over a `.focusDisabled` subtree instead of stopping at it.
    /// Refusing in `makeFirstResponder` alone would leave Tab stuck in front
    /// of the subtree, not past it.
    /// Tab:跨過 `.focusDisabled` 子樹，而不是停在它前面。只靠 `makeFirstResponder` 拒絕，Tab 會卡在子樹前面，而不是越過它。
    public override func selectKeyView(following view: NSView) {
        super.selectKeyView(following: AppKitFocusMarks.lastExcluded(from: view, forward: true))
    }

    /// Shift-Tab, the same way back. Shift-Tab,反方向相同。
    public override func selectKeyView(preceding view: NSView) {
        super.selectKeyView(preceding: AppKitFocusMarks.lastExcluded(from: view, forward: false))
    }
}
