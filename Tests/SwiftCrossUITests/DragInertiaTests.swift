import Foundation
import Testing

@testable @_spi(Backends) import SwiftCrossUI

/// Draggable with inertia: the release velocity from drag points and their
/// arrival times, and the coast (``Inertia``) as a function of time.
///
/// 帶慣性的拖曳：由拖曳點及其抵達時間算出的放開速度，以及作為時間函數的滑行(``Inertia``)。
@MainActor
@Suite("Drag inertia")
struct DragInertiaTests {
    func close(_ a: Double, _ b: Double, _ tolerance: Double = 1e-9) -> Bool {
        abs(a - b) <= tolerance
    }

    func value(_ x: Double, _ y: Double = 0) -> DragGestureValue {
        DragGestureValue(startLocation: .zero, location: SIMD2(x, y))
    }

    @Test("Velocity over the last tenth of a second; zero after standing still")
    func velocity() {
        var tracker = DragVelocityTracker()
        // 500 pt/s to the right, a point every 10 ms.
        // 每秒 500 點往右，每 10 毫秒一點。
        var last = DragGestureValue(startLocation: .zero, location: .zero)
        for i in 0...30 {
            last = tracker.changed(value(Double(i) * 5), at: 1 + Double(i) * 0.01)
        }
        #expect(close(last.velocity.x, 500, 1e-6))
        let released = tracker.ended(value(155), at: 1.31)
        #expect(close(released.velocity.x, 500, 1e-6))
        #expect(close(released.predictedEndTranslation.x, 155 + 500 * Inertia.timeConstant(0.998)))

        // Held still 0.2 s before letting go: no velocity.
        // 放開前靜止 0.2 秒：沒有速度。
        var still = DragVelocityTracker()
        for i in 0...10 {
            _ = still.changed(value(Double(i) * 5), at: Double(i) * 0.01)
        }
        #expect(still.ended(value(50), at: 0.3).velocity == .zero)
        // A new drag starts afresh. / 新的拖曳重新開始。
        #expect(still.changed(value(0), at: 5).velocity == .zero)
    }

    @Test("UIScrollView's time constants: 0.4995 s normal, 0.0995 s fast")
    func timeConstants() {
        #expect(close(Inertia.timeConstant(Inertia.normalDecelerationRate), 0.4995, 1e-4))
        #expect(close(Inertia.timeConstant(Inertia.fastDecelerationRate), 0.0995, 1e-4))
    }

    @Test("A free coast stops v·τ away, starts at the release speed and slows down")
    func freeCoast() {
        let tau = Inertia.timeConstant(0.998)
        let inertia = Inertia(start: SIMD2(10, 0), velocity: SIMD2(1000, 0))
        #expect(close(inertia.end.x, 10 + 1000 * tau, 1e-9))
        #expect(close(inertia.duration, tau * log(1000 * tau / Inertia.restDistance), 1e-9))
        let h = 1e-4
        let initialSpeed = (inertia.position(at: h).x - inertia.position(at: 0).x) / h
        #expect(close(initialSpeed, 1000, 1000 * 0.001))
        var previous = inertia.position(at: 0).x
        var previousStep = Double.infinity
        for i in 1...50 {
            let x = inertia.position(at: Double(i) * inertia.duration / 50).x
            #expect(x >= previous)
            #expect(x - previous <= previousStep + 1e-9)
            previousStep = x - previous
            previous = x
        }
        #expect(inertia.position(at: inertia.duration + 1) == inertia.end)
    }

    @Test("Bounds: the coast stops on the edge, from the same release speed")
    func bounded() {
        let bounds = Path.Rect(x: 0, y: 0, width: 200, height: 100)
        let inertia = Inertia(start: SIMD2(100, 50), velocity: SIMD2(3000, -40), bounds: bounds)
        #expect(inertia.end.x == 200)
        #expect(close(inertia.end.y, 50 - 40 * Inertia.timeConstant(0.998)))
        let h = 1e-5
        let initialSpeed = (inertia.position(at: h).x - inertia.position(at: 0).x) / h
        #expect(close(initialSpeed, 3000, 3000 * 0.002))
        let peak = stride(from: 0.0, through: inertia.duration, by: 0.001).map { inertia.position(at: $0).x }.max() ?? 0
        #expect(peak <= 200 + 1e-9)
        // A start outside the bounds begins on the edge.
        // 從範圍外開始時，從邊上開始。
        #expect(Inertia(start: SIMD2(-50, 50), velocity: .zero, bounds: bounds).start == SIMD2(0, 50))
    }

    @Test("No velocity, no coast")
    func still() {
        let inertia = Inertia(start: SIMD2(3, 4), velocity: .zero)
        #expect(inertia.duration == 0)
        #expect(inertia.end == SIMD2(3, 4))
    }

    @Test("The controller drags inside the bounds and, without a clock, coasts to the end")
    func controller() {
        let controller = InertialDragController()
        controller.bounds = Path.Rect(x: -100, y: 0, width: 200, height: 0)
        var inner: [SwiftCrossUI.AffineTransform] = []
        var outer: [SwiftCrossUI.AffineTransform] = []
        controller.drawInner = { inner.append($0) }
        controller.drawOuter = { outer.append($0) }
        var written: SIMD2<Double>?
        controller.binding = Binding(get: { written ?? .zero }, set: { written = $0 })
        controller.commit(offset: .zero)
        // During the drag the outer container stays where the drag began.
        // 拖曳期間外層容器停在拖曳開始之處。
        for i in 1...10 {
            controller.changed(value(Double(i) * 5, 30), at: Double(i) * 0.01)
        }
        #expect(controller.drawn == SIMD2(50, 0))
        #expect(outer.last == .identity)
        #expect(inner.last == .translation(x: 50, y: 0))
        controller.ended(value(55, 30), at: 0.11)
        // 500 pt/s would coast 250 pt; the bound at 100 stops it.
        // 每秒 500 點會滑 250 點;100 的邊界擋下它。
        #expect(controller.drawn == SIMD2(100, 0))
        #expect(written == SIMD2(100, 0))
        #expect(outer.last == .translation(x: 100, y: 0))
        #expect(inner.last == .identity)
    }
}
