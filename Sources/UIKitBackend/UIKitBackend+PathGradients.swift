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
/// case draws in `draw(_:)` with `CGGradient`, which takes both radii.
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
/// 的情況維持使用 shape layer、原封不動且維持原有成本，而漸層的情況則在 `draw(_:)` 中以 `CGGradient`
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
        if hasGradient {
            widget.setNeedsDisplay()
        }
    }
}

extension ResolvedFillStyle {
    /// `nil` for a flat colour, so the view can test one optional instead of
    /// switching on the enum in `draw(_:)`.
    /// 平面顏色時為 `nil`，使該 view 在 `draw(_:)` 中只需檢查一個 optional，而不必對 enum 做 switch。
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
                // Scaled by the shorter side, so a circle stays a circle in a
                // path that is not square. Same rule as GtkBackend.
                // 以較短的一邊縮放，使圓形在非正方形的路徑中仍是圓形。與 GtkBackend 規則相同。
                let scale = min(box.width, box.height)
                let middle = point(center)
                context.drawRadialGradient(
                    cgGradient,
                    startCenter: middle,
                    startRadius: CGFloat(startRadius) * scale,
                    endCenter: middle,
                    endRadius: CGFloat(endRadius) * scale,
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )
        }
    }
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
