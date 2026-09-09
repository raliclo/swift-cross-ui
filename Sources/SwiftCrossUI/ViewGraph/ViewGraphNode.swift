import Foundation

/// A view graph node storing a view, its widget, and its children (likely a
/// collection of more nodes).
///
/// This is where updates are initiated when a view's state updates, and where state is persisted
/// even when a view gets recomputed by its parent.
@MainActor
public class ViewGraphNode<NodeView: View, Backend: BaseAppBackend>: Sendable {
    /// The view's single widget for the entirety of its lifetime in the view graph.
    ///
    public var widget: Backend.Widget {
        _widget!
    }
    /// Only optional because of some initialisation order requirements. Private and wrapped to
    /// hide this inconvenient detail.
    private var _widget: Backend.Widget?
    /// The view's children (usually just contains more view graph nodes, but can handle extra logic
    /// such as figuring out how to update variable length array of children efficiently).
    ///
    /// It's type-erased because otherwise complex implementation details would
    /// be forced to the user or other compromises would have to be made. I
    /// believe that this is the best option with Swift's current generics landscape.
    public var children: any ViewGraphNodeChildren {
        get {
            _children!
        }
        set {
            _children = newValue
        }
    }
    /// Only optional because of some initialisation order requirements. Private and wrapped to
    /// hide this inconvenient detail.
    private var _children: (any ViewGraphNodeChildren)?
    /// A copy of the view itself (from the latest computed body of its parent).
    public var view: NodeView
    /// The backend used to create the view's widget.
    public var backend: Backend

    /// The view's most recently computed layout. Doesn't include cached layouts,
    /// as this is the layout that is currently 'ready to commit'.
    public var currentLayout: ViewLayoutResult?
    /// A cache of update results keyed by the proposed size they were for. Gets
    /// cleared before the results' sizes become invalid.
    var resultCache: [ProposedViewSize: ViewLayoutResult]
    /// The most recent size proposed by the parent view. Used when updating the wrapped
    /// view as a result of a state change rather than the parent view updating. Proposals
    /// that get cached responses don't update this size, as this size should stay in sync
    /// with currentLayout.
    private(set) var lastProposedSize: ProposedViewSize
    /// Whether the widget has had its first update yet.
    private var hasHadFirstUpdate = false

    /// A cancellable handle to the view's state property observations.
    private var cancellables: [Cancellable]

    /// The environment most recently provided by this node's parent.
    private var parentEnvironment: EnvironmentValues

    /// The dynamic property updater for this view.
    private var dynamicPropertyUpdater: DynamicPropertyUpdater<NodeView>

    /// Creates a node for a given view while also creating the nodes for its children, creating
    /// the view's widget, and starting to observe its state for changes.
    public init(
        for nodeView: NodeView,
        backend: Backend,
        snapshot: ViewGraphSnapshotter.NodeSnapshot? = nil,
        environment: EnvironmentValues
    ) {
        self.backend = backend

        // Restore node snapshot if present.
        self.view = nodeView
        snapshot?.restore(to: view)

        // First create the view's child nodes and widgets
        let childSnapshots = snapshot.map { snapshot in
            snapshot.isValid(for: NodeView.self) ? snapshot.children : [snapshot]
        }

        currentLayout = nil
        resultCache = [:]
        lastProposedSize = .zero
        parentEnvironment = environment
        cancellables = []

        dynamicPropertyUpdater = DynamicPropertyUpdater(for: nodeView)

        let viewEnvironment = updateEnvironment(environment)

        dynamicPropertyUpdater.update(view, with: viewEnvironment, previousValue: nil)

        let children = view.children(
            backend: backend,
            snapshots: childSnapshots,
            environment: viewEnvironment
        )
        self.children = children

        // Then create the widget for the view itself
        let widget = view.asWidget(
            children,
            backend: backend
        )
        _widget = widget

        let tag = String(String(describing: NodeView.self).split(separator: "<")[0])
        backend.tag(widget: widget, as: tag)

        // Update the view and its children when state changes (children are always updated first).
        forEachField(of: view) { name, _, fieldValue in
            // Ungated, for the same reason as the `App.state` notice in
            // `_App.swift`: a view whose `state` is no longer observed compiles
            // and then stops updating, and `#if DEBUG` kept the explanation out
            // of the release builds this project makes by default. This one runs
            // per node creation rather than once, but the check is a string
            // compare inside a reflection walk that happens anyway, and the
            // warning itself only fires on code that is already broken.
            //
            // 不設條件，理由與 `_App.swift` 中的 `App.state` 提示相同：一個 `state` 不再被觀察的
            // view 能夠編譯，然後就此停止更新，而 `#if DEBUG` 使這段說明不存在於本專案預設產生的
            // release 建置中。此處是每次建立節點時執行、而非只執行一次，但該檢查只是一趟本來就
            // 會發生的 reflection 走訪中的一次字串比較，而警告本身也只會對已經壞掉的程式碼觸發。
            if name == "state", fieldValue is ObservableObject {
                logger.warning(
                    """
                    the View.state protocol requirement has been removed in favour of \
                    SwiftUI-style @State annotations; decorate \(NodeView.self).state \
                    with the @State property wrapper to restore previous behaviour
                    """
                )
            }

            guard let value = fieldValue as? any ObservableProperty else {
                return // i.e. continue
            }

            let cancellable = value.didChange.observeAsUIUpdater(backend: backend) { [weak self] in
                self?.bottomUpUpdate()
            }
            cancellables.append(cancellable)
        }
    }

    /// Triggers the view to be updated as part of a bottom-up chain of updates (where either the
    /// current view gets updated due to a state change and has potential to trigger its parent to
    /// update as well, or the current view's child has propagated such an update upwards).
    /// What this node last told the window it was drawing.
    ///
    /// `nil` until the first bottom-up update, so the first comparison cannot
    /// fire spuriously against a value the window already applied at launch.
    /// 這個節點上一次告訴視窗它正在繪製的東西。
    ///
    /// 在第一次 bottom-up 更新之前為 `nil`，因此第一次比較不會對著「視窗在啟動時早已套用的值」
    /// 誤觸發。
    private var lastWindowChromeSignature: String?

    /// The window-facing part of a set of preferences, as one comparable string.
    ///
    /// A string rather than `Equatable` on `PreferenceValues`, which cannot have
    /// it: that type holds `onOpenURL`, a closure, and closures have no equality.
    /// 把 preference 中「面向視窗」的部分壓成一個可比較的字串。
    ///
    /// 用字串而非讓 `PreferenceValues` 實作 `Equatable`——它做不到：該型別持有 `onOpenURL`，
    /// 那是一個 closure，而 closure 沒有相等性。
    private static func windowChromeSignature(of preferences: PreferenceValues) -> String {
        let title = preferences.navigationTitle ?? ""
        let toolbar = preferences.toolbarItems.map(\.label).joined(separator: "\u{1f}")
        return "\(title)\u{1e}\(toolbar)"
    }

    private func bottomUpUpdate() {
        // First we compute what size the view will be after the update. If it will change size,
        // propagate the update to this node's parent instead of updating straight away.
        let currentSize = currentLayout?.size
        let newLayout = self.computeLayout(
            proposedSize: lastProposedSize,
            environment: parentEnvironment
        )

        self.currentLayout = newLayout
        if newLayout.size != currentSize {
            resultCache[lastProposedSize] = newLayout
            parentEnvironment.onResize(newLayout.size)
        } else {
            _ = self.commit()

            // A state change that does not resize anything can still change what
            // the WINDOW draws, and before this nothing carried that upwards.
            // `.navigationTitle(someState)` wrote its first value at launch and
            // every later one was computed, stored and never read -- P50 showed
            // "TITLE B" in its body and "TITLE A" in its title bar, in one
            // screenshot, on 2026-09-10.
            //
            // Compared rather than announced unconditionally: notifying on every
            // committed state change would make each one re-lay-out the whole
            // window, which is what `onResize` costs and why it is rare. The
            // signature covers exactly what `WindowReference` applies from
            // preferences -- the title and the toolbar's labels.
            //
            // 一次不改變尺寸的狀態改變，仍然可能改變**視窗**所繪製的東西，而在此之前沒有任何東西
            // 把那件事往上帶。`.navigationTitle(某個狀態)` 在啟動時寫入了它的第一個值，其後每一個
            // 都被算出、被存下、從未被讀取——2026-09-10，P50 在同一張截圖裡內容顯示「TITLE B」、
            // 標題列顯示「TITLE A」。
            //
            // 採比較而非無條件通知：若每一次已提交的狀態改變都通知，等於讓每一次都重排整個視窗，
            // 而那正是 `onResize` 的成本、也是它罕見的原因。這個簽章涵蓋的，恰好是 `WindowReference`
            // 會從 preference 中套用的東西——標題與工具列的標籤。
            let signature = Self.windowChromeSignature(of: newLayout.preferences)
            if signature != lastWindowChromeSignature {
                lastWindowChromeSignature = signature
                parentEnvironment.onWindowChromeChange()
            }
        }
    }

    private func updateEnvironment(_ environment: EnvironmentValues) -> EnvironmentValues {
        environment.with(\.onResize) { [weak self] _ in
            guard let self else { return }
            self.bottomUpUpdate()
        }
    }

    /// Recomputes the view's body and computes its layout and the layout of
    /// its children.
    ///
    /// The view may or may not propagate the update to its children depending
    /// on the nature of the update. If `newView` is provided (in the case that
    /// the parent's body got updated) then it simply replaces the old view
    /// while inheriting the old view's state.
    ///
    /// - Parameters:
    ///   - newView: The recomputed view.
    ///   - proposedSize: The view's proposed size.
    ///   - environment: The current environment.
    /// - Returns: The result of laying out the view.
    public func computeLayout(
        with newView: NodeView? = nil,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues
    ) -> ViewLayoutResult {
        // Defensively ensure that all future scene implementations obey this
        // precondition. By putting the check here instead of only in views
        // that require `environment.window` (such as the alert modifier view),
        // we decrease the likelihood of a bug like this flying under the radar.
        precondition(
            environment.window != nil,
            "View graph updated without parent window present in environment"
        )

        if !hasHadFirstUpdate {
            // We show the widget here instead of in init, because in init the widget
            // hasn't been added to its parent widget yet.
            backend.show(widget: widget)
            hasHadFirstUpdate = true
        }

        if proposedSize == lastProposedSize && !resultCache.isEmpty
            && (!parentEnvironment.allowLayoutCaching || environment.allowLayoutCaching),
            let currentLayout
        {
            // If the previous proposal is the same as the current one, and our
            // cache hasn't been invalidated, then we can reuse the current layout.
            // But only if the previous layout was computed without caching, or the
            // current layout is being computed with caching, cause otherwise we could
            // end up using a layout computed with caching while computing a layout
            // without caching.
            return currentLayout
        } else if environment.allowLayoutCaching, let cachedResult = resultCache[proposedSize] {
            // If this layout pass is a probing pass (not a final pass), then we
            // can reuse any layouts that we've computed since the cache was last
            // cleared. The cache gets cleared on commit.
            return cachedResult
        }

        parentEnvironment = environment
        lastProposedSize = proposedSize

        let previousView: NodeView?
        if let newView {
            previousView = view
            view = newView
        } else {
            previousView = nil
        }

        let viewEnvironment = updateEnvironment(environment)

        dynamicPropertyUpdater.update(view, with: viewEnvironment, previousValue: previousView)

        let result = view.computeLayout(
            widget,
            children: children,
            proposedSize: proposedSize,
            environment: viewEnvironment,
            backend: backend
        )

        // We assume that the view's sizing behaviour won't change between consecutive
        // layout computations and the following commit, because groups of updates
        // following that pattern are assumed to be occurring within a single overarching
        // view update. Under that assumption, we can cache view layout results.
        resultCache[proposedSize] = result

        currentLayout = result
        return result
    }

    /// Commits the view's most recently computed layout and any view state changes
    /// that have occurred since the last update (e.g. text content changes or font
    /// size changes).
    ///
    /// - Returns: The most recently computed layout. Guaranteed to match the
    ///   result of the last call to ``computeLayout(with:proposedSize:environment:)``.
    public func commit() -> ViewLayoutResult {
        guard let currentLayout else {
            logger.warning("layout committed before being computed, ignoring")
            return .leafView(size: .zero)
        }

        if parentEnvironment.allowLayoutCaching {
            logger.warning(
                "committing layout computed with caching enabled; results may be invalid",
                metadata: ["NodeView": "\(NodeView.self)"]
            )
        }
        if currentLayout.size.height == .infinity || currentLayout.size.width == .infinity {
            logger.warning(
                "infinite height or width on commit",
                metadata: [
                    "NodeView": "\(NodeView.self)",
                    "currentLayout.size": "\(currentLayout.size)",
                    "lastProposedSize": "\(lastProposedSize)",
                ]
            )
        }

        view.commit(
            widget,
            children: children,
            layout: currentLayout,
            environment: parentEnvironment,
            backend: backend
        )
        resultCache = [:]

        backend.showUpdate(of: widget)

        return currentLayout
    }
}
