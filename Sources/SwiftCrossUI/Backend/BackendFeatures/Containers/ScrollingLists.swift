extension BackendFeatures {
    /// A list widget that scrolls itself, so the framework does not have to lay
    /// it out at the height of all its rows.
    ///
    /// **Additive on purpose. Nothing existing has to conform.** A backend that
    /// does not implement this keeps the behaviour it has -- `List` reports the
    /// sum of every row's height and the window grows with the row count. That
    /// is what makes converting the five backends one at a time possible, and
    /// it is why this is a new protocol rather than a requirement added to
    /// ``SelectableListViews``: the latter would break four backends the moment
    /// the first one changed.
    ///
    /// **What it fixes, measured.** `testapp/P57.swift` reads the window's own
    /// height against the row count on AppKit:
    ///
    ///     rows=10    window 1280 x 1958 px
    ///     rows=50    window 1280 x 9306 px
    ///     rows=200   window taller than the display; capture fails
    ///
    /// `List` has no viewport. `createSelectableListView` built an
    /// `NSDisabledScrollView` whose `scrollWheel` forwards to the next
    /// responder, and the framework sized the table to its content -- so the
    /// row count set the window size.
    ///
    /// **This is not virtualisation yet, and the difference matters.** Every row
    /// is still built and laid out; only the reported height changes. What stops
    /// growing is the window. What does not stop growing is the work done to
    /// open it. Phase 3 of `testapp/plan/plan-list-virtualisation.md` is the
    /// other half, and it is the harder one.
    ///
    /// 一個自己會捲動的清單 widget,如此框架就不必把它排版成「所有列的高度」。
    ///
    /// **刻意設計為附加式的。沒有任何既有的東西必須實作它。** 未實作此協定的 backend 會保留它現有的
    /// 行為——`List` 回報每一列高度的總和,而視窗會隨列數增長。那正是「五個 backend 可以一次轉換一個」
    /// 的前提,也是此處新增一個協定、而不是往 ``SelectableListViews`` 加一條 requirement 的理由:
    /// 後者會在第一個 backend 改動的那一刻,同時弄壞另外四個。
    ///
    /// **它修的是什麼,已量測。** `testapp/P57.swift` 在 AppKit 上讀取視窗自身的高度對列數的關係:
    ///
    ///     rows=10    視窗 1280 x 1958 像素
    ///     rows=50    視窗 1280 x 9306 像素
    ///     rows=200   視窗高過顯示器;擷取失敗
    ///
    /// `List` 沒有視口。`createSelectableListView` 建立的是一個 `scrollWheel` 會轉交給 next responder
    /// 的 `NSDisabledScrollView`,而框架把 table 排版成它的內容大小——於是列數決定了視窗大小。
    ///
    /// **這還不是虛擬化,而那個差別很重要。** 每一列仍然會被建構、被排版;改變的只有被回報的高度。
    /// 停止增長的是**視窗**;沒有停止增長的是「打開它所做的工」。
    /// `testapp/plan/plan-list-virtualisation.md` 的 Phase 3 是另外一半,而那一半更難。
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
