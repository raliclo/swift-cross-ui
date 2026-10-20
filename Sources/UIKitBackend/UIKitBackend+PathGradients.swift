import UIKit

@_spi(Backends) import SwiftCrossUI

/// Painting a gradient into a shape, rather than flattening it to one colour.
///
/// This is AppKitBackend's implementation with two differences, and both are
/// forced by UIKit rather than chosen.
///
/// **The y axis is not inverted here.** AppKit's path arrives already flipped,
/// because `NSBezierPathView` is unflipped and its y grows upward; UIKit's y
/// grows downward and matches SwiftUI's unit space, so `UnitPoint.top` is the
/// *smallest* y in the box. The two files therefore differ in one sign, which
/// is exactly the sort of difference that is invisible in a screenshot of a
/// symmetric gradient. P43's ramp is red to blue and runs top to bottom, so the
/// sign shows: red must be at the top on both platforms.
///
/// **`CAShapeLayer` cannot paint a gradient**, and there is no property to set:
/// `fillColor` is a `CGColor`. `CAGradientLayer` masked by the shape is the
/// usual workaround and it does not express this feature -- its `.radial` type
/// is an ellipse from one point to another, with no start radius, so a
/// `radialGradient(startRadius:endRadius:)` cannot be stated. So the flat case
/// keeps the shape layer, unchanged and as cheap as it was, and the gradient
/// case draws with `CGGradient`, which takes both radii, in a layer of its own (`PathWidget.updateGradientLayer`).
///
/// 把漸層畫進形狀裡，而不是把它壓成單一顏色。
///
/// 這就是 AppKitBackend 的實作，只有兩處不同，而兩者都是 UIKit 逼出來的，不是選出來的。
///
/// **此處的 y 軸不是反的。** AppKit 的路徑抵達時已經被翻轉過，因為 `NSBezierPathView` 並非 flipped
/// 且其 y 向上增長；UIKit 的 y 向下增長，與 SwiftUI 的單位空間一致，因此 `UnitPoint.top` 是方框中
/// **最小**的 y。兩個檔案因而差一個正負號——而那正是「在對稱漸層的螢幕截圖上看不出來」的那種差異。
/// P43 的漸層是紅到藍、由上往下，因此那個正負號看得出來：紅色在兩個平台上都必須在上方。
///
/// **`CAShapeLayer` 無法繪製漸層**，而且沒有可設定的屬性：`fillColor` 是一個 `CGColor`。「以形狀
/// 遮蔽 `CAGradientLayer`」是常見的變通做法，但它表達不了這項功能——它的 `.radial` 型別是一個從某點
/// 到另一點的橢圓，沒有起始半徑，因此 `radialGradient(startRadius:endRadius:)` 無從表述。所以平面色
/// 的情況維持使用 shape layer、原封不動且維持原有成本，而漸層的情況則在自己的圖層(`PathWidget.updateGradientLayer`)中以 `CGGradient`
/// 繪製——它接受兩個半徑。
extension UIKitBackend {
    public func renderPath(
        _ path: Path,
        container: Widget,
        strokeStyle: ResolvedFillStyle,
        fillStyle: ResolvedFillStyle,
        overrideStrokeStyle: StrokeStyle?,
        environment: EnvironmentValues
    ) {
        // The flat call first, so every property the shape layer needs is set
        // exactly as it was before this file existed. When neither style is a
        // gradient, nothing below changes anything.
        // 先呼叫平面色的版本，使 shape layer 所需的每一個屬性都與本檔存在之前完全相同地被設定。
        // 當兩個樣式都不是漸層時，下方不會改變任何東西。
        renderPath(
            path,
            container: container,
            strokeColor: strokeStyle.flattened(in: environment),
            fillColor: fillStyle.flattened(in: environment),
            overrideStrokeStyle: overrideStrokeStyle
        )

        let widget = container as! PathWidget
        widget.fillGradient = fillStyle.asGradient
        widget.strokeGradient = strokeStyle.asGradient
        widget.environment = environment

        // The shape layer is hidden rather than removed, so switching a shape
        // from a gradient back to a colour restores it without rebuilding
        // anything.
        // shape layer 是被隱藏而非移除，因此把一個形狀從漸層改回顏色時，不需要重建任何東西就能還原。
        let hasGradient = widget.fillGradient != nil || widget.strokeGradient != nil
        widget.shapeLayer.isHidden = hasGradient
        widget.isOpaque = false
        widget.backgroundColor = .clear
        widget.updateGradientLayer()
    }
}

extension ResolvedFillStyle {
    /// `nil` for a flat colour, so the view can test one optional instead of
    /// switching on the enum when it draws.
    /// 平面顏色時為 `nil`，使該 view 繪製時只需檢查一個 optional，而不必對 enum 做 switch。
    var asGradient: ResolvedFillStyle? {
        if case .color = self { return nil }
        return self
    }
}

extension PathWidget {
    /// The gradient run across a box, in this view's coordinate system.
    /// 在本 view 的座標系中，橫跨一個方框繪製的漸層。
    func drawGradient(
        _ style: ResolvedFillStyle,
        in box: CGRect,
        environment: EnvironmentValues,
        context: CGContext
    ) {
        drawResolvedFill(style, in: box, environment: environment, context: context)
    }
}

/// Paints `style` across `box` in UIKit's y-down coordinates: unit points map
/// onto the box, radii are points, as in SwiftUI's `RadialGradient`. Shared by paths and
/// gradient text (TextView).
/// 在 UIKit 的 y 向下座標中把 `style` 畫滿 `box`:單位座標對應到方框，半徑以點為單位(同 SwiftUI)。路徑與漸層文字(TextView)共用。
@MainActor
func drawResolvedFill(
    _ style: ResolvedFillStyle,
    in box: CGRect,
    environment: EnvironmentValues,
    context: CGContext
) {
    do {
        // A zero-extent path leaves a gradient nowhere to run, and Core
        // Graphics would take the degenerate call and draw nothing -- the shape
        // would vanish. The flat colour keeps it visible, as in GtkBackend.
        // 範圍為零的路徑會讓漸層無處延展，而 Core Graphics 會接受那個退化的呼叫並什麼都不畫
        // ——形狀因而消失。改用平面色可讓它保持可見，與 GtkBackend 相同。
        guard box.width > 0, box.height > 0 else {
            context.setFillColor(style.flattened(in: environment).cgColor)
            context.fill(box)
            return
        }

        // Downward y, unlike AppKit's. See this file's note.
        // y 向下，與 AppKit 相反。見本檔開頭的說明。
        func point(_ unit: UnitPoint) -> CGPoint {
            CGPoint(
                x: box.minX + CGFloat(unit.x) * box.width,
                y: box.minY + CGFloat(unit.y) * box.height
            )
        }

        switch style {
            case .color(let resolved):
                context.setFillColor(resolved.cgColor)
                context.fill(box)

            case .linearGradient(let gradient, let start, let end):
                guard let cgGradient = gradient.cgGradient(in: environment) else { return }
                // Both options, so the area before the first stop and after the
                // last is painted rather than left transparent, which is what
                // Cairo does by default and therefore what GtkBackend produces.
                // 兩個選項都給，使第一個 stop 之前與最後一個 stop 之後的區域會被填色而非留白
                // ——那是 Cairo 的預設行為，也因此是 GtkBackend 所產生的結果。
                context.drawLinearGradient(
                    cgGradient,
                    start: point(start),
                    end: point(end),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )

            case .radialGradient(let gradient, let center, let startRadius, let endRadius):
                guard let cgGradient = gradient.cgGradient(in: environment) else { return }
                // The radii are points, as in SwiftUI's
                // `RadialGradient`, not scaled by the shape, and a circle in any path.
                // 半徑以點為單位，與 SwiftUI 的 `RadialGradient` 相同，不隨形狀大小縮放;在非正方形的路徑中仍是圓形。
                let middle = point(center)
                context.drawRadialGradient(
                    cgGradient,
                    startCenter: middle,
                    startRadius: CGFloat(startRadius),
                    endCenter: middle,
                    endRadius: CGFloat(endRadius),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )
            case .angularGradient(let gradient, let center, let startAngle, let endAngle):
                let stops = ResolvedFillStyle.angularTurnStops(gradient, startAngle: startAngle, endAngle: endAngle)
                drawConic(
                    stops: stops, centre: point(center), startAngle: startAngle, box: box, yDown: true,
                    environment: environment, context: context
                )
        }
    }
}

/// A conic gradient over `box`, a full turn from `startAngle` with `stops`
/// (``ResolvedFillStyle/angularTurnStops(_:startAngle:endAngle:)``), clockwise on
/// screen from three o'clock as in SwiftUI. `yDown` says whether the context's y
/// runs down the screen; the drawing is mirrored when it does not, so the turn is
/// clockwise on screen either way. Core Graphics has a conic gradient from macOS 14
/// and iOS 17; before that, 720 wedges of one colour each.
/// `box` 上的錐形漸層：從 `startAngle` 起一整圈，色標由 `angularTurnStops` 給出，如 SwiftUI 自三點鐘方向在螢幕上順時針。
/// `yDown` 表示 context 的 y 是否往螢幕下方;不是時鏡像繪製，使螢幕上一律順時針。Core Graphics 自 macOS 14 / iOS 17
/// 起有錐形漸層，之前的系統以 720 個單色扇形畫出。
@MainActor
func drawConic(
    stops: [Gradient.Stop],
    centre: CGPoint,
    startAngle: Angle,
    box: CGRect,
    yDown: Bool,
    environment: EnvironmentValues,
    context: CGContext
) {
    guard !stops.isEmpty else { return }
    context.saveGState()
    defer { context.restoreGState() }
    context.translateBy(x: centre.x, y: centre.y)
    if !yDown { context.scaleBy(x: 1, y: -1) }
    if #available(macOS 14, iOS 17, *), let cgGradient = Gradient(stops: stops).cgGradient(in: environment) {
        // Imported as a C function, not a CGContext method (Swift 6.4, macOS 27 SDK).
        CGContextDrawConicGradient(context, cgGradient, .zero, CGFloat(startAngle.radians))
        return
    }
    // Far enough to reach every corner of the box from the centre.
    // 從中心到方框最遠角的距離。
    let corners = [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                   CGPoint(x: box.minX, y: box.maxY), CGPoint(x: box.maxX, y: box.maxY)]
    let reach = corners.map { hypot($0.x - centre.x, $0.y - centre.y) }.max()! + 1
    let colours = stops.map { ($0.location, $0.color.resolve(in: environment)) }
    let wedges = 720
    for i in 0..<wedges {
        let t0 = Double(i) / Double(wedges), t1 = Double(i + 1) / Double(wedges)
        let a0 = startAngle.radians + t0 * 2 * .pi, a1 = startAngle.radians + t1 * 2 * .pi + 0.002
        context.setFillColor(conicColour(at: (t0 + t1) / 2, colours).cgColor)
        context.move(to: .zero)
        context.addLine(to: CGPoint(x: cos(a0) * reach, y: sin(a0) * reach))
        context.addLine(to: CGPoint(x: cos(a1) * reach, y: sin(a1) * reach))
        context.closePath()
        context.fillPath()
    }
}
/// The colour `t` of the way round, between the stops around it; the first
/// colour before the first stop, the last after the last.
/// 繞行 `t` 處的顏色，在其兩側色標之間內插;第一個色標之前是第一個顏色，最後一個之後是最後一個。
func conicColour(at t: Double, _ stops: [(Double, Color.Resolved)]) -> Color.Resolved {
    guard let first = stops.first, let last = stops.last else { return Color.Resolved(red: 0, green: 0, blue: 0) }
    if t <= first.0 { return first.1 }
    if t >= last.0 { return last.1 }
    let i = stops.firstIndex { $0.0 > t }!
    let (l0, c0) = stops[i - 1], (l1, c1) = stops[i]
    let f = Float(l1 > l0 ? (t - l0) / (l1 - l0) : 1)
    return Color.Resolved(
        red: c0.red + (c1.red - c0.red) * f, green: c0.green + (c1.green - c0.green) * f,
        blue: c0.blue + (c1.blue - c0.blue) * f, opacity: c0.opacity + (c1.opacity - c0.opacity) * f
    )
}
extension Gradient {
    @MainActor
    func cgGradient(in environment: EnvironmentValues) -> CGGradient? {
        let resolved = stops.map { $0.color.resolve(in: environment).cgColor }
        let locations = stops.map { CGFloat($0.location) }
        guard !resolved.isEmpty else { return nil }
        return CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: resolved as CFArray,
            locations: locations
        )
    }
}
