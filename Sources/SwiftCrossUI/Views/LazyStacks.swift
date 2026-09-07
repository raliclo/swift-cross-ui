/// A vertical stack for use inside a `ScrollView`.
///
/// **It is not lazy yet, and the name is the only place that says otherwise.**
/// Read this before using it in place of ``VStack``:
///
/// - **What is the same as SwiftUI:** the layout. `LazyVStack` and `VStack`
///   arrange children identically once every child exists, so any picture this
///   draws is the picture SwiftUI draws.
/// - **What differs:** SwiftUI creates a child only as it approaches the
///   viewport. This creates all of them up front. For a thousand rows that is a
///   thousand backend widgets instead of a screenful, and every child's
///   `onAppear` fires at once rather than on scroll. Code that hangs a network
///   request off `onAppear` therefore issues all of them immediately.
/// - **Why it exists anyway:** SwiftUI source that says `LazyVStack` should
///   compile and should look right, which is parity task #34. An eager stack is
///   the correct picture and the wrong performance; refusing to compile is
///   neither.
///
/// Real laziness needs the container to know which children are near the
/// viewport, which means `ScrollView` reporting its scroll offset and visible
/// rect back into the layout pass. That is a change to the layout system, not to
/// this file, and it is tracked separately.
///
/// 一個供 `ScrollView` 內部使用的垂直堆疊。
///
/// **它目前並不惰性，而全專案只有它的名字暗示相反的事。** 在拿它取代 ``VStack`` 之前請先讀這段：
///
/// - **與 SwiftUI 相同之處：** 版面。一旦所有子項都存在，`LazyVStack` 與 `VStack` 的排列方式
///   完全相同，因此它畫出來的畫面就是 SwiftUI 畫出來的畫面。
/// - **相異之處：** SwiftUI 只在子項接近可視區時才建立它。此處則一次全部建立。一千列就是一千個
///   backend widget，而非一個畫面的量；而且每個子項的 `onAppear` 會同時觸發，而不是隨捲動觸發。
///   把網路請求掛在 `onAppear` 上的程式碼，因此會一口氣全部送出。
/// - **為何仍然提供：** 寫著 `LazyVStack` 的 SwiftUI 原始碼應該編得過、也應該看起來正確，那正是
///   parity 任務 #34。一個積極求值的堆疊是「畫面正確、效能不對」；拒絕編譯則兩者皆非。
///
/// 真正的惰性需要容器知道哪些子項接近可視區，也就是要由 `ScrollView` 把捲動位移與可視矩形回報進
/// 版面計算流程。那是對版面系統的改動，而不是對這個檔案的改動，並另行追蹤。
public struct LazyVStack<Content: View>: View {
    private let content: Content
    private let alignment: HorizontalAlignment
    private let spacing: Int?

    public init(
        alignment: HorizontalAlignment = .center,
        spacing: Int? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: alignment, spacing: spacing) {
            content
        }
    }
}

/// A horizontal stack for use inside a `ScrollView`.
///
/// The horizontal counterpart of ``LazyVStack``, and not lazy for the same
/// reason. Read that type's note; every word of it applies here with the axes
/// swapped.
///
/// 一個供 `ScrollView` 內部使用的水平堆疊。
///
/// ``LazyVStack`` 的水平對應版本，且基於同樣的理由同樣不是惰性的。請讀該型別的說明；其中每一句
/// 在此都成立，只是把軸向對調。
public struct LazyHStack<Content: View>: View {
    private let content: Content
    private let alignment: VerticalAlignment
    private let spacing: Int?

    public init(
        alignment: VerticalAlignment = .center,
        spacing: Int? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        HStack(alignment: alignment, spacing: spacing) {
            content
        }
    }
}

/// A grid that grows downwards, for use inside a `ScrollView`.
///
/// **It is not lazy either, and for exactly the same reason as ``LazyVStack``.**
/// Read that type's note first; every word of it applies here. If anything this
/// one is the more eager of the two: it does not merely create every child up
/// front, it has to, because it cannot decide how many rows there are without
/// first counting the cells. Do not read "grid" as "more clever about
/// off-screen content than the stacks are" -- it is the same eagerness with more
/// arithmetic on top.
///
/// Composed from `VStack`, `HStack`, ``ForEach`` and
/// ``View/frame(width:height:alignment:)``, so it needs nothing from any
/// backend.
///
/// **How the content becomes cells.** A `@ViewBuilder` block hands over one
/// value, not a list, so the cells are recovered by ``gridCells(of:)`` -- see
/// ``GridCellsProviding`` for what that can and cannot see through. The short
/// version: `ForEach`, `Group`, `if`/`else`, and literal blocks of up to twenty
/// views all flatten; a custom view of your own counts as one cell, deliberately,
/// so that a grid never takes somebody's control apart across two columns.
///
/// **Two divergences from SwiftUI worth knowing before use:**
///
/// - **A short last row spreads out.** Each row is its own `HStack`, so a final
///   row holding fewer cells than there are columns shares the full width
///   between them instead of leaving the missing columns empty. Full rows do
///   line up with one another, because every cell carries its column's frame.
/// - **Per-column spacing collapses to one value.** ``GridItem/spacing`` is
///   per-column in SwiftUI; an `HStack` has a single spacing, so the first
///   column's is used for the whole row and the rest are ignored. Give every
///   item the same `spacing` and the two agree.
///
/// `pinnedViews` is not accepted, unlike SwiftUI's initialiser -- pinned section
/// headers need the scroll container to report its offset, which is the same
/// missing piece that keeps this type from being lazy.
///
/// 一個向下延伸、供 `ScrollView` 內部使用的網格。
///
/// **它同樣不是惰性的，理由與 ``LazyVStack`` 完全相同。** 請先讀該型別的說明；其中每一句在此都成立。
/// 若真要比較，這一個還更積極求值：它不只是把所有子項提前建立，而是**必須**如此，因為不先數過儲存格
/// 的總數，它就無法決定共有幾列。請勿把「grid」理解成「比那些 stack 更懂得處理畫面外的內容」——它是
/// 同樣的積極求值，只是上面多疊了一些算術。
///
/// 由 `VStack`、`HStack`、``ForEach`` 與 ``View/frame(width:height:alignment:)`` 組合而成，不需要
/// 任何 backend 支援。
///
/// **內容如何變成儲存格。** `@ViewBuilder` 區塊交出的是一個值而非一份列表，因此儲存格是由
/// ``gridCells(of:)`` 還原出來的——它能看穿什麼、不能看穿什麼，見 ``GridCellsProviding``。簡短版本
/// 是：`ForEach`、`Group`、`if`/`else`，以及最多二十個 view 的字面區塊都會被攤平；而你自訂的 view
/// 會被算作一個儲存格，這是刻意的，如此網格才不會把別人的控制項拆散到兩個欄位去。
///
/// **使用前值得知道的兩項與 SwiftUI 的差異：**
///
/// - **不足一列的最後一列會攤開。** 每一列都是各自的 `HStack`，因此當最後一列的儲存格少於欄數時，
///   它們會平分整個寬度，而不是把缺少的那幾欄留白。完整的列彼此之間是對齊的，因為每個儲存格都帶著
///   它所屬欄位的 frame。
/// - **各欄的間距會塌縮為單一值。** ``GridItem/spacing`` 在 SwiftUI 中是逐欄設定的；而 `HStack` 只有
///   單一間距，因此整列採用第一欄的值，其餘的則被忽略。只要讓每個 item 的 `spacing` 都相同，兩者
///   即一致。
///
/// 與 SwiftUI 的建構式不同，此處不接受 `pinnedViews`——釘住的區段標頭需要捲動容器回報其位移，而那
/// 正是使本型別無法成為惰性的同一塊缺件。
public struct LazyVGrid<Content: View>: View {
    private let content: Content
    private let columns: [GridItem]
    private let alignment: HorizontalAlignment
    private let spacing: Int?

    /// Creates a grid that flows its content into the given columns.
    ///
    /// - Parameters:
    ///   - columns: One ``GridItem`` per column. An empty array is treated as a
    ///     single column, because a grid with no columns can show nothing and
    ///     trapping would be a harsh answer to an array that came from data.
    ///   - alignment: How the rows align within the grid.
    ///   - spacing: The spacing BETWEEN ROWS. Horizontal spacing comes from
    ///     ``GridItem/spacing``, matching SwiftUI.
    ///   - content: The grid's cells.
    public init(
        columns: [GridItem],
        alignment: HorizontalAlignment = .center,
        spacing: Int? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            columns: columns,
            alignment: alignment,
            spacing: spacing,
            content: content()
        )
    }

    /// Takes the content as a VALUE, matching the shape ``VStack`` already uses.
    /// 以**值**的形式接收內容，與 ``VStack`` 既有的寫法一致。
    private init(
        columns: [GridItem],
        alignment: HorizontalAlignment,
        spacing: Int?,
        content: Content
    ) {
        self.columns = columns
        self.alignment = alignment
        self.spacing = spacing
        self.content = content
    }

    /// The one spacing an `HStack` can carry. See the type's note.
    /// `HStack` 能承載的那唯一一個間距。見本型別的說明。
    private var columnSpacing: Int? {
        columns.first?.spacing
    }

    /// The content's cells, sized by their column and cut into rows.
    ///
    /// Identifiers are positional, which is the honest choice here rather than a
    /// shortcut: the cells arrive already type-erased, so whatever identity a
    /// ``ForEach`` gave them is gone by this point and cannot be recovered.
    /// A cell that moves between positions is therefore rebuilt rather than
    /// moved -- the same trade ``AnyView`` makes everywhere else.
    ///
    /// 內容的各個儲存格，依其所屬欄位調整尺寸後切成一列列。
    ///
    /// 識別子是依位置決定的，這在此處是誠實的選擇而非便宜行事：儲存格抵達時型別早已被抹除，因此
    /// ``ForEach`` 原本賦予它們的 identity 到這一步已經消失、無法還原。所以在位置之間移動的儲存格
    /// 會被重建而非搬移——這與 ``AnyView`` 在他處所做的取捨相同。
    private var rows: [IdentifiedGridRow] {
        let cells = gridCells(of: content)
        guard !cells.isEmpty else { return [] }

        let columnCount = max(columns.count, 1)
        var rows: [IdentifiedGridRow] = []
        var start = 0

        while start < cells.count {
            let end = min(start + columnCount, cells.count)
            var rowCells: [IdentifiedGridCell] = []
            for index in start..<end {
                let column = columns.isEmpty ? nil : columns[index - start]
                let cell = cells[index]
                rowCells.append(
                    IdentifiedGridCell(id: index, view: column?.sizing(cell) ?? cell)
                )
            }
            rows.append(IdentifiedGridRow(id: rows.count, cells: rowCells))
            start = end
        }

        return rows
    }

    public var body: some View {
        VStack(alignment: alignment, spacing: spacing) {
            ForEach(rows) { row in
                HStack(spacing: columnSpacing) {
                    ForEach(row.cells) { cell in
                        cell.view
                    }
                }
            }
        }
    }
}

/// One cell of a ``LazyVGrid``, carrying the positional identifier that
/// ``ForEach`` needs.
/// ``LazyVGrid`` 的一個儲存格，帶著 ``ForEach`` 所需的位置識別子。
struct IdentifiedGridCell: Identifiable {
    let id: Int
    let view: AnyView
}

/// One row of a ``LazyVGrid``, carrying the positional identifier that
/// ``ForEach`` needs.
/// ``LazyVGrid`` 的一列，帶著 ``ForEach`` 所需的位置識別子。
struct IdentifiedGridRow: Identifiable {
    let id: Int
    let cells: [IdentifiedGridCell]
}
