extension View {
    /// Shows a menu when this view is secondary-clicked.
    ///
    /// ```swift
    /// Mesh3DView(scene)
    ///     .contextMenu {
    ///         Button("Reset the camera") { distance = 3.4 }
    ///         Button("Export .glb") { export() }
    ///     }
    /// ```
    ///
    /// The items are the same ones ``Menu`` takes, and resolve the same way.
    ///
    /// 在這個 view 被次要點擊(右鍵)時顯示一個選單。
    ///
    /// 其項目與 ``Menu`` 所取的相同,解析方式也相同。
    @MainActor
    public func contextMenu(@ViewBuilder items: () -> some View) -> some View {
        ContextMenuModifier(
            body: TupleView1(self),
            menu: Menu.resolve(items: items()._asMenuItems)
        )
    }
}

struct ContextMenuModifier<Content: View>: TypeSafeView {
    typealias Children = TupleView1<Content>.Children

    var body: TupleView1<Content>
    var menu: ResolvedMenu

    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> Children {
        body.children(backend: backend, snapshots: snapshots, environment: environment)
    }

    func asWidget<Backend: BaseAppBackend>(
        _ children: Children,
        backend: Backend
    ) -> Backend.Widget {
        let child: Backend.Widget = children.child0.widget.into()
        guard let backend = backend as? any BaseAppBackend & BackendFeatures.ContextMenus
        else {
            ContextMenuDegradation.reportOnce(backend: "\(Backend.self)")
            return child
        }
        return wrap(backend, child: child) as! Backend.Widget
    }

    private func wrap<Backend: BaseAppBackend & BackendFeatures.ContextMenus>(
        _ backend: Backend,
        child: Any
    ) -> Backend.Widget {
        backend.createContextMenuTarget(wrapping: child as! Backend.Widget)
    }

    func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        children.child0.computeLayout(
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
        let size = children.child0.commit().size
        backend.setSize(of: widget, to: size.vector)
        guard let backend = backend as? any BaseAppBackend & BackendFeatures.ContextMenus
        else { return }
        update(backend, widget: widget, environment: environment)
    }

    private func update<Backend: BaseAppBackend & BackendFeatures.ContextMenus>(
        _ backend: Backend,
        widget: Any,
        environment: EnvironmentValues
    ) {
        backend.updateContextMenuTarget(
            widget as! Backend.Widget,
            menu: menu,
            environment: environment
        )
    }
}

/// One report per backend, because a view commits on every update.
/// 每個 backend 只回報一次,因為一個 view 每次更新都會 commit。
enum ContextMenuDegradation {
    nonisolated(unsafe) private static var reported: Set<String> = []

    static func reportOnce(backend: String) {
        guard !reported.contains(backend) else { return }
        reported.insert(backend)
        logger.warning(
            """
            input warning (the app keeps running and the view is still drawn and laid out): \
            \(backend) does not implement BackendFeatures.ContextMenus, so .contextMenu \
            shows nothing -- a secondary click on the view does whatever it would have \
            done without the modifier. What to change: implement the two methods of that \
            protocol; the menu arrives as a ResolvedMenu, which this backend already \
            converts for PopoverMenus. AppKitBackend sets NSView.menu, UIKit has \
            UIContextMenuInteraction, GTK has GtkPopoverMenu raised from a gesture, \
            WinUI has ContextFlyout, and Android has registerForContextMenu.
            """
        )
    }
}
