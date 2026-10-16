import Foundation

/// How a value should travel from one number to another.
///
/// ```swift
/// withAnimation(.easeInOut(duration: 0.4)) {
///     offset = 200
/// }
/// ```
///
/// **What animates is the STATE, not the view tree.** SwiftUI interpolates
/// attributes anywhere in the tree through its attribute graph; this package
/// interpolates the value inside `@State`, and every view that reads it sees
/// the intermediate values and re-renders. For the common case --
/// `withAnimation { offset = 200 }` -- the two are indistinguishable. For
/// `.transition`, matched geometry, or animating a layout reflow that no single
/// value describes, they are not, and this does not do those.
///
/// That boundary is stated here rather than discovered, because an animation
/// system that silently does nothing for half the things called animations is
/// worse than one that says which half it does.
///
/// 一個值該如何從某個數字走到另一個數字。
///
/// **會動的是**狀態**，不是 view 樹。** SwiftUI 透過它的 attribute graph 對樹中任何位置的屬性做插值;
/// 本套件插值的是 `@State` 裡的那個值，而每一個讀取它的 view 都會看到中間值並重新算繪。對於常見情況
/// ——`withAnimation { offset = 200 }`——兩者無從分辨。對於 `.transition`、matched geometry，或是
/// 「動畫化一次沒有任何單一值描述得了的版面重排」，兩者並不相同，而本實作不做那些。
///
/// 這條界線在此處寫明、而不是留給人去發現;因為一個「對半數被稱為動畫的東西默默什麼都不做」的動畫
/// 系統，比一個說清楚自己做哪一半的更糟。
public struct Animation: Equatable, Sendable {
    /// The shape of the curve between the two values.
    /// 兩個值之間那條曲線的形狀。
    public enum Curve: Equatable, Sendable {
        case linear
        case easeIn
        case easeOut
        case easeInOut

        /// Maps linear progress to eased progress. Both ends are exact: `0`
        /// gives `0` and `1` gives `1` for every curve, so an animation always
        /// arrives at its target rather than near it.
        /// 把線性進度映射為緩動後的進度。兩端都是精確的:對每一條曲線，`0` 給出 `0`、`1` 給出 `1`
        /// ——因此一個動畫總是**抵達**它的目標，而不是停在它附近。
        public func progress(at fraction: Double) -> Double {
            let t = min(max(fraction, 0), 1)
            switch self {
                case .linear:
                    return t
                case .easeIn:
                    return t * t
                case .easeOut:
                    return t * (2 - t)
                case .easeInOut:
                    return t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t
            }
        }
    }

    public var duration: Double
    /// Any ``TimingCurve``: the four ``Curve`` cases, GSAP's ``Ease``s,
    /// ``Steps``, ``CubicBezier`` or a ``Spring``.
    /// 任何 ``TimingCurve``:四個 ``Curve``、GSAP 的 ``Ease``、``Steps``、``CubicBezier`` 或 ``Spring``。
    public var curve: any TimingCurve

    /// Seconds before the first frame moves, in real time: ``playbackSpeed``
    /// does not scale it, as GSAP's `timeScale` does not scale `delay`.
    /// 第一幀開始移動前的秒數，以真實時間計:``playbackSpeed`` 不縮放它，如同 GSAP 的 `timeScale`
    /// 不縮放 `delay`。
    public var startDelay: Double = 0
    /// 2 plays twice as fast. GSAP's `timeScale`.
    /// 2 代表兩倍速。即 GSAP 的 `timeScale`。
    public var playbackSpeed: Double = 1
    /// Plays of the curve, the first included -- SwiftUI's count, so
    /// `repeatCount(3)` is GSAP's `repeat: 2`.
    /// 曲線播放的次數，含第一次——SwiftUI 的算法，所以 `repeatCount(3)` 等於 GSAP 的 `repeat: 2`。
    public var playCount: Int = 1
    /// GSAP's `repeat: -1`.
    /// 即 GSAP 的 `repeat: -1`。
    public var repeatsForever = false
    /// Every second play runs backwards. GSAP's `yoyo`.
    /// 每隔一次倒著播放。即 GSAP 的 `yoyo`。
    public var autoreverses = false

    public init(duration: Double, curve: Curve) {
        self.duration = duration
        self.curve = curve
    }

    public init(duration: Double, curve: some TimingCurve) {
        self.duration = duration
        self.curve = curve
    }

    public static func == (lhs: Animation, rhs: Animation) -> Bool {
        lhs.duration == rhs.duration
            && lhs.curve.isEqual(to: rhs.curve)
            && lhs.startDelay == rhs.startDelay
            && lhs.playbackSpeed == rhs.playbackSpeed
            && lhs.playCount == rhs.playCount
            && lhs.repeatsForever == rhs.repeatsForever
            && lhs.autoreverses == rhs.autoreverses
    }

    /// 0.35 seconds, eased at both ends. The number matches SwiftUI's default
    /// so that a view ported from it does not visibly change speed.
    /// 0.35 秒，兩端緩動。這個數字與 SwiftUI 的預設相同，好讓一個從它移植過來的 view 不會出現看得見
    /// 的速度變化。
    public static let `default` = Animation(duration: 0.35, curve: .easeInOut)

    public static func linear(duration: Double = 0.35) -> Animation {
        Animation(duration: duration, curve: .linear)
    }

    public static func easeIn(duration: Double = 0.35) -> Animation {
        Animation(duration: duration, curve: .easeIn)
    }

    public static func easeOut(duration: Double = 0.35) -> Animation {
        Animation(duration: duration, curve: .easeOut)
    }

    public static func easeInOut(duration: Double = 0.35) -> Animation {
        Animation(duration: duration, curve: .easeInOut)
    }

    /// Any curve over a duration: `.timingCurve(.power2(.out), duration: 1)`
    /// is GSAP's `{ ease: "power2.out", duration: 1 }`.
    /// 任意曲線加上時長:`.timingCurve(.power2(.out), duration: 1)` 等於 GSAP 的
    /// `{ ease: "power2.out", duration: 1 }`。
    public static func timingCurve(_ curve: some TimingCurve, duration: Double = 0.35) -> Animation
    {
        Animation(duration: duration, curve: curve)
    }

    /// SwiftUI's cubic Bézier spelling, the same curve as CSS `cubic-bezier()`.
    /// SwiftUI 的三次 Bézier 寫法，與 CSS `cubic-bezier()` 是同一條曲線。
    public static func timingCurve(
        _ c0x: Double, _ c0y: Double, _ c1x: Double, _ c1y: Double,
        duration: Double = 0.35
    ) -> Animation {
        Animation(duration: duration, curve: CubicBezier(c0x, c0y, c1x, c1y))
    }

    /// A spring whose duration is its ``Spring/settlingDuration``.
    ///
    /// `blendDuration` is accepted for SwiftUI source compatibility and has no
    /// effect: SwiftUI uses it to carry velocity into a spring that replaces a
    /// running one, and a replaced animation here restarts from the current
    /// value at rest.
    ///
    /// 時長為其 ``Spring/settlingDuration`` 的彈簧。
    ///
    /// `blendDuration` 是為了與 SwiftUI 原始碼相容而接受，沒有作用:SwiftUI 用它把速度帶進「取代一個
    /// 執行中動畫」的彈簧，而此處被取代的動畫會從目前的值、以靜止狀態重新開始。
    public static func spring(
        response: Double = 0.5,
        dampingFraction: Double = 0.825,
        blendDuration: Double = 0
    ) -> Animation {
        spring(Spring(response: response, dampingFraction: dampingFraction))
    }

    /// SwiftUI's `spring(duration:bounce:)`. See ``spring(response:dampingFraction:blendDuration:)``
    /// for `blendDuration`.
    /// SwiftUI 的 `spring(duration:bounce:)`。`blendDuration` 見
    /// ``spring(response:dampingFraction:blendDuration:)``。
    public static func spring(
        duration: Double = 0.5,
        bounce: Double = 0,
        blendDuration: Double = 0
    ) -> Animation {
        spring(Spring(duration: duration, bounce: bounce))
    }

    private static func spring(_ spring: Spring) -> Animation {
        Animation(duration: spring.settlingDuration, curve: spring)
    }

    /// SwiftUI's presets: `spring` and `smooth` do not bounce, `snappy` bounces
    /// 0.15 and `bouncy` 0.3, all with a 0.5 second response.
    /// SwiftUI 的預設組:`spring` 與 `smooth` 不彈跳,`snappy` 彈跳 0.15、`bouncy` 0.3,response 皆為 0.5 秒。
    public static var spring: Animation { spring(Spring(duration: 0.5, bounce: 0)) }
    public static var smooth: Animation { smooth() }
    public static var snappy: Animation { snappy() }
    public static var bouncy: Animation { bouncy() }

    public static func smooth(duration: Double = 0.5, extraBounce: Double = 0) -> Animation {
        spring(Spring(duration: duration, bounce: extraBounce))
    }

    public static func snappy(duration: Double = 0.5, extraBounce: Double = 0) -> Animation {
        spring(Spring(duration: duration, bounce: 0.15 + extraBounce))
    }

    public static func bouncy(duration: Double = 0.5, extraBounce: Double = 0) -> Animation {
        spring(Spring(duration: duration, bounce: 0.3 + extraBounce))
    }

    /// Waits `delay` seconds before starting. Replaces an earlier delay.
    /// 開始前等待 `delay` 秒。會取代先前的延遲。
    public func delay(_ delay: Double) -> Animation {
        var animation = self
        animation.startDelay = max(delay, 0)
        return animation
    }

    /// Multiplies the playback speed, so `.speed(2).speed(2)` is four times as fast.
    /// 乘上播放速度，所以 `.speed(2).speed(2)` 是四倍速。
    public func speed(_ speed: Double) -> Animation {
        var animation = self
        animation.playbackSpeed *= speed
        return animation
    }

    /// Plays the curve `count` times. As in SwiftUI, `autoreverses` defaults to
    /// true, and the state still ends on the value that was assigned: an even
    /// count that ends on a backward play jumps to it on the last frame.
    /// 播放曲線 `count` 次。與 SwiftUI 相同,`autoreverses` 預設為 true,而狀態仍然停在被賦予的那個值:
    /// 偶數次、最後一次倒著播放時，會在最後一幀跳到那個值。
    public func repeatCount(_ count: Int, autoreverses: Bool = true) -> Animation {
        var animation = self
        animation.playCount = max(count, 1)
        animation.repeatsForever = false
        animation.autoreverses = autoreverses
        return animation
    }

    /// Plays until the state is assigned again or the animation is replaced.
    /// 一直播放，直到狀態再次被賦值或動畫被取代。
    public func repeatForever(autoreverses: Bool = true) -> Animation {
        var animation = self
        animation.repeatsForever = true
        animation.autoreverses = autoreverses
        return animation
    }
}
