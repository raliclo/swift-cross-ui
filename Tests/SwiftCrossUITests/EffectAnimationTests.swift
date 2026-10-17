import Testing

@testable @_spi(Backends) import SwiftCrossUI

/// The direct path for offset, scale, rotation and opacity: an effect modifier's
/// tween, without a backend. The driver has no clock here, so a started tween
/// draws its start and lands on its end at once, and the draws are what the
/// tests read.
///
/// offset、scale、rotation 與 opacity 的直接路徑：效果 modifier 的補間，不需要 backend。這裡的 driver 沒有
/// 時鐘，所以啟動的補間會畫出起點並立刻落在終點，測試讀的是那些繪製。
@MainActor
@Suite("Effect animation (direct path)")
struct EffectAnimationTests {
    @MainActor
    final class Draws {
        var all: [GeometricEffect] = []
    }

    func offset(_ x: Double) -> GeometricEffect {
        GeometricEffect(translation: SIMD2(x, 0))
    }

    func tween(_ draws: Draws) -> EffectTween<GeometricEffect> {
        let tween = EffectTween<GeometricEffect>()
        tween.draw = { draws.all.append($0) }
        return tween
    }

    func transaction(_ token: Int) -> EffectTransaction {
        EffectTransaction(animation: .linear(duration: 1), group: nil, token: .layout(token))
    }

    @Test("Without an animation a change is drawn at once")
    func noAnimation() {
        let draws = Draws()
        let tween = tween(draws)
        tween.commit(offset(0), transaction: nil)
        tween.commit(offset(100), transaction: nil)
        #expect(draws.all == [offset(0), offset(100)])
        #expect(!tween.isAnimating)
    }

    @Test("Under an animation a change starts from what is drawn")
    func animated() {
        let draws = Draws()
        let tween = tween(draws)
        tween.commit(offset(0), transaction: nil)
        tween.commit(offset(100), transaction: transaction(1))
        // Start drawn first, then (no clock) the end.
        // 先畫起點，然後(沒有時鐘)畫終點。
        #expect(draws.all == [offset(0), offset(0), offset(100)])
        #expect(tween.drawn == offset(100))
        #expect(!tween.isAnimating)
    }

    @Test("The first appearance is drawn as it is, even under an animation")
    func firstAppearance() {
        let draws = Draws()
        let tween = tween(draws)
        tween.commit(offset(50), transaction: transaction(1))
        #expect(draws.all == [offset(50)])
    }

    @Test("One transaction starts one tween per modifier; a second change in it jumps")
    func oneTweenPerTransaction() {
        let draws = Draws()
        let tween = tween(draws)
        tween.commit(offset(0), transaction: nil)
        tween.commit(offset(100), transaction: transaction(7))
        draws.all = []
        // A Double tween's frame inside the same armed window: drawn as it is.
        // 同一個上膛時間窗內 Double 補間的一幀：照原樣畫出。
        tween.commit(offset(120), transaction: transaction(7))
        #expect(draws.all == [offset(120)])
        // A new transaction animates again.
        // 新的 transaction 會再次動畫。
        draws.all = []
        tween.commit(offset(0), transaction: transaction(8))
        #expect(draws.all == [offset(120), offset(0)])
    }

    @Test("`.animation(nil, value:)` turns animation off")
    func nilAnimation() {
        let draws = Draws()
        let tween = tween(draws)
        tween.commit(offset(0), transaction: nil)
        tween.commit(
            offset(10),
            transaction: EffectTransaction(animation: nil, group: nil, token: .value(1))
        )
        #expect(draws.all == [offset(0), offset(10)])
    }

    @Test("Geometric effects interpolate component by component")
    func geometricInterpolation() {
        let start = GeometricEffect(
            translation: SIMD2(0, 10), scale: SIMD2(1, 1), rotation: .zero
        )
        let end = GeometricEffect(
            translation: SIMD2(100, 30), scale: SIMD2(2, 3), rotation: Angle(degrees: 360)
        )
        let half = GeometricEffect.interpolated(from: start, to: end, progress: 0.5)
        #expect(half.translation == SIMD2(50, 20))
        #expect(half.scale == SIMD2(1.5, 2))
        // In radians, so a full turn goes all the way round.
        // 以弧度插值，所以一整圈會轉完整一圈。
        #expect(abs(half.rotation.degrees - 180) < 1e-9)
    }

    @Test("Visual effects interpolate opacity and the filters")
    func visualInterpolation() {
        let start = VisualEffect(opacity: 1)
        let end = VisualEffect(opacity: 0, blurRadius: 8)
        let quarter = VisualEffect.interpolated(from: start, to: end, progress: 0.25)
        #expect(quarter.opacity == 0.75)
        #expect(quarter.blurRadius == 2)
    }

    @Test("Diagnostics record the last drawn value per label")
    func diagnostics() {
        let draws = Draws()
        let tween = tween(draws)
        tween.diagnosticsLabel = "test-effect-label"
        let before = EffectAnimationDiagnostics.draws["test-effect-label"] ?? 0
        tween.commit(offset(3), transaction: nil)
        tween.commit(offset(4), transaction: nil)
        #expect(EffectAnimationDiagnostics.draws["test-effect-label"] == before + 2)
        #expect(EffectAnimationDiagnostics.geometric["test-effect-label"] == offset(4))
    }
}
