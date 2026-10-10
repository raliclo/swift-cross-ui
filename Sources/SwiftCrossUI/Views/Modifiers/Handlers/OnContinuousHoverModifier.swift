extension View {
    /// Reports where the pointer is over this view and which modifier keys are
    /// held, as it moves.
    ///
    /// ```swift
    /// Mesh3DView(scene)
    ///     .onContinuousHover { phase in
    ///         switch phase {
    ///             case .active(let location, let modifiers):
    ///                 probe = modifiers.contains(.command) ? location : nil
    ///             case .ended:
    ///                 probe = nil
    ///         }
    ///     }
    /// ```
    ///
    /// On a backend without ``BackendFeatures/PointerHover`` the view is drawn
    /// as usual and nothing is reported; a warning is logged once.
    ///
    /// 指標移動時，回報它在這個 view 上的位置與按住的修飾鍵。在沒有 ``BackendFeatures/PointerHover``
    /// 的 backend 上，view 照常繪製、不回報任何東西，並記錄一次警告。
    public func onContinuousHover(
        perform action: @escaping (PointerHoverPhase) -> Void
    ) -> some View {
        OnContinuousHoverModifier(body: TupleView1(self), action: action)
    }
}

struct OnContinuousHoverModifier<Content: View>: TypeSafeView {
    typealias Children = TupleView1<Content>.Children

    var body: TupleView1<Content>
    var action: (PointerHoverPhase) -> Void

    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> Children {
        body.children(backend: backend, snapshots: snapshots, environment: environment)
    }

    /// Wraps the child when the backend reports pointer hover, and hands the
    /// child back when it does not, as ``OnKeyPressModifier`` does:
    /// `@CastBackend` would expand to `fatalError` on such a backend.
    /// backend 能回報指標 hover 時把子 view 包起來，不能時原樣交回，與 ``OnKeyPressModifier`` 相同:
    /// `@CastBackend` 在那種 backend 上會展開為 `fatalError`。
    func asWidget<Backend: BaseAppBackend>(
        _ children: Children,
        backend: Backend
    ) -> Backend.Widget {
        let child: Backend.Widget = children.child0.widget.into()
        guard let backend = backend as? any BaseAppBackend & BackendFeatures.PointerHover else {
            PointerHoverDegradation.reportOnce(backend: "\(Backend.self)")
            return child
        }
        return wrap(backend, child: child) as! Backend.Widget
    }

    private func wrap<Backend: BaseAppBackend & BackendFeatures.PointerHover>(
        _ backend: Backend,
        child: Any
    ) -> Backend.Widget {
        backend.createPointerHoverTarget(wrapping: child as! Backend.Widget)
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
        guard let backend = backend as? any BaseAppBackend & BackendFeatures.PointerHover
        else { return }
        update(backend, widget: widget, environment: environment)
    }

    private func update<Backend: BaseAppBackend & BackendFeatures.PointerHover>(
        _ backend: Backend,
        widget: Any,
        environment: EnvironmentValues
    ) {
        backend.updatePointerHoverTarget(
            widget as! Backend.Widget,
            environment: environment,
            action: action
        )
    }
}

/// One report per backend, because a view commits on every update.
/// 每個 backend 只回報一次，因為一個 view 每次更新都會 commit。
enum PointerHoverDegradation {
    nonisolated(unsafe) private static var reported: Set<String> = []

    static func reportOnce(backend: String) {
        guard !reported.contains(backend) else { return }
        reported.insert(backend)
        logger.warning(
            """
            input warning (the app keeps running and the view is still drawn and laid out): \
            \(backend) does not implement BackendFeatures.PointerHover, so \
            .onContinuousHover reports nothing on this backend. What to change: implement \
            the two methods of that protocol without taking clicks or drags from the child. \
            AppKitBackend puts an NSTrackingArea with .mouseMoved on a plain container; \
            UIKitBackend uses UIHoverGestureRecognizer; GtkBackend an EventControllerMotion; \
            AndroidBackend overrides dispatchHoverEvent; WinUI has PointerMoved and \
            PointerExited.
            """
        )
    }
}
