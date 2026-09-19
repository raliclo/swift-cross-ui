extension View {
    /// Reports a scroll wheel, trackpad scroll or touch scroll over this view,
    /// without moving anything.
    ///
    /// ```swift
    /// Mesh3DView(scene)
    ///     .onScrollGesture { value in
    ///         distance -= value.delta.y * 0.01
    ///     }
    /// ```
    ///
    /// See ``ScrollGestureValue`` for the sign convention -- positive `delta.y`
    /// is forward through the content -- and for why there is no momentum flag.
    ///
    /// 回報這個 view 上的滾輪、觸控板捲動或觸控捲動,而且**不移動任何東西**。
    ///
    /// 正負號的約定見 ``ScrollGestureValue``(`delta.y` 為正表示往內容的前方),以及為何沒有 momentum 旗標。
    public func onScrollGesture(
        onChanged: @escaping (ScrollGestureValue) -> Void,
        onEnded: @escaping (ScrollGestureValue) -> Void = { _ in }
    ) -> some View {
        OnScrollGestureModifier(body: TupleView1(self), onChange: onChanged, onEnd: onEnded)
    }
}

struct OnScrollGestureModifier<Content: View>: TypeSafeView {
    typealias Children = TupleView1<Content>.Children

    var body: TupleView1<Content>
    var onChange: (ScrollGestureValue) -> Void
    var onEnd: (ScrollGestureValue) -> Void

    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> Children {
        body.children(backend: backend, snapshots: snapshots, environment: environment)
    }

    /// Wraps the child when the backend can deliver scrolls, and hands the
    /// child straight back when it cannot.
    ///
    /// **The unwrapped case is why this is not `@CastBackend`.** That macro
    /// expands to `fatalError`, and on 2026-09-02 that cost three test apps
    /// their windows on macOS for one missing conformance. Returning the child
    /// means the view still renders, still lays out, and simply reports no
    /// scrolls.
    ///
    /// 當 backend 送得出捲動時把子 view 包起來;送不出時就把子 view 原樣交回。
    ///
    /// **「不包起來」的那條路徑,正是這裡不用 `@CastBackend` 的理由。** 那個 macro 會展開為
    /// `fatalError`,而 2026-09-02 那一次,一個缺失的 conformance 讓三支測試 app 在 macOS 上沒有視窗。
    /// 交回子 view,代表那個 view 照常繪製、照常排版,只是不回報任何捲動。
    func asWidget<Backend: BaseAppBackend>(
        _ children: Children,
        backend: Backend
    ) -> Backend.Widget {
        let child: Backend.Widget = children.child0.widget.into()
        guard let backend = backend as? any BaseAppBackend & BackendFeatures.ScrollGestures
        else {
            ScrollGestureDegradation.reportOnce(backend: "\(Backend.self)")
            return child
        }
        return wrap(backend, child: child) as! Backend.Widget
    }

    private func wrap<Backend: BaseAppBackend & BackendFeatures.ScrollGestures>(
        _ backend: Backend,
        child: Any
    ) -> Backend.Widget {
        backend.createScrollGestureTarget(wrapping: child as! Backend.Widget)
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
        guard let backend = backend as? any BaseAppBackend & BackendFeatures.ScrollGestures
        else { return }
        update(backend, widget: widget, environment: environment)
    }

    private func update<Backend: BaseAppBackend & BackendFeatures.ScrollGestures>(
        _ backend: Backend,
        widget: Any,
        environment: EnvironmentValues
    ) {
        backend.updateScrollGestureTarget(
            widget as! Backend.Widget,
            environment: environment,
            onChange: onChange,
            onEnd: onEnd
        )
    }
}

/// One report per backend, because a view commits on every update.
/// 每個 backend 只回報一次,因為一個 view 每次更新都會 commit。
enum ScrollGestureDegradation {
    nonisolated(unsafe) private static var reported: Set<String> = []

    static func reportOnce(backend: String) {
        guard !reported.contains(backend) else { return }
        reported.insert(backend)
        logger.warning(
            """
            input warning (the app keeps running and the view is still drawn and laid out): \
            \(backend) does not implement BackendFeatures.ScrollGestures, so \
            .onScrollGesture reports nothing on this backend -- a wheel turn or a \
            two-finger scroll over the view does nothing at all. What to change: \
            implement the two methods of that protocol on this backend. \
            AppKitBackend overrides NSView.scrollWheel(with:) and UIKitBackend uses \
            a UIPanGestureRecognizer with allowedScrollTypesMask; GTK has \
            GtkEventControllerScroll, WinUI has PointerWheelChanged, and Android has \
            onGenericMotionEvent with AXIS_VSCROLL.
            """
        )
    }
}
