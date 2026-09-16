import Foundation
@_spi(Backends) import SwiftCrossUI
import UWP
import WinUI

// `defaultTableRowContentHeight` and `defaultTableCellVerticalPadding` are not
// here: they were already declared on the type in WinUIBackend.swift, beside the
// other metrics, left over from an earlier attempt at this feature that was
// removed down to those two lines. Declaring them again here is an "invalid
// redeclaration", which is how they were found.
//
// `defaultTableRowContentHeight` 與 `defaultTableCellVerticalPadding` 不在此處：它們早已與其他度量
// 一同宣告於 WinUIBackend.swift 之中，是先前一次「僅剩這兩行」的實作嘗試所遺留。在此重複宣告會得到
// 「invalid redeclaration」——它們正是這樣被發現的。
extension WinUIBackend: BackendFeatures.Tables {
    public func createTable() -> Widget {
        WinUITable()
    }

    public func setRowCount(ofTable table: Widget, to rows: Int) {
        (table as! WinUITable).setRowCount(rows)
    }

    public func setColumnLabels(
        ofTable table: Widget,
        to labels: [String],
        environment: EnvironmentValues
    ) {
        (table as! WinUITable).setColumnLabels(labels, environment: environment)
    }

    public func setCells(
        ofTable table: Widget,
        to cells: [Widget],
        withRowHeights rowHeights: [Int]
    ) {
        (table as! WinUITable).setCells(cells, rowHeights: rowHeights)
    }

    public func setTextSelectability(ofTable table: Widget, to isSelectable: Bool) {
        (table as! WinUITable).setTextSelectable(isSelectable)
    }

    public func setColumnWidths(ofTable table: Widget, to widths: [Double?]) {
        (table as! WinUITable).setColumnWidths(widths)
    }
}

/// Row selection for `WinUITable` (#125).
///
/// Hand-built for the same reason GtkBackend's is: this table is a `Grid`, and a
/// grid has no rows to select. `ListView` and the community `DataGrid` both have
/// selection built in and both want to own their item source, which is the one
/// thing `BackendFeatures.Tables` does not hand over -- it supplies cells that
/// are already built.
///
/// `WinUITable` 的列選取(#125)。
///
/// 與 GtkBackend 那一版出於相同理由是手工做的:這個表格是一個 `Grid`,而 grid 沒有「列」可選。
/// `ListView` 與社群的 `DataGrid` 都內建選取,而兩者都想擁有自己的 item source
/// ——那正是 `BackendFeatures.Tables` **不會**交出去的東西:它給的是**已經建好的**儲存格。
extension WinUIBackend: BackendFeatures.TableSelection {
    public func setSelectionHandler(
        ofTable table: Widget,
        to action: @escaping (Int?) -> Void
    ) {
        (table as! WinUITable).onRowSelected = action
    }

    public func setSelectedRow(ofTable table: Widget, to index: Int?) {
        (table as! WinUITable).selectRow(index)
    }
}

/// Clickable column headers for `WinUITable` (#125).
///
/// The same `pointerPressed` answers both, because the hit test already had to
/// find which row the y fell in; a header click is index 0, and the x -- needed
/// nowhere else -- picks the column out of the same column definitions the
/// layout uses.
///
/// `WinUITable` 的可點欄位標題(#125)。
///
/// 同一個 `pointerPressed` 同時回答兩者,因為那個命中測試本來就得算出 y 落在哪一列;
/// 標題點擊就是索引 0,而 x——在別處都用不到——則從版面所用的同一組 column definition
/// 裡挑出欄號。
extension WinUIBackend: BackendFeatures.TableColumnSorting {
    public func setSortHandler(
        ofTable table: Widget,
        to action: @escaping (Int) -> Void
    ) {
        (table as! WinUITable).onColumnHeaderClicked = action
    }

    public func setSortIndicator(ofTable table: Widget, column: Int?, ascending: Bool) {
        (table as! WinUITable).setSortIndicator(column: column, ascending: ascending)
    }
}

/// A table drawn with a `Grid`.
///
/// `Grid` rather than the `Canvas` every other container in this backend uses,
/// because a table is the one place where SwiftCrossUI does *not* hand the
/// backend a position for each child. `setCells` supplies a flat array grouped
/// by row plus the row heights, and arranging that into columns is the
/// backend's job -- which is exactly what `Grid` does and `Canvas`, having no
/// layout of its own, does not.
///
/// The ordering makes `Canvas` unworkable rather than merely inconvenient:
/// `Table.commit` calls `setCells` before `setSize(of: table)`, so at the moment
/// the cells are placed the total width is not yet known. `Grid` resolves star
/// columns when it is measured, after that size arrives.
///
/// GtkBackend reaches the same conclusion with a `GtkGrid`, so the two backends
/// agree on the shape; only the widget differs.
///
/// 以 `Grid` 繪製的表格。
///
/// 使用 `Grid` 而非本 backend 其他容器所用的 `Canvas`，因為表格正是 SwiftCrossUI **不會**為每個子
/// 元件提供位置的那一處。`setCells` 交來的是「依列分組的扁平陣列」加上每列高度，而把它排進欄位是
/// backend 的工作——那正是 `Grid` 所做的，也正是自身沒有排版能力的 `Canvas` 所做不到的。
///
/// 呼叫順序使 `Canvas` 不只是不便，而是行不通：`Table.commit` 會在 `setSize(of: table)` **之前**
/// 呼叫 `setCells`，因此放置 cell 的當下總寬度尚未可知。`Grid` 會在被量測時才解析 star 欄位，那已
/// 是尺寸抵達之後。
///
/// GtkBackend 以 `GtkGrid` 得到相同的結論，因此兩個 backend 在形狀上一致，差別只在 widget 本身。
/// `@MainActor` on the whole type rather than on the methods that need it.
/// Every member here touches a WinUI object, and WinUI objects are main-thread
/// only; the backend protocol this serves is `@MainActor` for the same reason.
/// Annotating individual methods would be describing that fact one method at a
/// time and leaving the next one to be added unannotated.
///
/// 將 `@MainActor` 標在整個型別上，而非只標在需要的方法上。此處每個成員都會觸及 WinUI 物件，而
/// WinUI 物件僅限主執行緒；本類別所服務的 backend protocol 也基於同一理由標記為 `@MainActor`。
/// 逐一標註方法，等於把同一件事重複陳述多次，並且把「下一個被加進來的方法」留在未標註的狀態。
@MainActor
final class WinUITable: WinUI.Grid {
    private var columnCount = 0
    /// Our own references to the `ColumnDefinition`s, in order.
    ///
    /// `columnDefinitions` is a WinRT vector and reading an element back out of
    /// it to mutate is more ceremony than keeping the objects we just made.
    /// `ColumnDefinition` is a reference type, so setting `width` on one of
    /// these is seen by the Grid.
    ///
    /// 我們自己按順序持有的 `ColumnDefinition` 參考。
    ///
    /// `columnDefinitions` 是一個 WinRT vector,為了修改而把元素讀回來,比留住我們剛剛建立的那些
    /// 物件更繁瑣。`ColumnDefinition` 是參考型別,因此在其中一個上設定 `width`,Grid 看得到。
    private var columnDefinitionObjects: [WinUI.ColumnDefinition] = []
    /// The row definitions, in order, for the same reason the columns are kept:
    /// reading them back out of the WinRT vector to ask for `actualHeight` is
    /// more ceremony than holding the objects. Used to turn a click's y
    /// coordinate into a row -- see ``handleClick(atY:)``.
    /// 按順序持有的 row definition,理由與欄位相同:為了問 `actualHeight` 而把元素從 WinRT vector
    /// 讀回來,比直接留住那些物件更繁瑣。用途是把點擊的 y 座標換算成列——見 ``handleClick(atY:)``。
    private var rowDefinitionObjects: [WinUI.RowDefinition] = []
    private var rowCount = 0

    /// Kept so `setCells` can put them back. Every `setCells` clears the
    /// children -- tracking which ones to remove individually is more state
    /// than rebuilding costs -- and the headers are children too, so without
    /// this they would disappear on the first data update.
    /// 保留下來，好讓 `setCells` 能把它們放回去。每次 `setCells` 都會清空所有子元件——逐一追蹤該移除
    /// 哪些，其狀態成本高於重建——而表頭本身也是子元件，因此少了這個陣列，它們會在第一次資料更新時
    /// 消失。
    private var headerLabels: [WinUI.TextBlock] = []
    /// The column titles as given, without any sort arrow. See
    /// ``setColumnLabels(_:environment:)``.
    /// 欄位標題的原始字串,不含任何排序箭頭。見 ``setColumnLabels(_:environment:)``。
    private var columnLabels: [String] = []
    private var cellWidgets: [WinUI.FrameworkElement] = []

    /// Reapplied on every `setCells`, not only when the setting changes.
    ///
    /// The cells are replaced wholesale each time, so a table rebuilt after
    /// selection was turned on would come back unselectable. P23's "More rows"
    /// button does exactly that rebuild, which is how GtkBackend found the same
    /// trap.
    ///
    /// 每次 `setCells` 都會重新套用，而非僅在設定變更時。
    ///
    /// cell 每次都是整批替換，因此在啟用選取之後重建的表格會變回不可選取。P23 的「More rows」按鈕
    /// 做的正是這種重建，而 GtkBackend 也正是這樣踩到同一個陷阱的。
    private var isTextSelectable = false

    func setRowCount(_ rows: Int) {
        guard rows != rowCount else { return }
        rowCount = rows
        rebuildRowDefinitions(rowHeights: [])
    }

    func setColumnLabels(_ labels: [String], environment: EnvironmentValues) {
        columnCount = labels.count
        // The titles WITHOUT any sort arrow. A TextBlock's current text stops
        // being a reliable source for the column's name once an indicator has
        // been appended, and stripping one back off cannot tell an arrow this
        // class added from one that belongs to the title.
        // 不含任何排序箭頭的**原始**標題。一旦指示符被附加上去,`TextBlock` 當下的文字就不再是
        // 「這一欄叫什麼」的可靠來源;而把箭頭剝回去的操作,分不出「本類別加上的」與
        // 「標題本身就有的」。
        columnLabels = labels

        columnDefinitions.clear()
        columnDefinitionObjects = []
        for _ in labels {
            let column = WinUI.ColumnDefinition()
            // Star, not auto. Auto sizes each column to its widest cell, which
            // is what a table looks like before anyone has decided how wide it
            // should be; the view has already been given a width by then and
            // the columns should divide it. GtkBackend gets the same result
            // with `expandHorizontally` plus `.fill`.
            // 使用 star 而非 auto。auto 會讓每欄縮到其最寬的 cell，那是「還沒有人決定表格該多寬」
            // 時的樣子；而此刻該 view 早已被指定寬度，欄位應當去分配它。GtkBackend 以
            // `expandHorizontally` 搭配 `.fill` 得到相同結果。
            column.width = WinUI.GridLength(value: 1, gridUnitType: .star)
            columnDefinitions.append(column)
            columnDefinitionObjects.append(column)
        }

        headerLabels = labels.map { label in
            let block = WinUI.TextBlock()
            block.text = label
            block.textTrimming = .characterEllipsis
            // Only when the application asked for a colour; otherwise the
            // theme's own, which carries the disabled and high-contrast
            // variants a brush built here cannot. A fresh TextBlock has no
            // local value to clear.
            if let brush = environment.explicitWinUIForegroundBrush {
                block.foreground = brush
            }
            block.fontSize = environment.resolvedFont.pointSize
            return block
        }

        // The blocks were just built from the plain titles, so an indicator set
        // earlier is no longer on screen -- the same reapplication the selection
        // highlight needs after `setCells`.
        // 那些 block 剛依「未加工的標題」建好,因此先前設定的指示符已經不在畫面上
        // ——與選取高亮在 `setCells` 之後需要重新套用,是同一件事。
        applySortIndicator()
        rebuildChildren(rowHeights: [])
    }

    // `WinUI.FrameworkElement`, not `Widget`. `Widget` is a typealias on
    // `WinUIBackend`, so it resolves inside an extension of that type and not
    // inside this class.
    // 使用 `WinUI.FrameworkElement` 而非 `Widget`。`Widget` 是 `WinUIBackend` 上的 typealias，因此
    // 它只在該型別的 extension 之中解析得到，在本類別之中則否。
    /// Sets a fixed width per column; nil returns that column to a star share.
    ///
    /// `.pixel` against `.star` is the whole mapping, and it is why this backend
    /// needed no bookkeeping while GtkBackend did: a `Grid` keeps its column
    /// structure as objects, so a width can be changed after the cells have
    /// already been placed. GTK's `Grid` derives column width from its widest
    /// child, so there the width has to be re-applied to every cell.
    ///
    /// 設定每欄的固定寬度;nil 讓該欄回到 star 分配。
    ///
    /// `.pixel` 對上 `.star` 就是全部的對應關係,而這也正是「本 backend 不需要任何記帳、
    /// 而 GtkBackend 需要」的原因:`Grid` 把它的欄位結構保存為**物件**,因此即使儲存格早已擺好,
    /// 寬度仍然改得動。GTK 的 `Grid` 則是由**該欄最寬的子元件**推導欄寬,所以在那邊,寬度必須
    /// 重新套用到每一個儲存格上。
    func setColumnWidths(_ widths: [Double?]) {
        for (index, column) in columnDefinitionObjects.enumerated() {
            let width = index < widths.count ? widths[index] : nil
            column.width =
                width.map { WinUI.GridLength(value: $0, gridUnitType: .pixel) }
                ?? WinUI.GridLength(value: 1, gridUnitType: .star)
        }
    }

    func setCells(_ cells: [WinUI.FrameworkElement], rowHeights: [Int]) {
        cellWidgets = cells
        rebuildRowDefinitions(rowHeights: rowHeights)
        rebuildChildren(rowHeights: rowHeights)
        applyTextSelectability()
        // `rebuildChildren` cleared the children, and the highlight was one of
        // them. Same reason the text selectability is reapplied here.
        // `rebuildChildren` 清空了所有子元件,而高亮正是其中之一。與文字選取在此重新套用的理由相同。
        applySelectionHighlight()
    }

    func setTextSelectable(_ isSelectable: Bool) {
        isTextSelectable = isSelectable
        applyTextSelectability()
    }

    // ─────────────────────────────────────────────────────────────────────────

    private func rebuildRowDefinitions(rowHeights: [Int]) {
        rowDefinitions.clear()
        rowDefinitionObjects = []

        // Row 0 is the header and sizes to its own content; data rows take the
        // height SwiftCrossUI computed for them.
        // 第 0 列是表頭，依其自身內容決定高度；資料列則採用 SwiftCrossUI 為它們算好的高度。
        let header = WinUI.RowDefinition()
        header.height = WinUI.GridLength(value: 0, gridUnitType: .auto)
        rowDefinitions.append(header)
        rowDefinitionObjects.append(header)

        for index in 0..<rowCount {
            let row = WinUI.RowDefinition()
            if index < rowHeights.count {
                row.height = WinUI.GridLength(
                    value: Double(rowHeights[index]),
                    gridUnitType: .pixel
                )
            } else {
                row.height = WinUI.GridLength(value: 0, gridUnitType: .auto)
            }
            rowDefinitions.append(row)
            rowDefinitionObjects.append(row)
        }
    }

    // MARK: - Row selection / 列的選取

    /// Called with a row index when the user clicks a row, never from
    /// ``selectRow(_:)``.
    ///
    /// Setting it installs the pointer handler, so a table nobody asked to be
    /// selectable does not start responding to clicks.
    ///
    /// 使用者點擊某列時以該列索引呼叫;``selectRow(_:)`` 不會觸發它。
    ///
    /// 設定它同時會安裝 pointer handler,因此沒有人要求可選取的表格不會開始對點擊有反應。
    var onRowSelected: ((Int?) -> Void)? {
        didSet { attachPointerHandlerIfNeeded() }
    }

    /// Called with a column index when the user clicks that column's header.
    /// Installs the same pointer handler as ``onRowSelected``.
    /// 使用者點擊某欄標題時,以該欄索引呼叫。它安裝的是與 ``onRowSelected`` 相同的 pointer handler。
    var onColumnHeaderClicked: ((Int) -> Void)? {
        didSet { attachPointerHandlerIfNeeded() }
    }

    private var sortColumn: Int?
    private var sortAscending = true

    /// Shows the sort indicator on one column, or on none.
    ///
    /// The arrow goes into the header's TEXT, matching GtkBackend, and for the
    /// reason that side records: a separate glyph would need a wrapper per
    /// column, and those wrappers are what a hit test would then resolve to.
    ///
    /// 把排序指示符顯示在某一欄上,或都不顯示。
    ///
    /// 那個箭頭放進標題的**文字**裡,與 GtkBackend 一致,理由也是那一側所記載的:另外畫一個字符
    /// 需要為每一欄包一層,而那些包裝層接著就會變成命中測試解析到的東西。
    func setSortIndicator(column: Int?, ascending: Bool) {
        sortColumn = column
        sortAscending = ascending
        applySortIndicator()
    }

    private func applySortIndicator() {
        for (index, label) in headerLabels.enumerated() {
            guard index < columnLabels.count else { continue }
            if index == sortColumn {
                label.text = columnLabels[index] + (sortAscending ? " \u{25B2}" : " \u{25BC}")
            } else {
                label.text = columnLabels[index]
            }
        }
    }

    /// Which column an x coordinate falls in, by accumulating the columns'
    /// actual widths -- the same shape as the row hit test, and correct for the
    /// same reason: the columns here are not all the same width, because
    /// `setColumnWidths` exists.
    ///
    /// 某個 x 座標落在哪一欄——以累加各欄的**實際寬度**求得,與列的命中測試同一個形狀,
    /// 正確的理由也相同:此處各欄的寬度**並不一致**,因為 `setColumnWidths` 是存在的。
    private func columnIndex(atX x: Double) -> Int? {
        guard x >= 0 else { return nil }
        var offset = 0.0
        for (index, definition) in columnDefinitionObjects.enumerated() {
            let width = definition.actualWidth
            if x < offset + width { return index }
            offset += width
        }
        return nil
    }

    /// Placed BEHIND the cells, and that is what `insertAt(0,)` in
    /// ``applySelectionHighlight()`` buys: a `Grid` draws its children in order,
    /// so a highlight appended last would cover the text it is highlighting.
    ///
    /// A `Border` rather than a `Rectangle` because it needs no `Fill`/`Stroke`
    /// distinction and takes the row's whole cell by default.
    ///
    /// 放在儲存格**後面**,而那正是 ``applySelectionHighlight()`` 裡 `insertAt(0,)` 的用意:
    /// `Grid` 依加入順序繪製子元件,因此**最後**才加入的高亮會蓋住它所要高亮的文字。
    ///
    /// 用 `Border` 而非 `Rectangle`,因為它不需要區分 `Fill`/`Stroke`,且預設就會佔滿該列的儲存格。
    private lazy var selectionHighlight: WinUI.Border = {
        let border = WinUI.Border()
        border.background = WinUI.SolidColorBrush(
            UWP.Color(a: 90, r: 53, g: 132, b: 228)
        )
        // Never the thing a click lands on. Without this the highlight sits
        // between the pointer and the cells, and the row under it could not be
        // identified from the element that was hit.
        // 它永遠不該是點擊落到的那個東西。少了這一行,高亮會夾在指標與儲存格之間,
        // 而「被命中的元素」就無法用來辨識它底下是哪一列。
        border.isHitTestVisible = false
        return border
    }()

    private var selectedRow: Int?
    private var pointerHandlerAttached = false

    /// Selects a row without reporting it; nil clears the selection.
    /// 選取某一列但不回報;nil 清除選取。
    func selectRow(_ index: Int?) {
        guard index != selectedRow else { return }
        selectedRow = index
        applySelectionHighlight()
    }

    /// Whether the highlight is currently in `children`.
    ///
    /// **A flag rather than searching `children` for it.** Reading an element
    /// back out of a WinRT collection hands you a fresh Swift wrapper around the
    /// same COM object, so `===` against the one we hold can be false for the
    /// element that IS there -- measured on this backend's lazy rows the same
    /// day, where one wrapper address served six different rows. The search
    /// would then never find it, insert a second copy, and keep going.
    ///
    /// Cleared in ``rebuildChildren(rowHeights:)``, which empties the
    /// collection.
    ///
    /// 高亮目前是否在 `children` 之中。
    ///
    /// **用一個旗標,而不是去 `children` 裡尋找它。** 從 WinRT collection 讀回一個元素,拿到的是
    /// 圍繞同一個 COM 物件的**全新 Swift wrapper**,因此拿 `===` 去比對我們手上那個,對於
    /// **確實在裡面**的那個元素也可能是 false——同一天在本 backend 的 lazy rows 上量到過:
    /// 一個 wrapper 位址先後服務了六個不同的列。那樣的搜尋會永遠找不到它、於是插入第二份,然後繼續。
    ///
    /// 在 ``rebuildChildren(rowHeights:)`` 中清除,因為那裡會清空整個 collection。
    private var highlightIsInChildren = false

    private func applySelectionHighlight() {
        // Index 0 by construction: it is the only thing inserted at the front,
        // and everything else is appended after it. So removing it needs no
        // search and therefore no identity comparison at all.
        // 依建構方式必然在索引 0:只有它被插到最前面,其餘都是往後 append。因此移除它不需要搜尋,
        // 也就完全不需要做任何識別比對。
        if highlightIsInChildren, children.count > 0 {
            children.removeAt(0)
            highlightIsInChildren = false
        }
        guard let selectedRow, selectedRow < rowCount, columnCount > 0 else { return }
        WinUI.Grid.setRow(selectionHighlight, Int32(selectedRow + 1))
        WinUI.Grid.setColumn(selectionHighlight, 0)
        WinUI.Grid.setColumnSpan(selectionHighlight, Int32(columnCount))
        children.insertAt(0, selectionHighlight)
        highlightIsInChildren = true
    }

    /// Subscribes `pointerPressed`, once.
    ///
    /// **`background` is set at the same time and is not cosmetic.** A `Grid`
    /// with no background does not hit-test at all, so the transparent brush is
    /// what makes a click anywhere in the table -- including the gaps between
    /// cells -- reach this handler. A fully transparent brush still hit-tests;
    /// `nil` does not.
    ///
    /// Subscribed rather than `addHandler(_:_:handledEventsToo:)`, which this
    /// backend has measured as silently doing nothing (see the slider note in
    /// WinUIBackend.swift). Nothing in a table's own template handles
    /// `pointerPressed`, so the plain subscription is enough here.
    ///
    /// 訂閱 `pointerPressed`,只做一次。
    ///
    /// **同時設定 `background`,而那不是裝飾。** 一個沒有 background 的 `Grid` **完全不參與命中測試**,
    /// 因此那個透明筆刷才是「點在表格任何位置(含儲存格之間的空隙)都能抵達這個 handler」的原因。
    /// 完全透明的筆刷仍會參與命中測試;`nil` 不會。
    ///
    /// 採直接訂閱,而非 `addHandler(_:_:handledEventsToo:)`——本 backend 已量到後者會**靜默地
    /// 什麼都不做**(見 WinUIBackend.swift 中 slider 的那段註解)。表格自身的 template 不會 handle
    /// `pointerPressed`,因此此處直接訂閱就足夠。
    /// One line per attach, per pointer event and per hit test, when
    /// `SCUI_WINUI_TABLE_TRACE` is set. Off by default.
    /// 設定了 `SCUI_WINUI_TABLE_TRACE` 時,掛載、每個 pointer 事件與每次命中測試各印一行。預設關閉。
    static let tableTraceEnabled =
        ProcessInfo.processInfo.environment["SCUI_WINUI_TABLE_TRACE"] != nil

    static func traceTable(_ message: @autoclosure () -> String) {
        guard tableTraceEnabled else { return }
        print("TABLE \(message())")
    }

    private func attachPointerHandlerIfNeeded() {
        guard !pointerHandlerAttached else { return }
        pointerHandlerAttached = true
        background = WinUI.SolidColorBrush(UWP.Color(a: 0, r: 0, g: 0, b: 0))
        WinUITable.traceTable("pointer handler attached")
        pointerPressed.addHandler { [weak self] _, args in
            WinUITable.traceTable("pointerPressed fired")
            guard let self, let args else { return }
            // `try?`, not `try!`: this runs on every click, and a pointer event
            // whose position cannot be read is not worth taking the app down
            // for. A nil point becomes -1 below and selects nothing.
            // 用 `try?` 而非 `try!`:這段每次點擊都會跑,而「讀不到位置的 pointer 事件」
            // 不值得讓整個 app 結束。nil 在下方會變成 -1,於是什麼都不會被選取。
            let point = try? args.getCurrentPoint(self)
            // `Point.y` is a `Float` here while `RowDefinition.actualHeight` is
            // a `Double`, so the conversion is explicit rather than left to
            // whichever one the compiler picks.
            // 此處 `Point.y` 是 `Float`,而 `RowDefinition.actualHeight` 是 `Double`,
            // 因此明確轉換,而不是交給編譯器去挑一個。
            self.handleClick(
                atX: Double(point?.position.x ?? -1),
                y: Double(point?.position.y ?? -1)
            )
        }
    }

    /// Turns a click's y coordinate into a row index.
    ///
    /// Walks the row definitions' `actualHeight` rather than dividing by a
    /// nominal row height: rows here are given individual pixel heights by
    /// SwiftCrossUI, and the header row is `auto`, so there is no single height
    /// to divide by. The header is row 0 and consumes its height before any data
    /// row can match, which is what makes a click on a column title select
    /// nothing.
    ///
    /// 把點擊的 y 座標換算成列索引。
    ///
    /// 走訪各 row definition 的 `actualHeight`,而不是拿一個名目列高去除:此處各列的像素高度是
    /// SwiftCrossUI 個別給定的,而標題列是 `auto`——根本不存在單一的列高可供相除。標題是第 0 列,
    /// 且會在任何資料列能夠命中之前先耗掉它自己的高度,那正是「點在欄位標題上不會選到任何東西」的原因。
    private func handleClick(atX x: Double, y: Double) {
        WinUITable.traceTable(
            "handleClick y=\(y) rowDefs=\(rowDefinitionObjects.count) rowCount=\(rowCount)"
                + " heights=\(rowDefinitionObjects.prefix(4).map { $0.actualHeight })"
        )
        guard y >= 0 else { return }
        var offset = 0.0
        for (index, definition) in rowDefinitionObjects.enumerated() {
            let height = definition.actualHeight
            if y < offset + height {
                WinUITable.traceTable("handleClick matched definition index=\(index)")
                // Row 0 is the header. Not a selection -- but a SORT request
                // when anybody asked for one, which is the only place the x
                // coordinate is needed at all.
                // 第 0 列是標題。它不是一次選取——但**當有人要求排序時**,它是一次排序請求;
                // 而那也是**唯一**需要用到 x 座標的地方。
                if index == 0 {
                    guard let column = columnIndex(atX: x) else { return }
                    WinUITable.traceTable("handleClick header column=\(column)")
                    onColumnHeaderClicked?(column)
                    return
                }
                guard index >= 1 else { return }
                let row = index - 1
                guard row < rowCount else { return }
                selectedRow = row
                applySelectionHighlight()
                onRowSelected?(row)
                return
            }
            offset += height
        }
    }

    private func rebuildChildren(rowHeights: [Int]) {
        children.clear()
        // The highlight was one of the children that just went. `setCells`
        // puts it back after this returns.
        // 高亮正是剛剛被清掉的子元件之一。`setCells` 會在本方法返回後把它放回去。
        highlightIsInChildren = false

        for (column, label) in headerLabels.enumerated() {
            WinUI.Grid.setRow(label, 0)
            WinUI.Grid.setColumn(label, Int32(column))
            children.append(label)
        }

        guard columnCount > 0 else { return }

        for (index, cell) in cellWidgets.enumerated() {
            let row = index / columnCount
            let column = index % columnCount
            // A cell past the current row count is dropped rather than placed
            // in a row that does not exist. `setRowCount` and `setCells` are
            // separate calls, so the two can disagree for one frame.
            // 超出目前列數的 cell 會被捨棄，而不是放進一個不存在的列。`setRowCount` 與 `setCells`
            // 是兩次獨立呼叫，因此兩者可能有一個 frame 的時間彼此不一致。
            guard row < rowCount else { break }

            WinUI.Grid.setRow(cell, Int32(row + 1))
            WinUI.Grid.setColumn(cell, Int32(column))
            children.append(cell)
        }
    }

    /// Applies selection to the text a cell draws, not to the cell itself.
    ///
    /// A cell is an arbitrary view -- SwiftCrossUI wraps each one in a
    /// container and what is inside may not be text at all -- so this descends
    /// rather than assuming a shape, and leaves anything that is not a
    /// `TextBlock` alone. The header is included: a column title is as worth
    /// copying as a cell.
    ///
    /// 套用的對象是 cell 所繪製的文字，而非 cell 本身。
    ///
    /// cell 是任意的 view——SwiftCrossUI 會將每個 cell 包進一個容器，而其內容未必是文字——因此此處
    /// 是向下走訪而非假設其形狀，並且不去動任何非 `TextBlock` 的東西。表頭也包含在內：欄位標題與
    /// cell 一樣值得被複製。
    private func applyTextSelectability() {
        for label in headerLabels {
            label.isTextSelectionEnabled = isTextSelectable
        }
        for cell in cellWidgets {
            Self.applyTextSelectability(isTextSelectable, to: cell)
        }
    }

    private static func applyTextSelectability(
        _ isSelectable: Bool,
        to element: WinUI.FrameworkElement
    ) {
        if let block = element as? WinUI.TextBlock {
            block.isTextSelectionEnabled = isSelectable
            return
        }

        guard let panel = element as? WinUI.Panel else { return }
        for index in 0..<panel.children.size {
            guard let child = panel.children.getAt(index) as? WinUI.FrameworkElement else {
                continue
            }
            applyTextSelectability(isSelectable, to: child)
        }
    }
}
