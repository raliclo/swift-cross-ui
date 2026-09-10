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
    public var curve: Curve

    public init(duration: Double, curve: Curve) {
        self.duration = duration
        self.curve = curve
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
}
