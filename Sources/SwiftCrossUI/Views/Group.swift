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
        // Upstream's mechanism, taken in place of this tree's own.
        //
        // `layoutOverlapsChildren` was ours (e90a2b8d, for `Group` inside a
        // `ZStack`); upstream solved the same problem independently in #728 with
        // `usesZStackLayout` and a real ZStack layout rather than a plain
        // overlap. Two flags for one question is one too many, so ours goes and
        // theirs stays -- it also carries `zStackContentAlignment`, which the
        // overlap path could not, and this file used to say so as a known
        // limitation.
        //
        // 採用 upstream 的機制,取代本樹自有的那一套。
        //
        // `layoutOverlapsChildren` 是我們的(e90a2b8d,為了 `ZStack` 內的 `Group`);upstream 在
        // #728 中獨立地解了同一個問題,用的是 `usesZStackLayout` 與一套真正的 ZStack 版面,而非
        // 單純的重疊。同一個問題有兩個旗標就是多了一個,因此我們的移除、他們的保留——而且他們那套
        // 還帶著 `zStackContentAlignment`,那是重疊路徑做不到的,本檔過去正是把它記為一項已知限制。
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
