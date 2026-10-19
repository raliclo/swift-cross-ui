import Testing

@testable @_spi(Backends) import SwiftCrossUI

/// Keyframes and phases: the value a keyframe timeline gives at a time (a pure
/// function, no clock), and the phase and keyframe animators without a frame
/// clock, where a play goes to its end at once.
///
/// 關鍵影格與階段：關鍵影格 timeline 在某一時刻給出的值(純函數，不需要時鐘),以及沒有 frame clock 時的階段與
/// 關鍵影格 animator——此時播放會立刻走到終點。
@MainActor
@Suite("Keyframes and phases")
struct KeyframeTests {
    struct Values: Equatable {
        var x = 0.0
        var y = 0.0
        var scale = 1.0
    }

    func close(_ a: Double, _ b: Double, _ tolerance: Double = 1e-9) -> Bool {
        abs(a - b) <= tolerance
    }

    @Test("A linear keyframe moves on its curve and holds its value after")
    func linear() {
        let timeline = KeyframeTimeline(initialValue: Values()) {
            KeyframeTrack(\.x) {
                LinearKeyframe(100, duration: 1)
            }
            KeyframeTrack(\.y) {
                LinearKeyframe(40, duration: 2, timingCurve: .easeInOut)
            }
        }
        #expect(timeline.duration == 2)
        #expect(close(timeline.value(time: 0.5).x, 50))
        #expect(close(timeline.value(time: 1).x, 100))
        #expect(close(timeline.value(time: 1.7).x, 100))
        #expect(close(timeline.value(time: 1).y, 20, 1e-6))
        #expect(timeline.value(time: 0) == Values())
        #expect(close(timeline.value(progress: 1).y, 40))
        // Untracked properties keep the initial value. / 沒有軌道的屬性維持初始值。
        #expect(timeline.value(time: 0.5).scale == 1)
    }

    @Test("Unit curves: SwiftUI's eases and the circular ones")
    func unitCurves() {
        #expect(close(UnitCurve.linear.value(at: 0.3), 0.3))
        #expect(close(UnitCurve.easeInOut.value(at: 0.5), 0.5, 1e-6))
        #expect(UnitCurve.easeIn.value(at: 0.25) < 0.25)
        #expect(UnitCurve.easeOut.value(at: 0.25) > 0.25)
        #expect(close(UnitCurve.circularEaseIn.value(at: 0.5), 1 - 0.75.squareRoot()))
        #expect(close(UnitCurve.circularEaseOut.value(at: 0.5), 0.75.squareRoot()))
        #expect(close(UnitCurve.circularEaseInOut.value(at: 0.5), 0.5))
        let bezier = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.42, y: 0), endControlPoint: UnitPoint(x: 0.58, y: 1))
        #expect(close(bezier.value(at: 0.2), UnitCurve.easeInOut.value(at: 0.2)))
    }

    @Test("A move jumps; the next keyframe starts from the moved value")
    func move() {
        let timeline = KeyframeTimeline(initialValue: 0.0) {
            KeyframeTrack {
                LinearKeyframe(100, duration: 1)
                MoveKeyframe(0)
                LinearKeyframe(50, duration: 1)
            }
        }
        #expect(close(timeline.value(time: 0.99), 99))
        #expect(close(timeline.value(time: 1), 0))
        #expect(close(timeline.value(time: 1.5), 25))
        #expect(close(timeline.value(time: 9), 50))
        // A move first takes effect at time zero. / 最前面的 move 在時間零就生效。
        let first = KeyframeTimeline(initialValue: 0.0) {
            KeyframeTrack {
                MoveKeyframe(7)
                LinearKeyframe(17, duration: 1)
            }
        }
        #expect(close(first.value(time: 0), 7))
        #expect(close(first.value(time: 0.5), 12))
    }

    @Test("A spring keyframe follows the spring from rest; cut short, the next starts from there")
    func spring() {
        let spring = Spring.bouncy
        let timeline = KeyframeTimeline(initialValue: 0.0) {
            KeyframeTrack {
                SpringKeyframe(100, duration: 0.2, spring: spring)
                LinearKeyframe(0, duration: 1)
            }
        }
        let reached = 100 * (1 - spring.remaining(at: 0.2))
        #expect(close(timeline.value(time: 0.1), 100 * (1 - spring.remaining(at: 0.1))))
        #expect(close(timeline.value(time: 0.2), reached))
        #expect(close(timeline.value(time: 0.7), reached / 2))
        // Without a duration the segment lasts the spring's response.
        // 沒有 duration 時，區段持續彈簧的 response。
        let plain = KeyframeTimeline(initialValue: 0.0) {
            KeyframeTrack { SpringKeyframe(1, spring: Spring.smooth) }
        }
        #expect(plain.duration == Spring.smooth.duration)
        // A bouncy spring overshoots. / 有彈性的彈簧會衝過頭。
        let long = KeyframeTimeline(initialValue: 0.0) {
            KeyframeTrack { SpringKeyframe(100, duration: 2, spring: spring) }
        }
        let peak = stride(from: 0.0, through: 2, by: 0.01).map { long.value(time: $0) }.max() ?? 0
        #expect(peak > 100)
    }

    @Test("Cubic keyframes pass through each value with a smooth slope")
    func cubic() {
        let timeline = KeyframeTimeline(initialValue: 0.0) {
            KeyframeTrack {
                CubicKeyframe(10, duration: 1)
                CubicKeyframe(30, duration: 1)
                CubicKeyframe(0, duration: 2)
            }
        }
        #expect(close(timeline.value(time: 1), 10))
        #expect(close(timeline.value(time: 2), 30))
        #expect(close(timeline.value(time: 4), 0))
        let h = 1e-5
        for knot in [1.0, 2.0] {
            let left = (timeline.value(time: knot) - timeline.value(time: knot - h)) / h
            let right = (timeline.value(time: knot + h) - timeline.value(time: knot)) / h
            #expect(close(left, right, 1e-3))
        }
        // Rising through 10 at t = 1 (between 0 and 30), not flat.
        // 在 t = 1 經過 10 時是上升的(介於 0 與 30 之間),不是平的。
        #expect(timeline.value(time: 1.1) > 10)
    }

    @Test("Tracks of different lengths: the timeline lasts the longest")
    func lengths() {
        let timeline = KeyframeTimeline(initialValue: Values()) {
            KeyframeTrack(\.x) { LinearKeyframe(1, duration: 0.5) }
            KeyframeTrack(\.scale) {
                LinearKeyframe(2, duration: 1)
                LinearKeyframe(1, duration: 1)
            }
        }
        #expect(timeline.duration == 2)
        #expect(timeline.value(time: 1.5) == Values(x: 1, y: 0, scale: 1.5))
    }

    @Test("Builders take if, else and loops")
    func builders() {
        let wide = true
        let timeline = KeyframeTimeline(initialValue: 0.0) {
            KeyframeTrack {
                if wide {
                    LinearKeyframe(200, duration: 1)
                } else {
                    LinearKeyframe(100, duration: 1)
                }
                for _ in 0..<2 {
                    LinearKeyframe(0, duration: 0.5)
                }
            }
        }
        #expect(timeline.duration == 2)
        #expect(close(timeline.value(time: 1), 200))
    }

    @Test("Without a frame clock a keyframe play ends on the last value")
    func animatorNoClock() {
        let model = KeyframeAnimatorModel<Double>()
        let timeline = KeyframeTimeline(initialValue: 0.0) {
            KeyframeTrack { LinearKeyframe(80, duration: 1) }
        }
        model.play(timeline, repeating: true)
        #expect(model.value == 80)
        #expect(!model.isPlaying)
    }

    @Test("Without a frame clock phases go round once and end on the first")
    func phasesNoClock() {
        let model = PhaseAnimatorModel()
        var asked: [Int] = []
        model.run(count: 3, cycles: false) { asked.append($0); return .linear(duration: 0.2) }
        #expect(asked == [1, 2, 0])
        #expect(model.index == 0)
        asked = []
        model.run(count: 3, cycles: true) { asked.append($0); return nil }
        #expect(asked == [1, 2, 0])
        model.run(count: 1, cycles: true) { _ in .default }
        #expect(model.index == 0)
    }

    @Test("A trigger compares by value, whatever its type")
    func trigger() {
        #expect(AnyEquatableTrigger(3) == AnyEquatableTrigger(3))
        #expect(AnyEquatableTrigger(3) != AnyEquatableTrigger(4))
        #expect(AnyEquatableTrigger(3) != AnyEquatableTrigger("3"))
    }
}
