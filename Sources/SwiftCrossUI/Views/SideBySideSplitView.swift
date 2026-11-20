/// Two or three columns side by side at every width, phones included.
///
/// This is what ``NavigationSplitView`` did before it learned SwiftUI's compact
/// behaviour, kept under its own name: it never collapses to one column, so a
/// phone shows the panes next to each other.
///
/// 在任何寬度下都把兩欄或三欄並排顯示，手機也一樣。
///
/// 這是 ``NavigationSplitView`` 學會 SwiftUI 的 compact 行為之前的做法，以自己的名字保留下來：它從不收合
/// 成一欄，因此手機上各窗格會並排顯示。
public struct SideBySideSplitView<Sidebar: View, MiddleBar: View, Detail: View>: View {
    public var body: some View {
        SplitView(
            sidebar: {
                return sidebar
            },
            detail: {
                if MiddleBar.self == EmptyView.self {
                    detail
                } else {
                    SplitView(
                        sidebar: {
                            return content
                        },
                        detail: {
                            return detail
                        }
                    )
                }
            }
        )
    }

    /// The sidebar content. / 側邊欄的內容。
    public var sidebar: Sidebar
    /// The middle content. / 中間欄的內容。
    public var content: MiddleBar
    /// The detail content. / 詳細欄的內容。
    public var detail: Detail

    /// Creates a three-column split view. / 建立三欄的 split view。
    public init(
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder content: () -> MiddleBar,
        @ViewBuilder detail: () -> Detail
    ) {
        self.sidebar = sidebar()
        self.content = content()
        self.detail = detail()
    }
}

extension SideBySideSplitView where MiddleBar == EmptyView {
    /// Creates a two-column split view. / 建立兩欄的 split view。
    public init(
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: () -> Detail
    ) {
        self.sidebar = sidebar()
        content = EmptyView()
        self.detail = detail()
    }
}
