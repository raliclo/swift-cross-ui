import Testing

@testable @_spi(Backends) import SwiftCrossUI

/// A layout or colour parameter's tween (frame, padding, Color view, Shape
/// fill), without a backend. The driver has no clock here, so a started tween
/// lands on its end at once; what the tests read is the value handed back and
/// whether a frame asked for a re-layout.
///
/// 版面或顏色參數(frame、padding、Color view、Shape 填色)的補間，不需要 backend。這裡的 driver 沒有時鐘，
/// 所以啟動的補間會立刻落在終點;測試讀的是交回的值，以及某一幀是否要求了重新排版。
@MainActor
@Suite("Layout animation (frame, padding, colours)")
struct LayoutAnimationTests {
    func transaction(_ token: Int, _ animation: Animation? = .linear(duration: 1)) -> EffectTransaction {
        EffectTransaction(animation: animation, group: nil, token: .layout(token))
    }

    @Test("The first value is laid out as it is, even under an animation")
    func firstAppearance() {
        let tween = ParameterTween<Double>()
        #expect(tween.resolve(100, transaction: transaction(1)) == 100)
        #expect(tween.drawn == 100)
        #expect(!tween.isAnimating)
    }

    @Test("Without an animation a change is laid out at once")
    func noAnimation() {
        let tween = ParameterTween<Double>()
        _ = tween.resolve(100, transaction: nil)
        #expect(tween.resolve(300, transaction: nil) == 300)
        #expect(tween.drawn == 300)
    }

    @Test("Under an animation the tween ends on the new value (no clock)")
    func animated() {
        let tween = ParameterTween<Double>()
        _ = tween.resolve(100, transaction: nil)
        #expect(tween.resolve(300, transaction: transaction(1)) == 300)
        #expect(tween.drawn == 300)
        #expect(!tween.isAnimating)
    }

    @Test("Registering a tween does not re-lay out from inside the layout pass")
    func noFrameWhileStarting() {
        let tween = ParameterTween<Double>()
        var frames = 0
        tween.onFrame = { frames += 1 }
        _ = tween.resolve(100, transaction: nil)
        _ = tween.resolve(300, transaction: transaction(1))
        // Without a clock the end is applied inside `start`, which is inside
        // the layout pass that called resolve.
        // 沒有時鐘時終值在 `start` 之內套用，而那就在呼叫 resolve 的那趟排版裡。
        #expect(frames == 0)
    }

    @Test("A repeated layout pass with the same value keeps what is drawn")
    func samePass() {
        let tween = ParameterTween<Double>()
        _ = tween.resolve(100, transaction: nil)
        _ = tween.resolve(300, transaction: transaction(1))
        #expect(tween.resolve(300, transaction: transaction(1)) == 300)
        #expect(tween.resolve(300, transaction: nil) == 300)
    }

    @Test("animation(nil) makes the change at once")
    func nilAnimation() {
        let tween = ParameterTween<Double>()
        _ = tween.resolve(30, transaction: nil)
        #expect(tween.resolve(120, transaction: transaction(1, nil)) == 120)
        #expect(!tween.isAnimating)
    }

    @Test("A reset forgets the drawn value, so the next one appears as it is")
    func reset() {
        let tween = ParameterTween<Double>()
        _ = tween.resolve(100, transaction: nil)
        tween.reset()
        #expect(tween.drawn == nil)
        #expect(tween.resolve(300, transaction: transaction(1)) == 300)
        #expect(!tween.isAnimating)
    }

    @Test("A colour tweens through its components")
    func colour() {
        let blue = Color(red: 0, green: 0, blue: 1)
        let red = Color(red: 1, green: 0, blue: 0)
        #expect(
            Color.interpolated(from: blue, to: red, progress: 0.5)
                == Color(red: 0.5, green: 0, blue: 0.5)
        )
        let tween = ParameterTween<Color>()
        _ = tween.resolve(blue, transaction: nil)
        #expect(tween.resolve(red, transaction: transaction(2)) == red)
    }
}
