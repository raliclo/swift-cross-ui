import Foundation

// GSAP's Draggable with InertiaPlugin: `.inertialDrag(offset:bounds:axes:
// decelerationRate:)` moves a view with the pointer and, when it is let go,
// coasts from the release velocity to a stop, decelerating, optionally inside
// bounds. The velocity is SwiftUI's `DragGesture.Value.velocity`, which
// `onDragGesture` now reports too (``DragVelocityTracker``).
//
// **The coast.** ``Inertia`` is UIScrollView's deceleration: the speed falls by
// `decelerationRate` each millisecond (0.998 normal, 0.99 fast), so the view
// moves `x(t) = x0 + v·τ·(1 - e^(-t/τ))` with τ = -1 ms / ln(rate) and stops
// `v·τ` from where it was let go -- the distance `predictedEndTranslation`
// adds. When that end is outside the bounds the axis stops on the bound
// instead, decelerating the same way from the same release speed over the
// shorter distance. The coast ends when less than a tenth of a point is left,
// and lands on its end exactly.
//
// **How it is drawn.** Three widgets: a geometric-effect container around the
// drag target around a second geometric-effect container around the content.
// At rest the outer one carries the offset and the inner one nothing; while a
// drag is held the outer one stays where the drag began and the inner one
// carries the movement. So the drag target does not move under the pointer
// during a drag -- the reported translation is the pointer's, on every backend,
// whether or not a backend measures through a transform -- yet the view can be
// picked up again wherever it was left, or caught in mid-coast. Every frame is
// set on the containers from the frame clock with no body evaluation; the
// binding is written when a drag ends without a coast and when a coast ends.
//
// GSAP 的 Draggable 加 InertiaPlugin:`.inertialDrag(offset:bounds:axes:decelerationRate:)` 讓 view 跟著指標移動，
// 放開時從放開的速度滑行、減速到停止，可選擇限制在範圍內。速度就是 SwiftUI 的 `DragGesture.Value.velocity`,現在
// `onDragGesture` 也會回報(``DragVelocityTracker``)。
//
// **滑行。** ``Inertia`` 是 UIScrollView 的減速：速度每毫秒乘以 `decelerationRate`(一般 0.998、快速 0.99),所以
// view 依 `x(t) = x0 + v·τ·(1 - e^(-t/τ))` 移動，τ = -1 毫秒 / ln(rate),停在離放開處 `v·τ` 的地方——正是
// `predictedEndTranslation` 加上的距離。當終點在範圍外，該軸改停在邊界上，以同樣的放開速度、同樣的方式在較短的
// 距離內減速。剩不到十分之一點時滑行結束，並精確落在終點。
//
// **怎麼畫。** 三個 widget:幾何效果容器包著拖曳目標，拖曳目標包著第二個幾何效果容器，裡面是內容。靜止時外層帶著
// 位移、內層什麼都沒有;拖曳進行中外層停在拖曳開始之處，由內層帶著移動。因此拖曳期間拖曳目標不會在指標下移動——
// 回報的位移就是指標的位移，在每個 backend 上都一樣，不論 backend 量測時是否經過變換——而 view 仍可在它被留下的
// 地方再次拿起，或在滑行途中接住。每一幀由 frame clock 設到容器上，不求值 body;拖曳結束而沒有滑行時、以及滑行
// 結束時才寫入 binding。

/// Velocity from the times drag points arrive, the same on every backend.
/// 依拖曳各點抵達的時間算出的速度，在每個 backend 上都一樣。
public struct DragVelocityTracker: Sendable {
    /// The span the velocity is measured over, in seconds.
    /// 量測速度的時間跨度(秒)。
    public static let window = 0.1

    private var samples: [(time: Double, location: SIMD2<Double>)] = []
    private var isActive = false

    public init() {}

    /// Notes a drag point that arrived at `time` and returns it with its velocity.
    /// 記下在 `time` 抵達的拖曳點，並帶著它的速度傳回。
    public mutating func changed(_ value: DragGestureValue, at time: Double) -> DragGestureValue {
        if !isActive {
            isActive = true
            samples = []
        }
        add(value.location, at: time)
        var value = value
        value.velocity = velocity(at: time)
        return value
    }

    /// Notes the last point; the velocity is the release velocity, zero when
    /// the pointer stood still for the whole window before it.
    /// 記下最後一點;速度即放開時的速度，指標在那之前整個時間窗都靜止時為零。
    public mutating func ended(_ value: DragGestureValue, at time: Double) -> DragGestureValue {
        if !isActive {
            samples = []
        }
        add(value.location, at: time)
        var value = value
        value.velocity = velocity(at: time)
        isActive = false
        return value
    }

    private mutating func add(_ location: SIMD2<Double>, at time: Double) {
        samples.append((time, location))
        samples.removeAll { time - $0.time > Self.window * 2 }
    }

    /// Points per second between the oldest and newest points of the window
    /// ending at `time`. / 以 `time` 結束的時間窗中，最舊與最新兩點之間每秒的點數。
    public func velocity(at time: Double) -> SIMD2<Double> {
        let recent = samples.filter { time - $0.time <= Self.window + 1e-9 }
        guard let first = recent.first, let last = recent.last, last.time - first.time > 0.004 else {
            return .zero
        }
        return (last.location - first.location) / (last.time - first.time)
    }
}

/// A coast from a release velocity to a stop -- GSAP's InertiaPlugin with
/// UIScrollView's deceleration, optionally stopping on bounds.
/// 從放開的速度滑行到停止——GSAP 的 InertiaPlugin,採用 UIScrollView 的減速，可選擇停在邊界上。
public struct Inertia: Equatable, Sendable {
    /// UIScrollView's `.normal` and `.fast`: the speed kept per millisecond.
    /// UIScrollView 的 `.normal` 與 `.fast`:每毫秒保留的速度比例。
    public static let normalDecelerationRate = 0.998
    public static let fastDecelerationRate = 0.99

    /// τ, the seconds in which the speed falls to 1/e.
    /// τ,速度降到 1/e 所需的秒數。
    public static func timeConstant(_ decelerationRate: Double) -> Double {
        let rate = min(max(decelerationRate, 0.5), 0.99999)
        return -0.001 / log(rate)
    }

    /// The coast ends with this much left, in points.
    /// 剩下這麼多點時滑行結束。
    public static let restDistance = 0.1

    struct Axis: Equatable, Sendable {
        var start: Double
        var distance: Double
        var timeConstant: Double
        var duration: Double

        init(start: Double, velocity: Double, timeConstant: Double, range: ClosedRange<Double>?) {
            let start = range.map { min(max(start, $0.lowerBound), $0.upperBound) } ?? start
            self.start = start
            var end = start + velocity * timeConstant
            if let range {
                end = min(max(end, range.lowerBound), range.upperBound)
            }
            distance = end - start
            // Stopped short by a bound: the same release speed over the
            // shorter distance. / 被邊界提早擋下：同樣的放開速度，較短的距離。
            if abs(velocity) > 0, abs(distance) < abs(velocity * timeConstant) {
                self.timeConstant = abs(distance / velocity)
            } else {
                self.timeConstant = timeConstant
            }
            if abs(distance) > Inertia.restDistance, self.timeConstant > 0 {
                duration = self.timeConstant * log(abs(distance) / Inertia.restDistance)
            } else {
                duration = 0
            }
        }

        func position(at time: Double) -> Double {
            guard duration > 0, time < duration else { return start + distance }
            guard time > 0 else { return start }
            let reached = 1 - exp(-time / timeConstant)
            let total = 1 - exp(-duration / timeConstant)
            return start + distance * reached / total
        }
    }

    let x: Axis
    let y: Axis

    /// Where the coast stops. / 滑行停止之處。
    public var end: SIMD2<Double> { SIMD2(x.start + x.distance, y.start + y.distance) }
    /// Where it starts, inside the bounds. / 起點，位於範圍之內。
    public var start: SIMD2<Double> { SIMD2(x.start, y.start) }
    /// Seconds until it stops. / 到停止為止的秒數。
    public var duration: Double { max(x.duration, y.duration) }

    /// - Parameters:
    ///   - start: The position when let go.
    ///   - velocity: Points per second when let go.
    ///   - decelerationRate: The speed kept per millisecond.
    ///   - bounds: Where the position may go; the coast stops on an edge.
    public init(
        start: SIMD2<Double>,
        velocity: SIMD2<Double>,
        decelerationRate: Double = Inertia.normalDecelerationRate,
        bounds: Path.Rect? = nil
    ) {
        let tau = Self.timeConstant(decelerationRate)
        x = Axis(
            start: start.x, velocity: velocity.x, timeConstant: tau,
            range: bounds.map { $0.x...$0.maxX }
        )
        y = Axis(
            start: start.y, velocity: velocity.y, timeConstant: tau,
            range: bounds.map { $0.y...$0.maxY }
        )
    }

    /// The position `time` seconds after release. / 放開後 `time` 秒的位置。
    public func position(at time: Double) -> SIMD2<Double> {
        SIMD2(x.position(at: time), y.position(at: time))
    }

    /// `point` moved into `bounds`. / 把 `point` 移進 `bounds`。
    static func clamp(_ point: SIMD2<Double>, to bounds: Path.Rect?) -> SIMD2<Double> {
        guard let bounds else { return point }
        return SIMD2(
            min(max(point.x, bounds.x), bounds.maxX),
            min(max(point.y, bounds.y), bounds.maxY)
        )
    }
}

extension View {
    /// Moves this view with a drag and, when let go, lets it coast from the
    /// release velocity to a stop -- GSAP's Draggable with InertiaPlugin.
    ///
    /// - Parameters:
    ///   - offset: Where the view is drawn from its layout position; written
    ///     when a drag ends without a coast and when a coast ends.
    ///   - bounds: The offsets allowed; a drag stops at an edge and a coast
    ///     stops on it.
    ///   - axes: The axes that move.
    ///   - decelerationRate: The speed kept per millisecond (``Inertia``).
    ///
    /// 讓此 view 隨拖曳移動，放開時從放開的速度滑行到停止——GSAP 的 Draggable 加 InertiaPlugin。`offset` 是 view
    /// 相對於其版面位置畫出之處，在拖曳結束而沒有滑行時、以及滑行結束時寫入;`bounds` 是允許的位移，拖曳停在邊上、
    /// 滑行停在邊上;`axes` 是會移動的軸;`decelerationRate` 是每毫秒保留的速度比例(``Inertia``)。
    public func inertialDrag(
        offset: Binding<SIMD2<Double>>,
        bounds: Path.Rect? = nil,
        axes: Axis.Set = [.horizontal, .vertical],
        decelerationRate: Double = Inertia.normalDecelerationRate
    ) -> some View {
        InertialDragModifier(
            content: self,
            offset: offset,
            bounds: bounds,
            axes: axes,
            decelerationRate: decelerationRate
        )
    }
}

/// Drives one inertial drag: the drawn offset, the drag and the coast.
/// 驅動一個慣性拖曳：畫出的位移、拖曳與滑行。
@MainActor
final class InertialDragController {
    /// Sets the inner container's transform (the movement during a drag).
    /// 設定內層容器的變換(拖曳期間的移動)。
    var drawInner: ((AffineTransform) -> Void)?
    /// Sets the outer container's transform (where the drag target is).
    /// 設定外層容器的變換(拖曳目標所在之處)。
    var drawOuter: ((AffineTransform) -> Void)?
    var label: String?
    var binding: Binding<SIMD2<Double>>?
    var bounds: Path.Rect?
    var axes: Axis.Set = [.horizontal, .vertical]
    var decelerationRate = Inertia.normalDecelerationRate

    private(set) var drawn = SIMD2<Double>(0, 0)
    private(set) var targetOffset = SIMD2<Double>(0, 0)
    private(set) var isDragging = false
    private(set) var inertia: Inertia?
    private var dragStart = SIMD2<Double>(0, 0)
    private var tracker = DragVelocityTracker()
    private var lastBound: SIMD2<Double>?
    private var coastStart: Double?
    private var ticker: UUID?
    private var lastInner: AffineTransform?
    private var lastOuter: AffineTransform?

    init() {}

    deinit {
        if let ticker {
            AnimationDriver.shared.removeTicker(ticker)
        }
    }

    /// Called on every commit with the binding's value; a value set from
    /// outside moves the view unless a drag or a coast is under way.
    /// 每次 commit 時以 binding 的值呼叫;從外部設定的值會移動 view,除非拖曳或滑行正在進行。
    func commit(offset: SIMD2<Double>) {
        if offset != lastBound {
            lastBound = offset
            if !isDragging && inertia == nil {
                drawn = offset
                targetOffset = offset
            }
        }
        draw()
    }

    func changed(_ raw: DragGestureValue, at time: Double) {
        let value = tracker.changed(raw, at: time)
        if !isDragging {
            // Caught in mid-coast, or picked up: the target stays here for the drag.
            // 滑行途中被接住，或被拿起：拖曳期間目標留在這裡。
            isDragging = true
            stopCoast()
            dragStart = drawn
            targetOffset = drawn
        }
        drawn = moved(by: value.translation)
        draw()
        InertialDragDiagnostics.record(label, .drag, offset: drawn, velocity: value.velocity)
    }

    func ended(_ raw: DragGestureValue, at time: Double) {
        // An end with no drag before it is not a throw, and a non-finite point
        // or velocity does not start a coast.
        // 之前沒有拖曳的結束不是一次拋擲，非有限值的點或速度也不會開始滑行。
        guard isDragging else {
            InertialDragDiagnostics.record(label, .ignoredEnd, offset: raw.location, velocity: .zero)
            return
        }
        var value = tracker.ended(raw, at: time)
        if !(value.velocity.x.isFinite && value.velocity.y.isFinite) {
            value.velocity = .zero
        }
        if value.translation.x.isFinite && value.translation.y.isFinite {
            drawn = moved(by: value.translation)
        }
        isDragging = false
        InertialDragDiagnostics.record(label, .release, offset: drawn, velocity: value.velocity)
        coast(velocity: value.velocity)
    }

    /// Starts a coast from the drawn offset. / 從畫出的位移開始滑行。
    func coast(velocity: SIMD2<Double>) {
        stopCoast()
        let velocity = SIMD2(
            axes.contains(.horizontal) ? velocity.x : 0,
            axes.contains(.vertical) ? velocity.y : 0
        )
        let inertia = Inertia(start: drawn, velocity: velocity, decelerationRate: decelerationRate, bounds: bounds)
        targetOffset = drawn
        guard inertia.duration > 0 else {
            drawn = inertia.end
            finish()
            return
        }
        self.inertia = inertia
        coastStart = nil
        InertialDragDiagnostics.record(label, .coast, offset: drawn, velocity: velocity, inertia: inertia)
        var endedAtOnce = false
        let key = AnimationDriver.shared.addTicker { [weak self] timestamp in
            MainActor.assumeIsolated {
                guard let self else { return false }
                let running = self.tick(timestamp)
                if !running { endedAtOnce = true }
                return running
            }
        }
        ticker = endedAtOnce ? nil : key
    }

    private func tick(_ timestamp: Double?) -> Bool {
        guard let inertia else { return false }
        guard let timestamp else {
            drawn = inertia.end
            finish()
            return false
        }
        guard let coastStart else {
            coastStart = timestamp
            return true
        }
        let elapsed = timestamp - coastStart
        drawn = inertia.position(at: elapsed)
        targetOffset = drawn
        draw()
        InertialDragDiagnostics.record(label, .frame, offset: drawn, velocity: .zero, elapsed: elapsed)
        if elapsed >= inertia.duration {
            finish()
            return false
        }
        return true
    }

    private func stopCoast() {
        if let ticker {
            AnimationDriver.shared.removeTicker(ticker)
        }
        ticker = nil
        inertia = nil
    }

    private func finish() {
        ticker = nil
        inertia = nil
        targetOffset = drawn
        draw()
        lastBound = drawn
        InertialDragDiagnostics.record(label, .end, offset: drawn, velocity: .zero)
        binding?.wrappedValue = drawn
    }

    private func moved(by translation: SIMD2<Double>) -> SIMD2<Double> {
        let moved = SIMD2(
            dragStart.x + (axes.contains(.horizontal) ? translation.x : 0),
            dragStart.y + (axes.contains(.vertical) ? translation.y : 0)
        )
        return Inertia.clamp(moved, to: bounds)
    }

    private func draw() {
        let outer = AffineTransform.translation(x: targetOffset.x, y: targetOffset.y)
        let delta = drawn - targetOffset
        let inner = AffineTransform.translation(x: delta.x, y: delta.y)
        if outer != lastOuter {
            lastOuter = outer
            drawOuter?(outer)
        }
        if inner != lastInner {
            lastInner = inner
            drawInner?(inner)
        }
    }
}

final class InertialDragChildren<Content: View>: TupleViewChildren1<Content> {
    /// Made on first use, on the main actor. / 第一次使用時(於 main actor 上)建立。
    private var made: InertialDragController?
    var inner: AnyWidget?
    var target: AnyWidget?

    var controller: InertialDragController {
        if let made {
            return made
        }
        let controller = InertialDragController()
        made = controller
        return controller
    }
}

struct InertialDragModifier<Content: View>: View, TypeSafeView {
    var content: Content
    var offset: Binding<SIMD2<Double>>
    var bounds: Path.Rect?
    var axes: Axis.Set
    var decelerationRate: Double

    var body: TupleView1<Content> { content }

    typealias Children = InertialDragChildren<Content>

    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> Children {
        Children(content, backend: backend, snapshots: snapshots, environment: environment)
    }

    /// Outer geometric container, drag target, inner geometric container, content.
    /// 外層幾何容器、拖曳目標、內層幾何容器、內容。
    func asWidget<Backend: BaseAppBackend>(
        _ children: Children,
        backend: Backend
    ) -> Backend.Widget {
        let content: Backend.Widget = body.asWidget(children, backend: backend)
        let inner = GeometricEffectWidgets.wrap(content, backend: backend) ?? content
        let target = DragTargetWidgets.wrap(inner, backend: backend) ?? inner
        children.inner = AnyWidget(inner)
        children.target = AnyWidget(target)
        return GeometricEffectWidgets.wrap(target, backend: backend) ?? target
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

    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        let size = children.child0.commit().size
        let inner: Backend.Widget = children.inner?.into() ?? widget
        let target: Backend.Widget = children.target?.into() ?? widget
        backend.setSize(of: inner, to: size.vector)
        backend.setSize(of: target, to: size.vector)
        backend.setSize(of: widget, to: size.vector)

        let controller = children.controller
        controller.binding = offset
        controller.bounds = bounds
        controller.axes = axes
        controller.decelerationRate = decelerationRate
        controller.label = environment.effectDiagnosticsLabel
        controller.drawInner = GeometricEffectWidgets.setter(for: inner, backend: backend)
        controller.drawOuter = GeometricEffectWidgets.setter(for: widget, backend: backend)
        InertialDragDiagnostics.register(controller)
        DragTargetWidgets.update(
            target,
            backend: backend,
            environment: environment,
            onChange: { [weak controller] value in
                controller?.changed(value, at: ProcessInfo.processInfo.systemUptime)
            },
            onEnd: { [weak controller] value in
                controller?.ended(value, at: ProcessInfo.processInfo.systemUptime)
            }
        )
        controller.commit(offset: offset.wrappedValue)
    }
}

/// Opens a backend's ``BackendFeatures/DragGestures`` for the inertial drag.
/// 為慣性拖曳開啟 backend 的 ``BackendFeatures/DragGestures``。
@MainActor
enum DragTargetWidgets {
    static func wrap<Backend: BaseAppBackend>(_ child: Backend.Widget, backend: Backend) -> Backend.Widget? {
        guard let capable = backend as? any BackendFeatures.DragGestures else {
            logger.warnOnce("\(type(of: backend)) doesn't support drag gestures; inertialDrag only draws")
            return nil
        }
        func open<B: BackendFeatures.DragGestures>(_ backend: B) -> Backend.Widget {
            backend.createDragGestureTarget(wrapping: child as! B.Widget) as! Backend.Widget
        }
        return open(capable)
    }

    static func update<Backend: BaseAppBackend>(
        _ target: Backend.Widget,
        backend: Backend,
        environment: EnvironmentValues,
        onChange: @escaping (DragGestureValue) -> Void,
        onEnd: @escaping (DragGestureValue) -> Void
    ) {
        guard let capable = backend as? any BackendFeatures.DragGestures else { return }
        func open<B: BackendFeatures.DragGestures>(_ backend: B) {
            backend.updateDragGestureTarget(
                target as! B.Widget, environment: environment, onChange: onChange, onEnd: onEnd
            )
        }
        open(capable)
    }
}

/// What each labelled inertial drag did, for test apps (P108); `fling` starts
/// a coast as a release at that velocity would. Not SwiftUI API.
/// 每個加了標籤的慣性拖曳做了什麼，供測試 app(P108)使用;`fling` 會像以那個速度放開一樣開始滑行。不是 SwiftUI API。
@_spi(Backends)
@MainActor
public enum InertialDragDiagnostics {
    public enum Kind: Sendable {
        case drag
        case release
        case coast
        case frame
        case end
        /// A drag end with no drag before it, which is ignored; `offset` is
        /// the location it reported. / 之前沒有拖曳的結束，會被忽略;`offset` 是它回報的位置。
        case ignoredEnd
    }

    public struct Event: Sendable {
        public var time: Double
        public var kind: Kind
        public var offset: SIMD2<Double>
        public var velocity: SIMD2<Double>
        /// Seconds into the coast, for `.frame`. / 滑行進行的秒數，供 `.frame` 使用。
        public var elapsed: Double
        /// The coast, for `.coast`. / 滑行本身，供 `.coast` 使用。
        public var inertia: Inertia?
    }

    public private(set) static var events: [String: [Event]] = [:]
    private static var controllers: [String: WeakController] = [:]

    private struct WeakController {
        weak var controller: InertialDragController?
    }

    static func register(_ controller: InertialDragController) {
        guard let label = controller.label else { return }
        controllers[label] = WeakController(controller: controller)
    }

    static func record(
        _ label: String?,
        _ kind: Kind,
        offset: SIMD2<Double>,
        velocity: SIMD2<Double>,
        elapsed: Double = 0,
        inertia: Inertia? = nil
    ) {
        guard let label else { return }
        events[label, default: []].append(
            Event(
                time: ProcessInfo.processInfo.systemUptime, kind: kind, offset: offset,
                velocity: velocity, elapsed: elapsed, inertia: inertia
            )
        )
    }

    /// Starts a coast of the labelled view from where it is drawn.
    /// 讓加了標籤的 view 從畫出之處開始滑行。
    public static func fling(_ label: String, velocity: SIMD2<Double>) {
        controllers[label]?.controller?.coast(velocity: velocity)
    }

    /// The labelled view's drawn offset. / 加了標籤的 view 畫出的位移。
    public static func drawnOffset(_ label: String) -> SIMD2<Double>? {
        controllers[label]?.controller?.drawn
    }

    public static func clear() {
        events = [:]
    }
}
