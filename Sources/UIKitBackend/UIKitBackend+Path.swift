@_spi(Backends) import SwiftCrossUI
import UIKit

final class PathWidget: BaseViewWidget {
    let shapeLayer = CAShapeLayer()
    /// Draws a gradient fill or stroke; shown only while one is set.
    /// 繪製漸層填色或描邊；只在設定了漸層時顯示。
    let gradientLayer = PathGradientLayer()

    /// Set only when the style is not a flat colour; see
    /// `UIKitBackend+PathGradients.swift`.
    /// 僅在樣式不是平面顏色時才設定；見 `UIKitBackend+PathGradients.swift`。
    var fillGradient: ResolvedFillStyle?
    var strokeGradient: ResolvedFillStyle?
    var environment: EnvironmentValues?

    override init() {
        super.init()

        layer.addSublayer(shapeLayer)
        gradientLayer.owner = self
        gradientLayer.isHidden = true
        layer.addSublayer(gradientLayer)
    }

    // The display scale is known once the view is in a window; the layer is
    // redrawn at it.
    // 進入視窗後才知道顯示倍率；圖層依它重繪。
    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateGradientLayer()
    }

    /// Sizes the gradient layer to the path's extents -- stroked, when the
    /// stroke is a gradient -- and redraws it.
    ///
    /// A layer of its own rather than `draw(_:)`, because a view draws only
    /// inside its bounds: half of a stroke centred on a shape that fills its
    /// frame lies outside, and a gradient ring was cut flat on four sides
    /// (P43). The flat colour's `CAShapeLayer` was never clipped, and neither
    /// is this layer.
    ///
    /// 把漸層圖層的大小設為路徑的範圍(描邊是漸層時為描邊後的範圍)並重繪。
    ///
    /// 用一個自己的圖層而不是 `draw(_:)`,因為 view 只畫在自己的 bounds 之內：填滿外框的形狀，其置中的描邊
    /// 有一半落在外面，漸層圓環因此四邊都被切平(P43)。平面色的 `CAShapeLayer` 從未被裁切，這個圖層也不會。
    func updateGradientLayer() {
        let hasGradient = fillGradient != nil || strokeGradient != nil
        gradientLayer.isHidden = !hasGradient
        guard hasGradient, let path = shapeLayer.path else { return }

        var box = path.boundingBoxOfPath
        if strokeGradient != nil {
            let stroked = path.copy(
                strokingWithWidth: shapeLayer.lineWidth,
                lineCap: shapeLayer.lineCap == .round
                    ? .round : shapeLayer.lineCap == .square ? .square : .butt,
                lineJoin: shapeLayer.lineJoin == .round
                    ? .round : shapeLayer.lineJoin == .bevel ? .bevel : .miter,
                miterLimit: shapeLayer.miterLimit
            )
            box = box.union(stroked.boundingBoxOfPath)
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // One point of margin for the antialiased edge.
        // 留一點邊距給反鋸齒的邊緣。
        gradientLayer.frame = box.insetBy(dx: -1, dy: -1).integral
        gradientLayer.contentsScale = traitCollection.displayScale
        CATransaction.commit()
        gradientLayer.setNeedsDisplay()
    }

    /// The gradients, in this view's coordinates translated to the gradient
    /// layer's origin.
    /// 漸層，以本 view 的座標繪製，平移到漸層圖層的原點。
    func drawGradients(in context: CGContext, layerOrigin: CGPoint) {
        guard
            fillGradient != nil || strokeGradient != nil,
            let environment,
            let path = shapeLayer.path
        else { return }

        context.translateBy(x: -layerOrigin.x, y: -layerOrigin.y)

        // The path's own extents, not the view's. A gradient's unit points are
        // in the shape's space, which is what lets it be clipped to a circle
        // instead of filling a rectangle the way the gradient views do.
        // 使用路徑自身的範圍，而非 view 的。漸層的單位座標位於形狀的空間中，這正是它能被裁進一個
        // 圓形、而非像漸層視圖那樣填滿一個矩形的原因。
        let box = path.boundingBoxOfPath

        if let fillGradient {
            context.saveGState()
            context.addPath(path)
            context.clip(using: shapeLayer.fillRule == .evenOdd ? .evenOdd : .winding)
            drawGradient(fillGradient, in: box, environment: environment, context: context)
            context.restoreGState()
        }

        if let strokeGradient {
            context.saveGState()
            context.addPath(path)
            // The stroke parameters go on the context, because
            // `replacePathWithStrokedPath` reads the context's rather than the
            // layer's. Leaving them at the defaults produces a hairline outline
            // with the gradient shut inside it.
            // 描邊參數設定在 context 上，因為 `replacePathWithStrokedPath` 讀的是 context 的設定，
            // 而非 layer 的。若維持預設值，會得到一條髮絲般細的外框，漸層被關在裡面。
            context.setLineWidth(shapeLayer.lineWidth)
            context.setMiterLimit(shapeLayer.miterLimit)
            context.setLineCap(
                shapeLayer.lineCap == .round
                    ? .round : shapeLayer.lineCap == .square ? .square : .butt
            )
            context.setLineJoin(
                shapeLayer.lineJoin == .round
                    ? .round : shapeLayer.lineJoin == .bevel ? .bevel : .miter
            )
            context.replacePathWithStrokedPath()
            context.clip()
            drawGradient(strokeGradient, in: box, environment: environment, context: context)
            context.restoreGState()
        }
    }
}

/// The layer `PathWidget` draws its gradients into.
/// `PathWidget` 繪製漸層所用的圖層。
final class PathGradientLayer: CALayer {
    weak var owner: PathWidget?

    // Core Animation draws a layer on the main thread (this one does not set
    // drawsAsynchronously), where the owning view lives.
    // Core Animation 在主執行緒上繪製圖層(這個圖層沒有設定 drawsAsynchronously),也就是擁有它的 view 所在之處。
    override func draw(in ctx: CGContext) {
        nonisolated(unsafe) let context = ctx
        nonisolated(unsafe) let owner = owner
        let origin = frame.origin
        MainActor.assumeIsolated {
            owner?.drawGradients(in: context, layerOrigin: origin)
        }
    }
}

extension UIKitBackend {
    public typealias Path = UIBezierPath

    public func createPathWidget() -> any WidgetProtocol {
        PathWidget()
    }

    public func createPath() -> UIBezierPath {
        UIBezierPath()
    }

    func applyStrokeStyle(_ strokeStyle: StrokeStyle, to path: UIBezierPath) {
        path.lineWidth = CGFloat(strokeStyle.width)

        path.lineCapStyle =
            switch strokeStyle.cap {
                case .butt:
                    .butt
                case .round:
                    .round
                case .square:
                    .square
            }

        switch strokeStyle.join {
            case .miter(let limit):
                path.lineJoinStyle = .miter
                path.miterLimit = CGFloat(limit)
            case .round:
                path.lineJoinStyle = .round
            case .bevel:
                path.lineJoinStyle = .bevel
        }
    }

    public func updatePath(
        _ path: UIBezierPath,
        _ source: SwiftCrossUI.Path,
        bounds: SwiftCrossUI.Path.Rect,
        pointsChanged: Bool,
        environment: EnvironmentValues
    ) {
        path.usesEvenOddFillRule = (source.fillRule == .evenOdd)

        applyStrokeStyle(source.strokeStyle, to: path)

        if pointsChanged {
            path.removeAllPoints()
            applyActions(source.actions, to: path)
        }
    }

    func applyActions(_ actions: [SwiftCrossUI.Path.Action], to path: UIBezierPath) {
        for action in actions {
            switch action {
                case .moveTo(let point):
                    path.move(to: CGPoint(x: point.x, y: point.y))
                case .lineTo(let point):
                    path.addLine(to: CGPoint(x: point.x, y: point.y))
                case .quadCurve(let control, let end):
                    path.addQuadCurve(
                        to: CGPoint(x: end.x, y: end.y),
                        controlPoint: CGPoint(x: control.x, y: control.y)
                    )
                case .cubicCurve(let control1, let control2, let end):
                    path.addCurve(
                        to: CGPoint(x: end.x, y: end.y),
                        controlPoint1: CGPoint(x: control1.x, y: control1.y),
                        controlPoint2: CGPoint(x: control2.x, y: control2.y)
                    )
                case .rectangle(let rect):
                    let cgPath: CGMutablePath = path.cgPath.mutableCopy()!
                    cgPath.addRect(
                        CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
                    )
                    path.cgPath = cgPath
                case .circle(let center, let radius):
                    let cgPath: CGMutablePath = path.cgPath.mutableCopy()!
                    cgPath.addEllipse(
                        in: CGRect(
                            x: center.x - radius,
                            y: center.y - radius,
                            width: radius * 2.0,
                            height: radius * 2.0
                        )
                    )
                    path.cgPath = cgPath
                case .arc(let center, let radius, let startAngle, let endAngle, let clockwise):
                    path.addArc(
                        withCenter: CGPoint(x: center.x, y: center.y),
                        radius: CGFloat(radius),
                        startAngle: CGFloat(startAngle),
                        endAngle: CGFloat(endAngle),
                        clockwise: clockwise
                    )
                case .transform(let transform):
                    path.apply(CGAffineTransform(transform))
                case .subpath(let subpathActions):
                    let subpath = UIBezierPath()
                    applyActions(subpathActions, to: subpath)
                    path.append(subpath)
            }
        }
    }

    public func renderPath(
        _ path: Path,
        container: Widget,
        strokeColor: Color.Resolved,
        fillColor: Color.Resolved,
        overrideStrokeStyle: StrokeStyle?
    ) {
        if let overrideStrokeStyle {
            applyStrokeStyle(overrideStrokeStyle, to: path)
        }

        let widget = container as! PathWidget
        let shapeLayer = widget.shapeLayer

        shapeLayer.path = path.cgPath
        shapeLayer.lineWidth = path.lineWidth
        shapeLayer.miterLimit = path.miterLimit
        shapeLayer.fillRule = path.usesEvenOddFillRule ? .evenOdd : .nonZero

        switch path.lineJoinStyle {
            case .miter:
                shapeLayer.lineJoin = .miter
            case .round:
                shapeLayer.lineJoin = .round
            case .bevel:
                shapeLayer.lineJoin = .bevel
            @unknown default:
                logger.warning(
                    "unrecognized lineJoinStyle",
                    metadata: ["lineJoinStyle": "\(path.lineJoinStyle)"]
                )
                shapeLayer.lineJoin = .miter
        }

        switch path.lineCapStyle {
            case .butt:
                shapeLayer.lineCap = .butt
            case .round:
                shapeLayer.lineCap = .round
            case .square:
                shapeLayer.lineCap = .square
            @unknown default:
                logger.warning(
                    "unrecognized lineCapStyle",
                    metadata: ["lineCapStyle": "\(path.lineCapStyle)"]
                )
                shapeLayer.lineCap = .butt
        }

        shapeLayer.strokeColor = strokeColor.cgColor
        shapeLayer.fillColor = fillColor.cgColor
    }
}

extension CGAffineTransform {
    public init(_ transform: AffineTransform) {
        self.init(
            a: transform.linearTransform.x,
            b: transform.linearTransform.z,
            c: transform.linearTransform.y,
            d: transform.linearTransform.w,
            tx: transform.translation.x,
            ty: transform.translation.y
        )
    }
}

extension AffineTransform {
    public init(cg transform: CGAffineTransform) {
        self.init(
            linearTransform: SIMD4(x: transform.a, y: transform.c, z: transform.b, w: transform.d),
            translation: SIMD2(x: transform.tx, y: transform.ty)
        )
    }
}
