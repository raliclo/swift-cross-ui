@_spi(Backends) import SwiftCrossUI
import UIKit

final class PathWidget: BaseViewWidget {
    let shapeLayer = CAShapeLayer()

    /// Set only when the style is not a flat colour; see
    /// `UIKitBackend+PathGradients.swift`.
    /// 僅在樣式不是平面顏色時才設定；見 `UIKitBackend+PathGradients.swift`。
    var fillGradient: ResolvedFillStyle?
    var strokeGradient: ResolvedFillStyle?
    var environment: EnvironmentValues?

    override init() {
        super.init()

        layer.addSublayer(shapeLayer)
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)

        guard
            fillGradient != nil || strokeGradient != nil,
            let environment,
            let path = shapeLayer.path,
            let context = UIGraphicsGetCurrentContext()
        else { return }

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
