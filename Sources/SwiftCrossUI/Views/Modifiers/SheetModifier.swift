extension View {
    /// Presents a conditional modal overlay. `onDismiss` gets invoked when the
    /// sheet is dismissed.
    ///
    /// On most platforms sheets appear as form-style modals. On tvOS, sheets
    /// appear as full screen overlays (non-opaque).
    ///
    /// `onDismiss` runs when the presentation ends, however it ended -- the user
    /// closing the sheet, and `isPresented` being set to `false`. That is
    /// SwiftUI's rule, and until 2026-09-08 this modifier only had the first
    /// half of it. The doc comment here said so in as many words: *"`onDismiss`
    /// isn't called when the sheet gets dismissed programmatically"*. It was an
    /// accurate description of a defect, which is not the same as a design.
    /// `.popover` had the identical shape and was fixed first, in `6ec976b2`.
    ///
    /// The callback is the backends' to run, not this modifier's. `commit`
    /// hands `handleDismiss` to `updateSheet(onDismiss:)`, and each backend
    /// runs it from the one place where a sheet is actually torn down, so both
    /// paths reach it and neither reaches it twice. Doing it here instead --
    /// calling `onDismiss` from the `else` branch below -- would have fired
    /// twice on every backend that already notifies on `dismissSheet`, which
    /// AppKit, Gtk and WinUI all do for the CHILDREN of a dismissed sheet.
    ///
    /// On the user's path `onDismiss` gets called *after* the sheet has been
    /// dismissed by the underlying UI framework, and *before* `isPresented`
    /// gets set to false. On the programmatic path `isPresented` is already
    /// false before the sheet closes, by definition, so only the first half of
    /// that ordering is meaningful there.
    ///
    /// 無論 presentation 以何種方式結束，`onDismiss` 都會執行——使用者關閉 sheet，以及 `isPresented`
    /// 被設為 `false`。那是 SwiftUI 的規則，而在 2026-09-08 之前，本 modifier 只做到了其中的前半。
    /// 此處的文件註解也把話說得很白：*「以程式方式關閉 sheet 時不會呼叫 `onDismiss`」*。那是對一項
    /// 缺陷的如實描述，而如實描述一項缺陷與一項設計並不是同一回事。`.popover` 有著完全相同的形狀，
    /// 並已於 `6ec976b2` 先行修正。
    ///
    /// 這個回呼歸各 backend 執行，而非歸本 modifier。`commit` 把 `handleDismiss` 交給
    /// `updateSheet(onDismiss:)`，而每個 backend 都只在「sheet 真正被拆除」的那唯一一處執行它，
    /// 因此兩條路都抵達得了它，而且都不會抵達兩次。改在此處執行——也就是從下方的 `else` 分支呼叫
    /// `onDismiss`——會在每一個「已經會在 `dismissSheet` 時發出通知」的 backend 上觸發兩次，而
    /// AppKit、Gtk 與 WinUI 三者對於「被關閉之 sheet 的子 sheet」本來就都會發出通知。
    ///
    /// 在使用者的那條路上，`onDismiss` 會在底層 UI 框架關閉 sheet **之後**、且在 `isPresented`
    /// 被設為 false **之前**被呼叫。在程式化的那條路上，依定義 `isPresented` 在 sheet 關閉前就
    /// 已經是 false，因此該順序只有前半段有意義。
    ///
    /// - Parameters:
    ///   - isPresented: A binding controlling whether the sheet is presented.
    ///   - onDismiss: An action to perform when the sheet is dismissed, whether
    ///     by the user or by setting `isPresented` to `false`.
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
            // The backend runs `onDismiss` from inside this call, and that does
            // not loop back into this branch. Three things hold it shut, and
            // they are the same three `PopoverModifier` relies on:
            //
            // - This branch is only entered when `isPresented` is ALREADY
            //   false, so the `isPresented.wrappedValue = false` that
            //   `handleDismiss` performs cannot flip anything.
            // - `children.sheet` is nilled immediately below, and
            //   `handleDismiss` nils it too -- before it touches `isPresented`.
            //   A second pass finds `children.sheet == nil` and takes neither
            //   branch.
            // - State updates are asynchronous, so `handleDismiss` cannot
            //   re-enter `commit` part-way through this branch:
            //   `Publisher.observeAsUIUpdater` (`Publisher.swift:97`) queues the
            //   update on `serialUpdateHandlingQueue` and then hops through
            //   `backend.runInMainThread`.
            //
            // Worth stating precisely, because the corresponding note in
            // `GtkBackend+Popovers.swift` argues it from "writes `false` over a
            // `false` -- no state change, so no further update", and that part
            // is not true of this codebase: `StateImpl.wrappedValue`'s setter
            // calls `postSet()` unconditionally (`StateImpl.swift:36-41`) and
            // `postSet` ends in a bare `didChange.send()` (`:92`). There is no
            // equality check anywhere on the path -- `Value` is not even
            // constrained to `Equatable` -- so the write DOES publish, and one
            // extra update is scheduled per dismissal. It terminates on the
            // second and third points above, not the first.
            //
            // backend 會在這個呼叫內部執行 `onDismiss`，而那不會繞回本分支。有三件事把門關住，
            // 且與 `PopoverModifier` 所倚賴的是同樣的三件：
            //
            // - 只有在 `isPresented` **已經**為 false 時才會進入本分支，因此 `handleDismiss`
            //   所做的 `isPresented.wrappedValue = false` 翻不動任何東西。
            // - `children.sheet` 在下方隨即被設為 nil，而 `handleDismiss` 也會設它為 nil
            //   ——並且是在它動到 `isPresented` 之前。第二輪會發現 `children.sheet == nil`，
            //   於是兩個分支都不進入。
            // - state 更新是非同步的，因此 `handleDismiss` 無法在本分支執行到一半時重入
            //   `commit`：`Publisher.observeAsUIUpdater`（`Publisher.swift:97`）會把更新排入
            //   `serialUpdateHandlingQueue`，再經由 `backend.runInMainThread` 轉手。
            //
            // 值得把話說精確，因為 `GtkBackend+Popovers.swift` 中對應的註記是以「在一個 `false`
            // 上寫入 `false`——沒有狀態改變，也就不會再引發下一輪 update」來論證的，而那一段在本
            // 專案裡並不成立：`StateImpl.wrappedValue` 的 setter 無條件呼叫 `postSet()`
            //（`StateImpl.swift:36-41`），而 `postSet` 以一個純粹的 `didChange.send()` 收尾
            //（`:92`）。整條路徑上沒有任何相等性檢查——`Value` 甚至沒有被約束為 `Equatable`
            // ——所以該次寫入**確實**會發佈，每次關閉都會多排一輪更新。真正讓它停下來的是上述第二點
            // 與第三點，而不是第一點。
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
