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
    /// The column titles as given, without any sort arrow.
    ///
    /// Kept because a `GtkLabel`'s current text is not a reliable source for
    /// what the column is called once an indicator has been appended to it:
    /// stripping an arrow back off cannot tell an arrow this class added from
    /// one that is part of the title.
    /// 欄位標題的**原始**字串,不含任何排序箭頭。
    ///
    /// 之所以保留,是因為一旦指示符被附加上去,`GtkLabel` 當下的文字就不再是「這一欄叫什麼」的
    /// 可靠來源:把箭頭剝回去的操作,分不出「本類別加上的箭頭」與「標題本身就有的箭頭」。
    private var columnLabels: [String] = []
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
        columnLabels = labels

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

        // The labels were just rebuilt from the plain titles, so an indicator
        // set earlier is no longer on screen. Same shape as the selection
        // highlight being reapplied after `setCells`.
        // 那些 label 剛剛才依「未加工的標題」重建過,因此先前設定的指示符已經不在畫面上。
        // 與選取高亮在 `setCells` 之後重新套用,是同一個形狀。
        applySortIndicator()
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
        // Same reasoning, and the reason `Table.swift` in SwiftCrossUI applies
        // the selection AFTER the cells: these are new widgets, so whatever was
        // highlighted a moment ago is no longer on screen.
        // 同樣的理由,也正是 SwiftCrossUI 的 `Table.swift` 把選取放在儲存格**之後**套用的原因:
        // 這些是新的 widget,因此片刻之前被高亮的東西已經不在畫面上了。
        applySelectionHighlight()
    }

    // MARK: - Row selection / 列的選取

    /// Called with a row index when the user clicks a row, never when
    /// ``selectRow(_:)`` is called.
    ///
    /// Setting it is also what installs the click gesture, so a table nobody
    /// asked to be selectable does not become clickable as a side effect of this
    /// code existing.
    ///
    /// 使用者點擊某列時以該列索引呼叫;``selectRow(_:)`` 被呼叫時**不會**觸發。
    ///
    /// 設定它同時也是**安裝點擊 gesture 的動作**,因此一個沒有人要求它可選取的表格,不會因為
    /// 這段程式碼的存在就順帶變得可點。
    public var onRowSelected: ((Int?) -> Void)? {
        didSet { attachClickGestureIfNeeded() }
    }

    /// Called with a column index when the user clicks that column's header.
    ///
    /// Installs the same gesture as ``onRowSelected``, so a table that wants
    /// only sorting gets clickable headers without becoming row-selectable, and
    /// the other way round.
    ///
    /// 使用者點擊某欄標題時,以該欄索引呼叫。
    ///
    /// 它安裝的是與 ``onRowSelected`` 相同的那個 gesture,因此一個**只要排序**的表格會得到可點的
    /// 標題、而不會因此變得可選列;反之亦然。
    public var onColumnHeaderClicked: ((Int) -> Void)? {
        didSet { attachClickGestureIfNeeded() }
    }

    /// Which column carries the sort indicator, and which way it points.
    /// 哪一欄帶著排序指示符,以及它朝哪個方向。
    private var sortColumn: Int?
    private var sortAscending = true

    /// Shows the sort indicator on one column, or on none.
    ///
    /// **The arrow is appended to the header's TEXT rather than drawn as a
    /// separate widget.** A `GtkGrid` header cell holds one label; adding an
    /// icon beside it would mean a box per column, and those boxes would then be
    /// the grid children that ``handleClick(x:y:)`` walks up to -- changing what
    /// a click resolves to in order to draw a triangle.
    ///
    /// The labels are re-set from `columnLabels` every time rather than having
    /// arrows stripped off them, because "remove the arrow I added" and "remove
    /// the arrow that is part of this column's name" are the same string
    /// operation and only one of them is right.
    ///
    /// 把排序指示符顯示在某一欄上,或都不顯示。
    ///
    /// **那個箭頭是**附加在標題的**文字**上,而不是另外畫一個 widget。`GtkGrid` 的標題格裡只有
    /// 一個 label;要在旁邊加一個圖示,就得為每一欄包一個 box,而那些 box 接著會變成
    /// ``handleClick(x:y:)`` 往上走時碰到的 grid 子元件——**為了畫一個三角形而改變了「一次點擊
    /// 會解析成什麼」**。
    ///
    /// 每次都從 `columnLabels` **重新設定**文字,而不是把箭頭從現有文字上剝掉,因為
    /// 「移除我加上的那個箭頭」與「移除這一欄名字裡本來就有的箭頭」是同一個字串操作,
    /// 而其中只有一個是對的。
    public func setSortIndicator(column: Int?, ascending: Bool) {
        sortColumn = column
        sortAscending = ascending
        applySortIndicator()
    }

    private func applySortIndicator() {
        for (index, label) in headerLabels.enumerated() {
            guard index < columnLabels.count else { continue }
            if index == sortColumn {
                label.label = columnLabels[index] + (sortAscending ? " \u{25B2}" : " \u{25BC}")
            } else {
                label.label = columnLabels[index]
            }
        }
    }

    private var selectedRow: Int?
    private var clickGesture: GestureClick?

    /// One provider for the whole display, loaded once.
    ///
    /// **A literal colour rather than a theme variable.** `@accent_bg_color`
    /// would follow the user's theme and is what a hand-written GTK app should
    /// use -- but a name the running theme does not define is a CSS parse error,
    /// and GTK drops the rule silently rather than reporting it. A dropped rule
    /// here means clicks register and nothing highlights, which reads exactly
    /// like selection not working at all.
    ///
    /// 一個載入一次、涵蓋整個 display 的 provider。
    ///
    /// **使用字面色值,而非主題變數。** `@accent_bg_color` 會跟隨使用者的主題,那也是一支手寫的
    /// GTK app 該用的東西——但**目前主題沒有定義的名稱是 CSS 解析錯誤**,而 GTK 會靜默地丟掉該規則、
    /// 不作任何回報。在此被丟掉的規則意謂著「點擊有反應、但什麼都沒有高亮」,而那看起來與
    /// 「選取根本沒有運作」一模一樣。
    private static let selectionCSSClass = "scui-table-row-selected"
    private lazy var selectionCSSProvider: CSSProvider = {
        let provider = CSSProvider()
        provider.loadCss(
            from: ".\(Table.selectionCSSClass) { background-color: rgba(53, 132, 228, 0.35); }"
        )
        return provider
    }()

    /// Selects a row without reporting it. nil clears the selection.
    /// 選取某一列但**不**回報它;nil 清除選取。
    public func selectRow(_ index: Int?) {
        guard index != selectedRow else { return }
        selectedRow = index
        applySelectionHighlight()
    }

    /// Adds the highlight class to the selected row's cells and removes it from
    /// everything else.
    ///
    /// Walks every cell rather than tracking which ones were marked: the cells
    /// are replaced wholesale by ``setCells(_:rowHeights:)``, so a remembered
    /// list of highlighted widgets would name widgets that no longer exist.
    ///
    /// 把高亮 class 加到被選取列的儲存格上,並從其他所有儲存格移除。
    ///
    /// 走訪**每一個**儲存格,而不是記住「哪些被標記過」:儲存格會被
    /// ``setCells(_:rowHeights:)`` 整批替換,因此一份記住的清單所指的會是已經不存在的 widget。
    private func applySelectionHighlight() {
        guard columnCount > 0 else { return }
        _ = selectionCSSProvider
        for (index, cell) in cellWidgets.enumerated() {
            let row = index / columnCount
            if row == selectedRow {
                gtk_widget_add_css_class(cell.widgetPointer, Table.selectionCSSClass)
            } else {
                gtk_widget_remove_css_class(cell.widgetPointer, Table.selectionCSSClass)
            }
        }
    }

    /// Attaches the click gesture, once.
    ///
    /// **Once, and the counter is the gesture itself rather than a bool**, so
    /// there is nothing to get out of step. A controller added per commit is the
    /// `began=5` shape this backend already hit on a slider: five controllers,
    /// each firing once, reported as five presses.
    ///
    /// The gesture goes on the GRID, not on the cells. A cell is an arbitrary
    /// widget supplied by the framework, and putting a gesture on each would
    /// mean adding and removing controllers on widgets this class does not own,
    /// every time the table is rebuilt.
    ///
    /// 掛上點擊 gesture,只掛一次。
    ///
    /// **只掛一次,而且作為記號的是那個 gesture 本身、不是一個 bool**,因此沒有東西可以失去同步。
    /// 每次 commit 都新增一個 controller,正是本 backend 在 slider 上撞過的 `began=5` 形狀:
    /// 五個 controller、各觸發一次,被回報成五次按下。
    ///
    /// gesture 掛在 **grid** 上,不是掛在儲存格上。儲存格是框架提供的任意 widget,若逐一掛上,
    /// 等於每次重建表格時都要在「本類別並不擁有的 widget」上增刪 controller。
    private func attachClickGestureIfNeeded() {
        guard clickGesture == nil else { return }
        let gesture = GestureClick()
        gesture.pressed = { [weak self] _, _, x, y in
            self?.handleClick(x: x, y: y)
        }
        clickGesture = gesture
        grid.addEventController(gesture)
    }

    /// Turns a click position into a row index, or nil for the header and for
    /// empty space.
    ///
    /// `gtk_widget_pick` answers "what is under this point", and the answer is
    /// usually a label deep inside a cell, so this walks up until it reaches a
    /// direct child of the grid -- which is the widget the grid can be asked
    /// about. Reading the row out of `gtk_grid_query_child` rather than dividing
    /// by a row height is what makes it correct for rows of different heights.
    ///
    /// 把點擊位置變成列索引;標題列與空白處回傳 nil。
    ///
    /// `gtk_widget_pick` 回答的是「這個點底下是什麼」,而答案通常是深藏在儲存格裡的某個 label,
    /// 因此此處會往上走,直到抵達 grid 的**直接子元件**——那才是可以拿去問 grid 的 widget。
    /// 從 `gtk_grid_query_child` 讀出列號、而不是拿列高去除,正是它在各列高度不同時仍然正確的原因。
    private func handleClick(x: Double, y: Double) {
        guard
            let picked = gtk_widget_pick(
                grid.widgetPointer,
                x,
                y,
                GTK_PICK_DEFAULT
            )
        else { return }

        var candidate: UnsafeMutablePointer<GtkWidget>? = picked
        while let current = candidate,
            let parent = gtk_widget_get_parent(current),
            parent != grid.widgetPointer
        {
            candidate = parent
        }
        guard let child = candidate, let position = grid.queryChild(child) else { return }

        // Row 0 is the header; a click there is not a row selection.
        // 第 0 列是標題;點在那裡不是一次列選取。
        // Row 0 is the header, and it is not a dead zone: a click there is a
        // SORT request when anybody asked for one. The row and the column come
        // out of the same `queryChild` call, so this costs nothing beyond the
        // branch -- and it is the reason the gesture stayed on the grid rather
        // than on the cells.
        // 第 0 列是標題,而它**不是死區**:當有人要求排序時,點在那裡是一次**排序請求**。
        // 列號與欄號來自**同一次** `queryChild` 呼叫,因此除了這個分支之外不花任何成本
        // ——這也正是那個 gesture 掛在 grid 上、而不是掛在儲存格上的理由。
        if position.row == 0 {
            guard position.column < columnCount else { return }
            onColumnHeaderClicked?(position.column)
            return
        }

        guard position.row >= 1 else { return }
        let index = position.row - 1
        guard index < rowCount else { return }

        selectedRow = index
        applySelectionHighlight()
        onRowSelected?(index)
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
