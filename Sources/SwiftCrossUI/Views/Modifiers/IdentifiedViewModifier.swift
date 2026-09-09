extension View {
    /// Tags this view so that ``ScrollViewProxy/scrollTo(_:anchor:)`` can reach
    /// it.
    ///
    /// **Narrower than SwiftUI's `.id(_:)`, and deliberately so.** SwiftUI's
    /// also controls view identity: changing the id destroys the view and
    /// rebuilds it, discarding its `@State`. This one does not -- it records
    /// where a widget is and nothing else. Doing both would mean reaching into
    /// the view graph's identity, and a modifier that quietly reset state would
    /// be a much worse thing to get wrong than one that only addresses.
    ///
    /// Said here because the name is SwiftUI's and a reader will assume the
    /// SwiftUI meaning. The scroll half is the half this repository needed.
    ///
    /// 為這個 view 加上標記,好讓 ``ScrollViewProxy/scrollTo(_:anchor:)`` 能夠抵達它。
    ///
    /// **比 SwiftUI 的 `.id(_:)` 窄,而且是刻意的。** SwiftUI 的那一個同時掌管 view 的身分:改變 id
    /// 會摧毀該 view 並重建它,連同丟棄它的 `@State`。這一個不會——它只記錄某個 widget 在哪裡,
    /// 別的都不做。要兩者兼具,就必須伸手進 view graph 的身分機制,而一個「會靜默重置狀態」的 modifier
    /// 若出了錯,後果遠比一個「只負責定址」的糟糕得多。
    ///
    /// 在此說明,是因為這個名字取自 SwiftUI,而讀者會假設 SwiftUI 的語意。捲動的那一半,正是本倉庫
    /// 所需要的那一半。
    public func id(_ id: some Hashable) -> some View {
        IdentifiedViewModifier(body: TupleView1(self), id: AnyHashable(id))
    }
}

struct IdentifiedViewModifier<Content: View>: TypeSafeView {
    typealias Children = TupleView1<Content>.Children

    var body: TupleView1<Content>
    var id: AnyHashable

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
        // Passes the child through rather than wrapping it. There is nothing to
        // draw and nothing to intercept -- an extra container would be one more
        // widget in every list this is used on, and lists are where it is used.
        // 直接把子元件傳遞出去,而不是包住它。這裡沒有東西要畫、也沒有東西要攔截——多一層容器,就是在
        // 每一個用到它的清單裡多一個 widget,而清單正是它被使用的地方。
        children.child0.widget.into()
    }

    func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: Children,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        // Registered during layout rather than in `update`, because this is the
        // pass that runs for every view on every frame; `update` on a passthrough
        // modifier is not guaranteed to.
        // 在 layout 期間登記而不是在 `update` 中,因為這是「每一幀對每一個 view 都會跑」的那個階段;
        // 而一個直通型 modifier 的 `update` 並不保證會執行。
        environment.scrollAnchors?.register(children.child0.widget, for: id)
        return children.child0.computeLayout(
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
        _ = children.child0.commit()
    }
}
