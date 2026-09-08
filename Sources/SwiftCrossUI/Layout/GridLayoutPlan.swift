/// Resolved columns, handed down to whoever actually arranges the cells.
///
/// **It travels in the environment for the same reason ``EnvironmentValues/
/// layoutOverlapsChildren`` does.** ``ForEach`` builds a real container rather
/// than being flattened away, so a `LazyVGrid` whose content is a `ForEach` --
/// which is nearly every one -- sees exactly one child. Arranging that one child
/// in a grid puts every cell in the first column and the `ForEach` then lays its
/// own children out along whatever axis it inherited, which is a vertical list.
/// That is what the first version of this did, and the screenshot showed eight
/// cells stacked one above another with the numbers in the right order, which
/// reads as a grid whose columns are wrong rather than as a grid that never ran.
///
/// The fix is the one the tree already reached for twice: tell `ForEach` how its
/// parent arranges things and let it do the arranging. `layoutOrientation` was
/// the first, `layoutOverlapsChildren` the second when `ZStack` hit the same
/// wall, and this is the third.
///
/// 解析完成的欄位,交給真正負責排列儲存格的那一方。
///
/// **它之所以隨 environment 傳遞,理由與 ``EnvironmentValues/layoutOverlapsChildren`` 完全相同。**
/// ``ForEach`` 會建立一個真正的容器,而不是被攤平消去,因此一個「內容是 `ForEach`」的 `LazyVGrid`
/// ——而那幾乎是全部——只會看到**一個**子節點。把那一個子節點排進格線,會讓每一格都落在第一欄,
/// 接著 `ForEach` 再依它所繼承到的軸向安排自己的子元件,也就是一個垂直清單。本實作的第一版正是如此,
/// 而截圖顯示八格由上而下排成一列、編號順序正確——那讀起來像是「一個欄位算錯的格線」,而不像是
/// 「一個從未執行的格線」。
///
/// 修法就是這棵樹已經採用過兩次的那一個:告訴 `ForEach` 它的父層是怎麼排的,然後讓它自己去排。
/// 第一次是 `layoutOrientation`,第二次是 `ZStack` 撞上同一堵牆時的 `layoutOverlapsChildren`,
/// 而這是第三次。
///
/// **It stayed integral when ``GridItem/Size`` widened to `Double` (task #108),
/// and that is a decision rather than an oversight.** A `GridItem` is what the
/// caller asked for and may be fractional -- `.fixed(100.5)`, or a third of a
/// container. A `GridLayoutPlan` is where the asking stops: every consumer of it
/// hands its numbers to a backend that positions in whole points
/// (`LayoutSystem.commitGridLayout` builds a `SIMD2<Int>` from
/// `columnOffsets`), so widening this type would only move the same rounding
/// downstream, into five backends instead of one resolver. The fractional
/// arithmetic therefore happens entirely inside
/// ``LazyVGrid/resolve(columns:alignment:spacing:proposedWidth:)``, which rounds
/// column EDGES once, at the end -- so the columns still tile exactly and no
/// remainder is dropped.
///
/// **當 ``GridItem/Size`` 於任務 #108 放寬為 `Double` 時，本型別維持整數，那是一個決定，不是疏漏。**
/// 一個 `GridItem` 是呼叫端所要求的東西，可以帶小數——`.fixed(100.5)`，或容器的三分之一。而
/// `GridLayoutPlan` 是「要求」終止之處：它的每一個消費端都會把其中的數值交給「以整數點定位」的
/// backend（`LayoutSystem.commitGridLayout` 以 `columnOffsets` 建構 `SIMD2<Int>`），因此放寬本型別
/// 只會把同一次取整往下游推——從一個解析器推給五個 backend。所以帶小數的算式完全發生在
/// ``LazyVGrid/resolve(columns:alignment:spacing:proposedWidth:)`` 內部，由它在最後一次性地對欄位
/// **邊界**取整——如此各欄仍然恰好密合，也沒有任何餘數被丟棄。
public struct GridLayoutPlan: Equatable, Sendable {
    /// One entry per resolved column. An adaptive ``GridItem`` contributes
    /// several, which is why this is not the caller's `[GridItem]`.
    /// 每一個已解析的欄各一項。一個 adaptive 的 ``GridItem`` 會貢獻數項,這正是此處不是呼叫端那份
    /// `[GridItem]` 的原因。
    public var columnWidths: [Int]

    /// The x offset of each column, cumulative, including spacing.
    /// 各欄的 x 位移,累計值,已含間距。
    public var columnOffsets: [Int]

    /// Per column, so a `GridItem` can override the grid's own alignment.
    /// 逐欄記錄,如此個別 `GridItem` 便能覆寫格線自身的對齊方式。
    public var alignments: [HorizontalAlignment]

    public var spacing: Int

    public init(
        columnWidths: [Int],
        columnOffsets: [Int],
        alignments: [HorizontalAlignment],
        spacing: Int
    ) {
        self.columnWidths = columnWidths
        self.columnOffsets = columnOffsets
        self.alignments = alignments
        self.spacing = spacing
    }
}
