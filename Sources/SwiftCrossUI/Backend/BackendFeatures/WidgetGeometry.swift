extension BackendFeatures {
    /// Where a widget sits inside its window.
    ///
    /// **The platform is the authority on this, and that is why it is a backend
    /// requirement rather than bookkeeping in the layout system.** The framework
    /// assigns every position, so it could in principle accumulate them itself
    /// -- and it would go quietly wrong the first time a modifier shifted a
    /// child in a way the accumulator did not model. Asking the widget cannot
    /// drift from where the widget actually is.
    ///
    /// The two candidate designs it was chosen over are recorded, with their
    /// costs, in `testapp/plan/plan-120-grid-and-geometry.md`.
    ///
    /// 一個 widget 在它的視窗中位於何處。
    ///
    /// **這件事的權威在平台那一側,而那正是它成為一個 backend requirement、而不是版面系統內部帳目
    /// 的原因。** 每一個位置都是框架指派的,因此原則上框架可以自己累加——而在某個 modifier 以累加器
    /// 未曾模擬的方式位移了子節點的那一刻,它就會安靜地出錯。去問那個 widget,則不可能與「那個 widget
    /// 實際在哪」產生分歧。
    ///
    /// 它勝過的另外兩個候選設計及其代價,記載於 `testapp/plan/plan-120-grid-and-geometry.md`。
    @MainActor
    public protocol WidgetGeometry: Core {
        /// The widget's top-leading corner, in its window's coordinates.
        ///
        /// Returns `nil` when the widget is not in a window yet, which is an
        /// ordinary state rather than an error: a view is laid out before it is
        /// shown. `nil` and `.zero` are kept apart on purpose -- "not placed
        /// yet" and "placed at the origin" are different answers, and collapsing
        /// them would make a `GeometryReader` at the top-left corner
        /// indistinguishable from one that has never been positioned.
        ///
        /// 這個 widget 的左上角，以其視窗的座標表示。
        ///
        /// 當該 widget 尚未位於任何視窗中時回傳 `nil`——那是一個**常態**而非錯誤:一個 view 會在
        /// 被顯示之前先被排版。`nil` 與 `.zero` 刻意分開:「尚未被放置」與「被放置在原點」是兩個
        /// 不同的答案，把它們併起來，會讓一個位於左上角的 `GeometryReader` 與一個從未被定位過的
        /// 無從分辨。
        func originInWindow(ofWidget widget: Widget) -> SIMD2<Int>?
    }
}
