extension Scene {
    /// Modifies the scene's environment.
    ///
    /// - Parameters:
    ///   - keyPath: The key path to the environment value to update.
    ///   - newValue: The new value.
    public func environment<T>(
        _ keyPath: WritableKeyPath<EnvironmentValues, T>,
        _ newValue: T
    ) -> some Scene {
        SceneEnvironmentModifier(self) { environment in
            environment.with(keyPath, newValue)
        }
    }

    /// Modifies the scene's environment.
    ///
    /// - Parameters:
    ///   - keyPath: The key path to the environment value to update.
    ///   - transform: A closure that transforms the environment at `keyPath`.
    public func transformEnvironment<T>(
        _ keyPath: WritableKeyPath<EnvironmentValues, T>,
        transform: @escaping (inout T) -> Void
    ) -> some Scene {
        SceneEnvironmentModifier(self) { environment in
            var value = environment[keyPath: keyPath]
            transform(&value)
            return environment.with(keyPath, value)
        }
    }

    /// Places an observable object in the environment of this scene, where any
    /// view in it can read the object with ``EnvironmentObject``.
    ///
    /// This exists as well as the ``View`` modifier of the same name because it
    /// is the placement almost every application actually wants: the object
    /// belongs to the app, and hanging it off `WindowGroup { … }` puts it above
    /// the root view rather than inside it.
    ///
    /// ```swift
    /// var body: some Scene {
    ///     WindowGroup {
    ///         ContentView()
    ///     }
    ///     .environmentObject(session)
    /// }
    /// ```
    ///
    /// - Important: This modifier stores the object; it does not observe it.
    ///   Ownership has to sit somewhere that outlives the scene and publishes
    ///   its changes -- an `@State` or ``StateObject`` property on the `App` --
    ///   otherwise the object is rebuilt whenever the app's `body` runs and the
    ///   state it holds resets with it.
    ///
    /// - Parameter object: The object to place in the scene's environment.
    ///
    /// 把一個 observable 物件放進此 scene 的 environment 中，其中任何 view 都可以用
    /// ``EnvironmentObject`` 讀取它。
    ///
    /// 除了同名的 ``View`` modifier 之外還提供這一個，是因為它才是幾乎每個應用程式真正想要的放置點：
    /// 該物件屬於整個 app，而把它掛在 `WindowGroup { … }` 上，是把它放在根 view 之上，而非之內。
    ///
    /// - Important: 這個 modifier 只負責存放該物件，並不觀察它。所有權必須放在某個比 scene 活得久
    ///   且會發佈其變更的地方——`App` 上的 `@State` 或 ``StateObject`` 屬性——否則該物件會在 app 的
    ///   `body` 每次執行時被重建，它所持有的狀態也會隨之重設。
    public func environmentObject<T: ObservableObject>(_ object: T) -> some Scene {
        SceneEnvironmentModifier(self) { environment in
            var environment = environment
            environment[observable: T.self] = object
            return environment
        }
    }
}

struct SceneEnvironmentModifier<Content: Scene>: Scene {
    typealias Node = SceneEnvironmentModifierNode<Content>

    var content: Content
    var modification: (EnvironmentValues) -> EnvironmentValues

    init(
        _ content: Content,
        modification: @escaping (EnvironmentValues) -> EnvironmentValues
    ) {
        self.content = content
        self.modification = modification
    }
}

final class SceneEnvironmentModifierNode<Content: Scene>: SceneGraphNode {
    typealias NodeScene = SceneEnvironmentModifier<Content>

    var modification: (EnvironmentValues) -> EnvironmentValues
    var contentNode: Content.Node

    init<Backend: BaseAppBackend>(
        from scene: NodeScene,
        backend: Backend,
        environment: EnvironmentValues
    ) {
        self.modification = scene.modification
        self.contentNode = Content.Node(
            from: scene.content,
            backend: backend,
            environment: modification(environment)
        )
    }

    func updateNode(
        _ newScene: NodeScene?,
        environment: EnvironmentValues
    ) -> SceneNodeUpdateResult {
        if let newScene {
            self.modification = newScene.modification
        }

        return contentNode.updateNode(
            newScene?.content,
            environment: modification(environment)
        )
    }

    func update<Backend: BaseAppBackend>(
        backend: Backend,
        environment: EnvironmentValues
    ) {
        contentNode.update(
            backend: backend,
            environment: modification(environment)
        )
    }
}
