import CGtk
import Foundation
import GtkCHelpers
@_spi(Backends) import SwiftCrossUI

// A path drawn as GSK fill and stroke nodes (GTK 4.14 and later).
//
// The cairo draw function rasterizes every stroke on the CPU each time the widget
// is drawn: P96's 33 curve tiles were replayed through cairo and uploaded as
// textures on every frame (sampled 2026-10-19, about half of gsk_renderer_render).
// Here the path is built once, when it changes, and each snapshot appends the same
// GskPath, which the renderer draws and caches itself.
//
// The path is flattened to move, line, cubic and close with the cairo version's
// semantics, so a shape draws the same either way: transforms compose as
// `renderPathActions` composes them, an action at index 0 with no current point
// starts from (0, 0), an arc joins the current point with a line, and arcs become
// cubics of at most 90 degrees as cairo makes them.
//
// 以 GSK 的填色與線條節點畫出的路徑(GTK 4.14 起)。cairo 的繪製函式每次畫 widget 都在 CPU 上點陣化每一條線：P96 的
// 33 格曲線每一幀都經由 cairo 重播並上傳成 texture(2026-10-19 取樣，約佔 gsk_renderer_render 的一半)。這裡路徑只在
// 改變時建一次，每次 snapshot 附加同一條 GskPath,由 renderer 自己繪製並快取。路徑以 cairo 版本的語意攤平成
// move、line、cubic 與 close,所以兩種方式畫出的形狀相同:transform 的組合方式與 `renderPathActions` 相同，位於 index 0
// 且沒有目前點的動作從 (0, 0) 開始，圓弧以直線連接目前的點，圓弧轉成每段至多 90 度的三次曲線，與 cairo 的做法相同。

/// An affine transform in cairo's layout: x' = xx x + xy y + x0, y' = yx x + yy y + y0.
/// cairo 排列的仿射變換:x' = xx x + xy y + x0,y' = yx x + yy y + y0。
struct ShapeAffine {
    var xx = 1.0, xy = 0.0, yx = 0.0, yy = 1.0, x0 = 0.0, y0 = 0.0

    init() {}

    init(_ transform: SwiftCrossUI.AffineTransform) {
        xx = transform.linearTransform.x
        xy = transform.linearTransform.y
        yx = transform.linearTransform.z
        yy = transform.linearTransform.w
        x0 = transform.translation.x
        y0 = transform.translation.y
    }

    func apply(_ point: SIMD2<Double>) -> SIMD2<Double> {
        SIMD2(xx * point.x + xy * point.y + x0, yx * point.x + yy * point.y + y0)
    }

    /// `other` first, then this one: what `cairo_transform(other)` does to the CTM.
    /// 先 `other`、再這一個:`cairo_transform(other)` 對 CTM 所做的事。
    func applying(_ other: ShapeAffine) -> ShapeAffine {
        var result = ShapeAffine()
        result.xx = xx * other.xx + xy * other.yx
        result.xy = xx * other.xy + xy * other.yy
        result.yx = yx * other.xx + yy * other.yx
        result.yy = yx * other.xy + yy * other.yy
        result.x0 = xx * other.x0 + xy * other.y0 + x0
        result.y0 = yx * other.x0 + yy * other.y0 + y0
        return result
    }

    /// The inverse, or nil for a singular transform (cairo refuses to invert one).
    /// 反矩陣;奇異矩陣時為 nil(cairo 不會反轉它)。
    var inverted: ShapeAffine? {
        let determinant = xx * yy - xy * yx
        guard determinant != 0, determinant.isFinite else { return nil }
        var result = ShapeAffine()
        result.xx = yy / determinant
        result.xy = -xy / determinant
        result.yx = -yx / determinant
        result.yy = xx / determinant
        result.x0 = -(result.xx * x0 + result.xy * y0)
        result.y0 = -(result.yx * x0 + result.yy * y0)
        return result
    }
}

/// A path as the verbs and coordinates of gtk_passthrough_drawing_area_set_shape.
/// 以 gtk_passthrough_drawing_area_set_shape 的 verb 與座標表示的路徑。
struct FlattenedShapePath {
    private(set) var verbs: [UInt8] = []
    private(set) var coords: [Double] = []
    private var matrix = ShapeAffine()
    /// In output coordinates, as cairo keeps its current point in device space.
    /// 以輸出座標保存，與 cairo 以裝置座標保存目前的點相同。
    private var current: SIMD2<Double>?
    private var subpathStart: SIMD2<Double>?

    init(_ actions: [SwiftCrossUI.Path.Action]) {
        add(actions)
    }

    private mutating func add(_ actions: [SwiftCrossUI.Path.Action]) {
        for case .transform(let transform) in actions {
            matrix = matrix.applying(ShapeAffine(transform))
        }
        for (index, action) in actions.enumerated() {
            switch action {
                case .moveTo(let point):
                    move(point)
                case .lineTo(let point):
                    if index == 0 { move(.zero) }
                    line(point)
                case .quadCurve(let control, let end):
                    if index == 0 { move(.zero) }
                    let start = userCurrent ?? .zero
                    cubic((start + 2 * control) / 3, (end + 2 * control) / 3, end)
                case .cubicCurve(let control1, let control2, let end):
                    if index == 0 { move(.zero) }
                    cubic(control1, control2, end)
                case .rectangle(let rect):
                    let origin = rect.origin
                    let size = rect.size
                    move(origin)
                    line(SIMD2(origin.x + size.x, origin.y))
                    line(SIMD2(origin.x + size.x, origin.y + size.y))
                    line(SIMD2(origin.x, origin.y + size.y))
                    close()
                case .circle(let center, let radius):
                    arc(center: center, radius: radius, from: 0, to: 2 * .pi, positive: true)
                case .arc(let center, let radius, let startAngle, let endAngle, let clockwise):
                    arc(center: center, radius: radius, from: startAngle, to: endAngle, positive: clockwise)
                case .transform(let transform):
                    if let inverse = ShapeAffine(transform).inverted {
                        matrix = matrix.applying(inverse)
                    }
                case .subpath(let subpathActions):
                    add(subpathActions)
            }
        }
    }

    private var userCurrent: SIMD2<Double>? {
        guard let current else { return nil }
        return matrix.inverted?.apply(current) ?? current
    }

    private mutating func emit(_ verb: UInt8, _ points: [SIMD2<Double>]) {
        verbs.append(verb)
        for point in points {
            let mapped = matrix.apply(point)
            coords.append(mapped.x)
            coords.append(mapped.y)
        }
    }

    private mutating func move(_ point: SIMD2<Double>) {
        emit(0, [point])
        current = matrix.apply(point)
        subpathStart = current
    }

    /// A line with no current point is a move, as `cairo_line_to` treats it.
    /// 沒有目前點時的直線就是 move,與 `cairo_line_to` 的處理相同。
    private mutating func line(_ point: SIMD2<Double>) {
        guard current != nil else {
            move(point)
            return
        }
        emit(1, [point])
        current = matrix.apply(point)
    }

    /// With no current point the curve starts at its first control point, as
    /// `cairo_curve_to` does. / 沒有目前點時，曲線從第一個控制點開始，與 `cairo_curve_to` 相同。
    private mutating func cubic(_ control1: SIMD2<Double>, _ control2: SIMD2<Double>, _ end: SIMD2<Double>) {
        if current == nil { move(control1) }
        emit(2, [control1, control2, end])
        current = matrix.apply(end)
    }

    private mutating func close() {
        verbs.append(3)
        current = subpathStart
    }

    /// `cairo_arc` (positive) or `cairo_arc_negative`: the end angle is moved by
    /// whole turns until it lies past the start in the arc's direction, the start
    /// point is joined to the current one by a line, and a radius that is not
    /// positive is a line to the centre.
    /// `cairo_arc`(正向)或 `cairo_arc_negative`:終點角以整圈移動，直到它沿圓弧方向落在起點之後;起點以直線連到目前的點;
    /// 半徑不為正時是一條到圓心的直線。
    private mutating func arc(
        center: SIMD2<Double>, radius: Double, from start: Double, to end: Double, positive: Bool
    ) {
        guard radius > 0 else {
            line(center)
            return
        }
        var end = end
        if positive {
            while end < start { end += 2 * .pi }
            while end - start > 4 * .pi { end -= 2 * .pi }
        } else {
            while end > start { end -= 2 * .pi }
            while start - end > 4 * .pi { end += 2 * .pi }
        }
        func point(_ angle: Double) -> SIMD2<Double> {
            center + radius * SIMD2(cos(angle), sin(angle))
        }
        let first = point(start)
        if current == nil { move(first) } else { line(first) }
        let sweep = end - start
        let segments = max(1, Int((abs(sweep) / (.pi / 2)).rounded(.up)))
        let step = sweep / Double(segments)
        // The control points' distance along each tangent for a step of `step`.
        // 每一段 `step` 沿切線方向的控制點距離。
        let handle = 4.0 / 3.0 * tan(step / 4) * radius
        for segment in 0..<segments {
            let a = start + step * Double(segment)
            let b = a + step
            let from = point(a)
            let to = point(b)
            let control1 = from + handle * SIMD2(-sin(a), cos(a))
            let control2 = to - handle * SIMD2(-sin(b), cos(b))
            emit(2, [control1, control2, to])
            current = matrix.apply(to)
        }
    }
}

extension GtkBackend {
    /// The C description of a fill style; `body` gets it while its stops are alive.
    /// 填充樣式的 C 描述;`body` 在它的 stops 仍存活時取得它。
    func withShapePaint<Result>(
        _ style: ResolvedFillStyle,
        flattenedTo flat: SwiftCrossUI.Color.Resolved,
        environment: EnvironmentValues,
        _ body: (UnsafePointer<ScuiShapePaint>) -> Result
    ) -> Result {
        var paint = ScuiShapePaint()
        paint.rgba = (Double(flat.red), Double(flat.green), Double(flat.blue), Double(flat.opacity))
        var stops: [Double] = []
        func addStops(_ gradient: Gradient) {
            for stop in gradient.stops {
                let colour = stop.color.resolve(in: environment)
                stops += [
                    stop.location, Double(colour.red), Double(colour.green), Double(colour.blue),
                    Double(colour.opacity),
                ]
            }
        }
        switch style {
            case .color:
                paint.kind = 0
            case .linearGradient(let gradient, let start, let end):
                paint.kind = 1
                paint.geometry = (start.x, start.y, end.x, end.y)
                addStops(gradient)
            case .radialGradient(let gradient, let center, let startRadius, let endRadius):
                paint.kind = 2
                paint.geometry = (center.x, center.y, startRadius, endRadius)
                addStops(gradient)
            case .angularGradient(let gradient, let center, let startAngle, let endAngle):
                // Kind 3: a conic gradient, a full turn from geometry[2] (radians from
                // three o'clock, clockwise) with the stops of that turn.
                // 種類 3:錐形漸層，從 geometry[2](自三點鐘方向順時針的弧度)起一整圈，色標是那一圈的。
                paint.kind = 3
                paint.geometry = (center.x, center.y, startAngle.radians, 0)
                addStops(Gradient(stops: ResolvedFillStyle.angularTurnStops(gradient, startAngle: startAngle, endAngle: endAngle)))
        }
        paint.stop_count = Int32(stops.count / 5)
        return stops.withUnsafeBufferPointer { buffer in
            paint.stops = buffer.baseAddress
            return withUnsafePointer(to: &paint) { body($0) }
        }
    }

    /// Sets `source` on the drawing area as GSK nodes. / 把 `source` 以 GSK 節點設到 drawing area 上。
    func setShape(
        _ source: SwiftCrossUI.Path,
        on drawingArea: UnsafeMutablePointer<GtkWidget>,
        strokeStyle: StrokeStyle,
        strokeFill: ResolvedFillStyle,
        strokeColor: SwiftCrossUI.Color.Resolved,
        fill: ResolvedFillStyle,
        fillColor: SwiftCrossUI.Color.Resolved,
        overflow: Double,
        environment: EnvironmentValues
    ) {
        let flat = FlattenedShapePath(source.actions)
        let cap: Int32
        switch strokeStyle.cap {
            case .butt: cap = 0
            case .round: cap = 1
            case .square: cap = 2
        }
        let join: Int32
        var miterLimit = 10.0
        switch strokeStyle.join {
            case .miter(let limit):
                join = 0
                miterLimit = limit
            case .round: join = 1
            case .bevel: join = 2
        }
        withShapePaint(fill, flattenedTo: fillColor, environment: environment) { fillPaint in
            withShapePaint(strokeFill, flattenedTo: strokeColor, environment: environment) { strokePaint in
                flat.verbs.withUnsafeBufferPointer { verbs in
                    flat.coords.withUnsafeBufferPointer { coords in
                        gtk_passthrough_drawing_area_set_shape(
                            drawingArea,
                            verbs.baseAddress,
                            Int32(verbs.count),
                            coords.baseAddress,
                            Int32(coords.count),
                            source.fillRule == .evenOdd ? 1 : 0,
                            strokeStyle.width,
                            cap,
                            join,
                            miterLimit,
                            fillPaint,
                            strokePaint,
                            overflow
                        )
                    }
                }
            }
        }
    }
}
