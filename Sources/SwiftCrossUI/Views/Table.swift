/// A container that presents rows of data arranged in columns.
public struct Table<RowValue, RowContent: TableRowContent<RowValue>>: TypeSafeView, View {
    typealias Children = TableViewChildren<RowContent.RowContent>

    public var body = EmptyView()

    /// The row data to display.
    private var rows: [RowValue]
    /// The columns to display (which each compute their cell values when given
    /// ``Table/Row`` instances).
    private var columns: RowContent

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
