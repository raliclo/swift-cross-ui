/// What one ``GridRow`` measured, reported upward so its ``Grid`` can decide
/// the column widths.
///
/// **It exists because a parent cannot see its grandchildren any other way.**
/// `ViewLayoutResult` takes `childResults` in an initialiser and keeps only the
/// merged preferences -- checked 2026-09-10, and it is what rules out the
/// obvious plan of reading the cell widths back out of each row's result. The
/// preference channel is the one upward path that already works, so the row
/// packs what it measured into one of these and the grid unpacks it.
///
/// 一個 ``GridRow`` 量到的東西，向上回報，好讓它的 ``Grid`` 決定各欄的寬度。
///
/// **它之所以存在，是因為父層沒有別的方式看得見它的孫節點。** `ViewLayoutResult` 只在 initialiser
/// 中接收 `childResults`，而它保留下來的只有合併後的 preferences——這是 2026-09-10 查證過的，也正是
/// 它排除了「從每一列的結果讀回儲存格寬度」這個顯而易見的做法。preference 是這棵樹上唯一已經在運作
/// 的向上通道，因此由列把它量到的東西打包成一個這種值，再由格線拆開。
public struct GridRowMeasurement: Equatable, Sendable {
    /// One entry per cell, in declaration order.
    /// 每個儲存格一項，依宣告順序排列。
    public var cells: [Cell]

    public init(cells: [Cell]) {
        self.cells = cells
    }

    public struct Cell: Equatable, Sendable {
        /// What the cell asked for when nothing constrained it.
        /// 在沒有任何約束時，這個儲存格所要求的寬度。
        public var naturalWidth: Double

        /// How many columns it occupies. Always at least one.
        ///
        /// A span wider than the row has columns is clamped by the grid rather
        /// than here: this type reports what was asked for, and the grid is the
        /// only place that knows how many columns there are.
        ///
        /// 它佔據幾個欄。至少為一。
        ///
        /// 「跨欄數大於該列的欄數」是由格線夾住、而不是在此處夾住:本型別回報的是**被要求的**東西，
        /// 而只有格線知道總共有幾個欄。
        public var columnSpan: Int

        public init(naturalWidth: Double, columnSpan: Int) {
            self.naturalWidth = naturalWidth
            self.columnSpan = max(1, columnSpan)
        }
    }
}
