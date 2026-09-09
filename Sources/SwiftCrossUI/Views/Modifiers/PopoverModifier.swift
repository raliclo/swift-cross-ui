extension View {
    /// Presents `content` in a popover anchored to this view, while
    /// `isPresented` is true.
    ///
    /// Anchored is the whole of the difference from
    /// ``View/sheet(isPresented:onDismiss:content:)``: the popover points at
    /// the view it is attached to, and every one of the five backends draws it
    /// with its own native popover -- `NSPopover`,
    /// `UIPopoverPresentationController`, `GtkPopover`, WinUI's `Flyout`,
    /// Android's `PopupWindow`. On iPhone, UIKit itself adapts a popover into a
    /// sheet, which is the platform's own answer to a screen too small to point
    /// at anything, and is not this toolkit substituting one presentation for
    /// another.
    ///
    /// 在 `isPresented` 為真時，以一個錨定於本 view 的 popover 呈現 `content`。
    ///
    /// 「有錨點」就是它與 ``View/sheet(isPresented:onDismiss:content:)`` 的全部差異:popover 指向它所
    /// 附著的那個 view，而五個 backend 每一個都以自身的原生 popover 繪製它——`NSPopover`、
    /// `UIPopoverPresentationController`、`GtkPopover`、WinUI 的 `Flyout`、Android 的 `PopupWindow`。
    /// 在 iPhone 上，UIKit 自己會把 popover 調適為 sheet,那是該平台對於「螢幕小到無法指向任何東西」
    /// 所給出的答案,並不是本工具組拿一種呈現去替換另一種。
    public func popover<PopoverContent: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> PopoverContent
    ) -> some View {
        PopoverModifier(
            isPresented: isPresented,
            body: TupleView1(self),
            onDismiss: onDismiss,
            popoverContent: content
        )
    }
}

struct PopoverModifier<Content: View, PopoverContent: View>: TypeSafeView {
    typealias Children = PopoverModifierViewChildren<Content, PopoverContent>

    var isPresented: Binding<Bool>
    var body: TupleView1<Content>
    var onDismiss: (() -> Void)?
    var popoverContent: () -> PopoverContent

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
        return PopoverModifierViewChildren(
            childNode: AnyViewGraphNode(bodyViewGraphNode),
            popoverContentNode: nil,
            popover: nil
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

    @CastBackend<BackendFeatures.Popovers>(backendGenericName: "NewBackend")
    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        _ = children.childNode.commit()

        if isPresented.wrappedValue {
            let needsPresenting = children.popover == nil
            let popover: NewBackend.Popover

            if children.popoverContentNode == nil {
                let node = ViewGraphNode(
                    for: popoverContent(),
                    backend: backend,
                    environment: environment
                )
                children.popoverContentNode = AnyViewGraphNode(node)
                popover = backend.createPopover(
                    content: children.popoverContentNode!.widget.into()
                )
            } else {
                guard
                    let existing = children.popover,
                    let casted = existing as? NewBackend.Popover
                else {
                    logger.warning(
                        """
                        PopoverModifier has a nil popover, even though the \
                        popover has already been presented
                        """
                    )
                    return
                }
                popover = casted
            }

            let dismissAction = DismissAction(action: { [isPresented] in
                isPresented.wrappedValue = false
            })

            // The popover's content is laid out at its ideal size, and unlike a
            // sheet there is no detent that can ask for more: a popover is as
            // big as what it contains, on all five platforms, and one that
            // filled the window would not be a popover.
            // popover 的內容以其理想尺寸佈局,而與 sheet 不同的是,此處沒有任何 detent 能要求更多:
            // 在五個平台上,popover 的大小就是它所容納之物的大小,而一個填滿視窗的 popover 也就不是
            // popover 了。
            _ = children.popoverContentNode!.computeLayout(
                with: popoverContent(),
                proposedSize: .unspecified,
                environment: environment.with(\.dismiss, dismissAction)
            )
            let result = children.popoverContentNode!.commit()

            let window = environment.window!
            // The same field `SheetModifier` reads, from the same place: the
            // content's own commit result. `presentationBackground` was already
            // a modifier and a `PreferenceValues` field before this -- only the
            // popover path never collected it, so the whole of "colour a popover
            // when asked" was one argument away.
            //
            // Resolved against the OUTER environment, matching the sheet: the
            // colour describes the presentation, not the content inside it.
            //
            // 與 `SheetModifier` 讀的是同一個欄位、同一個來源:內容自身的 commit 結果。在此之前
            // `presentationBackground` 就已經是一個 modifier 與一個 `PreferenceValues` 欄位——
            // 只有 popover 這條路從未收集它,因此「有要求時為 popover 上色」整件事只差一個引數。
            //
            // 以**外層** environment 解析,與 sheet 一致:該顏色描述的是這個 presentation 本身,
            // 而不是它內部的內容。
            backend.updatePopover(
                popover,
                environment: environment,
                size: result.size.vector,
                backgroundColor: result.preferences.presentationBackground?
                    .resolve(in: environment),
                onDismiss: { handleDismiss(children: children) }
            )

            if needsPresenting {
                backend.presentPopover(
                    popover,
                    // The anchor is this modifier's own widget, which is the
                    // child's widget -- see `asWidget`. That is what makes the
                    // popover point at the view it was attached to rather than
                    // at the window.
                    // 錨點是本 modifier 自身的 widget,也就是其子節點的 widget——見 `asWidget`。
                    // 那正是讓 popover 指向「它所附著的那個 view」而非指向視窗的原因。
                    relativeTo: widget,
                    window: window as! NewBackend.Window
                )
            }

            children.popover = popover
            children.window = window
        } else if !isPresented.wrappedValue && children.popover != nil {
            backend.dismissPopover(
                children.popover as! NewBackend.Popover,
                window: children.window! as! NewBackend.Window
            )
            children.popover = nil
            children.window = nil
            children.popoverContentNode = nil
        }
    }

    func handleDismiss(children: Children) {
        onDismiss?()
        children.popover = nil
        children.window = nil
        children.popoverContentNode = nil
        isPresented.wrappedValue = false
    }
}

class PopoverModifierViewChildren<Child: View, PopoverContent: View>: ViewGraphNodeChildren {
    var widgets: [AnyWidget] {
        [childNode.widget]
    }

    var erasedNodes: [ErasedViewGraphNode] {
        var nodes: [ErasedViewGraphNode] = [ErasedViewGraphNode(wrapping: childNode)]
        if let popoverContentNode {
            nodes.append(ErasedViewGraphNode(wrapping: popoverContentNode))
        }
        return nodes
    }

    var childNode: AnyViewGraphNode<Child>
    var popoverContentNode: AnyViewGraphNode<PopoverContent>?
    var popover: Any?
    var window: Any?

    init(
        childNode: AnyViewGraphNode<Child>,
        popoverContentNode: AnyViewGraphNode<PopoverContent>?,
        popover: Any?
    ) {
        self.childNode = childNode
        self.popoverContentNode = popoverContentNode
        self.popover = popover
    }
}
