/// A column of a ``NavigationSplitView``, as SwiftUI's
/// `NavigationSplitViewColumn`. In a compact window the split view shows one
/// column at a time, and this names which.
///
/// ``NavigationSplitView`` 的一欄，即 SwiftUI 的 `NavigationSplitViewColumn`。在 compact 視窗中，
/// split view 一次只顯示一欄，而這個值指出是哪一欄。
public struct NavigationSplitViewColumn: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case sidebar
        case content
        case detail
    }

    let kind: Kind

    /// The leading column. / 最前面那一欄。
    public static let sidebar = Self(kind: .sidebar)
    /// The middle column of a three-column split view. / 三欄 split view 的中間那一欄。
    public static let content = Self(kind: .content)
    /// The trailing column. / 最後面那一欄。
    public static let detail = Self(kind: .detail)
}
