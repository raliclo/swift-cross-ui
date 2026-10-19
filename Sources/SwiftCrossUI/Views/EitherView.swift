/// A view used by ``ViewBuilder`` to support if/else conditional statements.
public struct EitherView<A: View, B: View> {
    typealias NodeChildren = EitherViewChildren<A, B>

    public var body = EmptyView()

    /// Stores one of two possible view types.
    enum Storage {
        case a(A)
        case b(B)
    }

    var storage: Storage

    /// Creates an either view with its first case visible initially.
    init(_ a: A) {
        storage = .a(a)
    }

    /// Creates an either view with its second case visible initially.
    init(_ b: B) {
        storage = .b(b)
    }
}

extension EitherView: View {
    public var _asMenuItems: [MenuItem] {
        switch storage {
            case .a(let a): a._asMenuItems
            case .b(let b): b._asMenuItems
        }
    }

    /// Needed for `if` inside a ``Picker``'s content, and NOT optional.
    ///
    /// `EitherView`'s `body` is not the taken branch, so without this the
    /// default would forward to something that knows nothing about either side
    /// and a conditional option would silently vanish. Same reason
    /// ``_asMenuItems`` above exists.
    ///
    /// ``Picker`` 的內容中要使用 `if` 就必須有它,而且它**不是可選的**。
    ///
    /// `EitherView` 的 `body` 並不是被採用的那個分支,因此少了這個覆寫,預設實作會轉發給一個
    /// 對兩側都一無所知的東西,而一個條件式的選項就會**靜默消失**。與上方 ``_asMenuItems``
    /// 存在的理由相同。
    public var _asPickerOptions: [PickerOption] {
        switch storage {
            case .a(let a): a._asPickerOptions
            case .b(let b): b._asPickerOptions
        }
    }
}

extension EitherView: TypeSafeView {
    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> NodeChildren {
        return EitherViewChildren(
            from: self,
            backend: backend,
            snapshots: snapshots,
            environment: environment
        )
    }

    func asWidget<Backend: BaseAppBackend>(
        _ children: EitherViewChildren<A, B>,
        backend: Backend
    ) -> Backend.Widget {
        return backend.createContainer()
    }

    func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: EitherViewChildren<A, B>,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        let result: ViewLayoutResult
        let hasSwitchedCase: Bool
        switch storage {
            case .a(let a):
                switch children.node {
                    case .a(let nodeA):
                        result = nodeA.computeLayout(
                            with: a,
                            proposedSize: proposedSize,
                            environment: environment
                        )
                        hasSwitchedCase = false
                    case .b:
                        let nodeA = AnyViewGraphNode(
                            for: a,
                            backend: backend,
                            environment: environment
                        )
                        children.switchNode(to: .a(nodeA), environment: environment)
                        result = nodeA.computeLayout(
                            with: a,
                            proposedSize: proposedSize,
                            environment: environment
                        )
                        hasSwitchedCase = true
                }
            case .b(let b):
                switch children.node {
                    case .b(let nodeB):
                        result = nodeB.computeLayout(
                            with: b,
                            proposedSize: proposedSize,
                            environment: environment
                        )
                        hasSwitchedCase = false
                    case .a:
                        let nodeB = AnyViewGraphNode(
                            for: b,
                            backend: backend,
                            environment: environment
                        )
                        children.switchNode(to: .b(nodeB), environment: environment)
                        result = nodeB.computeLayout(
                            with: b,
                            proposedSize: proposedSize,
                            environment: environment
                        )
                        hasSwitchedCase = true
                }
        }
        children.hasSwitchedCase = children.hasSwitchedCase || hasSwitchedCase

        return result
    }

    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: EitherViewChildren<A, B>,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        if children.hasSwitchedCase {
            // The child switched away from stays drawn while it departs; the
            // new one is inserted in front of it (Transition.swift).
            // 被切換掉的子元件在離場期間繼續畫出;新的插在它前面(Transition.swift)。
            let newChild: Backend.Widget = children.node.widget.into()
            children.departing.commitSwitch(
                container: widget,
                backend: backend,
                hadChild: children.hasCommitted,
                departure: children.pendingDeparture,
                newChild: newChild
            )
            children.pendingDeparture = nil
            children.hasSwitchedCase = false
        }

        _ = children.node.erasedNode.commit()

        backend.setSize(of: widget, to: children.departing.containerSize(layout.size.vector))
        children.hasCommitted = true
    }
}

/// Uses an `enum` to store a view graph node for one of two possible child view types.
class EitherViewChildren<A: View, B: View>: ViewGraphNodeChildren {
    /// A view graph node that wraps one of two possible child view types.
    @MainActor
    enum EitherNode {
        case a(AnyViewGraphNode<A>)
        case b(AnyViewGraphNode<B>)

        /// The widget corresponding to the currently displayed child view.
        var widget: AnyWidget {
            switch self {
                case .a(let node):
                    return node.widget
                case .b(let node):
                    return node.widget
            }
        }

        var erasedNode: ErasedViewGraphNode {
            switch self {
                case .a(let node):
                    return ErasedViewGraphNode(wrapping: node)
                case .b(let node):
                    return ErasedViewGraphNode(wrapping: node)
            }
        }
    }

    /// The view graph node for the currently displayed child.
    var node: EitherNode

    /// Tracks whether the view has switched cases since the last non-dryrun update.
    /// Initially `true`.
    var hasSwitchedCase = true
    /// Children removed under an animation, drawn until their removal
    /// transitions end (Transition.swift).
    /// 在動畫中被移除、畫到移除轉場結束為止的子元件(Transition.swift)。
    lazy var departing = DepartingViews()
    /// The departure of the child switched away from since the last commit.
    /// 自上次 commit 以來被切換掉之子元件的離場。
    var pendingDeparture: DepartingViews.Departure?
    /// A switch before the first commit is the first appearance, not an insertion.
    /// 第一次 commit 之前的切換是首次出現，而不是插入。
    var hasCommitted = false

    /// Replaces the node with `new`. Under an animation the old child departs
    /// with its `.transition` and the new one is inserted with its own.
    /// 以 `new` 取代節點。在動畫中，舊的子元件以它的 `.transition` 離場，新的以它自己的轉場插入。
    func switchNode(to new: EitherNode, environment: EnvironmentValues) {
        if hasCommitted, pendingDeparture == nil {
            pendingDeparture = departing.depart(node.erasedNode, environment: environment)
        }
        node = new
        if hasCommitted, let transaction = TransitionLookup.animatedTransaction(in: environment) {
            TransitionLookup.controller(in: new.erasedNode)?.pendingInsertion = transaction
        }
    }

    var widgets: [AnyWidget] {
        return [node.widget]
    }

    var erasedNodes: [ErasedViewGraphNode] {
        [node.erasedNode]
    }

    /// Creates storage for an either view's current child (which can change at any time).
    init<Backend: BaseAppBackend>(
        from view: EitherView<A, B>,
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) {
        // TODO: Ensure that this is valid in all circumstances. It should be, given that
        //   we're assuming that the parent view's state was restored from the same snapshot
        //   which should mean that the same EitherView case will be selected (if we assume
        //   that views are pure, which we have to).
        let snapshot = snapshots?.first
        switch view.storage {
            case .a(let a):
                node = .a(
                    AnyViewGraphNode(
                        for: a,
                        backend: backend,
                        snapshot: snapshot,
                        environment: environment
                    )
                )
            case .b(let b):
                node = .b(
                    AnyViewGraphNode(
                        for: b,
                        backend: backend,
                        snapshot: snapshot,
                        environment: environment
                    )
                )
        }
    }
}
