extension View {
    /// Sets the transparency of this view.
    ///
    /// - Parameter opacity: 0 is invisible, 1 leaves the view unchanged.
    /// 設定此 view 的透明度。0 為完全不可見，1 為維持原樣。
    public func opacity(_ opacity: Double) -> some View {
        visualEffect(VisualEffect(opacity: opacity))
    }

    /// Applies a Gaussian blur to this view.
    ///
    /// - Parameter radius: The blur radius, in points. 0 leaves it sharp.
    /// 對此 view 套用高斯模糊。radius 的單位為點，0 表示不模糊。
    public func blur(radius: Double) -> some View {
        visualEffect(VisualEffect(blurRadius: radius))
    }

    /// Adjusts the colour intensity of this view.
    ///
    /// - Parameter amount: 0 is fully desaturated, 1 leaves it unchanged.
    /// 調整此 view 的色彩濃度。0 為完全去飽和，1 為維持原樣。
    public func saturation(_ amount: Double) -> some View {
        visualEffect(VisualEffect(saturation: amount))
    }

    /// Brightens this view by adding to each colour channel.
    ///
    /// - Parameter amount: 0 leaves the view unchanged.
    /// 藉由對每個色彩通道做加法來提亮此 view。0 為維持原樣。
    public func brightness(_ amount: Double) -> some View {
        visualEffect(VisualEffect(brightness: amount))
    }

    /// Adjusts the contrast of this view.
    ///
    /// - Parameter amount: 1 leaves the view unchanged, 0 flattens it to grey.
    /// 調整此 view 的對比。1 為維持原樣，0 會把它壓平為灰色。
    public func contrast(_ amount: Double) -> some View {
        visualEffect(VisualEffect(contrast: amount))
    }

    /// Pushes this view towards grey.
    ///
    /// - Parameter amount: 0 leaves it unchanged, 1 is fully grey.
    /// 把此 view 推向灰階。0 為維持原樣，1 為完全灰階。
    public func grayscale(_ amount: Double) -> some View {
        visualEffect(VisualEffect(grayscale: amount))
    }

    /// Rotates the hues of this view around the colour wheel.
    /// 讓此 view 的色相繞色輪旋轉。
    public func hueRotation(_ angle: Angle) -> some View {
        visualEffect(VisualEffect(hueRotation: angle))
    }

    /// Applies several compositing effects in one container.
    ///
    /// Public because the seven modifiers above each wrap separately, so
    /// `.saturation(0).brightness(0.2)` builds two containers. That is correct
    /// and matches SwiftUI, but when several effects are known together this
    /// says so in one.
    ///
    /// 以單一容器套用多種合成效果。
    ///
    /// 之所以公開：上方七個 modifier 各自會包一層，因此 `.saturation(0).brightness(0.2)` 會建立兩個
    /// 容器。那是正確的、也與 SwiftUI 一致，但當多種效果本來就是一起決定的，此處可用一個容器表達。
    public func visualEffect(_ effect: VisualEffect) -> some View {
        VisualEffectModifier(content: self, effect: effect)
    }
}

struct VisualEffectModifier<Content: View>: View, TypeSafeView {
    var content: Content
    var effect: VisualEffect

    var body: TupleView1<Content> { content }

    typealias Children = TupleView1<Content>.Children

    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> Children {
        body.children(backend: backend, snapshots: snapshots, environment: environment)
    }

    @CastBackend<BackendFeatures.VisualEffects>(returnsWidget: true)
    func asWidget<Backend: BaseAppBackend>(
        _ children: Children,
        backend: Backend
    ) -> Backend.Widget {
        backend.createVisualEffectContainer(wrapping: body.asWidget(children, backend: backend))
    }

    func layoutableChildren<Backend: BaseAppBackend>(
        backend: Backend,
        children: Children
    ) -> [LayoutSystem.LayoutableChild] {
        body.layoutableChildren(backend: backend, children: children)
    }

    // Unchanged from the child. A compositing effect changes what the pixels
    // look like, never how much room the view takes, which is why blurring
    // something does not reflow the page around it.
    // 與子元件相同。合成效果改變的是像素的外觀，絕不改變 view 佔用的空間——這正是「把某個東西
    // 模糊化不會讓周圍版面重排」的原因。
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

    @CastBackend<BackendFeatures.VisualEffects>
    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        let size = children.child0.commit().size
        backend.setSize(of: widget, to: size.vector)
        backend.setVisualEffect(effect, ofWidget: widget)
    }
}
