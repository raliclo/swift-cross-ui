import AppKit
@_spi(Backends) import SwiftCrossUI

extension AppKitBackend {
    public typealias Path = NSBezierPath

    final class NSBezierPathView: NSView {
        var path: NSBezierPath!
        var fillColor: NSColor = .clear
        var strokeColor: NSColor = .clear

        /// Set only when the style is not a flat colour; see
        /// `AppKitBackend+PathGradients.swift`.
        /// 僅在樣式不是平面顏色時才設定；見 `AppKitBackend+PathGradients.swift`。
        var fillGradient: ResolvedFillStyle?
        var strokeGradient: ResolvedFillStyle?
        var environment: EnvironmentValues?

        override func draw(_ dirtyRect: NSRect) {
            guard let path else { return }

            let context = NSGraphicsContext.current?.cgContext

            if let fillGradient, let environment, let context {
                context.saveGState()
                // `addClip()` and not `context.clip()`: the fill region is what
                // `NSBezierPath` already knows how to describe, honouring its own
                // winding rule. No CGPath conversion is needed for the fill.
                // 使用 `addClip()` 而非 `context.clip()`：填充區域是 `NSBezierPath` 本來就知道
                // 如何描述的東西，並會遵守它自己的 winding rule。填充不需要任何 CGPath 轉換。
                path.addClip()
                drawGradient(
                    fillGradient,
                    in: path.bounds,
                    environment: environment,
                    context: context
                )
                context.restoreGState()
            } else {
                fillColor.set()
                path.fill()
            }

            if let strokeGradient, let environment, let context {
                context.saveGState()
                context.addPath(cgPath(of: path))
                // The stroke parameters have to be on the context, not on the
                // NSBezierPath, because `replacePathWithStrokedPath` reads the
                // context's. Setting the path's line width alone produces a
                // hairline outline with the gradient inside it.
                // 描邊參數必須設定在 context 上而非 NSBezierPath 上，因為
                // `replacePathWithStrokedPath` 讀的是 context 的設定。只設定路徑的線寬，會得到一條
                // 髮絲般細的外框，漸層被關在裡面。
                context.setLineWidth(path.lineWidth)
                context.setMiterLimit(path.miterLimit)
                let cap: CGLineCap =
                    switch path.lineCapStyle {
                        case .round: .round
                        case .square: .square
                        default: .butt
                    }
                let join: CGLineJoin =
                    switch path.lineJoinStyle {
                        case .round: .round
                        case .bevel: .bevel
                        default: .miter
                    }
                context.setLineCap(cap)
                context.setLineJoin(join)
                context.replacePathWithStrokedPath()
                context.clip()
                drawGradient(
                    strokeGradient,
                    in: path.bounds,
                    environment: environment,
                    context: context
                )
                context.restoreGState()
            } else {
                strokeColor.set()
                path.stroke()
            }
        }
    }

    public func createPathWidget() -> NSView {
        NSBezierPathView()
    }

    public func createPath() -> Path {
        NSBezierPath()
    }

    func applyStrokeStyle(_ strokeStyle: StrokeStyle, to path: NSBezierPath) {
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
        _ path: Path,
        _ source: SwiftCrossUI.Path,
        bounds: SwiftCrossUI.Path.Rect,
        pointsChanged: Bool,
        environment: EnvironmentValues
    ) {
        applyStrokeStyle(source.strokeStyle, to: path)

        if pointsChanged {
            path.removeAllPoints()
            applyActions(
                source.actions,
                to: path,
                bounds: bounds,
                applyCoordinateSystemCorrection: true
            )
        }
    }

    func applyActions(
        _ actions: [SwiftCrossUI.Path.Action],
        to path: NSBezierPath,
        bounds: SwiftCrossUI.Path.Rect,
        applyCoordinateSystemCorrection: Bool
    ) {
        for action in actions {
            switch action {
                case .moveTo(let point):
                    path.move(to: NSPoint(x: point.x, y: point.y))
                case .lineTo(let point):
                    if path.isEmpty {
                        path.move(to: .zero)
                    }
                    path.line(to: NSPoint(x: point.x, y: point.y))
                case .quadCurve(let control, let end):
                    if path.isEmpty {
                        path.move(to: .zero)
                    }

                    if #available(macOS 14, *) {
                        // Use the native quadratic curve function
                        path.curve(
                            to: NSPoint(x: end.x, y: end.y),
                            controlPoint: NSPoint(x: control.x, y: control.y)
                        )
                    } else {
                        let start = path.currentPoint
                        // Build a cubic curve that follows the same path as the quadratic
                        path.curve(
                            to: NSPoint(x: end.x, y: end.y),
                            controlPoint1: NSPoint(
                                x: (start.x + 2.0 * control.x) / 3.0,
                                y: (start.y + 2.0 * control.y) / 3.0
                            ),
                            controlPoint2: NSPoint(
                                x: (2.0 * control.x + end.x) / 3.0,
                                y: (2.0 * control.y + end.y) / 3.0
                            )
                        )
                    }
                case .cubicCurve(let control1, let control2, let end):
                    if path.isEmpty {
                        path.move(to: .zero)
                    }

                    path.curve(
                        to: NSPoint(x: end.x, y: end.y),
                        controlPoint1: NSPoint(x: control1.x, y: control1.y),
                        controlPoint2: NSPoint(x: control2.x, y: control2.y)
                    )
                case .rectangle(let rect):
                    path.appendRect(
                        NSRect(
                            origin: NSPoint(x: rect.x, y: rect.y),
                            size: NSSize(
                                width: CGFloat(rect.width),
                                height: CGFloat(rect.height)
                            )
                        )
                    )
                case .circle(let center, let radius):
                    path.appendOval(
                        in: NSRect(
                            origin: NSPoint(x: center.x - radius, y: center.y - radius),
                            size: NSSize(
                                width: CGFloat(radius) * 2.0,
                                height: CGFloat(radius) * 2.0
                            )
                        )
                    )
                case .arc(
                let center,
                let radius,
                let startAngle,
                let endAngle,
                let clockwise
            ):
                    path.appendArc(
                        withCenter: NSPoint(x: center.x, y: center.y),
                        radius: CGFloat(radius),
                        startAngle: CGFloat(startAngle * 180.0 / .pi),
                        endAngle: CGFloat(endAngle * 180.0 / .pi),
                        // Due to being in a flipped coordinate system (before the
                        // correction gets applied), we have to reverse all arcs.
                        clockwise: !clockwise
                    )
                case .transform(let transform):
                    let affineTransform = Foundation.AffineTransform(
                        m11: CGFloat(transform.linearTransform.x),
                        m12: CGFloat(transform.linearTransform.z),
                        m21: CGFloat(transform.linearTransform.y),
                        m22: CGFloat(transform.linearTransform.w),
                        tX: CGFloat(transform.translation.x),
                        tY: CGFloat(transform.translation.y)
                    )
                    path.transform(using: affineTransform)
                case .subpath(let subpathActions):
                    let subpath = NSBezierPath()
                    // We don't apply the coordinate system correction to the subpath,
                    // we only want to apply it to the whole path once we're done.
                    applyActions(
                        subpathActions,
                        to: subpath,
                        bounds: bounds,
                        applyCoordinateSystemCorrection: false
                    )
                    path.append(subpath)
            }
        }

        if applyCoordinateSystemCorrection {
            // AppKit's coordinate system has a flipped Y axis so we have to correct for that
            // once we've constructed the whole path.
            var coordinateSystemCorrection = Foundation.AffineTransform(scaleByX: 1, byY: -1)
            coordinateSystemCorrection.append(
                Foundation.AffineTransform(translationByX: 0, byY: bounds.maxY + bounds.y)
            )
            path.transform(using: coordinateSystemCorrection)
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

        let widget = container as! NSBezierPathView
        widget.path = path
        widget.strokeColor = strokeColor.nsColor
        widget.fillColor = fillColor.nsColor

        widget.needsDisplay = true
    }
}
