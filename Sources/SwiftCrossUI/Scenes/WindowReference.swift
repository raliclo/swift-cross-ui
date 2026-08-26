/// Holds the view graph and window handle for a single window.
@MainActor
final class WindowReference<SceneType: WindowingScene> {
    /// The scene.
    private var scene: SceneType
    /// The view graph of the window's root view.
    private let viewGraph: ViewGraph<SceneType.Content>
    /// The window being rendered in.
    let window: Any
    /// `false` after the first scene update.
    private var isFirstUpdate = true
    /// The cached window size. Nil on first run or after a window is resized.
    private var cachedWindowSize: SIMD2<Int>?
    /// The environment most recently provided by this node's parent scene.
    private var parentEnvironment: EnvironmentValues
    /// The container used to center the root view in the window.
    private let containerWidget: AnyWidget
    /// The window's preferred color scheme, cached from the last update.
    private var preferredColorScheme: ColorScheme?
    /// The window levels already reported as unsupported for this window.
    ///
    /// The level is re-applied on every update, so without this the warning
    /// would be emitted on every layout pass and bury whatever the app itself
    /// logs. Keyed by level rather than a plain flag so a scene that later asks
    /// for a *different* unsupported level still says so.
    ///
    /// 已針對此視窗回報過「不支援」的 window level。
    ///
    /// 由於每次更新都會重新套用 level，若無此集合，該警告會在每一次版面配置時發出，把 app 自己的
    /// 日誌淹沒。以 level 為鍵而非單一旗標，是為了讓「之後改為要求另一個同樣不支援的 level」的場景
    /// 仍然會出聲。
    private var reportedUnsupportedWindowLevels: Set<WindowLevel> = []

    /// - Parameters:
    ///   - closeHandler: The action to perform when the window is closed. Should
    ///     dispose of the scene's reference to this `WindowReference`.
    ///   - id: A unique id to use when restoring the window's frame from disk (if present).
    init<Backend: BaseAppBackend>(
        scene: SceneType,
        backend: Backend,
        environment: EnvironmentValues,
        onClose closeHandler: @escaping @Sendable @MainActor () -> Void,
        id: String
    ) {
        self.scene = scene
        let window = backend.createWindow(
            withDefaultSize: environment.defaultWindowSize,
            id: id
        )

        viewGraph = ViewGraph(
            for: scene.content(),
            backend: backend,
            environment: environment.with(\.window, window)
        )
        let rootWidget = viewGraph.rootNode.concreteNode(for: Backend.self).widget

        let container = backend.createContainer()
        backend.insert(rootWidget, into: container, at: 0)
        self.containerWidget = AnyWidget(container)

        backend.setChild(ofWindow: window, to: container)
        backend.setTitle(ofWindow: window, to: scene.title)

        self.window = window
        parentEnvironment = environment

        if let backend = backend as? any BackendFeatures.WindowClosing {
            func setCloseHandler<NewBackend: BackendFeatures.WindowClosing>(backend: NewBackend) {
                backend.setCloseHandler(ofWindow: window as! NewBackend.Window, to: closeHandler)
            }
            setCloseHandler(backend: backend)
        }

        backend.setResizeHandler(ofWindow: window) { [weak self] newSize in
            guard let self else { return }
            self.update(
                self.scene,
                proposedWindowSize: newSize,
                needsWindowSizeCommit: false,
                backend: backend,
                environment: self.parentEnvironment,
                windowSizeIsFinal: !backend.isWindowProgrammaticallyResizable(window)
            )
        }

        backend.setWindowEnvironmentChangeHandler(of: window) { [weak self] in
            guard let self else { return }
            self.update(
                self.scene,
                proposedWindowSize: backend.size(ofWindow: window),
                needsWindowSizeCommit: false,
                backend: backend,
                environment: self.parentEnvironment,
                windowSizeIsFinal: !backend.isWindowProgrammaticallyResizable(window)
            )
        }
    }

    /// Says once that a window level could not be honoured, and why it matters.
    ///
    /// A warning rather than a crash. A window level is a hint with a working
    /// fallback -- the window still opens, and everything in it still works --
    /// unlike a missing widget, which leaves nothing to show. But not silence
    /// either: a `.floating` window that is not floating looks like the app
    /// ignoring its own code, and the platform reason is not guessable from the
    /// outside.
    ///
    /// 針對「某個 window level 無法被實現」發出一次說明，並指出其重要性。
    ///
    /// 採警告而非崩潰。window level 是一個帶有可用退路的提示——視窗照樣開啟，其中的一切照樣運作
    /// ——這與「缺少某個 widget」不同，後者根本無物可顯示。但也不採靜默：一個並未浮動的 `.floating`
    /// 視窗，看起來就像 app 忽略了自己的程式碼，而平台層面的原因從外部是猜不出來的。
    private func warnAboutWindowLevelOnce(_ level: WindowLevel, backend: Any.Type) {
        guard reportedUnsupportedWindowLevels.insert(level).inserted else { return }
        logger.warning(
            """
            window level \(String(describing: level)) is not supported by \
            \(String(describing: backend)) on this platform; using .normal
            """
        )
    }

    func update<Backend: BaseAppBackend>(
        _ newScene: SceneType?,
        backend: Backend,
        environment: EnvironmentValues
    ) {
        guard let window = window as? Backend.Window else {
            fatalError("Scene updated with a backend incompatible with the window it was given")
        }

        let isProgramaticallyResizable =
            backend.isWindowProgrammaticallyResizable(window)

        let proposedWindowSize: SIMD2<Int>
        let usedDefaultSize: Bool
        if isFirstUpdate && isProgramaticallyResizable && !backend.restoresWindowFrames {
            proposedWindowSize = environment.defaultWindowSize
            usedDefaultSize = true
        } else {
            proposedWindowSize = cachedWindowSize ?? backend.size(ofWindow: window)
            usedDefaultSize = false
        }

        update(
            newScene,
            proposedWindowSize: proposedWindowSize,
            needsWindowSizeCommit: usedDefaultSize,
            backend: backend,
            environment: environment,
            windowSizeIsFinal: !isProgramaticallyResizable
        )
    }

    /// Updates the `WindowReference`.
    /// - Parameters:
    ///   - newScene: The scene. `nil` if reusing previous scene value.
    ///   - proposedWindowSize: The proposed window size.
    ///   - needsWindowSizeCommit: Whether the proposed window size matches the
    ///     windows current size (or imminent size in the case of a window
    ///     resize). We use this parameter instead of comparing to the window's
    ///     current size to the proposed size, because some backends (such as
    ///     AppKitBackend) trigger window resize handlers *before* the underlying
    ///     window gets assigned its new size (allowing us to pre-emptively update the
    ///     window's content to match the new size).
    ///   - backend: The backend to use.
    ///   - environment: The current environment.
    ///   - windowSizeIsFinal: If true, no further resizes can/will be made. This
    ///     is true on platforms that don't support programmatic window resizing,
    ///     and when a window is full screen.
    private func update<Backend: BaseAppBackend>(
        _ newScene: SceneType?,
        proposedWindowSize: SIMD2<Int>,
        needsWindowSizeCommit: Bool,
        backend: Backend,
        environment: EnvironmentValues,
        windowSizeIsFinal: Bool = false
    ) {
        guard let window = window as? Backend.Window else {
            fatalError("Scene updated with a backend incompatible with the window it was given")
        }

        parentEnvironment = environment

        if let newScene {
            // Don't set default size even if it has changed. We only set that once
            // at window creation since some backends don't have a concept of
            // 'default' size which would mean that setting the default size every time
            // the default size changed would resize the window (which is incorrect
            // behaviour).
            backend.setTitle(ofWindow: window, to: newScene.title)
            scene = newScene
        }

        var environment =
            backend.computeWindowEnvironment(
                window: window,
                rootEnvironment: environment.with(\.window, window)
            )
            .with(\.onResize) { [weak self] _ in
                guard let self else { return }
                self.cachedWindowSize = nil
                // TODO: Figure out whether this would still work if we didn't recompute the
                //   scene's body. I have a vague feeling that it wouldn't work in all cases?
                //   But I don't have the time to come up with a counterexample right now.
                self.update(
                    self.scene,
                    proposedWindowSize: backend.size(ofWindow: window),
                    needsWindowSizeCommit: false,
                    backend: backend,
                    environment: environment
                )
            }
        let outerColorScheme = environment.colorScheme

        // Update environment with latest cached value before first update to
        // minimise toggling between outer color scheme and preferred color
        // scheme where possible (could confuse people when logging the color
        // scheme or debugging things)
        if let preferredColorScheme {
            environment.colorScheme = preferredColorScheme
        }

        let probingResult = viewGraph.computeLayout(
            with: newScene?.content(),
            proposedSize: .zero,
            environment: environment
                .with(\.allowLayoutCaching, true)
        )
        let minimumWindowSize = probingResult.size
        updateEnvironment(
            &environment,
            viewLayoutResult: probingResult,
            outerColorScheme: outerColorScheme,
            backend: backend
        )

        // With `.contentSize`, the window's maximum size is the maximum size of its
        // content. With `.contentMinSize` (and `.automatic`), there is no maximum
        // size.
        let maximumWindowSize: ViewSize?
        switch environment.windowResizability {
            case .contentSize:
                let result = viewGraph.computeLayout(
                    with: newScene?.content(),
                    proposedSize: .infinity,
                    environment: environment.with(\.allowLayoutCaching, true)
                )
                updateEnvironment(
                    &environment,
                    viewLayoutResult: result,
                    outerColorScheme: outerColorScheme,
                    backend: backend
                )
                maximumWindowSize = result.size
            case .automatic, .contentMinSize:
                maximumWindowSize = nil
        }

        let clampedWindowSize = ViewSize(
            min(
                maximumWindowSize?.width ?? .infinity,
                max(minimumWindowSize.width, Double(proposedWindowSize.x))
            ),
            min(
                maximumWindowSize?.height ?? .infinity,
                max(minimumWindowSize.height, Double(proposedWindowSize.y))
            )
        )

        if clampedWindowSize.vector != proposedWindowSize && !windowSizeIsFinal {
            // Restart the window update if the content has caused the window to
            // change size.
            return update(
                scene,
                proposedWindowSize: clampedWindowSize.vector,
                needsWindowSizeCommit: true,
                backend: backend,
                environment: environment,
                windowSizeIsFinal: true
            )
        }

        // Set these even if the window isn't programmatically resizable
        // because the window may still be user resizable.
        backend.setSizeLimits(
            ofWindow: window,
            minimum: minimumWindowSize.vector,
            maximum: maximumWindowSize?.vector
        )

        let finalContentResult = viewGraph.computeLayout(
            proposedSize: ProposedViewSize(proposedWindowSize),
            environment: environment
        )
        updateEnvironment(
            &environment,
            viewLayoutResult: finalContentResult,
            outerColorScheme: outerColorScheme,
            backend: backend
        )

        backend.setPosition(
            ofChildAt: 0,
            in: containerWidget.into(),
            to: (proposedWindowSize &- finalContentResult.size.vector) / 2
        )

        if needsWindowSizeCommit {
            backend.setSize(ofWindow: window, to: proposedWindowSize)
        }
        cachedWindowSize = proposedWindowSize

        if let backend = backend as? any BackendFeatures.WindowBehaviors {
            func setBehaviors<NewBackend: BackendFeatures.WindowBehaviors>(backend: NewBackend) {
                backend.setBehaviors(
                    ofWindow: window as! NewBackend.Window,
                    closable: finalContentResult.preferences.windowDismissBehavior?
                        .isEnabled ?? true,
                    minimizable: finalContentResult.preferences.preferredWindowMinimizeBehavior?
                        .isEnabled ?? true,
                    resizable: finalContentResult.preferences.windowResizeBehavior?
                        .isEnabled ?? true
                )
            }
            setBehaviors(backend: backend)
        }

        // Applied on every update, not once. A backend re-places a window as
        // part of resizing it, which on Windows drops the topmost flag -- the
        // same reason testapp/P6.swift re-asserts its own.
        // 每次更新都套用，而非只做一次。backend 在調整視窗尺寸時會重新擺放視窗，在 Windows 上這會
        // 清掉置頂旗標——與 testapp/P6.swift 必須反覆重新宣告其置頂狀態的理由相同。
        if let levelBackend = backend as? any BackendFeatures.WindowLevels {
            func setLevel<NewBackend: BackendFeatures.WindowLevels>(backend: NewBackend) {
                var level = environment.windowLevel
                if !backend.supportedWindowLevels.contains(level) {
                    warnAboutWindowLevelOnce(level, backend: NewBackend.self)
                    level = .normal
                }
                backend.setLevel(ofWindow: window as! NewBackend.Window, to: level)
            }
            setLevel(backend: levelBackend)
        } else if environment.windowLevel != .automatic {
            warnAboutWindowLevelOnce(environment.windowLevel, backend: Backend.self)
        }

        // Generally just used to update the window color scheme
        backend.updateWindow(window, environment: environment)

        // Delay committing the view graph so that the View.inspectWindow(_:)
        // modifiers can be used to overwrite certain SwiftCrossUI behaviors
        viewGraph.commit()

        if isFirstUpdate {
            backend.show(window: window)
            isFirstUpdate = false
        }
    }

    func activate<Backend: BaseAppBackend>(backend: Backend) {
        guard let window = window as? Backend.Window else {
            fatalError("Scene updated with a backend incompatible with the window it was given")
        }

        backend.activate(window: window)
    }

    private func updateEnvironment<Backend: BaseAppBackend>(
        _ environment: inout EnvironmentValues,
        viewLayoutResult: ViewLayoutResult,
        outerColorScheme: ColorScheme,
        backend: Backend
    ) {
        preferredColorScheme = viewLayoutResult.preferences.preferredColorScheme

        // Update environment with preferred color scheme if provided
        if let preferredColorScheme, backend.canOverrideWindowColorScheme {
            environment.colorScheme = preferredColorScheme
        } else {
            // If the preferred color scheme just changed to nil, then we must
            // reset the environment's color scheme to the outer color scheme
            // provided by a higher scene or the system.
            environment.colorScheme = outerColorScheme
        }
    }
}
