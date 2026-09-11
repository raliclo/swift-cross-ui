import Foundation
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

        // Row padding, in one place, because both paths need exactly the same
        // wrapping and a copy of it would drift.
        // 列的內距集中在一處，因為兩條路徑需要的是完全相同的包裝，而複製一份會日後漂移。
        func padded(_ rowView: RowView) -> PaddingModifierView<RowView> {
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

        // The lazy path, when the backend can ask for one row at a time.
        //
        // It returns before `rowViews` is built, and that early return is the
        // entire memory saving: `(0..<rowCount).map(rowContent)` below builds a
        // view for every row, and the loop after it builds a node for every
        // view. On P57 with ten thousand rows that was 423 MB.
        //
        // The size reported here is the proposal, not the content: a backend
        // that takes lazy rows scrolls them itself, so the framework must not
        // ask for a window as tall as ten thousand rows. That is the same rule
        // `ScrollingLists` established, arrived at from the other direction.
        //
        // 延遲路徑——當 backend 有辦法一次要一列時走這裡。
        //
        // 它在 `rowViews` 被建立**之前**就返回，而那個提早返回正是全部的記憶體節省所在:下方的
        // `(0..<rowCount).map(rowContent)` 會為每一列建一個 view，而它後面的迴圈再為每個 view 建一個
        // 節點。在 P57 上，一萬列時那是 423 MB。
        //
        // 此處回報的尺寸是那份**提案**，而不是內容:一個接受延遲列的 backend 會自己捲動它們，因此
        // 框架不可以去要一個「像一萬列那麼高」的視窗。那與 `ScrollingLists` 所確立的是同一條規則，
        // 只是從另一個方向抵達。
        if let lazyBackend = backend as? any BackendFeatures.LazyListRows {
            // `lazy` is the conformance and `backend` is still the full one.
            // Nodes can only be built by a backend that implements everything --
            // `AnyViewGraphNode`'s initialiser requires it -- so the narrow type
            // is used for the one call that needs it and nothing else.
            // `lazy` 是那個 conformance，而 `backend` 仍然是完整的那一個。節點只能由「實作了全部」的
            // backend 建立(`AnyViewGraphNode` 的 initialiser 如此要求)，因此那個較窄的型別只用在
            // 唯一需要它的那一個呼叫上，其餘一概不用。
            let proposedRowWidth: Double? =
                proposedSize.width.map {
                    max(Double(minimumRowSize.x), $0 - baseRowPadding.axisTotals.x)
                }

            /// Builds (or reuses) one row and returns its widget and height.
            /// 建立(或重用)一列，並回傳它的 widget 與高度。
            @MainActor
            func buildRow(_ index: Int) -> (widget: AnyWidget, height: Int)? {
                guard index >= 0, index < rowCount else { return nil }
                let rowView = padded(rowContent(index))
                let node: AnyViewGraphNode<PaddingModifierView<RowView>>
                if let cached = children.lazyNodes[index] {
                    node = cached
                } else {
                    node = AnyViewGraphNode(
                        for: rowView,
                        backend: backend,
                        environment: environment
                    )
                    children.lazyNodes[index] = node
                }
                children.touch(index)

                let result = node.computeLayout(
                    with: rowView,
                    proposedSize: ProposedViewSize(proposedRowWidth, nil),
                    environment: environment
                )
                _ = node.commit()
                let height = LayoutSystem.roundSize(
                    result.size.height + baseRowPadding.axisTotals.y
                )
                children.lazyHeights[index] = height
                return (node.widget, height)
            }

            func install<B: BackendFeatures.LazyListRows>(_ lazy: B) {
                let listView = widget as! B.Widget

                // One row is built before the count is handed over, purely to
                // have an estimate worth giving.
                //
                // Without it the first estimate is `minimumRowSize.y`, the table
                // believes the list is much shorter than it is, lays out far
                // more rows than it will show, and each real height that comes
                // back disagrees with the estimate and invalidates the ones
                // after it. Measured at ten thousand rows: the provider was
                // called more than 500 times to show twelve.
                //
                // 在把列數交出去之前先建一列，純粹是為了有一個值得交出去的估計值。
                //
                // 少了它，第一個估計值是 `minimumRowSize.y`，表格會以為這份清單比實際短得多，
                // 於是排出遠多於它將顯示的列數;而每一個回來的真實高度都與估計值不符，又讓它後面的
                // 那些失效。在一萬列時量到:為了顯示十二列，provider 被呼叫了 500 次以上。
                if children.lazyHeights.isEmpty, rowCount > 0 {
                    _ = buildRow(0)
                }

                lazy.setLazyRows(
                    ofSelectableListView: listView,
                    count: rowCount,
                    estimatedRowHeight: max(
                        minimumRowSize.y,
                        LazyRowEstimate.height(from: children.lazyHeights)
                    ),
                    provider: { index in
                        guard let built = buildRow(index) else { return nil }
                        return (built.widget.into(), built.height)
                    }
                )
            }
            install(lazyBackend)

            // Nothing eager is left behind: a list that switches paths -- which
            // happens the first time a backend gains the conformance -- would
            // otherwise keep every node it built under the old one.
            // 不留下任何 eager 的殘留:一個切換了路徑的清單(當某個 backend 首次取得該 conformance 時
            // 就會發生)否則會留著它在舊路徑下建立的每一個節點。
            children.nodes = []

            return ViewLayoutResult(
                size: ViewSize(
                    max(proposedSize.width ?? Double(minimumRowSize.x), Double(minimumRowSize.x)),
                    proposedSize.height ?? Double(rowCount * minimumRowSize.y)
                ),
                childResults: []
            )
        }

        let rowViews = (0..<rowCount).map(rowContent).map(padded)

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

        // The lazy path committed each row as it was built, inside the
        // provider, because that is the only moment the backend is asking for
        // it. There is nothing to hand over here.
        // 延遲路徑在每一列被建立時就已經在 provider 裡 commit 過了，因為那才是 backend 索取它的
        // 唯一時刻。此處沒有東西要交出去。
        if backend is any BackendFeatures.LazyListRows {
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
            return
        }

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
    /// Every row, when the backend takes them all at once.
    /// 當 backend 一次收下全部時，這裡是每一列。
    var nodes: [AnyViewGraphNode<RowView>]

    /// Rows built on demand, keyed by index, when the backend asks for them one
    /// at a time.
    ///
    /// **Bounded, and the bound is what replaces a `setRowRecycler` in the
    /// protocol.** Without a limit this is "build lazily and then keep for
    /// ever", which reaches the same memory as building eagerly the moment
    /// somebody scrolls to the bottom -- slower to get there and no better when
    /// it arrives.
    ///
    /// 依需求建立的列，以索引為鍵——當 backend 一次要一列時使用。
    ///
    /// **有上限，而那個上限正是協定中不需要 `setRowRecycler` 的原因。** 少了上限，這就是
    /// 「延遲建立、然後永遠留著」——只要有人捲到底，它就會抵達與「一次全建」相同的記憶體用量:
    /// 到達得比較慢，抵達之後並沒有比較好。
    var lazyNodes: [Int: AnyViewGraphNode<RowView>] = [:]

    /// The heights those rows reported, so the backend can be told a real
    /// height for a row it has already seen.
    /// 那些列所回報的高度——好讓 backend 對「它已經看過的列」得到真實高度。
    var lazyHeights: [Int: Int] = [:]

    /// Least-recently-used first. A plain array because the cap is in the
    /// hundreds: an `O(n)` remove on a 200-entry array is not worth an index.
    ///
    /// **Evicting here does not return the memory, and that is measured rather
    /// than assumed.** Scrolling a ten-thousand-row list from the top grew RSS
    /// from 104 MB to 225 MB -- about 30 KB for every row visited, which is the
    /// per-row cost, so nothing was being freed. The heap says where it goes:
    /// `NSKeyValueDependency` went from 1,381 to 25,835 objects, which is AppKit
    /// holding on to the views, not the framework holding on to the nodes.
    ///
    /// So the win this cache delivers is the one at REST -- a list that opens on
    /// ten thousand rows costs what one that opens on four hundred costs -- and
    /// the remaining work is on the backend side, where a row's view has to be
    /// released or reused when it scrolls away. That is the next phase, and it
    /// is written here so nobody has to re-derive it from a memory graph.
    ///
    /// **此處的逐出並不會把記憶體還回來，而這是量過的、不是假設的。** 把一份一萬列的清單從頂端捲下去，
    /// RSS 從 104 MB 長到 225 MB——約等於每造訪一列 30 KB，也就是每列的成本，因此什麼都沒有被釋放。
    /// heap 指出它去了哪裡:`NSKeyValueDependency` 從 1,381 個物件變成 25,835 個——那是 AppKit 抓著
    /// 那些 view 不放，不是框架抓著那些節點不放。
    ///
    /// 因此這個快取所帶來的勝利是**靜止時**的那一個——一份開在一萬列上的清單，成本與開在四百列上的
    /// 相同——而剩下的工作在 backend 那一側:當某一列捲出視野時，它的 view 必須被釋放或重用。那是下一個
    /// 階段，而它寫在這裡，好讓沒有人需要再從一張記憶體圖裡把它推導一次。
    /// 最久未使用者在前。使用單純的陣列，因為上限只有數百:對一個 200 筆的陣列做 `O(n)` 移除，
    /// 不值得為它多維護一份索引。
    var lazyOrder: [Int] = []

    /// Enough for any viewport anyone has, and small enough that the whole
    /// point survives: at the 31 KB a row measured on P57, 200 rows is about
    /// 6 MB against 423 MB for ten thousand.
    /// 足以容納任何人手上的視口，又小到讓這件事的意義得以存活:以 P57 上量到的每列 31 KB 計，
    /// 200 列約 6 MB，相對於一萬列的 423 MB。
    static var lazyCacheLimit: Int { 200 }

    init() {
        nodes = []
    }

    /// Notes that `index` was just used, and evicts if that put the cache over
    /// its limit.
    /// 記下 `index` 剛被使用過，並在因此超出上限時逐出最久未使用的。
    func touch(_ index: Int) {
        if let existing = lazyOrder.firstIndex(of: index) {
            lazyOrder.remove(at: existing)
        }
        lazyOrder.append(index)
        while lazyOrder.count > Self.lazyCacheLimit {
            let evicted = lazyOrder.removeFirst()
            lazyNodes[evicted] = nil
            // The HEIGHT is kept. It costs a few bytes, it is what the backend
            // needs to keep the scrollbar steady for a row it has already
            // measured once, and throwing it away would make the list resize
            // itself as the user scrolls back over old rows.
            // **高度保留下來。** 它只佔幾個位元組，而它正是 backend 對「已經量過一次的列」維持
            // 捲軸穩定所需要的;丟掉它會讓使用者往回捲過舊的列時，清單自己改變大小。
        }
    }

    func forgetLazyRows() {
        lazyNodes.removeAll()
        lazyHeights.removeAll()
        lazyOrder.removeAll()
    }

    var erasedNodes: [ErasedViewGraphNode] {
        (nodes + lazyNodes.values).map(ErasedViewGraphNode.init)
    }

    var widgets: [AnyWidget] {
        nodes.map(\.widget)
    }
}


/// How tall to assume an unbuilt row is.
///
/// **The median of what has been seen, not the mean.** A list whose first row
/// is a header three times the height of the rest would drag a mean upward and
/// leave the scrollbar claiming the list is half again as long as it is; the
/// median ignores it. With nothing seen yet there is no answer to give, and the
/// caller supplies the minimum row height instead.
///
/// 一個尚未建立的列，該假設它有多高。
///
/// **取已見過者的中位數，而不是平均值。** 一份「第一列是高度為其餘三倍的標頭」的清單會把平均值往上
/// 拉，讓捲軸宣稱這份清單比實際長了一半;中位數則會忽略它。在還沒看過任何一列時，這裡沒有答案可給，
/// 由呼叫端改用最小列高。
enum LazyRowEstimate {
    static func height(from seen: [Int: Int]) -> Int {
        guard !seen.isEmpty else { return 0 }
        let sorted = seen.values.sorted()
        return sorted[sorted.count / 2]
    }
}
