extension View {
    /// Sets the area of this view that receives taps and clicks.
    ///
    /// A pointer inside `shape` hits the view; a pointer elsewhere in its
    /// frame goes on to whatever is underneath, as if the view were not
    /// there. `.contentShape(Circle())` on a square makes only the circle
    /// tappable -- a tap in a corner reaches the view below -- and
    /// `.contentShape(Rectangle())` makes the whole frame tappable, gaps
    /// between a stack's children included.
    ///
    /// The shape is resolved in the view's bounds after every layout, so it
    /// follows the view when it changes size. Drawing and layout are not
    /// affected.
    ///
    /// A tap gesture applied to the view, `.contentShape(Circle()).onTapGesture { ... }`,
    /// takes the same shape: it is resolved again in the tap target's own
    /// bounds, so a `.padding` or `.frame` between the two resolves the
    /// shape in the larger frame rather than the inner one.
    ///
    /// Taps, clicks and touches follow the shape on AppKitBackend, UIKitBackend,
    /// GtkBackend, WinUIBackend and AndroidBackend. Hover tracking is not
    /// limited by it. A backend without ``BackendFeatures/ContentShapes``
    /// shows the view with its whole frame hittable and logs a warning once.
    ///
    /// 設定此 view 接收點擊與觸控的區域。
    ///
    /// 指標位於 `shape` 之內時命中此 view；位於其 frame 其他地方時，則繼續前往下方的東西，如同此
    /// view 不存在。正方形上的 `.contentShape(Circle())` 只讓圓形可被點擊——點在角落會到達下方
    /// 的 view——而 `.contentShape(Rectangle())` 讓整個 frame 都可被點擊，包括 stack 子元件之間
    /// 的空隙。
    ///
    /// 形狀在每次排版之後依 view 的 bounds 解析，因此 view 改變尺寸時會跟著它。不影響繪圖與排版。
    ///
    /// 套用在此 view 上的點擊手勢，`.contentShape(Circle()).onTapGesture { ... }`，會沿用同一個
    /// 形狀：它在點擊目標自己的 bounds 中重新解析，因此兩者之間若有 `.padding` 或 `.frame`，形狀會
    /// 在較大的 frame 中解析，而不是內層的。
    ///
    /// 在 AppKitBackend、UIKitBackend、GtkBackend、WinUIBackend 與 AndroidBackend 上，點擊與
    /// 觸控都依循該形狀。滑鼠懸停的追蹤不受它限制。不具 ``BackendFeatures/ContentShapes`` 的
    /// backend 會以整個 frame 可被點中的方式顯示此 view，並記錄一次警告。
    ///
    /// - Parameters:
    ///   - shape: The area that receives hits, in the view's bounds.
    ///   - eoFill: Whether the shape is filled by the even-odd rule rather
    ///     than non-zero winding, which decides what is inside a path that
    ///     crosses itself or has a hole.
    public func contentShape(_ shape: some Shape, eoFill: Bool = false) -> some View {
        ContentShapeModifier(
            content: self,
            shape: ContentShape(shape: shape, eoFill: eoFill)
        )
    }
}

/// A shape set by ``View/contentShape(_:eoFill:)``, kept unresolved so that
/// each widget that uses it can resolve it in its own bounds.
///
/// 由 ``View/contentShape(_:eoFill:)`` 設定的形狀，保持未解析，讓使用它的每個 widget 都能
/// 依自己的 bounds 解析。
struct ContentShape: Sendable {
    var shape: any Shape
    var eoFill: Bool

    /// The shape resolved in a frame of the given size.
    /// 在給定尺寸的 frame 中解析後的形狀。
    func region(in size: ViewSize) -> HitRegion {
        let bounds = Path.Rect(x: 0, y: 0, width: size.width, height: size.height)
        return HitRegion(path: shape.path(in: bounds), evenOdd: eoFill)
    }
}

struct ContentShapeModifier<Content: View>: View, TypeSafeView {
    var content: Content
    var shape: ContentShape

    var body: TupleView1<Content> { content }

    typealias Children = TupleView1<Content>.Children

    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> Children {
        body.children(backend: backend, snapshots: snapshots, environment: environment)
    }

    func asWidget<Backend: BaseAppBackend>(
        _ children: Children,
        backend: Backend
    ) -> Backend.Widget {
        body.asWidget(children, backend: backend)
    }

    func layoutableChildren<Backend: BaseAppBackend>(
        backend: Backend,
        children: Children
    ) -> [LayoutSystem.LayoutableChild] {
        body.layoutableChildren(backend: backend, children: children)
    }

    func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        // The shape goes up as a preference so that a tap gesture applied
        // to this view can take it for its own target; see
        // `PreferenceValues.contentShape`.
        // 形狀以 preference 向上傳遞，讓套用在此 view 上的點擊手勢能把它用於自己的目標；見
        // `PreferenceValues.contentShape`。
        var result = body.computeLayout(
            widget,
            children: children,
            proposedSize: proposedSize,
            environment: environment,
            backend: backend
        )
        result.preferences.contentShape = shape
        return result
    }

    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        // No wrapper widget, as with `allowsHitTesting`: the shape goes on the
        // content's own widget, so layout and drawing are untouched.
        // 與 `allowsHitTesting` 相同，不建立包裝 widget：形狀直接設在內容自己的 widget 上，因此排版
        // 與繪圖都不受影響。
        body.commit(
            widget,
            children: children,
            layout: layout,
            environment: environment,
            backend: backend
        )
        let region = shape.region(in: layout.size)
        if !backend.setContentShapeIfSupported(of: widget, to: region) {
            logger.warnOnce(
                "\(type(of: backend)) doesn't support contentShape; the whole frame stays hittable"
            )
        }
    }
}
