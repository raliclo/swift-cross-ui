/// The cache's properties are read-only to avoid the possibility of their
/// values getting out of sync with each other (especially when new
/// properties get introduced).
struct StackLayoutCache {
    /// The stack's children grouped by priority. May sometimes have all children
    /// in a single group due to the stack layout system determining that
    /// flexibility/priority will not have an effect on the final layout.
    let priorityGroups: [LayoutPriorityGroup]
    /// Whether each child is hidden or not. Hidden means zero size *and* doesn't
    /// want spacing of its own in the stack.
    let isHidden: [Bool]
    /// The total amount of spacing used by the stack.
    let totalSpacing: Double
    /// Each child's minimum length along the stack's axis: what it returns when
    /// proposed zero.
    ///
    /// Computed while measuring flexibility and kept rather than discarded,
    /// because a proposal below a child's minimum is not information it can act
    /// on -- it returns the minimum either way -- while the proposal *is* what
    /// that child's own children see. A stack that has run out of room used to
    /// propose zero, and a `Text` two levels down wrapped to one character per
    /// line because of it.
    ///
    /// 每個子元件沿 stack 軸向的最小長度：即它在被提議零時所回傳的值。
    ///
    /// 這是在量測彈性時一併算出的，此處予以保留而非丟棄；因為「低於子元件最小值的提議」對該子元件
    /// 而言不是可據以行動的資訊——它無論如何都會回傳最小值——但那個提議**正是**它自己的子元件所
    /// 看到的東西。空間用盡的 stack 過去會提議零，而兩層之下的 `Text` 就因此變成每行一個字。
    let minimumLengths: [Double]
    /// Whether to redistribute space on commit or not. `true` if and only if the
    /// stack was provided a proposed size with an unspecified perpendicular axis.
    let redistributeSpaceOnCommit: Bool
    /// The length the stack was proposed along its axis when this cache was
    /// computed, or nil when it was proposed none.
    ///
    /// Commit-time redistribution must not offer the children more than this.
    /// It used to offer the stack's resulting length, and when the children
    /// overflowed the proposal that result is LARGER than what they were laid
    /// out in: P51's two columns, proposed 408, came to 494 + 28 = 522, were
    /// re-offered 522, and the second column took 247 instead of 190. The
    /// stack reported 522 and drew 579, so the root scroll view stopped 57 pt
    /// short of the content (2026-10-01).
    ///
    /// stack 計算此快取時沿主軸被提議的長度；未被提議時為 nil。commit 時的重新分配不得
    /// 提供子元件超過此值的空間。它原本提供的是 stack 的結果長度，而當子元件超出提議時，
    /// 那個結果**大於**它們當初被排版的空間:P51 的兩欄被提議 408,得到 494 + 28 = 522,
    /// 再被重新提議 522,第二欄便取了 247 而非 190。stack 回報 522、實際畫到 579,root
    /// scroll view 因此在內容之前 57 點就停住了(2026-10-01)。
    var proposedLength: Double? = nil

    /// The initial value of the cache (just a dummy value, shouldn't ever be used).
    static let initial = StackLayoutCache(
        priorityGroups: [],
        isHidden: [],
        totalSpacing: 0,
        minimumLengths: [],
        redistributeSpaceOnCommit: false
    )
}
