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
            EnvironmentModifier(sidebar()) { $0.with(\.listStyle, .sidebar) },
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
        // 臨時診斷：設定 SCUI_DEBUG_SPLIT 可看到傳給 backend 的上下界與分隔線最後
        // 的位置。backend 只能回報它採用的寬度，app 只能量到內容尺寸，因此這些真正
        // 決定版面的數字在別處都看不到。把內容寬度誤讀為 pane 寬度，曾對 #556 造成
        // 兩次自信但錯誤的判斷。
        if ProcessInfo.processInfo.environment["SCUI_DEBUG_SPLIT"] != nil {
            let maximum = LayoutSystem.roundSize(
                max(
                    children.minimumLeadingWidth,
                    layout.size.width - children.minimumTrailingWidth
                )
            )
            let line =
                "[SplitView] total=\(layout.size.width)"
                + " minLeading=\(children.minimumLeadingWidth)"
                + " minTrailing=\(children.minimumTrailingWidth)"
                + " -> bounds min=\(LayoutSystem.roundSize(children.minimumLeadingWidth))"
                + " max=\(maximum)"
                + " currentSidebar=\(leadingWidth)"
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
