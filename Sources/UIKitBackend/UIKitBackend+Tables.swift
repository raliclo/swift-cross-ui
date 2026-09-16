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

    // MARK: Row selection (#125)

    /// The highlight, kept as a view rather than drawn.
    ///
    /// **A subview, because the cells are subviews.** Drawing the band in
    /// `draw(_:)` would put it under everything this view draws itself, which
    /// is nothing -- the cells are separate views and would still cover it or
    /// not depending on their own opacity. A sibling sent to the back sits
    /// behind the cells by the same rule that orders every other view here,
    /// and it survives `setCells` removing and re-adding every cell.
    ///
    /// 那道高亮,做成一個 view,而不是畫出來的。
    ///
    /// **做成 subview,是因為 cell 就是 subview。** 在 `draw(_:)` 裡畫出這條色帶,會把它放在
    /// 「這個 view 自己畫的東西」之下——而它自己什麼也沒畫;cell 是獨立的 view,會不會蓋住它
    /// 仍取決於它們自身的不透明度。一個被送到最底層的同層 view,是依「此處其餘每個 view 所遵循的
    /// 同一條規則」坐在 cell 後面的,而且它能撐過 `setCells` 把每一個 cell 移除再加回來。
    private let selectionHighlight = UIView()

    private var selectedRow: Int?
    private var selectionHandler: ((Int?) -> Void)?
    private var tapRecognizer: UITapGestureRecognizer?

    /// The sort arrow, one label moved between columns rather than one per
    /// column.
    ///
    /// Only one column is sorted at a time, so per-column labels would be a set
    /// of hidden views maintained in step with a column count that changes on
    /// every `setColumnLabels`. Moving one is less to keep correct.
    ///
    /// **Not appended to the header's own text.** `setColumnLabels` rebuilds
    /// every header label from the environment on every commit, so an arrow
    /// baked into the string would be erased by the next update and would also
    /// have to be stripped back out before the next one -- a round trip through
    /// text that has nothing to do with what is being asked.
    ///
    /// 那個排序箭頭:一個 label 在欄位之間移動,而不是每欄一個。
    ///
    /// 同一時間只有一欄被用來排序,因此「每欄一個 label」會是一組隱藏的 view,還得跟著一個
    /// 「每次 `setColumnLabels` 都會變」的欄數保持同步。移動一個,要維持正確的東西比較少。
    ///
    /// **不是附加在標題自己的文字上。** `setColumnLabels` 每次 commit 都會依 environment 重建每一個
    /// 標題 label,因此被烤進字串裡的箭頭會被下一次更新抹掉,而且在那之前還得先被剝除——那是一趟
    /// 與「被問的問題」毫無關係的文字往返。
    private let sortIndicator = UILabel()

    private var sortColumn: Int?
    private var sortAscending = true
    private var sortHandler: ((Int) -> Void)?

    /// Installs the tap recogniser once, and replaces the handler every time.
    ///
    /// The split matters because `Table.commit` calls this on every commit. A
    /// recogniser added each time would deliver one tap as many taps as there
    /// had been frames; a handler added rather than replaced would write the
    /// binding just as many times. The protocol asks for replacement, and the
    /// recogniser is the part that must not be replaced with it.
    ///
    /// 只安裝一次 tap recogniser,而每一次都取代 handler。
    ///
    /// 這個區分很重要,因為 `Table.commit` 每一次 commit 都會呼叫這裡。每次都加一個 recogniser,
    /// 會讓一次點擊被送成「有過幾幀」那麼多次;而一個被**追加**而非取代的 handler,則會往 binding
    /// 寫同樣多次。協定要求的是取代,而 recogniser 正是那個不可以跟著被取代的部分。
    func setSelectionHandler(_ handler: @escaping (Int?) -> Void) {
        selectionHandler = handler
        ensureTapRecognizer()
    }

    /// One recogniser for both channels.
    ///
    /// Hoisted out of `setSelectionHandler` when sorting arrived, because a
    /// table given `sortOrder:` and no `selection:` needs taps and would
    /// otherwise have had none -- and the failure would have been silent, a
    /// header that simply never responded with every line of sorting code
    /// present and correct.
    /// 一個 recogniser 服務兩條通道。
    ///
    /// 排序加進來時把它從 `setSelectionHandler` 裡提出來,因為一個只給了 `sortOrder:`、沒有給
    /// `selection:` 的表格也需要點擊,否則它一個都不會有——而那個失敗會是無聲的:一個從不反應的標題,
    /// 而所有排序程式碼都在、也都正確。
    private func ensureTapRecognizer() {
        guard tapRecognizer == nil else { return }
        let recognizer = UITapGestureRecognizer(
            target: self,
            action: #selector(handleSelectionTap)
        )
        addGestureRecognizer(recognizer)
        tapRecognizer = recognizer
    }

    func setSortHandler(_ handler: @escaping (Int) -> Void) {
        sortHandler = handler
        ensureTapRecognizer()
    }

    func setSortIndicator(column: Int?, ascending: Bool) {
        guard sortColumn != column || sortAscending != ascending else { return }
        sortColumn = column
        sortAscending = ascending
        setNeedsLayout()
    }

    func setSelectedRow(_ index: Int?) {
        guard selectedRow != index else { return }
        selectedRow = index
        setNeedsLayout()
    }

    /// Turns a tap's position into a row, or into a deselection.
    ///
    /// **A tap on the header, or below the last row, means nothing selected**
    /// rather than nothing happened. That is the only way to clear a selection
    /// by hand on a table with no keyboard, and it is what AppKit does with a
    /// click in the same places.
    ///
    /// 把一次點擊的位置變成一個列號,或變成一次取消選取。
    ///
    /// **點在表頭上、或點在最後一列下方,意思是「沒有選取任何一列」**,而不是「什麼也沒發生」。
    /// 在一個沒有鍵盤的表格上,那是唯一能用手清掉選取的方式,而 AppKit 對同樣位置的點擊也正是
    /// 這麼做的。
    @objc private func handleSelectionTap(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: self)

        // The header belongs to sorting when sorting was asked for, and to
        // deselection otherwise. Not both: a tap that sorted AND cleared the
        // selection would make the selection impossible to keep while
        // reordering, which is the one time a user most wants to keep it.
        // 當有人要求排序時,標題列歸排序所有;否則歸取消選取。不會兩者都做:一次「又排序又清掉選取」
        // 的點擊,會讓「重新排序時保住選取」變成做不到的事——而那正是使用者最想保住它的時刻。
        if point.y < headerHeight, let sortHandler, let column = column(atX: point.x) {
            sortHandler(column)
            return
        }
        selectionHandler?(row(atY: point.y))
    }

    /// Which header the tap landed on.
    ///
    /// **A column, not a decision.** The first version of this returned the
    /// next `TableSortOrder`, which meant this backend carried its own copy of
    /// the rule that a second click on the same column reverses -- and so did
    /// the Android one, while AppKit got it from `NSTableView`. Three copies of
    /// one rule, in a place where a difference between them would show up as a
    /// header that behaves differently on one platform. The published protocol
    /// asks only which header was clicked and applies
    /// ``TableSortOrder/toggled(byClicking:)`` once, in the framework.
    ///
    /// 這次點擊落在哪一個標題上。
    ///
    /// **是一個欄位,不是一個決定。** 這個方法的第一版回傳的是下一個 `TableSortOrder`,那代表這個
    /// backend 自己帶了一份「在同一欄上點第二次會反轉」的規則副本——Android 那個也帶了一份,而
    /// AppKit 是從 `NSTableView` 拿的。同一條規則有三份副本,而它們之間的差異,會以「某個平台上的
    /// 標題行為不一樣」的形式現身。已發布的協定只問「哪一個標題被點了」,並在框架裡套用
    /// ``TableSortOrder/toggled(byClicking:)`` 一次。
    private func column(atX x: CGFloat) -> Int? {
        guard columnCount > 0 else { return nil }
        let columnWidth = bounds.width / CGFloat(columnCount)
        return min(columnCount - 1, max(0, Int(x / columnWidth)))
    }

    /// Places the arrow, or hides it.
    ///
    /// Right-aligned inside the sorted column's header cell, which is where
    /// AppKit puts its triangle -- the two platforms should not disagree about
    /// where a reader's eye goes for the same fact.
    /// 放好那個箭頭,或把它藏起來。
    ///
    /// 在被排序那一欄的標題格內靠右對齊,那正是 AppKit 放它三角形的位置——同一件事實,兩個平台
    /// 不該讓讀者的視線落在不同的地方。
    private func layoutSortIndicator() {
        if sortIndicator.superview !== self {
            sortIndicator.isUserInteractionEnabled = false
            sortIndicator.textAlignment = .right
            addSubview(sortIndicator)
        }
        // Front, every pass, for the mirror of the reason the highlight goes to
        // the back: `setColumnLabels` re-adds every header label, and each one
        // lands above whatever was there before -- including this.
        // 每一輪都送到最上層,理由與那道高亮被送到最底層恰好互為鏡像:`setColumnLabels` 會把每一個
        // 標題 label 重新加入,而它們每一個都會落在原有內容之上——包括這個箭頭。
        bringSubviewToFront(sortIndicator)

        guard let sortColumn, columnCount > 0, sortColumn < columnCount else {
            sortIndicator.isHidden = true
            return
        }
        sortIndicator.isHidden = false
        sortIndicator.text = sortAscending ? "▲" : "▼"
        sortIndicator.font = .systemFont(ofSize: 10)
        sortIndicator.textColor = .label

        let columnWidth = bounds.width / CGFloat(columnCount)
        sortIndicator.frame = CGRect(
            x: CGFloat(sortColumn) * columnWidth,
            y: 0,
            width: columnWidth - 4,
            height: headerHeight
        )
    }

    private func row(atY y: CGFloat) -> Int? {
        guard y >= headerHeight else { return nil }
        var top = headerHeight
        for (index, height) in rowHeights.enumerated() {
            let bottom = top + CGFloat(height)
            if y < bottom { return index }
            top = bottom
        }
        return nil
    }

    /// Places the band, or hides it.
    ///
    /// Called from `layoutSubviews` rather than from `setSelectedRow`, because
    /// a row's position is only known once the widths and heights for this
    /// pass are in -- the same reason the cells are positioned there.
    /// 放好色帶,或把它藏起來。
    ///
    /// 從 `layoutSubviews` 呼叫,而不是從 `setSelectedRow`——因為一列的位置要等到這一輪的寬高
    /// 都到齊才知道,理由與 cell 也在那裡定位相同。
    private func layoutSelectionHighlight() {
        if selectionHighlight.superview !== self {
            selectionHighlight.isUserInteractionEnabled = false
            addSubview(selectionHighlight)
        }
        // Back, every pass. `setCells` re-adds every cell, and each of those
        // lands above whatever was there before.
        // 每一輪都送到最底層。`setCells` 會把每一個 cell 重新加入,而它們每一個都會落在原有內容之上。
        sendSubviewToBack(selectionHighlight)

        guard let selectedRow, selectedRow >= 0, selectedRow < rowHeights.count else {
            selectionHighlight.isHidden = true
            return
        }
        selectionHighlight.isHidden = false
        // The view's own tint, not a colour chosen here. It follows the app's
        // accent and the user's appearance settings, which a literal would not.
        // 用這個 view 自己的 tint,而不是在此挑一個顏色。它會跟隨 app 的 accent 與使用者的外觀設定,
        // 而一個寫死的字面值不會。
        selectionHighlight.backgroundColor = tintColor.withAlphaComponent(0.25)

        var top = headerHeight
        for index in 0..<selectedRow {
            top += CGFloat(rowHeights[index])
        }
        selectionHighlight.frame = CGRect(
            x: 0,
            y: top,
            width: bounds.width,
            height: CGFloat(rowHeights[selectedRow])
        )
    }

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

        // Before the `columnCount` guard. A table whose columns have not
        // arrived yet still has a selection to clear, and leaving the band
        // where it was would leave a highlight over a table that no longer has
        // the row it belonged to.
        // 放在 `columnCount` 的 guard 之前。一個欄位尚未抵達的表格,仍然有一個需要被清掉的選取;
        // 把色帶留在原處,會讓高亮停在一個「已經沒有那一列」的表格上。
        layoutSelectionHighlight()
        layoutSortIndicator()

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
