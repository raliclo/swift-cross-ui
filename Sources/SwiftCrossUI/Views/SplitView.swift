import Foundation

/// A two-column split view.
struct SplitView<Sidebar: View, Detail: View>: TypeSafeView, View {
    typealias Children = SplitViewChildren<EnvironmentModifier<Sidebar>, Detail>

    var body: TupleView2<EnvironmentModifier<Sidebar>, Detail>

    /// Creates a two-column split view.
    ///
    /// - Parameters:
    ///   - sidebar: The sidebar content.
    ///   - detail: The detail content.
    init(@ViewBuilder sidebar: () -> Sidebar, @ViewBuilder detail: () -> Detail) {
        body = TupleView2(
            // Both entries, because a backend reads the resolved one and an
            // application reads the other. Written here rather than through
            // `.listStyle(_:)` so the sidebar's own style is not something a
            // caller can accidentally override by setting a style further out.
            // 兩個條目都寫入，因為 backend 讀的是已解析的那個、應用程式讀的是另一個。此處直接寫入
            // 而不透過 `.listStyle(_:)`，如此側邊欄自身的樣式便不會被「在更外層設定樣式」的呼叫端
            // 意外覆蓋。
            EnvironmentModifier(sidebar()) {
                $0
                    .with(\.listStyle, .sidebar)
                    .with(\.backendListStyle, .sidebar)
            },
            detail()
        )
    }

    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> Children {
        SplitViewChildren(
            wrapping: body.children(
                backend: backend,
                snapshots: snapshots,
                environment: environment
            ),
            backend: backend
        )
    }

    func asWidget<Backend: BaseAppBackend>(
        _ children: Children,
        backend: Backend
    ) -> Backend.Widget {
        return backend.createSplitView(
            leadingChild: children.leadingPaneContainer.into(),
            trailingChild: children.trailingPaneContainer.into()
        )
    }

    func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        let leadingWidth = Double(backend.sidebarWidth(ofSplitView: widget))

        // TODO: If computeLayout ever becomes a pure requirement of View, then we
        //   can delay this until commit.
        children.minimumLeadingWidth =
            children.leadingChild.computeLayout(
                with: body.view0,
                proposedSize: ProposedViewSize(
                    0,
                    proposedSize.height
                ),
                environment: environment
            ).size.width

        children.minimumTrailingWidth =
            children.trailingChild.computeLayout(
                with: body.view1,
                proposedSize: ProposedViewSize(
                    0,
                    proposedSize.height
                ),
                environment: environment
            ).size.width

        // TODO: Figure out proper fixedSize behaviour (when width is unspecified)
        // Update pane children
        let leadingResult = children.leadingChild.computeLayout(
            with: body.view0,
            proposedSize: ProposedViewSize(
                proposedSize.width == nil ? nil : leadingWidth,
                proposedSize.height
            ),
            environment: environment
        )
        let trailingResult = children.trailingChild.computeLayout(
            with: body.view1,
            proposedSize: ProposedViewSize(
                proposedSize.width.map { $0 - max(leadingWidth, leadingResult.size.width) },
                proposedSize.height
            ),
            environment: environment
        )

        // Update split view size and sidebar width bounds
        let leadingContentSize = leadingResult.size
        let trailingContentSize = trailingResult.size
        children.lastLeadingContentSize = leadingContentSize
        children.lastTrailingContentSize = trailingContentSize
        var size = ViewSize(
            leadingContentSize.width + trailingContentSize.width,
            max(leadingContentSize.height, trailingContentSize.height)
        )

        if let proposedWidth = proposedSize.width {
            size.width = max(size.width, proposedWidth)
        }
        if let proposedHeight = proposedSize.height {
            size.height = max(size.height, proposedHeight)
        }

        return ViewLayoutResult(
            size: size,
            childResults: [leadingResult, trailingResult]
        )
    }

    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        backend.setResizeHandler(ofSplitView: widget) {
            // The parameter to onResize is currently unused
            environment.onResize(.zero)
        }

        let leadingWidth = backend.sidebarWidth(ofSplitView: widget)
        let leadingResult = children.leadingChild.commit()
        let trailingResult = children.trailingChild.commit()

        backend.setSize(of: widget, to: layout.size.vector)

        // Temporary: set SCUI_DEBUG_SPLIT to see the bounds this hands the
        // backend, and where the divider ended up. A backend can only report
        // the width it settled on, and the app can only measure content, so
        // these are the numbers that decide the layout and they are otherwise
        // invisible. Reading a content width as a pane width produced two
        // confident, wrong diagnoses of #556.
        //
        // `leadingContent` and `trailingContent` are here for #160, which is
        // about what the panes get on the first layout pass versus after a
        // state change. A test app cannot obtain them: anything it adds to the
        // view tree to do the measuring becomes part of what is measured, and
        // in this framework `overlay` is not exempt -- `OverlayModifier` sizes
        // its host as `max(content, overlay)`. Reported from here, the numbers
        // cost the layout nothing.
        //
        // They are content sizes, not pane sizes, and the names say so
        // deliberately. A pane's child is offered the pane's width and answers
        // with what it wants, which can be less -- in P7 a trailing child
        // offered 220 answered 207. The pane widths are `currentSidebar` and
        // `total` minus it. Confusing the two is what produced two confident,
        // wrong diagnoses of #556, and a field named `leadingPane` would have
        // invited it a third time.
        //
        // One line is emitted per SplitView per commit, and a three-column
        // NavigationSplitView is two nested SplitViews, so expect two lines
        // per pass: the outer one's trailing pane is the inner split view.
        // 臨時診斷：設定 SCUI_DEBUG_SPLIT 可看到傳給 backend 的上下界與分隔線最後
        // 的位置。backend 只能回報它採用的寬度，app 只能量到內容尺寸，因此這些真正
        // 決定版面的數字在別處都看不到。把內容寬度誤讀為 pane 寬度，曾對 #556 造成
        // 兩次自信但錯誤的判斷。
        //
        // `leadingContent` 與 `trailingContent` 是為 #160 而加的——該問題正是關於「第一次版面
        // 計算時各窗格得到什麼」與「狀態改變之後」之差異。測試 app 拿不到這兩個數字：
        // 任何為了量測而加進 view tree 的東西，都會變成被量測對象的一部分，而在本框架中
        // `overlay` 並不例外——`OverlayModifier` 是以 `max(content, overlay)` 決定其宿主尺寸。
        // 從這裡回報則完全不影響版面。
        //
        // 它們是**內容**尺寸而非窗格尺寸，命名刻意如此。窗格的子視圖收到的是窗格寬度的提議，
        // 而它回答的可以更小——P7 中 trailing 子視圖收到 220 的提議，回答 207。窗格寬度是
        // `currentSidebar` 以及 `total` 減去它。把兩者混為一談，正是 #556 兩次自信但錯誤判斷的
        // 成因；一個叫做 `leadingPane` 的欄位只會招來第三次。
        //
        // 每個 SplitView 每次 commit 輸出一行，而三欄的 NavigationSplitView 是兩層巢狀的
        // SplitView，因此每一輪應有兩行：外層的 trailing 窗格就是內層那個 split view。
        if ProcessInfo.processInfo.environment["SCUI_DEBUG_SPLIT"] != nil {
            let maximum = LayoutSystem.roundSize(
                max(
                    children.minimumLeadingWidth,
                    layout.size.width - children.minimumTrailingWidth
                )
            )
            let leading = children.lastLeadingContentSize
            let trailing = children.lastTrailingContentSize
            let line =
                "[SplitView] total=\(layout.size.width)"
                + " minLeading=\(children.minimumLeadingWidth)"
                + " minTrailing=\(children.minimumTrailingWidth)"
                + " -> bounds min=\(LayoutSystem.roundSize(children.minimumLeadingWidth))"
                + " max=\(maximum)"
                + " currentSidebar=\(leadingWidth)"
                + " leadingContent=\(leading.width)x\(leading.height)"
                + " trailingContent=\(trailing.width)x\(trailing.height)"
            print(line)
            // Also to a file: a WinUI app has no console, so stdout is lost
            // there and this comparison needs both backends.
            if let data = "\(line)\n".data(using: .utf8) {
                let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                    .appendingPathComponent("splitview-debug.log")
                if let handle = try? FileHandle(forWritingTo: url) {
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                    try? handle.close()
                } else {
                    try? data.write(to: url)
                }
            }
        }

        backend.setSidebarWidthBounds(
            ofSplitView: widget,
            minimum: LayoutSystem.roundSize(children.minimumLeadingWidth),
            maximum: LayoutSystem.roundSize(
                max(
                    children.minimumLeadingWidth,
                    layout.size.width - children.minimumTrailingWidth
                )
            )
        )

        // Center pane children, but never at a negative offset.
        //
        // Centring assumes the child fits. When it does not, half the overflow
        // becomes a negative origin and the content is clipped at its leading
        // edge as well as its trailing one: a sidebar list rendered
        // "Elderberry" as "berry", losing the same number of pixels from the
        // start of every row.
        //
        // Widening the pane does not remove the need for this. With the sidebar
        // opened at 200 instead of 87, the list still measures wider than its
        // pane on some layout passes, so the negative origin still happens --
        // just less often. Clipping is unavoidable once the child is too big;
        // which end gets clipped is not, and the start of the content is the
        // part worth keeping.
        // 置中的前提是子元件放得下。放不下時，溢出的一半會變成負的原點，內容的
        // 開頭與結尾都被裁掉——sidebar 清單會把 "Elderberry" 畫成 "berry"，每一列
        // 都從開頭少掉同樣的像素寬。加寬 pane 並不能取代這個修正：sidebar 開在 200
        // 而非 87 之後，清單在某些 layout pass 仍然寬於它的 pane。
        backend.setPosition(
            ofChildAt: 0,
            in: children.leadingPaneContainer.into(),
            to: SIMD2(
                max(0, leadingWidth - leadingResult.size.vector.x),
                max(0, layout.size.vector.y - leadingResult.size.vector.y)
            ) / 2
        )
        backend.setPosition(
            ofChildAt: 0,
            in: children.trailingPaneContainer.into(),
            to: SIMD2(
                max(0, layout.size.vector.x - leadingWidth - trailingResult.size.vector.x),
                max(0, layout.size.vector.y - trailingResult.size.vector.y)
            ) / 2
        )
    }
}

class SplitViewChildren<Sidebar: View, Detail: View>: ViewGraphNodeChildren {
    var paneChildren: TupleView2<Sidebar, Detail>.Children
    var leadingPaneContainer: AnyWidget
    var trailingPaneContainer: AnyWidget
    var minimumLeadingWidth: Double
    var minimumTrailingWidth: Double
    /// The sizes the two panes' *contents* last chose, kept only so that
    /// `commit` can report them. `ViewLayoutResult` does not store
    /// `childResults` -- it merges their preferences and discards them -- so by
    /// the time `commit` runs, these are gone unless they are stashed here,
    /// alongside the minimums that are stashed for the same reason.
    ///
    /// Content, not pane. A pane's child is offered the pane's width and
    /// answers with what it wants, which can be less: measured in P7, a
    /// trailing child offered 220 answered 207. The pane widths are
    /// `sidebarWidth(ofSplitView:)` and the split view's width minus it.
    /// 兩個窗格**內容**上一次選擇的尺寸，存放於此僅為了讓 `commit` 能回報它們。
    /// `ViewLayoutResult` 並未儲存 `childResults`——它合併其 preferences 後就丟棄——
    /// 因此 `commit` 執行時這些數字已不復存在，除非像那兩個 minimum 一樣先存下來。
    ///
    /// 是內容，不是窗格。窗格的子視圖收到的是窗格寬度的提議，而它回答的可以更小：P7 實測，
    /// trailing 子視圖收到 220 的提議，回答 207。窗格寬度是
    /// `sidebarWidth(ofSplitView:)` 以及「split view 寬度減去它」。
    var lastLeadingContentSize: ViewSize
    var lastTrailingContentSize: ViewSize

    init<Backend: BaseAppBackend>(
        wrapping children: TupleView2<Sidebar, Detail>.Children,
        backend: Backend
    ) {
        self.paneChildren = children

        let leadingPaneContainer = backend.createContainer()
        backend.insert(
            paneChildren.child0.widget.into(),
            into: leadingPaneContainer,
            at: 0
        )
        let trailingPaneContainer = backend.createContainer()
        backend.insert(
            paneChildren.child1.widget.into(),
            into: trailingPaneContainer,
            at: 0
        )

        self.leadingPaneContainer = AnyWidget(leadingPaneContainer)
        self.trailingPaneContainer = AnyWidget(trailingPaneContainer)
        self.minimumLeadingWidth = 0
        self.minimumTrailingWidth = 0
        self.lastLeadingContentSize = .zero
        self.lastTrailingContentSize = .zero
    }

    var erasedNodes: [ErasedViewGraphNode] {
        paneChildren.erasedNodes
    }

    var widgets: [AnyWidget] {
        [
            leadingPaneContainer,
            trailingPaneContainer,
        ]
    }

    var leadingChild: AnyViewGraphNode<Sidebar> {
        paneChildren.child0
    }

    var trailingChild: AnyViewGraphNode<Detail> {
        paneChildren.child1
    }
}
