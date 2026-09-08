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
