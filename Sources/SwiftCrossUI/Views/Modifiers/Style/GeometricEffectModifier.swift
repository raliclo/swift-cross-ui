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

    @CastBackend<BackendFeatures.GeometricEffects>(returnsWidget: true)
    func asWidget<Backend: BaseAppBackend>(
        _ children: Children,
        backend: Backend
    ) -> Backend.Widget {
        backend.createGeometricEffectContainer(wrapping: body.asWidget(children, backend: backend))
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

    @CastBackend<BackendFeatures.GeometricEffects>
    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        let size = children.child0.commit().size
        backend.setSize(of: widget, to: size.vector)
        backend.setGeometricEffect(
            effect.resolved(in: SIMD2(Double(size.vector.x), Double(size.vector.y))),
            ofWidget: widget
        )
    }
}
