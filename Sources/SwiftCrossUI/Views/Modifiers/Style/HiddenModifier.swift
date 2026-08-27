extension View {
    /// Hides this view while it keeps its place in the layout.
    ///
    /// The space stays reserved and everything around it stays where it was.
    /// That is the whole point, and the difference from simply not building the
    /// view: `if condition { thing }` collapses the layout, `.hidden()` does
    /// not.
    ///
    /// Also stops taking pointer events, which SwiftUI does too and which is
    /// easy to leave out. An invisible view that still swallows clicks is worse
    /// than either a visible one or an absent one, because nothing on screen
    /// explains why the thing underneath stopped responding.
    ///
    /// Composed from ``View/opacity(_:)`` and ``View/allowsHitTesting(_:)``
    /// rather than given a protocol of its own, so it works on every backend
    /// that has those two and nothing new has to be implemented anywhere.
    ///
    /// 隱藏此 view，同時讓它保留在版面中的位置。
    ///
    /// 其所佔空間仍被保留，周圍的一切也維持原位。這正是重點所在，也是它與「乾脆不建立該 view」的
    /// 差別：`if condition { thing }` 會使版面塌陷，`.hidden()` 不會。
    ///
    /// 它同時會停止接收指標事件——SwiftUI 亦然，而這一點很容易被遺漏。一個看不見卻仍會吞掉點擊的
    /// view，比「看得見」或「不存在」都更糟，因為畫面上沒有任何東西能解釋它下方的元件為何失去反應。
    ///
    /// 此處由 ``View/opacity(_:)`` 與 ``View/allowsHitTesting(_:)`` 組合而成，而非另立 protocol，
    /// 因此凡具備這兩者的 backend 都能運作，任何地方都無須新增實作。
    public func hidden() -> some View {
        opacity(0).allowsHitTesting(false)
    }
}
