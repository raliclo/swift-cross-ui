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
        // `ZStack` sets no orientation, so without this branch a `Group`
        // inside one would fall back to whatever axis the grandparent used and
        // lay three views that should overlap out in a column.
        //
        // Upstream's `usesZStackLayout` (#728) answers this with a real ZStack
        // layout, which also honours `zStackContentAlignment`. It replaced this
        // tree's own `layoutOverlapsChildren` flag (e90a2b8d), a plain overlap
        // that could not align: two flags for one question is one too many.
        //
        // upstream 的 `usesZStackLayout`(#728)以一套真正的 ZStack 版面處理這件事,它同時遵守
        // `zStackContentAlignment`。它取代了本樹原有的 `layoutOverlapsChildren` 旗標(e90a2b8d)
        // ——那只是單純的重疊,無法對齊:同一個問題有兩個旗標就是多了一個。
        if environment.usesZStackLayout {
            var cache = (children as? TupleViewChildren)?.stackLayoutCache
                ?? StackLayoutCache.initial
            let result = LayoutSystem.computeZStackLayout(
                container: widget,
                children: layoutableChildren(backend: backend, children: children),
                cache: &cache,
                proposedSize: proposedSize,
                environment: environment,
                backend: backend
            )
            (children as? TupleViewChildren)?.stackLayoutCache = cache
            (children as? TupleViewChildren)?.stackLayoutCache = StackLayoutCache(
                priorityGroups: [],
                isHidden: [],
                totalSpacing: 0,
                minimumLengths: [],
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
        // Inside a `ZStack`, aligned by the `zStackContentAlignment` the stack
        // puts in the environment, so a grouped child lines up the same as a
        // bare one.
        //
        // 在 `ZStack` 內時，依該堆疊放進 environment 的 `zStackContentAlignment` 對齊，因此被 Group
        // 包住的子元件與直接子元件對齊方式相同。
        if environment.usesZStackLayout {
            var zCache = (children as? TupleViewChildren)?.stackLayoutCache
                ?? StackLayoutCache.initial
            LayoutSystem.commitZStackLayout(
                container: widget,
                children: layoutableChildren(backend: backend, children: children),
                cache: &zCache,
                layout: layout,
                environment: environment,
                backend: backend
            )
            (children as? TupleViewChildren)?.stackLayoutCache = zCache
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
