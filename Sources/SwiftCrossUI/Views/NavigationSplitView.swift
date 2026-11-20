/// A view that presents views in two or three columns.
///
/// In a regular-width window the columns sit side by side. In a compact one --
/// a phone held upright, a narrow desktop window -- it shows one column at a
/// time, as SwiftUI does: choosing a row in a ``List`` with a selection moves
/// to the next column, and a back bar (or the platform's own Back) returns to
/// the previous one and clears the row chosen there. ``SideBySideSplitView``
/// keeps the columns side by side at every width.
///
/// 以兩欄或三欄呈現內容的 view。
///
/// 在 regular 寬度的視窗中各欄並排。在 compact 的視窗中(直拿的手機、窄的桌面視窗)則與 SwiftUI 相同，
/// 一次只顯示一欄：在帶有選取的 ``List`` 中選一列會前往下一欄，返回列(或平台自己的返回)會回到上一欄，
/// 並清除在那一欄選的列。``SideBySideSplitView`` 則在任何寬度都讓各欄並排。
public struct NavigationSplitView<Sidebar: View, MiddleBar: View, Detail: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// The column shown in a compact window when the app does not bind one.
    /// app 沒有綁定時，compact 視窗所顯示的那一欄。
    @State private var ownCompactColumn = NavigationSplitViewColumn.sidebar

    @State private var store = NavigationSplitViewStore()

    @ViewBuilder
    public var body: some View {
        if horizontalSizeClass == .compact {
            collapsed
        } else {
            SplitView(
                sidebar: {
                    column(sidebar, .sidebar)
                },
                detail: {
                    if hasContentColumn {
                        SplitView(
                            sidebar: {
                                column(content, .content)
                            },
                            detail: {
                                detailColumn
                            }
                        )
                    } else {
                        detailColumn
                    }
                }
            )
        }
    }

    /// The sidebar content.
    public var sidebar: Sidebar
    /// The middle content.
    public var content: MiddleBar
    /// The detail content.
    public var detail: Detail

    /// The app's binding for the column a compact window shows, if it gave one.
    /// app 為 compact 視窗所顯示之欄提供的綁定(若有)。
    private var preferredCompactColumn: Binding<NavigationSplitViewColumn>?

    /// Creates a three-column split view.
    /// - Parameters:
    ///   - sidebar: The leading column.
    ///   - content: The middle column.
    ///   - detail: The trailing column.
    public init(
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder content: () -> MiddleBar,
        @ViewBuilder detail: () -> Detail
    ) {
        self.sidebar = sidebar()
        self.content = content()
        self.detail = detail()
    }

    /// Creates a three-column split view that shows `preferredCompactColumn`
    /// in a compact window, and updates it as the user moves between columns.
    ///
    /// 建立三欄 split view,在 compact 視窗中顯示 `preferredCompactColumn`,並隨使用者在各欄間移動而更新它。
    public init(
        preferredCompactColumn: Binding<NavigationSplitViewColumn>,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder content: () -> MiddleBar,
        @ViewBuilder detail: () -> Detail
    ) {
        self.init(sidebar: sidebar, content: content, detail: detail)
        self.preferredCompactColumn = preferredCompactColumn
    }

    private var hasContentColumn: Bool {
        MiddleBar.self != EmptyView.self
    }

    /// Where the compact column lives: the app's binding, or this view's own.
    /// compact 欄存放之處:app 的綁定，或此 view 自己的。
    private var compactColumn: Binding<NavigationSplitViewColumn> {
        preferredCompactColumn ?? $ownCompactColumn
    }

    /// The column a compact window shows. `.content` names the detail column
    /// when there is no middle one.
    /// compact 視窗所顯示的欄。沒有中間欄時,`.content` 指的是詳細欄。
    private var visibleCompactColumn: NavigationSplitViewColumn {
        let column = compactColumn.wrappedValue
        if column == .content && !hasContentColumn {
            return .detail
        }
        return column
    }

    /// The column before `column`, which Back returns to.
    /// `column` 之前的那一欄，也就是返回會回到的地方。
    private func column(before column: NavigationSplitViewColumn) -> NavigationSplitViewColumn {
        column == .detail && hasContentColumn ? .content : .sidebar
    }

    /// The column after `column`, which choosing a row there moves to.
    /// `column` 之後的那一欄，也就是在那裡選一列會前往的地方。
    private func column(after column: NavigationSplitViewColumn) -> NavigationSplitViewColumn {
        column == .sidebar && hasContentColumn ? .content : .detail
    }

    /// One column at a time, with a back bar on every column but the first.
    ///
    /// Fills what it is offered at every column, for the reason
    /// ``NavigationStack`` does: a back bar that comes and goes would otherwise
    /// move whatever is around the split view.
    ///
    /// 一次一欄，除了第一欄之外每一欄都有返回列。
    ///
    /// 不論顯示哪一欄都填滿被給予的空間，理由與 ``NavigationStack`` 相同：否則返回列的出現與消失會移動
    /// split view 周圍的東西。
    @ViewBuilder
    private var collapsed: some View {
        let shown = visibleCompactColumn
        VStack(spacing: 0) {
            if shown != .sidebar {
                backBar
            }
            if shown == .sidebar {
                column(sidebar, .sidebar)
            } else if shown == .content {
                column(content, .content)
            } else {
                detailColumn
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The platform's own Back returns a column too, while there is one to
        // return to; see ``NavigationBackTarget``.
        // 只要還有上一欄可回，平台自己的返回也會回到上一欄；見 ``NavigationBackTarget``。
        .navigationBackRegistration(
            target: store.backTarget,
            canPop: shown != .sidebar,
            pop: { goBack() }
        )
    }

    @ViewBuilder
    private var backBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button("‹ Back") {
                    _ = goBack()
                }
                Spacer()
            }
            .padding(8)

            Divider()
        }
    }

    /// Returns to the previous column and clears the row chosen there, as
    /// SwiftUI does, so that choosing it again moves forward again. Returns how
    /// to undo the move, or `nil` when already at the first column.
    ///
    /// 回到上一欄並清除在那裡選的列(與 SwiftUI 相同),讓再次選它時會再次前往。回傳復原此移動的方法;
    /// 已在第一欄時回傳 `nil`。
    private func goBack() -> (() -> Void)? {
        let shown = visibleCompactColumn
        guard shown != .sidebar else { return nil }
        let previous = column(before: shown)
        let binding = compactColumn
        store.clearSelection[previous]?()
        binding.wrappedValue = previous
        return { binding.wrappedValue = shown }
    }

    /// `view` as the column `source`: a sidebar-styled list that reports its
    /// row choices to this split view.
    /// 把 `view` 當作 `source` 這一欄：側邊欄樣式的 list,並把它的選列回報給這個 split view。
    private func column<V: View>(
        _ view: V,
        _ source: NavigationSplitViewColumn
    ) -> EnvironmentModifier<V> {
        let next = column(after: source)
        let binding = compactColumn
        let store = store
        let report = NavigationSplitColumnSelection { selected, clear in
            store.clearSelection[source] = clear
            binding.wrappedValue = selected ? next : source
        }
        return EnvironmentModifier(view) {
            $0
                .with(\.listStyle, .sidebar)
                .with(\.backendListStyle, .sidebar)
                .with(\.splitColumnSelection, report)
        }
    }

    /// The detail column. Lists in it belong to no split column, including an
    /// enclosing split view's.
    /// 詳細欄。其中的 list 不屬於任何 split 欄，外層 split view 的也不算。
    private var detailColumn: EnvironmentModifier<Detail> {
        EnvironmentModifier(detail) {
            $0.with(\.splitColumnSelection, nil)
        }
    }
}

extension NavigationSplitView where MiddleBar == EmptyView {
    /// Creates a two-column split view.
    /// - Parameters:
    ///   - sidebar: The leading column.
    ///   - detail: The trailing column.
    public init(
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: () -> Detail
    ) {
        self.sidebar = sidebar()
        content = EmptyView()
        self.detail = detail()
    }

    /// Creates a two-column split view that shows `preferredCompactColumn` in a
    /// compact window, and updates it as the user moves between columns.
    ///
    /// 建立兩欄 split view,在 compact 視窗中顯示 `preferredCompactColumn`,並隨使用者在各欄間移動而更新它。
    public init(
        preferredCompactColumn: Binding<NavigationSplitViewColumn>,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: () -> Detail
    ) {
        self.init(sidebar: sidebar, detail: detail)
        self.preferredCompactColumn = preferredCompactColumn
    }
}

/// What a selectable ``List`` in a column of a ``NavigationSplitView`` tells the
/// split view when the user chooses a row: whether a row is now chosen, and how
/// to clear it when Back returns to that column.
///
/// ``NavigationSplitView`` 某一欄裡可選取的 ``List`` 在使用者選列時告訴 split view 的事：現在是否有選中的列，
/// 以及返回回到該欄時如何清除它。
struct NavigationSplitColumnSelection {
    var report: @MainActor (_ selected: Bool, _ clear: @escaping @MainActor () -> Void) -> Void

    init(
        _ report: @escaping @MainActor (_ selected: Bool, _ clear: @escaping @MainActor () -> Void) -> Void
    ) {
        self.report = report
    }
}

extension EnvironmentValues {
    /// Set inside the sidebar and content columns of a ``NavigationSplitView``.
    /// 在 ``NavigationSplitView`` 的側邊欄與中間欄之內設定。
    @Entry var splitColumnSelection: NavigationSplitColumnSelection? = nil
}

/// What a ``NavigationSplitView`` keeps across updates without redrawing when
/// it changes.
/// ``NavigationSplitView`` 跨更新保存、且改變時不需重繪的東西。
@MainActor
final class NavigationSplitViewStore: ObservableObject {
    /// How to clear the row chosen in each column. / 清除各欄所選之列的方法。
    var clearSelection: [NavigationSplitViewColumn: @MainActor () -> Void] = [:]
    /// This split view's place among the targets of the platform's Back.
    /// 此 split view 在平台返回之目標中的位置。
    let backTarget = NavigationBackTarget()
}
