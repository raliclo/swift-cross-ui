struct EnvironmentModifier<Child: View>: View {
    var body: TupleView1<Child>
    var modification: (EnvironmentValues) -> EnvironmentValues

    init(_ child: Child, modification: @escaping (EnvironmentValues) -> EnvironmentValues) {
        self.body = TupleView1(child)
        self.modification = modification
    }

    func children<Backend: BaseAppBackend>(
        backend: Backend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues
    ) -> any ViewGraphNodeChildren {
        body.children(
            backend: backend,
            snapshots: snapshots,
            environment: modification(environment)
        )
    }

    func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children: any ViewGraphNodeChildren,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend
    ) -> ViewLayoutResult {
        body.computeLayout(
            widget,
            children: children,
            proposedSize: proposedSize,
            environment: modification(environment),
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
            environment: modification(environment),
            backend: backend
        )
    }

    public var _asMenuItems: [MenuItem] {
        self.body._asMenuItems.map { menuItem in
            .modifiedEnvironment({ menuItem }, { self.modification })
        }
    }
}

extension View {
    /// Modifies the environment of the View its applied to
    public func environment<T>(_ keyPath: WritableKeyPath<EnvironmentValues, T>, _ newValue: T)
        -> some View
    {
        EnvironmentModifier(self) { environment in
            environment.with(keyPath, newValue)
        }
    }

    /// Adds an observable object to the environment of the enclosed View.
    /// You are responsible for ensuring that the object is being observed
    /// by a parent view, as this modifier does not perform any observation.
    ///
    /// - Note: The caveat above is about *this* modifier, not about the whole
    ///   round trip. A descendant reading the object with ``EnvironmentObject``
    ///   subscribes to it itself, so no parent observer is needed in that case.
    ///   The caveat still applies to ``Environment``, which reads the same slot
    ///   without observing anything.
    ///
    ///   上述提醒是針對**這個** modifier，而非整趟往返。以 ``EnvironmentObject`` 讀取該物件的
    ///   後代會自行訂閱它，因此那種情形不需要任何父層觀察者。該提醒對 ``Environment`` 仍然適用，
    ///   因為它讀的是同一個位置，卻不觀察任何東西。
    public func environment<T: ObservableObject>(_ object: T) -> some View {
        EnvironmentModifier(self) { environment in
            var environment = environment
            environment[observable: T.self] = object
            return environment
        }
    }

    /// Places an observable object in the environment of this view's subtree,
    /// where any descendant can read it with ``EnvironmentObject``.
    ///
    /// The object is stored and found **by its type**, so exactly one object of
    /// each type is visible at a point in the tree and a nested call replaces
    /// the outer one for its own subtree only.
    ///
    /// Spelled separately from `.environment(_ object:)` even though the two
    /// do the same thing, because the pairing is what makes the feature
    /// findable: `.environmentObject(_:)` is the name a reader of
    /// `@EnvironmentObject` will search for, and the failure it prevents --
    /// nobody supplied the object -- is a trap at the far end of the tree with
    /// nothing at the near end to point at.
    ///
    /// - Parameter object: The object to place in the environment.
    ///
    /// 把一個 observable 物件放進此 view 子樹的 environment 中，其下任何後代都可以用
    /// ``EnvironmentObject`` 讀取它。
    ///
    /// 該物件是**依型別**存放與查找的，因此在樹上的任一點，每個型別只有一個物件可見；巢狀的呼叫
    /// 只會在它自己的子樹中取代外層的那一個。
    ///
    /// 儘管它與 `.environment(_ object:)` 做的是同一件事，仍另行命名，因為「成對」正是這項功能
    /// 能被找到的關鍵：`.environmentObject(_:)` 是讀到 `@EnvironmentObject` 的人會去搜尋的名字，
    /// 而它所防止的失敗——沒有人提供該物件——是發生在樹另一端的中止，近端沒有任何東西可供指認。
    public func environmentObject<T: ObservableObject>(_ object: T) -> some View {
        environment(object)
    }
}
