/// Which frame of reference a geometry question is asked in.
///
/// ```swift
/// GeometryReader { proxy in
///     Text("\(proxy.frame(in: .global).x)")
/// }
/// ```
///
/// 一個關於幾何的問題，是以哪一個參考座標系提出的。
public enum CoordinateSpace: Equatable, Sendable {
    /// The view's own space: its origin is always zero.
    /// 這個 view 自己的空間:它的原點恆為零。
    case local

    /// The window's space.
    ///
    /// **The window, not the screen.** SwiftUI's `.global` is the window's
    /// coordinate space too, and it is also the only one of the two that every
    /// backend here can answer without a second requirement -- a widget knows
    /// its window; where that window sits on which display is a different
    /// question, and one no view has ever needed to ask.
    ///
    /// 視窗的空間。
    ///
    /// **是視窗，不是螢幕。** SwiftUI 的 `.global` 同樣是視窗的座標系;而它也是兩者之中，唯一一個
    /// 此處每個 backend 都能在不新增第二個 requirement 的情況下回答的——一個 widget 知道它的視窗，
    /// 至於那個視窗位於哪一台顯示器的哪裡，是另一個問題，而且從來沒有任何 view 需要問它。
    case global

    /// A space named by an ancestor's ``View/coordinateSpace(name:)``.
    ///
    /// Resolves to ``global`` when no ancestor carries that name. That is a
    /// deliberate choice over trapping or returning zero: a name that does not
    /// resolve is nearly always a typo or a view that moved, and a frame in
    /// window coordinates is a wrong answer somebody can see, while zero looks
    /// like a view parked in the corner.
    ///
    /// 一個由某個祖先的 ``View/coordinateSpace(name:)`` 所命名的空間。
    ///
    /// 當沒有任何祖先帶著該名稱時，它會解析為 ``global``。這是刻意選擇，而非 trap 或回傳零:一個
    /// 解析不到的名稱幾乎總是拼錯，或是某個 view 被搬走了;而「一個以視窗座標表示的 frame」是一個
    /// **看得出來**的錯誤答案，零則看起來像是一個停在角落的 view。
    case named(String)
}

extension EnvironmentValues {
    /// The origins of the coordinate spaces named by ``View/coordinateSpace(name:)``.
    ///
    /// In the environment rather than the preference channel because it flows
    /// DOWNWARD: a name is declared by an ancestor and read by a descendant.
    ///
    /// 由 ``View/coordinateSpace(name:)`` 所命名的那些座標系的原點。
    ///
    /// 放在 environment 而非 preference 通道，因為它是**向下**流動的:名稱由祖先宣告、由後代讀取。
    @Entry internal var namedCoordinateSpaces: [String: SIMD2<Int>] = [:]
}
