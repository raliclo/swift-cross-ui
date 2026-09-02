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

    /// The initial value of the cache (just a dummy value, shouldn't ever be used).
    static let initial = StackLayoutCache(
        priorityGroups: [],
        isHidden: [],
        totalSpacing: 0,
        minimumLengths: [],
        redistributeSpaceOnCommit: false
    )
}
