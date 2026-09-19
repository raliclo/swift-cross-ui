extension View {
    /// Reports raw key presses and modifier changes over this view.
    ///
    /// ```swift
    /// Mesh3DView(scene)
    ///     .onKeyPress { press in
    ///         guard press.phase != .up else { return }
    ///         switch press.key {
    ///             case .upArrow: height += press.modifiers.contains(.shift) ? 1 : 0.1
    ///             case nil: isConstrained = press.modifiers.contains(.shift)
    ///             default: break
    ///         }
    ///     }
    /// ```
    ///
    /// The view is made able to take focus by the backend, so a key pressed over
    /// it arrives without the caller arranging anything. See ``KeyPress`` for
    /// what `key == nil` means and for why the key is a character rather than a
    /// physical key.
    ///
    /// 回報這個 view 上的原始按鍵與修飾鍵變化。
    ///
    /// 這個 view 取得焦點的能力由 backend 安排,因此在它上面按下的鍵會直接送達,呼叫端不必做任何事。
    /// `key == nil` 的意義、以及「為何是字元而不是實體按鍵」,見 ``KeyPress``。
    public func onKeyPress(
        perform onKey: @escaping (KeyPress) -> Void
    ) -> some View {
        OnKeyPressModifier(body: TupleView1(self), onKey: onKey)
    }
}

struct OnKeyPressModifier<Content: View>: TypeSafeView {
    typealias Children = TupleView1<Content>.Children

    var body: TupleView1<Content>
    var onKey: (KeyPress) -> Void

    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> Children {
        body.children(backend: backend, snapshots: snapshots, environment: environment)
    }

    /// Wraps the child when the backend delivers keys, and hands the child back
    /// when it does not -- the same shape, and the same reason, as
    /// ``OnScrollGestureModifier``: `@CastBackend` expands to `fatalError`.
    /// 當 backend 送得出按鍵時把子 view 包起來,送不出時原樣交回——形狀與理由都與
    /// ``OnScrollGestureModifier`` 相同:`@CastBackend` 會展開為 `fatalError`。
    func asWidget<Backend: BaseAppBackend>(
        _ children: Children,
        backend: Backend
    ) -> Backend.Widget {
        let child: Backend.Widget = children.child0.widget.into()
        guard let backend = backend as? any BaseAppBackend & BackendFeatures.KeyEvents
        else {
            KeyEventDegradation.reportOnce(backend: "\(Backend.self)")
            return child
        }
        return wrap(backend, child: child) as! Backend.Widget
    }

    private func wrap<Backend: BaseAppBackend & BackendFeatures.KeyEvents>(
        _ backend: Backend,
        child: Any
    ) -> Backend.Widget {
        backend.createKeyEventTarget(wrapping: child as! Backend.Widget)
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
        guard let backend = backend as? any BaseAppBackend & BackendFeatures.KeyEvents
        else { return }
        update(backend, widget: widget, environment: environment)
    }

    private func update<Backend: BaseAppBackend & BackendFeatures.KeyEvents>(
        _ backend: Backend,
        widget: Any,
        environment: EnvironmentValues
    ) {
        backend.updateKeyEventTarget(
            widget as! Backend.Widget,
            environment: environment,
            onKey: onKey
        )
    }
}

/// One report per backend, because a view commits on every update.
/// 每個 backend 只回報一次,因為一個 view 每次更新都會 commit。
enum KeyEventDegradation {
    nonisolated(unsafe) private static var reported: Set<String> = []

    static func reportOnce(backend: String) {
        guard !reported.contains(backend) else { return }
        reported.insert(backend)
        logger.warning(
            """
            input warning (the app keeps running and the view is still drawn and laid out): \
            \(backend) does not implement BackendFeatures.KeyEvents, so .onKeyPress \
            reports nothing on this backend -- keys pressed over the view go nowhere, \
            and modifier changes are not reported either. What to change: implement \
            the two methods of that protocol, and make the target able to take focus \
            while doing it, because a view that cannot be first responder receives no \
            keys however well the rest is written. AppKitBackend overrides keyDown, \
            keyUp and flagsChanged with acceptsFirstResponder; UIKitBackend uses \
            pressesBegan/pressesEnded with canBecomeFirstResponder; GTK has \
            GtkEventControllerKey, WinUI has KeyDown/KeyUp, and Android has \
            View.onKeyDown with setFocusableInTouchMode.
            """
        )
    }
}
