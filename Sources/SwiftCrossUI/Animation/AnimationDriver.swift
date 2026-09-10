import Foundation

/// Runs every animation in the process off one frame clock.
///
/// **One driver and one clock, however many animations are in flight.** The
/// backend requirement (``BackendFeatures/FrameClocks``) is app-level for the
/// same reason; fifty animating values starting fifty clocks would be fifty
/// display links on Apple platforms and fifty tick callbacks on GTK.
///
/// The clock is started when the first animation begins and stopped when the
/// last one ends, so an idle app is not woken sixty times a second to discover
/// it has nothing to do.
///
/// 以單一個 frame clock 驅動整個行程中的每一個動畫。
///
/// **不論同時有多少動畫在跑，都只有一個 driver 與一個時鐘。** backend requirement
/// (``BackendFeatures/FrameClocks``)之所以是 app 層級的，理由相同;五十個動畫中的值若各自啟動一個
/// 時鐘，在 Apple 平台上就是五十個 display link、在 GTK 上就是五十個 tick callback。
///
/// 時鐘在第一個動畫開始時啟動、在最後一個結束時停止——因此一個閒置的 app 不會每秒被叫醒六十次，
/// 只為了發現自己無事可做。
/// **Not `@MainActor`, and the reason is the call site rather than the class.**
/// The tween is started from `StateImpl`'s setter, which is a `nonmutating set`
/// on a struct and therefore nonisolated; handing a non-Sendable `@State` value
/// into a main-actor method from there is a `sending` diagnostic, and hopping to
/// the main actor to avoid it would make the assignment land after the line that
/// made it.
///
/// So the isolation is an invariant instead of an annotation, and it holds by
/// construction: ``withAnimation(_:_:)`` is `@MainActor`, so no animation can be
/// started from anywhere else, and `StateImpl` checks `Thread.isMainThread`
/// before it gets here. The clock that drives ticks is main-actor and calls back
/// on the main thread on every backend.
///
/// **不是 `@MainActor`，而理由在呼叫端、不在這個類別。** 那個補間是從 `StateImpl` 的 setter 啟動的，
/// 那是一個 struct 上的 `nonmutating set`、因而是 nonisolated 的;從那裡把一個非 Sendable 的
/// `@State` 值交給一個 main-actor 方法會產生 `sending` 診斷，而「跳到 main actor 以避開它」會讓那次
/// 賦值比「做出它的那一行」更晚落地。
///
/// 因此這裡的 isolation 是一項**不變式**、而不是一個標註，而它由構造保證成立:
/// ``withAnimation(_:_:)`` 是 `@MainActor`，所以動畫不可能從別處被啟動;而 `StateImpl` 在抵達此處
/// 之前會檢查 `Thread.isMainThread`。驅動 tick 的那個時鐘是 main-actor 的，而且在每一個 backend 上
/// 都在主執行緒回呼。
public final class AnimationDriver: @unchecked Sendable {
    public static let shared = AnimationDriver()

    /// Set once, when the app's root environment is built.
    /// 在 app 的根環境被建立時設定一次。
    @_spi(Backends) public var backend: (any BaseAppBackend)?


    private var tweens: [UUID: Tween] = [:]
    private var isRunning = false

    private struct Tween {
        var animation: Animation
        var startTime: Double?
        /// Applies the value for a progress in `0...1`, and returns nothing:
        /// what it writes to is the state box that started the animation.
        /// 對一個位於 `0...1` 的進度套用其值，且不回傳任何東西:它寫入的對象，正是啟動這個動畫的
        /// 那個 state box。
        var apply: (Double) -> Void
    }

    private init() {}

    /// Starts an animation, replacing any animation the same key already had.
    ///
    /// The key is the state box's identity, so a value that is re-animated
    /// mid-flight continues from where it is rather than running two tweens that
    /// fight over the same storage -- which is what "set it again halfway" looks
    /// like when a user drags something twice in a row.
    ///
    /// 啟動一個動畫，並取代同一個 key 上原有的任何動畫。
    ///
    /// 那個 key 是該 state box 的識別碼，因此一個「在飛行途中被重新動畫」的值，會從它當下所在之處
    /// 繼續，而不是讓兩個補間去爭奪同一份儲存——而那正是「使用者連續拖了兩次」時，「中途再設一次值」
    /// 看起來的樣子。
    func start(key: UUID, animation: Animation, apply: @escaping (Double) -> Void) {
        tweens[key] = Tween(animation: animation, startTime: nil, apply: apply)
        startClockIfNeeded()
    }

    func cancel(key: UUID) {
        tweens[key] = nil
        stopClockIfIdle()
    }

    private func startClockIfNeeded() {
        guard !isRunning, !tweens.isEmpty else { return }
        guard let clock = MainActor.assumeIsolated({ backend as? any BackendFeatures.FrameClocks })
        else {
            // No clock: every animation lands on its final value immediately.
            // Stated rather than silent -- an app whose animations do nothing
            // should be told the backend has no clock, not left to wonder.
            // 沒有時鐘:每一個動畫都立刻抵達它的終值。此處說出來、而非默默處理——一個「動畫毫無作用」
            // 的 app，應該被告知那個 backend 沒有時鐘，而不是被留在原地猜測。
            logger.warnOnce(
                "\(type(of: backend)) has no frame clock, so animations finish instantly"
            )
            finishAllImmediately()
            return
        }
        isRunning = true
        start(clock: clock)
    }

    private func start<Clock: BackendFeatures.FrameClocks>(clock: Clock) {
        MainActor.assumeIsolated {
            clock.startFrameClock { [weak self] timestamp in
                self?.tick(at: timestamp)
            }
        }
    }

    private func stopClockIfIdle() {
        guard isRunning, tweens.isEmpty else { return }
        isRunning = false
        if let clock = MainActor.assumeIsolated({ backend as? any BackendFeatures.FrameClocks }) {
            stop(clock: clock)
        }
    }

    private func stop<Clock: BackendFeatures.FrameClocks>(clock: Clock) {
        MainActor.assumeIsolated { clock.stopFrameClock() }
    }

    private func finishAllImmediately() {
        for (key, tween) in tweens {
            tween.apply(1)
            tweens[key] = nil
        }
    }

    private func tick(at timestamp: Double) {
        for (key, tween) in tweens {
            var tween = tween
            // The clock's origin is the backend's, so the first tick is what
            // defines t=0 rather than whenever `start` happened to be called.
            // Using the call time would charge the animation for the wait until
            // the next frame, which at 60 Hz is up to a sixtieth of a short
            // animation's whole duration.
            // 時鐘的原點是 backend 的，因此定義 t=0 的是**第一次 tick**，而不是「`start` 剛好在何時
            // 被呼叫」。若用呼叫的時間，等於把「等到下一幀」的那段時間算進動畫裡——在 60 Hz 之下，
            // 那對一個短動畫而言最多是它整段時長的六十分之一。
            guard let startTime = tween.startTime else {
                tween.startTime = timestamp
                tweens[key] = tween
                tween.apply(0)
                continue
            }

            let elapsed = timestamp - startTime
            if tween.animation.duration <= 0 || elapsed >= tween.animation.duration {
                tweens[key] = nil
                tween.apply(1)
            } else {
                tween.apply(tween.animation.curve.progress(at: elapsed / tween.animation.duration))
            }
        }
        stopClockIfIdle()
    }
}

/// The animation in force for the current assignment, if any.
///
/// A global rather than a parameter, because the whole point of
/// ``withAnimation(_:_:)`` is that the assignment inside it looks exactly like
/// an assignment outside it. `@TaskLocal` would be the tidier spelling and does
/// not fit: these assignments are synchronous main-actor code, and a task-local
/// read from a `nonmutating set` inside a property wrapper would have to be
/// awaited.
///
/// 目前這次賦值所適用的動畫，若有的話。
///
/// 使用全域變數而非參數，因為 ``withAnimation(_:_:)`` 的全部意義，就在於「它裡面的那個賦值，看起來
/// 與它外面的賦值一模一樣」。`@TaskLocal` 是比較整潔的寫法，而它不適用:這些賦值是同步的 main-actor
/// 程式碼，而在一個 property wrapper 的 `nonmutating set` 中讀取 task-local 會需要 await。
enum AnimationTransaction {
    /// Main-thread-only by construction; see ``AnimationDriver`` for the
    /// invariant and why it is not an annotation.
    /// 由構造保證只在主執行緒上使用;該不變式以及它為何不是一個標註，見 ``AnimationDriver``。
    nonisolated(unsafe) static var current: Animation?
}

/// Runs `body`, animating any animatable state it assigns to.
///
/// ```swift
/// withAnimation(.easeOut(duration: 0.25)) {
///     offset = 200
/// }
/// ```
///
/// State whose type does not conform to ``AnimatableValue`` is assigned at once,
/// with no animation and no warning: see that protocol for why a `Bool` has no
/// intermediate values to show.
///
/// 執行 `body`，並為其中所賦值的任何「可動畫狀態」加上動畫。
///
/// 型別未 conform ``AnimatableValue`` 的狀態會立刻被賦值，沒有動畫、也沒有警告:一個 `Bool` 為何沒有
/// 中間值可以顯示，見該協定。
@MainActor
public func withAnimation<Result>(
    _ animation: Animation = .default,
    _ body: () throws -> Result
) rethrows -> Result {
    let previous = AnimationTransaction.current
    AnimationTransaction.current = animation
    defer { AnimationTransaction.current = previous }
    return try body()
}
