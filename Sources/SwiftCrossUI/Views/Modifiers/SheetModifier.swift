extension View {
    /// Presents a conditional modal overlay. `onDismiss` gets invoked when the
    /// sheet is dismissed.
    ///
    /// On most platforms sheets appear as form-style modals. On tvOS, sheets
    /// appear as full screen overlays (non-opaque).
    ///
    /// `onDismiss` isn't called when the sheet gets dismissed programmatically
    /// (i.e. by setting `isPresented` to `false`).
    ///
    /// `onDismiss` gets called *after* the sheet has been dismissed by the
    /// underlying UI framework, and *before* `isPresented` gets set to false.
    ///
    /// - Parameters:
    ///   - isPresented: A binding controlling whether the sheet is presented.
    ///   - onDismiss: An action to perform when the sheet is dismissed
    ///     by the user.
    ///   - content: The content of the sheet
    public func sheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        SheetModifier(
            isPresented: isPresented,
            body: TupleView1(self),
            onDismiss: onDismiss,
            sheetContent: content
        )
    }
}

struct SheetModifier<Content: View, SheetContent: View>: TypeSafeView {
    /// Whether these detents ask for the whole presentation.
    ///
    /// `.large` and a fraction of one or more both mean it. The rest of the
    /// vocabulary describes a partial height, which is a mobile idea and is
    /// left to the backends that have one.
    ///
    /// 這些 detent 是否要求佔滿整個呈現空間。
    ///
    /// `.large` 與大於等於一的 fraction 都代表如此。其餘的詞彙描述的是部分高度,那是行動裝置的概念,
    /// 留給具備該概念的 backend 處理。
    static func fillsPresentation(_ detents: [PresentationDetent]?) -> Bool {
        guard let detents else { return false }
        return detents.contains { detent in
            switch detent {
                case .large:
                    true
                case .fraction(let fraction):
                    fraction >= 1
                case .medium, .height:
                    false
            }
        }
    }

    typealias Children = SheetModifierViewChildren<Content, SheetContent>

    var isPresented: Binding<Bool>
    var body: TupleView1<Content>
    var onDismiss: (() -> Void)?
    var sheetContent: () -> SheetContent

    var sheet: Any?

    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> Children {
        let bodyViewGraphNode = ViewGraphNode(
            for: body.view0,
            backend: backend,
            environment: environment
        )
        let bodyNode = AnyViewGraphNode(bodyViewGraphNode)

        return SheetModifierViewChildren(
            childNode: bodyNode,
            sheetContentNode: nil,
            sheet: nil
        )
    }

    func asWidget<Backend: BaseAppBackend>(
        _ children: Children,
        backend: Backend
    ) -> Backend.Widget {
        children.childNode.widget.into()
    }

    func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        children.childNode.computeLayout(
            with: body.view0,
            proposedSize: proposedSize,
            environment: environment
        )
    }

    @CastBackend<BackendFeatures.Sheets>(backendGenericName: "NewBackend")
    func commit<Backend: BaseAppBackend>(
        _: Backend.Widget,
        children: Children,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        _ = children.childNode.commit()

        if isPresented.wrappedValue {
            let needsPresenting = children.sheet == nil

            let sheet: NewBackend.Sheet
            if children.sheetContentNode == nil {
                let sheetViewGraphNode = ViewGraphNode(
                    for: sheetContent(),
                    backend: backend,
                    environment: environment
                )
                let sheetContentNode = AnyViewGraphNode(sheetViewGraphNode)
                children.sheetContentNode = sheetContentNode

                sheet = backend.createSheet(
                    content: children.sheetContentNode!.widget.into()
                )
            } else {
                guard
                    let existingSheet = children.sheet,
                    let castedSheet = existingSheet as? NewBackend.Sheet
                else {
                    logger.warning(
                        """
                        SheetModifier has a nil sheet, even though the sheet \
                        has already been presented
                        """
                    )
                    return
                }
                sheet = castedSheet
            }

            let dismissAction = DismissAction(action: { [isPresented] in
                isPresented.wrappedValue = false
            })

            let sheetEnvironment =
                environment
                    .with(\.dismiss, dismissAction)
                    .with(\.sheet, sheet)

            _ = children.sheetContentNode!.computeLayout(
                with: sheetContent(),
                proposedSize: .unspecified,
                environment: sheetEnvironment
            )
            var result = children.sheetContentNode!.commit()

            let window = environment.window!

            // A second pass, when and only when the content asked to fill the
            // presentation.
            //
            // The detents are a PREFERENCE, so they are not known until the
            // content has been laid out once -- and the first pass proposes
            // `.unspecified`, which is the content's ideal size. That is right
            // for a sheet and wrong for anything asking to fill, and it is why
            // `.fraction(1)` had no effect on ANY backend rather than on one of
            // them: nothing was ever proposed the larger size, so no backend
            // ever received it. AppKitBackend was blamed first, and sizing its
            // NSWindow directly changed nothing, because the sheet's content
            // view is pinned to its content by constraints and the constraints
            // win.
            //
            // 第二輪,而且僅在內容要求填滿呈現空間時才發生。
            //
            // detents 是一項 preference,因此在內容被佈局過一次之前無從得知——而第一輪提議的是
            // `.unspecified`,也就是內容的理想尺寸。那對 sheet 是對的,對任何要求填滿的東西則是錯的;
            // 這也正是 `.fraction(1)` 在**每一個** backend 上都無效、而非只在其中一個上無效的原因:
            // 從來沒有任何東西被提議過那個較大的尺寸,因此沒有任何 backend 收到過它。最初被歸咎的是
            // AppKitBackend,而直接設定它的 NSWindow 尺寸什麼都沒有改變,因為 sheet 的 content view
            // 是以約束釘在其內容上的,而約束會贏。
            if Self.fillsPresentation(result.preferences.presentationDetents) {
                let windowSize = backend.size(ofWindow: window as! NewBackend.Window)
                _ = children.sheetContentNode!.computeLayout(
                    with: sheetContent(),
                    proposedSize: ProposedViewSize(
                        Double(windowSize.x),
                        Double(windowSize.y)
                    ),
                    environment: sheetEnvironment
                )
                result = children.sheetContentNode!.commit()
            }

            let preferences = result.preferences
            backend.updateSheet(
                sheet,
                window: window as! NewBackend.Window,
                // We intentionally use the outer environment rather than
                // sheetEnvironment here, because this is meant to be the sheet's
                // environment, not that of its content.
                environment: environment,
                size: result.size.vector,
                onDismiss: { handleDismiss(children: children) },
                cornerRadius: preferences.presentationCornerRadius,
                detents: preferences.presentationDetents ?? [],
                dragIndicatorVisibility: preferences.presentationDragIndicatorVisibility
                    ?? .automatic,
                backgroundColor: preferences.presentationBackground?.resolve(in: environment),
                interactiveDismissDisabled: preferences.interactiveDismissDisabled ?? false
            )

            let parentSheet = environment.sheet.map { $0 as! NewBackend.Sheet }

            if needsPresenting {
                backend.presentSheet(
                    sheet,
                    window: window as! NewBackend.Window,
                    parentSheet: parentSheet
                )
            }

            children.sheet = sheet
            children.window = window
            children.parentSheet = parentSheet
        } else if !isPresented.wrappedValue && children.sheet != nil {
            backend.dismissSheet(
                children.sheet as! NewBackend.Sheet,
                window: children.window! as! NewBackend.Window,
                parentSheet: children.parentSheet.map { $0 as! NewBackend.Sheet }
            )
            children.sheet = nil
            children.window = nil
            children.parentSheet = nil
            children.sheetContentNode = nil
        }
    }

    func handleDismiss(children: Children) {
        onDismiss?()
        children.sheet = nil
        children.window = nil
        children.parentSheet = nil
        children.sheetContentNode = nil
        isPresented.wrappedValue = false
    }
}

class SheetModifierViewChildren<Child: View, SheetContent: View>: ViewGraphNodeChildren {
    var widgets: [AnyWidget] {
        [childNode.widget]
    }

    var erasedNodes: [ErasedViewGraphNode] {
        var nodes: [ErasedViewGraphNode] = [ErasedViewGraphNode(wrapping: childNode)]
        if let sheetContentNode {
            nodes.append(ErasedViewGraphNode(wrapping: sheetContentNode))
        }
        return nodes
    }

    var childNode: AnyViewGraphNode<Child>
    var sheetContentNode: AnyViewGraphNode<SheetContent>?
    var sheet: Any?
    var window: Any?
    var parentSheet: Any?

    init(
        childNode: AnyViewGraphNode<Child>,
        sheetContentNode: AnyViewGraphNode<SheetContent>?,
        sheet: Any?
    ) {
        self.childNode = childNode
        self.sheetContentNode = sheetContentNode
        self.sheet = sheet
    }
}
