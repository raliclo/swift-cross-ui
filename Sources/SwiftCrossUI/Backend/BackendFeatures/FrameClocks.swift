extension BackendFeatures {
    /// A callback that fires once per displayed frame.
    ///
    /// **The requirement animation (#28) was missing, and the reason it is a
    /// backend requirement is that nothing in the framework can invent one.**
    /// Checked 2026-09-10: `CADisplayLink`, `CVDisplayLink` and
    /// `Timer.scheduled` are zero hits across all of `Sources/`, so no backend
    /// had any per-frame signal at all. An animation needs to be told when a
    /// frame is about to be drawn; a timer that guesses will tear on one
    /// display and stutter on another.
    ///
    /// **One clock per backend, not one per widget.** GTK's is per widget
    /// (`gtk_widget_add_tick_callback`) and everyone else's is per app or per
    /// display, so a per-widget shape would force four backends to invent a
    /// widget to hang it on. The framework runs one clock and drives every
    /// animation from it, which is also what stops fifty animating views from
    /// starting fifty clocks.
    ///
    /// 一個「每顯示一幀就觸發一次」的回呼。
    ///
    /// **動畫(#28)缺的就是這個 requirement,而它之所以是 backend requirement,是因為框架裡沒有任何
    /// 東西能憑空造出一個。** 2026-09-10 查證:`CADisplayLink`、`CVDisplayLink` 與 `Timer.scheduled`
    /// 在整個 `Sources/` 是零命中,也就是說沒有任何一個 backend 有任何逐幀訊號。動畫需要被告知
    /// 「一幀即將被繪製」;一個用猜的計時器,會在某台顯示器上撕裂、在另一台上頓挫。
    ///
    /// **一個 backend 一個時鐘,而不是一個 widget 一個。** GTK 的是逐 widget 的
    /// (`gtk_widget_add_tick_callback`),其餘每一個都是逐 app 或逐顯示器;因此「逐 widget」的形狀
    /// 會逼著四個 backend 去發明一個 widget 來掛它。框架只跑一個時鐘、並以它驅動每一個動畫——那也
    /// 正是「五十個動畫中的 view 不會啟動五十個時鐘」的原因。
    @MainActor
    public protocol FrameClocks: Core {
        /// Starts calling `handler` once per frame.
        ///
        /// The parameter is a monotonic timestamp in SECONDS, and it is the
        /// backend's own clock rather than a wall clock: an animation needs
        /// elapsed time, and a wall clock steps sideways when the system time
        /// is adjusted.
        ///
        /// Starting twice replaces the handler rather than adding a second one,
        /// which is what makes the framework's "start when the first animation
        /// begins" safe to call more than once.
        ///
        /// 開始每幀呼叫一次 `handler`。
        ///
        /// 那個參數是以**秒**為單位的單調時間戳記，而且是 backend 自己的時鐘、不是牆上時鐘:動畫要的
        /// 是**經過的時間**，而牆上時鐘會在系統時間被調整時橫向跳一步。
        ///
        /// 呼叫兩次是**取代**那個 handler，而不是再加一個——那正是讓框架的「第一個動畫開始時就啟動」
        /// 可以被安全地呼叫多次的原因。
        func startFrameClock(handler: @escaping @MainActor (Double) -> Void)

        /// Stops the clock. Stopping one that is not running does nothing.
        /// 停止該時鐘。停止一個並未在運作的時鐘不會有任何作用。
        func stopFrameClock()
    }
}
