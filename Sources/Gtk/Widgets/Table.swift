import CGtk
import Foundation
import GtkCHelpers

/// A scrollable grid of cells with a header row, for `BackendFeatures.Tables`.
///
/// A `GtkGrid` inside a `GtkScrolledWindow` rather than a `GtkColumnView`.
/// ColumnView is GTK's real table and would give sorting and selection for
/// free, but it is list-model driven: it wants a `GListModel` and factories that
/// produce cells on demand. SwiftCrossUI hands the backend a flat array of
/// already-built widgets and expects them placed, which is a grid's job. Going
/// through ColumnView would mean wrapping every cell widget in a GObject for a
/// model that exists only to hand them straight back.
///
/// Rebuilds on every `setCells`, matching what AppKitBackend does with
/// `reloadData`. The protocol passes the entire contents each time, so there is
/// no incremental information to exploit.
///
/// 一個帶有標題列、可捲動的儲存格網格，用於實作 `BackendFeatures.Tables`。
///
/// 採用 `GtkScrolledWindow` 內含 `GtkGrid`，而非 `GtkColumnView`。ColumnView 才是 GTK 真正的
/// 表格元件，能直接獲得排序與選取功能，但它是由 list model 驅動的：它需要一個 `GListModel`
/// 以及按需產生儲存格的 factory。而 SwiftCrossUI 交給 backend 的是一個「已建構完成的 widget」
/// 扁平陣列，只要求將其放置到位——那正是 grid 的職責。若改走 ColumnView，等於要把每一個儲存格
/// widget 包進 GObject，只為了餵給一個隨即又把它們原樣交還的 model。
///
/// 每次 `setCells` 都整份重建，與 AppKitBackend 使用 `reloadData` 的做法一致。該協定每次都傳入
/// 完整內容，因此並不存在可資利用的增量資訊。
public class Table: ScrolledWindow {
    private let grid = Grid()
    private var headerLabels: [Label] = []
    private var cellWidgets: [Widget] = []
    private var columnCount = 0
    private var rowCount = 0
    private var isTextSelectable = false

    public convenience init() {
        self.init(gtk_scrolled_window_new())
        grid.columnSpacing = 0
        grid.rowSpacing = 0
        setChild(grid)
        setScrollBarPresence(hasVerticalScrollBar: true, hasHorizontalScrollBar: true)
    }

    /// Sets the header row, and with it the column count.
    /// 設定標題列，並同時決定欄數。
    public func setColumnLabels(_ labels: [String]) {
        columnCount = labels.count

        for label in headerLabels {
            grid.remove(child: label)
        }
        headerLabels = labels.map { text in
            let label = Label(string: text)
            // Left-aligned and expanding, so a header sits over its column
            // rather than floating in the middle of it. `hexpand` on the header
            // is what gives the column its width when the cells are narrower.
            // 靠左對齊並允許擴展，使標題位於其欄位上方，而非浮在欄位中央。標題上的 `hexpand`
            // 正是在儲存格較窄時決定欄寬的依據。
            label.horizontalAlignment = .start
            label.expandHorizontally = true
            return label
        }

        for (column, label) in headerLabels.enumerated() {
            grid.attach(child: label, left: column, top: 0, width: 1, height: 1)
        }
    }

    /// Sets every cell. `cells` is row-major and its length must be
    /// `rowCount * columnCount`; anything beyond that is ignored rather than
    /// trapping, because a mismatch here means the caller and the backend
    /// disagree about the shape and a crash would say less than a short table.
    /// 設定所有儲存格。`cells` 依列優先排列，長度應為 `rowCount * columnCount`；超出的部分會被
    /// 忽略而非觸發 trap，因為此處的長度不符代表呼叫端與 backend 對表格形狀的認知不一致，
    /// 而崩潰所能提供的資訊反而不如一個內容較短的表格。
    public func setCells(_ cells: [Widget], rowHeights: [Int]) {
        for cell in cellWidgets {
            grid.remove(child: cell)
        }
        cellWidgets = cells

        guard columnCount > 0 else { return }

        for (index, cell) in cells.enumerated() {
            let row = index / columnCount
            let column = index % columnCount
            guard row < rowCount else { break }

            cell.expandHorizontally = true
            cell.horizontalAlignment = .fill
            if row < rowHeights.count {
                cell.setSizeRequest(width: -1, height: rowHeights[row])
            }

            // Row 0 is the header, so data starts at 1.
            // 第 0 列是標題，因此資料自第 1 列開始。
            grid.attach(child: cell, left: column, top: row + 1, width: 1, height: 1)
        }

        // Reapplied here, not only when the setting changes. Every `setCells`
        // replaces the widgets, so a table rebuilt after selection was turned on
        // would come back unselectable -- and P23's `More rows` rebuilds it.
        // 於此處重新套用，而非僅在設定變更時。每次 `setCells` 都會替換 widget，因此在啟用選取之後
        // 重建的表格會變回不可選取——而 P23 的 `More rows` 正是會重建它。
        applyTextSelectability()
    }

    /// Sets whether the user can select and copy the table's text.
    ///
    /// GTK offers selection on `GtkLabel`, not on a container, so this walks the
    /// cells and applies it to every label found. Cells are arbitrary widgets --
    /// SwiftCrossUI wraps each one in a container and the view inside may not be
    /// text at all -- so the walk descends rather than assuming a shape, and
    /// leaves anything that is not a label alone.
    ///
    /// The header row is included. A column title is as worth copying as a cell,
    /// and excluding it would be a distinction the caller never asked for.
    ///
    /// 設定使用者是否能選取並複製表格中的文字。
    ///
    /// GTK 的選取功能位於 `GtkLabel` 而非容器上，因此此處會走訪各儲存格，並套用至所找到的每一個
    /// label。儲存格是任意的 widget——SwiftCrossUI 會將每個儲存格包進容器，其中的 view 也未必是
    /// 文字——因此此走訪採用遞迴下降而非假設固定結構，並對非 label 的元件不做任何處理。
    ///
    /// 標題列亦包含在內。欄位標題與儲存格同樣值得複製，將其排除等於做出一個呼叫端從未要求的區分。
    public func setTextSelectable(_ isSelectable: Bool) {
        isTextSelectable = isSelectable
        applyTextSelectability()
    }

    private func applyTextSelectability() {
        for label in headerLabels {
            label.selectable = isTextSelectable
        }
        var reached = 0
        for cell in cellWidgets {
            reached += Self.setLabelsSelectable(under: cell.widgetPointer, to: isTextSelectable)
        }

        // Set SCUI_DEBUG_TABLE to see how many labels the walk actually reached.
        // Zero and "nothing is selectable" look identical on screen, and they
        // have different causes: zero means the walk never found the text, while
        // a non-zero count means it did and GTK declined.
        // 設定 SCUI_DEBUG_TABLE 可看到此走訪實際觸及了多少個 label。「0」與「沒有任何內容可選取」
        // 在畫面上看起來完全相同，但成因不同：0 代表走訪根本沒找到文字，而非 0 的計數代表找到了，
        // 是 GTK 拒絕了。
        if ProcessInfo.processInfo.environment["SCUI_DEBUG_TABLE"] != nil {
            let line =
                "table: selectable=\(isTextSelectable) cells=\(cellWidgets.count) "
                + "labels=\(reached) headers=\(headerLabels.count)\n"
            FileHandle.standardError.write(Data(line.utf8))
        }
    }

    /// Walks the GTK widget tree and sets `selectable` on every label.
    ///
    /// Through the C API rather than the Swift wrappers: the wrappers only know
    /// about widgets this package created, and a cell's contents arrive as an
    /// opaque `Widget`. `gtk_widget_get_first_child` and `get_next_sibling` see
    /// the real tree whatever built it.
    ///
    /// 透過 C API 而非 Swift wrapper：wrapper 只認得本套件所建立的 widget，而儲存格的內容是以
    /// 不透明的 `Widget` 形式抵達。`gtk_widget_get_first_child` 與 `get_next_sibling` 則無論該樹
    /// 由何者建立，都能看見真實結構。
    @discardableResult
    private static func setLabelsSelectable(
        under widget: UnsafeMutablePointer<GtkWidget>,
        to isSelectable: Bool
    ) -> Int {
        var reached = 0
        if let label = wrapped_gtk_widget_as_label(widget) {
            gtk_label_set_selectable(label, isSelectable.toGBoolean())
            reached += 1
        }

        var child = gtk_widget_get_first_child(widget)
        while let current = child {
            reached += setLabelsSelectable(under: current, to: isSelectable)
            child = gtk_widget_get_next_sibling(current)
        }
        return reached
    }

    /// Sets how many data rows the table has. Cells already placed below the new
    /// bound are detached.
    /// 設定表格的資料列數。已放置於新上限之下的儲存格會被卸下。
    public func setRowCount(_ count: Int) {
        guard count < rowCount, columnCount > 0 else {
            rowCount = count
            return
        }

        let keep = count * columnCount
        for cell in cellWidgets.dropFirst(keep) {
            grid.remove(child: cell)
        }
        cellWidgets = Array(cellWidgets.prefix(keep))
        rowCount = count
    }
}
