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
    private var tickers: [UUID: (Double?) -> Bool] = [:]
    private var isRunning = false

    /// Tests only: a clock the test steps by hand, used instead of the backend's.
    ///
    /// No backend in the test target has a frame clock, so every animation there
    /// finishes the moment it starts, and nothing that happens to a tween in
    /// flight -- cancelling it, replacing it, its view going away -- can be
    /// reached. Giving DummyBackend a clock instead would change every test that
    /// relies on that instant finish. It is what lets tests reach `cancel` and
    /// `repeatForever` outliving its view.
    ///
    /// 僅供測試：由測試手動推進的時鐘，取代 backend 的時鐘。測試目標中沒有任何 backend 有 frame clock,因此那裡的
    /// 每個動畫一開始就結束，飛行中的補間會遇到的事——被取消、被取代、它的 view 消失——都測不到。改給 DummyBackend
    /// 一個時鐘，會改變所有依賴「立即結束」的測試。有了它，測試才觸及得到 `cancel` 與「`repeatForever` 比 view 活得久」
    /// 這兩種情況。
    final class ManualClock {
        fileprivate var handler: ((Double) -> Void)?

        /// Delivers one frame at `timestamp`, in seconds. / 在 `timestamp`(秒)送出一幀。
        func advance(to timestamp: Double) {
            handler?(timestamp)
        }
    }

    var manualClock: ManualClock?

    /// How many tweens are in flight, for tests. / 進行中的補間數，供測試使用。
    var activeTweenCount: Int { tweens.count }

    private struct Tween {
        var animation: Animation
        var startTime: Double?
        /// Applies the value for a progress in `0...1`, and returns nothing:
        /// what it writes to is the state box that started the animation.
        /// 對一個位於 `0...1` 的進度套用其值，且不回傳任何東西:它寫入的對象，正是啟動這個動畫的
        /// 那個 state box。
        var apply: (Double) -> Void
        /// The `withAnimation` that started it, for callbacks and completion.
        /// 啟動它的那個 `withAnimation`,用於回呼與 completion。
        var group: AnimationGroup?
        /// Called once when the tween reaches its end (not when cancelled or replaced).
        /// 補間抵達終點時呼叫一次(被取消或取代時不呼叫)。
        var finish: (() -> Void)? = nil
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
        start(key: key, animation: animation, group: AnimationTransaction.group, apply: apply)
    }

    /// The same, joining `group` rather than the current `withAnimation`'s: a
    /// flip starts in the update after its `withAnimation` has returned.
    /// 同上，但加入 `group` 而非目前這個 `withAnimation` 的群組:flip 是在它的 `withAnimation` 返回之後的
    /// 那次更新裡才啟動的。
    func start(
        key: UUID,
        animation: Animation,
        group: AnimationGroup?,
        apply: @escaping (Double) -> Void,
        finish: (() -> Void)? = nil
    ) {
        // The new tween is in place, and its group counted, before the replaced
        // tween's group is told it ended -- the same ordering as `cancel`, for
        // the same reason. It also matters when both belong to one group: ending
        // first took that group's count to zero for a moment and could run its
        // completion while the replacement was still to come.
        // 新補間就位、其群組計數之後，才告知被取代者的群組已結束——與 `cancel` 相同的順序，理由也相同。兩者屬於同一
        // 群組時這也重要：先結束會讓該群組的計數短暫歸零，可能在替代的補間尚未加入時就執行它的 completion。
        let replaced = tweens.removeValue(forKey: key)
        group?.tweenStarted()
        tweens[key] = Tween(
            animation: animation, startTime: nil, apply: apply, group: group, finish: finish
        )
        replaced?.group?.tweenEnded()
        startClockIfNeeded()
    }

    /// Calls `ticker` with every frame's timestamp until it returns false or is removed;
    /// `nil` means the backend has no clock and the ticker should finish now. What a
    /// ``TimelinePlayer`` plays on, sharing the one clock with the tweens.
    /// 以每一幀的時間戳呼叫 `ticker`,直到它回傳 false 或被移除;`nil` 代表 backend 沒有時鐘,ticker 應立刻結束。
    /// ``TimelinePlayer`` 就是靠它播放，與補間共用同一個時鐘。
    func addTicker(_ ticker: @escaping (Double?) -> Bool) -> UUID {
        let key = UUID()
        tickers[key] = ticker
        startClockIfNeeded()
        return key
    }

    func removeTicker(_ key: UUID) {
        tickers[key] = nil
        stopClockIfIdle()
    }

    /// Removes the tween BEFORE its group is told it ended. `tweenEnded` can run
    /// the `withAnimation` completion synchronously, and a completion that
    /// animates the same value again starts a new tween under this key; ending
    /// first and removing second would delete that new tween, so it would never run and its
    /// own completion would never come.
    /// 先移除補間，再告知它的群組已結束。`tweenEnded` 可能同步執行 `withAnimation` 的 completion,而一個再次對
    /// 同一個值做動畫的 completion 會在這個 key 下啟動新的補間；先結束、後移除會把那個新補間刪掉，它因而永遠不會執行，
    /// 它自己的 completion 也永遠不會來。
    func cancel(key: UUID) {
        let cancelled = tweens.removeValue(forKey: key)
        cancelled?.group?.tweenEnded()
        stopClockIfIdle()
    }

    private func startClockIfNeeded() {
        guard !isRunning, !tweens.isEmpty || !tickers.isEmpty else { return }
        if let manualClock {
            isRunning = true
            manualClock.handler = { [weak self] timestamp in self?.tick(at: timestamp) }
            return
        }
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
        guard isRunning, tweens.isEmpty, tickers.isEmpty else { return }
        isRunning = false
        if let manualClock {
            manualClock.handler = nil
            return
        }
        if let clock = MainActor.assumeIsolated({ backend as? any BackendFeatures.FrameClocks }) {
            stop(clock: clock)
        }
    }

    private func stop<Clock: BackendFeatures.FrameClocks>(clock: Clock) {
        MainActor.assumeIsolated { clock.stopFrameClock() }
    }

    private func finishAllImmediately() {
        // A ticker told there is no clock finishes where it would have ended.
        // 被告知沒有時鐘的 ticker,直接停在它本來會結束的地方。
        for (key, ticker) in tickers {
            _ = ticker(nil)
            tickers[key] = nil
        }
        for (key, tween) in tweens {
            // Removed before `finish` and the group's end, as in `cancel`: either
            // can start a tween under this key, which must survive. And skipped
            // when already gone: that start, with no clock, re-enters here and
            // finishes the snapshot's later tweens itself.
            // 與 `cancel` 相同，在 `finish` 與群組結束之前移除：兩者都可能在這個 key 下啟動補間，而那個補間必須留下。
            // 已經不在時跳過：沒有時鐘時，那次啟動會重入這裡，自己把快照中後面的補間結束掉。
            guard tweens.removeValue(forKey: key) != nil else { continue }
            tween.apply(1)
            tween.finish?()
            tween.group?.tweenEnded()
        }
    }

    private func tick(at timestamp: Double) {
        // Callbacks after EVERY tween of the frame has written, so an onUpdate
        // reads one consistent frame. Reported per tween, the first tween's
        // callback saw the others a frame behind: P100's mid-flight probe read
        // three blocks 3 points behind the fourth, one 60 Hz frame (2026-10-17).
        // GSAP's onUpdate also fires after the render.
        // 回呼在這一幀**每個**補間都寫入之後才觸發，讓 onUpdate 讀到一致的一幀。逐補間回報時，第一個補間的
        // 回呼看到的其他補間落後一幀:P100 的飛行中探針讀到三個方塊落後第四個 3 點，正好是 60 Hz 的一幀
        // (2026-10-17)。GSAP 的 onUpdate 也是在算繪之後觸發。
        var reports: [(AnimationGroup, TweenClock.State)] = []
        var ended: [AnimationGroup] = []
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
                if let group = tween.group {
                    reports.append((group, TweenClock(tween.animation).state(at: 0)))
                }
                continue
            }

            let state = TweenClock(tween.animation).state(at: timestamp - startTime)
            if state.isFinished {
                tweens[key] = nil
                tween.apply(1)
                tween.finish?()
            } else {
                tween.apply(state.progress)
            }
            if let group = tween.group {
                reports.append((group, state))
                if state.isFinished {
                    ended.append(group)
                }
            }
        }
        for (group, state) in reports {
            group.report(state, at: timestamp)
        }
        for group in ended {
            group.tweenEnded()
        }
        // Tickers after the tweens, so a timeline renders on top of a tween started in the
        // same frame, as the later of two writes to one state wins anywhere else.
        // ticker 在補間之後執行，讓 timeline 的結果蓋過同一幀啟動的補間——與其他地方「同一狀態兩次寫入，後者為準」相同。
        for (key, ticker) in tickers where !ticker(timestamp) {
            tickers[key] = nil
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
    /// The tweens the current `withAnimation` starts join this group.
    /// 目前這個 `withAnimation` 啟動的補間都加入這個群組。
    nonisolated(unsafe) static var group: AnimationGroup?
}

/// The tweens one `withAnimation` started: one timeline for GSAP's callbacks,
/// and one `completion`.
///
/// Every tween in a group has the same animation and the same first frame, so
/// the callbacks fire from whichever tween the driver reaches first in a tick
/// and are skipped for the rest of that tick. Main-thread only, by the same
/// construction as ``AnimationDriver``.
///
/// 同一個 `withAnimation` 啟動的補間：GSAP 回呼的一條時間軸，以及一個 `completion`。群組裡每個補間都有
/// 相同的動畫與相同的第一幀，所以回呼由 driver 在一次 tick 中最先處理到的那個補間觸發，同一次 tick 的其他
/// 補間略過。只在主執行緒上使用，理由與 ``AnimationDriver`` 相同。
final class AnimationGroup: @unchecked Sendable {
    private let callbacks: AnimationCallbacks
    private let completion: (@MainActor () -> Void)?
    private var live = 0
    private var isOpen = true
    private var isDone = false
    private var lastReport: Double?
    private var hasStarted = false
    private var iteration = 0

    init(animation: Animation, completion: (@MainActor () -> Void)?) {
        callbacks = animation.callbacks
        self.completion = completion
    }

    func tweenStarted() {
        live += 1
    }

    /// Finished, cancelled or replaced.
    /// 結束、取消或被取代。
    func tweenEnded() {
        live -= 1
        finishIfDone()
    }

    /// The body has returned: no more tweens can join.
    /// body 已經返回：不會再有補間加入。
    func close() {
        isOpen = false
        finishIfDone()
    }

    func report(_ state: TweenClock.State, at timestamp: Double) {
        guard lastReport != timestamp, !state.isWaiting else { return }
        lastReport = timestamp
        MainActor.assumeIsolated {
            if !hasStarted {
                hasStarted = true
                iteration = state.iteration
                callbacks.onStart?()
            } else if state.iteration != iteration {
                iteration = state.iteration
                callbacks.onRepeat?(state.iteration)
            }
            callbacks.onUpdate?(state.progress)
        }
    }

    private func finishIfDone() {
        guard !isOpen, live <= 0, !isDone else { return }
        isDone = true
        if let completion {
            MainActor.assumeIsolated { completion() }
        }
    }
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
    try runAnimationTransaction(animation, completion: nil, body)
}

/// Runs `body` as ``withAnimation(_:_:)`` does, then `completion` once, when
/// every tween the body started has finished or been replaced by a later
/// animation of the same state -- SwiftUI's iOS 17 signature, and GSAP's
/// `onComplete`.
///
/// ```swift
/// withAnimation(.bouncy) {
///     scale = 1.2
/// } completion: {
///     scale = 1
/// }
/// ```
///
/// `repeatForever` never completes. When the body animates nothing,
/// `completion` runs as `withAnimation` returns.
///
/// 與 ``withAnimation(_:_:)`` 一樣執行 `body`,然後在 body 啟動的每一個補間都結束、或被同一個狀態的新動畫
/// 取代時，執行 `completion` 一次——SwiftUI iOS 17 的寫法，也就是 GSAP 的 `onComplete`。`repeatForever`
/// 永遠不會完成。body 沒有讓任何東西動起來時,`completion` 在 `withAnimation` 返回時執行。
@MainActor
public func withAnimation<Result>(
    _ animation: Animation = .default,
    _ body: () throws -> Result,
    completion: @escaping @MainActor () -> Void
) rethrows -> Result {
    try runAnimationTransaction(animation, completion: completion, body)
}

@MainActor
private func runAnimationTransaction<Result>(
    _ animation: Animation,
    completion: (@MainActor () -> Void)?,
    _ body: () throws -> Result
) rethrows -> Result {
    let previous = (AnimationTransaction.current, AnimationTransaction.group)
    let group = AnimationGroup(animation: animation, completion: completion)
    AnimationTransaction.current = animation
    AnimationTransaction.group = group
    defer {
        AnimationTransaction.current = previous.0
        AnimationTransaction.group = previous.1
        group.close()
    }
    return try body()
}
