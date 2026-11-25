import Foundation

/// An area that takes pointer input, in a view's own coordinates.
///
/// Made by ``View/contentShape(_:eoFill:)`` from a ``Shape`` and the size the
/// view was laid out at, and handed to backends through
/// ``BackendFeatures/ContentShapes``. The origin is the view's top-left corner
/// and y grows downwards, the same space ``Shape/path(in:)`` draws in.
///
/// The path is flattened to closed polygons -- curves, circles and arcs become
/// short line segments -- so that every backend can answer "is this point
/// inside" with the same arithmetic and the same result. A backend that keeps
/// the test in another language (GTK's C, Android's Kotlin) is given
/// ``flattenedPoints`` and ``contourPointCounts`` and runs the same rule.
///
/// 在 view 自身座標中、接收指標輸入的區域。
///
/// 由 ``View/contentShape(_:eoFill:)`` 以一個 ``Shape`` 與該 view 排版後的尺寸產生，並經由
/// ``BackendFeatures/ContentShapes`` 交給 backend。原點是 view 的左上角，y 向下增加，與
/// ``Shape/path(in:)`` 繪圖所用的座標系相同。
///
/// 路徑會被展平成封閉多邊形——曲線、圓與圓弧都化為短線段——讓每個 backend 都能以相同的算術、
/// 得到相同的「此點是否在內」答案。在其他語言中做判斷的 backend(GTK 的 C、Android 的 Kotlin)
/// 會拿到 ``flattenedPoints`` 與 ``contourPointCounts``,並執行同一條規則。
public struct HitRegion: Equatable, Sendable {
    /// Closed polygons; the last point of each joins back to its first.
    /// 封閉多邊形；每一個的最後一點都接回它的第一點。
    public var contours: [[SIMD2<Double>]]
    /// `true` for the even-odd rule, `false` for non-zero winding.
    /// `true` 表示奇偶規則,`false` 表示非零環繞規則。
    public var evenOdd: Bool

    /// Line segments used for a full circle; an arc uses its share of them.
    /// 一個完整圓所用的線段數；圓弧依比例使用。
    static let circleSegments = 96
    /// Line segments used for one quadratic or cubic curve.
    /// 一段二次或三次曲線所用的線段數。
    static let curveSegments = 24

    public init(contours: [[SIMD2<Double>]], evenOdd: Bool = false) {
        self.contours = contours
        self.evenOdd = evenOdd
    }

    /// A region covering a whole rectangle of the given size.
    /// 涵蓋給定尺寸整個矩形的區域。
    public static func rectangle(width: Double, height: Double) -> HitRegion {
        HitRegion(contours: [[[0, 0], [width, 0], [width, height], [0, height]]])
    }

    /// Flattens a path. `evenOdd` is the fill rule of the region, which is
    /// what `contentShape(_:eoFill:)` chooses; the path's own fill rule is for
    /// drawing and is not used.
    ///
    /// 展平一條路徑。`evenOdd` 是本區域的填色規則，由 `contentShape(_:eoFill:)` 決定；
    /// 路徑自己的填色規則是給繪圖用的，此處不使用。
    public init(path: Path, evenOdd: Bool = false) {
        var flattener = Flattener()
        flattener.apply(path.actions)
        self.init(contours: flattener.finished(), evenOdd: evenOdd)
    }

    /// Whether a point is inside, by the region's fill rule. A point exactly on
    /// an edge may fall either side; nothing a pointer does depends on that.
    ///
    /// 依本區域的填色規則判斷一個點是否在內。正好落在邊上的點可能歸到任一側；指標的任何
    /// 行為都不取決於此。
    public func contains(_ point: SIMD2<Double>) -> Bool {
        var winding = 0
        var crossings = 0
        for contour in contours where contour.count >= 3 {
            var previous = contour[contour.count - 1]
            for current in contour {
                if (previous.y <= point.y) != (current.y <= point.y) {
                    let t = (point.y - previous.y) / (current.y - previous.y)
                    let x = previous.x + t * (current.x - previous.x)
                    if x > point.x {
                        crossings += 1
                        winding += current.y > previous.y ? 1 : -1
                    }
                }
                previous = current
            }
        }
        return evenOdd ? crossings % 2 == 1 : winding != 0
    }

    /// Every contour's points one after another as x, y pairs, for a backend
    /// that tests containment outside Swift. / 所有輪廓的點依序以 x、y 成對排列，
    /// 供在 Swift 之外判斷包含關係的 backend 使用。
    public var flattenedPoints: [Double] {
        contours.flatMap { $0.flatMap { [$0.x, $0.y] } }
    }

    /// How many points each contour in ``flattenedPoints`` has.
    /// ``flattenedPoints`` 中每個輪廓各有幾個點。
    public var contourPointCounts: [Int] {
        contours.map(\.count)
    }

    /// The same region with every coordinate multiplied by `factor`, for a
    /// backend whose widgets measure in device pixels.
    /// 每個座標都乘上 `factor` 的同一區域，供 widget 以裝置像素為單位的 backend 使用。
    /// The region with every point mapped through `transform`, the way a
    /// geometric effect maps the view it is applied to.
    ///
    /// 每個點都經 `transform` 映射後的區域，與幾何效果映射其所套用之 view 的方式相同。
    public func applying(_ transform: AffineTransform) -> HitRegion {
        guard transform != .identity else { return self }
        let m = transform.linearTransform
        let t = transform.translation
        return HitRegion(
            contours: contours.map { contour in
                contour.map { p in
                    SIMD2(m.x * p.x + m.y * p.y + t.x, m.z * p.x + m.w * p.y + t.y)
                }
            },
            evenOdd: evenOdd
        )
    }

    public func scaled(by factor: Double) -> HitRegion {
        HitRegion(
            contours: contours.map { $0.map { $0 * factor } },
            evenOdd: evenOdd
        )
    }

    /// Turns path actions into polygons, following the meaning
    /// ``Path/Action`` documents: the first action starts at (0, 0), a
    /// transform applies to everything drawn so far, and a subpath's own
    /// transforms stay inside it.
    ///
    /// 把路徑動作轉為多邊形，遵循 ``Path/Action`` 所記載的意義：第一個動作從 (0, 0) 開始，
    /// transform 作用於至今畫出的一切，而 subpath 自己的 transform 只留在它之內。
    struct Flattener {
        var contours: [[SIMD2<Double>]] = []
        var current: [SIMD2<Double>] = []
        var currentPoint = SIMD2<Double>(0, 0)

        mutating func closeCurrent() {
            if !current.isEmpty {
                contours.append(current)
                current = []
            }
        }

        mutating func ensureStarted() {
            if current.isEmpty {
                current = [currentPoint]
            }
        }

        mutating func addPoint(_ point: SIMD2<Double>) {
            current.append(point)
            currentPoint = point
        }

        mutating func finished() -> [[SIMD2<Double>]] {
            closeCurrent()
            return contours
        }

        mutating func apply(_ actions: [Path.Action]) {
            for action in actions {
                switch action {
                    case .moveTo(let point):
                        closeCurrent()
                        current = [point]
                        currentPoint = point
                    case .lineTo(let point):
                        ensureStarted()
                        addPoint(point)
                    case .quadCurve(let control, let end):
                        ensureStarted()
                        let start = currentPoint
                        for step in 1...HitRegion.curveSegments {
                            let t = Double(step) / Double(HitRegion.curveSegments)
                            let u = 1 - t
                            addPoint(u * u * start + 2 * u * t * control + t * t * end)
                        }
                    case .cubicCurve(let control1, let control2, let end):
                        ensureStarted()
                        let start = currentPoint
                        for step in 1...HitRegion.curveSegments {
                            let t = Double(step) / Double(HitRegion.curveSegments)
                            let u = 1 - t
                            let a = u * u * u * start + 3 * u * u * t * control1
                            addPoint(a + 3 * u * t * t * control2 + t * t * t * end)
                        }
                    case .rectangle(let rect):
                        closeCurrent()
                        contours.append([
                            rect.origin,
                            [rect.maxX, rect.y],
                            [rect.maxX, rect.maxY],
                            [rect.x, rect.maxY],
                        ])
                        currentPoint = rect.origin
                    case .circle(let center, let radius):
                        closeCurrent()
                        var circle: [SIMD2<Double>] = []
                        for step in 0..<HitRegion.circleSegments {
                            let angle = 2 * Double.pi * Double(step) / Double(HitRegion.circleSegments)
                            circle.append(center + radius * SIMD2(cos(angle), sin(angle)))
                        }
                        contours.append(circle)
                        currentPoint = center + SIMD2(radius, 0)
                    case .arc(let center, let radius, let startAngle, let endAngle, let clockwise):
                        // Angles grow clockwise on screen (y down), so a
                        // clockwise arc runs from start to a larger end.
                        // 角度在螢幕上(y 向下)順時針增加，因此順時針圓弧從起點走到較大的終點。
                        var sweep = endAngle - startAngle
                        if clockwise {
                            while sweep < 0 { sweep += 2 * .pi }
                        } else {
                            while sweep > 0 { sweep -= 2 * .pi }
                        }
                        let fraction = abs(sweep) / (2 * .pi)
                        let steps = max(1, Int((fraction * Double(HitRegion.circleSegments)).rounded(.up)))
                        let first = center + radius * SIMD2(cos(startAngle), sin(startAngle))
                        if current.isEmpty {
                            current = [first]
                            currentPoint = first
                        } else {
                            addPoint(first)
                        }
                        for step in 1...steps {
                            let angle = startAngle + sweep * Double(step) / Double(steps)
                            addPoint(center + radius * SIMD2(cos(angle), sin(angle)))
                        }
                    case .transform(let transform):
                        let m = transform.linearTransform
                        let t = transform.translation
                        func map(_ p: SIMD2<Double>) -> SIMD2<Double> {
                            SIMD2(m.x * p.x + m.y * p.y + t.x, m.z * p.x + m.w * p.y + t.y)
                        }
                        contours = contours.map { $0.map(map) }
                        current = current.map(map)
                        currentPoint = map(currentPoint)
                    case .subpath(let actions):
                        closeCurrent()
                        var inner = Flattener()
                        inner.apply(actions)
                        let last = inner.currentPoint
                        contours.append(contentsOf: inner.finished())
                        currentPoint = last
                }
            }
        }
    }
}

