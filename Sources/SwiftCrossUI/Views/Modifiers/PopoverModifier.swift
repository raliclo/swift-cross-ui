extension View {
    /// Presents a transient panel of content anchored to this view.
    ///
    /// A popover is light-dismiss: clicking outside it, or pressing escape,
    /// closes it and calls `onDismiss`. It is positioned against this view
    /// rather than against the window, which is the whole difference between it
    /// and ``View/sheet(isPresented:onDismiss:content:)`` -- see
    /// ``BackendFeatures/Popovers`` for why that difference needed a backend
    /// protocol of its own rather than a parameter added to `Sheets`.
    ///
    /// `onDismiss` is *not* called when the popover is closed programmatically
    /// (by setting `isPresented` to `false`), matching `sheet`.
    ///
    /// **Platform shapes, none of which is a fallback.** macOS gets an
    /// `NSPopover` with a beak; Windows a WinUI `Flyout`; GTK a `GtkPopover`;
    /// iPad a `UIPopoverPresentationController`. On iPhone, where UIKit's own
    /// adaptation would turn a popover into a full-screen sheet, UIKitBackend
    /// asks for `.none` so it stays a popover -- SwiftUI's `.popover` behaves
    /// as a sheet there, and this deliberately does not, because a caller who
    /// wanted a sheet has `sheet`. Android gets a `PopupWindow` anchored to the
    /// view, which is the primitive its own menus and autocomplete drop-downs
    /// are built from.
    ///
    /// **On a backend that does not implement ``BackendFeatures/Popovers``,**
    /// this warns once and renders the anchor view unmodified. That is the
    /// sanctioned answer for `CursesBackend`, `LVGLBackend`, `QtBackend` and
    /// `DummyBackend` -- and *only* for those. All five shipped backends
    /// conform, so none of them reaches that branch; if one ever does, the
    /// warning is the bug report.
    ///
    /// - Parameters:
    ///   - isPresented: A binding controlling whether the popover is presented.
    ///   - attachmentEdge: The edge of this view the popover should prefer to
    ///     appear from. Backends flip it when the requested side would run off
    ///     the screen.
    ///   - onDismiss: An action to perform when the popover is dismissed by the
    ///     user.
    ///   - content: The content of the popover.
    ///
    /// 呈現一塊錨定於此 view 的短暫內容面板。
    ///
    /// popover 採點擊外部即關閉：在它之外點擊、或按下 escape，都會關閉它並呼叫 `onDismiss`。它是
    /// 相對於此 view 定位，而非相對於視窗定位，這正是它與
    /// ``View/sheet(isPresented:onDismiss:content:)`` 的全部差異——關於這項差異為何需要一個屬於
    /// 自己的 backend protocol，而不是在 `Sheets` 上加一個參數，見 ``BackendFeatures/Popovers``。
    ///
    /// 當 popover 是以程式方式關閉時（將 `isPresented` 設為 `false`），`onDismiss` **不會**被呼叫，
    /// 與 `sheet` 一致。
    ///
    /// **各平台的形態，其中沒有任何一種是後備方案。** macOS 得到帶尖角的 `NSPopover`；Windows 得到
    /// WinUI 的 `Flyout`；GTK 得到 `GtkPopover`；iPad 得到 `UIPopoverPresentationController`。
    /// 在 iPhone 上，UIKit 自身的調適會把 popover 變成全螢幕 sheet，因此 UIKitBackend 要求 `.none`
    /// 以維持它是 popover——SwiftUI 的 `.popover` 在該處的行為即為 sheet，而此處刻意不如此，因為
    /// 想要 sheet 的呼叫端有 `sheet` 可用。Android 得到錨定於該 view 的 `PopupWindow`，那正是它自身
    /// 的選單與自動完成下拉所建構於其上的基本元件。
    ///
    /// **在未實作 ``BackendFeatures/Popovers`` 的 backend 上，** 本 modifier 會警告一次，並原樣繪製
    /// 錨點 view。那是給 `CursesBackend`、`LVGLBackend`、`QtBackend` 與 `DummyBackend` 的既定答案
    /// ——而且**僅限**這些。五個已發布的 backend 全部 conform，因此它們都不會走到那個分支；若哪天
    /// 有一個走到了，那則警告就是它的錯誤回報。
    public func popover<PopoverContent: View>(
        isPresented: Binding<Bool>,
        attachmentEdge: Edge = .bottom,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> PopoverContent
    ) -> some View {
        PopoverModifier(
            isPresented: isPresented,
            attachmentEdge: attachmentEdge,
            body: TupleView1(self),
            onDismiss: onDismiss,
            popoverContent: content
        )
    }
}

/// The view that drives ``View/popover(isPresented:attachmentEdge:onDismiss:content:)``.
///
/// Modelled closely on `SheetModifier`, and intentionally so: the presentation
/// lifecycle -- create once, update every pass, present once, dismiss on the
/// falling edge -- is the same one, and two presentation modifiers that
/// disagree about it would diverge under nesting.
///
/// It differs from `SheetModifier` in three ways, all forced:
///
/// - **It anchors to its own widget.** `asWidget` returns the child's widget, so
///   the `widget` handed to `commit` *is* the view the popover points at. No
///   extra plumbing is needed to find the anchor, and none should be added.
/// - **There is no parent-popover chain.** Sheets track `parentSheet` because a
///   sheet presented from a sheet must be attached to it. A popover presented
///   from a popover is attached to a widget like any other, and the platform's
///   popup layer handles the stacking.
/// - **It does not use `@CastBackend`.** That macro expands to `fatalError` when
///   the backend does not conform, which takes the process down for one
///   modifier. `SheetModifier` predates the rule against that; this does not.
///
/// 驅動 ``View/popover(isPresented:attachmentEdge:onDismiss:content:)`` 的 view。
///
/// 刻意緊貼 `SheetModifier` 建模：呈現的生命週期——建立一次、每次計算時更新、呈現一次、於下降邊
/// 關閉——是同一套，而兩個對此看法不一致的 presentation modifier，在巢狀使用時就會分歧。
///
/// 它與 `SheetModifier` 有三處不同，且三者都是被迫的：
///
/// - **它錨定在自己的 widget 上。** `asWidget` 回傳子節點的 widget，因此交給 `commit` 的 `widget`
///   **就是** popover 所指向的那個 view。不需要額外的接線去尋找錨點，也不應該加上。
/// - **沒有 parent-popover 鏈。** sheet 之所以追蹤 `parentSheet`，是因為由 sheet 呈現出的 sheet
///   必須附著於它。而由 popover 呈現出的 popover，與其他任何 popover 一樣附著於某個 widget，堆疊
///   由平台的 popup 圖層處理。
/// - **它不使用 `@CastBackend`。** 該 macro 在 backend 未 conform 時會展開為 `fatalError`，為了
///   一個 modifier 而拖垮整個行程。`SheetModifier` 早於禁止此事的規則；本檔案則不然。
struct PopoverModifier<Content: View, PopoverContent: View>: TypeSafeView {
    typealias Children = PopoverModifierViewChildren<Content, PopoverContent>

    var isPresented: Binding<Bool>
    var attachmentEdge: Edge
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

    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        _ = children.childNode.commit()

        // Degrade rather than abort, and only ever out here. See the type's
        // documentation: this branch is unreachable on the five shipped
        // backends, and reaching it is itself the thing worth reporting.
        // 在此處降級而非中止，且僅限於此。見本型別的文件：這個分支在五個已發布的 backend 上是
        // 走不到的，而「走到了」本身就是值得回報的事。
        guard
            let popoverBackend = backend as? any BaseAppBackend & BackendFeatures.Popovers
        else {
            if isPresented.wrappedValue {
                logger.warnOnce(
                    """
                    '\(String(describing: Backend.self))' does not implement \
                    'BackendFeatures.Popovers'; '.popover' is showing nothing. \
                    The anchor view is unaffected.
                    """
                )
            }
            return
        }

        func present<NewBackend: BaseAppBackend & BackendFeatures.Popovers>(
            _ backend: NewBackend
        ) {
            guard isPresented.wrappedValue else {
                guard let existingPopover = children.popover else { return }
                backend.dismissPopover(existingPopover as! NewBackend.Popover)
                children.popover = nil
                children.popoverContentNode = nil
                return
            }

            let needsPresenting = children.popover == nil

            let popover: NewBackend.Popover
            if children.popoverContentNode == nil {
                let contentNode = AnyViewGraphNode(
                    ViewGraphNode(
                        for: popoverContent(),
                        backend: backend,
                        environment: environment
                    )
                )
                children.popoverContentNode = contentNode
                popover = backend.createPopover(content: contentNode.widget.into())
            } else {
                guard
                    let existingPopover = children.popover,
                    let castedPopover = existingPopover as? NewBackend.Popover
                else {
                    logger.warning(
                        """
                        PopoverModifier has a nil popover, even though the \
                        popover has already been presented
                        """
                    )
                    return
                }
                popover = castedPopover
            }

            // `dismiss` in the popover's own content must close the popover, not
            // whatever sheet or window encloses the anchor. Without this an
            // `@Environment(\.dismiss)` button inside a popover reaches straight
            // past it, which is a far more confusing outcome than doing nothing.
            // popover 自身內容中的 `dismiss` 必須關閉該 popover，而不是關閉包住錨點的那個 sheet
            // 或視窗。少了這一段，popover 內部的 `@Environment(\.dismiss)` 按鈕會越過它直接生效，
            // 那個結果遠比「什麼都沒發生」更令人困惑。
            let popoverEnvironment = environment.with(
                \.dismiss,
                DismissAction(action: { [isPresented] in
                    isPresented.wrappedValue = false
                })
            )

            _ = children.popoverContentNode!.computeLayout(
                with: popoverContent(),
                proposedSize: .unspecified,
                environment: popoverEnvironment
            )
            let result = children.popoverContentNode!.commit()

            backend.updatePopover(
                popover,
                // The outer environment, not the content's, for the same reason
                // `SheetModifier` uses it: this describes the popover, not what
                // is inside it.
                // 使用外層環境而非內容的環境，理由與 `SheetModifier` 相同：這描述的是 popover
                // 本身，不是它裡面的東西。
                environment: environment,
                size: result.size.vector,
                attachmentEdge: attachmentEdge,
                backgroundColor: result.preferences.presentationBackground?
                    .resolve(in: environment),
                onDismiss: { handleDismiss(children: children) }
            )

            if needsPresenting {
                guard let window = environment.window else {
                    logger.warning("'.popover' was presented outside of a window")
                    return
                }
                backend.showPopover(
                    popover,
                    relativeTo: widget as! NewBackend.Widget,
                    window: window as! NewBackend.Window
                )
            }

            children.popover = popover
        }

        present(popoverBackend)
    }

    func handleDismiss(children: Children) {
        onDismiss?()
        children.popover = nil
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
