import UIKit

@_spi(Backends) import SwiftCrossUI

/// A table laid out in `layoutSubviews`, for the reason WinUIBackend uses a
/// `Grid` and GtkBackend a `GtkGrid`.
///
/// A table is the one place where SwiftCrossUI does *not* hand the backend a
/// position for each child: `setCells` supplies a flat array grouped by row
/// plus the row heights, and arranging that into columns is the backend's job.
///
/// The ordering is what rules out doing it in `setCells` itself. `Table.commit`
/// calls `setCells` **before** `setSize(of: table)`, so at the moment the cells
/// arrive the total width is not known yet. WinUI resolves star columns when
/// the `Grid` is measured; UIKit's equivalent moment is `layoutSubviews`, which
/// runs after a size has been assigned. So the cells are stored on arrival and
/// positioned later.
///
/// 於 `layoutSubviews` 中排版的表格，理由與 WinUIBackend 使用 `Grid`、GtkBackend 使用 `GtkGrid`
/// 相同。
///
/// 表格是 SwiftCrossUI **唯一**不為每個子元件交出位置的地方：`setCells` 提供的是依列分組的扁平
/// 陣列與各列高度，而把它排成欄是 backend 自己的工作。
///
/// 真正排除「在 `setCells` 內完成排版」的是呼叫順序。`Table.commit` 呼叫 `setCells` 的時機**早於**
/// `setSize(of: table)`，因此在 cell 抵達的當下，總寬度尚未可知。WinUI 是在 `Grid` 被 measure 時
/// 解析 star 欄；UIKit 的對應時機是 `layoutSubviews`，它在尺寸被指派之後才執行。所以 cell 抵達時
/// 先存起來，稍後再定位。
final class TableWidget: BaseViewWidget {
    private var headerLabels: [UILabel] = []
    private var cells: [UIView] = []
    private var rowHeights: [Int] = []
    private var columnCount = 0

    /// Kept because the header occupies a row that is not in `rowHeights`.
    /// 保留此值，因為表頭佔用了一列，而該列並不在 `rowHeights` 之中。
    private let headerHeight: CGFloat = 24

    func setColumnLabels(_ labels: [String], environment: EnvironmentValues) {
        headerLabels.forEach { $0.removeFromSuperview() }
        headerLabels = labels.map { text in
            let label = UILabel()
            label.attributedText = UIKitBackend.attributedString(
                text: text,
                environment: environment,
                defaultForegroundColor: .label
            )
            addSubview(label)
            return label
        }
        columnCount = labels.count
        setNeedsLayout()
    }

    // `[any WidgetProtocol]`, not `[Widget]`. `Widget` is a typealias on
    // UIKitBackend, so it is not in scope inside this class -- the same name
    // resolves in the extension below and not here.
    // 使用 `[any WidgetProtocol]` 而非 `[Widget]`。`Widget` 是 UIKitBackend 上的 typealias，
    // 因此在本 class 內不在 scope——同一個名稱在下方的 extension 中可解析，在此處則否。
    func setCells(_ newCells: [any WidgetProtocol], rowHeights newRowHeights: [Int]) {
        // Removed from the view, not just dropped from the array. A cell whose
        // widget the view graph has replaced stays on screen otherwise, drawn
        // over its successor at whatever position it last had.
        // 從 view 中移除，而不只是從陣列中丟棄。否則，view graph 已替換掉其 widget 的 cell 仍會留在
        // 畫面上，以它最後所在的位置覆蓋在後繼者之上。
        cells.forEach { $0.removeFromSuperview() }
        cells = newCells.map { widget in
            let view = widget.view!
            addSubview(view)
            return view
        }
        rowHeights = newRowHeights
        setNeedsLayout()
    }

    func setTextSelectable(_ isSelectable: Bool) {
        // UILabel has no selection. A table of labels cannot offer text
        // selection without becoming a table of UITextViews, which changes
        // every cell's metrics and scrolling behaviour for a feature the
        // protocol makes optional -- its default implementation is empty.
        // Recorded rather than silently ignored.
        // UILabel 沒有選取功能。要讓一個由 label 構成的表格支援文字選取，就必須改成由 UITextView
        // 構成，那會改變每一個 cell 的度量與捲動行為——而 protocol 把這項功能定為選用，其預設實作
        // 是空的。此處記錄下來，而非默默忽略。
        _ = isSelectable
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        guard columnCount > 0 else { return }

        // Equal columns, which is what a star-sized Grid gives WinUI. The
        // protocol carries no column widths, so any other division would be
        // this backend inventing a policy the others do not share.
        // 等寬欄位，那正是 star 尺寸的 Grid 給 WinUI 的結果。protocol 並未帶有欄寬資訊，因此任何
        // 其他分法，都會是本 backend 自行發明一套其他 backend 並不共有的策略。
        let columnWidth = bounds.width / CGFloat(columnCount)

        for (index, label) in headerLabels.enumerated() {
            label.frame = CGRect(
                x: CGFloat(index) * columnWidth,
                y: 0,
                width: columnWidth,
                height: headerHeight
            )
        }

        var y = headerHeight
        for row in 0..<rowHeights.count {
            let height = CGFloat(rowHeights[row])
            for column in 0..<columnCount {
                let index = row * columnCount + column
                // The flat array is grouped by row, so the index arithmetic is
                // row-major. A shorter-than-expected array is not an error
                // worth trapping on: the view graph can call setCells with a
                // count that has not caught up with setRowCount yet.
                // 扁平陣列是依列分組的，因此索引運算為 row-major。陣列比預期短並不是值得中止的錯誤：
                // view graph 可能以「尚未跟上 setRowCount」的數量呼叫 setCells。
                guard index < cells.count else { break }
                cells[index].frame = CGRect(
                    x: CGFloat(column) * columnWidth,
                    y: y,
                    width: columnWidth,
                    height: height
                )
            }
            y += height
        }
    }
}

extension UIKitBackend: BackendFeatures.Tables {
    public func createTable() -> Widget {
        TableWidget()
    }

    public func setRowCount(ofTable table: Widget, to rows: Int) {
        // Nothing to do. The row count arrives again as the length of
        // `rowHeights` in `setCells`, which is the call that can act on it --
        // this one has no cells to arrange yet. GtkBackend needs it because a
        // GtkGrid is sized before it is filled; this table is sized by the
        // layout system either way.
        // 無事可做。列數會在 `setCells` 中以 `rowHeights` 的長度再次抵達，而那才是能據以行動的呼叫
        // ——此處尚無任何 cell 可供排列。GtkBackend 需要它，是因為 GtkGrid 在被填入之前就要決定尺寸；
        // 而本表格無論如何都是由版面系統決定尺寸的。
        _ = (table, rows)
    }

    public func setColumnLabels(
        ofTable table: Widget,
        to labels: [String],
        environment: EnvironmentValues
    ) {
        (table as! TableWidget).setColumnLabels(labels, environment: environment)
    }

    public func setCells(
        ofTable table: Widget,
        to cells: [Widget],
        withRowHeights rowHeights: [Int]
    ) {
        (table as! TableWidget).setCells(cells, rowHeights: rowHeights)
    }

    public func setTextSelectability(ofTable table: Widget, to isSelectable: Bool) {
        (table as! TableWidget).setTextSelectable(isSelectable)
    }
}
