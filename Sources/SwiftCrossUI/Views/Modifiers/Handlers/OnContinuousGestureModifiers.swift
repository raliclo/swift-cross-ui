extension View {
    /// Reports a one-finger drag, or a mouse press-and-move, over this view.
    ///
    /// ```swift
    /// Rectangle()
    ///     .onDragGesture { value in
    ///         offset = value.translation
    ///     } onEnded: { _ in
    ///         offset = .zero
    ///     }
    /// ```
    ///
    /// **A modifier, not a `Gesture` value, which is a divergence from SwiftUI
    /// worth knowing before reaching for `.simultaneously(with:)`.** SwiftUI
    /// composes gestures -- `.sequenced`, `.simultaneously`, `.exclusively` --
    /// and that composition is a whole system: it needs a recogniser graph and
    /// a failure-requirement relation between the nodes. This package has
    /// ``onTapGesture(gesture:perform:)`` as a modifier and these three follow
    /// it, so a caller can attach one gesture per view and no more.
    ///
    /// 回報在這個 view 上的一指拖曳，或滑鼠按住並移動。
    ///
    /// **它是一個 modifier，不是一個 `Gesture` 值——這是與 SwiftUI 的一項差異，值得在伸手去用
    /// `.simultaneously(with:)` 之前先知道。** SwiftUI 會組合手勢(`.sequenced`、`.simultaneously`、
    /// `.exclusively`)，而那套組合本身是一整個系統:它需要一張辨識器的圖，以及節點之間的「失敗依賴」
    /// 關係。本套件的 ``onTapGesture(gesture:perform:)`` 是一個 modifier，而這三個沿用它——因此呼叫端
    /// 每個 view 可以掛一個手勢，不能更多。
    public func onDragGesture(
        onChanged: @escaping (DragGestureValue) -> Void,
        onEnded: @escaping (DragGestureValue) -> Void = { _ in }
    ) -> some View {
        OnDragGestureModifier(body: TupleView1(self), onChange: onChanged, onEnd: onEnded)
    }

    /// Reports a pinch, or a trackpad magnify, over this view.
    ///
    /// The value is cumulative from the start of the gesture: `1.0` at the
    /// beginning, `2.0` when the fingers have moved twice as far apart. See
    /// ``MagnifyGestureValue`` for why the accumulation is the backends' job.
    ///
    /// 回報在這個 view 上的捏合，或觸控板上的縮放。
    ///
    /// 該值自手勢開始起累計:一開始是 `1.0`，當兩指距離拉開為兩倍時是 `2.0`。累計為何由各 backend
    /// 負責，見 ``MagnifyGestureValue``。
    public func onMagnifyGesture(
        onChanged: @escaping (MagnifyGestureValue) -> Void,
        onEnded: @escaping (MagnifyGestureValue) -> Void = { _ in }
    ) -> some View {
        OnMagnifyGestureModifier(body: TupleView1(self), onChange: onChanged, onEnd: onEnded)
    }

    /// Reports a two-finger rotation over this view, in radians, clockwise
    /// positive.
    /// 回報在這個 view 上的兩指旋轉，單位為弧度，順時針為正。
    public func onRotateGesture(
        onChanged: @escaping (RotateGestureValue) -> Void,
        onEnded: @escaping (RotateGestureValue) -> Void = { _ in }
    ) -> some View {
        OnRotateGestureModifier(body: TupleView1(self), onChange: onChanged, onEnd: onEnded)
    }
}

struct OnDragGestureModifier<Content: View>: TypeSafeView {
    typealias Children = TupleView1<Content>.Children

    var body: TupleView1<Content>
    var onChange: (DragGestureValue) -> Void
    var onEnd: (DragGestureValue) -> Void

    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> Children {
        body.children(backend: backend, snapshots: snapshots, environment: environment)
    }

    @CastBackend<BackendFeatures.DragGestures>(returnsWidget: true)
    func asWidget<Backend: BaseAppBackend>(
        _ children: Children,
        backend: Backend
    ) -> Backend.Widget {
        backend.createDragGestureTarget(wrapping: children.child0.widget.into())
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

    @CastBackend<BackendFeatures.DragGestures>
    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        let size = children.child0.commit().size
        backend.setSize(of: widget, to: size.vector)
        backend.updateDragGestureTarget(
            widget,
            environment: environment,
            onChange: onChange,
            onEnd: onEnd
        )
    }
}

struct OnMagnifyGestureModifier<Content: View>: TypeSafeView {
    typealias Children = TupleView1<Content>.Children

    var body: TupleView1<Content>
    var onChange: (MagnifyGestureValue) -> Void
    var onEnd: (MagnifyGestureValue) -> Void

    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> Children {
        body.children(backend: backend, snapshots: snapshots, environment: environment)
    }

    @CastBackend<BackendFeatures.MagnifyGestures>(returnsWidget: true)
    func asWidget<Backend: BaseAppBackend>(
        _ children: Children,
        backend: Backend
    ) -> Backend.Widget {
        backend.createMagnifyGestureTarget(wrapping: children.child0.widget.into())
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

    @CastBackend<BackendFeatures.MagnifyGestures>
    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        let size = children.child0.commit().size
        backend.setSize(of: widget, to: size.vector)
        backend.updateMagnifyGestureTarget(
            widget,
            environment: environment,
            onChange: onChange,
            onEnd: onEnd
        )
    }
}

struct OnRotateGestureModifier<Content: View>: TypeSafeView {
    typealias Children = TupleView1<Content>.Children

    var body: TupleView1<Content>
    var onChange: (RotateGestureValue) -> Void
    var onEnd: (RotateGestureValue) -> Void

    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> Children {
        body.children(backend: backend, snapshots: snapshots, environment: environment)
    }

    @CastBackend<BackendFeatures.RotateGestures>(returnsWidget: true)
    func asWidget<Backend: BaseAppBackend>(
        _ children: Children,
        backend: Backend
    ) -> Backend.Widget {
        backend.createRotateGestureTarget(wrapping: children.child0.widget.into())
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

    @CastBackend<BackendFeatures.RotateGestures>
    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        let size = children.child0.commit().size
        backend.setSize(of: widget, to: size.vector)
        backend.updateRotateGestureTarget(
            widget,
            environment: environment,
            onChange: onChange,
            onEnd: onEnd
        )
    }
}
