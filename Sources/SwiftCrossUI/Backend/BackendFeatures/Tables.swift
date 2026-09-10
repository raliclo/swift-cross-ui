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
