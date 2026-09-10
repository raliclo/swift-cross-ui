/// A container view that allows its content to read the size proposed to it.
///
/// Geometry readers always take up the size proposed to them; no more, no less.
/// This is to decouple the geometry reader's size from the size of its content
/// in order to avoid feedback loops.
///
/// ```swift
/// struct MeasurementView: View {
///     var body: some View {
///         GeometryReader { proxy in
///             Text("Width: \(proxy.size.width)")
///             Text("Height: \(proxy.size.height)")
///         }
///     }
/// }
/// ```
///
/// > Note: Geometry reader content may get evaluated multiple times with various
/// > sizes before the layout system settles on a size. Do not depend on the size
/// > proposal always being final.
public struct GeometryReader<Content: View>: TypeSafeView, View {
    var content: (GeometryProxy) -> Content

    public var body = EmptyView()

    public init(@ViewBuilder content: @escaping (GeometryProxy) -> Content) {
        self.content = content
    }

    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> GeometryReaderChildren<Content> {
        GeometryReaderChildren()
    }

    func layoutableChildren<Backend: BaseAppBackend>(
        backend: Backend,
        children: GeometryReaderChildren<Content>
    ) -> [LayoutSystem.LayoutableChild] {
        []
    }

    func asWidget<Backend: BaseAppBackend>(
        _ children: GeometryReaderChildren<Content>,
        backend: Backend
    ) -> Backend.Widget {
        // This is a little different to our usual wrapper implementations
        // because we want to avoid calling the user's content closure before
        // we actually have to.
        return backend.createContainer()
    }

    func computeLayout<Backend: BaseAppBackend>(
        _ container: Backend.Widget,
        children: GeometryReaderChildren<Content>,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        let size = proposedSize.replacingUnspecifiedDimensions(by: ViewSize(10, 10))

        // Where this reader sits, taken from what COMMIT last learned.
        //
        // Not asked here, and that is the whole of the ordering problem: at
        // layout time this widget has not been placed yet, so the backend has
        // nothing to say. `commit` runs after the placement and asks then; if
        // the answer differs from the one the content was built with, it asks
        // for another pass. Pass one reports a nil origin, pass two reports the
        // real one, and pass three never happens because the answer stopped
        // changing.
        //
        // 這個 reader 位於何處，取自 **commit 上一次得知的結果**。
        //
        // 不在此處詢問，而那正是整個順序問題之所在:在版面計算的當下，這個 widget 還沒有被放置，
        // 因此 backend 無話可說。`commit` 執行於放置之後、並在那時詢問;若答案與「內容當初據以建立
        // 的那一個」不同，它就要求再排一輪。第一輪回報的原點是 nil、第二輪回報真正的值，而第三輪
        // 不會發生——因為答案不再改變。
        let origin = children.originUsed ?? nil

        let view = content(
            GeometryProxy(
                size: size,
                originInWindow: origin,
                namedOrigins: environment.namedCoordinateSpaces
            )
        )

        let environment = environment.with(\.layoutAlignment, .leading)

        let contentNode: AnyViewGraphNode<Content>
        if let node = children.node {
            contentNode = node
        } else {
            contentNode = AnyViewGraphNode(
                for: view,
                backend: backend,
                environment: environment
            )
            children.node = contentNode

            backend.insert(contentNode.widget.into(), into: container, at: 0)
        }

        let contentResult = contentNode.computeLayout(
            with: view,
            proposedSize: ProposedViewSize(size),
            environment: environment
        )

        return ViewLayoutResult(
            size: size,
            childResults: [contentResult]
        )
    }

    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: GeometryReaderChildren<Content>,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        _ = children.node?.commit()
        backend.setPosition(ofChildAt: 0, in: widget, to: .zero)
        backend.setSize(of: widget, to: layout.size.vector)

        // Now that it is placed, ask where it landed.
        // 現在它已經被放置了，去問它落在哪裡。
        let origin = Self.originInWindow(of: widget, backend: backend)
        if origin != nil, origin != (children.originUsed ?? nil) {
            children.originUsed = origin
            environment.requestWindowUpdate()
        }
    }
}

extension GeometryReader {
    @MainActor
    static func originInWindow<Backend: BaseAppBackend>(
        of widget: Backend.Widget,
        backend: Backend
    ) -> SIMD2<Int>? {
        guard let geometryBackend = backend as? any BackendFeatures.WidgetGeometry
        else { return nil }
        @MainActor
        func ask<B: BackendFeatures.WidgetGeometry>(_ backend: B) -> SIMD2<Int>? {
            backend.originInWindow(ofWidget: widget as! B.Widget)
        }
        return ask(geometryBackend)
    }
}

class GeometryReaderChildren<Content: View>: ViewGraphNodeChildren {
    var node: AnyViewGraphNode<Content>?

    /// The origin the content was last built with.
    ///
    /// Kept so that "the position changed" can be told from "the position is
    /// the same", which is the difference between asking for one more pass and
    /// asking for one on every pass forever.
    ///
    /// 內容上一次據以建立的那個原點。
    ///
    /// 保留它，是為了能分辨「位置改變了」與「位置沒有變」——而那正是「再要求一輪」與「從此每一輪
    /// 都要求一輪」之間的差別。
    var originUsed: SIMD2<Int>??

    var widgets: [AnyWidget] {
        [node?.widget].compactMap { $0 }
    }

    var erasedNodes: [ErasedViewGraphNode] {
        [node.map(ErasedViewGraphNode.init(wrapping:))].compactMap { $0 }
    }
}
