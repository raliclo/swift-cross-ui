extension BackendFeatures {
    /// A list that asks for a row when it needs one, instead of being handed
    /// every row up front.
    ///
    /// **This reverses the direction, and that is the whole feature.** Today
    /// ``SelectableListViews/setItems(ofSelectableListView:to:withRowHeights:)``
    /// takes an array: the framework builds one view-graph node per row and
    /// hands the lot over. Measured on P57 with AppKit -- 400 rows 113 MB,
    /// 10,000 rows 423 MB, about 31 KB a row -- and none of that is backend
    /// widgets, because `NSTableView` recycles cells already. It is the nodes.
    ///
    /// Every one of the five platforms already has the other direction:
    /// `tableView(_:viewFor:row:)`, `UITableViewDataSource`, `GtkListView` with
    /// a factory, `ItemsRepeater`. This protocol is how the framework reaches
    /// it.
    ///
    /// **Conformance-checked, not required**, the same way ``ScrollingLists``
    /// was, so the five backends convert one at a time and a backend that does
    /// not conform keeps exactly the behaviour it has.
    ///
    /// 一個「需要某一列時才去要它」的清單，而不是把每一列都預先交給它。
    ///
    /// **這是把方向反轉過來，而那就是這項功能的全部。** 今天的
    /// ``SelectableListViews/setItems(ofSelectableListView:to:withRowHeights:)`` 收的是一個陣列:
    /// 框架為每一列建一個 view-graph 節點，然後整批交出去。在 AppKit 上以 P57 量過——400 列 113 MB、
    /// 10,000 列 423 MB，約每列 31 KB——而其中沒有一點是 backend 的 widget，因為 `NSTableView` 本來
    /// 就回收 cell。那是那些節點。
    ///
    /// 五個平台**每一個**都已經有反方向的機制:`tableView(_:viewFor:row:)`、
    /// `UITableViewDataSource`、帶 factory 的 `GtkListView`、`ItemsRepeater`。這個協定就是框架伸手去
    /// 拿它的方式。
    ///
    /// **採 conformance 檢查而非要求實作**，與 ``ScrollingLists`` 當初相同——好讓五個 backend 一次
    /// 轉一個，而未 conform 的 backend 行為與現在完全一致。
    @MainActor
    public protocol LazyListRows: SelectableListViews {
        /// Hands the list a row count and a way to get one row.
        ///
        /// **One method rather than the three an earlier sketch had**
        /// (`setRowCount`, `setRowProvider`, `setRowRecycler`). They are never
        /// useful apart: a count without a provider is a list of blanks, and a
        /// provider without a count is never called. Passing them together also
        /// means a backend cannot observe a half-updated pair.
        ///
        /// The recycler is gone for a different reason. It was there to stop
        /// memory growing as rows are visited, and the framework does that
        /// itself now with a bounded cache -- which needs no protocol surface
        /// and works the same on every backend. See ``List``'s row cache.
        ///
        /// - Parameters:
        ///   - count: How many rows exist. The list sizes its scrollbar from
        ///     this and from `estimatedRowHeight`, without building anything.
        ///   - estimatedRowHeight: What to assume a row is worth before it has
        ///     been built. **A backend must not call `provider` just to answer a
        ///     height question**: doing so builds every row to find out how tall
        ///     the list is, which is the thing being avoided.
        ///   - provider: Called with a row index when that row is about to be
        ///     shown. Returns the row's widget and its real height, or `nil`
        ///     when the index is out of range -- which happens legitimately
        ///     while a count is shrinking.
        ///
        /// 把「列數」與「取得某一列的方式」交給這個清單。
        ///
        /// **一個方法，而不是先前草稿裡的三個**(`setRowCount`、`setRowProvider`、`setRowRecycler`)。
        /// 它們分開沒有用處:有列數而無 provider 是一份空白清單，有 provider 而無列數則永遠不會被呼叫。
        /// 一起傳遞也意味著 backend 不會觀察到「只更新了一半」的組合。
        ///
        /// 至於 recycler 消失，理由不同。它原本是為了阻止「記憶體隨著被造訪的列而成長」，而現在框架
        /// 自己以一個有上限的快取做到了——那不需要任何協定表面，而且在每個 backend 上行為相同。
        /// 見 ``List`` 的列快取。
        ///
        /// - Parameters:
        ///   - count: 共有幾列。清單以它與 `estimatedRowHeight` 決定捲軸長度，過程中不建立任何東西。
        ///   - estimatedRowHeight: 在某一列被建立之前，假設它有多高。**backend 不得為了回答高度問題
        ///     而呼叫 `provider`**:那會為了知道清單有多高而建出每一列，正是本項所要避免的事。
        ///   - provider: 當某一列即將被顯示時，以該列索引呼叫。回傳該列的 widget 與它真正的高度;
        ///     索引超出範圍時回傳 `nil`——那在列數正在縮減時是**正當**會發生的。
        func setLazyRows(
            ofSelectableListView listView: Widget,
            count: Int,
            estimatedRowHeight: Int,
            provider: @escaping (Int) -> (widget: Widget, height: Int)?
        )
    }
}
