import Foundation

/// A value an animation can produce intermediates of.
///
/// **Conformance is opt-in per type, and the types that do NOT conform matter
/// as much as the ones that do.** `withAnimation { isOpen = true }` on a `Bool`
/// cannot mean anything -- there is no value between `false` and `true` -- so a
/// `Bool` does not conform and that assignment happens at once. The alternative,
/// making everything conform and having half of them jump at the midpoint, would
/// make "did this animate?" a question about the type rather than something the
/// compiler settles.
///
/// 一個動畫能為它產出中間值的型別。
///
/// **conformance 是逐型別選擇加入的，而「不」conform 的那些型別，與 conform 的同樣重要。**
/// 對一個 `Bool` 做 `withAnimation { isOpen = true }` 不可能有任何意義——`false` 與 `true` 之間沒有
/// 任何值——因此 `Bool` 不 conform，而那個賦值會立刻生效。另一種做法是讓所有型別都 conform、而其中一半
/// 在中點跳一下，那會讓「這個有沒有動畫?」變成一個關於型別的問題，而不是一件由編譯器決定的事。
public protocol AnimatableValue {
    /// The value `progress` of the way from `start` to `end`, where `0` is
    /// `start` and `1` is `end`.
    /// 從 `start` 到 `end` 之間、進度為 `progress` 的那個值；`0` 為 `start`，`1` 為 `end`。
    static func interpolated(from start: Self, to end: Self, progress: Double) -> Self
}

extension Double: AnimatableValue {
    public static func interpolated(from start: Double, to end: Double, progress: Double) -> Double
    {
        start + (end - start) * progress
    }
}

extension Float: AnimatableValue {
    public static func interpolated(from start: Float, to end: Float, progress: Double) -> Float {
        start + (end - start) * Float(progress)
    }
}

extension Int: AnimatableValue {
    /// Rounded, not truncated.
    ///
    /// Truncation makes an animation from 0 to 10 spend the first tenth of its
    /// time on 0 and never reach 10 until the final frame, which looks like a
    /// stutter at the start and a jump at the end rather than like rounding.
    ///
    /// 採四捨五入，而非截斷。
    ///
    /// 截斷會讓一個「從 0 到 10」的動畫，把它前十分之一的時間耗在 0 上，而且直到最後一幀才抵達 10
    /// ——那看起來像是「開頭頓一下、結尾跳一下」，而不像取整。
    public static func interpolated(from start: Int, to end: Int, progress: Double) -> Int {
        Int((Double(start) + Double(end - start) * progress).rounded())
    }
}

extension SIMD2: AnimatableValue where Scalar: BinaryFloatingPoint {
    public static func interpolated(
        from start: SIMD2<Scalar>,
        to end: SIMD2<Scalar>,
        progress: Double
    ) -> SIMD2<Scalar> {
        start + (end - start) * Scalar(progress)
    }
}

// `Color` deliberately does NOT conform, and the reason is a real obstacle
// rather than a decision to make later.
//
// A `Color` here is a `Representation`, which may be a system colour whose
// components are not known until it is resolved against an environment -- and
// this tween lives inside `@State`, where there is no environment to resolve
// against. Interpolating the two representations without resolving them would
// mean inventing components for a colour that does not have any yet, and the
// wrongness would show up only under a colour scheme nobody tested.
//
// It becomes possible if resolution moves earlier, or if the tween moves into
// the view tree where an environment exists. Both are larger than this.
//
// `Color` 刻意**不** conform，而理由是一個真正的障礙，不是一個「以後再說」的決定。
//
// 此處的 `Color` 是一個 `Representation`，它可能是一個系統色——其分量在對某個環境 resolve 之前並不
// 知道;而這個補間住在 `@State` 裡面，那裡沒有任何環境可以 resolve。若不 resolve 就對兩個
// representation 插值，等於為一個「尚未擁有分量」的顏色捏造分量，而那個錯誤只會在沒有人測過的配色
// 方案下顯現。
//
// 若 resolve 的時機往前移，或這個補間移進「有環境存在」的 view 樹裡，它就變得可行。兩者都比這件事大。
