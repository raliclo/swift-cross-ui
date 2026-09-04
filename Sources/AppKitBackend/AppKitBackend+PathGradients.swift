import AppKit

@_spi(Backends) import SwiftCrossUI

/// Painting a gradient into a shape, rather than flattening it to one colour.
///
/// `BackendFeatures.Paths` carries a default `renderPath(…fillStyle:)` that
/// flattens both styles to the gradient's midpoint colour and warns once. That
/// default was written on a machine with no Mac, and it says so: implementing
/// AppKit and UIKit blind would have landed as a build break for whoever pulled
/// next. This is that implementation, written and measured on a Mac.
///
/// **The unit points are in the path's own space, and that is the feature.**
/// A gradient *view* fills a rectangle it owns; this fills the shape, so a
/// gradient in a circle is clipped to the circle. The box is `path.bounds` --
/// the path's own extents -- exactly as GtkBackend uses `cairo_path_extents`.
///
/// **The y axis is inverted here and not in UIKit.** `applyActions` ends by
/// transforming the whole path through `scaleByX: 1, byY: -1`, because
/// `NSBezierPathView` is not flipped and AppKit's y grows upward. The path
/// arrives already corrected, so `UnitPoint.top` -- y 0 in SwiftUI's space --
/// is the *largest* y in the box. Getting this backwards produces a gradient
/// that runs the right way along the wrong axis direction, which looks like a
/// reversed colour order rather than like a coordinate bug.
///
/// 把漸層畫進形狀裡，而不是把它壓成單一顏色。
///
/// `BackendFeatures.Paths` 帶有一個預設的 `renderPath(…fillStyle:)`，它會把兩個樣式都壓成漸層的
/// 中點顏色並警告一次。那個預設是在一台沒有 Mac 的機器上寫的，而它自己也說明了這一點：盲寫 AppKit
/// 與 UIKit 會讓下一個 pull 的人拿到建置失敗。此處就是那份實作，在 Mac 上寫成並量測。
///
/// **單位座標位於路徑自身的空間中，而那正是這項功能的重點。** 漸層**視圖**填滿的是它自己擁有的
/// 矩形；此處填的是形狀，因此圓形中的漸層會被裁進該圓形。所用的方框是 `path.bounds`——路徑自身的
/// 範圍——與 GtkBackend 使用 `cairo_path_extents` 完全相同。
///
/// **y 軸在此處是反的，在 UIKit 中則不是。** `applyActions` 最後會以 `scaleByX: 1, byY: -1` 變換
/// 整條路徑，因為 `NSBezierPathView` 並非 flipped，而 AppKit 的 y 向上增長。路徑抵達時已經被修正過，
/// 因此 `UnitPoint.top`——SwiftUI 空間中的 y 0——對應的是方框中**最大**的 y。若把這一點弄反，會產生
/// 一個「方向正確但軸向相反」的漸層，看起來像是顏色順序寫反了，而不像座標系錯誤。
extension AppKitBackend {
    public func renderPath(
        _ path: Path,
        container: Widget,
        strokeStyle: ResolvedFillStyle,
        fillStyle: ResolvedFillStyle,
        overrideStrokeStyle: StrokeStyle?,
        environment: EnvironmentValues
    ) {
        if let overrideStrokeStyle {
            applyStrokeStyle(overrideStrokeStyle, to: path)
        }

        let widget = container as! NSBezierPathView
        widget.path = path

        // The flat colours are still set, and are still what draws when the
        // style is a colour. Keeping that path untouched is deliberate: a shape
        // filled with a colour should cost exactly what it did before this file
        // existed.
        // 平面顏色仍然會被設定，且在樣式為顏色時仍是實際繪製的東西。維持該路徑不變是刻意的：一個
        // 以顏色填充的形狀，其代價應與本檔存在之前完全相同。
        widget.strokeColor = strokeStyle.flattened(in: environment).nsColor
        widget.fillColor = fillStyle.flattened(in: environment).nsColor

        widget.fillGradient = fillStyle.asGradient
        widget.strokeGradient = strokeStyle.asGradient
        widget.environment = environment

        widget.needsDisplay = true
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

@MainActor
extension AppKitBackend.NSBezierPathView {
    /// The gradient run across a box, in the coordinate system this view draws
    /// in.
    /// 在本 view 所使用的座標系中，橫跨一個方框繪製的漸層。
    func drawGradient(
        _ style: ResolvedFillStyle,
        in box: NSRect,
        environment: EnvironmentValues,
        context: CGContext
    ) {
        // A zero-extent path leaves a gradient nowhere to run. Core Graphics
        // would take the degenerate call and draw nothing, so the shape would
        // vanish; the flat colour keeps it visible. GtkBackend guards the same
        // case for the same reason.
        // 範圍為零的路徑會讓漸層無處延展。Core Graphics 會接受那個退化的呼叫並什麼都不畫，形狀因而
        // 消失；改用平面色可讓它保持可見。GtkBackend 基於相同理由也守住了同一個情況。
        guard box.width > 0, box.height > 0 else {
            context.setFillColor(style.flattened(in: environment).cgColor)
            context.fill(box)
            return
        }

        func point(_ unit: UnitPoint) -> CGPoint {
            CGPoint(
                x: box.minX + CGFloat(unit.x) * box.width,
                y: box.maxY - CGFloat(unit.y) * box.height
            )
        }

        switch style {
            case .color(let resolved):
                context.setFillColor(resolved.cgColor)
                context.fill(box)

            case .linearGradient(let gradient, let start, let end):
                guard let cgGradient = gradient.cgGradient(in: environment) else { return }
                // Both options, so the area before the first stop and after the
                // last is painted rather than left transparent. Cairo extends by
                // default -- without these the two backends disagree at the ends
                // of any gradient whose stops do not reach 0 and 1.
                // 兩個選項都給，使第一個 stop 之前與最後一個 stop 之後的區域會被填色而非留白。Cairo
                // 預設就是延伸的——少了這兩個選項，兩個 backend 在「stop 未觸及 0 與 1」的漸層兩端
                // 會給出不同結果。
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

/// `NSBezierPath` to `CGPath`, because the stroke needs an outline.
///
/// Clipping to the *filled* region needs no conversion -- `NSBezierPath` has
/// `addClip()`. Clipping to the *stroked* region does: the only way to turn a
/// stroke into a region is `CGContext.replacePathWithStrokedPath()`, which
/// works on the context's current path.
///
/// `NSBezierPath.cgPath` exists, and only from macOS 14. This package deploys
/// to macOS 11.
///
/// 把 `NSBezierPath` 轉成 `CGPath`，因為描邊需要一個外框。
///
/// 裁切到**填充**區域不需要轉換——`NSBezierPath` 有 `addClip()`。裁切到**描邊**區域則需要：把描邊
/// 變成一個區域的唯一方法是 `CGContext.replacePathWithStrokedPath()`，而它作用於 context 的當前路徑。
///
/// `NSBezierPath.cgPath` 確實存在，但只從 macOS 14 起。本套件的部署目標是 macOS 11。
func cgPath(of path: NSBezierPath) -> CGPath {
    let result = CGMutablePath()
    var points = [NSPoint](repeating: .zero, count: 3)

    for index in 0..<path.elementCount {
        let element = path.element(at: index, associatedPoints: &points)
        switch element {
            case .moveTo:
                result.move(to: points[0])
            case .lineTo:
                result.addLine(to: points[0])
            case .curveTo:
                // Also `.cubicCurveTo`: the SDK declares
                // `NSBezierPathElementCurveTo = NSBezierPathElementCubicCurveTo`,
                // one raw value with two spellings, the newer one available only
                // from macOS 14. Swift treats them as two cases and asks for
                // both, but this package deploys to macOS 11 and cannot name the
                // newer one outside an availability check. The older spelling
                // matches the same value on every version.
                // 這同時也是 `.cubicCurveTo`：SDK 宣告的是
                // `NSBezierPathElementCurveTo = NSBezierPathElementCubicCurveTo`，同一個 raw
                // value、兩種寫法，較新的那個僅自 macOS 14 起可用。Swift 視它們為兩個 case 並要求
                // 兩者都寫，但本套件部署至 macOS 11，無法在 availability 檢查之外指名較新的那個。
                // 較舊的寫法在每一個版本上都對應到同一個值。
                result.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath:
                result.closeSubpath()
            default:
                // `.quadraticCurveTo`, macOS 14 and later, where `applyActions`
                // emits quadratics instead of converting them to cubics -- so
                // this arm runs on every current Mac rather than on none.
                //
                // Named rather than assumed. This was `@unknown default` with an
                // unconditional `addQuadCurve`, which was right only because
                // `.curveTo` above already absorbs the cubic case; had it not,
                // every cubic would have been rebuilt as a quadratic through
                // points[0] and points[1] and the stroke outline would have been
                // quietly wrong. A future element type now falls through
                // untouched instead of being bent into a quadratic.
                //
                // `default` and not `@unknown default`, because the case this
                // arm is for is a known one that cannot be spelled at this
                // deployment target; `@unknown default` asks the compiler for a
                // warning naming exactly the cases that cannot be written.
                //
                // `.quadraticCurveTo`，macOS 14 起。在該版本上 `applyActions` 會直接輸出二次曲線
                // 而不再轉成三次——因此這個分支在現今每一台 Mac 上都會走到，而非永不執行。
                //
                // 這裡是指名，而非假設。此處原本是 `@unknown default` 加上無條件的 `addQuadCurve`；
                // 那之所以正確，只是因為上方的 `.curveTo` 已經吸收了三次曲線那個 case——若不然，
                // 每一條三次曲線都會被以 points[0] 與 points[1] 重建成二次曲線，描邊外框會靜默地
                // 出錯。現在，未來新增的 element 型別會原樣通過，而不是被硬掰成二次曲線。
                //
                // 使用 `default` 而非 `@unknown default`，因為本分支所服務的是一個「已知但在此
                // 部署目標下無法寫出名字」的 case；`@unknown default` 會要求編譯器對「恰好就是那些
                // 寫不出來的 case」發出警告。
                if #available(macOS 14, *), element == .quadraticCurveTo {
                    result.addQuadCurve(to: points[1], control: points[0])
                }
        }
    }

    return result
}
