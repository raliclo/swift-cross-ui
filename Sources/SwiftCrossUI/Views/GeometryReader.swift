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

        var environment = environment.with(\.layoutAlignment, .leading)
        // The content is built fresh from the closure on every pass, so a body
        // kept from the last pass is not this content's body. Reusing it is
        // right for the children of a kept body -- their values did not change
        // -- and wrong here: with it on, P63 on iOS logged the new origin from
        // inside the closure while its Text still drew x=0 y=0, because each
        // node below served its old body to commit (2026-09-30).
        //
        // 內容每一輪都由 closure 重新建立,所以上一輪保留下來的 body 並不是這份內容的 body。對「被保留
        // 的 body」的子元件而言重用是對的——它們的值沒有改變——在這裡則是錯的:開著它時,iOS 上的
        // P63 在 closure 內記下了新的原點,它的 Text 卻仍畫著 x=0 y=0,因為底下每個節點交給 commit 的
        // 都是舊的 body(2026-09-30)。
        environment.reusesBodies = false

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
            // Deferred, not called here. This runs INSIDE the commit, and every
            // node keeps its layout cache until its commit ends
            // (`ViewGraphNode.commit` clears it after `view.commit`). An update
            // requested now re-entered layout with those caches still full, so
            // each node returned its old layout and the reader was never
            // recomputed: on iOS P63 kept global x=0 y=0 after UIKit had
            // answered (47, 558) -- traced 2026-09-30 -- and AppKit only showed
            // the right numbers because unrelated passes followed.
            //
            // 延後，而不是在這裡呼叫。這段執行於 commit **之中**，而每個節點的版面快取要到它的 commit
            // 結束時才清除（`ViewGraphNode.commit` 在 `view.commit` 之後清除）。在此時要求的更新會在
            // 快取仍滿的情況下重新進入版面計算，於是每個節點都回傳舊的版面、reader 從未被重算:iOS 上的
            // P63 在 UIKit 已回答 (47, 558) 之後仍是 global x=0 y=0——2026-09-30 追蹤得知——而 AppKit
            // 之所以顯示正確數字，只是因為之後剛好有無關的輪次。
            //
            // And through `onResize`, not `requestWindowUpdate`. This
            // environment is the PARENT node's, so `onResize` makes the parent
            // re-lay out its subtree with its kept body -- recomputing this
            // reader with the new origin -- and then commit that subtree, the
            // path a child resize takes. A deferred window update still left
            // the screen at x=0 y=0 while the log read (47, 558): the
            // recomputed content never reached the widgets.
            //
            // 並且經由 `onResize` 而非 `requestWindowUpdate`。此處的 environment 是**父**節點的,
            // 所以 `onResize` 會讓父節點以保留的 body 重排它的子樹——以新的原點重算這個 reader——然後
            // commit 該子樹,也就是子元件改變尺寸時所走的路徑。延後的視窗更新仍讓畫面停在 x=0 y=0,
            // 而 log 已讀到 (47, 558):重算出的內容從未抵達 widget。
            let size = layout.size
            backend.runInMainThread {
                environment.onResize(size)
            }
        } else if origin == nil, !children.retryScheduled {
            // No answer yet, because the widget is not in a window yet. Ask
            // once more on the next turn of the main loop, after the tree
            // is attached. Without this, a backend that says nil at the first
            // commit is never asked again unless something else happens to
            // update the window: on iOS nothing does, and P63 showed
            // global x=0 y=0 permanently while its marker sat at about
            // (49, 583) points (2026-09-30). AppKit only looked right because
            // later passes happened to follow. One retry per nil answer, and
            // a retry that is still nil schedules nothing, so this cannot
            // loop.
            //
            // 還沒有答案，因為 widget 還不在視窗裡。在主迴圈的下一輪、樹掛上之後再問一次。沒有這一步，
            // 一個在第一次 commit 回答 nil 的 backend 就再也不會被問，除非別的東西剛好更新了視窗:在
            // iOS 上沒有任何東西會，而 P63 就永遠顯示 global x=0 y=0，儘管它的標記約在 (49, 583) 點
            // (2026-09-30)。AppKit 看起來正確，只是因為之後剛好有別的輪次。每個 nil 答案只重試一次，
            // 而重試仍為 nil 時不再排程任何東西，因此不會形成迴圈。
            children.retryScheduled = true
            let widget = AnyWidget(widget)
            let size = layout.size
            backend.runInMainThread { [weak children] in
                guard let children else { return }
                children.retryScheduled = false
                let later = Self.originInWindow(
                    of: widget.into() as Backend.Widget,
                    backend: backend
                )
                if later != nil, later != (children.originUsed ?? nil) {
                    children.originUsed = later
                    environment.onResize(size)
                }
            }
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

    /// A deferred "where did it land?" is pending; see `commit`.
    /// 一次延後的「它落在哪裡?」正在等待;見 `commit`。
    var retryScheduled = false

    var widgets: [AnyWidget] {
        [node?.widget].compactMap { $0 }
    }

    var erasedNodes: [ErasedViewGraphNode] {
        [node.map(ErasedViewGraphNode.init(wrapping:))].compactMap { $0 }
    }
}
