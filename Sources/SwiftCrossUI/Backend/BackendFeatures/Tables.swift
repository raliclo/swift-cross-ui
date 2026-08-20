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
}
