import Foundation

/// The shape of an animation's progress over its duration.
///
/// `fraction` is the share of the duration that has passed, `0...1`; the
/// result is how far the value has travelled. Every curve returns exactly `0`
/// at `0` and exactly `1` at `1`, so an animation lands on its target. Between
/// the ends a curve may leave `0...1`: ``Ease/back(_:overshoot:)``,
/// ``Ease/elastic(_:amplitude:period:)`` and an under-damped ``Spring`` pass
/// the target and come back, which is what they are for.
///
/// The built-in shapes are GSAP's eases under SwiftUI's spelling: the curve is
/// a value passed to ``Animation/timingCurve(_:duration:)``, as SwiftUI's
/// `UnitCurve` is, and GSAP's `"power2.out"` is `.power2(.out)`.
///
/// 一個動畫在其時長內的進度形狀。
///
/// `fraction` 是已經過的時長比例(`0...1`);結果是那個值走了多遠。每條曲線在 `0` 精確回傳 `0`、在 `1`
/// 精確回傳 `1`,因此動畫一定落在目標上。兩端之間，曲線可以離開 `0...1`:``Ease/back(_:overshoot:)``、
/// ``Ease/elastic(_:amplitude:period:)`` 與欠阻尼的 ``Spring`` 會衝過目標再回來——那正是它們的用途。
///
/// 內建的形狀是 GSAP 的 ease,用 SwiftUI 的寫法:曲線是一個傳給 ``Animation/timingCurve(_:duration:)``
/// 的值，如同 SwiftUI 的 `UnitCurve`;GSAP 的 `"power2.out"` 寫成 `.power2(.out)`。
public protocol TimingCurve: Sendable, Equatable {
    func progress(at fraction: Double) -> Double
}

extension TimingCurve {
    /// Equality across curve types, for ``Animation``'s `==`: two curves of
    /// different types are different curves.
    /// 跨曲線型別的相等比較，供 ``Animation`` 的 `==` 使用:型別不同的兩條曲線就是不同的曲線。
    func isEqual(to other: any TimingCurve) -> Bool {
        (other as? Self) == self
    }
}

extension Animation.Curve: TimingCurve {}

/// GSAP's named eases. Each shape is defined once, as its `in` form; `out` is
/// that form played backwards and `inOut` is the two halves joined, as GSAP
/// builds them, so the three directions cannot drift apart.
///
/// GSAP 的具名 ease。每種形狀只定義一次(它的 `in` 形式);`out` 是倒著播放的 `in`,`inOut` 是兩半
/// 接起來——與 GSAP 的建構方式相同，因此三個方向不會彼此走樣。
public struct Ease: TimingCurve {
    public enum Shape: Equatable, Sendable {
        /// `t^(n+1)`: power1 is quad, power2 cubic, power3 quart, power4 quint.
        /// `t^(n+1)`:power1 是 quad、power2 是 cubic、power3 是 quart、power4 是 quint。
        case power(Int)
        case sine
        case expo
        case circ
        case back(overshoot: Double)
        case elastic(amplitude: Double, period: Double)
        case bounce
    }

    public enum Direction: Equatable, Sendable {
        case `in`
        case out
        case inOut
    }

    public var shape: Shape
    public var direction: Direction

    public init(_ shape: Shape, _ direction: Direction) {
        self.shape = shape
        self.direction = direction
    }

    public func progress(at fraction: Double) -> Double {
        let t = min(max(fraction, 0), 1)
        if t == 0 || t == 1 {
            return t
        }
        switch direction {
            case .in:
                return easeIn(t)
            case .out:
                return 1 - easeIn(1 - t)
            case .inOut:
                return t < 0.5 ? easeIn(2 * t) / 2 : 1 - easeIn(2 - 2 * t) / 2
        }
    }

    private func easeIn(_ t: Double) -> Double {
        switch shape {
            case .power(let n):
                return pow(t, Double(max(n, 0) + 1))
            case .sine:
                return 1 - cos(t * .pi / 2)
            case .expo:
                return pow(2, 10 * (t - 1))
            case .circ:
                return 1 - (1 - t * t).squareRoot()
            case .back(let s):
                return t * t * ((s + 1) * t - s)
            case .elastic(let amplitude, let period):
                return 1 - Self.elasticOut(1 - t, amplitude: amplitude, period: period)
            case .bounce:
                return 1 - Self.bounceOut(1 - t)
        }
    }

    /// GSAP's `elastic.out`: an amplitude below 1 is raised to 1 and stretches
    /// the period instead, as GSAP does.
    /// GSAP 的 `elastic.out`:小於 1 的振幅會被提高到 1、改為拉長週期，與 GSAP 相同。
    private static func elasticOut(_ t: Double, amplitude: Double, period: Double) -> Double {
        let a = max(amplitude, 1)
        let p = period / min(max(amplitude, .ulpOfOne), 1)
        let shift = p / (2 * .pi) * asin(1 / a)
        return a * pow(2, -10 * t) * sin((t - shift) * 2 * .pi / p) + 1
    }

    /// GSAP's `bounce.out`: four parabolas, each a quarter the height of the last.
    /// GSAP 的 `bounce.out`:四段拋物線，每段高度是前一段的四分之一。
    private static func bounceOut(_ t: Double) -> Double {
        let n = 7.5625
        let d = 2.75
        if t < 1 / d {
            return n * t * t
        } else if t < 2 / d {
            let u = t - 1.5 / d
            return n * u * u + 0.75
        } else if t < 2.5 / d {
            let u = t - 2.25 / d
            return n * u * u + 0.9375
        } else {
            let u = t - 2.625 / d
            return n * u * u + 0.984375
        }
    }
}

extension TimingCurve where Self == Ease {
    public static func power1(_ direction: Ease.Direction) -> Ease { Ease(.power(1), direction) }
    public static func power2(_ direction: Ease.Direction) -> Ease { Ease(.power(2), direction) }
    public static func power3(_ direction: Ease.Direction) -> Ease { Ease(.power(3), direction) }
    public static func power4(_ direction: Ease.Direction) -> Ease { Ease(.power(4), direction) }
    public static func sine(_ direction: Ease.Direction) -> Ease { Ease(.sine, direction) }
    public static func expo(_ direction: Ease.Direction) -> Ease { Ease(.expo, direction) }
    public static func circ(_ direction: Ease.Direction) -> Ease { Ease(.circ, direction) }
    public static func bounce(_ direction: Ease.Direction) -> Ease { Ease(.bounce, direction) }

    /// GSAP's default overshoot, 1.70158, passes the target by about 10%.
    /// GSAP 的預設超越量 1.70158,大約衝過目標 10%。
    public static func back(_ direction: Ease.Direction, overshoot: Double = 1.70158) -> Ease {
        Ease(.back(overshoot: overshoot), direction)
    }

    public static func elastic(
        _ direction: Ease.Direction,
        amplitude: Double = 1,
        period: Double = 0.3
    ) -> Ease {
        Ease(.elastic(amplitude: amplitude, period: period), direction)
    }
}

/// GSAP's `steps(n)` and CSS's `steps(n, jump-end)`: `n` equal jumps, the
/// first at the start of the second step, and the target only at the end.
/// GSAP 的 `steps(n)`,即 CSS 的 `steps(n, jump-end)`:`n` 次等量跳躍，第一次在第二格開始時，目標只在
/// 最後才抵達。
public struct Steps: TimingCurve {
    public var count: Int

    public init(_ count: Int) {
        self.count = max(count, 1)
    }

    public func progress(at fraction: Double) -> Double {
        let t = min(max(fraction, 0), 1)
        if t == 1 {
            return 1
        }
        return (t * Double(count)).rounded(.down) / Double(count)
    }
}

extension TimingCurve where Self == Steps {
    public static func steps(_ count: Int) -> Steps { Steps(count) }
}

/// A cubic Bézier from (0, 0) to (1, 1), as CSS's `cubic-bezier()`, SwiftUI's
/// `UnitCurve.bezier` and GSAP's CustomEase with two handles define it. The x
/// coordinates of the handles are clamped to `0...1` so that time runs one way.
/// 從 (0, 0) 到 (1, 1) 的三次 Bézier,定義與 CSS 的 `cubic-bezier()`、SwiftUI 的 `UnitCurve.bezier`
/// 以及有兩個控制點的 GSAP CustomEase 相同。控制點的 x 被限制在 `0...1`,好讓時間只往一個方向走。
public struct CubicBezier: TimingCurve {
    public var x1: Double
    public var y1: Double
    public var x2: Double
    public var y2: Double

    public init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        self.x1 = min(max(x1, 0), 1)
        self.y1 = y1
        self.x2 = min(max(x2, 0), 1)
        self.y2 = y2
    }

    public func progress(at fraction: Double) -> Double {
        let t = min(max(fraction, 0), 1)
        if t == 0 || t == 1 {
            return t
        }
        return Self.bezier(parameter(forX: t), y1, y2)
    }

    private static func bezier(_ s: Double, _ a: Double, _ b: Double) -> Double {
        let u = 1 - s
        return 3 * a * u * u * s + 3 * b * u * s * s + s * s * s
    }

    /// Newton's method from `x`, falling back to bisection where the slope is
    /// too flat for Newton to converge. x(s) is monotonic because the handles'
    /// x coordinates are in `0...1`, so bisection always finds the one root.
    /// 從 `x` 起跑的牛頓法；斜率太平、牛頓法收斂不了時退回二分法。因為控制點的 x 在 `0...1` 內，
    /// x(s) 是單調的，二分法一定找得到那唯一的根。
    private func parameter(forX x: Double) -> Double {
        var s = x
        for _ in 0..<8 {
            let error = Self.bezier(s, x1, x2) - x
            if abs(error) < 1e-7 {
                return s
            }
            let u = 1 - s
            let slope = 3 * u * u * x1 + 6 * u * s * (x2 - x1) + 3 * s * s * (1 - x2)
            if abs(slope) < 1e-6 {
                break
            }
            s -= error / slope
        }
        var low = 0.0
        var high = 1.0
        s = x
        for _ in 0..<60 {
            let value = Self.bezier(s, x1, x2)
            if abs(value - x) < 1e-7 {
                break
            }
            if value < x {
                low = s
            } else {
                high = s
            }
            s = (low + high) / 2
        }
        return s
    }
}

extension TimingCurve where Self == CubicBezier {
    public static func bezier(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double)
        -> CubicBezier
    {
        CubicBezier(x1, y1, x2, y2)
    }
}

/// A damped spring released from rest, with SwiftUI's two parameters: the
/// `response` is the period of the undamped spring in seconds, and the
/// `dampingFraction` is 1 for critical damping, below 1 to bounce.
///
/// A spring has no duration of its own; it approaches the target forever. Its
/// duration here is ``settlingDuration``, the time after which it stays within
/// 0.1% of the target, and the last frame closes that 0.1% -- the same rule
/// that makes every curve here arrive.
///
/// 一個從靜止釋放的阻尼彈簧，使用 SwiftUI 的兩個參數:`response` 是無阻尼彈簧的週期(秒),
/// `dampingFraction` 為 1 是臨界阻尼，小於 1 會彈跳。
///
/// 彈簧本身沒有時長；它永遠在逼近目標。此處它的時長是 ``settlingDuration``——此後它始終在目標的 0.1%
/// 以內——而最後一幀補上那 0.1%:與「這裡每條曲線都會抵達」是同一條規則。
public struct Spring: TimingCurve {
    public var response: Double
    public var dampingFraction: Double

    public init(response: Double = 0.5, dampingFraction: Double = 0.825) {
        self.response = max(response, 0.001)
        self.dampingFraction = max(dampingFraction, 0.01)
    }

    /// SwiftUI's `spring(duration:bounce:)` parameters: `bounce` 0 is
    /// critically damped, positive bounces, negative is over-damped.
    /// SwiftUI `spring(duration:bounce:)` 的參數:`bounce` 為 0 是臨界阻尼，正值會彈跳，負值是過阻尼。
    public init(duration: Double, bounce: Double) {
        self.init(
            response: duration,
            dampingFraction: bounce >= 0 ? 1 - bounce : 1 / (1 + max(bounce, -0.99))
        )
    }

    var omega: Double { 2 * .pi / response }

    /// Where a spring at its target and given a velocity of 1 is `time`
    /// seconds later: the displacement a start velocity adds, per unit of it.
    /// 一個位於目標、獲得速度 1 的彈簧在 `time` 秒後的位置：起始速度每單位所增加的位移。
    func displacementPerUnitVelocity(at time: Double) -> Double {
        let zeta = dampingFraction
        let w = omega
        if zeta < 1 {
            let wd = w * (1 - zeta * zeta).squareRoot()
            return exp(-zeta * w * time) * sin(wd * time) / wd
        } else if zeta == 1 {
            return time * exp(-w * time)
        } else {
            let root = (zeta * zeta - 1).squareRoot()
            let r1 = -w * (zeta - root)
            let r2 = -w * (zeta + root)
            return (exp(r1 * time) - exp(r2 * time)) / (r1 - r2)
        }
    }

    /// The rate of ``displacementPerUnitVelocity(at:)``: that spring's
    /// velocity at `time`.
    /// ``displacementPerUnitVelocity(at:)`` 的變化率：那個彈簧在 `time` 時的速度。
    func velocityPerUnitVelocity(at time: Double) -> Double {
        let zeta = dampingFraction
        let w = omega
        if zeta < 1 {
            let wd = w * (1 - zeta * zeta).squareRoot()
            return exp(-zeta * w * time) * (cos(wd * time) - zeta * w / wd * sin(wd * time))
        } else if zeta == 1 {
            return exp(-w * time) * (1 - w * time)
        } else {
            let root = (zeta * zeta - 1).squareRoot()
            let r1 = -w * (zeta - root)
            let r2 = -w * (zeta + root)
            return (r1 * exp(r1 * time) - r2 * exp(r2 * time)) / (r1 - r2)
        }
    }

    /// The rate of ``remaining(at:)``: `-omega^2` times
    /// ``displacementPerUnitVelocity(at:)``, as both solve the same equation.
    /// ``remaining(at:)`` 的變化率:`-omega^2` 乘以 ``displacementPerUnitVelocity(at:)``,因為兩者解的是同一個方程式。
    func remainingRate(at time: Double) -> Double {
        -omega * omega * displacementPerUnitVelocity(at: time)
    }

    /// The distance still to go at `time` seconds, starting from 1.
    /// 在第 `time` 秒時還剩下的距離，起點為 1。
    func remaining(at time: Double) -> Double {
        let zeta = dampingFraction
        let w = omega
        if zeta < 1 {
            let wd = w * (1 - zeta * zeta).squareRoot()
            return exp(-zeta * w * time) * (cos(wd * time) + zeta * w / wd * sin(wd * time))
        } else if zeta == 1 {
            return exp(-w * time) * (1 + w * time)
        } else {
            let root = (zeta * zeta - 1).squareRoot()
            let r1 = -w * (zeta - root)
            let r2 = -w * (zeta + root)
            return (r2 * exp(r1 * time) - r1 * exp(r2 * time)) / (r2 - r1)
        }
    }

    /// Seconds until the spring stays within 0.1% of the target. Under-damped,
    /// from the decay envelope; otherwise the approach is monotonic and is
    /// bisected.
    /// 彈簧從此始終在目標 0.1% 以內所需的秒數。欠阻尼時由衰減包絡線求得；否則逼近是單調的，用二分法。
    public var settlingDuration: Double {
        let zeta = dampingFraction
        let w = omega
        if zeta < 1 {
            return log(1000 / (1 - zeta * zeta).squareRoot()) / (zeta * w)
        }
        var low = 0.0
        var high = response
        while abs(remaining(at: high)) >= 0.001 {
            high *= 2
        }
        for _ in 0..<50 {
            let middle = (low + high) / 2
            if abs(remaining(at: middle)) >= 0.001 {
                low = middle
            } else {
                high = middle
            }
        }
        return high
    }

    public func progress(at fraction: Double) -> Double {
        let t = min(max(fraction, 0), 1)
        if t == 1 {
            return 1
        }
        return 1 - remaining(at: t * settlingDuration)
    }
}

extension TimingCurve where Self == Spring {
    public static func spring(response: Double = 0.5, dampingFraction: Double = 0.825) -> Spring {
        Spring(response: response, dampingFraction: dampingFraction)
    }
}
