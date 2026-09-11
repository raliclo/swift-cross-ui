import Testing

@testable import SwiftCrossUI

/// The arithmetic an animation is made of.
///
/// P66 is the other half and neither replaces the other: it measures that a real
/// state change produced 31 intermediate values over half a second on a real
/// frame clock. These pin the parts that must be exact regardless of any clock
/// -- that every curve arrives, and that a value which cannot be interpolated
/// says so by not conforming.
///
/// 構成一個動畫的那些算式。
///
/// P66 是這件事的另一半，兩者互不取代:它量到的是「一次真實的狀態改變，在一個真實的 frame clock 上，
/// 於半秒內產生了 31 個中間值」。而此處釘住的是「無論時鐘如何都必須精確」的那些部分——每一條曲線都會
/// 抵達，以及一個無法被插值的值會以「不 conform」的方式說出這件事。
@Suite("Animation")
struct AnimationTests {
    @Test("Every curve starts at 0 and arrives at 1")
    func curvesArrive() {
        for curve in [
            Animation.Curve.linear, .easeIn, .easeOut, .easeInOut,
        ] {
            #expect(curve.progress(at: 0) == 0, "\(curve) at 0")
            #expect(curve.progress(at: 1) == 1, "\(curve) at 1")
        }
    }

    @Test("Progress outside 0...1 is clamped, not extrapolated")
    func curvesClamp() {
        // A late tick past the end must not overshoot the target. Without the
        // clamp, `easeOut` at 1.2 returns 0.96 -- BELOW its value at 1.0 -- so a
        // late frame would walk the value backwards at the very end.
        // 一個晚到、已超過終點的 tick 不可以衝過目標。少了這個 clamp，`easeOut` 在 1.2 時回傳 0.96
        // ——**低於**它在 1.0 時的值——因此一個晚到的幀會在最後關頭把那個值往回走。
        for curve in [Animation.Curve.linear, .easeIn, .easeOut, .easeInOut] {
            #expect(curve.progress(at: 1.2) == 1, "\(curve) past the end")
            #expect(curve.progress(at: -0.2) == 0, "\(curve) before the start")
        }
    }

    @Test("Eased curves are monotonic")
    func curvesAreMonotonic() {
        for curve in [Animation.Curve.linear, .easeIn, .easeOut, .easeInOut] {
            var previous = -1.0
            for step in 0...100 {
                let value = curve.progress(at: Double(step) / 100)
                #expect(value >= previous, "\(curve) went backwards at \(step)%")
                previous = value
            }
        }
    }

    @Test("Doubles interpolate linearly between the two ends")
    func doublesInterpolate() {
        #expect(Double.interpolated(from: 0, to: 200, progress: 0) == 0)
        #expect(Double.interpolated(from: 0, to: 200, progress: 0.5) == 100)
        #expect(Double.interpolated(from: 0, to: 200, progress: 1) == 200)
        // Backwards too: an animation from 200 to 20 is as ordinary as one the
        // other way, and a sign error here would only show on the return trip.
        // 反向亦然:一個從 200 到 20 的動畫，與反過來的一樣尋常;而此處的正負號錯誤，只會在回程時顯現。
        #expect(Double.interpolated(from: 200, to: 20, progress: 0.5) == 110)
    }

    @Test("Ints round rather than truncate")
    func intsRound() {
        // Truncating would leave this at 0 for the first tenth of the animation
        // and reach 10 only on the final frame.
        // 若採截斷，這個值會在動畫的前十分之一維持在 0，而且直到最後一幀才抵達 10。
        #expect(Int.interpolated(from: 0, to: 10, progress: 0.05) == 1)
        #expect(Int.interpolated(from: 0, to: 10, progress: 0.94) == 9)
        #expect(Int.interpolated(from: 0, to: 10, progress: 1) == 10)
    }

    @Test("Two component colours interpolate, component by component")
    func rgbColoursInterpolate() {
        let start = Color(red: 0, green: 0, blue: 0)
        let end = Color(red: 1, green: 0.5, blue: 0)
        let middle = Color.interpolated(from: start, to: end, progress: 0.5)
        #expect(middle == Color(red: 0.5, green: 0.25, blue: 0))
        #expect(Color.interpolated(from: start, to: end, progress: 0) == start)
        #expect(Color.interpolated(from: start, to: end, progress: 1) == end)
    }

    @Test("Opacity interpolates with the components")
    func colourOpacityInterpolates() {
        let start = Color(red: 1, green: 1, blue: 1, opacity: 0)
        let end = Color(red: 1, green: 1, blue: 1, opacity: 1)
        #expect(
            Color.interpolated(from: start, to: end, progress: 0.25)
                == Color(red: 1, green: 1, blue: 1, opacity: 0.25)
        )
    }

    @Test("A system colour assigns at once rather than inventing a midpoint")
    func systemColoursDoNotInterpolate() {
        // At the halfway point it must already BE the target. Holding the old
        // colour and snapping at the end was the alternative, and a delayed jump
        // reads as a bug where an immediate assignment reads as "this does not
        // animate".
        // 在中點時它必須**已經是**目標值。另一個選項是「維持舊色、最後才切換」，而一次延遲的跳變
        // 讀起來像 bug，一次立即的賦值則讀起來是「這個不做動畫」。
        let start = Color(red: 0, green: 0, blue: 0)
        let end = Color.system(.blue)
        #expect(Color.interpolated(from: start, to: end, progress: 0.5) == end)
        #expect(Color.interpolated(from: start, to: end, progress: 0) == end)
    }

    @Test("Adaptive colours interpolate on both sides")
    func adaptiveColoursInterpolate() {
        let start = Color.adaptive(
            light: Color(red: 0, green: 0, blue: 0),
            dark: Color(red: 1, green: 1, blue: 1)
        )
        let end = Color.adaptive(
            light: Color(red: 1, green: 1, blue: 1),
            dark: Color(red: 0, green: 0, blue: 0)
        )
        let middle = Color.interpolated(from: start, to: end, progress: 0.5)
        let grey = Color(red: 0.5, green: 0.5, blue: 0.5)
        #expect(middle == Color.adaptive(light: grey, dark: grey))
    }

    @Test("A Bool is not animatable, and that is the point")
    func boolsAreNotAnimatable() {
        // The compiler settles this, and the test states it so that a future
        // conformance added for convenience has to delete a test that says why
        // it should not exist.
        // 這件事由編譯器決定，而這個測試把它寫下來——好讓日後任何「為了方便而加上的 conformance」，
        // 必須先刪掉一個「說明它為何不該存在」的測試。
        #expect(!(Bool.self is any AnimatableValue.Type))
        #expect(Double.self is any AnimatableValue.Type)
    }
}
