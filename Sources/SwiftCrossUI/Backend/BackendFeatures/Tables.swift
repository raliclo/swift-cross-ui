extension BackendFeatures {
    /// Backend methods for tables.
    ///
    /// These are used by ``Table``.
    @MainActor
    public protocol Tables: Core {
        /// The default height of a table row excluding cell padding. This is a
        /// recommendation by the backend that SwiftCrossUI won't necessarily
        /// follow in all cases.
        var defaultTableRowContentHeight: Int { get }

        /// The default vertical padding to apply to table cells.
        ///
        /// This is the amount of padding added above and below each cell, not the
        /// total amount added along the vertical axis. It's a recommendation by the
        /// backend that SwiftCrossUI won't necessarily follow in all cases.
        var defaultTableCellVerticalPadding: Int { get }

        /// Creates an empty table.
        ///
        /// - Returns: A table.
        func createTable() -> Widget

        /// Sets the number of rows of a table.
        ///
        /// Existing rows outside of the new bounds should be deleted.
        ///
        /// - Parameters:
        ///   - table: The table to set the row count of.
        ///   - rows: The number of rows.
        func setRowCount(ofTable table: Widget, to rows: Int)

        /// Sets the labels of a table's columns. Also sets the number of columns of
        /// the table to the number of labels provided.
        ///
        /// - Parameters:
        ///   - table: The table to set the column labels of.
        ///   - labels: The column labels to set.
        ///   - environment: The current environment.
        func setColumnLabels(
            ofTable table: Widget,
            to labels: [String],
            environment: EnvironmentValues
        )

        /// Sets the contents of the table as a flat array of cells in order of and
        /// grouped by row. Also sets the height of each row's content.
        ///
        /// A nested array would have significantly more overhead, especially for
        /// large arrays.
        ///
        /// - Parameters:
        ///   - table: The table.
        ///   - cells: The widgets to fill the table with.
        ///   - rowHeights: The heights of the table's rows.
        func setCells(
            ofTable table: Widget,
            to cells: [Widget],
            withRowHeights rowHeights: [Int]
        )

        /// Sets whether the user can select a table's text and copy it.
        ///
        /// Off unless a table asks for it, with ``View/tableTextSelection(_:)``.
        /// Selection is not free: it gives cells a caret and a highlight, makes
        /// them take keyboard focus, and changes what a drag inside the table
        /// does. A table used as a read-only readout should not acquire any of
        /// that because a different table somewhere wanted copyable values.
        ///
        /// What is selectable is the text a cell draws, not the cell as an
        /// object. A cell is an arbitrary view, so a backend applies this to the
        /// text it finds and leaves everything else alone; a table of buttons
        /// gains nothing from it.
        ///
        /// A backend that cannot offer selection should do nothing. There is no
        /// sensible fallback -- refusing to draw the table would be worse than
        /// drawing it unselectable -- so this is one of the few places where
        /// silently ignoring a request is the right behaviour.
        ///
        /// - Parameters:
        ///   - table: The table.
        ///   - isSelectable: Whether the table's text can be selected and copied.
        func setTextSelectability(ofTable table: Widget, to isSelectable: Bool)

        /// Sets each column's width, or nil for a column that shares evenly.
        ///
        /// Called after ``setColumnLabels(ofTable:to:environment:)``, so the
        /// column count is already established and the array matches it.
        ///
        /// **Why this is a backend call at all, when the layout already knows.**
        /// ``Table`` computes cell widths itself and passes them down as
        /// proposed sizes, so the CONTENT is placed correctly without a backend
        /// ever hearing about widths. What it cannot place is the header row and
        /// whatever column structure the backend keeps its own copy of -- GTK's
        /// `Grid` columns, WinUI's `WinUITable` -- and a header that disagrees
        /// with the cells beneath it is the visible defect this exists to
        /// prevent.
        ///
        /// A backend with no per-column width control should do nothing, and its
        /// table keeps the even split it had before this existed. That is the
        /// same judgement `setTextSelectability` records: refusing to draw the
        /// table would be worse than drawing it evenly.
        ///
        /// 設定每一欄的寬度;nil 表示該欄平均分配。
        ///
        /// 在 ``setColumnLabels(ofTable:to:environment:)`` 之後呼叫,因此欄數已經確立,
        /// 而此陣列與之相符。
        ///
        /// **既然版面層已經知道寬度,為何還要一個 backend 呼叫。** ``Table`` 自行計算儲存格寬度並
        /// 以 proposed size 往下傳,因此**內容**的擺放不需要任何 backend 知道寬度。它擺不了的是
        /// **標題列**,以及 backend 自行保有的那份欄位結構——GTK 的 `Grid` 欄、WinUI 的 `WinUITable`
        /// ——而**標題與其下的儲存格對不齊**,正是本方法所要防止的、看得見的缺陷。
        ///
        /// 沒有逐欄寬度控制能力的 backend 應當什麼都不做,其表格維持本方法存在之前的平均分配。
        /// 那與 `setTextSelectability` 所記載的判斷相同:拒絕繪製表格,會比把它平均地畫出來更糟。
        func setColumnWidths(ofTable table: Widget, to widths: [Double?])
    }

    /// A table whose rows can be selected, and which says when the user selects
    /// one.
    ///
    /// **This is the first backend-to-VIEW channel a table has.** Every other
    /// method on ``Tables`` runs one way -- the framework tells the backend what
    /// to draw -- which is why selection could not be expressed before it: the
    /// user clicking a row is information that only the backend has.
    ///
    /// Modelled on ``SelectableListViews``, which answered the same question for
    /// lists: a handler that receives an index, and a setter that takes one, so
    /// a selection made in code and a selection made with the mouse end in the
    /// same place.
    ///
    /// **Separate from ``TableColumnSorting`` on purpose.** A backend can
    /// plausibly manage one and not the other, and a single protocol carrying
    /// both would turn "half of it works" into a claim that both do. Same
    /// reasoning as ``Containers/LazyListRows`` and
    /// ``Containers/LazyListRowLifetimes``.
    ///
    /// Conformance-checked rather than required, so a backend that does not
    /// implement it draws exactly the table it draws today.
    ///
    /// 一個列可以被選取、並且會說出使用者選了哪一列的表格。
    ///
    /// **這是表格的第一條 backend→view 通道。** ``Tables`` 上其他每一個方法都是單向的
    /// ——框架告訴 backend 要畫什麼——而那正是「選取」在此之前無法被表達的原因:
    /// **使用者點了哪一列,是只有 backend 知道的資訊**。
    ///
    /// 形狀取自 ``SelectableListViews``,它為清單回答過同一個問題:一個收索引的 handler,
    /// 加上一個收索引的 setter,好讓「程式設定的選取」與「滑鼠造成的選取」落在同一個地方。
    ///
    /// **刻意與 ``TableColumnSorting`` 分開。** 一個 backend 完全可能做得到其中一個而非另一個,
    /// 而把兩者合成一個協定,會把「只有一半能用」變成「宣稱兩者都有」。理由與
    /// ``Containers/LazyListRows`` 和 ``Containers/LazyListRowLifetimes`` 分開相同。
    ///
    /// 採 conformance 檢查而非要求實作,因此未實作它的 backend,畫出來的表格與今天完全相同。
    @MainActor
    public protocol TableSelection: Tables {
        /// Sets the action to perform when the user selects a row.
        ///
        /// Receives the selected row's index, or nil when the selection is
        /// cleared. Row indices exclude the header row: the first data row is 0,
        /// which is the same numbering ``Tables/setCells(ofTable:to:withRowHeights:)``
        /// uses.
        ///
        /// Called on every commit, so an implementation must REPLACE the stored
        /// handler rather than add one. A backend that subscribes each time ends
        /// up with one subscription per frame -- the shape this tree has hit as
        /// `began=5` on a slider and guarded against in its lazy-row containers.
        ///
        /// 設定「使用者選取某一列時」要執行的動作。
        ///
        /// 收到的是被選取列的索引,選取被清除時為 nil。列索引**不含標題列**:第一個資料列是 0,
        /// 與 ``Tables/setCells(ofTable:to:withRowHeights:)`` 的編號相同。
        ///
        /// 每次 commit 都會呼叫,因此實作必須**取代**所存的 handler,而不是再加一個。每次都重新
        /// 訂閱的 backend 會變成每幀多一個訂閱——那正是這棵樹在 slider 上撞到的 `began=5`,
        /// 也正是 lazy-row 容器所防的那個形狀。
        func setSelectionHandler(
            ofTable table: Widget,
            to action: @escaping (_ selectedRow: Int?) -> Void
        )

        /// Selects a row, or clears the selection when given nil.
        ///
        /// **Must not call the handler.** This is the framework telling the
        /// backend what the selection is, and a backend that reports it back
        /// would make every programmatic selection look like a user action --
        /// which, with a binding on the other end, is an update loop.
        ///
        /// 選取某一列;給 nil 時清除選取。
        ///
        /// **不得觸發 handler。** 這是框架在告訴 backend「選取是什麼」,而一個把它回報回去的
        /// backend,會讓每一次程式設定的選取看起來都像使用者的動作——在另一端接著 binding 的情況下,
        /// 那是一個更新迴圈。
        func setSelectedRow(ofTable table: Widget, to index: Int?)
    }

    /// A table whose column headers can be clicked to sort by, and which says
    /// when one is.
    ///
    /// **It reports, it does not sort.** The backend says which column the user
    /// clicked; the app reorders its own rows. That is not a shortcut -- a
    /// ``TableColumn`` here is a `(RowValue) -> Content` closure with no key
    /// path and no comparator, so nothing between the click and the app knows
    /// how two rows compare. SwiftUI can sort because its columns are declared
    /// with `value:`; ours cannot, and pretending otherwise would mean sorting
    /// by the rendered text.
    ///
    /// **Every header is clickable while a sort handler is installed.** There is
    /// no per-column opt-out, for the same reason: with no comparator, "this
    /// column is sortable" is a statement only the app can make, and it makes it
    /// by what it does with the callback. A column the app ignores simply does
    /// not move the rows, and the indicator follows the binding rather than the
    /// click, so it does not appear on a column nothing happened for.
    ///
    /// Separate from ``TableSelection`` because a backend may manage one and not
    /// the other; conformance-checked, so a backend without it draws the table
    /// it draws today, with headers that do nothing.
    ///
    /// 一個「標題列可被點擊以排序、並且會說出哪一欄被點」的表格。
    ///
    /// **它只回報,不排序。** backend 說出使用者點了哪一欄;由 **app** 重新排列自己的資料。
    /// 這不是偷懶——此處的 ``TableColumn`` 是一個 `(RowValue) -> Content` closure,**沒有 key path、
    /// 也沒有 comparator**,因此在「點擊」與「app」之間,沒有任何一層知道兩列該怎麼比較。
    /// SwiftUI 能排序,是因為它的欄位以 `value:` 宣告;我們的不行,而假裝可以,等於拿**算繪出來的
    /// 文字**去排序。
    ///
    /// **只要安裝了 sort handler,每一個標題都可點。** 沒有逐欄的退出選項,理由相同:在沒有
    /// comparator 的情況下,「這一欄可排序」是只有 app 說得出口的話,而它是用「對那個回呼做了什麼」
    /// 來說的。app 忽略的欄位就是不會讓列移動;而**指示符跟隨的是 binding、不是點擊**,
    /// 因此它不會出現在一個「什麼都沒發生」的欄位上。
    ///
    /// 與 ``TableSelection`` 分開,因為一個 backend 可能做得到其中一個而非另一個;採 conformance
    /// 檢查,因此沒有實作它的 backend,畫出來的仍是今天那個表格,只是標題點了沒有反應。
    @MainActor
    public protocol TableColumnSorting: Tables {
        /// Sets the action to perform when the user clicks a column header.
        ///
        /// Receives the column's index, counting from 0 in the order the labels
        /// were given to ``Tables/setColumnLabels(ofTable:to:environment:)``.
        ///
        /// Called on every commit, so an implementation must REPLACE the stored
        /// handler rather than add one.
        ///
        /// 設定「使用者點擊某個欄位標題時」要執行的動作。
        ///
        /// 收到的是該欄的索引,自 0 起算,順序與交給
        /// ``Tables/setColumnLabels(ofTable:to:environment:)`` 的 labels 相同。
        ///
        /// 每次 commit 都會呼叫,因此實作必須**取代**所存的 handler,而不是再加一個。
        func setSortHandler(
            ofTable table: Widget,
            to action: @escaping (_ column: Int) -> Void
        )

        /// Shows which column the table is sorted by, and in which direction.
        ///
        /// nil clears the indicator from every column. **Must not call the
        /// handler**, for the reason ``TableSelection/setSelectedRow(ofTable:to:)``
        /// gives: this is the framework stating the sort order, and a backend
        /// that reported it back would turn one click into an endless one.
        ///
        /// 顯示這個表格目前依哪一欄、以哪個方向排序。
        ///
        /// nil 會把指示符從所有欄位清除。**不得觸發 handler**,理由與
        /// ``TableSelection/setSelectedRow(ofTable:to:)`` 所述相同:這是框架在陳述排序狀態,
        /// 而一個把它回報回去的 backend,會把一次點擊變成永無止盡的一次。
        func setSortIndicator(
            ofTable table: Widget,
            column: Int?,
            ascending: Bool
        )
    }
}

extension BackendFeatures.Tables {
    /// Ignores the request.
    ///
    /// A default so that adding this did not break every existing `Tables`
    /// backend, and so that a backend with no notion of text selection is not
    /// forced to write an empty method to say so. The feature is opt-in at the
    /// call site, so a backend that does nothing here behaves exactly as it did
    /// before the option existed.
    public func setTextSelectability(ofTable table: Widget, to isSelectable: Bool) {}

    /// Ignores the request, leaving the table's columns evenly split.
    ///
    /// A default for the same reason as the one above: adding this must not
    /// break an existing `Tables` backend, and a backend with no per-column
    /// width control should not be made to write an empty method to say so.
    /// Nil widths already mean "share evenly", so a backend that does nothing
    /// here behaves exactly as it did before the option existed.
    ///
    /// 忽略此請求,讓表格的欄位維持平均分配。
    ///
    /// 提供預設實作的理由與上一個相同:新增這個方法不得弄壞任何既有的 `Tables` backend,
    /// 而一個沒有逐欄寬度控制能力的 backend,也不該被迫寫一個空方法來聲明這件事。
    /// nil 寬度本來就代表「平均分配」,因此在此什麼都不做的 backend,行為與本選項存在之前完全相同。
    public func setColumnWidths(ofTable table: Widget, to widths: [Double?]) {}
}
