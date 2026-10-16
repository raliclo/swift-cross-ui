import Testing

@testable import SwiftCrossUI

/// GSAP's callbacks, `withAnimation`'s completion and `stagger`, without a
/// frame clock: the group is fed the states the driver would feed it.
///
/// GSAP 的回呼、`withAnimation` 的 completion 與 `stagger`,不需要 frame clock:直接把 driver 會餵給群組的狀態
/// 餵給它。
@MainActor
@Suite("Animation callbacks and stagger")
struct AnimationCallbackTests {
    /// Main-actor storage the callbacks can write to.
    /// 讓回呼寫入的 main-actor 儲存。
    @MainActor
    final class Events {
        var lines: [String] = []
    }

    func state(_ progress: Double, iteration: Int = 0, waiting: Bool = false, finished: Bool = false)
        -> TweenClock.State
    {
        TweenClock.State(
            progress: progress,
            iteration: iteration,
            isReversed: false,
            isFinished: finished,
            isWaiting: waiting
        )
    }

    @Test("onStart once after the delay, onRepeat per new play, onUpdate once per frame")
    func callbacks() {
        let events = Events()
        let animation = Animation.linear(duration: 1)
            .onStart { events.lines.append("start") }
            .onRepeat { events.lines.append("repeat \($0)") }
            .onUpdate { events.lines.append("update \($0)") }
        let group = AnimationGroup(animation: animation, completion: nil)
        group.report(state(0, waiting: true), at: 0)
        group.report(state(0.25), at: 1)
        // A second tween of the same group in the same frame reports nothing.
        // 同一群組的第二個補間在同一幀不回報任何東西。
        group.report(state(0.25), at: 1)
        group.report(state(0.5, iteration: 1), at: 2)
        group.report(state(1, iteration: 1, finished: true), at: 3)
        #expect(events.lines == ["start", "update 0.25", "repeat 1", "update 0.5", "update 1.0"])
    }

    @Test("Completion runs once, after the body has returned and every tween has ended")
    func completion() {
        let events = Events()
        let group = AnimationGroup(animation: .default) { events.lines.append("done") }
        group.tweenStarted()
        group.tweenStarted()
        // Both tweens end before the body returns: nothing yet.
        // 兩個補間都在 body 返回前結束:還不執行。
        group.tweenEnded()
        group.tweenEnded()
        #expect(events.lines.isEmpty)
        group.close()
        #expect(events.lines == ["done"])
        group.tweenEnded()
        #expect(events.lines == ["done"])
    }

    @Test("A body that animates nothing completes as withAnimation returns")
    func emptyBody() {
        let events = Events()
        withAnimation(.linear(duration: 1)) {
        } completion: {
            events.lines.append("done")
        }
        #expect(events.lines == ["done"])
    }

    @Test("Stagger steps follow GSAP's from")
    func staggerSteps() {
        func steps(_ origin: StaggerOrigin) -> [Double] {
            (0..<5).map { Animation.staggerSteps($0, of: 5, from: origin) }
        }
        #expect(steps(.start) == [0, 1, 2, 3, 4])
        #expect(steps(.end) == [4, 3, 2, 1, 0])
        #expect(steps(.center) == [2, 1, 0, 1, 2])
        #expect(steps(.edges) == [0, 1, 2, 1, 0])
        #expect(steps(.index(1)) == [1, 0, 1, 2, 3])
        let random = steps(.random(seed: 7))
        #expect(random.sorted() == [0, 1, 2, 3, 4])
        #expect(random == steps(.random(seed: 7)))
    }

    @Test("Stagger adds to an existing delay")
    func staggerDelay() {
        let animation = Animation.linear(duration: 1).delay(0.2).stagger(3, of: 8, each: 0.1)
        #expect(abs(animation.startDelay - 0.5) < 1e-12)
        #expect(TweenClock(animation).state(at: 0.4).isWaiting)
        #expect(!TweenClock(animation).state(at: 0.6).isWaiting)
    }
}
