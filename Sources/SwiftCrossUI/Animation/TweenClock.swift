import Foundation

/// Where an animation is at a moment: delay, speed, repeats and reversal
/// applied to the seconds since its first frame, and the curve applied to the
/// result.
///
/// **A pure function of elapsed time, and the driver holds no other timing
/// state.** Everything ``Animation`` adds to a curve is decided here, so it is
/// tested without a frame clock, and ``AnimationDriver`` only feeds it the
/// clock's timestamps -- the same split that lets a timeline seek to any time
/// later.
///
/// 一個動畫在某一刻的位置：把延遲、速度、重複與倒播套用在「自第一幀起的秒數」上，再把曲線套用在結果上。
///
/// **它是經過時間的純函數，而 driver 不保存其他任何計時狀態。** ``Animation`` 在曲線之上加的每一樣東西都
/// 在這裡決定，因此不需要 frame clock 就能測試;``AnimationDriver`` 只負責把時鐘的時間戳餵給它——日後
/// timeline 能跳到任意時間，靠的也是同一種分工。
public struct TweenClock: Sendable {
    public struct State: Equatable, Sendable {
        /// The curve's output: `0` is the start value and `1` the target.
        /// 曲線的輸出:`0` 是起始值,`1` 是目標值。
        public var progress: Double
        /// The play in progress, counting from 0.
        /// 正在進行的是第幾次播放，從 0 起算。
        public var iteration: Int
        public var isReversed: Bool
        /// The animation is over; ``progress`` is `1`, whatever direction the
        /// last play ran, because the state holds the value that was assigned.
        /// 動畫已結束;不論最後一次往哪個方向播放,``progress`` 都是 `1`,因為狀態保存的是被賦予的那個值。
        public var isFinished: Bool
        /// Still inside the delay: nothing has moved yet, and GSAP's `onStart` has
        /// not fired.
        /// 仍在延遲之中：還沒有任何東西移動,GSAP 的 `onStart` 也還沒觸發。
        public var isWaiting: Bool
    }

    public var animation: Animation

    public init(_ animation: Animation) {
        self.animation = animation
    }

    public func state(at elapsed: Double) -> State {
        let plays = max(animation.playCount, 1)
        let finished = State(
            progress: 1,
            iteration: animation.repeatsForever ? 0 : plays - 1,
            isReversed: false,
            isFinished: true,
            isWaiting: false
        )
        guard animation.duration > 0, animation.playbackSpeed > 0 else {
            return finished
        }
        let played = max(0, elapsed - animation.startDelay) * animation.playbackSpeed
            / animation.duration
        let iteration = Int(played.rounded(.down))
        if !animation.repeatsForever && iteration >= plays {
            return finished
        }
        let fraction = played - Double(iteration)
        let isReversed = animation.autoreverses && iteration % 2 == 1
        return State(
            progress: animation.curve.progress(at: isReversed ? 1 - fraction : fraction),
            iteration: iteration,
            isReversed: isReversed,
            isFinished: false,
            isWaiting: elapsed < animation.startDelay
        )
    }
}
