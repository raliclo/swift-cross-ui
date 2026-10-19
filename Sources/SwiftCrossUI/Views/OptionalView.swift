/// A view used by ``ViewBuilder`` to support non-exhaustive if statements.
public struct OptionalView<V: View> {
    public var body = EmptyView()

    var view: V?

    /// Wraps an optional view.
    init(_ view: V?) {
        self.view = view
    }
}

extension OptionalView: View {
    public var _asMenuItems: [MenuItem] {
        view?._asMenuItems ?? []
    }

    public var _asPickerOptions: [PickerOption] {
        view?._asPickerOptions ?? []
    }
}

extension OptionalView: TypeSafeView {
    typealias Children = OptionalViewChildren<V>

    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> OptionalViewChildren<V> {
        // TODO: This is a conservative implementation, perhaps there are some situations
        //   where we could usefully use the snapshots even if there are too many.
        let snapshot = snapshots?.count == 1 ? snapshots?.first : nil
        return OptionalViewChildren(
            from: view,
            backend: backend,
            snapshot: snapshot,
            environment: environment
        )
    }

    func asWidget<Backend: BaseAppBackend>(
        _ children: OptionalViewChildren<V>,
        backend: Backend
    ) -> Backend.Widget {
        return backend.createContainer()
    }

    func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: OptionalViewChildren<V>,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        let hasToggled: Bool
        let result: ViewLayoutResult
        if let view {
            if let node = children.node {
                result = node.computeLayout(
                    with: view,
                    proposedSize: proposedSize,
                    environment: environment
                )
                hasToggled = false
            } else {
                let node = AnyViewGraphNode(
                    for: view,
                    backend: backend,
                    environment: environment
                )
                children.node = node
                // Inserted under an animation: the child's `.transition` runs,
                // or the default fade. / 在動畫中插入：子元件的 `.transition` 會執行，或是預設的淡入。
                if children.hasCommitted,
                    let transaction = TransitionLookup.animatedTransaction(in: environment)
                {
                    TransitionLookup.prepareInsertion(of: node, transaction: transaction)
                }
                result = node.computeLayout(
                    with: view,
                    proposedSize: proposedSize,
                    environment: environment
                )
                hasToggled = true
            }
        } else {
            hasToggled = children.node != nil
            // Under an animation the child departs with its `.transition` (or
            // the default fade) instead of going at once.
            // 在動畫中，子元件帶著它的 `.transition`(或預設的淡出)離場，而不是立刻消失。
            if let node = children.node, children.hasCommitted, children.pendingDeparture == nil {
                children.pendingDeparture = children.departing.depart(
                    ErasedViewGraphNode(wrapping: node),
                    environment: environment
                )
            }
            children.node = nil
            result = ViewLayoutResult(
                size: .zero,
                childResults: [],
                participateInStackLayoutsWhenEmpty: false
            )
        }
        children.hasToggled = children.hasToggled || hasToggled

        return result
    }

    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: OptionalViewChildren<V>,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        if children.hasToggled {
            // The removed child stays drawn while it departs; the new one is
            // inserted in front of it (Transition.swift).
            // 被移除的子元件在離場期間繼續畫出;新的子元件插在它前面(Transition.swift)。
            let newChild: Backend.Widget? = children.node.map { TransitionLookup.outerWidget(of: $0) }?.into()
            children.departing.commitSwitch(
                container: widget,
                backend: backend,
                hadChild: children.committedHasChild,
                departure: children.pendingDeparture,
                newChild: newChild
            )
            children.pendingDeparture = nil
            children.committedHasChild = newChild != nil
            children.hasToggled = false
        }

        _ = children.node?.commit()

        backend.setSize(of: widget, to: children.departing.containerSize(layout.size.vector))
        children.hasCommitted = true
    }
}

/// Stores a view graph node for the view's child if present. Tracks whether
/// the child has toggled since last time the parent was updated or not.
class OptionalViewChildren<V: View>: ViewGraphNodeChildren {
    /// The view graph node for the view's child if present.
    var node: AnyViewGraphNode<V>?
    /// Whether the view has toggled since the last non-dryrun update. `true`
    /// if the first view update hasn't occurred yet.
    var hasToggled = true
    /// Children removed under an animation, drawn until their removal
    /// transitions end (Transition.swift).
    /// 在動畫中被移除、畫到移除轉場結束為止的子元件(Transition.swift)。
    lazy var departing = DepartingViews()
    /// The departure of the child removed since the last commit.
    /// 自上次 commit 以來被移除之子元件的離場。
    var pendingDeparture: DepartingViews.Departure?
    /// Whether the last commit left a live child in the container.
    /// 上次 commit 是否在容器中留下了存活的子元件。
    var committedHasChild = false
    /// A child appearing before the first commit is the first appearance, not an insertion.
    /// 在第一次 commit 之前出現的子元件是首次出現，而不是插入。
    var hasCommitted = false

    var widgets: [AnyWidget] {
        return [node?.widget].compactMap { $0 }
    }

    var erasedNodes: [ErasedViewGraphNode] {
        if let node {
            [ErasedViewGraphNode(wrapping: node)]
        } else {
            []
        }
    }

    /// Creates storage for an optional view's child if present (which can change at
    /// any time).
    init<Backend: BaseAppBackend>(
        from view: V?,
        backend: Backend,
        snapshot: ViewGraphSnapshotter.NodeSnapshot?,
        environment: EnvironmentValues
    ) {
        if let view {
            node = AnyViewGraphNode(
                for: view,
                backend: backend,
                snapshot: snapshot,
                environment: environment
            )
        }
    }
}
