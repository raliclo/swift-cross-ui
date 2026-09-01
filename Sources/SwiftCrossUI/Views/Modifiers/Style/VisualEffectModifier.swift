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

    // Degrades to the unmodified view rather than aborting the process.
    //
    // `@CastBackend` expands to `fatalError("'X' does not implement ...")`, which
    // is right where there is nothing to fall back to -- GtkBackend's WebView
    // and AngularGradient both rely on it. A compositing effect is not that
    // case. It changes what pixels look like and never what they mean, so a
    // backend without one can show the view plainly and the app keeps working.
    //
    // Measured 2026-09-01: AppKitBackend implements neither this nor
    // `GeometricEffects`, so P30 and P39 aborted at launch and had no window on
    // macOS at all. The abort was doing more damage than the missing feature --
    // one `.blur` anywhere in an app took the whole app down on a backend that
    // had not implemented it yet, and the app could not fall back to anything
    // because it never got to run.
    //
    // This is what the rest of the tree already does. `dismissWindow`,
    // `openURL` and the file dialogs all warn once and carry on;
    // `datePickerStyle(_:)` downgrades an unsupported style to `.automatic`.
    //
    // 降級為未經修飾的 view，而非中止行程。
    //
    // `@CastBackend` 會展開為 `fatalError("'X' does not implement ...")`，而在沒有任何退路可言之處，
    // 那是對的——GtkBackend 的 WebView 與 AngularGradient 都倚賴它。合成效果不屬於那種情況。它改變
    // 的是像素的外觀，從不改變其意義，因此沒有該功能的 backend 可以平實地顯示該 view，而 app 仍能繼續運作。
    //
    // 2026-09-01 量測：AppKitBackend 既未實作本項、也未實作 `GeometricEffects`，因此 P30 與 P39 在
    // 啟動時即中止，在 macOS 上根本沒有視窗。那次中止造成的損害大於缺失功能本身——app 中任何一處的
    // 一個 `.blur`，就會在尚未實作它的 backend 上拖垮整個 app，而 app 也無從退回任何替代方案，
    // 因為它根本沒有機會執行。
    //
    // 這也正是這棵樹其餘部分已經在做的事。`dismissWindow`、`openURL` 與各個檔案對話框都是警告一次
    // 後繼續；`datePickerStyle(_:)` 則把不支援的樣式降級為 `.automatic`。
    func asWidget<Backend: BaseAppBackend>(
        _ children: Children,
        backend: Backend
    ) -> Backend.Widget {
        let inner = body.asWidget(children, backend: backend)

        func wrap<B: BaseAppBackend & BackendFeatures.VisualEffects>(backend: B) -> B.Widget {
            backend.createVisualEffectContainer(wrapping: inner as! B.Widget)
        }
        guard let capable = backend as? any BaseAppBackend & BackendFeatures.VisualEffects
        else {
            logger.warnOnce(
                "\(type(of: backend)) doesn't support visual effects; showing the view unmodified"
            )
            return inner
        }
        return wrap(backend: capable) as! Backend.Widget
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

    // No warning here. `asWidget` has already reported it, and this runs on
    // every update -- warnOnce dedupes by source location, so a second call site
    // would add a second line saying the same thing rather than a repeat of the
    // first. In the degraded case `widget` is the child's own widget, since that
    // is what `asWidget` returned, and setting it to the size the child just
    // committed is the same value it already has.
    // 此處不發出警告。`asWidget` 已經回報過了，而本方法在每次更新時都會執行——warnOnce 是依原始碼
    // 位置去重的，因此第二個呼叫點只會多出一行說著同樣的事，而非重複第一行。在降級的情況下，
    // `widget` 就是子元件自己的 widget（因為那正是 `asWidget` 所回傳的），而把它設為子元件剛剛
    // commit 的尺寸，就是它已經具有的那個值。
    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        let size = children.child0.commit().size
        backend.setSize(of: widget, to: size.vector)

        func apply<B: BaseAppBackend & BackendFeatures.VisualEffects>(backend: B) {
            backend.setVisualEffect(effect, ofWidget: widget as! B.Widget)
        }
        guard let capable = backend as? any BaseAppBackend & BackendFeatures.VisualEffects
        else {
            return
        }
        apply(backend: capable)
    }
}
