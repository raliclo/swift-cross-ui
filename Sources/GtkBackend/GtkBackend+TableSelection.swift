import Gtk
@_spi(Backends) import SwiftCrossUI

/// Row selection for `Gtk.Table` (#125).
///
/// **Hand-built, because this table is a `GtkGrid` and a grid has no rows.**
/// `GtkColumnView` would give selection for free, and `Sources/Gtk/Widgets/Table.swift`
/// records why this tree does not use it: the protocol hands the backend an
/// array of already-built cell widgets, and a model-driven view would mean
/// wrapping each one in a GObject for a model that hands them straight back.
///
/// So a click is hit-tested to a grid child, the child is asked which row it is
/// in, and the row's cells get a CSS class. All three steps live in `Gtk.Table`;
/// this file is only the protocol surface.
///
/// `Gtk.Table` 的列選取(#125)。
///
/// **是手工做的,因為這個表格是一個 `GtkGrid`,而 grid 沒有「列」這個東西。**
/// `GtkColumnView` 可以免費給你選取功能,而 `Sources/Gtk/Widgets/Table.swift` 記載了這棵樹為何
/// 不用它:協定交給 backend 的是一個**已建好的儲存格 widget 陣列**,而 model-driven 的元件等於
/// 要把每一個都包成 GObject,只為了餵給一個隨即原樣交還的 model。
///
/// 因此:把一次點擊命中測試到某個 grid 子元件、問那個子元件在第幾列、再把該列的儲存格加上一個
/// CSS class。這三步都在 `Gtk.Table` 裡;本檔案只是協定的介面。
extension GtkBackend: BackendFeatures.TableSelection {
    public func setSelectionHandler(
        ofTable table: Widget,
        to action: @escaping (Int?) -> Void
    ) {
        // Replaced, not added to. The protocol says this is called on every
        // commit, and `Gtk.Table` installs its gesture once regardless.
        // **取代**,不是疊加。協定寫明這個方法每次 commit 都會被呼叫,而 `Gtk.Table` 無論如何
        // 只會安裝一次 gesture。
        (table as! Gtk.Table).onRowSelected = action
    }

    public func setSelectedRow(ofTable table: Widget, to index: Int?) {
        (table as! Gtk.Table).selectRow(index)
    }
}

/// Clickable column headers for `Gtk.Table` (#125).
///
/// **The same click gesture answers both**, because `gtk_grid_query_child`
/// returns the column and the row together: row 0 is a header and anything
/// below it is a row. That is why the gesture went on the grid rather than on
/// the cells -- a per-cell gesture would have had nothing to attach to for the
/// header, whose children are plain `GtkLabel`s.
///
/// `Gtk.Table` 的可點欄位標題(#125)。
///
/// **同一個點擊 gesture 同時回答兩者**,因為 `gtk_grid_query_child` 是把欄與列**一起**回傳的:
/// 第 0 列是標題,其下則是資料列。這正是那個 gesture 掛在 grid 上、而不是掛在儲存格上的理由
/// ——逐儲存格的 gesture 在標題那一列根本無處可掛,因為那裡的子元件是單純的 `GtkLabel`。
extension GtkBackend: BackendFeatures.TableColumnSorting {
    public func setSortHandler(
        ofTable table: Widget,
        to action: @escaping (Int) -> Void
    ) {
        (table as! Gtk.Table).onColumnHeaderClicked = action
    }

    public func setSortIndicator(ofTable table: Widget, column: Int?, ascending: Bool) {
        (table as! Gtk.Table).setSortIndicator(column: column, ascending: ascending)
    }
}
