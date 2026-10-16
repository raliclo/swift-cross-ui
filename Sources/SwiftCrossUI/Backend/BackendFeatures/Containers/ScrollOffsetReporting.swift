extension BackendFeatures {
    /// Where a scroll container's content is scrolled to, and a call each time
    /// it moves -- what `scrollTransition`, `onScrollVisibilityChange` and
    /// `onScrollGeometryChange` (GSAP's ScrollTrigger) are driven by.
    ///
    /// **A separate protocol rather than more of ``ScrollContainers``**, so a
    /// backend outside the shipped five keeps compiling and its scroll views
    /// keep scrolling; the modifiers then draw the identity phase and say once
    /// that the backend reports no offsets. The five shipped backends --
    /// GtkBackend, WinUIBackend, AppKitBackend, UIKitBackend, AndroidBackend --
    /// all conform.
    ///
    /// **Reported by the platform, not computed**, for the reason
    /// ``WidgetGeometry`` gives: scrolling happens in the toolkit, by finger,
    /// wheel, scroll bar or keyboard, and no layout pass sees it.
    ///
    /// 捲動容器的內容捲到哪裡，以及每次移動時的一次呼叫——`scrollTransition`、`onScrollVisibilityChange`
    /// 與 `onScrollGeometryChange`(GSAP 的 ScrollTrigger)就是由它驅動。**獨立成一個協定而不是併入
    /// ``ScrollContainers``**,讓五個已發布 backend 以外的 backend 仍能編譯、其捲動視圖仍能捲動;那些
    /// modifier 會停在 identity 階段，並說一次「這個 backend 不回報位移」。五個已發布的 backend——
    /// GtkBackend、WinUIBackend、AppKitBackend、UIKitBackend、AndroidBackend——全部 conform。
    /// **由平台回報，而非計算**,理由與 ``WidgetGeometry`` 相同：捲動發生在 toolkit 裡——手指、滾輪、
    /// 捲軸或鍵盤——沒有任何一次排版看得到它。
    @MainActor
    public protocol ScrollOffsetReporting: ScrollContainers {
        /// How far the content's top-leading corner is scrolled past the
        /// viewport's top-leading corner, in the same points as layout.
        /// Positive when scrolled down or right.
        /// 內容左上角被捲過視口左上角多遠，單位與排版相同的點。往下或往右捲時為正。
        func contentOffset(ofScrollContainer scrollView: Widget) -> SIMD2<Double>

        /// Calls `handler` with the new offset whenever the content moves, by
        /// the user or by code (`ScrollViewProxy.scrollTo`); `nil` removes it.
        ///
        /// Called on every update of the scroll view, so it must replace the
        /// handler cheaply rather than add a second observer each time.
        ///
        /// 每當內容移動——不論由使用者或程式(`ScrollViewProxy.scrollTo`)——就以新的位移呼叫 `handler`;
        /// `nil` 移除它。捲動視圖每次更新都會呼叫，所以必須以低成本替換 handler,而不是每次多加一個觀察者。
        func setContentOffsetHandler(
            ofScrollContainer scrollView: Widget,
            to handler: (@MainActor (SIMD2<Double>) -> Void)?
        )
    }
}
