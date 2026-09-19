extension View {
    /// Shows `cursor` while the pointer is over this view.
    ///
    /// ```swift
    /// Mesh3DView(scene)
    ///     .cursor(.crosshair)
    /// ```
    ///
    /// Does nothing on a device with no pointer, which is most phones -- not an
    /// error, and not something a caller should branch on.
    ///
    /// 當指標位於這個 view 上方時,顯示 `cursor`。
    ///
    /// 在沒有指標的裝置上(也就是大多數手機)不做任何事;那不是錯誤,呼叫端也不該為它分支。
    public func cursor(_ cursor: Cursor) -> some View {
        CursorModifier(body: TupleView1(self), cursor: cursor)
    }
}

struct CursorModifier<Content: View>: TypeSafeView {
    typealias Children = TupleView1<Content>.Children

    var body: TupleView1<Content>
    var cursor: Cursor

    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> Children {
        body.children(backend: backend, snapshots: snapshots, environment: environment)
    }

    /// Wraps when the backend can set a cursor, hands the child back when it
    /// cannot -- the shape ``OnScrollGestureModifier`` uses, for the reason
    /// `CLAUDE.md` records about `@CastBackend` expanding to `fatalError`.
    /// 能設游標時包起來,不能時原樣交回——與 ``OnScrollGestureModifier`` 相同的形狀,理由是 `CLAUDE.md`
    /// 所記載的:`@CastBackend` 會展開為 `fatalError`。
    func asWidget<Backend: BaseAppBackend>(
        _ children: Children,
        backend: Backend
    ) -> Backend.Widget {
        let child: Backend.Widget = children.child0.widget.into()
        guard let backend = backend as? any BaseAppBackend & BackendFeatures.Cursors
        else {
            CursorDegradation.reportOnce(backend: "\(Backend.self)")
            return child
        }
        return wrap(backend, child: child) as! Backend.Widget
    }

    private func wrap<Backend: BaseAppBackend & BackendFeatures.Cursors>(
        _ backend: Backend,
        child: Any
    ) -> Backend.Widget {
        backend.createCursorTarget(wrapping: child as! Backend.Widget)
    }

    func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        children.child0.computeLayout(
            with: body.view0,
            proposedSize: proposedSize,
            environment: environment
        )
    }

    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        let size = children.child0.commit().size
        backend.setSize(of: widget, to: size.vector)
        guard let backend = backend as? any BaseAppBackend & BackendFeatures.Cursors
        else { return }
        update(backend, widget: widget, environment: environment)
    }

    private func update<Backend: BaseAppBackend & BackendFeatures.Cursors>(
        _ backend: Backend,
        widget: Any,
        environment: EnvironmentValues
    ) {
        backend.updateCursorTarget(
            widget as! Backend.Widget,
            cursor: cursor,
            environment: environment
        )
    }
}

/// One report per backend, because a view commits on every update.
/// 每個 backend 只回報一次,因為一個 view 每次更新都會 commit。
enum CursorDegradation {
    nonisolated(unsafe) private static var reported: Set<String> = []

    static func reportOnce(backend: String) {
        guard !reported.contains(backend) else { return }
        reported.insert(backend)
        logger.warning(
            """
            input warning (the app keeps running and the view is still drawn and laid out): \
            \(backend) does not implement BackendFeatures.Cursors, so .cursor(_:) has no \
            effect -- the pointer keeps whatever shape it had. What to change: implement \
            the two methods of that protocol. AppKitBackend uses NSTrackingArea with \
            cursorUpdate(with:); GTK has gtk_widget_set_cursor with the named cursors, \
            WinUI has ProtectedCursor with InputSystemCursorShape, Android has \
            View.pointerIcon from API 24, and UIKit has UIPointerInteraction on iPadOS.
            """
        )
    }
}
