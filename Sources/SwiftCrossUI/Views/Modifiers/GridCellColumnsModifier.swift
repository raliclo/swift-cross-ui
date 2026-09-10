extension View {
    /// Makes this cell occupy several of its ``Grid``'s columns.
    ///
    /// ```swift
    /// Grid {
    ///     GridRow {
    ///         Text("spans the lot").gridCellColumns(3)
    ///     }
    ///     GridRow {
    ///         Text("a"); Text("b"); Text("c")
    ///     }
    /// }
    /// ```
    ///
    /// **The grid never asks which view this is, and that is deliberate.** The
    /// span travels up as a preference, so a cell that is a `ForEach`, a
    /// `Group`, or a `Text` wrapped in three modifiers all report it the same
    /// way. A grid that instead looked for a `ForEach` and treated it specially
    /// would be correct only for the shapes somebody thought to enumerate.
    ///
    /// A count below one is treated as one. Zero columns is not a layout, and
    /// the alternative -- a cell that vanishes -- is a picture nobody can debug.
    ///
    /// 讓這個儲存格佔據它所屬 ``Grid`` 的數個欄。
    ///
    /// **格線從不過問「這是哪一種 view」，而那是刻意的。** 跨欄數是以 preference 向上傳遞的，因此
    /// 一個身為 `ForEach`、`Group`，或被三層 modifier 包住的 `Text` 的儲存格，回報的方式完全相同。
    /// 若改成「去找 `ForEach` 並特別處理它」，那就只對「有人想得到並列舉出來的那些形狀」成立。
    ///
    /// 小於一的數值一律視為一。零個欄不構成一種版面，而它的替代結果——一個消失的儲存格——是一張
    /// 沒有人除錯得了的圖。
    public func gridCellColumns(_ count: Int) -> some View {
        PreferenceModifier(self) { preferences, _ in
            preferences.with(\.gridCellColumns, max(1, count))
        }
    }
}
