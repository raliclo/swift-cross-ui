import CGtk

extension ListBox {
    /// Appends a widget to the end of the list box.
    public func append(_ child: Widget) {
        gtk_list_box_append(opaquePointer, child.widgetPointer)
    }

    /// Removes all rows in the list box.
    public func removeAll() {
        // gtk_list_box_remove_all was introduced in 4.12 (too late for us)
        while removeRow(at: 0) {}
    }

    /// Removes the row at the given index.
    /// - Returns: `false` if the index is out of bounds, and `true` otherwise
    ///   (indicating that a row was removed).
    @discardableResult
    public func removeRow(at index: Int) -> Bool {
        guard let row = gtk_list_box_get_row_at_index(opaquePointer, gint(index)) else {
            return false
        }

        gtk_list_box_row_set_child(row, nil)
        gtk_list_box_remove(opaquePointer, row.cast())
        return true
    }

    /// Returns `true` on success.
    @discardableResult
    public func selectRow(at index: Int) -> Bool {
        guard let row = gtk_list_box_get_row_at_index(opaquePointer, gint(index)) else {
            return false
        }
        gtk_list_box_select_row(opaquePointer, row)
        return true
    }

    public func unselectAll() {
        gtk_list_box_unselect_all(opaquePointer)
    }

    /// The index of the selected row, or `nil` when nothing is selected.
    ///
    /// The counterpart to ``selectRow(at:)``, which had no way to ask what the
    /// answer currently is. GTK returns the row widget rather than an index, and
    /// the index lives on the row.
    ///
    /// ``selectRow(at:)`` 的對應項——先前無從詢問「目前的答案是什麼」。GTK 回傳的是那一列的
    /// widget 而非索引，而索引位於該列之上。
    public var selectedRowIndex: Int? {
        guard let row = gtk_list_box_get_selected_row(opaquePointer) else { return nil }
        let index = gtk_list_box_row_get_index(row)
        return index < 0 ? nil : Int(index)
    }
}
