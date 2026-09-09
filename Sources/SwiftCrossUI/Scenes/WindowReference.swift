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
    /// Keyed by level rather than a plain flag so a scene that later asks for a
    /// *different* unsupported level still says so.
    private var reportedUnsupportedWindowLevels: Set<WindowLevel> = []
    /// The window level last requested by the environment.
    ///
    /// Starts as `nil` rather than `.automatic` so that the first update does
    /// apply, which is what puts a scene declaring `.floating` in front at
    /// launch. After that unchanged non-floating levels are not handed over
    /// again, because `.automatic` and `.normal` can map to a platform-level
    /// "not topmost" call that would undo temporary external pins.
    private var lastRequestedWindowLevel: WindowLevel?
    /// The title last handed to the backend, whatever its source.
    ///
    /// Cached so an unchanged title is not re-applied on every layout pass.
    /// That is not merely an optimisation on GTK: `gtk_window_set_title`
    /// notifies `notify::title` unconditionally, and this method runs on every
    /// resize, so an uncached write turns a drag of the window edge into a
    /// stream of title changes for anything listening.
    ///
    /// Starts `nil` rather than `scene.title` so that the first update always
    /// applies. `init` sets the scene title directly and does not populate
    /// this, so `nil` is honest about what the backend has been told.
    ///
    /// 最近一次交給 backend 的標題，不論其來源為何。
    ///
    /// 之所以快取，是為了避免在每一次版面計算中重複套用未變更的標題。這在 GTK 上不只是最佳化：
    /// `gtk_window_set_title` 會無條件送出 `notify::title`，而本方法在每次縮放時都會執行，因此
    /// 未經快取的寫入會把「拖曳視窗邊緣」變成一連串的標題變更，任何監聽者都會收到。
    ///
    /// 初值為 `nil` 而非 `scene.title`，以確保第一次更新必定套用。`init` 會直接設定 scene 的標題
    /// 而不填入此欄位，因此 `nil` 如實反映了「backend 已被告知的內容」。
    private var lastAppliedWindowTitle: String?

    /// What was last handed to the backend, so an unchanged toolbar is not
    /// rebuilt on every layout pass. `ToolbarItem`'s `==` ignores the action
    /// closure, which has no identity to compare -- see its note.
    /// 上一次交給 backend 的內容,如此未變更的工具列便不會在每次版面計算時被重建。`ToolbarItem`
    /// 的 `==` 會忽略 action closure,因為它沒有可比較的身分——見其說明。
    private var lastAppliedNavigationTitle: String??

    private var lastAppliedToolbar: [ToolbarItem] = []

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
            //
            // The title is deliberately *not* set here. It used to be, and that
            // left two writers for one property: this one, and the
            // `navigationTitle` preference applied after layout. Two writers
            // meant the scene title won on any pass that carried a new scene
            // and lost on every other, so a `.navigationTitle` would appear and
            // then be overwritten by the scene's own title on the next resize.
            // There is now exactly one application point, below, and
            // `scene.title` is its fallback.
            //
            // 此處刻意**不**設定標題。它原本在這裡設定，而那讓同一個屬性有了兩個寫入者：這一處，
            // 以及在版面計算之後套用的 `navigationTitle` preference。兩個寫入者意謂著：在任何帶有
            // 新 scene 的計算中由 scene 標題勝出，在其餘每一次計算中則落敗，因此 `.navigationTitle`
            // 會先出現、再於下一次縮放時被 scene 自己的標題覆蓋。現在只有下方唯一一個套用點，
            // 而 `scene.title` 是它的後備值。
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
                    environment: environment,
                    // The two sibling call sites -- the resize handler and the
                    // environment-change handler -- both pass this, and this one
                    // did not, so it took the default of `false`. That permits
                    // the restart below, which re-proposes `clampedWindowSize`:
                    // the content's size when offered zero width, which for a
                    // page of text is a very tall, very narrow column. On a
                    // backend that can resize, the window becomes that and all
                    // is well. On one that cannot, `setSize(ofWindow:)` does
                    // nothing and the content is then centred against a window
                    // that does not exist.
                    //
                    // Measured on the Android emulator with P12, 2026-09-03.
                    // At rest the update reported proposed (411, 841) against
                    // content (350, 678). After a state change that made the
                    // content wider: proposed (411, 5558), content (409, 678),
                    // while `size(ofWindow:)` still answered 411 x 841 both
                    // times. The content was placed at y = (5558 - 678) / 2 =
                    // 2440 points -- 6405 pixels down a 2400-pixel screen -- and
                    // the window looked blank. Nine presses of a counter did not
                    // do it; the tenth, where the number needs a second digit,
                    // did.
                    //
                    // 它的兩個兄弟呼叫點——resize handler 與環境變更 handler——都會傳這個參數，
                    // 而此處沒有傳，於是取了預設值 `false`。那使下方的重啟得以執行，重新提議
                    // `clampedWindowSize`：也就是「內容在被提議寬度 0 時的尺寸」，對一個文字頁面
                    // 而言那是一根極高極窄的長條。在可調整大小的 backend 上，視窗會真的變成那樣，
                    // 一切正常；在不能調整的 backend 上，`setSize(ofWindow:)` 什麼都不做，而內容
                    // 接著就被對著一個並不存在的視窗置中。
                    //
                    // 2026-09-03 於 Android emulator 上以 P12 實測。靜止時該次更新回報
                    // proposed (411, 841)、content (350, 678)。在一次讓內容變寬的狀態變更之後：
                    // proposed (411, 5558)、content (409, 678)，而 `size(ofWindow:)` 兩次都仍
                    // 回答 411 x 841。內容因而被放在 y = (5558 - 678) / 2 = 2440 點——在一個
                    // 2400 像素高的螢幕上往下 6405 像素——視窗看起來就是空白的。按計數器九次不會
                    // 造成它，第十次（數字需要第二位數時）會。
                    windowSizeIsFinal: !backend.isWindowProgrammaticallyResizable(window)
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

        // The one place a window title is applied. `View/navigationTitle(_:)`
        // sets a preference on the content; the scene's own title is what a
        // window is called when the content asks for nothing.
        //
        // `setTitle(ofWindow:to:)` is a `BackendFeatures/Core` requirement, so
        // this reaches every backend without a conformance check and without a
        // cast -- which is the whole reason the modifier was built on a
        // preference rather than on a backend protocol of its own.
        //
        // 視窗標題唯一的套用之處。`View/navigationTitle(_:)` 會在內容上設定一個 preference；
        // 而 scene 自身的標題，是在內容沒有任何要求時該視窗的名字。
        //
        // `setTitle(ofWindow:to:)` 是 `BackendFeatures/Core` 的要求，因此這行不需要 conformance
        // 檢查、也不需要轉型就能觸及每一個 backend——這正是該 modifier 建構於 preference 而非
        // 建構於自己的 backend protocol 之上的全部理由。
        let title = finalContentResult.preferences.navigationTitle ?? scene.title
        if title != lastAppliedWindowTitle {
            backend.setTitle(ofWindow: window, to: title)
            lastAppliedWindowTitle = title
        }

        // Applied the same way the title is, and beside it for the same reason:
        // both are things the CONTENT asks of the WINDOW, and the window is the
        // only place that knows both. Guarded by a conformance check rather than
        // required of every backend, because a platform without window chrome
        // has nowhere to put one.
        // 套用方式與標題相同,並置於其旁,理由也相同:兩者都是「內容向視窗提出的要求」,而視窗是
        // 唯一同時知道這兩者的地方。此處以 conformance 檢查為條件、而非要求每個 backend 都實作,
        // 因為沒有視窗外框的平台無處安放它。
        if let toolbarBackend = backend as? any BackendFeatures.Toolbars {
            func setToolbar<NewBackend: BackendFeatures.Toolbars>(backend: NewBackend) {
                let items = finalContentResult.preferences.toolbarItems
                // The CONTENT's title, not `title` above. That one is
                // `navigationTitle ?? scene.title` and a backend cannot tell the
                // two apart; this one is nil when the content asked for nothing,
                // which is what lets iOS and Android decide whether a bar
                // appears at all.
                // 這是**內容**的標題,不是上方的 `title`。那一個是 `navigationTitle ?? scene.title`,
                // backend 分辨不出兩者;而這一個在內容什麼都沒要求時為 nil,那正是讓 iOS 與 Android
                // 能夠決定「那條列究竟該不該出現」的東西。
                let heading = finalContentResult.preferences.navigationTitle
                guard items != lastAppliedToolbar || heading != lastAppliedNavigationTitle
                else { return }
                backend.setToolbar(
                    ofWindow: window as! NewBackend.Window,
                    to: items,
                    title: heading
                )
                lastAppliedToolbar = items
                lastAppliedNavigationTitle = heading
            }
            setToolbar(backend: toolbarBackend)
        }

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

        // Generally just used to update the window color scheme
        backend.updateWindow(window, environment: environment)

        // Delay committing the view graph so that the View.inspectWindow(_:)
        // modifiers can be used to overwrite certain SwiftCrossUI behaviors
        viewGraph.commit()

        if isFirstUpdate {
            backend.show(window: window)
            isFirstUpdate = false
        }

        // Apply after the first show, not before it. GTK's platform handle does
        // not exist until the window is realized, so the old "apply before
        // show, then remember it as applied" path could silently drop an
        // initial `.floating` request. Keep reasserting `.floating`, because a
        // backend resize may replace the platform window and lose topmost
        // state. Do not reassert unchanged `.automatic` or `.normal`: on
        // Windows those can map to `HWND_NOTOPMOST`, which undoes the temporary
        // topmost pin used by `-actionfile` replays.
        if let levelBackend = backend as? any BackendFeatures.WindowLevels {
            func setLevel<NewBackend: BackendFeatures.WindowLevels>(backend: NewBackend) {
                var level = environment.windowLevel
                if !backend.supportedWindowLevels.contains(level) {
                    warnAboutWindowLevelOnce(level, backend: NewBackend.self)
                    level = .normal
                }

                let shouldApply =
                    environment.windowLevel != lastRequestedWindowLevel
                    || level == .floating

                guard shouldApply else { return }
                backend.setLevel(ofWindow: window as! NewBackend.Window, to: level)
                lastRequestedWindowLevel = environment.windowLevel
            }
            setLevel(backend: levelBackend)
        } else if environment.windowLevel != .automatic {
            warnAboutWindowLevelOnce(environment.windowLevel, backend: Backend.self)
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
