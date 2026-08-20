import CGtk

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
