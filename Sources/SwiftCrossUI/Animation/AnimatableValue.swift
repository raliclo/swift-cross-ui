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

extension Color: AnimatableValue {
    /// Interpolates two colours when both are made of components, and assigns
    /// immediately when either is not.
    ///
    /// **The two cases are not a compromise, they are two different questions.**
    /// A `.rgb` colour has numbers and the midpoint between two of them exists.
    /// A `.system` colour has no components at all until it is resolved against
    /// an environment, and a tween inside `@State` has no environment -- so
    /// there is no midpoint to compute, only one to invent.
    ///
    /// What it does instead of inventing one is assign at once, which is exactly
    /// what a non-conforming type does. **Holding the old colour for the
    /// duration and snapping at the end was the alternative and is worse**: a
    /// delayed jump reads as a bug, while an immediate assignment reads as "this
    /// colour does not animate", which is the truth.
    ///
    /// `.adaptive` recurses, because a light/dark pair of `.rgb` colours has a
    /// midpoint on each side.
    ///
    /// 當兩端都由分量構成時做插值;當任一端不是時，立即賦值。
    ///
    /// **這兩種情況不是折衷，它們是兩個不同的問題。** 一個 `.rgb` 顏色有數字，而兩個數字之間的中點
    /// 存在。一個 `.system` 顏色在對某個環境 resolve 之前根本沒有分量，而 `@State` 裡的補間沒有環境
    /// ——因此不存在一個可以**計算**的中點，只存在一個可以**捏造**的中點。
    ///
    /// 它不去捏造，而是立即賦值——那正是一個「未 conform 的型別」所做的事。**另一個選項是「整段期間
    /// 維持舊顏色、最後才切換」，而那更糟**:一次延遲的跳變讀起來像 bug，而一次立即的賦值讀起來是
    /// 「這個顏色不做動畫」——那是事實。
    ///
    /// `.adaptive` 會遞迴，因為一對淺色/深色的 `.rgb` 在各自那一側都有中點。
    public static func interpolated(from start: Color, to end: Color, progress: Double) -> Color {
        guard
            let representation = Representation.interpolated(
                from: start.representation,
                to: end.representation,
                progress: progress
            )
        else {
            return end
        }
        return Color(
            representation: representation,
            opacityMultiplier: Double.interpolated(
                from: start.opacityMultiplier,
                to: end.opacityMultiplier,
                progress: progress
            )
        )
    }
}

extension Color.Representation {
    /// `nil` when there is nothing to interpolate, which the caller turns into
    /// an immediate assignment.
    /// 當沒有東西可以插值時為 `nil`——呼叫端會把它變成一次立即賦值。
    static func interpolated(
        from start: Self,
        to end: Self,
        progress: Double
    ) -> Self? {
        switch (start, end) {
            case (
                .rgb(let r0, let g0, let b0),
                .rgb(let r1, let g1, let b1)
            ):
                return .rgb(
                    red: Double.interpolated(from: r0, to: r1, progress: progress),
                    green: Double.interpolated(from: g0, to: g1, progress: progress),
                    blue: Double.interpolated(from: b0, to: b1, progress: progress)
                )
            case (
                .adaptive(let light0, let dark0),
                .adaptive(let light1, let dark1)
            ):
                return .adaptive(
                    light: Color.interpolated(from: light0, to: light1, progress: progress),
                    dark: Color.interpolated(from: dark0, to: dark1, progress: progress)
                )
            default:
                return nil
        }
    }
}

// ~~`Color` deliberately does NOT conform~~ -- it does now, above, and the note
// below is kept because the obstacle it describes is real and is what shaped the
// conformance: a `.system` colour still has no midpoint, and what changed is
// that a `.rgb` one was never the same question.
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
