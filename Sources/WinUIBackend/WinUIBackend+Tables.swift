@_spi(Backends) import SwiftCrossUI
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
    private var rowCount = 0

    /// Kept so `setCells` can put them back. Every `setCells` clears the
    /// children -- tracking which ones to remove individually is more state
    /// than rebuilding costs -- and the headers are children too, so without
    /// this they would disappear on the first data update.
    /// 保留下來，好讓 `setCells` 能把它們放回去。每次 `setCells` 都會清空所有子元件——逐一追蹤該移除
    /// 哪些，其狀態成本高於重建——而表頭本身也是子元件，因此少了這個陣列，它們會在第一次資料更新時
    /// 消失。
    private var headerLabels: [WinUI.TextBlock] = []
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

        columnDefinitions.clear()
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

        rebuildChildren(rowHeights: [])
    }

    // `WinUI.FrameworkElement`, not `Widget`. `Widget` is a typealias on
    // `WinUIBackend`, so it resolves inside an extension of that type and not
    // inside this class.
    // 使用 `WinUI.FrameworkElement` 而非 `Widget`。`Widget` 是 `WinUIBackend` 上的 typealias，因此
    // 它只在該型別的 extension 之中解析得到，在本類別之中則否。
    func setCells(_ cells: [WinUI.FrameworkElement], rowHeights: [Int]) {
        cellWidgets = cells
        rebuildRowDefinitions(rowHeights: rowHeights)
        rebuildChildren(rowHeights: rowHeights)
        applyTextSelectability()
    }

    func setTextSelectable(_ isSelectable: Bool) {
        isTextSelectable = isSelectable
        applyTextSelectability()
    }

    // ─────────────────────────────────────────────────────────────────────────

    private func rebuildRowDefinitions(rowHeights: [Int]) {
        rowDefinitions.clear()

        // Row 0 is the header and sizes to its own content; data rows take the
        // height SwiftCrossUI computed for them.
        // 第 0 列是表頭，依其自身內容決定高度；資料列則採用 SwiftCrossUI 為它們算好的高度。
        let header = WinUI.RowDefinition()
        header.height = WinUI.GridLength(value: 0, gridUnitType: .auto)
        rowDefinitions.append(header)

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
        }
    }

    private func rebuildChildren(rowHeights: [Int]) {
        children.clear()

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
