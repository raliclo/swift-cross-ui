import Foundation
import Testing

@testable import SwiftCrossUI

/// Tweens in flight, on a clock the test steps by hand.
///
/// The review findings of 2026-10-22 (todo.md, Now): cancelling a tween ended
/// its group before removing it, so a completion that animated the same value
/// again lost its new tween; and a tween held its state storage strongly, so a
/// `repeatForever()` outlived its view. Neither can be reached without a clock,
/// and no backend in this target has one: ``AnimationDriver/manualClock`` is
/// that clock. Each test is synchronous on the main actor, so no other test's
/// animation runs while the driver uses it.
///
/// **The tests drive ``AnimationDriver`` directly rather than assigning to a
/// `@State`.** On Linux, Swift Testing runs main-actor tests off the main thread
/// (measured 2026-10-22: `Thread.isMainThread` is false in a `@MainActor` test),
/// and `StateImpl` assigns without animating off the main thread -- the first
/// draft of these tests did that, and both completions ran at once.
///
/// 飛行中的補間，在一個由測試手動推進的時鐘上。2026-10-22 的審查發現(todo.md,Now):取消補間時先結束群組再移除，
/// 使「再次對同一個值做動畫」的 completion 失去它的新補間；以及補間強參照狀態儲存，使 `repeatForever()` 比它的 view
/// 活得久。兩者沒有時鐘都碰不到，而本目標中沒有任何 backend 有時鐘：``AnimationDriver/manualClock`` 就是那個時鐘。
/// 每個測試都在 main actor 上同步執行，因此 driver 使用它時沒有其他測試的動畫在跑。
///
/// **測試直接驅動 ``AnimationDriver``,而不是對 `@State` 賦值。**在 Linux 上,Swift Testing 在主執行緒之外執行
/// main-actor 測試(2026-10-22 實測:`@MainActor` 測試中 `Thread.isMainThread` 為 false),而 `StateImpl` 在主執行緒
/// 之外賦值時不做動畫——這些測試的第一版就是那樣寫的，結果兩個 completion 都立刻執行。
@MainActor
@Suite("Animation lifetimes")
struct AnimationLifetimeTests {
    final class TestStorage: StateStorageProtocol {
        var value: Double
        var didChange = Publisher()
        var downstreamObservation: Cancellable?

        init(_ value: Double) {
            self.value = value
        }
    }

    @MainActor
    final class Events {
        var lines: [String] = []
    }

    /// Runs `body` with the manual clock installed, and removes it afterwards.
    /// 在裝上手動時鐘的情況下執行 `body`,之後移除它。
    func withManualClock(_ body: (AnimationDriver, AnimationDriver.ManualClock) -> Void) {
        let driver = AnimationDriver.shared
        let clock = AnimationDriver.ManualClock()
        driver.manualClock = clock
        defer { driver.manualClock = nil }
        body(driver, clock)
    }

    @Test("A completion that animates the same key again keeps its tween when the first is cancelled")
    func completionSurvivesCancel() {
        withManualClock { driver, clock in
            let events = Events()
            let key = UUID()
            let first = AnimationGroup(animation: .linear(duration: 1)) {
                events.lines.append("first done")
                let second = AnimationGroup(animation: .linear(duration: 1)) {
                    events.lines.append("second done")
                }
                driver.start(key: key, animation: .linear(duration: 1), group: second) { _ in }
                second.close()
            }
            driver.start(key: key, animation: .linear(duration: 1), group: first) { _ in }
            first.close()

            clock.advance(to: 0)
            clock.advance(to: 0.5)
            #expect(driver.activeTweenCount == 1)

            // The first group's completion runs inside this cancel and starts
            // the second tween under the same key.
            // 第一個群組的 completion 在這次取消中執行，並在同一個 key 下啟動第二個補間。
            driver.cancel(key: key)
            #expect(events.lines == ["first done"])
            #expect(driver.activeTweenCount == 1)

            clock.advance(to: 1)
            clock.advance(to: 3)
            #expect(events.lines == ["first done", "second done"])
            #expect(driver.activeTweenCount == 0)
        }
    }

    @Test("A repeatForever tween ends once its state storage is gone")
    func repeatForeverEndsWithItsStorage() {
        withManualClock { driver, clock in
            let key = UUID()
            weak var released: TestStorage?
            do {
                let storage = TestStorage(0)
                released = storage
                driver.start(
                    key: key,
                    animation: .linear(duration: 1).repeatForever(),
                    group: nil,
                    apply: StateImpl<TestStorage>.tweenApply(
                        storage: storage, key: key, from: 0.0, to: 1.0
                    )
                )
            }
            clock.advance(to: 0)
            clock.advance(to: 0.25)
            #expect(released == nil)
            #expect(driver.activeTweenCount == 0)
        }
    }
}
