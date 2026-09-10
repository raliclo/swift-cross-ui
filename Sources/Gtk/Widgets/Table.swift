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
    /// A fixed width per column, or nil for a column that shares evenly.
    ///
    /// STORED rather than applied and forgotten, because a `GtkGrid` column's
    /// width comes from its widest child and the children arrive in two batches:
    /// the header labels from ``setColumnLabels(_:)`` and the cells from
    /// ``setCells(_:rowHeights:)``, with `setColumnWidths` called between them.
    /// Applying widths only when they arrive would size the headers and leave
    /// every cell expanding, and a header that disagrees with the cells beneath
    /// it is exactly the defect this is meant to remove.
    ///
    /// 每欄的固定寬度;nil 表示該欄平均分配。
    ///
    /// **儲存起來**而非套用後即丟,因為 `GtkGrid` 某一欄的寬度取決於**該欄最寬的子元件**,而子元件
    /// 分兩批抵達:``setColumnLabels(_:)`` 送來的標題,以及 ``setCells(_:rowHeights:)`` 送來的
    /// 儲存格,而 `setColumnWidths` 夾在兩者之間被呼叫。若只在寬度抵達時套用一次,結果會是標題被
    /// 定了尺寸、而每一個儲存格仍在擴張——**標題與其下儲存格對不齊**,正是本功能所要消除的缺陷。
    private var columnWidths: [Double?] = []

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
            // `xalign` as well as `halign`, and the difference only shows once a
            // column has a fixed width. `halign` places the LABEL WIDGET inside
            // its grid cell; `xalign` places the TEXT inside the label. While
            // every column expands they are the same thing, because the widget
            // shrinks to its text. Give a column a width and the widget becomes
            // that wide, and GtkLabel's default `xalign` of 0.5 then centres the
            // text inside it -- so the header floats in the middle of a column
            // whose cells are left-aligned.
            //
            // Measured 2026-09-10 with `.width(200)` on P23's ID column: the
            // header "ID" landed at x=131 while the digits beneath it were at
            // x=33.
            //
            // 同時設定 `xalign` 與 `halign`,而兩者的差別只有在某一欄有固定寬度時才看得出來。
            // `halign` 決定的是 **label widget** 在其 grid cell 中的位置;`xalign` 決定的是
            // **文字** 在 label 之內的位置。當每一欄都在擴展時,兩者是同一回事,因為 widget 會縮到
            // 貼合它的文字。一旦給某欄固定寬度,widget 就變成那麼寬,而 GtkLabel 預設的 `xalign`
            // 0.5 會把文字置中於其中——於是標題浮在一個「儲存格靠左」的欄位中央。
            //
            // 2026-09-10 以 P23 的 ID 欄加 `.width(200)` 實測:標題「ID」落在 x=131,
            // 而其下的數字在 x=33。
            label.xalign = 0
            return label
        }

        for (column, label) in headerLabels.enumerated() {
            grid.attach(child: label, left: column, top: 0, width: 1, height: 1)
        }

        applyWidth(toHeaders: true)
    }

    /// Sets a fixed width per column; nil lets that column share evenly.
    ///
    /// Applied to the headers now and remembered for the cells, which have not
    /// arrived yet -- see ``columnWidths``.
    ///
    /// 設定每欄的固定寬度;nil 讓該欄平均分配。
    ///
    /// 現在套用到標題,並為**尚未抵達**的儲存格記住它——見 ``columnWidths``。
    public func setColumnWidths(_ widths: [Double?]) {
        columnWidths = widths
        applyWidth(toHeaders: true)
        applyWidth(toHeaders: false)
    }

    /// The width for a column, or nil when it should share evenly.
    /// 某一欄的寬度;應平均分配時為 nil。
    private func width(ofColumn column: Int) -> Double? {
        guard column < columnWidths.count else { return nil }
        return columnWidths[column]
    }

    /// Pins or releases the horizontal sizing of one batch of children.
    ///
    /// `expandHorizontally` and a size request are set together and always
    /// opposite: a widget that both expands and asks for a width will be given
    /// the larger of the two by GTK, so leaving expand on would make a fixed
    /// width behave as a MINIMUM. That is a plausible-looking result -- narrow
    /// columns obey and wide ones do not -- which is worse than it plainly not
    /// working.
    ///
    /// 為某一批子元件釘住或釋放其水平尺寸。
    ///
    /// `expandHorizontally` 與 size request 一起設定,而且**永遠相反**:一個既會擴展、又要求寬度的
    /// widget,GTK 會給它兩者中較大的那個——因此若讓 expand 保持開啟,固定寬度的行為會變成**最小值**。
    /// 那是一個**看起來合理**的結果:窄的欄遵守、寬的欄不遵守——而那比「明顯不生效」更糟。
    private func applyWidth(toHeaders: Bool) {
        let widgets: [Widget] = toHeaders ? headerLabels : cellWidgets
        guard columnCount > 0 else { return }

        for (index, widget) in widgets.enumerated() {
            let column = toHeaders ? index : index % columnCount
            let width = width(ofColumn: column)
            widget.expandHorizontally = width == nil
            widget.setSizeRequest(
                width: width.map { Int($0.rounded()) } ?? -1,
                height: toHeaders ? -1 : widget.getSizeRequest().height
            )
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

            let width = width(ofColumn: column)
            cell.expandHorizontally = width == nil
            cell.horizontalAlignment = .fill
            cell.setSizeRequest(
                width: width.map { Int($0.rounded()) } ?? -1,
                height: row < rowHeights.count ? rowHeights[row] : -1
            )

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
