import Foundation

// GSAP's MotionPath with a SwiftUI-style API: `.motionPath(_:progress:anchor:
// orientsAlongPath:)` places a view on a `Path` at a fraction of its length, and
// `Path.trimmedPath(from:to:)`, `Path.currentPoint`, `Path.length` and
// `Path.point(at:)` measure a path the way SwiftUI's `trimmedPath(from:to:)`
// does.
//
// **The choice.** SwiftUI has no motion-path modifier; its idiom is
// `.position(path.trimmedPath(from: 0, to: progress).currentPoint)`, which
// re-lays out the view at every step. Here the view keeps its layout and is
// drawn moved -- the anchor point (the centre by default) at the path's point,
// the path read in the view's own coordinates with (0, 0) at its top-left, as
// `.offset` reads its distance -- and with `orientsAlongPath` rotated about the
// anchor to the path's direction there (GSAP's `autoRotate`). `progress` is a
// fraction of the path's length, so equal steps cover equal distances
// whatever the curves.
//
// **Animating it.** The modifier tweens `progress`, not the drawn position:
// under `.animation(_:value:)` or a `withAnimation` assignment that cannot tween
// (a `Bool` choosing 0 or 1), the view runs along the path on the frame clock
// from where it is drawn, on the direct path (no body evaluation, no re-layout),
// rather than in a straight line between the two ends. A `Double` state animated
// by `withAnimation` passes through every value itself and is drawn as it goes.
//
// **Measuring.** Curves and arcs are flattened to lines about a quarter point
// long (a circle of radius 100 measures within 0.01 pt of 2π·100 in the unit
// tests), transforms are
// applied as the path's actions give them, and the jump of a `move(to:)`
// between subpaths is not part of the length.
//
// GSAP 的 MotionPath,以 SwiftUI 風格的 API:`.motionPath(_:progress:anchor:orientsAlongPath:)` 把 view 放在
// `Path` 上長度的某個比例處;`Path.trimmedPath(from:to:)`、`Path.currentPoint`、`Path.length` 與 `Path.point(at:)`
// 以 SwiftUI `trimmedPath(from:to:)` 的方式量測路徑。
//
// **這個選擇。** SwiftUI 沒有沿路徑運動的 modifier;它的慣用法是
// `.position(path.trimmedPath(from: 0, to: progress).currentPoint)`,每一步都重新排版 view。這裡 view 維持它的
// 版面、被移動後畫出——錨點(預設為中心)落在路徑的點上，路徑以 view 自己的座標讀取、(0, 0) 在左上角，與
// `.offset` 讀取距離的方式相同——`orientsAlongPath` 時再繞錨點旋轉到該處路徑的方向(GSAP 的 `autoRotate`)。
// `progress` 是路徑長度的比例，所以不論曲線如何，相等的步長走相等的距離。
//
// **加上動畫。** modifier 補間的是 `progress`,不是畫出的位置：在 `.animation(_:value:)` 或無法補間的
// `withAnimation` 賦值(以 `Bool` 選 0 或 1)之下，view 在 frame clock 上從它畫出之處沿路徑前進，走直接路徑
// (不求值 body、不重排版面),而不是在兩端之間走直線。由 `withAnimation` 補間的 `Double` 狀態自己會經過每個值，
// 照著畫出即可。
//
// **量測。** 曲線與圓弧被展平為約四分之一點長的線段(單元測試中半徑 100 的圓與 2π·100 相差在 0.01 點以內);變換依路徑動作給出的方式套用;子路徑之間 `move(to:)` 的跳躍不算在長度內。

/// A point on a path and the path's direction there.
/// 路徑上的一點，以及路徑在該處的方向。
public struct PathPoint: Equatable, Sendable {
    public var position: SIMD2<Double>
    /// Clockwise from the trailing direction, as `rotationEffect` turns.
    /// 從後緣方向順時針量起，與 `rotationEffect` 轉動的方向相同。
    public var direction: Angle
}

/// A path flattened to polylines, with the length along them.
/// 展平為折線的路徑，以及沿折線的長度。
struct PathMeasure: Sendable {
    /// The polylines, one per subpath. / 各折線，每個子路徑一條。
    private(set) var polylines: [[SIMD2<Double>]] = []
    /// The length along each polyline up to each of its points.
    /// 每條折線到其每一點為止的長度。
    private(set) var lengths: [[Double]] = []
    private(set) var length = 0.0

    init(_ path: Path) {
        polylines = Self.flatten(path.actions).filter { $0.count > 1 }
        var total = 0.0
        for line in polylines {
            var running = [total]
            for (a, b) in zip(line, line.dropFirst()) {
                total += Self.distance(a, b)
                running.append(total)
            }
            lengths.append(running)
        }
        length = total
    }

    /// The point `fraction` of the way along the path's length.
    /// 沿路徑長度 `fraction` 處的點。
    func point(at fraction: Double) -> PathPoint? {
        guard let firstLine = polylines.first, let first = firstLine.first else { return nil }
        guard length > 0 else {
            return PathPoint(position: first, direction: .zero)
        }
        let target = min(max(fraction, 0), 1) * length
        for (lineIndex, line) in polylines.enumerated() {
            let running = lengths[lineIndex]
            guard let end = running.last, target <= end || lineIndex == polylines.count - 1 else {
                continue
            }
            // The segment holding the target; zero-length segments are skipped
            // so a direction always exists.
            // 包含目標的線段;略過長度為零的線段，讓方向一定存在。
            var index = 1
            while index < line.count - 1, running[index] < target {
                index += 1
            }
            var segmentStart = index - 1
            while segmentStart > 0, running[index] - running[segmentStart] == 0 {
                segmentStart -= 1
            }
            let a = line[segmentStart]
            let b = line[index]
            let span = running[index] - running[segmentStart]
            let t = span > 0 ? min(max((target - running[segmentStart]) / span, 0), 1) : 1
            let direction = Angle(radians: atan2(b.y - a.y, b.x - a.x))
            return PathPoint(position: a + (b - a) * t, direction: direction)
        }
        return nil
    }

    /// The part of the path between two fractions of its length, as lines.
    /// 路徑在兩個長度比例之間的部分，以線段表示。
    func trimmed(from start: Double, to end: Double) -> [[SIMD2<Double>]] {
        let from = min(max(start, 0), 1) * length
        let to = min(max(end, 0), 1) * length
        guard to > from else { return [] }
        var result: [[SIMD2<Double>]] = []
        for (lineIndex, line) in polylines.enumerated() {
            let running = lengths[lineIndex]
            guard let lineEnd = running.last, let lineStart = running.first,
                lineEnd > from, lineStart < to
            else { continue }
            var piece: [SIMD2<Double>] = []
            func at(_ distance: Double) -> SIMD2<Double> {
                var index = 1
                while index < line.count - 1, running[index] < distance {
                    index += 1
                }
                let span = running[index] - running[index - 1]
                let t = span > 0 ? (distance - running[index - 1]) / span : 0
                return line[index - 1] + (line[index] - line[index - 1]) * min(max(t, 0), 1)
            }
            piece.append(at(max(from, lineStart)))
            for (point, distance) in zip(line, running) where distance > from && distance < to {
                piece.append(point)
            }
            piece.append(at(min(to, lineEnd)))
            result.append(piece)
        }
        return result
    }

    static func distance(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
        let d = b - a
        return (d.x * d.x + d.y * d.y).squareRoot()
    }

    static func apply(_ transform: AffineTransform, _ p: SIMD2<Double>) -> SIMD2<Double> {
        let m = transform.linearTransform
        return SIMD2(
            m.x * p.x + m.y * p.y + transform.translation.x,
            m.z * p.x + m.w * p.y + transform.translation.y
        )
    }

    /// Steps for a curve whose control polygon is `length` long: about one
    /// per quarter point, at least 16. / 控制多邊形長 `length` 的曲線所用的步數：約每四分之一點一步，至少 16。
    static func steps(forLength length: Double) -> Int {
        min(max(Int((length * 4).rounded(.up)), 16), 4096)
    }

    /// The actions as polylines, in the path's own coordinates: a transform
    /// applies to what came before it in the same (sub)path.
    /// 把動作轉為折線，位於路徑自己的座標中：變換作用於同一個(子)路徑中在它之前的部分。
    static func flatten(_ actions: [Path.Action]) -> [[SIMD2<Double>]] {
        var lines: [[SIMD2<Double>]] = []
        var current: [SIMD2<Double>] = []
        var point = SIMD2<Double>(0, 0)

        func finish() {
            if current.count > 1 {
                lines.append(current)
            }
            current = []
        }
        func lineTo(_ p: SIMD2<Double>) {
            if current.isEmpty {
                current = [point]
            }
            current.append(p)
            point = p
        }
        func arcPoints(center: SIMD2<Double>, radius: Double, from a0: Double, sweep: Double)
            -> [SIMD2<Double>]
        {
            let count = steps(forLength: abs(sweep) * radius)
            return (0...count).map { i in
                let a = a0 + sweep * Double(i) / Double(count)
                return center + SIMD2(cos(a), sin(a)) * radius
            }
        }

        for action in actions {
            switch action {
                case .moveTo(let p):
                    finish()
                    point = p
                case .lineTo(let p):
                    lineTo(p)
                case .quadCurve(let control, let end):
                    let start = point
                    let count = steps(forLength: distance(start, control) + distance(control, end))
                    for i in 1...count {
                        let t = Double(i) / Double(count)
                        let u = 1 - t
                        lineTo(start * (u * u) + control * (2 * u * t) + end * (t * t))
                    }
                case .cubicCurve(let control1, let control2, let end):
                    let start = point
                    let count = steps(
                        forLength: distance(start, control1) + distance(control1, control2)
                            + distance(control2, end)
                    )
                    for i in 1...count {
                        let t = Double(i) / Double(count)
                        let u = 1 - t
                        lineTo(
                            start * (u * u * u) + control1 * (3 * u * u * t) + control2 * (3 * u * t * t)
                                + end * (t * t * t)
                        )
                    }
                case .rectangle(let rect):
                    finish()
                    lines.append([
                        rect.origin,
                        SIMD2(rect.maxX, rect.y),
                        SIMD2(rect.maxX, rect.maxY),
                        SIMD2(rect.x, rect.maxY),
                        rect.origin,
                    ])
                    point = rect.origin
                case .circle(let center, let radius):
                    finish()
                    lines.append(arcPoints(center: center, radius: radius, from: 0, sweep: 2 * .pi))
                    point = center + SIMD2(radius, 0)
                case .arc(let center, let radius, let startAngle, let endAngle, let clockwise):
                    // Angles grow clockwise on screen; a clockwise arc goes the
                    // growing way from start to end.
                    // 角度在螢幕上順時針增加;順時針的圓弧從起點往增加的方向走到終點。
                    var sweep = endAngle - startAngle
                    if clockwise {
                        while sweep < 0 { sweep += 2 * .pi }
                    } else {
                        while sweep > 0 { sweep -= 2 * .pi }
                    }
                    let points = arcPoints(center: center, radius: radius, from: startAngle, sweep: sweep)
                    if current.isEmpty && point == SIMD2(0, 0) && lines.isEmpty {
                        point = points[0]
                    }
                    for p in points {
                        lineTo(p)
                    }
                case .transform(let transform):
                    lines = lines.map { $0.map { apply(transform, $0) } }
                    current = current.map { apply(transform, $0) }
                    point = apply(transform, point)
                case .subpath(let inner):
                    finish()
                    let innerLines = flatten(inner)
                    lines.append(contentsOf: innerLines)
                    if let last = innerLines.last?.last {
                        point = last
                    }
            }
        }
        finish()
        return lines
    }
}

extension Path {
    /// The length of the path's drawn segments, not counting `move(to:)` jumps.
    /// 路徑畫出的線段長度，不含 `move(to:)` 的跳躍。
    public var length: Double {
        PathMeasure(self).length
    }

    /// The point `fraction` (`0...1`) of the way along the path's length, and
    /// the path's direction there; nil for an empty path.
    /// 沿路徑長度 `fraction`(`0...1`)處的點與該處路徑的方向;空路徑為 nil。
    public func point(at fraction: Double) -> PathPoint? {
        PathMeasure(self).point(at: fraction)
    }

    /// Where the path ends -- SwiftUI's `currentPoint`; nil for an empty path.
    /// 路徑結束之處——SwiftUI 的 `currentPoint`;空路徑為 nil。
    public var currentPoint: SIMD2<Double>? {
        PathMeasure(self).polylines.last?.last
    }

    /// The part of the path between two fractions of its length --
    /// SwiftUI's `trimmedPath(from:to:)`. Curves come back as short lines.
    /// 路徑在兩個長度比例之間的部分——SwiftUI 的 `trimmedPath(from:to:)`。曲線以短線段傳回。
    public func trimmedPath(from start: Double, to end: Double) -> Path {
        var trimmed = Path()
        for line in PathMeasure(self).trimmed(from: start, to: end) {
            guard let first = line.first else { continue }
            trimmed = trimmed.move(to: first)
            for point in line.dropFirst() {
                trimmed = trimmed.addLine(to: point)
            }
        }
        return trimmed.stroke(style: strokeStyle).fillRule(fillRule)
    }
}

extension View {
    /// Draws this view on `path` at `progress` (a fraction of its length):
    /// the view's `anchor` at the path's point, the path in the view's own
    /// coordinates, and with `orientsAlongPath` turned to the path's direction
    /// -- GSAP's MotionPath. The layout is unchanged.
    ///
    /// Under an animation `progress` tweens, so the view runs along the path.
    ///
    /// 把此 view 畫在 `path` 上的 `progress`(長度的比例)處:view 的 `anchor` 落在路徑的點上，路徑以 view 自己的
    /// 座標讀取;`orientsAlongPath` 時轉到路徑的方向——GSAP 的 MotionPath。版面不變。在動畫中 `progress` 會補間，
    /// 所以 view 沿著路徑前進。
    public func motionPath(
        _ path: Path,
        progress: Double,
        anchor: UnitPoint = .center,
        orientsAlongPath: Bool = false
    ) -> some View {
        MotionPathModifier(
            content: self,
            path: path,
            progress: progress,
            anchor: anchor,
            orientsAlongPath: orientsAlongPath
        )
    }
}

/// The children of a motion-path modifier: the progress tween and the measured path.
/// motion-path modifier 的 children:進度補間與量好的路徑。
final class MotionPathChildren<Content: View>: TupleViewChildren1<Content> {
    /// Made at the first commit, on the main actor. / 在第一次 commit 時(於 main actor 上)建立。
    var tween: ParameterTween<Double>?
    var measure: PathMeasure?
    var measuredActions: [Path.Action]?
}

struct MotionPathModifier<Content: View>: View, TypeSafeView {
    var content: Content
    var path: Path
    var progress: Double
    var anchor: UnitPoint
    var orientsAlongPath: Bool

    var body: TupleView1<Content> { content }

    typealias Children = MotionPathChildren<Content>

    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> Children {
        Children(content, backend: backend, snapshots: snapshots, environment: environment)
    }

    func asWidget<Backend: BaseAppBackend>(
        _ children: Children,
        backend: Backend
    ) -> Backend.Widget {
        let inner = body.asWidget(children, backend: backend)
        return GeometricEffectWidgets.wrap(inner, backend: backend) ?? inner
    }

    func layoutableChildren<Backend: BaseAppBackend>(
        backend: Backend,
        children: Children
    ) -> [LayoutSystem.LayoutableChild] {
        body.layoutableChildren(backend: backend, children: children)
    }

    func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        body.computeLayout(
            widget,
            children: children,
            proposedSize: proposedSize,
            environment: environment,
            backend: backend
        )
    }

    /// The effect that puts a view of `size` at `progress` along `measure`.
    /// 把尺寸為 `size` 的 view 放在 `measure` 上 `progress` 處的效果。
    static func effect(
        _ measure: PathMeasure,
        progress: Double,
        size: SIMD2<Double>,
        anchor: UnitPoint,
        orientsAlongPath: Bool
    ) -> GeometricEffect {
        guard let point = measure.point(at: progress) else { return .identity }
        let anchorPoint = SIMD2(anchor.x * size.x, anchor.y * size.y)
        return GeometricEffect(
            translation: point.position - anchorPoint,
            rotation: orientsAlongPath ? point.direction : .zero,
            anchor: anchor
        )
    }

    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        let size = children.child0.commit().size
        backend.setSize(of: widget, to: size.vector)
        guard let setter = GeometricEffectWidgets.setter(for: widget, backend: backend) else {
            return
        }
        if children.measuredActions != path.actions || children.measure == nil {
            children.measure = PathMeasure(path)
            children.measuredActions = path.actions
        }
        let measure = children.measure ?? PathMeasure(path)
        let resolvedSize = SIMD2(Double(size.vector.x), Double(size.vector.y))
        let anchor = anchor
        let orientsAlongPath = orientsAlongPath
        let label = environment.effectDiagnosticsLabel
        let draw = { (progress: Double) in
            let effect = Self.effect(
                measure, progress: progress, size: resolvedSize, anchor: anchor,
                orientsAlongPath: orientsAlongPath
            )
            setter(effect.resolved(in: resolvedSize))
            if let label {
                EffectAnimationDiagnostics.record(label: label, value: effect)
                MotionPathDiagnostics.record(label: label, progress: progress)
            }
        }
        let tween = children.tween ?? ParameterTween<Double>()
        children.tween = tween
        tween.onFrame = { [weak tween] in
            guard let drawn = tween?.drawn else { return }
            draw(drawn)
        }
        draw(tween.resolve(progress, transaction: EffectTransaction.current(in: environment)))
    }
}

/// The progress each labelled motion path last drew, for test apps (P107).
/// Not SwiftUI API. / 每個加了標籤的 motion path 最後畫出的進度，供測試 app(P107)使用。不是 SwiftUI API。
@_spi(Backends)
@MainActor
public enum MotionPathDiagnostics {
    public struct Sample: Sendable {
        public var time: Double
        public var progress: Double
    }

    public private(set) static var samples: [String: [Sample]] = [:]

    static func record(label: String, progress: Double) {
        if samples[label]?.last?.progress == progress { return }
        samples[label, default: []].append(Sample(time: ProcessInfo.processInfo.systemUptime, progress: progress))
    }

    public static func clear() {
        samples = [:]
    }
}
