extension BackendFeatures {
    /// A list widget that scrolls itself, so the framework does not have to lay
    /// it out at the height of all its rows.
    ///
    /// **Additive on purpose.** A backend that
    /// does not implement this keeps the behaviour it has -- `List` reports the
    /// sum of every row's height and the window grows with the row count. That
    /// is why this is a new protocol rather than a requirement added to
    /// ``SelectableListViews``: the latter would break every backend that had
    /// not implemented it yet.
    ///
    /// **What it fixes, measured.** Without it, `testapp/P57.swift` reads the
    /// window's own height against the row count on AppKit as:
    ///
    ///     rows=10    window 1280 x 1958 px
    ///     rows=50    window 1280 x 9306 px
    ///     rows=200   window taller than the display; capture fails
    ///
    /// Without it `List` has no viewport. `createSelectableListView` builds an
    /// `NSDisabledScrollView` whose `scrollWheel` forwards to the next
    /// responder, and the framework sizes the table to its content -- so the
    /// row count sets the window size.
    ///
    /// **This protocol alone is not virtualisation.** Every row
    /// is still built and laid out; only the reported height changes. What stops
    /// growing is the window. What does not stop growing is the work done to
    /// open it. ``LazyListRows`` is the other half.
    ///
    /// 一個自己會捲動的清單 widget,如此框架就不必把它排版成「所有列的高度」。
    ///
    /// **刻意設計為附加式的。** 未實作此協定的 backend 會保留它原有的
    /// 行為——`List` 回報每一列高度的總和,而視窗會隨列數增長。這也是此處新增一個協定、而不是往
    /// ``SelectableListViews`` 加一條 requirement 的理由:後者會讓每一個尚未實作的 backend 編不過。
    ///
    /// **它修的是什麼,已量測。** 沒有它時,`testapp/P57.swift` 在 AppKit 上讀到的視窗高度對列數的關係是:
    ///
    ///     rows=10    視窗 1280 x 1958 像素
    ///     rows=50    視窗 1280 x 9306 像素
    ///     rows=200   視窗高過顯示器;擷取失敗
    ///
    /// 沒有它時 `List` 沒有視口。`createSelectableListView` 建立的是一個 `scrollWheel` 會轉交給 next responder
    /// 的 `NSDisabledScrollView`,而框架把 table 排版成它的內容大小——於是列數決定了視窗大小。
    ///
    /// **單靠本協定還不是虛擬化。** 每一列仍然會被建構、被排版;改變的只有被回報的高度。停止增長的是
    /// **視窗**;沒有停止增長的是「打開它所做的工」。另外一半是 ``LazyListRows``。
    @MainActor
    public protocol ScrollingLists: SelectableListViews {
        /// Tells the list how tall its viewport is, so it can scroll within it.
        ///
        /// The framework calls this with the height it intends to give the list,
        /// before setting the widget's size. A backend that ignores it will
        /// clip rather than scroll -- which looks like missing rows, not like an
        /// unimplemented method.
        ///
        /// 告訴這個清單它的視口有多高,好讓它在其中捲動。
        ///
        /// 框架會在設定 widget 尺寸**之前**,以「它打算給這個清單的高度」呼叫此方法。忽略它的 backend
        /// 會變成裁切而不是捲動——那看起來像是少了幾列,而不像一個未實作的方法。
        func setViewportHeight(ofSelectableListView listView: Widget, to height: Int)
    }
}
