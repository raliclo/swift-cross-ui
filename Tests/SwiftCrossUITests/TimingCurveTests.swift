import Foundation
import Testing

@testable import SwiftCrossUI

/// GSAP's eases, steps, Bézier and spring curves, and the clock that applies
/// delay, speed and repeats. The expected values are GSAP's and CSS's own
/// formulas worked by hand at a point where each shape is distinctive.
///
/// GSAP 的 ease、steps、Bézier 與彈簧曲線，以及套用延遲、速度與重複的時鐘。期望值是 GSAP 與 CSS 自己的
/// 公式，在每種形狀最有辨識度的一點上手算出來的。
@Suite("Timing curves")
struct TimingCurveTests {
    static let directions: [Ease.Direction] = [.in, .out, .inOut]
    static let shapes: [Ease.Shape] = [
        .power(1), .power(2), .power(3), .power(4), .sine, .expo, .circ,
        .back(overshoot: 1.70158), .elastic(amplitude: 1, period: 0.3), .bounce,
    ]

    static var everyCurve: [any TimingCurve] {
        var curves: [any TimingCurve] = []
        for shape in shapes {
            for direction in directions {
                curves.append(Ease(shape, direction))
            }
        }
        curves += [
            Steps(4), CubicBezier(0.25, 0.1, 0.25, 1), CubicBezier(0.68, -0.6, 0.32, 1.6),
            Spring(response: 0.5, dampingFraction: 0.5), Spring(duration: 0.5, bounce: 0),
            Spring(duration: 0.5, bounce: -0.5),
        ]
        return curves
    }

    @Test("Every curve starts at exactly 0 and arrives at exactly 1")
    func curvesArrive() {
        for curve in Self.everyCurve {
            #expect(curve.progress(at: 0) == 0, "\(curve) at 0")
            #expect(curve.progress(at: 1) == 1, "\(curve) at 1")
            #expect(curve.progress(at: 1.3) == 1, "\(curve) past the end")
            #expect(curve.progress(at: -0.3) == 0, "\(curve) before the start")
        }
    }

    @Test("GSAP's values at the midpoint")
    func gsapMidpoints() {
        func value(_ curve: Ease) -> Double { curve.progress(at: 0.5) }
        #expect(abs(value(.power1(.in)) - 0.25) < 1e-12)
        #expect(abs(value(.power2(.out)) - 0.875) < 1e-12)
        #expect(abs(value(.power4(.inOut)) - 0.5) < 1e-12)
        #expect(abs(value(.sine(.inOut)) - 0.5) < 1e-12)
        #expect(abs(value(.expo(.out)) - 0.96875) < 1e-12)
        #expect(abs(value(.circ(.out)) - 0.75.squareRoot()) < 1e-12)
        // back.out passes the target: 1 - 0.25 * (2.70158 * 0.5 - 1.70158).
        // back.out 衝過目標:1 - 0.25 * (2.70158 * 0.5 - 1.70158)。
        #expect(abs(value(.back(.out)) - 1.0876975) < 1e-7)
        // elastic.out(1, 0.3): 2^-5 * sin(150 degrees) + 1.
        // elastic.out(1, 0.3):2^-5 * sin(150 度) + 1。
        #expect(abs(value(.elastic(.out)) - 1.015625) < 1e-9)
        // bounce.out: second parabola, 7.5625 * (0.5 - 1.5 / 2.75)^2 + 0.75.
        // bounce.out:第二段拋物線,7.5625 * (0.5 - 1.5 / 2.75)^2 + 0.75。
        #expect(abs(value(.bounce(.out)) - 0.765625) < 1e-9)
    }

    @Test("in and out mirror each other, and inOut joins them at one half")
    func directionsAreConsistent() {
        for shape in Self.shapes {
            let easeIn = Ease(shape, .in)
            let easeOut = Ease(shape, .out)
            let both = Ease(shape, .inOut)
            for step in 1..<20 {
                let t = Double(step) / 20
                #expect(
                    abs(easeOut.progress(at: t) - (1 - easeIn.progress(at: 1 - t))) < 1e-12,
                    "\(shape) at \(t)"
                )
            }
            #expect(abs(both.progress(at: 0.25) - easeIn.progress(at: 0.5) / 2) < 1e-12)
            #expect(abs(both.progress(at: 0.5) - 0.5) < 1e-12, "\(shape) inOut midpoint")
        }
    }

    @Test("Steps jump at each quarter and reach 1 only at the end")
    func steps() {
        let curve = Steps(4)
        #expect(curve.progress(at: 0.24) == 0)
        #expect(curve.progress(at: 0.25) == 0.25)
        #expect(curve.progress(at: 0.99) == 0.75)
        #expect(curve.progress(at: 1) == 1)
    }

    @Test("CSS's `ease` is cubic-bezier(0.25, 0.1, 0.25, 1)")
    func cssEase() {
        // 0.8024033877 is what browsers compute for `ease` at 50%.
        // 0.8024033877 是瀏覽器對 `ease` 在 50% 時算出的值。
        #expect(abs(CubicBezier(0.25, 0.1, 0.25, 1).progress(at: 0.5) - 0.8024033877) < 1e-6)
        let linear = CubicBezier(0, 0, 1, 1)
        for step in 0...10 {
            let t = Double(step) / 10
            #expect(abs(linear.progress(at: t) - t) < 1e-6)
        }
    }

    @Test("A critically damped spring never passes the target; a bouncy one does")
    func springs() {
        let critical = Spring(duration: 0.5, bounce: 0)
        let bouncy = Spring(duration: 0.5, bounce: 0.3)
        var previous = 0.0
        var peak = 0.0
        for step in 0...200 {
            let t = Double(step) / 200
            let value = critical.progress(at: t)
            #expect(value >= previous - 1e-12, "critical spring went back at \(t)")
            #expect(value <= 1 + 1e-12)
            previous = value
            peak = max(peak, bouncy.progress(at: t))
        }
        #expect(peak > 1.03, "bounce 0.3 peaked at \(peak)")
        // The last frame closes at most the 0.1% the settling duration allows.
        // 最後一幀補上的，最多是 settling duration 容許的 0.1%。
        #expect(abs(1 - critical.progress(at: 0.999_999)) < 0.0011)
        #expect(abs(1 - bouncy.progress(at: 0.999_999)) < 0.0011)
    }

    @Test("Animations compare by curve, across curve types")
    func animationEquality() {
        #expect(Animation.easeIn(duration: 1) == .easeIn(duration: 1))
        #expect(Animation.easeIn(duration: 1) != .easeOut(duration: 1))
        #expect(
            Animation.timingCurve(.power2(.out), duration: 1)
                == .timingCurve(.power2(.out), duration: 1)
        )
        #expect(
            Animation.timingCurve(.power2(.out), duration: 1)
                != .timingCurve(.power2(.in), duration: 1)
        )
        #expect(Animation.linear(duration: 1) != .timingCurve(.power1(.in), duration: 1))
        #expect(Animation.linear(duration: 1).delay(1) != .linear(duration: 1))
    }

    @Test("Delay holds the start, in real time")
    func delay() {
        let clock = TweenClock(Animation.linear(duration: 1).delay(0.5).speed(2))
        #expect(clock.state(at: 0.4).progress == 0)
        #expect(!clock.state(at: 0.4).isFinished)
        // 0.25 s after the delay at double speed is half way.
        // 延遲結束後 0.25 秒、兩倍速，就是一半。
        #expect(abs(clock.state(at: 0.75).progress - 0.5) < 1e-12)
        #expect(clock.state(at: 1.0).isFinished)
    }

    @Test("repeatCount counts plays, and autoreverses runs every second one backwards")
    func repeats() {
        let clock = TweenClock(Animation.linear(duration: 1).repeatCount(3))
        let second = clock.state(at: 1.25)
        #expect(second.iteration == 1)
        #expect(second.isReversed)
        #expect(abs(second.progress - 0.75) < 1e-12)
        let third = clock.state(at: 2.25)
        #expect(third.iteration == 2)
        #expect(!third.isReversed)
        #expect(abs(third.progress - 0.25) < 1e-12)
        #expect(clock.state(at: 3).isFinished)
        #expect(clock.state(at: 3).progress == 1)

        let forward = TweenClock(Animation.linear(duration: 1).repeatCount(2, autoreverses: false))
        #expect(abs(forward.state(at: 1.25).progress - 0.25) < 1e-12)
    }

    @Test("repeatForever does not finish")
    func forever() {
        let clock = TweenClock(Animation.linear(duration: 1).repeatForever(autoreverses: false))
        let state = clock.state(at: 1000.5)
        #expect(!state.isFinished)
        #expect(state.iteration == 1000)
        #expect(abs(state.progress - 0.5) < 1e-9)
    }

    @Test("A spring animation lasts as long as the spring takes to settle")
    func springAnimation() {
        let animation = Animation.spring(duration: 0.5, bounce: 0.3)
        #expect(animation.duration == Spring(duration: 0.5, bounce: 0.3).settlingDuration)
        #expect(animation.duration > 0.5)
        #expect(Animation.bouncy == .spring(duration: 0.5, bounce: 0.3))
    }
}
