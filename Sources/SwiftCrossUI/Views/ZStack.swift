/// A container that lays its views on top of each other.
public struct ZStack<Content: View>: View {
    /// The stack's alignment.
    public var alignment: Alignment
    /// The stack's content.
    public var body: Content

    /// Creates a ``ZStack``.
    ///
    /// - Parameters:
    ///   - alignment: The stack's alignment.
    ///   - content: The stack's content.
    public init(
        alignment: Alignment = .center,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            alignment: alignment,
            content: content()
        )
    }

    init(alignment: Alignment, content: Content) {
        self.alignment = alignment
        body = content
    }

    public func asWidget<Backend: BaseAppBackend>(
        _ children: any ViewGraphNodeChildren,
        backend: Backend
    ) -> Backend.Widget {
        let zStack = backend.createContainer()
        for (index, child) in children.widgets(for: backend).enumerated() {
            backend.insert(child, into: zStack, at: index)
        }
        return zStack
    }

    public func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: any ViewGraphNodeChildren,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        let result = LayoutSystem.computeOverlapLayout(
            children: layoutableChildren(backend: backend, children: children),
            proposedSize: proposedSize,
            // Told to the children, so that a `Group` or `ForEach` between this
            // stack and the views it holds overlaps them too instead of
            // arranging them along an axis it inherited from further up.
            environment: environment.with(\.layoutOverlapsChildren, true)
        )

        if !(children is TupleViewChildren || children is EmptyViewChildren) {
            logger.warning(
                "ZStack will not function correctly with non-TupleView content",
                metadata: [
                    "childrenType": "\(type(of: children))",
                    "contentType": "\(Content.self)",
                ]
            )
        }

        (children as? TupleViewChildren)?.stackLayoutCache = StackLayoutCache(
            priorityGroups: [],
            isHidden: [],
            totalSpacing: 0,
            redistributeSpaceOnCommit: proposedSize.width == nil || proposedSize.height == nil
        )

        return result
    }

    public func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: any ViewGraphNodeChildren,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        LayoutSystem.commitOverlapLayout(
            container: widget,
            children: layoutableChildren(backend: backend, children: children),
            cache: (children as? TupleViewChildren)?.stackLayoutCache ?? StackLayoutCache.initial,
            layout: layout,
            alignment: alignment,
            environment: environment.with(\.layoutOverlapsChildren, true),
            backend: backend
        )
    }
}
