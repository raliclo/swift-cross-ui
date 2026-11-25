extension View {
    /// Adds an action to perform when the user's pointer enters/leaves this
    /// view.
    ///
    /// - Parameter action: The action to perform when the hover state changes.
    ///   Receives a `Bool` parameter indicated whether the pointer entered or
    ///   left the view.
    public func onHover(
        perform action: @escaping (_ hovering: Bool) -> Void
    ) -> some View {
        OnHoverModifier(body: TupleView1(self), action: action)
    }
}

struct OnHoverModifier<Content: View>: TypeSafeView {
    typealias Children = TupleView1<Content>.Children

    var body: TupleView1<Content>
    var action: (Bool) -> Void

    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> Children {
        body.children(
            backend: backend,
            snapshots: snapshots,
            environment: environment
        )
    }

    @CastBackend<BackendFeatures.HoverGestures>(returnsWidget: true)
    func asWidget<Backend: BaseAppBackend>(
        _ children: Children,
        backend: Backend
    ) -> Backend.Widget {
        backend.createHoverTarget(wrapping: children.child0.widget.into())
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

    @CastBackend<BackendFeatures.HoverGestures>
    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        let committed = children.child0.commit()
        let size = committed.size.vector
        backend.setSize(of: widget, to: size)
        backend.updateHoverTarget(
            widget,
            environment: environment,
            action: action
        )
        // A pointer target takes the content shape of the view it wraps; see
        // `adoptContentShape(of:for:wrapping:)`.
        // 指標目標沿用其包裝之 view 的 content shape;見 `adoptContentShape(of:for:wrapping:)`。
        backend.adoptContentShape(
            of: committed, for: widget, wrapping: children.child0.widget.into())
    }
}
