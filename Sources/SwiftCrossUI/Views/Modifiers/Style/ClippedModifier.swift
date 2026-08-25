extension View {
    /// Clips this view to its bounds, cutting off anything its content draws
    /// outside them.
    ///
    /// The explicit counterpart to clipping via ``View/cornerRadius(_:)``: it
    /// asks for a rectangular clip without also rounding the corners, matching
    /// SwiftUI's `.clipped()`. The usual use is a resizable image given a smaller
    /// frame than its pixels, which would otherwise overflow the frame.
    ///
    /// A backend without a way to express this ignores it, leaving the content
    /// overflowing. That is visible and reportable, which no other fallback
    /// would be.
    ///
    /// 將此 view 裁切至其邊界,切除其內容繪製在邊界外的部分。
    ///
    /// 這是「透過 ``View/cornerRadius(_:)`` 裁切」的顯式對應版本:它要求矩形裁切但不圓角,與
    /// SwiftUI 的 `.clipped()` 一致。常見用途是一張被賦予比其像素更小 frame 的 resizable 圖片,
    /// 否則它會溢出該 frame。
    ///
    /// 無法表達此語意的 backend 會忽略它,使內容仍然溢出。這是看得見、也回報得出來的結果,而其他
    /// 任何 fallback 都做不到這一點。
    public func clipped() -> some View {
        ClippedModifier(body: TupleView1(self))
    }
}

struct ClippedModifier<Child: View>: TypeSafeView {
    var body: TupleView1<Child>

    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> TupleViewChildren1<Child> {
        body.children(backend: backend, snapshots: snapshots, environment: environment)
    }

    @CastBackend<BackendFeatures.Clipping>(returnsWidget: true)
    func asWidget<Backend: BaseAppBackend>(
        _ children: TupleViewChildren1<Child>,
        backend: Backend
    ) -> Backend.Widget {
        let container = backend.createClippedContainer()
        backend.insert(children.child0.widget.into(), into: container, at: 0)
        return container
    }

    func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: TupleViewChildren1<Child>,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        // Size-preserving: clip to the child's own layout, do not change it.
        let childResult = children.child0.computeLayout(
            with: body.view0,
            proposedSize: proposedSize,
            environment: environment
        )
        return ViewLayoutResult(size: childResult.size, childResults: [childResult])
    }

    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: TupleViewChildren1<Child>,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        let childSize = children.child0.commit().size
        // Pin the clip container to the child's size and the child at the origin;
        // the container clips anything the child draws past that box.
        backend.setSize(of: widget, to: childSize.vector)
        backend.setPosition(ofChildAt: 0, in: widget, to: .zero)
    }
}
