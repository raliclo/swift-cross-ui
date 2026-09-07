/// A container that arranges ``GridRow``s one above another.
///
/// Composed from `VStack` and `HStack`, so it needs nothing from any backend.
/// See ``Stepper`` for why this batch was chosen.
///
/// **Columns are not aligned across rows, and that is the one divergence worth
/// reading before using this.** SwiftUI's `Grid` measures every row before it
/// places anything, gives each column a single width taken from the widest cell
/// in it, and so produces a true table. This is a `VStack` of `HStack`s, and an
/// `HStack` sizes its children from its own row alone. Two rows whose first
/// cells differ in width therefore start their second cells at different x
/// positions -- a ragged table rather than a grid.
///
/// That is stated this loudly because it is the failure mode that looks like a
/// bug in the caller's own code rather than a documented limitation: everything
/// compiles, everything appears, and the columns are simply not straight.
/// Closing it needs the layout system to measure all rows before committing any
/// of them, which is a change to `LayoutSystem` -- there are exactly two
/// algorithms there today, stack and overlap, and neither can express a shared
/// column width. Use ``Grid`` for a small fixed table whose cells are close in
/// width, and reach for ``Table`` when the columns must line up.
///
/// 一個把 ``GridRow`` 由上而下依序排列的容器。
///
/// 由 `VStack` 與 `HStack` 組合而成，不需要任何 backend 支援。本批工作為何如此挑選，見 ``Stepper``。
///
/// **各列之間的欄並不對齊，而這是使用本型別前最值得先讀的一項差異。** SwiftUI 的 `Grid` 會在放置
/// 任何東西之前先量測每一列，讓每一欄取得「該欄中最寬儲存格」所決定的單一寬度，因而產生真正的
/// 表格。此處則是「`HStack` 疊成的 `VStack`」，而 `HStack` 只依據自己那一列來決定子項尺寸。因此，
/// 兩列若第一個儲存格寬度不同，它們的第二個儲存格就會從不同的 x 位置開始——那是一張參差不齊的
/// 表，而不是一個網格。
///
/// 之所以把這點講得如此明確，是因為它的失效樣態看起來像是呼叫端自己程式碼的錯誤，而不像一項已載明
/// 的限制：一切都編得過、一切都顯示得出來，只是那些欄就是沒對齊。要修補它，必須讓版面系統在
/// commit 任何一列之前先量測所有列，那是對 `LayoutSystem` 的改動——該處今日恰好只有兩套演算法
/// （stack 與 overlap），兩者都無法表達「共用的欄寬」。若是儲存格寬度相近的小型固定表格，可以使用
/// ``Grid``；若那些欄必須對齊，請改用 ``Table``。
public struct Grid<Content: View>: View {
    private let content: Content
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
    ///   - horizontalSpacing: The spacing between cells within a row. Reaches
    ///     the rows through the environment -- see
    ///     ``EnvironmentValues/gridHorizontalSpacing``.
    ///   - verticalSpacing: The spacing between rows.
    ///   - content: The grid's rows.
    public init(
        alignment: Alignment = .center,
        horizontalSpacing: Int? = nil,
        verticalSpacing: Int? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            alignment: alignment,
            horizontalSpacing: horizontalSpacing,
            verticalSpacing: verticalSpacing,
            content: content()
        )
    }

    /// Takes the content as a VALUE, matching the shape ``VStack`` already uses.
    /// 以**值**的形式接收內容，與 ``VStack`` 既有的寫法一致。
    private init(
        alignment: Alignment,
        horizontalSpacing: Int?,
        verticalSpacing: Int?,
        content: Content
    ) {
        self.alignment = alignment
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
        self.content = content
    }

    public var body: some View {
        VStack(alignment: alignment.horizontal, spacing: verticalSpacing) {
            content
        }
        .environment(\.gridHorizontalSpacing, horizontalSpacing)
        .environment(\.gridRowAlignment, alignment.vertical)
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

    private let content: Content
    private let alignment: VerticalAlignment?

    /// Creates a row of grid cells.
    ///
    /// - Parameters:
    ///   - alignment: How this row's cells align against one another. `nil`
    ///     takes the enclosing ``Grid``'s vertical alignment.
    ///   - content: The row's cells.
    public init(
        alignment: VerticalAlignment? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(alignment: alignment, content: content())
    }

    /// Takes the content as a VALUE, matching the shape ``HStack`` already uses.
    /// 以**值**的形式接收內容，與 ``HStack`` 既有的寫法一致。
    private init(alignment: VerticalAlignment?, content: Content) {
        self.alignment = alignment
        self.content = content
    }

    public var body: some View {
        HStack(alignment: alignment ?? inheritedAlignment, spacing: inheritedSpacing) {
            content
        }
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
}
