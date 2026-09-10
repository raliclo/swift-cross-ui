extension View {
    /// Names this view's coordinate space, so a descendant's
    /// ``GeometryProxy/frame(in:)`` can be measured against it.
    ///
    /// ```swift
    /// ScrollView { … }
    ///     .coordinateSpace(name: "scroll")
    /// ```
    ///
    /// **A container rather than a preference, because the name flows the other
    /// way.** A cell reporting its span travels UP; a named space is declared by
    /// an ancestor and read by a descendant, so it travels DOWN, and the
    /// environment is what goes that direction. The container exists because
    /// this view needs a widget of its own to ask the backend where it is.
    ///
    /// 為這個 view 的座標系命名，好讓某個後代的 ``GeometryProxy/frame(in:)`` 能以它為基準量測。
    ///
    /// **它是一個容器而非一個 preference，因為名稱流動的方向相反。** 一個回報跨欄數的儲存格是往
    /// **上**走;而一個具名的座標系是由祖先宣告、由後代讀取，因此它往**下**走——而往那個方向走的是
    /// environment。之所以需要一個容器，是因為這個 view 需要一個屬於自己的 widget，才能去問 backend
    /// 它在哪裡。
    public func coordinateSpace(name: String) -> some View {
        CoordinateSpaceContainer(name: name, content: self)
    }
}

/// Publishes its own origin under a name, for descendants to measure against.
///
/// **It delegates its layout to `TupleView1` instead of building a container of
/// its own, which is the shape `PreferenceModifier` already uses.** The first
/// version created a widget and positioned the child inside it; the entire
/// subtree then rendered as nothing at all -- no crash, no warning, an empty
/// area where a box had been. A view whose `body` is the child directly does
/// not give `layoutableChildren` the child, it gives the child's children, and
/// everything after that is arranged one level too deep.
///
/// 把自己的原點以一個名稱發布出去，供後代據以量測。
///
/// **它把版面委派給 `TupleView1`，而不是自己蓋一個容器——那正是 `PreferenceModifier` 已在使用的形狀。**
/// 第一版自己建了一個 widget 並把子節點放進去;結果整棵子樹**什麼都沒算繪出來**——沒有崩潰、沒有警告，
/// 原本是一個盒子的地方變成一片空白。一個 `body` 直接就是子節點的 view，交給 `layoutableChildren` 的
/// 並不是那個子節點，而是那個子節點的**子節點們**，其後的每一件事都深了一層。
struct CoordinateSpaceContainer<Content: View>: View {
    var body: TupleView1<Content>
    var name: String

    init(name: String, content: Content) {
        self.body = TupleView1(content)
        self.name = name
    }

    func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: any ViewGraphNodeChildren,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        var spaces = environment.namedCoordinateSpaces
        if let origin = Self.origin(of: widget, backend: backend) {
            spaces[name] = origin
        }
        // Not requested again when the origin first appears, because whoever
        // reads it is a `GeometryReader`, and that already asks for another pass
        // when ITS origin changes -- which is the same moment. A second request
        // for the same pass would be two asks for one answer.
        // 當原點首次出現時不再另外要求一輪，因為讀它的人是 `GeometryReader`，而它在**自己的**原點
        // 改變時就已經要求了再一輪——那是同一個時刻。為同一輪再要求一次，等於為同一個答案問兩次。
        return body.computeLayout(
            widget,
            children: children,
            proposedSize: proposedSize,
            environment: environment.with(\.namedCoordinateSpaces, spaces),
            backend: backend
        )
    }

    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: any ViewGraphNodeChildren,
        layout: ViewLayoutResult,
        environment: EnvironmentValues,
        backend: Backend
    ) {
        body.commit(
            widget,
            children: children,
            layout: layout,
            environment: environment,
            backend: backend
        )
    }

    @MainActor
    static func origin<Backend: BaseAppBackend>(
        of widget: Backend.Widget,
        backend: Backend
    ) -> SIMD2<Int>? {
        guard let geometryBackend = backend as? any BackendFeatures.WidgetGeometry
        else { return nil }
        @MainActor
        func ask<B: BackendFeatures.WidgetGeometry>(_ backend: B) -> SIMD2<Int>? {
            backend.originInWindow(ofWidget: widget as! B.Widget)
        }
        return ask(geometryBackend)
    }
}
