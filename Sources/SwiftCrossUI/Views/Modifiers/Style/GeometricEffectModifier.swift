import Foundation

extension View {
    /// Draws this view offset from where it was laid out.
    ///
    /// The layout is unchanged: neighbours keep their positions and the view
    /// keeps its size, so this moves pixels rather than reflowing anything.
    /// Use `padding` or a stack to move a view *and* what is around it.
    ///
    /// 把此 view 畫在偏離其排版位置之處。版面不變：鄰居維持原位、view 維持原尺寸，因此這是搬動
    /// 像素而非重排版面。若要連同周圍一起移動，請使用 padding 或 stack。
    public func offset(x: Double = 0, y: Double = 0) -> some View {
        geometricEffect(GeometricEffect(translation: SIMD2(x, y)))
    }

    /// Rotates this view around an anchor point.
    ///
    /// - Parameters:
    ///   - angle: How far to rotate, clockwise.
    ///   - anchor: The point held fixed, in unit space. Defaults to the centre.
    /// 以某個錨點為中心旋轉此 view。anchor 為單位空間中「保持不動」的點，預設為中心。
    public func rotationEffect(_ angle: Angle, anchor: UnitPoint = .center) -> some View {
        geometricEffect(GeometricEffect(rotation: angle, anchor: anchor))
    }

    /// Scales this view around an anchor point.
    ///
    /// - Parameters:
    ///   - scale: The factor to scale both axes by.
    ///   - anchor: The point held fixed, in unit space. Defaults to the centre.
    /// 以某個錨點為中心縮放此 view。
    public func scaleEffect(_ scale: Double, anchor: UnitPoint = .center) -> some View {
        geometricEffect(GeometricEffect(scale: SIMD2(scale, scale), anchor: anchor))
    }

    /// Scales this view's axes independently around an anchor point.
    /// 以某個錨點為中心，分別縮放此 view 的兩個軸。
    public func scaleEffect(
        x: Double = 1,
        y: Double = 1,
        anchor: UnitPoint = .center
    ) -> some View {
        geometricEffect(GeometricEffect(scale: SIMD2(x, y), anchor: anchor))
    }

    /// Draws this view under an arbitrary affine transform.
    ///
    /// Unlike the modifiers above this takes no anchor: a matrix is already
    /// expressed about the view's origin, which is what SwiftUI's
    /// `transformEffect(_:)` does too.
    ///
    /// 以任意仿射變換繪製此 view。與上方各 modifier 不同，此處不接受錨點：矩陣本就是相對於 view
    /// 原點所表達的，SwiftUI 的 `transformEffect(_:)` 亦然。
    public func transformEffect(_ transform: AffineTransform) -> some View {
        geometricEffect(GeometricEffect(matrix: transform))
    }

    /// Applies several geometric effects in one container.
    /// 以單一容器套用多種幾何效果。
    public func geometricEffect(_ effect: GeometricEffect) -> some View {
        GeometricEffectModifier(content: self, effect: effect)
    }
}

/// A transform expressed the way the modifiers above express it, before its
/// anchor has been resolved.
///
/// Kept unresolved until `commit` because an anchor is a fraction of the view's
/// size, and the size is not known when the modifier is built. Storing the
/// resolved matrix here would mean either guessing the size or rebuilding the
/// view tree whenever it changed.
///
/// 以上方各 modifier 所使用的方式表達的變換，其錨點尚未解析。
///
/// 之所以延到 `commit` 才解析：錨點是 view 尺寸的一個比例，而 modifier 被建立時尺寸尚屬未知。若在
/// 此處存放已解析的矩陣，就只能靠猜測尺寸、或在尺寸改變時重建整個 view tree。
public struct GeometricEffect: Equatable, Sendable {
    public var translation: SIMD2<Double>
    public var scale: SIMD2<Double>
    public var rotation: Angle
    public var anchor: UnitPoint

    /// An arbitrary transform, applied before the components above.
    /// 任意變換，其套用順序在上述各項之前。
    public var matrix: AffineTransform

    public init(
        translation: SIMD2<Double> = .zero,
        scale: SIMD2<Double> = SIMD2(1, 1),
        rotation: Angle = .zero,
        anchor: UnitPoint = .center,
        matrix: AffineTransform = .identity
    ) {
        self.translation = translation
        self.scale = scale
        self.rotation = rotation
        self.anchor = anchor
        self.matrix = matrix
    }

    public static let identity = GeometricEffect()

    /// Resolves this into a single transform about the view's own origin.
    ///
    /// Scale and rotation are taken about the anchor, which means moving to the
    /// anchor, transforming, and moving back. Translation is applied last and is
    /// anchor-independent, matching SwiftUI, where `.offset` moves the view by a
    /// fixed distance whatever the anchor is set to.
    ///
    /// 將此效果解析為「相對於 view 自身原點」的單一變換。
    ///
    /// 縮放與旋轉是繞錨點進行的，也就是「移到錨點、變換、再移回去」。平移最後才套用且與錨點無關，
    /// 這與 SwiftUI 一致——在 SwiftUI 中，無論錨點設為何處，`.offset` 都是把 view 移動固定距離。
    public func resolved(in size: SIMD2<Double>) -> AffineTransform {
        let anchorPoint = SIMD2(anchor.x * size.x, anchor.y * size.y)

        var transform = matrix

        if scale != SIMD2(1, 1) || rotation != .zero {
            transform = transform.followedBy(
                .translation(x: -anchorPoint.x, y: -anchorPoint.y)
            )
            if scale != SIMD2(1, 1) {
                transform = transform.followedBy(
                    AffineTransform(
                        linearTransform: SIMD4(x: scale.x, y: 0, z: 0, w: scale.y),
                        translation: .zero
                    )
                )
            }
            if rotation != .zero {
                transform = transform.followedBy(
                    .rotation(radians: rotation.radians, center: .zero)
                )
            }
            transform = transform.followedBy(
                .translation(x: anchorPoint.x, y: anchorPoint.y)
            )
        }

        if translation != .zero {
            transform = transform.followedBy(
                .translation(x: translation.x, y: translation.y)
            )
        }

        return transform
    }
}

struct GeometricEffectModifier<Content: View>: View, TypeSafeView {
    var content: Content
    var effect: GeometricEffect

    var body: TupleView1<Content> { content }

    typealias Children = TupleView1<Content>.Children

    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> Children {
        body.children(backend: backend, snapshots: snapshots, environment: environment)
    }

    // Degrades to the untransformed view rather than aborting the process.
    //
    // Same change as ``VisualEffectModifier/asWidget(_:backend:)`` and for the
    // same reason, but the argument for it is already written down elsewhere in
    // this file's own subject area: the GTK section of todo.md concludes that
    // declining to render a geometric effect beats rendering it wrongly,
    // because "an untransformed view is legible and clickable". That reasoning
    // applies with more force to a backend that has not implemented the feature
    // at all -- there the alternative was not a wrong rendering but no process.
    //
    // Measured 2026-09-01: AppKitBackend does not implement this, so P40 aborted
    // at launch with no window on macOS.
    //
    // Unlike a compositing effect, a geometric one does change where a view's
    // pixels land, and therefore where it can be clicked. Degrading leaves the
    // view at its layout rectangle, which is where hit testing already expects
    // it -- so the degraded case is self-consistent, and the transformed case is
    // the one that has to keep the two in step.
    //
    // 降級為未經變換的 view，而非中止行程。
    //
    // 與 ``VisualEffectModifier/asWidget(_:backend:)`` 是相同的改動、相同的理由；但支持它的論證，
    // 早已寫在本檔自身主題領域的別處：todo.md 的 GTK 一節結論是「寧可拒絕算繪幾何效果，也不要算繪
    // 錯誤」，因為「未經變換的 view 是可讀且可點擊的」。這個推理對「完全未實作該功能的 backend」
    // 更為適用——在那裡，替代方案並不是一個錯誤的算繪，而是根本沒有行程。
    //
    // 2026-09-01 量測：AppKitBackend 並未實作本項，因此 P40 在啟動時即中止，在 macOS 上沒有視窗。
    //
    // 不同於合成效果，幾何效果確實會改變 view 的像素落在何處，因而也改變它能在何處被點擊。降級會讓
    // view 留在它的版面矩形上，而那正是 hit testing 本來就預期它所在的位置——因此降級的情況是自洽的，
    // 反而是「有變換」的情況才必須讓兩者保持同步。
    func asWidget<Backend: BaseAppBackend>(
        _ children: Children,
        backend: Backend
    ) -> Backend.Widget {
        let inner = body.asWidget(children, backend: backend)

        func wrap<B: BaseAppBackend & BackendFeatures.GeometricEffects>(backend: B) -> B.Widget {
            backend.createGeometricEffectContainer(wrapping: inner as! B.Widget)
        }
        guard let capable = backend as? any BaseAppBackend & BackendFeatures.GeometricEffects
        else {
            logger.warnOnce(
                "\(type(of: backend)) doesn't support geometric effects; showing it untransformed"
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

    // Unchanged from the child, which is the point: SwiftUI's geometric effects
    // are explicitly not layout. A rotated view still occupies its original
    // rectangle, so the things around it do not move out of the way -- and it
    // can overlap them, which is the behaviour these modifiers exist for.
    // 與子元件相同，而這正是重點：SwiftUI 的幾何效果明確地不屬於版面。旋轉後的 view 仍佔據其原本
    // 的矩形，因此周圍的東西不會讓開——它可以與鄰居重疊，而那正是這些 modifier 存在的目的。
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

    // No warning here; `asWidget` has already reported it. See the note on
    // ``VisualEffectModifier``'s commit for why the second call site is left
    // silent.
    // 此處不發出警告；`asWidget` 已經回報過。第二個呼叫點保持沉默的理由，見 ``VisualEffectModifier``
    // 的 commit 上的說明。
    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        let size = children.child0.commit().size
        backend.setSize(of: widget, to: size.vector)

        func apply<B: BaseAppBackend & BackendFeatures.GeometricEffects>(backend: B) {
            backend.setGeometricEffect(
                effect.resolved(in: SIMD2(Double(size.vector.x), Double(size.vector.y))),
                ofWidget: widget as! B.Widget
            )
        }
        guard let capable = backend as? any BaseAppBackend & BackendFeatures.GeometricEffects
        else {
            return
        }
        apply(backend: capable)
    }
}
