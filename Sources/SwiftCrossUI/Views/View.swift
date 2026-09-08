/// A view that can be rendered by any backend.
@MainActor
public protocol View {
    /// The view's content (composed of other views).
    associatedtype Content: View

    /// The view's contents.
    @ViewBuilder var body: Content { get }

    /// Gets the view's children as a type-erased collection of view graph
    /// nodes.
    ///
    /// The collection is type-erased to avoid leaking complex requirements to
    /// users implementing their own regular views.
    ///
    /// - Parameters:
    ///   - backend: The app's backend.
    ///   - snapshots: A list of snapshots, used to restore view state during a
    ///     hot reload.
    ///   - environment: The current environment.
    /// - Returns: The view's children as a type-erased collection of view graph
    ///   nodes.
    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> any ViewGraphNodeChildren

    // TODO: Perhaps this can be split off into a separate protocol for the `TupleViewN`s
    //   if we can set up the generics right for VStack.
    /// Gets the view's children in a format that can be consumed by the
    /// ``LayoutSystem``.
    ///
    /// This really only needs to be its own method for views such as ``VStack``
    /// which treat their child's children as their own and skip over their
    /// direct child. Only needs to be implemented by the `TupleViewN`s.
    ///
    /// - Parameters:
    ///   - backend: The app's backend.
    ///   - children: The view's children.
    /// - Returns: The view's children in a format that can be consumed by the
    /// ``LayoutSystem``.
    func layoutableChildren<Backend: BaseAppBackend>(
        backend: Backend,
        children: any ViewGraphNodeChildren
    ) -> [LayoutSystem.LayoutableChild]

    /// Creates the view's widget using the supplied backend.
    ///
    /// A view is represented by the same widget instance for the whole time
    /// that it's visible even if its content is changing; keep that in mind
    /// while deciding the structure of the widget. For example, a view
    /// displaying one of two children should use ``BackendFeatures/GenericContainers/createContainer()``
    /// to create a container for the displayed child instead of just directly
    /// returning the widget of the currently displayed child (which would
    /// result in you not being able to ever switch to displaying the other
    /// child). This constraint significantly simplifies view implementations
    /// without requiring widgets to be re-created after every single update.
    ///
    /// - Parameters:
    ///   - children: The view's children.
    ///   - backend: The app's backend.
    /// - Returns: The view's widget created using the given backend.
    func asWidget<Backend: BaseAppBackend>(
        _ children: any ViewGraphNodeChildren,
        backend: Backend
    ) -> Backend.Widget

    /// Computes this view's layout after a state change or a change in
    /// available space.
    ///
    /// This method should _not_ apply the layout to `widget`; that should be
    /// done in ``commit(_:children:layout:environment:backend:)`` instead.
    ///
    /// `proposedSize` is the size suggested by the parent container, but child
    /// views always get the final call on their own size.
    ///
    /// - Parameters:
    ///   - widget: The view's underlying widget.
    ///   - children: The view's children.
    ///   - proposedSize: The size suggested to the view by its parent
    ///     container.
    ///   - environment: The current environment.
    ///   - backend: The app's backend.
    /// - Returns: The view's computed size, along with any propagated
    ///   preferences.
    func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: any ViewGraphNodeChildren,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult

    /// Commits the last computed layout to the underlying widget hierarchy.
    ///
    /// - Parameters:
    ///   - widget: The view's underlying widget.
    ///   - children: The view's children.
    ///   - layout: The layout to use for the view. Guaranteed to be the
    ///     last value returned by
    ///     ``computeLayout(_:children:proposedSize:environment:backend:)``.
    ///   - environment: The current environment.
    ///   - backend: The app's backend.
    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: any ViewGraphNodeChildren,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    )

    /// Returns this view as an array of ``MenuItem``s.
    ///
    /// The default implementation forwards to ``body``; you should never have to override this.
    ///
    /// - Warning: This is an implementation detail and is subject to be changed or removed at any
    ///   time.
    var _asMenuItems: [MenuItem] { get }
}

extension View {
    public func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> any ViewGraphNodeChildren {
        defaultChildren(
            backend: backend,
            snapshots: snapshots,
            environment: environment
        )
    }

    /// The default `View.children` implementation. Haters may see this as a
    /// composition lover re-implementing inheritance; I see it as innovation.
    public func defaultChildren<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> any ViewGraphNodeChildren {
        body.children(backend: backend, snapshots: snapshots, environment: environment)
    }

    public func layoutableChildren<Backend: BaseAppBackend>(
        backend: Backend,
        children: any ViewGraphNodeChildren
    ) -> [LayoutSystem.LayoutableChild] {
        defaultLayoutableChildren(backend: backend, children: children)
    }

    /// The default `View.layoutableChildren` implementation. Haters may see
    /// this as a composition lover re-implementing inheritance; I see it as
    /// innovation.
    public func defaultLayoutableChildren<Backend: BaseAppBackend>(
        backend: Backend,
        children: any ViewGraphNodeChildren
    ) -> [LayoutSystem.LayoutableChild] {
        body.layoutableChildren(backend: backend, children: children)
    }

    public func asWidget<Backend: BaseAppBackend>(
        _ children: any ViewGraphNodeChildren,
        backend: Backend
    ) -> Backend.Widget {
        defaultAsWidget(children, backend: backend)
    }

    /// The default `View.asWidget` implementation. Haters may see this as a
    /// composition lover re-implementing inheritance; I see it as innovation.
    /// Whether the default implementations may route through ``VStack``.
    ///
    /// **They may only do so when `body` came out of the `@ViewBuilder`.** An
    /// explicit `return` in a `body` opts out of the builder, so `Content`
    /// becomes the returned view itself -- `Text` rather than
    /// `TupleView1<Text>` -- and then the two halves of the default
    /// implementation stop agreeing about what `children` is.
    /// ``defaultChildren(backend:snapshots:environment:)`` asks `body` for them
    /// and gets `Text`'s; the three below hand those to a `VStack`, whose
    /// `layoutableChildren` finds none, so the stack lays out zero children,
    /// reports zero size, and draws nothing.
    ///
    /// It compiles, the body runs, and the view is silently absent.
    ///
    /// **`EmptyViewChildren` is on the wrong side of this test, and that is
    /// deliberate.** ``Text`` is an ``ElementaryView``, whose `Content` is
    /// `EmptyView`, so a `body` that returns a `Text` produces
    /// `EmptyViewChildren` -- the same children a genuinely empty builder body
    /// produces. Treating those as builder-produced was the first attempt at
    /// this fix and it changed nothing, because that is exactly the case that
    /// breaks. Only a `TupleViewChildren` means the builder ran, and delegating
    /// to `body` is right for everything else: an `EmptyView` body draws
    /// nothing either way.
    ///
    /// Recorded in testapp/plan/explicit-return-body.md.
    ///
    /// **`EmptyViewChildren` 被歸在這項判斷的另一側，而那是刻意的。** ``Text`` 是一個
    /// ``ElementaryView``，其 `Content` 為 `EmptyView`，因此一個回傳 `Text` 的 `body` 產生的正是
    /// `EmptyViewChildren`——與一個真正空白的 builder body 所產生的相同。把它們當成 builder 產生的，
    /// 是本次修正的第一次嘗試，而它什麼都沒有改變，因為那恰恰就是會壞掉的那一種。只有
    /// `TupleViewChildren` 才代表 builder 執行過;至於其餘各種情況，委派給 `body` 都是對的:一個
    /// `EmptyView` 的 body 無論走哪一條路都不會畫出任何東西。
    ///
    /// 預設實作是否可以繞道 ``VStack``。
    ///
    /// **只有在 `body` 出自 `@ViewBuilder` 時才可以。** 在 `body` 中使用顯式 `return` 會跳出 builder，
    /// 於是 `Content` 成為所回傳的 view 本身——是 `Text` 而非 `TupleView1<Text>`——此時預設實作的兩半
    /// 便對「`children` 是什麼」失去共識。
    /// ``defaultChildren(backend:snapshots:environment:)`` 是向 `body` 索取的，拿到的是 `Text` 的;
    /// 而下方那三個卻把它交給一個 `VStack`，該 `VStack` 的 `layoutableChildren` 一個也找不到，於是它
    /// 排列了零個子節點、回報零尺寸、什麼都不畫。
    ///
    /// 它編得過、body 也確實執行，而 view 靜默地不存在。`VStack` 途中會記下
    /// 「will not function correctly with non-TupleView content」，那是唯一的痕跡，而它並沒有提到
    /// 有一個 view 消失了。記於 testapp/plan/explicit-return-body.md。
    func bodyIsBuilderProduced(_ children: any ViewGraphNodeChildren) -> Bool {
        children is TupleViewChildren
    }

    public func defaultAsWidget<Backend: BaseAppBackend>(
        _ children: any ViewGraphNodeChildren,
        backend: Backend
    ) -> Backend.Widget {
        guard bodyIsBuilderProduced(children) else {
            return body.asWidget(children, backend: backend)
        }
        let vStack = VStack(content: body)
        return vStack.asWidget(children, backend: backend)
    }

    public func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: any ViewGraphNodeChildren,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        defaultComputeLayout(
            widget,
            children: children,
            proposedSize: proposedSize,
            environment: environment,
            backend: backend
        )
    }

    /// The default `View.computeLayout` implementation. Haters may see this as a
    /// composition lover re-implementing inheritance; I see it as innovation.
    public func defaultComputeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: any ViewGraphNodeChildren,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        guard bodyIsBuilderProduced(children) else {
            return body.computeLayout(
                widget,
                children: children,
                proposedSize: proposedSize,
                environment: environment,
                backend: backend
            )
        }
        let vStack = VStack(content: body)
        return vStack.computeLayout(
            widget,
            children: children,
            proposedSize: proposedSize,
            environment: environment,
            backend: backend
        )
    }

    public func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: any ViewGraphNodeChildren,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        defaultCommit(
            widget,
            children: children,
            layout: layout,
            environment: environment,
            backend: backend
        )
    }

    public func defaultCommit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: any ViewGraphNodeChildren,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        guard bodyIsBuilderProduced(children) else {
            return body.commit(
                widget,
                children: children,
                layout: layout,
                environment: environment,
                backend: backend
            )
        }
        let vStack = VStack(content: body)
        return vStack.commit(
            widget,
            children: children,
            layout: layout,
            environment: environment,
            backend: backend
        )
    }

    public var _asMenuItems: [MenuItem] { body._asMenuItems }

    /// Resolves this view's menu content to the representation used by backends.
    ///
    /// This is the same resolution applied to ``Menu`` content and scene ``Commands``.
    /// - Returns: The resolved menu.
    @MainActor
    @_spi(Backends) public func resolvedMenuContent() -> ResolvedMenu {
        Menu.resolve(items: _asMenuItems)
    }
}
