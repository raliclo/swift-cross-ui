extension View {
    /// Controls whether this view and its children can receive pointer events.
    ///
    /// `allowsHitTesting(false)` puts a view out of reach of the pointer without
    /// hiding it or changing its layout. The usual reason is a decorative layer
    /// over something interactive — a measuring overlay, a gradient, a
    /// highlight — which would otherwise take the clicks meant for what is
    /// underneath.
    ///
    /// Subtree-wide, matching SwiftUI: a nested `allowsHitTesting(true)` does
    /// not undo it. The toolkits express this as one flag on the widget, and
    /// re-enabling below it would mean walking the subtree and remembering each
    /// widget's own setting.
    ///
    /// A backend without a way to express this ignores it, leaving the view
    /// interactive when it was asked not to be. That is visible and reportable,
    /// which no other fallback would be.
    ///
    /// 控制此 view 及其子元件是否能接收指標事件。
    ///
    /// `allowsHitTesting(false)` 會使 view 脫離指標的觸及範圍，但不隱藏它、也不改變其版面。常見
    /// 用途是覆蓋在可互動元件之上的裝飾性圖層——量測用的 overlay、漸層、強調效果——否則它們會奪走
    /// 原本要給下方元件的點擊。
    ///
    /// 其作用範圍及於整個子樹，與 SwiftUI 一致：巢狀的 `allowsHitTesting(true)` 無法將其還原。
    /// 各 toolkit 都以 widget 上的單一旗標表達此語意，而要在其下重新啟用，就必須走訪整個子樹並
    /// 記住每一個 widget 自身的設定。
    ///
    /// 無法表達此語意的 backend 會忽略它，使該 view 在被要求不可互動時仍可互動。這是看得見、也
    /// 回報得出來的結果，而其他任何 fallback 都做不到這一點。
    ///
    /// - Parameter allowsHitTesting: Whether the view can be hit.
    public func allowsHitTesting(_ allowsHitTesting: Bool = true) -> some View {
        AllowsHitTestingModifier(content: self, allowsHitTesting: allowsHitTesting)
    }
}

struct AllowsHitTestingModifier<Content: View>: View, TypeSafeView {
    var content: Content
    var allowsHitTesting: Bool

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
        body.computeLayout(
            widget,
            children: children,
            proposedSize: proposedSize,
            environment: environment,
            backend: backend
        )
    }

    @CastBackend<BackendFeatures.HitTesting>
    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        // No wrapper widget of its own. The flag goes on the content's widget,
        // so the modifier costs nothing in layout and cannot change how the
        // content is sized -- which matters because the usual use is on a layer
        // whose geometry is already load-bearing.
        //
        // 不建立自己的包裝 widget。該旗標直接設在內容的 widget 上，因此此 modifier 在版面上毫無
        // 成本，也不可能改變內容的尺寸——這一點很重要，因為它最常用於「幾何本身已具關鍵作用」的
        // 圖層之上。
        body.commit(
            widget,
            children: children,
            layout: layout,
            environment: environment,
            backend: backend
        )
        backend.setHitTesting(of: widget, to: allowsHitTesting)
    }
}
