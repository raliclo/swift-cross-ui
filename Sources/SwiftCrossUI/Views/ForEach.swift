import DebugFeatures

/// Holds the once-per-process flag for ``ForEach``'s eager-children warning.
///
/// A separate non-generic type because `ForEach` is generic and Swift does not
/// allow static stored properties in generic types -- the first attempt put the
/// flag on `ForEach` itself and got `static stored properties not supported in
/// generic types`. Putting it here also makes the "once" correct rather than
/// accidental: a static on a generic type would be one flag PER SPECIALISATION,
/// so `ForEach<[Int], Int, Text>` and `ForEach<[String], String, Text>` would
/// each warn separately and the message would repeat with no new information.
///
/// 存放 ``ForEach`` 積極求值警告的「每個行程一次」旗標。
///
/// 之所以是獨立的非泛型型別：`ForEach` 是泛型，而 Swift 不允許泛型型別具有 static stored property
/// ——第一次嘗試把旗標放在 `ForEach` 上，得到 `static stored properties not supported in generic
/// types`。放在此處也讓那個「一次」成為正確的語意、而非湊巧：泛型型別上的 static 會是**每個特化
/// 各一份**，於是 `ForEach<[Int], Int, Text>` 與 `ForEach<[String], String, Text>` 會各警告一次，
/// 而那則訊息重複出現時不會帶有任何新資訊。
enum EagerForEachWarning {
    /// Deliberately high. Not a recommendation about list size -- the point past
    /// which "slow to appear" stops being plausibly something else.
    /// 刻意設得很高。它不是對清單大小的建議——而是「出現得慢」不再能被合理歸因於別的東西的那個點。
    static let threshold = 500

    /// `nonisolated(unsafe)` because every caller is already on the main actor
    /// and a diagnostic flag has nothing for isolation to protect.
    /// 標記 `nonisolated(unsafe)`：所有呼叫端本就在 main actor 上，而一個診斷旗標沒有任何東西需要
    /// 隔離來保護。
    nonisolated(unsafe) static var hasFired = false
}

/// A view that displays a variable amount of children.
public struct ForEach<Items: Collection, ID: Hashable, Child> {
    /// A variable-length collection of elements to display.
    var elements: Items
    /// A method to display the elements as views.
    var child: (Items.Element) -> Child
    /// The path to the property used as Identifier
    var idKeyPath: KeyPath<Items.Element, ID>?
}

extension ForEach: TypeSafeView, View where Child: View {
    /// Says once, when a `ForEach` builds a great many children in one update,
    /// that it did so eagerly.
    ///
    /// **The failure this names is currently invisible.** Nothing stops
    /// `ScrollView { LazyVStack { ForEach(0..<10_000) { ... } } }` from
    /// constructing ten thousand widget trees before the first frame. The app
    /// does not crash, log, or warn -- it simply takes a long time to appear,
    /// which reads as a hang with no cause attached. `LazyVStack` is eager here
    /// (see ``LazyVStack``, which says so in its own documentation), and the
    /// name is the only thing suggesting otherwise, so the developer's first
    /// guess will not be the right one.
    ///
    /// Behind ``DebugFeatures`` because it is a diagnostic, not a policy: a
    /// large `ForEach` is legitimate, and a release build should not pay for
    /// counting or complaining about one.
    ///
    /// The threshold is deliberately high. It is not a recommendation about
    /// list size -- it is the point past which "slow to appear" stops being
    /// plausibly something else.
    ///
    /// 當某個 `ForEach` 在一次更新中建立了極大量的子項時，說一次：它是積極求值地建的。
    ///
    /// **它所指出的失敗目前是看不見的。** 沒有任何東西會阻止
    /// `ScrollView { LazyVStack { ForEach(0..<10_000) { ... } } }` 在第一幀之前建出一萬棵 widget 樹。
    /// app 不會崩潰、不會記錄、也不會警告——它只是很久才出現，而那讀起來像是一次沒有任何線索的當機。
    /// `LazyVStack` 在此處是積極求值的（見 ``LazyVStack``，它自己的文件就這麼說），而唯一暗示相反的
    /// 就只有那個名字，因此開發者的第一個猜測不會是正確的那一個。
    ///
    /// 置於 ``DebugFeatures`` 之後，因為它是診斷而非政策：一個很大的 `ForEach` 是合理的，而 release
    /// build 不該為「計數並抱怨它」付出代價。
    ///
    /// 門檻刻意設得很高。它不是對清單大小的建議——它是「出現得慢」不再能被合理歸因於別的東西的那個點。
    static func warnIfEagerlyLarge(built count: Int) {
        guard DebugFeatures.isEnabled,
            count >= EagerForEachWarning.threshold,
            !EagerForEachWarning.hasFired
        else { return }
        EagerForEachWarning.hasFired = true
        DebugFeatures.log(
            """
            ForEach built \(count) children eagerly in one update. This tree's \
            LazyVStack and LazyHStack are NOT lazy -- they delegate to VStack and \
            HStack, so every child is created up front along with its onAppear. \
            See the documentation on LazyVStack in Views/LazyStacks.swift. If the \
            app appears to hang before its first frame, this is a candidate cause.
            """
        )
    }



    typealias Children = ForEachViewChildren<Items, ID, Child>

    /// Creates a view that creates child views on demand based on a collection
    /// of data.
    ///
    /// One instance of `child` will be rendered for every element in
    /// `elements`.
    ///
    /// - Parameters:
    ///   - elements: The collection to build an array of views from.
    ///   - keyPath: A key path to the element type's ID.
    ///   - child: A view builder that returns an appropriate view for
    ///     each element of `elements`.
    public init(
        _ elements: Items,
        id keyPath: KeyPath<Items.Element, ID>,
        @ViewBuilder _ child: @escaping (Items.Element) -> Child
    ) {
        self.elements = elements
        self.child = child
        self.idKeyPath = keyPath
    }

    public var body: EmptyView {
        return EmptyView()
    }

    public var _asMenuItems: [MenuItem] {
        elements.map(child).flatMap(\._asMenuItems)
    }

    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> Children {
        return Children(
            from: self,
            backend: backend,
            idKeyPath: idKeyPath,
            snapshots: snapshots,
            environment: environment
        )
    }

    func asWidget<Backend: BaseAppBackend>(
        _ children: Children,
        backend: Backend
    ) -> Backend.Widget {
        return backend.createContainer()
    }

    func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        func insertChild(_ child: Backend.Widget, atIndex index: Int) {
            children.queuedChanges.append(.insertChild(AnyWidget(child), index))
        }

        func removeChild(atIndex index: Int) {
            children.queuedChanges.append(.removeChild(index))
        }

        func swap(childAt firstIndex: Int, withChildAt secondIndex: Int) {
            children.queuedChanges.append(.swapChildren(firstIndex, secondIndex))
        }

        // Use the previous update Method when no keyPath is set on a
        // [Hashable] Collection to optionally keep the old behaviour.
        guard let idKeyPath else {
            return deprecatedUpdate(
                widget,
                children: children,
                proposedSize: proposedSize,
                environment: environment,
                backend: backend
            )
        }

        var oldIdentifiers = children.identifiers
        let newIdentifiers = elements.map { $0[keyPath: idKeyPath] }

        // If the identifiers of our elements have changed, then we must rearrange
        // our nodes and widgets so that child view states remain with their
        // corresponding identifiers.
        if oldIdentifiers != newIdentifiers {
            var oldIdentifierMap = children.identifierMap
            var oldNodes = children.nodes
            var seenIdentifiers = Set<ID>()
            var oldNodesReused = 0
            children.nodes = []
            children.identifierMap = [:]
            children.identifiers = []
            children.layoutableChildren = []

            var offset = 0
            var duplicateCount = 0
            for (index, element) in elements.enumerated() {
                let identifier = newIdentifiers[index]
                let childContent = child(element)
                let node: AnyViewGraphNode<Child>

                if !seenIdentifiers.insert(identifier).inserted {
                    // We cannot keep view state attached to the correct ForEach element
                    // when there are duplicate identifiers. Any elements with unique
                    // identifiers are guaranteed to keep functioning correctly. Elements
                    // with non-unique identifiers will get their corresponding view graph
                    // nodes recreated each time the identifiers of our elements change,
                    // unless they are the first element with the shared identifier, in which
                    // case they will inherit the view graph node of the previous first element
                    // with that same identifier.
                    logger.warning(
                        "duplicate identifier in ForEach; view state may not act as you would expect",
                        metadata: ["identifier": "\(identifier)"]
                    )
                    duplicateCount += 1
                }

                if let oldIndex = oldIdentifierMap.removeValue(forKey: identifier) {
                    // If the identifier already has a corresponding node, reuse it.
                    node = oldNodes[oldIndex]
                    oldNodesReused += 1

                    // If the node's corresponding widget isn't already at the correct
                    // position (accounting for insertions), then swap it with the widget
                    // at the target position and update our accounting accordinly.
                    if index != offset + oldIndex {
                        // When talking about current widget indices, we add `offset` to oldIndex.
                        // When talking about old element indices, we subtract `offset` from index.
                        swap(childAt: offset + oldIndex, withChildAt: index)
                        oldNodes.swapAt(oldIndex, index - offset)
                        oldIdentifierMap[oldIdentifiers[index - offset]] = oldIndex
                        oldIdentifiers.swapAt(oldIndex, index - offset)
                    }
                } else {
                    // If the identifier is new, create a node for it and insert its
                    // widget at the correct position.
                    node = AnyViewGraphNode(
                        for: childContent,
                        backend: backend,
                        environment: environment
                    )
                    insertChild(node.widget.into(), atIndex: index)

                    // `offset` tracks how many elements have been inserted, which we
                    // use to adjust old indices. All nodes before the one we just
                    // inserted are already at their final position, so we never have
                    // to adjust old indices that point to before our latest insertion, otherwise
                    // such a simple adjustment wouldn't be possible.
                    offset += 1
                }

                children.nodes.append(node)
                children.identifierMap[identifier] = index
                children.identifiers.append(identifier)
                children.layoutableChildren.append(
                    LayoutSystem.LayoutableChild(node) { child(element) }
                )
            }

            // TODO: We should be able to reuse unused widgets in newly created nodes.
            // Remove unused widgets, starting from the end of the container for
            // cheaper removals.
            let removalCount = oldNodes.count - oldNodesReused
            if removalCount > 0 {
                for i in (0..<removalCount).reversed() {
                    removeChild(atIndex: children.nodes.count + i)
                }
            }

            Self.warnIfEagerlyLarge(built: children.nodes.count - oldNodesReused)
        }

        // Recompute layoutable children if the last commit cleared them
        if children.layoutableChildren.isEmpty && !children.nodes.isEmpty {
            children.layoutableChildren = zip(children.nodes, elements).map { (node, element) in
                LayoutSystem.LayoutableChild(node) { child(element) }
            }
        }

        // Overlapping, when the enclosing stack overlaps -- the same branch
        // `Group` has, and for the same reason.
        //
        // `ForEach` is meant to be invisible to the layout system and can only
        // manage that by arranging its children the way its parent would have.
        // It inherits orientation, alignment and spacing for exactly that, but
        // a `ZStack` sets no orientation, so without this branch a `ForEach`
        // inside one fell back to whatever axis the *grandparent* used. Three
        // squares that should have overlapped appeared in a column, and the
        // enclosing frame did not even contain them.
        //
        // `layoutOverlapsChildren` was added when this was fixed for `Group`
        // (#158), and its own documentation says it exists so that "`Group` and
        // `ForEach`" can be transparent -- but only `Group` was ever wired up.
        // Found 2026-08-27 while trying to build a z-order test out of a
        // `ForEach` inside a `ZStack`, which could not work while the two were
        // not overlapping in the first place.
        //
        // 當外層 stack 為重疊式時走重疊排版——與 `Group` 相同的分支，理由也相同。
        //
        // `ForEach` 本應對排版系統隱形，而它做到這件事的唯一方式，就是「以父層原本會採用的方式」
        // 安排自己的子元件。它之所以繼承 orientation、alignment 與 spacing 正是為此；但 `ZStack`
        // 不設定 orientation，因此少了這個分支，`ZStack` 中的 `ForEach` 會退而採用**祖父層**所用的
        // 軸向。三個本應重疊的方塊變成排成一欄，甚至撐出了外層 frame。
        //
        // `layoutOverlapsChildren` 是在為 `Group` 修復此問題（#158）時加入的，其自身文件明寫此旗標
        // 的存在是為了讓「`Group` 與 `ForEach`」保持透明——但實際接上的只有 `Group`。此事於
        // 2026-08-27 被發現：當時正試圖以「`ZStack` 中的 `ForEach`」建立一項 z 順序測試，而在兩者
        // 根本沒有重疊的情況下，那項測試不可能成立。
        // Before the overlap branch, and for the same reason it exists: a
        // ForEach has to arrange its own children the way its parent would.
        // A LazyVGrid whose content is a ForEach -- nearly every one -- sees a
        // single child, so if this branch is missing the grid puts that one
        // child in column zero and the ForEach lays its cells out as a vertical
        // list. See GridLayoutPlan.
        // 置於 overlap 分支之前,理由與該分支存在的理由相同:ForEach 必須以父層原本會採用的方式
        // 安排自己的子元件。一個「內容是 ForEach」的 LazyVGrid——幾乎全部都是——只看得到單一個
        // 子節點,因此若少了這個分支,格線會把那一個子節點放進第 0 欄,而 ForEach 再把它的儲存格
        // 排成一個垂直清單。見 GridLayoutPlan。
        if let plan = environment.layoutGridPlan {
            let result = LayoutSystem.computeGridLayout(
                children: children.layoutableChildren,
                plan: plan,
                environment: environment,
                // true: these children ARE the cells.
                // true:這些子節點**就是**那些儲存格。
                clearsPlanForChildren: true
            )
            children.stackLayoutCache = StackLayoutCache(
                priorityGroups: [],
                isHidden: [],
                totalSpacing: 0,
                minimumLengths: [],
                redistributeSpaceOnCommit: false
            )
            return result
        }

        // Upstream's mechanism, taken in place of this tree's own.
        //
        // `layoutOverlapsChildren` was ours (e90a2b8d, for `Group` inside a
        // `ZStack`); upstream solved the same problem independently in #728 with
        // `usesZStackLayout` and a real ZStack layout rather than a plain
        // overlap. Two flags for one question is one too many, so ours goes and
        // theirs stays -- it also carries `zStackContentAlignment`, which the
        // overlap path could not, and this file used to say so as a known
        // limitation.
        //
        // 採用 upstream 的機制,取代本樹自有的那一套。
        //
        // `layoutOverlapsChildren` 是我們的(e90a2b8d,為了 `ZStack` 內的 `Group`);upstream 在
        // #728 中獨立地解了同一個問題,用的是 `usesZStackLayout` 與一套真正的 ZStack 版面,而非
        // 單純的重疊。同一個問題有兩個旗標就是多了一個,因此我們的移除、他們的保留——而且他們那套
        // 還帶著 `zStackContentAlignment`,那是重疊路徑做不到的,本檔過去正是把它記為一項已知限制。
        if environment.usesZStackLayout {
            let result = LayoutSystem.computeZStackLayout(
                container: widget,
                children: children.layoutableChildren,
                cache: &children.stackLayoutCache,
                proposedSize: proposedSize,
                environment: environment,
                backend: backend
            )
            children.stackLayoutCache = StackLayoutCache(
                priorityGroups: [],
                isHidden: [],
                totalSpacing: 0,
                minimumLengths: [],
                redistributeSpaceOnCommit: proposedSize.width == nil || proposedSize.height == nil
            )
            return result
        }

        return LayoutSystem.computeStackLayout(
            container: widget,
            children: children.layoutableChildren,
            cache: &children.stackLayoutCache,
            proposedSize: proposedSize,
            environment: environment,
            backend: backend
        )
    }

    @MainActor
    func deprecatedUpdate<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        @inline(__always)
        func insertChild(_ child: Backend.Widget, atIndex index: Int) {
            children.queuedChanges.append(.insertChild(AnyWidget(child), index))
        }

        @inline(__always)
        func removeChild(atIndex index: Int) {
            children.queuedChanges.append(.removeChild(index))
        }

        let elementsStartIndex = elements.startIndex

        var layoutableChildren: [LayoutSystem.LayoutableChild] = []
        for (i, node) in children.nodes.enumerated() {
            guard i < elements.count else {
                break
            }
            let index = elements.index(elementsStartIndex, offsetBy: i)
            if children.isFirstUpdate {
                insertChild(node.widget.into(), atIndex: i)
            }
            let layoutableChild = LayoutSystem.LayoutableChild(node) { child(elements[index]) }
            layoutableChildren.append(layoutableChild)
        }
        children.isFirstUpdate = false

        let nodeCount = children.nodes.count
        let remainingElementCount = elements.count - nodeCount
        if remainingElementCount > 0 {
            let startIndex = elements.index(elementsStartIndex, offsetBy: nodeCount)
            for i in 0..<remainingElementCount {
                let element = elements[elements.index(startIndex, offsetBy: i)]
                let node = AnyViewGraphNode(
                    for: child(element),
                    backend: backend,
                    environment: environment
                )
                insertChild(node.widget.into(), atIndex: children.nodes.count)
                children.nodes.append(node)
                let layoutableChild = LayoutSystem.LayoutableChild(node) { child(element) }
                layoutableChildren.append(layoutableChild)
            }
        } else if remainingElementCount < 0 {
            let unusedCount = -remainingElementCount
            for i in 0..<unusedCount {
                removeChild(atIndex: nodeCount - i - 1)
            }
            children.nodes.removeLast(unusedCount)
        }

        children.layoutableChildren = layoutableChildren

        return LayoutSystem.computeStackLayout(
            container: widget,
            children: layoutableChildren,
            cache: &children.stackLayoutCache,
            proposedSize: proposedSize,
            environment: environment,
            backend: backend
        )
    }

    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        for change in children.queuedChanges {
            switch change {
                case .insertChild(let child, let index):
                    backend.insert(child.into(), into: widget, at: index)
                case .removeChild(let index):
                    backend.remove(childAt: index, from: widget)
                case .swapChildren(let firstIndex, let secondIndex):
                    backend.swap(childAt: firstIndex, withChildAt: secondIndex, in: widget)
            }
        }
        children.queuedChanges = []

        // The commit half of the overlap branch in `computeLayout`. Both are
        // needed: computing an overlap layout and then committing a stack one
        // would size the children as though they overlapped and then place them
        // in a column.
        //
        // `.center`, matching `Group`'s note on the same call: `layoutAlignment`
        // is a `StackAlignment` and describes one axis, so the parent's
        // alignment is not available here. A `ZStack` with a non-default
        // alignment therefore aligns a direct child correctly and one inside a
        // `ForEach` to the centre. Stated rather than left implicit.
        //
        // `computeLayout` 中重疊分支的 commit 那一半。兩者缺一不可：以重疊方式計算版面、卻以 stack
        // 方式 commit，會得到「子元件依重疊計算尺寸、卻被排成一欄」的結果。
        //
        // 使用 `.center`，與 `Group` 在同一個呼叫處的註記一致：`layoutAlignment` 的型別是
        // `StackAlignment`，只描述單一軸向，因此此處取不到父層的對齊方式。帶有非預設對齊的
        // `ZStack`，對直接子元件會正確對齊，對包在 `ForEach` 內的則會置中。此處明言，不使其隱含。
        if let plan = environment.layoutGridPlan {
            LayoutSystem.commitGridLayout(
                container: widget,
                children: children.layoutableChildren,
                plan: plan,
                layout: layout,
                environment: environment,
                backend: backend
            )
            children.layoutableChildren = []
            return
        }

        if environment.usesZStackLayout {
            LayoutSystem.commitZStackLayout(
                container: widget,
                children: children.layoutableChildren,
                cache: &children.stackLayoutCache,
                layout: layout,
                environment: environment,
                backend: backend
            )
            children.layoutableChildren = []
            return
        }

        LayoutSystem.commitStackLayout(
            container: widget,
            children: children.layoutableChildren,
            cache: &children.stackLayoutCache,
            layout: layout,
            environment: environment,
            backend: backend
        )

        // Reset layoutable children cache so that we recompute them during the
        // next update cycle. This is important at the moment because the `child`
        // closure and `elements` array may have changed. In future we'll separate
        // view body recomputation from the computeLayout step, which should simplify
        // things.
        children.layoutableChildren = []
    }
}

/// Stores the child nodes of a ``ForEach`` view.
///
/// Also handles the ``ForEach`` view's widget unlike most ``ViewGraphNodeChildren``
/// implementations. This logic could mostly be moved into ``ForEach`` but it would still
/// be accessing ``ForEachViewChildren/storage`` so it'd just introduce an extra layer of
/// property accesses. It also means that the complexity is in a single type instead of
/// split across two.
///
/// Most of the complexity comes from resizing the list widget and moving around elements
/// when elements are added/removed.
class ForEachViewChildren<
    Items: Collection,
    ID: Hashable,
    Child: View
>: ViewGraphNodeChildren {
    /// The nodes for all current children of the ``ForEach`` view.
    var nodes: [AnyViewGraphNode<Child>] = []

    /// A map from element identifier to node index.
    var identifierMap: [ID: Int]

    /// The identifiers corresponding to ``nodes``.
    var identifiers: [ID]

    /// Changes queued during computeLayout.
    var queuedChanges: [Change] = []

    /// A queued widget operation to perform during `ForEach.commit`.
    enum Change: CustomStringConvertible {
        case insertChild(AnyWidget, Int)
        case removeChild(Int)
        case swapChildren(Int, Int)

        var description: String {
            switch self {
                case .insertChild(let widget, let index):
                    "Insert widget \(ObjectIdentifier(widget.widget as AnyObject)) at \(index)"
                case .removeChild(let index):
                    "Remove widget at \(index)"
                case .swapChildren(let firstIndex, let secondIndex):
                    "Swap widgets at \(firstIndex) and \(secondIndex)"
            }
        }
    }

    /// Only used by ``ForEach/deprecatedUpdate(_:children:proposedSize:environment:backend:)``.
    var isFirstUpdate = true

    /// A cache of the view's children, used when the ForEach's element
    /// identifiers haven't changed since the previous layout computation.
    var layoutableChildren: [LayoutSystem.LayoutableChild] = []

    var widgets: [AnyWidget] {
        nodes.map(\.widget)
    }

    // TODO: This pattern of erasing by wrapping in a temporary class seems
    //   inefficient. Could ErasedViewGraphNode maybe be a struct instead?
    var erasedNodes: [ErasedViewGraphNode] {
        nodes.map(ErasedViewGraphNode.init(wrapping:))
    }

    var stackLayoutCache = StackLayoutCache.initial

    init<Backend: BaseAppBackend>(
        from view: ForEach<Items, ID, Child>,
        backend: Backend,
        idKeyPath: KeyPath<Items.Element, ID>?,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) {
        identifierMap = [:]
        identifiers = []

        if idKeyPath == nil {
            // Deprecated code path. I'm not touching this anymore cause it's
            // gonna get deleted before any proper release.
            nodes = view.elements
                .map(view.child)
                .enumerated()
                .map { (index, child) in
                    let snapshot = index < snapshots?.count ?? 0 ? snapshots?[index] : nil
                    return ViewGraphNode(
                        for: child,
                        backend: backend,
                        snapshot: snapshot,
                        environment: environment
                    )
                }
                .map(AnyViewGraphNode.init(_:))
        } else {
            nodes = []
        }
    }
}

extension ForEach where ID == Int {
    /// Creates a view that creates child views on demand based on a collection of data.
    @available(
        *,
        deprecated,
        renamed: "init(_:id:_:)",
        message: """
            ForEach requires an explicit 'id' parameter for non-Identifiable \
            elements to correctly persist state across view updates
            """
    )
    @_disfavoredOverload
    public init(
        _ elements: Items,
        @ViewBuilder _ child: @escaping (Items.Element) -> Child
    ) {
        self.elements = elements
        self.child = child
        self.idKeyPath = nil
    }
}

extension ForEach where Items.Element: Identifiable, ID == Items.Element.ID {
    /// Creates a view that creates child views on demand based on a collection of identifiable data.
    public init(
        _ elements: Items,
        @ViewBuilder _ child: @escaping (Items.Element) -> Child
    ) {
        self.elements = elements
        self.child = child
        self.idKeyPath = \.id
    }
}

// MARK: Deprecated MenuItem-based inits

extension ForEach where ID == Int {
    /// Creates a view that creates child views on demand based on a collection of data.
    @available(
        *,
        deprecated,
        message: """
            ForEach requires an explicit 'id' parameter for non-Identifiable \
            elements to correctly persist state across view updates
            """
    )
    @_disfavoredOverload
    public init(
        menuItems elements: Items,
        @ViewBuilder _ child: @escaping (Items.Element) -> Child
    ) {
        self.elements = elements
        self.child = child
        self.idKeyPath = nil
    }
}

extension ForEach {
    /// Creates a view that creates child views on demand based on a collection of data.
    @available(
        *,
        deprecated,
        renamed: "init(_:id:_:)",
        message: """
            Special treatment of menu item ForEach blocks is no longer necessary. \
            Remove the menuItems parameter label.
            """
    )
    public init(
        menuItems elements: Items,
        id keyPath: KeyPath<Items.Element, ID>,
        @ViewBuilder _ child: @escaping (Items.Element) -> Child
    ) {
        self.elements = elements
        self.child = child
        self.idKeyPath = keyPath
    }
}

extension ForEach where Items.Element: Identifiable, ID == Items.Element.ID {
    /// Creates a view that creates child views on demand based on a collection of data.
    @available(
        *,
        deprecated,
        renamed: "init(_:_:)",
        message: """
            Special treatment of menu item ForEach blocks is no longer necessary. \
            Remove the menuItems parameter label.
            """
    )
    public init(
        menuItems elements: Items,
        @ViewBuilder _ child: @escaping (Items.Element) -> Child
    ) {
        self.elements = elements
        self.child = child
        self.idKeyPath = \.id
    }
}
