/// A container that presents rows of data arranged in columns.
public struct Table<RowValue, RowContent: TableRowContent<RowValue>>: TypeSafeView, View {
    typealias Children = TableViewChildren<RowContent.RowContent>

    public var body = EmptyView()

    /// The row data to display.
    private var rows: [RowValue]
    /// The columns to display (which each compute their cell values when given
    /// ``Table/Row`` instances).
    private var columns: RowContent
    /// The selected row's index, when the table was given a selection binding.
    ///
    /// **An index, not a row value.** A table's rows are not required to be
    /// `Identifiable` or even `Equatable` here -- `RowValue` carries no
    /// constraint at all -- so there is nothing to compare a stored row against
    /// to find it again. `List` can use values because its own API asks for
    /// them; this cannot, and an index is what the backend reports anyway.
    ///
    /// nil when no binding was given, which is what keeps the selection-free
    /// initializer behaving exactly as it did.
    ///
    /// 被選取列的索引——在這個表格有拿到 selection binding 時。
    ///
    /// **是索引,不是列的值。** 此處表格的列並不被要求 `Identifiable`、甚至不被要求 `Equatable`
    /// ——`RowValue` 完全沒有任何約束——因此沒有任何東西可以拿來比對、把存起來的那一列找回來。
    /// `List` 之所以能用值,是因為它自己的 API 就要求了那些;這裡不能,而 backend 回報的本來就是索引。
    ///
    /// 沒有給 binding 時為 nil,而那正是讓「不含選取的初始化式」行為完全不變的東西。
    private var selection: Binding<Int?>?
    /// Which column the table is sorted by and in which direction, when the
    /// table was given a sort binding.
    ///
    /// **The framework never sorts.** It reports the click, flips the direction
    /// when the same column is clicked twice, and writes the result here; the
    /// app reorders its own `rows`. See ``BackendFeatures/TableColumnSorting``
    /// for why there is no other option: a column is a closure, not a key path,
    /// so nothing between the click and the app knows how two rows compare.
    ///
    /// 這個表格依哪一欄、以哪個方向排序——在它有拿到 sort binding 時。
    ///
    /// **框架從不排序。** 它回報點擊、在同一欄被點第二次時翻轉方向,並把結果寫在這裡;
    /// 由 **app** 重新排列自己的 `rows`。為何別無選擇見 ``BackendFeatures/TableColumnSorting``:
    /// 一個欄位是 closure、不是 key path,因此在點擊與 app 之間沒有任何一層知道兩列該怎麼比較。
    private var sortOrder: Binding<TableSortOrder?>?

    /// Creates a table that computes its cell values based on a collection of
    /// rows.
    ///
    /// - Parameters:
    ///   - rows: The row data to display.
    ///   - columns: The columns to display (which each compute their cell
    ///     values when given `Row` instances).
    public init(
        _ rows: [RowValue],
        @TableRowBuilder<RowValue> _ columns: () -> RowContent
    ) {
        self.rows = rows
        self.columns = columns()
        self.selection = nil
        self.sortOrder = nil
    }

    /// Creates a table whose sort order is bound to `sortOrder`.
    ///
    /// Clicking a column header writes here; clicking the same header again
    /// flips `ascending`. **The rows do not move until the app moves them** --
    /// sort its own array on the binding's change. A backend that does not
    /// implement ``BackendFeatures/TableColumnSorting`` draws the table it drew
    /// before, with headers that do nothing.
    ///
    /// 建立一個「排序狀態與 `sortOrder` 綁定」的表格。
    ///
    /// 點擊欄位標題會寫入此處;再次點擊同一個標題會翻轉 `ascending`。
    /// **在 app 自己動手之前,那些列不會移動**——請在 binding 改變時排序自己的陣列。
    /// 未實作 ``BackendFeatures/TableColumnSorting`` 的 backend,畫出來的仍是先前那個表格,
    /// 只是標題點了沒有反應。
    public init(
        _ rows: [RowValue],
        sortOrder: Binding<TableSortOrder?>,
        @TableRowBuilder<RowValue> _ columns: () -> RowContent
    ) {
        self.rows = rows
        self.columns = columns()
        self.selection = nil
        self.sortOrder = sortOrder
    }

    /// Creates a table with both a selection and a sort order.
    ///
    /// Present because the two are independent features that a real table wants
    /// together, and because four initialisers is still fewer than making either
    /// one a modifier that can be applied twice.
    ///
    /// 建立一個同時具備選取與排序狀態的表格。
    ///
    /// 之所以存在,是因為這兩者是**互相獨立**、而真實的表格會同時想要的功能;也因為四個建構式
    /// 仍然好過「把其中一個做成可以被套用兩次的 modifier」。
    public init(
        _ rows: [RowValue],
        selection: Binding<Int?>,
        sortOrder: Binding<TableSortOrder?>,
        @TableRowBuilder<RowValue> _ columns: () -> RowContent
    ) {
        self.rows = rows
        self.columns = columns()
        self.selection = selection
        self.sortOrder = sortOrder
    }

    /// Creates a table whose selected row is bound to `selection`.
    ///
    /// The binding is written when the user selects a row and read to place the
    /// selection, so setting it in code moves the highlight. A backend that does
    /// not implement ``BackendFeatures/TableSelection`` ignores both directions
    /// and draws the table it drew before, rather than refusing to draw it.
    ///
    /// - Parameters:
    ///   - rows: The row data to display.
    ///   - selection: The index of the selected row, or nil for none.
    ///   - columns: The columns to display.
    ///
    /// 建立一個「被選取的列」與 `selection` 綁定的表格。
    ///
    /// 使用者選取某列時會寫入這個 binding,而放置選取時會讀它——因此在程式中設定它就會移動高亮。
    /// 未實作 ``BackendFeatures/TableSelection`` 的 backend 會忽略這兩個方向,畫出它先前所畫的表格,
    /// 而不是拒絕繪製。
    public init(
        _ rows: [RowValue],
        selection: Binding<Int?>,
        @TableRowBuilder<RowValue> _ columns: () -> RowContent
    ) {
        self.rows = rows
        self.columns = columns()
        self.selection = selection
        self.sortOrder = nil
    }

    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> Children {
        // TODO: Table snapshotting
        TableViewChildren()
    }

    @CastBackend<BackendFeatures.Tables>(returnsWidget: true)
    func asWidget<Backend: BaseAppBackend>(
        _ children: Children,
        backend: Backend
    ) -> Backend.Widget {
        return backend.createTable()
    }

    @CastBackend<BackendFeatures.Tables>
    func computeLayout<Backend: BaseAppBackend>(
        _: Backend.Widget,
        children: Children,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        let size = proposedSize
        var cellResults: [ViewLayoutResult] = []
        children.rowContent = rows.map(columns.content(for:)).map(RowView.init(_:))
        let columnLabels = columns.labels
        let columnCount = columnLabels.count

        // Create and destroy row nodes
        let remainder = children.rowContent.count - children.rowNodes.count
        if remainder < 0 {
            children.rowNodes.removeLast(-remainder)
            children.cellContainerWidgets.removeLast(-remainder * columnCount)
        } else if remainder > 0 {
            for row in children.rowContent[children.rowNodes.count...] {
                let rowNode = AnyViewGraphNode(
                    for: row,
                    backend: backend,
                    environment: environment
                )
                children.rowNodes.append(rowNode)
                for cellWidget in rowNode.getChildren().widgets(for: backend) {
                    let cellContainer = backend.createContainer()
                    backend.insert(cellWidget, into: cellContainer, at: 0)
                    children.cellContainerWidgets.append(AnyWidget(cellContainer))
                }
            }
        }

        // Update row nodes
        for (node, content) in zip(children.rowNodes, children.rowContent) {
            // TODO: Figure out if this is required
            // This doesn't update the row's cells. It just updates the view
            // instance stored in the row's ViewGraphNode
            _ = node.computeLayout(
                with: content,
                proposedSize: .zero,
                environment: environment
            )
        }

        // TODO: Compute a proper ideal size for tables. Look to SwiftUI to see what it does.
        //
        // ~~`let columnWidth = (proposedSize.width ?? 0) / Double(columnCount)`~~
        // -- a flat average, kept struck through because it is what
        // `TableColumn.width` exists to replace and because a reader comparing
        // against SwiftUI should see what this used to do. Every column got the
        // same space whatever it held, and there was no way to say otherwise.
        //
        // Sized columns take what they asked for; the rest divide the REMAINDER.
        // `max(0,)` on the remainder, because a table narrower than the sum of
        // its fixed widths would otherwise hand the flexible columns a negative
        // proposal, and a negative proposed width is not a smaller cell -- it is
        // a value the layout system has no meaning for.
        //
        // 此處原為 `(proposedSize.width ?? 0) / Double(columnCount)` ——一個平均值,劃線保留,
        // 因為那正是 `TableColumn.width` 要取代的東西,也因為對照 SwiftUI 的讀者應該看得到它
        // 原本的行為:無論欄裡裝什麼,每一欄都拿到相同的空間,而且沒有辦法改變。
        //
        // **有指定寬度的欄拿走它所要求的,其餘的瓜分剩下的部分。** 剩餘量取 `max(0,)`,因為當表格
        // 比其固定寬度總和還窄時,彈性欄會拿到一個**負的**提議寬度——而負的提議寬度並不是一個更小的
        // 儲存格,那是一個版面系統沒有意義可賦予的值。
        let columnWidths = columns.columnWidths
        let totalWidth = proposedSize.width ?? 0
        let fixedWidth = columnWidths.compactMap { $0 }.reduce(0, +)
        let flexibleCount = columnWidths.filter { $0 == nil }.count
        let flexibleWidth =
            flexibleCount > 0
            ? max(0, totalWidth - fixedWidth) / Double(flexibleCount)
            : 0

        // Compute cell layouts. Really only done during this initial layout
        // step to propagate cell preference values. Otherwise we'd do it
        // during commit.
        var rowHeights: [Int] = []
        let rows = zip(children.rowNodes, children.rowContent)
        for (rowNode, content) in rows {
            let rowCells = content.layoutableChildren(
                backend: backend,
                children: rowNode.getChildren()
            )

            var rowCellHeights: [Int] = []
            for (columnIndex, rowCell) in rowCells.enumerated() {
                // Indexed against `columnWidths` rather than zipped, because a
                // row can hold fewer cells than there are columns and the width
                // for a column that has no cell here must not shift onto the
                // next one. Out of range falls back to the flexible share.
                // 以索引對 `columnWidths` 取值而非用 zip,因為一列可能持有比欄數更少的儲存格,
                // 而某個「此列沒有儲存格」的欄,其寬度不可以順移到下一個儲存格上。
                // 超出範圍時退回彈性分配的份額。
                let width =
                    columnIndex < columnWidths.count
                    ? (columnWidths[columnIndex] ?? flexibleWidth)
                    : flexibleWidth
                let cellResult = rowCell.computeLayout(
                    proposedSize: ProposedViewSize(
                        width,
                        Double(backend.defaultTableRowContentHeight)
                    ),
                    environment: environment
                )
                cellResults.append(cellResult)
                rowCellHeights.append(cellResult.size.vector.y)
            }

            let rowHeight =
                max(
                    rowCellHeights.max() ?? 0,
                    backend.defaultTableRowContentHeight
                ) + backend.defaultTableCellVerticalPadding * 2

            rowHeights.append(rowHeight)
        }
        children.rowHeights = rowHeights

        return ViewLayoutResult(
            size: size.replacingUnspecifiedDimensions(by: .zero),
            childResults: cellResults
        )
    }

    @CastBackend<BackendFeatures.Tables>
    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: TableViewChildren<RowContent.RowContent>,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        let columnLabels = columns.labels
        backend.setRowCount(ofTable: widget, to: rows.count)
        backend.setColumnLabels(ofTable: widget, to: columnLabels, environment: environment)
        // AFTER the labels, because that call is what establishes the column
        // count -- a backend told widths first would have nowhere to put them.
        // 在 labels 之後,因為那個呼叫才是確立欄數的地方——先被告知寬度的 backend 會無處安放它們。
        backend.setColumnWidths(ofTable: widget, to: columns.columnWidths)
        // Before the cells, so that a backend applying selectability as cells
        // arrive sees the setting rather than having to revisit them.
        backend.setTextSelectability(ofTable: widget, to: environment.tableTextSelection)

        // TODO: Avoid overhead of converting `cellContainerWidgets` to
        //   `[AnyWidget]` and back again all the time.
        backend.setCells(
            ofTable: widget,
            to: children.cellContainerWidgets.map { $0.into() },
            withRowHeights: children.rowHeights
        )

        let columnCount = columnLabels.count
        for (rowIndex, rowHeight) in children.rowHeights.enumerated() {
            let rowCells = children.rowContent[rowIndex].layoutableChildren(
                backend: backend,
                children: children.rowNodes[rowIndex].getChildren()
            )

            for (columnIndex, cell) in rowCells.enumerated() {
                let index = rowIndex * columnCount + columnIndex
                let cellSize = cell.commit()
                backend.setPosition(
                    ofChildAt: 0,
                    in: children.cellContainerWidgets[index].into(),
                    to: SIMD2(0, (rowHeight - cellSize.size.vector.y) / 2)
                )
            }
        }

        backend.setSize(of: widget, to: layout.size.vector)

        // **After the cells, and that ordering is load-bearing on both backends
        // implemented so far.** Both rebuild their whole grid in `setCells`, so
        // a highlight applied before it is applied to cells that are about to be
        // thrown away. Selecting last means the backend is placing the highlight
        // on the cells the user will actually see.
        //
        // The handler is installed on every commit rather than once, matching
        // `List`. That puts the requirement on the backend -- replace the stored
        // closure, never add a subscription -- and the protocol says so.
        //
        // **在儲存格之後,而這個順序在目前已實作的兩個 backend 上都是關鍵。** 兩者都在 `setCells`
        // 裡整份重建自己的 grid,因此在它之前套用的高亮,會被套在「即將被丟掉」的儲存格上。
        // 放在最後,才是把高亮放在使用者真正會看到的那些儲存格上。
        //
        // handler 每次 commit 都重新安裝、而非只裝一次,與 `List` 一致。這把要求放到 backend 身上
        // ——**取代**所存的 closure、絕不新增訂閱——而協定裡寫明了這件事。
        if let selection, let selectable = backend as? any BackendFeatures.TableSelection {
            func installSelection<S: BackendFeatures.TableSelection>(_ backend: S) {
                let table = widget as! S.Widget
                backend.setSelectionHandler(ofTable: table) { selectedRow in
                    selection.wrappedValue = selectedRow
                }
                backend.setSelectedRow(ofTable: table, to: selection.wrappedValue)
            }
            installSelection(selectable)
        }

        // **The direction flip lives here, not in the backend.** Every backend
        // would otherwise implement the same three lines -- same column flips,
        // different column starts ascending -- and they would drift. The
        // backend's job is to say which header was clicked.
        //
        // **方向的翻轉放在這裡,不放在 backend。** 否則每一個 backend 都要實作同樣的三行
        // ——同一欄就翻轉、不同欄就從遞增開始——而它們會各自漂移。backend 的職責是說出
        // 「哪一個標題被點了」。
        if let sortOrder, let sortable = backend as? any BackendFeatures.TableColumnSorting {
            func installSorting<S: BackendFeatures.TableColumnSorting>(_ backend: S) {
                let table = widget as! S.Widget
                backend.setSortHandler(ofTable: table) { column in
                    sortOrder.wrappedValue =
                        sortOrder.wrappedValue?.toggled(byClicking: column)
                        ?? TableSortOrder(column: column)
                }
                backend.setSortIndicator(
                    ofTable: table,
                    column: sortOrder.wrappedValue?.column,
                    ascending: sortOrder.wrappedValue?.ascending ?? true
                )
            }
            installSorting(sortable)
        }
    }
}

class TableViewChildren<RowContent: View>: ViewGraphNodeChildren {
    var rowNodes: [AnyViewGraphNode<RowView<RowContent>>] = []
    var cellContainerWidgets: [AnyWidget] = []
    var rowHeights: [Int] = []
    var rowContent: [RowView<RowContent>] = []

    /// Not used, just a protocol requirement.
    var widgets: [AnyWidget] {
        rowNodes.map(\.widget)
    }

    var erasedNodes: [ErasedViewGraphNode] {
        rowNodes.map(ErasedViewGraphNode.init(wrapping:))
    }

    init() {
        rowNodes = []
        cellContainerWidgets = []
    }
}

/// An empty view that simply manages a row's children. Not intended to be rendered directly.
struct RowView<Content: View>: View {
    var body: Content

    init(_ content: Content) {
        self.body = content
    }

    func layoutableChildren<Backend: BaseAppBackend>(
        backend: Backend,
        children: any ViewGraphNodeChildren
    ) -> [LayoutSystem.LayoutableChild] {
        body.layoutableChildren(backend: backend, children: children)
    }

    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> any ViewGraphNodeChildren {
        body.children(backend: backend, snapshots: snapshots, environment: environment)
    }

    func asWidget<Backend: BaseAppBackend>(
        _ children: any ViewGraphNodeChildren,
        backend: Backend
    ) -> Backend.Widget {
        return backend.createContainer()
    }

    func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: any ViewGraphNodeChildren,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        return ViewLayoutResult.leafView(size: .zero)
    }

    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: any ViewGraphNodeChildren,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {}
}
