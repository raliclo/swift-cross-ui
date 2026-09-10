/// A view that displays a selectable list of views.
public struct List<SelectionValue: Hashable, RowView: View>: TypeSafeView, View {
    typealias Children = ListViewChildren<PaddingModifierView<RowView>>

    public let body = EmptyView()

    /// The current selection, if any.
    var selection: Binding<SelectionValue?>
    var rowContent: (Int) -> RowView
    var associatedSelectionValue: (Int) -> SelectionValue
    var find: (SelectionValue) -> Int?
    var rowCount: Int

    /// Creates a list view.
    ///
    /// - Parameters:
    ///   - data: A collection of `Identifiable` values to construct the list
    ///     from.
    ///   - selection: A binding to the ID of the value that is currently
    ///     selected.
    ///   - rowContent: A view builder that renders a single row of the list.
    ///     Receives an element of `data`.
    public init<Data: RandomAccessCollection>(
        _ data: Data,
        selection: Binding<SelectionValue?>,
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowView
    ) where Data.Element: Identifiable, Data.Element.ID == SelectionValue, Data.Index == Int {
        self.init(data, id: \.id, selection: selection, rowContent: rowContent)
    }

    /// Creates a list view that renders `Text` views based on the elements of
    /// `data`.
    ///
    /// - Parameters:
    ///   - data: A collection of `Identifiable` values to construct the list
    ///     from.
    ///   - selection: A binding to the ID of the value that is currently
    ///     selected.
    public init<Data: RandomAccessCollection>(
        _ data: Data,
        selection: Binding<SelectionValue?>
    )
        where
        Data.Element: CustomStringConvertible & Identifiable,
        Data.Element.ID == SelectionValue,
        Data.Index == Int,
        RowView == Text
    {
        self.init(data, selection: selection) { item in
            return Text(item.description)
        }
    }

    /// Creates a list view that renders `Text` views based on the elements of
    /// `data`.
    ///
    /// - Parameters:
    ///   - data: A collection of values to construct the list from.
    ///   - id: A closure that returns the ID to use for a given element of
    ///     `data`.
    ///   - selection: A binding to the ID of the value that is currently
    ///     selected.
    public init<Data: RandomAccessCollection>(
        _ data: Data,
        id: @escaping (Data.Element) -> SelectionValue,
        selection: Binding<SelectionValue?>
    ) where Data.Element: CustomStringConvertible, RowView == Text, Data.Index == Int {
        self.init(data, id: id, selection: selection) { item in
            return Text(item.description)
        }
    }

    /// Creates a list view that renders `Text` views based on the elements of
    /// `data`.
    ///
    /// - Parameters:
    ///   - data: A collection of values to construct the list from.
    ///   - id: A key path to the ID to use for an element of `data`.
    ///   - selection: A binding to the ID of the value that is currently
    ///     selected.
    public init<Data: RandomAccessCollection>(
        _ data: Data,
        id: KeyPath<Data.Element, SelectionValue>,
        selection: Binding<SelectionValue?>
    ) where Data.Element: CustomStringConvertible, RowView == Text, Data.Index == Int {
        self.init(data, id: id, selection: selection) { item in
            return Text(item.description)
        }
    }

    /// Creates a list view.
    ///
    /// - Parameters:
    ///   - data: A collection of values to construct the list from.
    ///   - id: A key path to the ID to use for an element of `data`.
    ///   - selection: A binding to the ID of the value that is currently
    ///     selected.
    ///   - rowContent: A view builder that renders a single row of the list.
    ///     Receives an element of `data`.
    public init<Data: RandomAccessCollection>(
        _ data: Data,
        id: KeyPath<Data.Element, SelectionValue>,
        selection: Binding<SelectionValue?>,
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowView
    ) where Data.Index == Int {
        self.init(data, id: { $0[keyPath: id] }, selection: selection, rowContent: rowContent)
    }

    /// Creates a list view.
    ///
    /// - Parameters:
    ///   - data: A collection of values to construct the list from.
    ///   - id: A closure that returns the ID to use for a given element of
    ///     `data`.
    ///   - selection: A binding to the ID of the value that is currently
    ///     selected.
    ///   - rowContent: A view builder that renders a single row of the list.
    ///     Receives an element of `data`.
    public init<Data: RandomAccessCollection>(
        _ data: Data,
        id: @escaping (Data.Element) -> SelectionValue,
        selection: Binding<SelectionValue?>,
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowView
    ) where Data.Index == Int {
        self.selection = selection
        self.rowContent = { index in
            rowContent(data[index])
        }
        associatedSelectionValue = { index in
            id(data[index])
        }
        find = { selection in
            data.firstIndex { item in
                id(item) == selection
            }
        }
        rowCount = data.count
    }

    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> Children {
        // TODO: Implement snapshotting
        Children()
    }

    func asWidget<Backend: BaseAppBackend>(
        _ children: Children,
        backend: Backend
    ) -> Backend.Widget {
        backend.createSelectableListView()
    }

    func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        // Padding that the backend could not remove (some frameworks have a small
        // constant amount of required padding within each row).
        let baseRowPadding = backend.baseItemPadding(ofSelectableListView: widget)
        let minimumRowSize = backend.minimumRowSize(ofSelectableListView: widget)
        let horizontalBasePadding = baseRowPadding.axisTotals.x
        let verticalBasePadding = baseRowPadding.axisTotals.y

        let rowViews = (0..<rowCount).map(rowContent).map { rowView in
            PaddingModifierView(
                body: TupleView1(rowView),
                insets: EdgeInsets.Internal(
                    top: max(6 - baseRowPadding.top, 0),
                    bottom: max(6 - baseRowPadding.bottom, 0),
                    leading: max(8 - baseRowPadding.leading, 0),
                    trailing: max(8 - baseRowPadding.trailing, 0)
                )
            )
        }

        if rowCount > children.nodes.count {
            for rowView in rowViews.dropFirst(children.nodes.count) {
                let node = AnyViewGraphNode(
                    for: rowView,
                    backend: backend,
                    environment: environment
                )
                children.nodes.append(node)
            }
        } else if children.nodes.count > rowCount {
            children.nodes.removeLast(children.nodes.count - rowCount)
        }

        var childResults: [ViewLayoutResult] = []
        for (rowView, node) in zip(rowViews, children.nodes) {
            let proposedWidth: Double?
            if let width = proposedSize.width {
                proposedWidth = max(
                    Double(minimumRowSize.x),
                    width - baseRowPadding.axisTotals.x
                )
            } else {
                proposedWidth = nil
            }

            let childResult = node.computeLayout(
                with: rowView,
                proposedSize: ProposedViewSize(
                    proposedWidth,
                    nil
                ),
                environment: environment
            )
            childResults.append(childResult)
        }

        let height = childResults.map(\.size.height).map { rowHeight in
            max(
                rowHeight + verticalBasePadding,
                Double(minimumRowSize.y)
            )
        }.reduce(0, +)
        let minimumWidth =
            (childResults.map(\.size.width).max() ?? 0) + horizontalBasePadding
        // A backend that scrolls its own list gets a VIEWPORT; one that does
        // not keeps the full content height, which is the behaviour it has.
        //
        // Conformance-checked rather than required, so converting the five
        // backends one at a time is possible. A backend that ignored a viewport
        // height would clip instead of scrolling, and missing rows read as a
        // layout fault rather than as an unimplemented method -- which is why
        // this asks rather than assumes.
        //
        // Measured before and after on P57: the window went from 9306 px at 50
        // rows, and taller than the display past 200, to the proposal.
        //
        // 會自行捲動清單的 backend 得到的是一個**視口**;不會的則保留完整內容高度,也就是它現有的行為。
        //
        // 此處採 conformance 檢查而非要求實作,好讓五個 backend 能一次轉換一個。一個忽略視口高度的
        // backend 會變成裁切而不是捲動,而少掉的列讀起來像是版面問題、不像一個未實作的方法——
        // 這正是此處「詢問」而非「假定」的理由。
        //
        // 在 P57 上前後量測過:視窗高度從「50 列時 9306 像素、超過 200 列高過顯示器」變成那份提案。
        let reportedHeight: Double
        if backend is any BackendFeatures.ScrollingLists, let proposed = proposedSize.height {
            reportedHeight = min(height, proposed)
        } else {
            reportedHeight = height
        }

        let size = ViewSize(
            max(proposedSize.width ?? minimumWidth, minimumWidth),
            reportedHeight
        )

        return ViewLayoutResult(
            size: size,
            childResults: childResults
        )
    }

    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        let baseRowPadding = backend.baseItemPadding(ofSelectableListView: widget)
        let verticalBasePadding = baseRowPadding.axisTotals.y

        let childResults = children.nodes.map { $0.commit() }
        backend.setItems(
            ofSelectableListView: widget,
            to: children.widgets.map { $0.into() },
            withRowHeights: childResults.map(\.size.height).map { height in
                // Rounded ONCE, after the padding is added, rather than
                // rounding the height and then adding. With `EdgeInsets` now
                // `Double`, the old order would have dropped the fraction of a
                // fractional base padding on every row.
                // **加上 padding 之後才取整一次**,而不是先把高度取整再相加。既然
                // `EdgeInsets` 現在是 `Double`,舊的順序會在**每一列**都丟掉「帶分數的
                // base padding」的那個分數。
                LayoutSystem.roundSize(height + verticalBasePadding)
            }
        )

        // Before setSize, so the list knows its viewport when it is resized to
        // it rather than after. A scroll view told its height second briefly
        // lays out against the old one, which on a long list is a visible jump.
        // 放在 setSize 之前,好讓這個清單在「被調整成該尺寸」時就已經知道它的視口,而不是之後才知道。
        // 一個「後得知自己高度」的捲動視圖會先對著舊值排版一次,而在長清單上那是看得見的跳動。
        if let scrollingBackend = backend as? any BackendFeatures.ScrollingLists {
            func setViewport<B: BackendFeatures.ScrollingLists>(backend: B) {
                backend.setViewportHeight(
                    ofSelectableListView: widget as! B.Widget,
                    to: LayoutSystem.roundSize(layout.size.height)
                )
            }
            setViewport(backend: scrollingBackend)
        }

        backend.setSize(of: widget, to: layout.size.vector)
        backend.setSelectionHandler(forSelectableListView: widget) { selectedIndex in
            selection.wrappedValue = associatedSelectionValue(selectedIndex)
        }

        let selectedIndex: Int?
        if let selectedItem = selection.wrappedValue {
            selectedIndex = find(selectedItem)
        } else {
            selectedIndex = nil
        }

        backend.updateSelectableListView(widget, environment: environment)
        backend.setSelectedItem(ofSelectableListView: widget, toItemAt: selectedIndex)
    }
}

class ListViewChildren<RowView: View>: ViewGraphNodeChildren {
    var nodes: [AnyViewGraphNode<RowView>]

    init() {
        nodes = []
    }

    var erasedNodes: [ErasedViewGraphNode] {
        nodes.map(ErasedViewGraphNode.init)
    }

    var widgets: [AnyWidget] {
        nodes.map(\.widget)
    }
}
