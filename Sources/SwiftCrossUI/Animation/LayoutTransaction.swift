import Foundation

/// The animation a layout change is drawn with, carried from `withAnimation` to
/// the view update that applies the change.
///
/// **Why a layout change needs carrying at all.** An animatable `@State`
/// assignment inside `withAnimation` becomes a tween at once (`StateImpl`), but
/// a `Bool` or an array has no value in between, so its assignment lands
/// immediately and the views move in a LATER update -- `observeAsUIUpdater`
/// queues it and runs it on the main thread after `withAnimation` has
/// returned. By then `AnimationTransaction.current` is nil. So the assignment
/// arms this, and every update that begins within ``window`` seconds sees it
/// as ``LayoutTransaction/active``, which is what `matchedGeometryEffect`
/// reads to decide whether a moved view flies to its new place (GSAP's Flip)
/// or jumps there.
///
/// A window rather than "the next update" because updates are merged and
/// serialised per observer: the first update to run after the assignment is
/// not always the one that redraws the views it moved.
///
/// 一次版面改變所用的動畫，從 `withAnimation` 帶到套用該改變的那次 view 更新。
///
/// **為什麼版面改變需要被「帶過去」。** `withAnimation` 裡可動畫的 `@State` 賦值會立刻變成補間
/// (`StateImpl`),但 `Bool` 或陣列沒有中間值，它的賦值立刻生效，而 view 是在**之後**的一次更新裡移動
/// ——`observeAsUIUpdater` 把它排入佇列，在 `withAnimation` 返回之後才於主執行緒執行。那時
/// `AnimationTransaction.current` 已經是 nil。所以賦值會把這裡「上膛」,在 ``window`` 秒內開始的每一次
/// 更新都會看到它(``LayoutTransaction/active``),`matchedGeometryEffect` 就是靠它決定移動的 view
/// 要飛到新位置(GSAP 的 Flip)還是直接跳過去。用時間窗而不是「下一次更新」,因為更新是逐訂閱者合併、
/// 序列化的：賦值後第一個執行的更新，不一定是重畫那些被移動的 view 的那一個。
struct LayoutTransactionState {
    struct Pending {
        var animation: Animation
        /// The `withAnimation` that armed it. Its completion waits for the
        /// flips: arming holds the group open until the hold is released.
        /// 上膛它的那個 `withAnimation`。它的 completion 會等 flip 結束：上膛時讓群組保持開啟，直到釋放。
        var group: AnimationGroup?
        var armedAt: Double
        var token: Int
        var holdReleased = false
    }

    /// Seconds after arming during which a starting update still sees it.
    /// 上膛後多少秒內開始的更新仍看得到它。
    static let window = 0.3

    private(set) var armed: Pending?
    private var nextToken = 0

    /// Arms `animation`, returning what it replaced so the caller can release
    /// that one's hold.
    /// 上膛 `animation`,回傳被取代的那一個，讓呼叫端釋放它的 hold。
    mutating func arm(_ animation: Animation, group: AnimationGroup?, now: Double) -> Pending? {
        let replaced = armed
        nextToken += 1
        armed = Pending(animation: animation, group: group, armedAt: now, token: nextToken)
        return replaced
    }

    /// What an update beginning at `now` animates with, if anything.
    /// 在 `now` 開始的一次更新要用哪個動畫(若有)。
    func current(now: Double) -> Pending? {
        guard let armed, now - armed.armedAt <= Self.window else { return nil }
        return armed
    }

    /// Marks the hold released; true when it had not been, so the caller
    /// releases it now and exactly once.
    /// 標記 hold 已釋放;若先前尚未釋放則回傳 true,呼叫端此時釋放、且只釋放一次。
    mutating func releaseHold(token: Int) -> Bool {
        guard var pending = armed, pending.token == token, !pending.holdReleased else {
            return false
        }
        pending.holdReleased = true
        armed = pending
        return true
    }

    /// Ends the window for `token`; returns the pending if its hold was still held.
    /// 結束 `token` 的時間窗;若它的 hold 仍未釋放，回傳它。
    mutating func expire(token: Int) -> Pending? {
        guard let pending = armed, pending.token == token else { return nil }
        armed = nil
        return pending.holdReleased ? nil : pending
    }
}

/// The process-wide ``LayoutTransactionState``, on the main thread by the same
/// construction as ``AnimationDriver``.
/// 行程層級的 ``LayoutTransactionState``,只在主執行緒上使用，理由與 ``AnimationDriver`` 相同。
enum LayoutTransaction {
    nonisolated(unsafe) static var state = LayoutTransactionState()

    /// The transaction the update now running animates layout changes with.
    /// 目前正在執行的更新用來為版面改變加上動畫的 transaction。
    nonisolated(unsafe) static var active: LayoutTransactionState.Pending?

    static var now: Double { ProcessInfo.processInfo.systemUptime }

    /// Called for an assignment inside `withAnimation` that cannot tween.
    /// 在 `withAnimation` 內、無法補間的賦值時呼叫。
    static func arm(_ animation: Animation) {
        let group = AnimationTransaction.group
        group?.tweenStarted()
        if let replaced = state.arm(animation, group: group, now: now), !replaced.holdReleased {
            replaced.group?.tweenEnded()
        }
        guard let token = state.armed?.token else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + LayoutTransactionState.window) {
            if let expired = state.expire(token: token) {
                expired.group?.tweenEnded()
            }
        }
    }

    static func beginUpdate() {
        active = state.current(now: now)
    }

    /// The flips this update started have joined the group, so the hold can go.
    /// 這次更新啟動的 flip 已加入群組，因此可以釋放 hold。
    static func endUpdate() {
        if let active, state.releaseHold(token: active.token) {
            active.group?.tweenEnded()
        }
        active = nil
    }
}

/// Work to do once a commit has finished and every widget has its position.
///
/// A view's `commit` runs BEFORE its parent places it (`LayoutSystem` commits
/// the children, then calls `setPosition`), so a view that wants to know where
/// it landed has to ask afterwards. `GeometryReader` asks on the next turn of
/// the main loop; a flip cannot, because by then the platform may have drawn a
/// frame at the new place and the animation would start with a flash of the
/// end. So the update that `observeAsUIUpdater` runs drains this queue as soon
/// as its commit returns, inside the same turn; anything enqueued by an update
/// that did not come through there drains on the next turn.
///
/// 一次 commit 結束、每個 widget 都有了位置之後要做的事。view 的 `commit` 在父節點放置它**之前**執行
/// (`LayoutSystem` 先 commit 子節點，再呼叫 `setPosition`),所以想知道自己落在哪裡的 view 必須事後再問。
/// `GeometryReader` 在主迴圈的下一輪問;flip 不行，因為那時平台可能已經在新位置畫了一幀，動畫會以
/// 「終點閃一下」開場。因此 `observeAsUIUpdater` 執行的更新在 commit 返回後、同一輪之內立刻清空這個
/// 佇列;不是經由那裡的更新所排入的工作，則在下一輪清空。
@MainActor
enum LayoutSettleQueue {
    private static var pending: [@MainActor () -> Void] = []
    private static var drainScheduled = false

    static func enqueue<Backend: BaseAppBackend>(
        _ backend: Backend,
        _ work: @escaping @MainActor () -> Void
    ) {
        pending.append(work)
        guard !drainScheduled else { return }
        drainScheduled = true
        backend.runInMainThread {
            drainScheduled = false
            drain()
        }
    }

    static func drain() {
        // Work may enqueue more (a follower retargeted by its source), so loop.
        // 工作可能再排入更多(被來源重新瞄準的跟隨者),所以用迴圈。
        var rounds = 0
        while !pending.isEmpty, rounds < 8 {
            let works = pending
            pending = []
            for work in works {
                work()
            }
            rounds += 1
        }
    }
}
