import CWinRT
import Foundation
@_spi(Backends) import SwiftCrossUI
@_spi(WinRTInternal) import WinUI
@_spi(WinRTInternal) import WindowsFoundation

extension WinUIBackend: BackendFeatures.FocusEffects, BackendFeatures.FocusDisabledContainers {
    /// `UseSystemFocusVisuals = false` on the widget and the elements it is
    /// made of, and the ring a `.focusable()` target draws itself kept hidden.
    ///
    /// The walk stops at an element another node was given (see
    /// ``BackendFeatures/FocusEffects``), so a `.focusEffectDisabled(false)`
    /// further in is not undone by an outer node applying after it.
    ///
    /// Restoring clears the local value instead of writing `true`: what comes
    /// back is the control's style value, which is what the widget had, since
    /// this backend sets `UseSystemFocusVisuals` nowhere else.
    ///
    /// 在 widget 與組成它的元素上設 `UseSystemFocusVisuals = false`,並讓 `.focusable()` target 自己畫的焦點環保持隱藏。
    /// 走訪在已交給另一個節點的元素停下(見 ``BackendFeatures/FocusEffects``),所以更內層的 `.focusEffectDisabled(false)`
    /// 不會被之後才套用的外層節點蓋掉。還原時清掉本地值，而不是寫入 `true`:回來的是控制項樣式裡的值，也就是 widget 原本的值，
    /// 因為本 backend 在別處都不設 `UseSystemFocusVisuals`。
    public func setFocusEffectDisabled(_ disabled: Bool, on widget: Widget) {
        WinUIFocusMarks.markNode(widget)
        Self.applyFocusEffect(disabled, to: widget, isRoot: true)
    }

    private static func applyFocusEffect(_ disabled: Bool, to element: UIElement, isRoot: Bool) {
        if !isRoot, WinUIFocusMarks.isNode(element) { return }
        if disabled {
            element.useSystemFocusVisuals = false
        } else {
            try? element.clearValue(UIElement.useSystemFocusVisualsProperty)
        }
        if let target = element as? WinUIFeatureTarget, target.isFocusableTarget {
            target.focusEffectDisabled = disabled
            target.focusRing?.visibility =
                !disabled && WinUIFocusMarks.holdsFocus(target) ? .visible : .collapsed
        }
        forEachChild(of: element) { applyFocusEffect(disabled, to: $0, isRoot: false) }
    }

    /// Marks the container so that nothing inside it takes the focus: Tab,
    /// a press and `.focused` are all refused.
    ///
    /// `IsTabStop = false` on the container alone does NOT do it: a panel's
    /// tab stop is its own, and its children stay tab stops. So three parts:
    /// - Tab: every element inside is taken out of the tab order
    ///   (`IsTabStop = false`), so Tab steps over the subtree rather than
    ///   stopping in front of it. Unmarking clears the local value, or, on a
    ///   `.focusable()` target, puts back the value the target keeps for itself.
    /// - Everything else: `GettingFocus` on the container, a routed event
    ///   raised for any element inside, is cancelled. That covers a press and a
    ///   focus from code, and a control added to the subtree after the walk:
    ///   that one is walked then, and a Tab that reached it carries on.
    /// - ``focus(_:)`` answers false for an element inside before it asks.
    ///
    /// 標記容器，讓其中任何東西都取不到焦點:Tab、按下與 `.focused` 全部被拒絕。只在容器上設 `IsTabStop = false` **沒有用**:
    /// panel 的 tab stop 只管它自己，子元素仍是 tab stop。所以分三部分:
    /// - Tab:把其中每個元素移出 Tab 順序(`IsTabStop = false`),Tab 才會跨過子樹，而不是停在它前面。取消標記時清掉本地值;
    ///   若是 `.focusable()` target,則放回 target 自己保存的值。
    /// - 其他一切：在容器上取消 `GettingFocus`;這是 routed event,其中任何元素都會引發。這涵蓋了按下與程式聚焦，也涵蓋走訪之後
    ///   才加進子樹的控制項：那時才走訪它，而到達它的 Tab 會繼續往前。
    /// - ``focus(_:)`` 對其中的元素在詢問之前就回答 false。
    public func setFocusDisabled(_ disabled: Bool, onContainer container: Widget) {
        WinUIFocusMarks.setExcluding(container, disabled)
        Self.subscribeGettingFocus(container)
        Self.applyTabStops(disabled, in: container, isRoot: true)
        guard disabled, let root = container.xamlRoot,
            let focused = try? FocusManager.getFocusedElement(root) as? DependencyObject,
            WinUIFocusMarks.excludes(focused)
        else { return }
        // Marking a container that holds the focus moves the focus out, to the
        // root, as unfocus(_:) does. 標記一個持有焦點的容器會把焦點移出去，移到 root,與 unfocus(_:) 相同。
        _ = try? root.content?.focus(.programmatic)
    }

    static func applyTabStops(_ disabled: Bool, in element: UIElement, isRoot: Bool) {
        // An inner container still marked keeps its subtree out when an outer
        // one is unmarked. 外層取消標記時，仍被標記的內層容器讓它的子樹維持排除。
        if !isRoot, !disabled, WinUIFocusMarks.isExcluding(element) { return }
        if let target = element as? WinUIFeatureTarget, target.isFocusableTarget {
            target.isTabStop = disabled ? false : target.focusableWanted
        } else if disabled {
            if element.isTabStop {
                element.isTabStop = false
                WinUIFocusMarks.noteTabStopCleared(element)
            }
        } else if WinUIFocusMarks.takeTabStopCleared(element) {
            try? element.clearValue(UIElement.isTabStopProperty)
        }
        forEachChild(of: element) { applyTabStops(disabled, in: $0, isRoot: false) }
    }

    private static func subscribeGettingFocus(_ container: Widget) {
        guard WinUIFocusMarks.firstSubscription(container) else { return }
        container.gettingFocus.addHandler { [weak container] _, args in
            guard let container, let args, WinUIFocusMarks.isExcluding(container),
                let new = args.newFocusedElement, WinUIFocusMarks.excludes(new)
            else { return }
            if !((try? args.tryCancel()) ?? false) {
                args.cancel = true
            }
            // Something inside was still a tab stop, so it came after the walk:
            // walk again, and let a Tab carry on past the subtree.
            // 其中仍有 tab stop,表示它是走訪之後才加進來的：再走訪一次，並讓 Tab 越過子樹繼續往前。
            applyTabStops(true, in: container, isRoot: true)
            let direction = args.direction
            guard args.focusState == .keyboard, direction == .next || direction == .previous else {
                return
            }
            DispatchQueue.main.async { [weak container] in
                guard let root = container?.xamlRoot?.content else { return }
                let options = FindNextElementOptions()
                options.searchRoot = root
                _ = try? FocusManager.tryMoveFocus(direction, options)
            }
        }
    }

    private static func forEachChild(of element: UIElement, _ body: (UIElement) -> Void) {
        let count = (try? VisualTreeHelper.getChildrenCount(element)) ?? 0
        for index in 0..<count {
            if let child = try? VisualTreeHelper.getChild(element, index) as? UIElement {
                body(child)
            }
        }
    }
}

/// Marks keyed by the element's COM identity (its IUnknown pointer): a
/// projected element's Swift wrapper is not stable, so an element reached by
/// walking the visual tree may come back as a different Swift object. Nodes
/// and containers are held weakly through the Swift object the view graph
/// keeps, so a mark goes away with its widget and a reused address cannot
/// inherit one.
///
/// 以元素的 COM identity(它的 IUnknown 指標)為鍵的標記：投影元素的 Swift 包裝並不穩定，走訪 visual tree 得到的元素可能是
/// 另一個 Swift 物件。節點與容器透過 view graph 所保有的 Swift 物件以弱參考持有，所以標記會隨 widget 消失，重複使用的位址
/// 不會繼承到它。
@MainActor
enum WinUIFocusMarks {
    private final class WeakElement {
        weak var element: UIElement?
        init(_ element: UIElement) { self.element = element }
    }

    private static var nodes: [UInt: WeakElement] = [:]
    private static var excluding: [UInt: WeakElement] = [:]
    private static var subscribed: [UInt: WeakElement] = [:]
    /// Elements whose `IsTabStop` this file set to false.
    /// 被這個檔案把 `IsTabStop` 設成 false 的元素。
    private static var tabStopsCleared: Set<UInt> = []

    static func identity(_ object: DependencyObject) -> UInt? {
        let pointer: UnsafeMutablePointer<C_IInspectable>? = object._getABI()
        guard let pointer else { return nil }
        var iid = WindowsFoundation.IUnknown.IID
        var result: UnsafeMutableRawPointer?
        guard pointer.pointee.lpVtbl.pointee.QueryInterface(pointer, &iid, &result) >= 0,
            let result
        else { return nil }
        let unknown = result.assumingMemoryBound(to: C_IUnknown.self)
        _ = unknown.pointee.lpVtbl.pointee.Release(unknown)
        return UInt(bitPattern: result)
    }

    private static func isLive(_ table: [UInt: WeakElement], _ id: UInt) -> Bool {
        guard let element = table[id]?.element else { return false }
        return identity(element) == id
    }

    private static func prune(_ table: inout [UInt: WeakElement]) {
        table = table.filter { $0.value.element != nil }
    }

    static func markNode(_ widget: UIElement) {
        guard let id = identity(widget) else { return }
        prune(&nodes)
        nodes[id] = WeakElement(widget)
    }

    static func isNode(_ element: UIElement) -> Bool {
        guard let id = identity(element) else { return false }
        return isLive(nodes, id)
    }

    static func setExcluding(_ container: UIElement, _ marked: Bool) {
        guard let id = identity(container) else { return }
        prune(&excluding)
        excluding[id] = marked ? WeakElement(container) : nil
    }

    static func isExcluding(_ element: UIElement) -> Bool {
        guard let id = identity(element) else { return false }
        return isLive(excluding, id)
    }

    /// Whether `object` sits in a `.focusDisabled` subtree, itself included.
    /// `object` 是否位於 `.focusDisabled` 子樹中(含它自己)。
    static func excludes(_ object: DependencyObject) -> Bool {
        guard !excluding.isEmpty else { return false }
        var current: DependencyObject? = object
        while let element = current {
            if let id = identity(element), isLive(excluding, id) { return true }
            current = try? VisualTreeHelper.getParent(element)
        }
        return false
    }

    /// True the first time for a given container, false after.
    /// 對同一個容器第一次回傳 true,之後回傳 false。
    static func firstSubscription(_ container: UIElement) -> Bool {
        guard let id = identity(container) else { return false }
        if isLive(subscribed, id) { return false }
        prune(&subscribed)
        subscribed[id] = WeakElement(container)
        return true
    }

    static func noteTabStopCleared(_ element: UIElement) {
        if let id = identity(element) { tabStopsCleared.insert(id) }
    }

    static func takeTabStopCleared(_ element: UIElement) -> Bool {
        guard let id = identity(element) else { return false }
        return tabStopsCleared.remove(id) != nil
    }

    /// Whether `element` itself (not something inside it) holds the focus.
    /// `element` 本身(而不是其中某個東西)是否持有焦點。
    static func holdsFocus(_ element: UIElement) -> Bool {
        guard let root = element.xamlRoot,
            let focused = try? FocusManager.getFocusedElement(root) as? DependencyObject
        else { return false }
        return identity(focused) == identity(element)
    }
}
