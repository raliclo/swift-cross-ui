import Foundation

// Paint servers: linear and radial gradients (2026-10-10). A gradient is a
// colour per point, so the canvas evaluates it at each covered pixel's centre,
// mapped back from device pixels to the gradient's own space.
//
// 塗料伺服器：線性與放射漸層(2026-10-10)。漸層是逐點的顏色，因此畫布在每一個被覆蓋像素的中心求值，
// 該點由裝置像素映射回漸層自己的空間。

/// An axis-aligned rectangle in some user space.
/// 某個使用者空間中的軸對齊矩形。
struct SVGRect: Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

extension SVGTransform {
    /// The inverse map, or nil when the transform collapses the plane.
    /// 反映射；轉換使平面塌縮時為 nil。
    func inverted() -> SVGTransform? {
        let determinant = a * d - b * c
        guard abs(determinant) > 1e-12 else { return nil }
        let ia = d / determinant
        let ib = -b / determinant
        let ic = -c / determinant
        let id = a / determinant
        return SVGTransform(
            a: ia, b: ib, c: ic, d: id, e: -(ia * e + ic * f), f: -(ib * e + id * f))
    }
}

/// Premultiplied RGBA in 0...1.
/// 預乘的 RGBA,範圍 0...1。
struct SVGPremultiplied: Sendable {
    var red: Float
    var green: Float
    var blue: Float
    var alpha: Float

    static let clear = SVGPremultiplied(red: 0, green: 0, blue: 0, alpha: 0)

    init(red: Float, green: Float, blue: Float, alpha: Float) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(_ color: SVGColor) {
        let alpha = Float(color.alpha)
        self.init(
            red: Float(color.red) * alpha, green: Float(color.green) * alpha,
            blue: Float(color.blue) * alpha, alpha: alpha)
    }

    func scaled(_ factor: Float) -> SVGPremultiplied {
        SVGPremultiplied(
            red: red * factor, green: green * factor, blue: blue * factor, alpha: alpha * factor)
    }
}

struct SVGGradientStop: Equatable, Sendable {
    var offset: Double
    var color: SVGColor
}

enum SVGSpreadMethod: String, Sendable {
    case pad, reflect, `repeat`
}

/// A gradient resolved for one shape: its geometry in gradient space and the
/// map from gradient space to the shape's user space.
/// 為某個形狀解析好的漸層：其在漸層空間中的幾何，以及從漸層空間到形狀使用者空間的映射。
struct SVGGradient: Sendable {
    enum Geometry: Sendable {
        case linear(x1: Double, y1: Double, x2: Double, y2: Double)
        case radial(cx: Double, cy: Double, r: Double, fx: Double, fy: Double, fr: Double)
    }

    var geometry: Geometry
    var stops: [SVGGradientStop]
    var spread: SVGSpreadMethod
    var transform: SVGTransform

    /// The premultiplied colour at `point` in gradient space.
    /// 漸層空間中 `point` 處的預乘顏色。
    func color(at point: SVGPoint) -> SVGPremultiplied {
        guard let first = stops.first, let last = stops.last else { return .clear }
        if stops.count == 1 { return SVGPremultiplied(first.color) }
        let parameter: Double
        switch geometry {
            case .linear(let x1, let y1, let x2, let y2):
                let dx = x2 - x1
                let dy = y2 - y1
                let lengthSquared = dx * dx + dy * dy
                // A zero-length vector paints the last stop (SVG 1.1 13.2.2).
                // 長度為零的向量以最後一個色標繪製(SVG 1.1 13.2.2)。
                guard lengthSquared > 1e-24 else { return SVGPremultiplied(last.color) }
                parameter = ((point.x - x1) * dx + (point.y - y1) * dy) / lengthSquared
            case .radial(let cx, let cy, let r, let fx, let fy, let fr):
                guard let t = Self.radialParameter(
                    point: point, cx: cx, cy: cy, r: r, fx: fx, fy: fy, fr: fr)
                else { return .clear }
                parameter = t
        }
        return color(forParameter: spread.apply(parameter))
    }

    /// The largest t with a non-negative radius for which `point` lies on the
    /// circle interpolated from the focal circle (t = 0) to the end circle
    /// (t = 1): the two-point conical gradient of SVG 2 and canvas.
    /// 使 `point` 落在由焦點圓(t = 0)內插到終點圓(t = 1)的圓上、且半徑非負的最大 t:SVG 2 與 canvas 的
    /// 雙點圓錐漸層。
    static func radialParameter(
        point: SVGPoint, cx: Double, cy: Double, r: Double, fx: Double, fy: Double, fr: Double
    ) -> Double? {
        let cdx = cx - fx
        let cdy = cy - fy
        let pdx = point.x - fx
        let pdy = point.y - fy
        let dr = r - fr
        let a = cdx * cdx + cdy * cdy - dr * dr
        let b = pdx * cdx + pdy * cdy + fr * dr
        let c = pdx * pdx + pdy * pdy - fr * fr
        if abs(a) < 1e-12 {
            guard abs(b) > 1e-12 else { return nil }
            let t = c / (2 * b)
            return fr + t * dr >= 0 ? t : nil
        }
        let discriminant = b * b - a * c
        guard discriminant >= 0 else { return nil }
        let root = discriminant.squareRoot()
        let t1 = (b + root) / a
        let t2 = (b - root) / a
        let larger = max(t1, t2)
        let smaller = min(t1, t2)
        if fr + larger * dr >= 0 { return larger }
        if fr + smaller * dr >= 0 { return smaller }
        return nil
    }

    func color(forParameter t: Double) -> SVGPremultiplied {
        if t <= stops[0].offset { return SVGPremultiplied(stops[0].color) }
        for index in 1..<stops.count {
            let next = stops[index]
            if t <= next.offset {
                let previous = stops[index - 1]
                let span = next.offset - previous.offset
                let fraction = span > 0 ? Float((t - previous.offset) / span) : 1
                let from = SVGPremultiplied(previous.color)
                let to = SVGPremultiplied(next.color)
                return SVGPremultiplied(
                    red: from.red + (to.red - from.red) * fraction,
                    green: from.green + (to.green - from.green) * fraction,
                    blue: from.blue + (to.blue - from.blue) * fraction,
                    alpha: from.alpha + (to.alpha - from.alpha) * fraction)
            }
        }
        return SVGPremultiplied(stops[stops.count - 1].color)
    }
}

extension SVGSpreadMethod {
    func apply(_ t: Double) -> Double {
        switch self {
            case .pad:
                return min(max(t, 0), 1)
            case .repeat:
                return t - t.rounded(.down)
            case .reflect:
                let m = t - 2 * (t / 2).rounded(.down)
                return m > 1 ? 2 - m : m
        }
    }
}

/// What fills or strokes a shape or a text run.
/// 填充或描邊一個形狀或一段文字的塗料。
enum SVGPaintValue: Sendable {
    /// Opacity already applied to the colour.
    /// 不透明度已套用到顏色上。
    case color(SVGColor)
    /// `opacity` is the fill- or stroke-opacity, applied on top of the stops.
    /// `opacity` 是 fill- 或 stroke-opacity,套用在色標之上。
    case gradient(SVGGradient, opacity: Double)

    /// A per-pixel colour source for drawing through `device` (user space to
    /// device pixels); nil when nothing can be drawn.
    /// 經 `device`(使用者空間到裝置像素)繪製時的逐像素顏色來源；無法繪製時為 nil。
    func shader(device: SVGTransform) -> SVGShader? {
        switch self {
            case .color(let color):
                guard color.alpha > 0 else { return nil }
                return .solid(SVGPremultiplied(color))
            case .gradient(let gradient, let opacity):
                guard opacity > 0,
                    let toGradient = device.concatenating(gradient.transform).inverted()
                else { return nil }
                return .gradient(gradient, toGradient: toGradient, opacity: Float(opacity))
        }
    }
}

/// A colour per device pixel.
/// 每個裝置像素的顏色。
enum SVGShader {
    case solid(SVGPremultiplied)
    case gradient(SVGGradient, toGradient: SVGTransform, opacity: Float)

    func color(x: Int, y: Int) -> SVGPremultiplied {
        switch self {
            case .solid(let color):
                return color
            case .gradient(let gradient, let toGradient, let opacity):
                let point = toGradient.apply(SVGPoint(Double(x) + 0.5, Double(y) + 0.5))
                return gradient.color(at: point).scaled(opacity)
        }
    }
}

// MARK: - Parsing / 解析

extension SVGBuilder {
    static let gradientNames: Set<String> = ["linearGradient", "radialGradient"]

    /// The element `href` names, or nil.
    /// `href` 所指的元素，或 nil。
    func referencedElement(_ element: SVGXMLElement) -> SVGXMLElement? {
        guard let href = element[attribute: "href"] ?? element[attribute: "xlink:href"],
            href.hasPrefix("#")
        else { return nil }
        return elementsByID[String(href.dropFirst())]
    }

    /// `element` and the gradients it inherits from through `href`, nearest first.
    /// `element` 以及它經由 `href` 繼承的漸層，最近的在前。
    func gradientChain(_ element: SVGXMLElement) -> [SVGXMLElement] {
        var chain = [element]
        var current = element
        while chain.count < 16, let next = referencedElement(current),
            Self.gradientNames.contains(next.localName),
            !chain.contains(where: { $0 === next })
        {
            chain.append(next)
            current = next
        }
        return chain
    }

    /// The gradient `element` describes, resolved for a shape whose user-space
    /// bounding box is `box`; nil paints nothing (no stops, or an empty box under
    /// objectBoundingBox units).
    /// `element` 所描述的漸層，為使用者空間外框為 `box` 的形狀解析；nil 表示不畫(沒有色標，或在
    /// objectBoundingBox 單位下外框為空)。
    func gradient(_ element: SVGXMLElement, box: SVGRect?, style: Style) -> SVGGradient? {
        let chain = gradientChain(element)
        func attribute(_ name: String) -> String? {
            for link in chain {
                if let value = link[attribute: name] { return value }
            }
            return nil
        }
        guard let stopOwner = chain.first(where: { $0.children.contains { $0.localName == "stop" } })
        else { return nil }
        let stops = parseStops(stopOwner, style: style)
        guard !stops.isEmpty else { return nil }

        let boundingBoxUnits = attribute("gradientUnits") != "userSpaceOnUse"
        if boundingBoxUnits {
            guard let box, box.width > 0, box.height > 0 else { return nil }
        }
        func coordinate(_ name: String, _ fallback: String, axis: Axis) -> Double {
            let text = attribute(name) ?? fallback
            if boundingBoxUnits {
                var scanner = SVGNumberScanner(text)
                guard let value = scanner.number() else { return 0 }
                scanner.skipSeparators()
                return scanner.peek() == UInt8(ascii: "%") ? value / 100 : value
            }
            return length(text, axis: axis, fontSize: style.fontSize) ?? 0
        }

        let geometry: SVGGradient.Geometry
        if element.localName == "linearGradient" {
            geometry = .linear(
                x1: coordinate("x1", "0%", axis: .x), y1: coordinate("y1", "0%", axis: .y),
                x2: coordinate("x2", "100%", axis: .x), y2: coordinate("y2", "0%", axis: .y))
        } else {
            let cx = coordinate("cx", "50%", axis: .x)
            let cy = coordinate("cy", "50%", axis: .y)
            let r = coordinate("r", "50%", axis: .other)
            guard r > 0 else {
                // r = 0 paints the last stop over the whole area (SVG 1.1 13.2.3).
                // r = 0 時整個區域以最後一個色標繪製(SVG 1.1 13.2.3)。
                return SVGGradient(
                    geometry: .linear(x1: 0, y1: 0, x2: 0, y2: 0), stops: stops, spread: .pad,
                    transform: .identity)
            }
            let fx = attribute("fx").map { _ in coordinate("fx", "", axis: .x) } ?? cx
            let fy = attribute("fy").map { _ in coordinate("fy", "", axis: .y) } ?? cy
            let fr = coordinate("fr", "0%", axis: .other)
            geometry = .radial(cx: cx, cy: cy, r: r, fx: fx, fy: fy, fr: max(fr, 0))
        }

        var transform = SVGTransform.identity
        if boundingBoxUnits, let box {
            transform = SVGTransform(a: box.width, b: 0, c: 0, d: box.height, e: box.x, f: box.y)
        }
        if let text = attribute("gradientTransform"), let parsed = SVGTransformParser.parse(text) {
            transform = transform.concatenating(parsed)
        }
        let spread = attribute("spreadMethod").flatMap(SVGSpreadMethod.init(rawValue:)) ?? .pad
        return SVGGradient(geometry: geometry, stops: stops, spread: spread, transform: transform)
    }

    /// `<stop>` children: offsets clamped to 0...1 and made non-decreasing,
    /// `stop-opacity` folded into the colour.
    /// `<stop>` 子元素：offset 限制在 0...1 並使其不遞減，`stop-opacity` 併入顏色。
    func parseStops(_ element: SVGXMLElement, style: Style) -> [SVGGradientStop] {
        var stops: [SVGGradientStop] = []
        var lastOffset = 0.0
        for stop in element.children where stop.localName == "stop" {
            var properties: [String: String] = [:]
            for name in ["stop-color", "stop-opacity"] {
                if let value = stop[attribute: name] { properties[name] = value }
            }
            for declaration in (stop[attribute: "style"] ?? "").split(separator: ";") {
                let parts = declaration.split(separator: ":", maxSplits: 1)
                guard parts.count == 2 else { continue }
                properties[parts[0].trimmingCharacters(in: .whitespaces)] =
                    parts[1].trimmingCharacters(in: .whitespaces)
            }
            var offset = 0.0
            if let text = stop[attribute: "offset"] {
                var scanner = SVGNumberScanner(text)
                if let value = scanner.number() {
                    scanner.skipSeparators()
                    offset = scanner.peek() == UInt8(ascii: "%") ? value / 100 : value
                }
            }
            offset = max(min(max(offset, 0), 1), lastOffset)
            lastOffset = offset

            var color = SVGColor(red: 0, green: 0, blue: 0)
            if let text = properties["stop-color"] {
                if text.lowercased() == "currentcolor" {
                    color = style.color
                } else if let parsed = SVGColor.parse(text) {
                    color = parsed
                } else {
                    report(.invalidValue, stop, "stop-color='\(text)'")
                }
            }
            if let text = properties["stop-opacity"] {
                var scanner = SVGNumberScanner(text)
                if let value = scanner.number() {
                    scanner.skipSeparators()
                    let opacity = scanner.peek() == UInt8(ascii: "%") ? value / 100 : value
                    color = color.with(alpha: color.alpha * min(max(opacity, 0), 1))
                }
            }
            stops.append(SVGGradientStop(offset: offset, color: color))
        }
        return stops
    }
}

extension SVGBuilder {
    /// The user-space bounding box of `path`, from its flattened outline.
    /// `path` 在使用者空間中的外框，取自其平坦化後的輪廓。
    static func bounds(of path: SVGPath) -> SVGRect? {
        var minX = Double.infinity, minY = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity
        for polyline in path.flattened(tolerance: 0.01) {
            for point in polyline.points {
                minX = min(minX, point.x)
                minY = min(minY, point.y)
                maxX = max(maxX, point.x)
                maxY = max(maxY, point.y)
            }
        }
        guard minX.isFinite else { return nil }
        return SVGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// A text run is drawn in text space, its anchor at the origin; a gradient
    /// resolved against the `<text>` element's user space moves with it.
    /// 一段文字在文字空間中繪製，錨點位於原點；針對 `<text>` 元素使用者空間解析的漸層需隨之平移。
    static func shifted(_ paint: SVGPaintValue?, x: Double, y: Double) -> SVGPaintValue? {
        guard case .gradient(var gradient, let opacity)? = paint else { return paint }
        gradient.transform = SVGTransform.translate(-x, -y).concatenating(gradient.transform)
        return .gradient(gradient, opacity: opacity)
    }
}
