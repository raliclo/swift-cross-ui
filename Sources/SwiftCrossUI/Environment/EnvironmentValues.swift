import Foundation

/// The environment used when constructing scenes and views. Each scene or view
/// gets to modify the environment before passing it on to its children, which
/// is the basis of many view modifiers.
public struct EnvironmentValues {
    /// A font resolution context derived from the current environment.
    ///
    /// Essentially just a subset of the environment.
    @MainActor
    public var fontResolutionContext: Font.Context {
        Font.Context(
            overlay: fontOverlay,
            deviceClass: backend.deviceClass,
            resolveTextStyle: { backend.resolveTextStyle($0) }
        )
    }

    /// The current font resolved to a form suitable for rendering.
    ///
    /// Just a helper method for our own backends. We haven't made this public
    /// because it would be weird to have two pretty equivalent ways of resolving
    /// fonts.
    @MainActor
    @_spi(Backends) public var resolvedFont: Font.Resolved {
        font.resolve(in: fontResolutionContext)
    }

    /// The suggested foreground color for backends to use.
    ///
    /// Backends don't neccessarily have to obey this when
    /// ``EnvironmentValues/foregroundColor`` is `nil`.
    ///
    /// When it is `nil`, prefer reading ``EnvironmentValues/foregroundColor``
    /// directly and falling back to the platform's own label color:
    /// `NSColor.labelColor`, `UIColor.label`, the GTK theme's `color`, WinUI's
    /// `TextFillColorPrimary`. Those carry secondary, disabled and
    /// high-contrast variants that this property cannot express, because
    /// ``ColorScheme/defaultForegroundColor`` is plain black or white.
    ///
    /// The trap is that this property is never `nil`, so it collapses "the
    /// application asked for a color" and "the application asked for nothing"
    /// into one value, and obeying it unconditionally is the path of least
    /// resistance. `UIKitBackend.attributedString` shows the shape to copy: it
    /// reads the optional and supplies a platform color when there is none.
    public var suggestedForegroundColor: Color {
        foregroundColor ?? colorScheme.defaultForegroundColor
    }

    /// Called by view graph nodes when they resize due to an internal state
    /// change and end up changing size.
    ///
    /// Each view graph node sets its own handler when passing the environment
    /// on to its children, setting up a bottom-up update chain up which resize
    /// events can propagate.
    @_spi(Backends) public var onResize: @MainActor (_ newSize: ViewSize) -> Void

    /// Backing storage for extensible subscript
    private var values: [ObjectIdentifier: Any]

    /// An internal environment value used to control whether layout caching is
    /// enabled or not.
    ///
    /// This is set to `true` when computing non-final layouts. E.g. when a stack
    /// computes the minimum and maximum sizes of its children, it should enable
    /// layout caching because those updates are guaranteed to be non-final. The
    /// reason that we can't cache on non-final updates is that the last layout
    /// proposal received by each view must be its intended final proposal.
    var allowLayoutCaching: Bool = false

    /// Backing storage for observable subscript
    private var observableObjects: [ObjectIdentifier: any ObservableObject]

    /// Gets an environment value given an environment key's metatype.
    ///
    /// - Parameter key: The type of the key.
    /// - Returns: The environment value associated with `key`, or the key's
    ///   default value if it hasn't been set in the environment yet.
    public subscript<T: EnvironmentKey>(_ key: T.Type) -> T.Value {
        get {
            values[ObjectIdentifier(T.self), default: T.defaultValue] as! T.Value
        }
        set {
            values[ObjectIdentifier(T.self)] = newValue
        }
    }

    public subscript<T: ObservableObject>(observable key: T.Type) -> T? {
        get {
            guard let value = observableObjects[ObjectIdentifier(T.self)] as? T? else {
                let message =
                    "EnvironmentValues type mismatch: value for key '\(T.self).self' doesn't match expected type '\(T.self)'"
                logger.critical("\(message)")
                fatalError(message)
            }
            return value
        }
        set {
            observableObjects[ObjectIdentifier(T.self)] = newValue
        }
    }

    /// Brings the current window forward.
    ///
    /// This is not guaranteed to always bring the window to the top (due
    /// to focus stealing prevention).
    @MainActor
    func bringWindowForward() {
        func activate<Backend: BaseAppBackend>(with backend: Backend) {
            backend.activate(window: window as! Backend.Window)
        }
        activate(with: backend)
    }

    /// The backend in use.
    ///
    /// Mustn't change throughout the app's lifecycle.
    let backend: any BaseAppBackend

    /// Presents an 'Open file' dialog fit for selecting a single file.
    ///
    /// Displays as a modal for the current window, or the entire app if
    /// accessed outside of a scene's view graph (in which case the backend
    /// can decide whether to make it an app modal, a standalone window, or a
    /// modal for a window of its choosing).
    ///
    /// - Important: GtkBackend and WinUIBackend will only
    ///   enable _either_ files or directories for selection, but won't
    ///   enable both types in a single dialog.
    @MainActor
    @available(tvOS, unavailable, message: "tvOS does not provide file system access")
    public var chooseFile: PresentSingleFileOpenDialogAction {
        PresentSingleFileOpenDialogAction(
            backend: backend,
            window: MainActorBox(value: window)
        )
    }

    /// Presents a 'Save file' dialog fit for selecting a save destination.
    ///
    /// Displays as a modal for the current window, or the entire app if
    /// accessed outside of a scene's view graph (in which case the backend
    /// can decide whether to make it an app modal, a standalone window, or a
    /// window of its choosing).
    @MainActor
    public var chooseFileSaveDestination: PresentFileSaveDialogAction {
        PresentFileSaveDialogAction(
            backend: backend,
            window: MainActorBox(value: window)
        )
    }

    /// Presents an alert for the current window, or the entire app if accessed
    /// outside of a scene's view graph (in which case the backend can decide
    /// whether to make it an app modal, a standalone window, or a modal for a
    /// window of its choosing).
    @MainActor
    public var presentAlert: PresentAlertAction {
        PresentAlertAction(environment: self)
    }

    /// Opens a URL with the default application.
    ///
    /// May present an application picker if multiple applications are registered
    /// for the given URL protocol.
    ///
    /// `nil` on platforms that don't support opening external URLS (none at the
    /// moment).
    @MainActor
    public var openURL: OpenURLAction {
        OpenURLAction(backend: backend)
    }

    /// Opens a window with the specified ID.
    @MainActor
    public var openWindow: OpenWindowAction {
        OpenWindowAction(environment: self)
    }

    /// Closes the enclosing window.
    @MainActor
    public var dismissWindow: DismissWindowAction {
        DismissWindowAction(
            backend: backend,
            window: MainActorBox(value: window)
        )
    }

    /// Reveals a file in the system's file manager.
    ///
    /// This opens the file's enclosing directory and highlights the file.
    ///
    /// `nil` on platforms that don't support revealing files, e.g. iOS.
    @MainActor
    public var revealFile: RevealFileAction? {
        RevealFileAction(backend: backend)
    }

    /// Whether the backend can have multiple windows open at once. Mobile
    /// backends generally can't.
    @MainActor
    public var supportsMultipleWindows: Bool {
        backend.supportsMultipleWindows
    }

    /// The display styles supported by ``DatePicker``.
    ///
    /// In backend vocabulary, because that is what a backend can answer for.
    /// A style written outside this module is not in this list and does not
    /// need to be: it draws itself out of ordinary views, so
    /// ``DatePickerStyle/isSupported(backend:)`` defaults to `true` for it.
    ///
    /// 以 backend 的詞彙表達，因為那才是 backend 答得出來的東西。在本模組之外撰寫的 style 不會
    /// 出現在此清單中，也不需要出現：它是以一般的 view 自行繪製的，因此
    /// ``DatePickerStyle/isSupported(backend:)`` 對它預設回傳 `true`。
    public let supportedDatePickerStyles: [BackendDatePickerStyle]

    /// The window levels the current backend can actually place a window at.
    ///
    /// Asking is only necessary for an app that wants to do something different
    /// where a level is unavailable. Simply setting one is safe: an unsupported
    /// level falls back to ``WindowLevel/normal`` and is logged. See
    /// ``Scene/windowLevel(_:)``.
    public let supportedWindowLevels: [WindowLevel]

    /// Checks whether a picker style is supported by the current backend.
    @MainActor
    public var isPickerStyleSupported: PickerSupportedAction {
        PickerSupportedAction(backend: backend)
    }

    /// Creates the default environment.
    ///
    /// - Parameters:
    ///   - backend: The app's backend.
    @_spi(Backends) public init<Backend: BaseAppBackend>(backend: Backend) {
        self.backend = backend

        onResize = { _ in }
        values = [:]
        observableObjects = [:]

        if let backend = backend as? any BackendFeatures.DatePickers {
            self.supportedDatePickerStyles = backend.supportedDatePickerStyles
        } else {
            self.supportedDatePickerStyles = [.automatic]
        }

        // A backend that does not conform still supports `.normal`: an ordinary
        // window is what it produces without being asked. Only `.floating`
        // needs an implementation.
        // 未實作此協定的 backend 仍然支援 `.normal`：不特別要求時，它產生的本來就是一般視窗。
        // 只有 `.floating` 才需要實作。
        if let backend = backend as? any BackendFeatures.WindowLevels {
            self.supportedWindowLevels = backend.supportedWindowLevels
        } else {
            self.supportedWindowLevels = [.automatic, .normal]
        }
    }

    /// Returns a copy of the environment with the specified property set to the
    /// provided new value.
    ///
    /// - Parameters:
    ///   - keyPath: A key path to the property to set.
    ///   - newValue: The new value of the property.
    /// - Returns: A copy of the environment with the specified property set to
    ///   `newValue`.
    public func with<T>(_ keyPath: WritableKeyPath<Self, T>, _ newValue: T) -> Self {
        var environment = self
        environment[keyPath: keyPath] = newValue
        return environment
    }
}

extension EnvironmentValues {
    /// The app storage provider to use for `@AppStorage` property wrappers.
    @Entry public var appStorageProvider: any AppStorageProvider = DefaultAppStorageProvider()

    /// The current stack orientation.
    ///
    /// Inherited by ``ForEach`` and ``Group`` so that they can be used without
    /// affecting layout.
    @Entry public var layoutOrientation: Orientation = .vertical

    /// The current stack alignment.
    ///
    /// Inherited by ``ForEach`` and ``Group`` so that they can be used without
    /// affecting layout.
    @Entry public var layoutAlignment: StackAlignment = .center

    /// Whether to use the ZStack StackLayout variants.
    @Entry public var usesZStackLayout: Bool = false

    /// The alignment of content inside a ``ZStack``.
    /// Only gets used when ``usesZStackLayout`` is `true`.
    @Entry public var zStackContentAlignment: Alignment = .center

    /// The current stack spacing.
    ///
    /// Inherited by ``ForEach`` and ``Group`` so that they can be used without
    /// affecting layout.
    @Entry public var layoutSpacing: Int = 10


    /// The columns a ``LazyVGrid`` resolved, for whoever arranges the cells.
    ///
    /// Set by ``LazyVGrid`` and cleared by ``VStack``, ``HStack`` and ``ZStack``,
    /// for the same reason ``layoutOverlapsChildren`` is: ``ForEach`` builds a
    /// real container and has to be told how its parent arranges things. A grid
    /// whose content is a `ForEach` sees one child, and arranging one child in a
    /// grid produces a single column -- which looks like a grid with the wrong
    /// column count rather than like a grid that never ran. See
    /// ``GridLayoutPlan``.
    ///
    /// 某個 ``LazyVGrid`` 所解析出來的欄位,供真正排列儲存格的一方使用。
    ///
    /// 由 ``LazyVGrid`` 設定,並由 ``VStack``、``HStack`` 與 ``ZStack`` 清除,理由與
    /// ``layoutOverlapsChildren`` 相同:``ForEach`` 會建立一個真正的容器,因此必須被告知其父層是
    /// 怎麼排列的。一個「內容是 `ForEach`」的格線只看得到一個子節點,而把一個子節點排進格線會產生
    /// 單一欄——那看起來像是「欄數算錯的格線」,而不像是「從未執行的格線」。見 ``GridLayoutPlan``。
    @Entry public var layoutGridPlan: GridLayoutPlan? = nil

    /// Whether the text in a ``Table`` can be selected and copied.
    ///
    /// Off by default, and set with ``View/tableTextSelection(_:)``. Selection
    /// changes how a table behaves under the pointer and the keyboard, so a
    /// read-only table should not acquire it because another table wanted it.
    @Entry public var tableTextSelection: Bool = false

    /// The current font.
    @Entry public var font: Font = .body

    /// A font overlay storing font modifications.
    ///
    /// If these conflict with the font's internal overlay, these win out.
    ///
    /// We keep this separate overlay for modifiers because we want modifiers to
    /// be persisted even if the developer sets a custom font further down the
    /// view hierarchy.
    @Entry internal var fontOverlay = Font.Overlay()

    /// How lines should be aligned relative to each other when line wrapped.
    @Entry public var multilineTextAlignment: HorizontalAlignment = .leading

    /// Whether to override the case of displayed ``Text`` views.
    ///
    /// `nil` displays the text without any case changes.
    @Entry public var textCase: Text.Case?

    /// The current color scheme of the current view scope.
    @Entry public var colorScheme: ColorScheme = .light

    /// The foreground color.
    ///
    /// `nil` means that the default foreground color of the current color scheme
    /// should be used.
    @Entry public var foregroundColor: Color?

    /// Called when a text field gets submitted (usually due to the user
    /// pressing Enter/Return).
    @Entry public var onSubmit: (@MainActor @Sendable () -> Void)?

    /// The action a scroll container should run when the user pulls to refresh.
    ///
    /// In the environment rather than on ``ScrollView`` because `.refreshable`
    /// is applied to whatever is inside the scroll view, exactly as SwiftUI
    /// spells it -- `List { ... }.refreshable { ... }` puts the modifier on the
    /// list, and the container that has to grow the control is its ancestor.
    ///
    /// Unlike ``onSubmit`` it does NOT chain. Two nested `.refreshable`s in
    /// SwiftUI give the inner scroll view the inner action, not both; a scroll
    /// view running an ancestor's refresh as well would refresh things the user
    /// cannot see.
    ///
    /// scroll container 在使用者下拉重新整理時應執行的動作。
    ///
    /// 放在 environment 而非 ``ScrollView`` 上,因為 `.refreshable` 是套用在捲動視圖**內部**的東西上,
    /// 這與 SwiftUI 的寫法完全一致——`List { ... }.refreshable { ... }` 是把 modifier 加在 list 上,
    /// 而必須長出那個控制項的容器是它的祖先。
    ///
    /// 與 ``onSubmit`` 不同,它**不**串接。SwiftUI 中兩層巢狀的 `.refreshable` 會讓內層捲動視圖取得
    /// 內層的動作,而不是兩者都執行;一個連祖先的 refresh 也一併執行的捲動視圖,會去重新整理使用者
    /// 看不到的東西。
    @Entry public var onRefresh: (@MainActor @Sendable () -> Void)?

    /// Where ``View/id(_:)`` registers and ``ScrollViewProxy`` looks.
    ///
    /// `nil` outside a ``ScrollViewReader``, which is why `.id(_:)` costs
    /// nothing when nobody is going to scroll to it: the modifier checks this
    /// and returns.
    ///
    /// ``View/id(_:)`` 登記之處,也是 ``ScrollViewProxy`` 查找之處。
    ///
    /// 在 ``ScrollViewReader`` 之外為 `nil`,而那正是「當沒有人打算捲向它時,`.id(_:)` 不花任何成本」
    /// 的原因:該 modifier 會檢查這個值然後直接返回。
    @Entry public var scrollAnchors: ScrollAnchorRegistry?

    /// The scale factor of the current window.
    @Entry public var windowScaleFactor: Double = 1

    /// The type of input that text fields represent.
    ///
    /// This affects autocomplete suggestions, and on devices with no physical keyboard, which
    /// on-screen keyboard to use.
    ///
    /// - Warning: Do not use this in place of validation, even if you only plan on supporting
    ///   mobile devices, as this does not restrict copy-paste and many mobile devices support
    ///   Bluetooth keyboards.
    @Entry public var textContentType: TextContentType = .text

    /// The way that scrollable content interacts with the software keyboard.
    @Entry public var scrollDismissesKeyboardMode: ScrollDismissesKeyboardMode = .automatic

    /// The style of list to use.
    @Entry public var listStyle: any ListStyle = .automatic

    /// The same style, already resolved to something a backend understands.
    ///
    /// The same split as ``backendDatePickerStyle`` and for the same reason:
    /// `updateSelectableListView` receives the environment rather than the
    /// view, so this is where a backend can reach a value from its own
    /// vocabulary.
    ///
    /// 與 ``backendDatePickerStyle`` 相同的拆分，理由也相同：`updateSelectableListView` 收到的是
    /// environment 而非 view，因此此處便是 backend 能取到「出自其自身詞彙之值」的地方。
    @_spi(Backends)
    @Entry public var backendListStyle: BackendListStyle = .default

    /// The role of the button currently being updated, if it has one.
    ///
    /// Carried through the environment rather than added to
    /// ``BackendFeatures/Controls/updateButton(_:label:environment:action:)``
    /// so that adding it does not break every backend at once. A backend that
    /// ignores it draws an ordinary button, which is the correct degradation:
    /// the action still works and only the warning colour is missing.
    ///
    /// Set by ``Button`` on the environment it hands the backend, not inherited
    /// from an ancestor -- a role belongs to one button, unlike a style.
    ///
    /// 目前正在更新的按鈕之 role（若有）。
    ///
    /// 透過 environment 傳遞，而非加入
    /// ``BackendFeatures/Controls/updateButton(_:label:environment:action:)``，如此新增它就不會
    /// 一次弄壞所有 backend。忽略它的 backend 會畫出一般按鈕，而那正是正確的降級方式：動作照常
    /// 運作，缺少的只是警示色。
    ///
    /// 此值由 ``Button`` 設定於它交給 backend 的 environment 上，而非自祖先繼承而來——role 屬於
    /// 單一按鈕，這一點與 style 不同。
    @_spi(Backends)
    @Entry public var buttonRole: ButtonRole?

    /// The style of toggle to use.
    @Entry public var toggleStyle: any ToggleStyle = .button

    /// The style of text field to use. Set with ``View/textFieldStyle(_:)``.
    ///
    /// Read by ``TextField``, which routes its body through the style, as
    /// ``Toggle`` does through ``toggleStyle``. A backend cannot read this --
    /// it is an `any TextFieldStyle` and may hold a type this module has never
    /// heard of -- so the built-in path resolves it to
    /// ``backendTextFieldStyle`` on its way down.
    ///
    /// 文字輸入框所使用的樣式，以 ``View/textFieldStyle(_:)`` 設定。
    ///
    /// 由 ``TextField`` 讀取，它會將自己的 body 交由該 style 繪製，正如 ``Toggle`` 之於
    /// ``toggleStyle``。backend 讀不懂此值——它是 `any TextFieldStyle`，其中可能放著一個本模組從未
    /// 聽過的型別——因此內建路徑會在往下傳遞的途中，把它解析成 ``backendTextFieldStyle``。
    @Entry public var textFieldStyle: any TextFieldStyle = .automatic

    /// The same style, already resolved to something a backend understands.
    ///
    /// The same split as ``backendListStyle`` and ``backendDatePickerStyle``,
    /// and for the same reason: `updateTextField` receives the environment
    /// rather than the view, so this is where a backend can reach a value from
    /// its own vocabulary. Putting the shape here rather than in that signature
    /// also means adding text field styles did not have to touch a method seven
    /// backends implement.
    ///
    /// Unlike those two, this is **not** written by the modifier. It is set by
    /// ``_BuiltinTextFieldImplementation`` on the environment it hands the
    /// backend, and only there -- see that type for the reasoning. The
    /// consequence is that its value is `.automatic` everywhere except at the
    /// moment a built-in text field is being committed, which is exactly the
    /// set of places that should read it.
    ///
    /// 與 ``backendListStyle``、``backendDatePickerStyle`` 相同的拆分，理由也相同：
    /// `updateTextField` 收到的是 environment 而非 view，因此此處便是 backend 能取到「出自其自身
    /// 詞彙之值」的地方。把外形放在這裡而不是放進該簽章，也意味著新增文字輸入框樣式，不必去動一個
    /// 有七個 backend 實作的方法。
    ///
    /// 與那兩者不同的是，此值**並非**由 modifier 寫入，而是由
    /// ``_BuiltinTextFieldImplementation`` 設定於它交給 backend 的 environment 上，且僅止於此
    /// ——理由見該型別。其結果是：除了「內建文字輸入框正在被 commit」的那一刻之外，它在任何地方都
    /// 是 `.automatic`，而那正好就是應該讀取它的地方所構成的集合。
    @_spi(Backends)
    @Entry public var backendTextFieldStyle: BackendTextFieldStyle = .automatic

    /// The style ``ProgressView`` uses. Set with
    /// ``View/progressViewStyle(_:)``.
    /// ``ProgressView`` 所使用的樣式。以 ``View/progressViewStyle(_:)`` 設定。
    @Entry public var progressViewStyle: any ProgressViewStyle = .automatic

    /// What the ``ProgressView``'s initialiser chose, for
    /// ``ProgressViewStyle/automatic`` to hand back unchanged.
    ///
    /// Internal, and in the environment rather than a parameter, because a
    /// custom style's `makeView` has no business receiving it -- it builds its
    /// own view and the default is meaningless to it.
    ///
    /// ``ProgressView`` 的建構式所做的選擇，供 ``ProgressViewStyle/automatic`` 原樣交還。
    ///
    /// 設為 internal，且放在 environment 而非參數中，因為自訂樣式的 `makeView` 沒有理由收到它
    /// ——它建構的是自己的 view，那個預設值對它毫無意義。
    @Entry internal var progressViewDefaultKind: _ProgressIndicatorKind = .spinner

    /// Whether the spinner `ProgressView(_:)` builds may resize.
    /// `ProgressView(_:)` 所建構的轉圈是否可以縮放。
    @Entry internal var progressSpinnerIsResizable: Bool = false

    /// The style of label to use.
    ///
    /// There is no `backendLabelStyle` beside this one, unlike
    /// ``backendListStyle`` and ``backendDatePickerStyle``. Those exist because
    /// a backend receives the environment and needs a value from its own
    /// vocabulary; a label style never reaches a backend at all, since ``Label``
    /// is composed entirely out of other views.
    ///
    /// 此處沒有與之並列的 `backendLabelStyle`，這一點與 ``backendListStyle``、
    /// ``backendDatePickerStyle`` 不同。那兩者的存在，是因為 backend 收到的是 environment，需要一個
    /// 出自其自身詞彙的值；而 label style 根本不會抵達任何 backend，因為 ``Label`` 完全是由其他
    /// view 組合而成的。
    @Entry public var labelStyle: any LabelStyle = .automatic

    /// The active background color of button-style toggles.
    @Entry public var toggleColor: Color?

    /// Whether the text should be selectable.
    ///
    /// Set by ``View/textSelectionEnabled(_:)``.
    @Entry public var isTextSelectionEnabled: Bool = false

    /// The resizing behaviour of windows.
    ///
    /// Set by ``Window/windowResizability(_:)->Scene``.
    @Entry internal var windowResizability: WindowResizability = .automatic

    /// Where windows sit in the stack of windows on screen.
    ///
    /// Set by ``Scene/windowLevel(_:)``.
    @Entry internal var windowLevel: WindowLevel = .automatic

    /// The default launch behavior of windows.
    ///
    /// Set by ``Window/defaultLaunchBehavior(_:)->Scene``.
    @Entry internal var defaultLaunchBehavior: SceneLaunchBehavior = .automatic

    /// The default size of windows.
    ///
    /// Defaults to 900x450.
    ///
    /// Set by ``Window/defaultSize(width:height:)->Scene``.
    @Entry internal var defaultWindowSize: SIMD2<Int> = SIMD2(900, 450)

    /// The id of the window this view is being displayed in.
    ///
    /// The same string the scene hands to ``createWindow(withDefaultSize:id:)``,
    /// which backends already use to restore a window's frame from disk. It is
    /// `nil` outside a window -- in a menu item's environment, for instance --
    /// and ``SceneStorage`` treats that as "no scope to store against" rather
    /// than inventing one, because a value stored under a guessed id would be
    /// written and never read again.
    ///
    /// 這個 view 正被顯示於其中的那個視窗的 id。
    ///
    /// 與 scene 交給 ``createWindow(withDefaultSize:id:)`` 的是同一個字串，而各 backend 本來就用它
    /// 從磁碟還原視窗的框。在視窗之外——例如某個選單項目的 environment 中——它是 `nil`，而
    /// ``SceneStorage`` 會把那視為「沒有可供存放的範圍」，而不是自行捏造一個：一個存在猜來的 id 底下
    /// 的值，會被寫進去，然後再也不會被讀到。
    @Entry internal var sceneID: String? = nil

    /// The menu ordering to use.
    @Entry public var menuOrder: MenuOrder = .automatic

    /// Backing store for ``EnvironmentValues/openWindowFunctionsByID``.
    /// Used to resolve "non-sendable type" warnings in Swift 5 and errors in Swift 6 language mode.
    @Entry private var openWindowFunctionsByIDStore = UncheckedSendable(
        wrappedValue: Box<[String: @MainActor () -> Void]>([:])
    )

    /// A mapping of window IDs to functions that open the corresponding windows.
    internal var openWindowFunctionsByID: Box<[String: @MainActor () -> Void]> {
        get {
            openWindowFunctionsByIDStore.wrappedValue
        }
        set {
            openWindowFunctionsByIDStore.wrappedValue = newValue
        }
    }

    /// The app's lifecycle phase.
    ///
    /// Unlike in SwiftUI, where the app's lifecycle phase can only be accessed
    /// by using `@Environment(\.scenePhase)` directly on the ``App`` struct, this
    /// environment value can be accessed from anywhere within the application.
    @Entry public package(set) var appPhase: AppPhase = .active

    /// The current scene's lifecycle phase.
    ///
    /// - Important: Unlike SwiftUI, this environment value cannot be accessed from
    ///   outside a scene. If you need to access the phase of the entire application,
    ///   use ``appPhase`` instead.
    public package(set) var scenePhase: ScenePhase {
        get {
            guard let phase = self[__Key_scenePhase.self] else {
                if window != nil {
                    // If there's a window but no scenePhase, we assume that the
                    // backend is actively trying to _set_ the scene phase; return
                    // a dummy value to prevent a crash.
                    return .inactive
                }

                fatalError(
                    """
                    'scenePhase' accessed from outside a scene (most likely \
                    with an @Environment property on the App struct); you \
                    probably meant to use 'appPhase' instead
                    """
                )
            }
            return phase
        }
        set { self[__Key_scenePhase.self] = newValue }
    }
    private struct __Key_scenePhase: EnvironmentKey {
        static let defaultValue: ScenePhase? = nil
    }

    /// Backing store for ``EnvironmentValues/window``.
    /// Used to resolve "non-sendable type" warnings in Swift 5 and errors in Swift 6 language mode.
    @Entry private var windowStore = UncheckedSendable<Any?>(wrappedValue: nil)

    /// The backend's representation of the window that the current view is
    /// in, if any.
    ///
    /// This is a very internal detail that should never get exposed to users.
    @_spi(Backends) public var window: Any? {
        get {
            windowStore.wrappedValue
        }
        set {
            windowStore.wrappedValue = newValue
        }
    }

    /// Backing store for ``EnvironmentValues/sheet``.
    /// Used to resolve "non-sendable type" warnings in Swift 5 and errors in Swift 6 language mode.
    @Entry private var sheetStore = UncheckedSendable<Any?>(wrappedValue: nil)

    /// The backend's representation of the sheet that the current view is
    /// in, if any.
    ///
    /// This is a very internal detail that should never get exposed to users.
    @_spi(Backends) public var sheet: Any? {
        get {
            sheetStore.wrappedValue
        }
        set {
            sheetStore.wrappedValue = newValue
        }
    }

    /// The current calendar that views should use when handling dates.
    @Entry public var calendar: Calendar = .current

    /// The current time zone that views should use when handling dates.
    @Entry public var timeZone: TimeZone = .current

    /// The current locale.
    @Entry public var locale: Locale = .current

    /// The display style used by ``Picker``.
    @Entry public var pickerStyle: any PickerStyle = .automatic

    /// The display style used by ``DatePicker``.
    @Entry public var datePickerStyle: any DatePickerStyle = .automatic

    /// The same style, already resolved to something a backend understands.
    ///
    /// Two entries rather than one because the two audiences want different
    /// things. An application sets and reads ``datePickerStyle``, which may hold
    /// a style this module has never heard of. A backend needs a value from its
    /// own vocabulary, and `updateDatePicker` receives the environment rather
    /// than the view, so this is where it can find one.
    ///
    /// It stays `.automatic` for a style that is not built in, which is correct:
    /// such a style never reaches the backend's date input at all, having drawn
    /// itself out of ordinary views instead.
    ///
    /// 分成兩個 entry 而非一個，因為兩邊的讀者要的東西不同。應用程式設定與讀取的是
    /// ``datePickerStyle``，其中可能放著一個本模組從未聽過的 style。而 backend 需要的是出自它自己
    /// 詞彙的值，且 `updateDatePicker` 收到的是 environment 而非 view，因此此處便是它取用之處。
    ///
    /// 對於非內建的 style，此值維持 `.automatic`，而這是正確的：那樣的 style 根本不會抵達 backend
    /// 的日期輸入元件，它是以一般的 view 自行繪製的。
    @_spi(Backends)
    @Entry public var backendDatePickerStyle: BackendDatePickerStyle = .automatic

    /// Whether user interaction is enabled.
    ///
    /// Set by ``View/disabled(_:)``.
    @Entry public var isEnabled: Bool = true

    /// The number of lines text can occupy and whether to reserve that space.
    @Entry public var lineLimitSettings: LineLimit?

    /// The maximum number of lines that text can occupy in a view.
    public var lineLimit: Int? {
        lineLimitSettings?.limit
    }

    /// Whether the current device has a circular screen. Primarily Android smart watches.
    @Entry public var isCircularScreen: Bool = false

    /// The built-in display style used by ``Button``.
    ///
    /// Named `buttonStyle` and typed ``PrimitiveButtonStyle`` since 2026-09-08;
    /// only the type's name changed. This is the value every backend reads, and
    /// the vocabulary it is written in -- three cases -- is the backend's, not
    /// the application's.
    ///
    /// A custom ``ButtonStyle`` does not appear here. It goes in
    /// ``customButtonStyle`` and ``Button`` overrides *this* value with `.plain`
    /// while one is in effect, so the platform stops drawing chrome underneath a
    /// style that draws its own.
    ///
    /// 由 ``Button`` 使用的內建顯示樣式。
    ///
    /// 自 2026-09-08 起名稱為 `buttonStyle`、型別為 ``PrimitiveButtonStyle``；改變的只有型別名稱。
    /// 這是每一個 backend 都會讀取的值，而它所使用的詞彙——三個 case——屬於 backend，而非應用程式。
    ///
    /// 自訂的 ``ButtonStyle`` 不會出現在此處。它放在 ``customButtonStyle``，而在其生效期間 ``Button``
    /// 會把**本值**覆寫為 `.plain`，好讓平台停止在「自行繪製的樣式」底下畫出自身外框。
    @Entry public var buttonStyle: PrimitiveButtonStyle?

    /// The application-supplied ``ButtonStyle``, if any.
    ///
    /// Type-erased because ``EnvironmentValues`` is not generic; see
    /// ``View/buttonStyle(_:)-(S)`` for the full reasoning. Stored beside
    /// ``buttonStyle`` rather than merged into it because the two are read by
    /// different code for different purposes: this one only ever reaches
    /// ``Button``, and no backend has any use for it.
    ///
    /// Optional, unlike ``labelStyle``, because there is no default conformer to
    /// fall back to. The absence of a custom style is not "the automatic custom
    /// style"; it means the platform draws the button, which is what
    /// ``buttonStyle`` describes.
    ///
    /// 應用程式提供的 ``ButtonStyle``（若有）。
    ///
    /// 之所以型別抹除，是因為 ``EnvironmentValues`` 並非泛型；完整理由見
    /// ``View/buttonStyle(_:)-(S)``。它與 ``buttonStyle`` 並列而非合而為一，是因為兩者被不同的程式碼
    /// 以不同目的讀取：本值只會抵達 ``Button``，任何 backend 都用不到它。
    ///
    /// 與 ``labelStyle`` 不同，本值是 optional，因為此處沒有可退回的預設 conformer。「沒有自訂樣式」
    /// 並不等於「採用自動的自訂樣式」；它的意思是按鈕由平台繪製，而那正是 ``buttonStyle`` 所描述的事。
    @Entry public var customButtonStyle: (any ButtonStyle)?

    /// The default button style as declared by the backend.
    @MainActor
    public var defaultButtonStyle: PrimitiveButtonStyle {
        backend.defaultButtonStyle()
    }

    /// The resolved ``PrimitiveButtonStyle``. Either ``buttonStyle``, or ``defaultButtonStyle`` if nil.
    @MainActor
    public var resolvedButtonStyle: PrimitiveButtonStyle {
        buttonStyle ?? defaultButtonStyle
    }

    /// The amount of padding that the current backend applies to the labels of buttons with the current ``PrimitiveButtonStyle``.
    @MainActor
    public var buttonPadding: SIMD2<Int> {
        backend.buttonPadding(in: self)
    }

    /// The device class of the current device.
    @MainActor
    public var deviceClass: DeviceClass { backend.deviceClass }
}

extension EnvironmentValues {
    func applyingTextTransforms(to string: String) -> String {
        var string = string

        switch textCase {
            case .lowercase: string = string.lowercased(with: locale)
            case .uppercase: string = string.uppercased(with: locale)
            case nil: break
        }

        return string
    }
}


/// A key that can be used to extend the environment with new properties.
public protocol EnvironmentKey<Value> {
    /// The type of value the key can hold.
    associatedtype Value
    /// The default value for the key.
    static var defaultValue: Value { get }
}
