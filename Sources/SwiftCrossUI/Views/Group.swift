/// A view that groups views together without affecting their layout (allowing
/// modifiers to be applied to a whole group of views at once).
public struct Group<Content: View>: View {
    public var body: Content

    /// Creates a group.
    ///
    /// - Parameter content: The content of the group.
    public init(@ViewBuilder content: () -> Content) {
        self.init(content: content())
    }

    init(content: Content) {
        body = content
    }

    public func asWidget<Backend: BaseAppBackend>(
        _ children: any ViewGraphNodeChildren,
        backend: Backend
    ) -> Backend.Widget {
        let container = backend.createContainer()
        for (index, child) in children.widgets(for: backend).enumerated() {
            backend.insert(child, into: container, at: index)
        }
        return container
    }

    public func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: any ViewGraphNodeChildren,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        if !(children is TupleViewChildren || children is EmptyViewChildren) {
            logger.warning(
                "Group will not function correctly with non-TupleView content",
                metadata: ["childrenType": "\(type(of: children))"]
            )
        }
        // Overlapping, when the enclosing stack overlaps. A `Group` is meant to
        // be invisible to the layout system, and it can only manage that by
        // arranging its children the way its parent would have. It inherits
        // orientation, alignment and spacing for exactly this reason -- but a
        // `ZStack` sets no orientation, so before this branch existed a `Group`
        // inside one fell back to whatever axis the grandparent used and laid
        // three views that should have overlapped out in a column.
        if environment.layoutOverlapsChildren {
            let result = LayoutSystem.computeOverlapLayout(
                children: layoutableChildren(backend: backend, children: children),
                proposedSize: proposedSize,
                environment: environment
            )
            (children as? TupleViewChildren)?.stackLayoutCache = StackLayoutCache(
                priorityGroups: [],
                isHidden: [],
                totalSpacing: 0,
                redistributeSpaceOnCommit: proposedSize.width == nil || proposedSize.height == nil
            )
            return result
        }

        var cache = (children as? TupleViewChildren)?.stackLayoutCache ?? StackLayoutCache.initial
        let result = LayoutSystem.computeStackLayout(
            container: widget,
            children: layoutableChildren(backend: backend, children: children),
            cache: &cache,
            proposedSize: proposedSize,
            environment: environment,
            backend: backend,
            inheritStackLayoutParticipation: true
        )
        (children as? TupleViewChildren)?.stackLayoutCache = cache
        return result
    }

    public func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: any ViewGraphNodeChildren,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        // Centred, matching `ZStack`'s own default. A `Group` carries no
        // alignment of its own, and the parent's is not reachable from here --
        // `layoutAlignment` is a `StackAlignment`, which describes one axis.
        // Naming the limitation rather than leaving it implicit: a `ZStack`
        // with a non-default alignment aligns a bare child correctly and a
        // grouped one to the centre.
        //
        // 置中，與 `ZStack` 自身的預設一致。`Group` 本身不帶對齊資訊，而父層的對齊在此處取不到
        // ——`layoutAlignment` 的型別是 `StackAlignment`，只描述單一軸向。此處明言此限制而不使其
        // 隱含：帶有非預設對齊的 `ZStack`，對直接子元件會正確對齊，對被 Group 包住的則會置中。
        if environment.layoutOverlapsChildren {
            LayoutSystem.commitOverlapLayout(
                container: widget,
                children: layoutableChildren(backend: backend, children: children),
                cache: (children as? TupleViewChildren)?.stackLayoutCache
                    ?? StackLayoutCache.initial,
                layout: layout,
                alignment: .center,
                environment: environment,
                backend: backend
            )
            return
        }

        var cache = (children as? TupleViewChildren)?.stackLayoutCache ?? StackLayoutCache.initial
        LayoutSystem.commitStackLayout(
            container: widget,
            children: layoutableChildren(backend: backend, children: children),
            cache: &cache,
            layout: layout,
            environment: environment,
            backend: backend
        )
        (children as? TupleViewChildren)?.stackLayoutCache = cache
    }
}
