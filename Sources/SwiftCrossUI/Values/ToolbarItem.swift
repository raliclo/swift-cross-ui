/// One control in a window's toolbar.
///
/// A resolved model rather than a view, and the reason is what a toolbar is on
/// each platform: `NSToolbar` on macOS, `UINavigationItem`'s bar button items
/// on iOS, a `GtkHeaderBar`'s packed children on GTK, a `CommandBar` on WinUI,
/// and an `androidx` `Toolbar` on Android. Not one of those hosts an arbitrary
/// view tree the way a window's content area does -- they take titled,
/// optionally iconed controls and lay them out themselves. Handing each backend
/// a view and asking it to host it would mean five different partial answers;
/// handing it a label, a symbol and an action means five complete ones.
///
/// This mirrors ``ResolvedMenu``, which resolves menu content to a model for
/// the same reason: a platform menu is not a view either.
///
/// 視窗工具列中的一個控制項。
///
/// 這是一個「已解析的模型」而非一個 view，理由在於工具列在各平台上究竟是什麼:macOS 的 `NSToolbar`、
/// iOS 上 `UINavigationItem` 的 bar button item、GTK 的 `GtkHeaderBar` 所裝載的子元件、WinUI 的
/// `CommandBar`，以及 Android 的 `androidx` `Toolbar`。它們沒有一個是像視窗內容區那樣「承載任意
/// view 樹」的——它們接收的是帶標題、可選帶圖示的控制項，並自行安排版面。若交給每個 backend 一個
/// view 並要求它承載，得到的會是五個不同的部分答案;交給它一個標籤、一個符號與一個動作，得到的是
/// 五個完整的答案。
///
/// 這與 ``ResolvedMenu`` 的做法一致，後者基於同樣的理由把選單內容解析為模型:平台的選單也不是 view。
public struct ToolbarItem: Sendable {
    /// Where the platform should put it.
    ///
    /// A request, not an instruction. Each platform has its own vocabulary --
    /// macOS toolbars have no notion of a navigation bar's leading and trailing
    /// slots, and a `CommandBar` distinguishes primary from secondary commands
    /// rather than left from right -- so a backend maps these onto whatever it
    /// has and is expected to say in its own documentation what it did.
    ///
    /// 表達的是「希望平台把它放在哪裡」，而非一項指令。各平台的詞彙不同——macOS 的工具列沒有
    /// 「導覽列前緣與後緣」這種概念，而 `CommandBar` 區分的是主要與次要命令、不是左與右——因此
    /// backend 會把這些對應到它所擁有的東西，並應在自己的文件中說明它做了什麼對應。
    public enum Placement: Sendable, Hashable {
        /// The natural place for a confirming or primary action.
        /// 確認性或主要動作的自然位置。
        case primary
        /// The leading edge, where a platform has one.
        /// 前緣——在具備該概念的平台上。
        case leading
        /// The trailing edge, where a platform has one.
        /// 後緣——在具備該概念的平台上。
        case trailing
        /// Let the platform decide. The default.
        /// 交由平台決定。此為預設值。
        case automatic
    }

    public var label: String

    /// A ``SystemSymbol`` name, resolved the way ``Image/init(systemName:)``
    /// resolves it, or `nil` for a text-only item.
    ///
    /// A name rather than a resolved symbol, so that a backend which draws its
    /// toolbar from a platform icon set can use its own column of the symbol
    /// table instead of being handed a glyph it would have to unpick.
    ///
    /// 一個 ``SystemSymbol`` 的名稱，其解析方式與 ``Image/init(systemName:)`` 相同;若為純文字項目
    /// 則為 `nil`。
    ///
    /// 傳名稱而非已解析的符號，是為了讓「以平台圖示集繪製工具列」的 backend 能使用符號表中屬於它自己
    /// 的那一欄，而不是收到一個它還得反推的字符。
    public var systemImage: String?

    public var placement: Placement

    /// Whether the control accepts presses.
    /// 該控制項是否接受按下。
    public var isEnabled: Bool

    public var action: @MainActor @Sendable () -> Void

    public init(
        _ label: String,
        systemImage: String? = nil,
        placement: Placement = .automatic,
        isEnabled: Bool = true,
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        self.label = label
        self.systemImage = systemImage
        self.placement = placement
        self.isEnabled = isEnabled
        self.action = action
    }
}

extension ToolbarItem: Equatable {
    /// Compares everything except the action.
    ///
    /// A closure has no identity to compare, and the backends use this to
    /// decide whether to rebuild the toolbar. Rebuilding on every layout pass
    /// because two identical toolbars compared unequal would make the bar
    /// flicker; not rebuilding when a label changed would leave it stale. So
    /// the comparison covers exactly what is visible.
    ///
    /// 比較除了 action 以外的一切。
    ///
    /// closure 沒有可供比較的身分，而各 backend 以此判斷是否需要重建工具列。若兩個內容相同的工具列
    /// 比較起來不相等，就會在每一次版面計算時重建、使工具列閃爍;而在標籤改變時不重建，則會讓它停留在
    /// 舊值。因此這項比較所涵蓋的，恰好就是看得見的部分。
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.label == rhs.label
            && lhs.systemImage == rhs.systemImage
            && lhs.placement == rhs.placement
            && lhs.isEnabled == rhs.isEnabled
    }
}
