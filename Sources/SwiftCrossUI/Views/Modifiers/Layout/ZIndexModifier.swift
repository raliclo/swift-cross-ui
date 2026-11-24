extension View {
    /// Controls where this view is drawn among the views it overlaps.
    ///
    /// Siblings are drawn in declaration order, so in a ``ZStack`` the last
    /// child is on top. A view with a higher `zIndex` is drawn above its
    /// siblings with lower ones whatever their order, and it is also the one a
    /// click or touch reaches first, because what is on top is what is hit.
    /// Equal values keep declaration order. The default is 0.
    ///
    /// It orders a view among its siblings only -- the children of the same
    /// stack -- the way SwiftUI's does. Layout is not affected.
    ///
    /// 控制此 view 在與它重疊的 view 之間被畫在哪一層。兄弟元件依宣告順序繪製，所以在 ``ZStack`` 中
    /// 最後一個子元件在最上面。`zIndex` 較高的 view 會畫在 `zIndex` 較低的兄弟元件之上，不論順序;
    /// 它也是點擊或觸控先到達的那一個，因為在上面的就是被點到的。值相同時維持宣告順序。預設為 0。
    ///
    /// 與 SwiftUI 相同，它只在兄弟元件(同一個 stack 的子元件)之間排序。不影響排版。
    public func zIndex(_ value: Double) -> some View {
        PreferenceModifier(self) { preferences, _ in
            preferences.with(\.zIndex, value)
        }
    }
}
