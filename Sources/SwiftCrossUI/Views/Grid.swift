/// A container that arranges ``GridRow``s one above another.
///
/// Composed from `VStack` and `HStack`, so it needs nothing from any backend.
/// See ``Stepper`` for why this batch was chosen.
///
/// **Columns ARE aligned across rows, since #120.** Every cell in column two
/// starts at the same x, whatever the first column holds, because the grid
/// measures every row before it places any of them. This paragraph used to say
/// the opposite, and said it loudly, because a ragged table compiles and
/// appears and simply is not a grid.
///
/// How it gets the measurements is worth knowing before extending this: a
/// parent cannot see its grandchildren. `ViewLayoutResult` takes `childResults`
/// in an initialiser and keeps only the merged preferences, so the cells report
/// themselves upward through ``PreferenceValues/gridRowCells`` and the grid
/// unpacks that. See ``GridRowMeasurement``.
///
/// **A cell that is a `ForEach` counts as ONE cell**, which is the same shape
/// `GridRow`'s own children have always had. `LazyVGrid` solves the opposite
/// problem -- one child that owns many cells -- by handing the plan down to
/// `ForEach`; a `Grid` cannot, because the number of columns is decided by all
/// the rows together and a `ForEach` inside one row does not know about the
/// others. Use ``LazyVGrid`` when the cells are generated, and ``Grid`` for the
/// fixed table it is for.
///
/// 一個把 ``GridRow`` 由上而下依序排列的容器。
///
/// 由 `VStack` 與 `HStack` 組合而成，不需要任何 backend 支援。本批工作為何如此挑選，見 ``Stepper``。
///
/// **自 #120 起，各欄在列與列之間是對齊的。** 無論第一欄裝著什麼，每一列的第二欄都從同一個 x 開始，
/// 因為這個格線會在放置任何一列之前，先量測每一列。本段過去說的是相反的話、而且說得很大聲——因為
/// 一張參差不齊的表編得過、顯示得出來，而它就是不是一個格線。
///
/// 在擴充本型別之前，值得知道它是怎麼取得那些量測的:父層看不見它的孫節點。`ViewLayoutResult` 只在
/// initialiser 中接收 `childResults`，保留下來的只有合併後的 preferences，因此是由儲存格經
/// ``PreferenceValues/gridRowCells`` 自行向上回報，再由格線拆開。見 ``GridRowMeasurement``。
///
/// **一個身為 `ForEach` 的儲存格算作一格**，而那與 `GridRow` 自身子節點一向的形狀相同。`LazyVGrid`
/// 解的是相反的問題——一個持有許多儲存格的子節點——它把計畫交給 `ForEach`;而 `Grid` 做不到，因為
/// 欄數是由**所有列共同**決定的，而某一列裡的 `ForEach` 並不知道其他列。儲存格是被生成的，用
/// ``LazyVGrid``;而 ``Grid`` 就用在它本來要處理的那種固定表格上。
///
public struct Grid<Content: View>: View {
    static var defaultSpacing: Int { 10 }

    public var body: Content
    private let alignment: Alignment
    private let horizontalSpacing: Int?
    private let verticalSpacing: Int?

    /// Creates a grid with the given alignment and spacings.
    ///
    /// - Parameters:
    ///   - alignment: How each cell is aligned within its own space. The
    ///     horizontal component aligns the rows within the grid; the vertical
    ///     component becomes each row's default cell alignment, which a
    ///     ``GridRow`` may override.
    ///   - horizontalSpacing: The spacing between cells within a row.
    ///   - verticalSpacing: The spacing between rows.
    ///   - content: The grid's rows.
    public init(
        alignment: Alignment = .center,
        horizontalSpacing: Int? = nil,
        verticalSpacing: Int? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
        self.body = content()
    }

    var columnSpacing: Int { horizontalSpacing ?? Self.defaultSpacing }
    var rowSpacing: Int { verticalSpacing ?? Self.defaultSpacing }

    public func asWidget<Backend: BaseAppBackend>(
        _ children: any ViewGraphNodeChildren,
        backend: Backend
    ) -> Backend.Widget {
        let container = backend.createContainer()
        for (index, child) in children.widgets(for: backend).enumerated() {
            backend.insert(child, into: container, at: index)
        }
        return container
    }

    /// Measures every row, decides the columns, then lays the rows out again.
    ///
    /// **Two passes in ONE update, not one pass repeated.** The grid drives its
    /// own rows' `computeLayout`, so it can call them twice before it returns,
    /// and no re-layout has to be requested from anywhere. That is the whole
    /// reason this was buildable here while `GeometryProxy.frame(in: .global)`
    /// was not: positions are a commit-time fact, and cell widths are not.
    ///
    /// 先量測每一列、決定各欄，然後把各列重新排一次。
    ///
    /// **是在**同一次**更新裡跑兩輪，而不是把一輪重複兩次。** 這個格線自己驅動它那些列的
    /// `computeLayout`，因此它可以在回傳之前呼叫它們兩次，不需要向任何地方請求重新版面。這正是
    /// 「本項在此處做得出來、而 `GeometryProxy.frame(in: .global)` 做不出來」的全部原因:位置是
    /// commit 時才成立的事實，而儲存格寬度不是。
    public func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: any ViewGraphNodeChildren,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        let rows = layoutableChildren(backend: backend, children: children)
        let rowEnvironment =
            environment
            .with(\.gridHorizontalSpacing, columnSpacing)
            .with(\.gridRowAlignment, alignment.vertical)

        // Pass one: nothing constrains the cells, so what they report is what
        // they would like to be.
        // 第一輪:沒有任何東西約束那些儲存格，因此它們回報的就是它們想要的大小。
        let measuringEnvironment = rowEnvironment.with(\.gridColumnWidths, nil)
        let measurements = rows.map { row -> GridRowMeasurement in
            let result = row.computeLayout(
                proposedSize: ProposedViewSize(nil, nil),
                environment: measuringEnvironment
            )
            // A child that is not a `GridRow` reports nothing, and is one cell.
            // A row nested in a row would report several; the first is this
            // row's own.
            // 一個不是 `GridRow` 的子節點什麼都不會回報，它就是一格。巢狀於列中的列會回報數項，
            // 而第一項是這一列自己的。
            return result.preferences.gridRowCells.first
                ?? GridRowMeasurement(
                    cells: [
                        GridRowMeasurement.Cell(
                            naturalWidth: result.size.width,
                            columnSpan: max(1, result.preferences.gridCellColumns)
                        )
                    ]
                )
        }

        let columns = Self.resolveColumns(from: measurements, spacing: columnSpacing)

        // Pass two: the same rows, now told what the columns are.
        // 第二輪:同樣那些列，這次告訴它們各欄是什麼。
        let placingEnvironment = rowEnvironment.with(\.gridColumnWidths, columns)
        let rowResults = rows.map { row in
            row.computeLayout(
                proposedSize: ProposedViewSize(
                    Self.width(of: columns, spacing: columnSpacing),
                    nil
                ),
                environment: placingEnvironment
            )
        }

        let height =
            rowResults.map(\.size.height).reduce(0, +)
            + Double(rowSpacing * max(0, rowResults.count - 1))
        return ViewLayoutResult(
            size: ViewSize(Self.width(of: columns, spacing: columnSpacing), height),
            childResults: rowResults
        )
    }

    public func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: any ViewGraphNodeChildren,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        let rows = layoutableChildren(backend: backend, children: children)
        let results = rows.map { $0.commit() }

        var y = 0
        for (index, result) in results.enumerated() {
            let rowWidth = Int(result.size.width.rounded(.up))
            let dx =
                switch alignment.horizontal {
                    case .leading: 0
                    case .center: (Int(layout.size.width.rounded(.up)) - rowWidth) / 2
                    case .trailing: Int(layout.size.width.rounded(.up)) - rowWidth
                }
            backend.setPosition(ofChildAt: index, in: widget, to: SIMD2(dx, y))
            y += Int(result.size.height.rounded(.up)) + rowSpacing
        }

        backend.setSize(of: widget, to: layout.size.vector)
    }

    /// The width a set of columns occupies, spacing included.
    /// 一組欄所佔的寬度，已含間距。
    static func width(of columns: [Double], spacing: Int) -> Double {
        columns.reduce(0, +) + Double(spacing * max(0, columns.count - 1))
    }

    /// Turns what the rows reported into one width per column.
    ///
    /// Single-column cells decide the widths; spanning cells are then given
    /// whatever they still lack, spread evenly across the columns they cover.
    /// Doing it in that order is what keeps a `gridCellColumns(3)` cell from
    /// inflating three columns that nothing else needed -- a spanning cell can
    /// only widen columns that were already too narrow FOR IT, and by the least
    /// that fixes that.
    ///
    /// 把各列回報的東西，變成「每一欄一個寬度」。
    ///
    /// 由單欄的儲存格決定各欄寬度；跨欄的儲存格接著才拿到它仍然缺少的部分，平均分攤到它所覆蓋的
    /// 那些欄上。依這個順序處理，正是「一個 `gridCellColumns(3)` 的儲存格不會把三個沒有別人需要
    /// 那麼寬的欄一起撐大」的原因——跨欄的儲存格只能撐大「對它而言本來就太窄」的欄，而且只撐大到
    /// 剛好足夠為止。
    static func resolveColumns(
        from rows: [GridRowMeasurement],
        spacing: Int
    ) -> [Double] {
        let columnCount = rows.map { row in
            row.cells.reduce(0) { $0 + $1.columnSpan }
        }.max() ?? 0
        guard columnCount > 0 else { return [] }

        var widths = [Double](repeating: 0, count: columnCount)

        for row in rows {
            var column = 0
            for cell in row.cells where column < columnCount {
                if cell.columnSpan == 1 {
                    widths[column] = max(widths[column], cell.naturalWidth)
                }
                column += cell.columnSpan
            }
        }

        for row in rows {
            var column = 0
            for cell in row.cells where column < columnCount {
                defer { column += cell.columnSpan }
                guard cell.columnSpan > 1 else { continue }
                let last = min(column + cell.columnSpan, columnCount)
                let covered = last - column
                guard covered > 0 else { continue }
                let have =
                    widths[column..<last].reduce(0, +)
                    + Double(spacing * max(0, covered - 1))
                let shortfall = cell.naturalWidth - have
                guard shortfall > 0 else { continue }
                let share = shortfall / Double(covered)
                for index in column..<last {
                    widths[index] += share
                }
            }
        }

        return widths
    }
}

/// One horizontal line of cells inside a ``Grid``.
///
/// Composed from `HStack`, so it needs nothing from any backend.
///
/// Its spacing is **not** a parameter, which matches SwiftUI: the spacing
/// between cells belongs to the grid, so that every row uses the same value and
/// one row cannot silently disagree with the rest. It arrives through the
/// environment from the enclosing ``Grid``. A `GridRow` used outside a `Grid` is
/// legal and simply falls back to the default `HStack` spacing.
///
/// Its `alignment` overrides only the vertical component of the grid's, again
/// matching SwiftUI -- a row decides how its own cells sit against one another,
/// and the grid decides where the rows sit.
///
/// ``Grid`` documents the divergence that matters here: cells are **not**
/// aligned into columns across rows. Read that before assuming a `GridRow`
/// lines up with the one above it.
///
/// `Grid` 之中的一列儲存格。
///
/// 由 `HStack` 組合而成，不需要任何 backend 支援。
///
/// 它的間距**不是**參數，這與 SwiftUI 一致：儲存格之間的間距屬於整個 grid，如此每一列才會採用同一
/// 個值，也不會有某一列悄悄與其餘各列不同。該值由外層的 ``Grid`` 經環境傳入。在 `Grid` 之外使用
/// `GridRow` 是合法的，此時它就退回 `HStack` 的預設間距。
///
/// 它的 `alignment` 只覆寫 grid 對齊方式中的垂直分量，同樣與 SwiftUI 一致——由列決定自己的儲存格
/// 彼此如何對齊，由 grid 決定各列位於何處。
///
/// 此處真正重要的差異記載於 ``Grid``：各列之間的儲存格**不會**對齊成欄。在假設某個 `GridRow` 會與
/// 它上方那一列對齊之前，請先讀該段說明。
public struct GridRow<Content: View>: View {
    @Environment(\.gridHorizontalSpacing) private var inheritedSpacing
    @Environment(\.gridRowAlignment) private var inheritedAlignment
    @Environment(\.gridColumnWidths) private var columnWidths

    public var body: Content
    private let alignment: VerticalAlignment?

    public init(
        alignment: VerticalAlignment? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.body = content()
    }

    var spacing: Int { inheritedSpacing ?? Grid<EmptyView>.defaultSpacing }
    var cellAlignment: VerticalAlignment { alignment ?? inheritedAlignment }

    public func asWidget<Backend: BaseAppBackend>(
        _ children: any ViewGraphNodeChildren,
        backend: Backend
    ) -> Backend.Widget {
        let container = backend.createContainer()
        for (index, child) in children.widgets(for: backend).enumerated() {
            backend.insert(child, into: container, at: index)
        }
        return container
    }

    /// Measures its cells, and then places them if it has been told the columns.
    ///
    /// **It measures in both passes rather than remembering the first one.** The
    /// span comes back on the cell's own layout result, so a cell has to be laid
    /// out before this row knows how wide to make it -- measure, then place. A
    /// remembered span would be a value from the previous update being used to
    /// size the current one, which is right until the moment somebody changes a
    /// `gridCellColumns` and gets last frame's table.
    ///
    /// 先量測它的儲存格；若已被告知各欄是什麼，則接著放置它們。
    ///
    /// **它在兩輪中都重新量測，而不是記住第一輪的結果。** 跨欄數是隨儲存格自身的版面結果回來的，
    /// 因此一個儲存格必須先被排一次，這一列才知道要把它做多寬——先量，再放。若把跨欄數記起來，
    /// 那就是拿上一次更新的值來決定這一次的尺寸:在有人改動某個 `gridCellColumns` 之前它都是對的，
    /// 而在那一刻，你會拿到上一幀的表。
    public func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: any ViewGraphNodeChildren,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        let cells = layoutableChildren(backend: backend, children: children)
        // Cleared for the cells: a `Grid` nested inside a cell describes its own
        // columns, and inheriting this row's would place its cells in them.
        // 為那些儲存格清除:巢狀於某一格內的 `Grid` 描述的是它自己的欄，若讓它繼承這一列的，
        // 它的儲存格就會被放進**這一列**的欄裡。
        let cellEnvironment = environment.with(\.gridColumnWidths, nil)

        let measured = cells.map { cell in
            cell.computeLayout(
                proposedSize: ProposedViewSize(nil, nil),
                environment: cellEnvironment
            )
        }
        let measurement = GridRowMeasurement(
            cells: measured.map { result in
                GridRowMeasurement.Cell(
                    naturalWidth: result.size.width,
                    columnSpan: max(1, result.preferences.gridCellColumns)
                )
            }
        )

        guard let columnWidths, !columnWidths.isEmpty else {
            // No columns yet: this is the measuring pass, or the row is being
            // used outside a `Grid`. Either way it behaves like an `HStack`,
            // which is what it always was.
            // 還沒有欄:這是量測那一輪，或這一列被用在 `Grid` 之外。無論哪一種，它的行為都與
            // 一個 `HStack` 相同——那本來就是它。
            let width =
                measured.map(\.size.width).reduce(0, +)
                + Double(spacing * max(0, measured.count - 1))
            let height = measured.map(\.size.height).max() ?? 0
            return ViewLayoutResult(
                size: ViewSize(width, height),
                childResults: measured,
                preferencesOverlay: PreferenceValues.default.with(
                    \.gridRowCells, [measurement]
                )
            )
        }

        let placements = Self.placements(
            of: measurement,
            in: columnWidths,
            spacing: spacing
        )
        let placed = zip(cells, placements).map { cell, placement in
            cell.computeLayout(
                proposedSize: ProposedViewSize(placement.width, nil),
                environment: cellEnvironment
            )
        }
        let height = placed.map(\.size.height).max() ?? 0
        return ViewLayoutResult(
            size: ViewSize(
                Grid<EmptyView>.width(of: columnWidths, spacing: spacing),
                height
            ),
            childResults: placed,
            preferencesOverlay: PreferenceValues.default.with(
                \.gridRowCells, [measurement]
            )
        )
    }

    public func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: any ViewGraphNodeChildren,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        let cells = layoutableChildren(backend: backend, children: children)
        let results = cells.map { $0.commit() }
        let measurement = GridRowMeasurement(
            cells: results.map { result in
                GridRowMeasurement.Cell(
                    naturalWidth: result.size.width,
                    columnSpan: max(1, result.preferences.gridCellColumns)
                )
            }
        )

        let rowHeight = Int(layout.size.height.rounded(.up))
        let widths = columnWidths ?? []
        let placements = Self.placements(
            of: measurement,
            in: widths,
            spacing: spacing
        )

        var x = 0.0
        for (index, result) in results.enumerated() {
            let cellHeight = Int(result.size.height.rounded(.up))
            let dy =
                switch cellAlignment {
                    case .top: 0
                    case .center: (rowHeight - cellHeight) / 2
                    case .bottom: rowHeight - cellHeight
                }
            let originX: Double
            if index < placements.count {
                originX = placements[index].origin
            } else {
                originX = x
            }
            backend.setPosition(
                ofChildAt: index,
                in: widget,
                to: SIMD2(Int(originX.rounded()), dy)
            )
            x += result.size.width + Double(spacing)
        }

        backend.setSize(of: widget, to: layout.size.vector)
    }

    /// Where each cell starts and how wide it is, given the columns.
    /// 給定各欄之後，每一格從哪裡開始、有多寬。
    static func placements(
        of measurement: GridRowMeasurement,
        in columnWidths: [Double],
        spacing: Int
    ) -> [(origin: Double, width: Double)] {
        var result: [(origin: Double, width: Double)] = []
        var column = 0
        var origin = 0.0
        for cell in measurement.cells {
            guard column < columnWidths.count else {
                // More cells than columns. It happens while a row is being
                // edited, and a trailing cell parked at the right edge is a
                // visible wrong answer rather than a crash.
                // 儲存格比欄還多。這在一列正被編輯時會發生，而把多出來的那一格停在右緣，
                // 是一個**看得見**的錯誤答案，而不是一次崩潰。
                result.append((origin: origin, width: 0))
                continue
            }
            let last = min(column + cell.columnSpan, columnWidths.count)
            let covered = last - column
            let width =
                columnWidths[column..<last].reduce(0, +)
                + Double(spacing * max(0, covered - 1))
            result.append((origin: origin, width: width))
            origin += width + Double(spacing)
            column = last
        }
        return result
    }
}

extension EnvironmentValues {
    /// The spacing a ``Grid`` wants between the cells of each of its
    /// ``GridRow``s.
    ///
    /// `nil` means "no preference", which is what a bare ``GridRow`` outside any
    /// ``Grid`` sees, and which ``HStack`` reads as its own default spacing.
    ///
    /// This exists because the alternative is silent. `Grid`'s
    /// `horizontalSpacing` is a parameter SwiftUI accepts, so ported code passes
    /// it; without a channel down to the rows it would type-check, run, and
    /// change nothing at all.
    ///
    /// ``Grid`` 希望其各個 ``GridRow`` 的儲存格之間採用的間距。
    ///
    /// `nil` 表示「無偏好」，那正是位於任何 ``Grid`` 之外的單獨 ``GridRow`` 所看到的值，而
    /// ``HStack`` 會把它讀作自身的預設間距。
    ///
    /// 這個環境值之所以存在，是因為另一種做法是靜默的。`Grid` 的 `horizontalSpacing` 是 SwiftUI
    /// 接受的參數，因此移植過來的程式碼會傳入它；若少了通往各列的管道，它會通過型別檢查、能夠執行，
    /// 卻什麼也不會改變。
    @Entry internal var gridHorizontalSpacing: Int?

    /// The vertical alignment a ``Grid`` wants its ``GridRow``s to use for
    /// cells that do not state one themselves.
    ///
    /// Separate from ``gridHorizontalSpacing`` because a ``GridRow`` may
    /// override it and may not override the spacing, which is exactly SwiftUI's
    /// split.
    ///
    /// ``Grid`` 希望其 ``GridRow`` 對「自身未指定對齊方式」的儲存格採用的垂直對齊。
    ///
    /// 與 ``gridHorizontalSpacing`` 分開，因為 ``GridRow`` 可以覆寫它、卻不能覆寫間距，而這正是
    /// SwiftUI 的劃分方式。
    @Entry internal var gridRowAlignment: VerticalAlignment = .center

    /// The resolved column widths, from a ``Grid`` to its ``GridRow``s.
    ///
    /// `nil` in the measuring pass and outside a grid, and those two are the
    /// same case on purpose: a row with no columns to fill behaves like the
    /// `HStack` it used to be.
    ///
    /// 已解析的各欄寬度，由 ``Grid`` 傳給它的那些 ``GridRow``。
    ///
    /// 在量測那一輪、以及在格線之外時皆為 `nil`，而這兩者刻意是同一種情況:一個沒有欄可填的列，
    /// 其行為就與它過去所是的那個 `HStack` 相同。
    @Entry internal var gridColumnWidths: [Double]?
}
