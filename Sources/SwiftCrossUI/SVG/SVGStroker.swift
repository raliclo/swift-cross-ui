import Foundation

/// `stroke-linecap`.
public enum SVGLineCap: String, Sendable {
    case butt, round, square
}

/// `stroke-linejoin`. `miter-clip` and `arcs` (SVG 2) are read as `miter`.
/// `miter-clip` 與 `arcs`(SVG 2)以 `miter` 處理。
public enum SVGLineJoin: String, Sendable {
    case miter, round, bevel
}

/// Turns a stroke into polygons to be filled with the nonzero rule.
///
/// Every polygon it returns winds the same way, so filling all of them
/// together with nonzero gives their union -- the overlaps at joins count
/// once, which matters for a translucent stroke. Each segment becomes a
/// rectangle; joins and caps are separate polygons laid over the ends.
///
/// 把描邊轉成以 nonzero 規則填充的多邊形。它回傳的每一個多邊形繞行方向都相同，因此以 nonzero
/// 一起填充即得到它們的聯集——接點處的重疊只算一次，這對半透明描邊很重要。每一段成為一個矩形；
/// 接點與端帽是另外疊在端點上的多邊形。
struct SVGStroker {
    var halfWidth: Double
    var cap: SVGLineCap
    var join: SVGLineJoin
    var miterLimit: Double
    /// Maximum distance between a true circle and its polygon, in the same
    /// units as the points.
    /// 真實圓與其多邊形之間的最大距離，單位與點相同。
    var tolerance: Double

    func stroke(_ polylines: [SVGPolyline]) -> [[SVGPoint]] {
        var polygons: [[SVGPoint]] = []
        for polyline in polylines {
            strokeOne(polyline, into: &polygons)
        }
        return polygons
    }

    private func strokeOne(_ polyline: SVGPolyline, into polygons: inout [[SVGPoint]]) {
        // Drop repeated points: they have no direction.
        // 去掉重複的點：它們沒有方向。
        var points: [SVGPoint] = []
        for point in polyline.points {
            if let last = points.last, last.distance(to: point) <= 1e-9 {
                continue
            }
            points.append(point)
        }
        var closed = polyline.closed
        if closed, points.count > 1, points[0].distance(to: points[points.count - 1]) <= 1e-9 {
            points.removeLast()
        }
        if points.count < 2 {
            // A zero-length subpath still draws its caps (SVG 1.1 11.4).
            // 長度為零的子路徑仍要畫出端帽(SVG 1.1 11.4)。
            guard let point = points.first ?? polyline.points.first else { return }
            switch cap {
                case .round:
                    add(circle(at: point), to: &polygons)
                case .square:
                    let h = halfWidth
                    add(
                        [
                            SVGPoint(point.x - h, point.y - h), SVGPoint(point.x + h, point.y - h),
                            SVGPoint(point.x + h, point.y + h), SVGPoint(point.x - h, point.y + h),
                        ], to: &polygons)
                case .butt:
                    break
            }
            return
        }
        if points.count == 2 { closed = false }

        let count = points.count
        let segmentCount = closed ? count : count - 1
        for index in 0..<segmentCount {
            let a = points[index]
            let b = points[(index + 1) % count]
            let normal = Self.leftNormal(from: a, to: b) * halfWidth
            add([a + normal, b + normal, b - normal, a - normal], to: &polygons)
        }

        let joinRange = closed ? 0..<count : 1..<(count - 1)
        for index in joinRange {
            let previous = points[(index - 1 + count) % count]
            let point = points[index]
            let next = points[(index + 1) % count]
            addJoin(previous: previous, point: point, next: next, to: &polygons)
        }

        if !closed {
            addCap(at: points[0], awayFrom: points[1], to: &polygons)
            addCap(at: points[count - 1], awayFrom: points[count - 2], to: &polygons)
        }
    }

    static func leftNormal(from a: SVGPoint, to b: SVGPoint) -> SVGPoint {
        let d = b - a
        let length = d.length
        guard length > 0 else { return SVGPoint(0, 0) }
        return SVGPoint(-d.y / length, d.x / length)
    }

    private func addJoin(
        previous: SVGPoint, point: SVGPoint, next: SVGPoint, to polygons: inout [[SVGPoint]]
    ) {
        let d0 = point - previous
        let d1 = next - point
        let cross = d0.x * d1.y - d0.y * d1.x
        let dot = d0.x * d1.x + d0.y * d1.y
        let lengths = d0.length * d1.length
        guard lengths > 0 else { return }
        // Straight on: the two rectangles already meet edge to edge.
        // 直線延續：兩個矩形已經邊對邊相接。
        if abs(cross) <= 1e-12 * lengths && dot > 0 { return }

        if join == .round {
            add(circle(at: point), to: &polygons)
            return
        }
        // The outer side is the one the path turns away from.
        // 外側是路徑轉離的那一側。
        let side: Double = cross > 0 ? -1 : 1
        let n0 = Self.leftNormal(from: previous, to: point) * side
        let n1 = Self.leftNormal(from: point, to: next) * side
        let a = point + n0 * halfWidth
        let b = point + n1 * halfWidth
        if join == .miter {
            // Miter length / stroke width = 1 / sin(theta / 2), theta being
            // the angle between the segments.
            // 斜接長度 / 線寬 = 1 / sin(theta / 2),theta 為兩段之間的夾角。
            let cosTheta = -dot / lengths
            let sinHalf = ((1 - cosTheta) / 2).squareRoot()
            if sinHalf > 1e-9, 1 / sinHalf <= miterLimit {
                let bisector = n0 + n1
                let bisectorLength = bisector.length
                if bisectorLength > 1e-12 {
                    let tip = point + bisector * (halfWidth / sinHalf / bisectorLength)
                    add([point, a, tip, b], to: &polygons)
                    return
                }
            }
        }
        add([point, a, b], to: &polygons)
    }

    private func addCap(at end: SVGPoint, awayFrom inner: SVGPoint, to polygons: inout [[SVGPoint]]) {
        switch cap {
            case .butt:
                return
            case .round:
                add(circle(at: end), to: &polygons)
            case .square:
                let direction = end - inner
                let length = direction.length
                guard length > 0 else { return }
                let forward = direction * (halfWidth / length)
                let normal = Self.leftNormal(from: inner, to: end) * halfWidth
                add(
                    [end + normal, end + normal + forward, end - normal + forward, end - normal],
                    to: &polygons)
        }
    }

    func circle(at center: SVGPoint) -> [SVGPoint] {
        let radius = halfWidth
        let steps: Int
        if radius <= tolerance {
            steps = 8
        } else {
            let angle = 2 * acos(max(-1, 1 - tolerance / radius))
            steps = min(max(Int((2 * Double.pi / angle).rounded(.up)), 8), 512)
        }
        return (0..<steps).map { step in
            let theta = Double(step) / Double(steps) * 2 * Double.pi
            return SVGPoint(center.x + radius * cos(theta), center.y + radius * sin(theta))
        }
    }

    /// Adds `polygon` after making it wind positively; drops it if it has no area.
    /// 先讓 `polygon` 以正向繞行再加入；面積為零則捨棄。
    private func add(_ polygon: [SVGPoint], to polygons: inout [[SVGPoint]]) {
        let area = Self.signedArea(polygon)
        if abs(area) <= 1e-18 { return }
        polygons.append(area < 0 ? polygon.reversed() : polygon)
    }

    static func signedArea(_ polygon: [SVGPoint]) -> Double {
        var sum = 0.0
        for index in polygon.indices {
            let a = polygon[index]
            let b = polygon[(index + 1) % polygon.count]
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }

    // MARK: Dashes / 虛線

    /// Splits polylines by `stroke-dasharray`. `pattern` must already be
    /// validated (non-negative, some entry positive, even length).
    ///
    /// 依 `stroke-dasharray` 切分折線。`pattern` 必須事先驗證過(非負、至少一項為正、長度為偶數)。
    static func dash(_ polylines: [SVGPolyline], pattern: [Double], offset: Double) -> [SVGPolyline] {
        let total = pattern.reduce(0, +)
        guard total > 0 else { return polylines }
        var result: [SVGPolyline] = []
        for polyline in polylines {
            var points = polyline.points
            if polyline.closed, let first = points.first { points.append(first) }
            guard points.count >= 2 else { continue }

            // Where in the pattern the subpath starts.
            // 子路徑從圖樣的哪個位置開始。
            var phase = offset.truncatingRemainder(dividingBy: total)
            if phase < 0 { phase += total }
            var patternIndex = 0
            while phase >= pattern[patternIndex] {
                phase -= pattern[patternIndex]
                patternIndex = (patternIndex + 1) % pattern.count
            }
            var remaining = pattern[patternIndex] - phase
            var drawing = patternIndex % 2 == 0
            var current: [SVGPoint] = drawing ? [points[0]] : []

            for index in 0..<(points.count - 1) {
                var a = points[index]
                let b = points[index + 1]
                var segmentLength = a.distance(to: b)
                while segmentLength > remaining {
                    let t = remaining / segmentLength
                    let split = a + (b - a) * t
                    if drawing {
                        current.append(split)
                        result.append(SVGPolyline(points: current, closed: false))
                        current = []
                    } else {
                        current = [split]
                    }
                    drawing.toggle()
                    segmentLength -= remaining
                    a = split
                    patternIndex = (patternIndex + 1) % pattern.count
                    remaining = pattern[patternIndex]
                }
                remaining -= segmentLength
                if drawing { current.append(b) }
            }
            if drawing, current.count >= 2 {
                result.append(SVGPolyline(points: current, closed: false))
            }
        }
        return result
    }
}
