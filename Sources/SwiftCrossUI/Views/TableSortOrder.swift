/// Which column a ``Table`` is sorted by, and in which direction.
///
/// **A column index and a direction, not a comparator.** SwiftUI's `sortOrder`
/// carries `KeyPathComparator`s and can therefore sort the rows itself; a
/// ``TableColumn`` here is a `(RowValue) -> Content` closure with no key path,
/// so nothing between the header click and the app knows how two rows compare.
/// Carrying a comparator that could only be built from the rendered text would
/// look like SwiftUI's shape and sort by the wrong thing.
///
/// So this says what the user asked for, and the app does the sorting. The
/// framework's part is the bookkeeping that is the same in every app: which
/// column, which way, and flipping the direction when the same header is
/// clicked twice.
///
/// 一個 ``Table`` 依哪一欄、以哪個方向排序。
///
/// **是「欄索引 + 方向」,不是 comparator。** SwiftUI 的 `sortOrder` 帶的是
/// `KeyPathComparator`,因此它能自己排序那些列;而此處的 ``TableColumn`` 是一個
/// `(RowValue) -> Content` closure、**沒有 key path**,所以在「標題被點擊」與「app」之間,
/// 沒有任何一層知道兩列該怎麼比較。若硬要帶一個 comparator,它只能從**算繪出來的文字**建出來
/// ——那會長得像 SwiftUI 的形狀,卻是照錯的東西排序。
///
/// 因此這個型別說的是「使用者要求了什麼」,而排序由 app 完成。框架負責的是每個 app 都一樣的那部分:
/// 哪一欄、哪個方向,以及同一個標題被點第二次時把方向翻過來。
public struct TableSortOrder: Equatable, Hashable, Sendable {
    /// The column's index, counting from 0 in the order the columns were
    /// declared.
    /// 該欄的索引,自 0 起算,順序與欄位宣告的順序相同。
    public var column: Int

    /// Whether the sort is ascending. Starts true for a newly clicked column and
    /// flips when that same column is clicked again.
    /// 是否為遞增。剛被點選的欄位自 true 開始,同一欄再次被點時翻轉。
    public var ascending: Bool

    public init(column: Int, ascending: Bool = true) {
        self.column = column
        self.ascending = ascending
    }

    /// The order that results from clicking `column`'s header, given this one.
    ///
    /// Clicking a different column starts ascending rather than keeping the
    /// current direction: a fresh column has no direction the user has expressed
    /// yet, and inheriting one silently answers a question nobody asked.
    ///
    /// 在目前這個排序狀態下,點擊 `column` 的標題會得到的排序狀態。
    ///
    /// 點擊**不同**的欄位時從遞增開始,而不是沿用目前的方向:一個新的欄位還沒有任何「使用者表達過
    /// 的方向」,而默默沿用等於替一個沒有人問過的問題作答。
    public func toggled(byClicking column: Int) -> TableSortOrder {
        guard column == self.column else {
            return TableSortOrder(column: column, ascending: true)
        }
        return TableSortOrder(column: column, ascending: !ascending)
    }
}
