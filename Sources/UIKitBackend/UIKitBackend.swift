import Logging
@_spi(Backends) import SwiftCrossUI
import Metal
import UIKit

public final class UIKitBackend:
    BaseAppBackend,
    BackendFeatures.ExternalURLs,
    BackendFeatures.IncomingURLs,
    BackendFeatures.Alerts,
    BackendFeatures.Sheets,
    BackendFeatures.Popovers,
    BackendFeatures.CornerRadius,
    BackendFeatures.Paths,
    BackendFeatures.Tooltips,
    BackendFeatures.Colors,
    BackendFeatures.Gradients,
    // Listed here, so `UIKitBackend+ButtonPressState.swift` must be a bare
    // `extension UIKitBackend { ... }`; naming the protocol in both places is
    // `error: redundant conformance`.
    // 在此處列出，因此 `UIKitBackend+ButtonPressState.swift` 必須是不帶 conformance 的
    // `extension UIKitBackend { ... }`；兩處都寫上該 protocol 會得到 `error: redundant conformance`。
    BackendFeatures.ButtonPressState
{
    /// The Metal device chosen by `-GPU N`. See
    /// `UIKitBackend+GraphicsAdapters.swift`.
    /// 由 `-GPU N` 選定的 Metal 裝置。見 `UIKitBackend+GraphicsAdapters.swift`。
    var metalDevice: (any MTLDevice)?

    /// The one frame clock. See ``UIKitFrameClockTarget`` for why the target is
    /// a separate object.
    /// 那唯一一個 frame clock。target 之所以是獨立物件，見 ``UIKitFrameClockTarget``。
    var frameClockLink: CADisplayLink?
    var frameClockTarget: UIKitFrameClockTarget?
    var frameClockHandler: (@MainActor (Double) -> Void)? {
        get { Self.currentFrameClockHandler }
        set { Self.currentFrameClockHandler = newValue }
    }
    @MainActor static var currentFrameClockHandler: (@MainActor (Double) -> Void)?

    static var onWindowEnvironmentChange: (() -> Void)?
    static var onBecomeActive: (() -> Void)?

    /// Windows waiting for the scene `show(window:)` requested for them; the
    /// next connecting scene takes the first. See `SceneDelegate`.
    static var pendingSceneWindows: [UIWindow] = []
    static var onReceiveURL: ((URL) -> Void)?
    static var queuedURLs: [URL] = []

    /// The first window to get created.
    static var mainWindow: UIWindow?
    static var hasReturnedAWindow = false

    private var timeZoneObserver: NSObjectProtocol?

    public let scrollBarWidth = 0
    public let defaultPaddingAmount = 15
    public let requiresToggleSwitchSpacer = true

    // TODO: When tables are supported, update these
    public let defaultTableRowContentHeight = -1
    public let defaultTableCellVerticalPadding = -1

    public let requiresImageUpdateOnScaleFactorChange = false

    /// The platform's answer, not a constant. On iPad, Mac Catalyst and
    /// visionOS an app that declares `UIApplicationSupportsMultipleScenes` can
    /// open a window per scene (see `show(window:)`); on iPhone it cannot.
    /// A constant `false` would make `openWindow` on iPad log "the backend
    /// doesn't support multi-window, ignoring" and drop P5's second window.
    ///
    /// 平台自己的答案，而不是常數。在 iPad、Mac Catalyst 與 visionOS 上，宣告了
    /// `UIApplicationSupportsMultipleScenes` 的 app 可以每個 scene 開一個視窗（見 `show(window:)`）;
    /// 在 iPhone 上不行。若固定為 `false`，iPad 上的 `openWindow` 會記下
    /// 「the backend doesn't support multi-window, ignoring」，P5 的第二個視窗就不會出現。
    /// 「the backend doesn't support multi-window, ignoring」，P5 的第二個視窗從未出現。
    public var supportsMultipleWindows: Bool {
        UIApplication.shared.supportsMultipleScenes
    }
    public let canOverrideWindowColorScheme = true
    public let restoresWindowFrames = false

    public var deviceClass: DeviceClass {
        switch UIDevice.current.userInterfaceIdiom {
            case .phone:
                .phone
            case .pad, .vision:
                .tablet
            case .tv:
                .tv
            case .mac:
                .desktop
            case .unspecified, .carPlay:
                // Seems like the safest fallback for now given that we don't
                // explicitly support these devices.
                .tablet
            @unknown default:
                .tablet
        }
    }

    public var defaultPickerStyle: BackendPickerStyle {
        #if os(tvOS)
            .segmented
        #elseif os(visionOS)
            .menu
        #else
            if #available(iOS 14, macCatalyst 14, *) {
                .menu
            } else {
                .wheel
            }
        #endif
    }

    public var supportedPickerStyles: [BackendPickerStyle] {
        #if os(tvOS)
            if #available(tvOS 17, *) {
                [.menu, .segmented]
            } else {
                [.segmented]
            }
        #else
            // `.radioGroup` is `UIRadioGroupPicker`.
            // `.radioGroup` 由 `UIRadioGroupPicker` 實作。
            if #available(iOS 14, macCatalyst 14, *) {
                [.menu, .segmented, .wheel, .radioGroup]
            } else {
                [.segmented, .wheel, .radioGroup]
            }
        #endif
    }

    var onTraitCollectionChange: (() -> Void)?

    private let appDelegateClass: ApplicationDelegate.Type

    #if !os(tvOS)
        let filePickerDelegates = NSMapTable<UIDocumentPickerViewController, FilePickerDelegate>
            .weakToStrongObjects()
    #endif

    // Logging
    private struct LogLocation: Hashable, Equatable {
        let file: String
        let line: Int
        let column: Int
    }

    private var logsPerformed: Set<LogLocation> = []

    func debugLogOnce(
        _ message: String,
        file: String = #file,
        line: Int = #line,
        column: Int = #column
    ) {
        #if DEBUG
            let location = LogLocation(file: file, line: line, column: column)
            if logsPerformed.insert(location).inserted {
                logger.notice("\(message)")
            }
        #endif
    }

    public convenience init() {
        self.init(appDelegateClass: ApplicationDelegate.self)
    }

    public init(appDelegateClass: ApplicationDelegate.Type) {
        self.appDelegateClass = appDelegateClass
    }

    public func runMainLoop(
        _ callback: @escaping @MainActor () -> Void
    ) {
        Self.onReceiveURL = { url in
            Self.queuedURLs.append(url)
        }
        Self.onBecomeActive = callback
        UIApplicationMain(
            CommandLine.argc,
            CommandLine.unsafeArgv,
            NSStringFromClass(UIApplication.self),
            NSStringFromClass(appDelegateClass)
        )
    }

    public func setIncomingURLHandler(to action: @escaping (URL) -> Void) {
        // If the app wasn't already open, URLs can arrive before the view graph
        // gets a chance to register a handler. To fix this we store any early
        // URLs and replay them when the register gets added.
        runInMainThread {
            for url in Self.queuedURLs {
                action(url)
            }
            Self.queuedURLs = []
        }

        Self.onReceiveURL = action
    }

    public func computeRootEnvironment(defaultEnvironment: EnvironmentValues) -> EnvironmentValues {
        var environment = defaultEnvironment

        environment.toggleStyle = .switch
        environment.timeZone = .current

        // The system's scheme, not `UITraitCollection.current`: the window now
        // carries `overrideUserInterfaceStyle` for `preferredColorScheme`, and
        // read through it the preference would come back as the system's and
        // stay after the preference is removed. See `updateWindow`.
        // 系統的配色，不是 `UITraitCollection.current`:window 現在為 `preferredColorScheme` 設定了
        // `overrideUserInterfaceStyle`,經由它讀，偏好會被當成系統配色，並在偏好移除後留下。見 `updateWindow`。
        switch Self.systemUserInterfaceStyle {
            case .light:
                environment.colorScheme = .light
            case .dark:
                environment.colorScheme = .dark
            default:
                break
        }

        switch UIApplication.shared.applicationState {
            case .active: environment.appPhase = .active
            case .inactive: environment.appPhase = .inactive
            case .background: environment.appPhase = .background
            @unknown default:
                logger.warning(
                    """
                    UIApplication.applicationState returned unknown state
                    '\(UIApplication.shared.applicationState)'; ignoring and returning
                    'active' instead
                    """
                )
                environment.appPhase = .active
        }

        return environment
    }

    public func setRootEnvironmentChangeHandler(
        to action: @escaping @Sendable @MainActor () -> Void
    ) {
        onTraitCollectionChange = action
        if timeZoneObserver == nil {
            timeZoneObserver = NotificationCenter.default.addObserver(
                forName: .NSSystemTimeZoneDidChange,
                object: nil,
                queue: .main
            ) { [unowned self] _ in
                MainActor.assumeIsolated {
                    self.onTraitCollectionChange?()
                }
            }
        }

        let notifications = [
            UIApplication.willEnterForegroundNotification,
            UIApplication.didBecomeActiveNotification,
            UIApplication.willResignActiveNotification,
            UIApplication.didEnterBackgroundNotification,
        ]
        for notification in notifications {
            NotificationCenter.default.addObserver(
                forName: notification,
                object: nil,
                queue: .main
            ) { _ in
                action()
            }
        }
    }

    public func computeWindowEnvironment(
        window: Window,
        rootEnvironment: EnvironmentValues
    ) -> EnvironmentValues {
        // `windowScaleFactor` is the window's display scale. Left at the
        // environment default of 1, every iOS device would report 1 while
        // AppKitBackend supplies `backingScaleFactor`, WinUIBackend derives it
        // from the DPI and AndroidBackend from the display metrics. P42 checks
        // it: "current: 1.0" on an iPhone 16 simulator, whose display scale is
        // 3, is the failure. `Image` re-renders on this value, so a wrong
        // answer produces art rendered for the wrong scale rather than an error.
        //
        // `traitCollection.displayScale` and not `screen.scale`: the trait is
        // what the view hierarchy is actually laid out and drawn against, and
        // it is the value that changes under Display Zoom. `UIScreen.scale`
        // reports the physical panel and does not follow it.
        //
        // `windowScaleFactor` 是視窗的顯示縮放。若停在環境預設值 1，每一台 iOS 裝置都會回報 1，
        // 而 AppKitBackend 提供 `backingScaleFactor`、WinUIBackend 由 DPI 推導、AndroidBackend 由
        // display metrics 取得。P42 會檢查它：在顯示縮放為 3 的 iPhone 16 模擬器上顯示「current: 1.0」
        // 就是失敗。`Image` 會依這個值重新算繪，因此錯誤的答案產生的是「以錯誤縮放算繪的圖像」，
        // 而不是一個錯誤。
        //
        // 使用 `traitCollection.displayScale` 而非 `screen.scale`：trait 才是 view 階層實際據以
        // 排版與繪製的值，也是會隨 Display Zoom 改變的那一個。`UIScreen.scale` 回報的是實體面板，
        // 不會跟著改變。
        let scale = window.traitCollection.displayScale
        return rootEnvironment
            .with(\.windowScaleFactor, scale > 0 ? Double(scale) : 1)
            .with(\.scenePhase, window.isKeyWindow ? .active : .inactive)
    }

    public func setWindowEnvironmentChangeHandler(
        of window: Window,
        to action: @escaping @Sendable @MainActor () -> Void
    ) {
        Self.onWindowEnvironmentChange = action

        // The value is recomputed when the display scale changes, not only read
        // once: a window whose display scale changed under it would otherwise
        // keep whatever it started with. P42 tests exactly that -- the current
        // value alone cannot be the test, because a window showing 2.0 tells
        // you nothing about whether it would still say 2.0 after a change.
        //
        // `registerForTraitChanges` is iOS 17, and this package deploys to
        // iOS 13, so the older path observes the screen instead. Neither is a
        // guess: `UITraitDisplayScale` is the trait the value is read from, and
        // `UIScreen.modeDidChangeNotification` is what fires when the display
        // the window is on changes mode.
        //
        // 顯示縮放改變時會重新計算該值，而不只是讀一次：否則一個「顯示縮放在其底下改變了」的視窗，
        // 會一直保留它最初取得的值。P42 測的正是這件事——單憑當前值無法作為測試，
        // 因為一個顯示著 2.0 的視窗，並不能告訴你它在一次改變之後是否仍會顯示 2.0。
        //
        // `registerForTraitChanges` 需要 iOS 17，而本套件的部署目標是 iOS 13，因此較舊的路徑改為
        // 觀察螢幕。兩者都不是猜的：`UITraitDisplayScale` 正是該值所讀取的 trait，而
        // `UIScreen.modeDidChangeNotification` 正是「視窗所在的顯示器改變模式時」會發出的通知。
        if #available(iOS 17.0, tvOS 17.0, visionOS 1.0, *) {
            // The registration is retained on the window, because a token
            // dropped on the floor unregisters and the handler stops firing --
            // which would look exactly like the notification not existing,
            // which is the bug this replaces.
            // 該註冊由 window 保留，因為被丟棄的 token 會解除註冊、handler 也就不再觸發——而那看
            // 起來會與「通知根本不存在」一模一樣，也就是這段程式碼所要取代的那個 bug。
            let registration = window.registerForTraitChanges(
                [UITraitDisplayScale.self]
            ) { (_: UIWindow, _: UITraitCollection) in
                Self.onWindowEnvironmentChange?()
            }
            objc_setAssociatedObject(
                window,
                &Self.traitRegistrationKey,
                registration,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        } else {
            Self.screenModeObserver = NotificationCenter.default.addObserver(
                forName: UIScreen.modeDidChangeNotification,
                object: nil,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated { Self.onWindowEnvironmentChange?() }
            }
        }
    }

    private nonisolated(unsafe) static var traitRegistrationKey: UInt8 = 0
    private nonisolated(unsafe) static var screenModeObserver: NSObjectProtocol?

    public func runInMainThread(action: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async(execute: action)
    }

    public func show(widget: Widget) {
    }

    public func openExternalURL(_ url: URL) throws {
        UIApplication.shared.open(url)
    }

}

extension App {
    public typealias Backend = UIKitBackend

    public var backend: UIKitBackend {
        UIKitBackend()
    }
}

/// The root class for application delegates of SwiftCrossUI apps.
///
/// In order to use a custom application delegate, pass your class to ``UIKitBackend/init(appDelegateClass:)``:
///
/// ```swift
/// import SwiftCrossUI
/// import UIKitBackend
///
/// class MyAppDelegate: ApplicationDelegate {
///     // UIApplicationDelegate methods here
/// }
///
/// @main
/// struct SwiftCrossUI_TestApp: App {
///     var backend: UIKitBackend {
///         UIKitBackend(appDelegateClass: MyAppDelegate.self)
///     }
///
///     var body: some Scene {
///         WindowGroup {
///             // View code here
///         }
///     }
/// }
/// ```
open class ApplicationDelegate: UIResponder, UIApplicationDelegate {
    public var window: UIWindow? {
        get {
            UIKitBackend.mainWindow
        }
        set {
            UIKitBackend.mainWindow = newValue
        }
    }

    var menu: [ResolvedMenu.Submenu] = []
    var environment: EnvironmentValues?

    // MARK: Keyboard shortcuts without a menu bar (#121 on iPhone)

    /// The shortcuts, as key commands, for a device that never builds a main
    /// menu.
    ///
    /// **`buildMenu(with:)` is never called with `.main` on iPhone**, because
    /// there is no menu bar to build -- measured 2026-09-16 on an iPhone 17 Pro
    /// Max and recorded in `actions/ios/P71-shortcuts.actions`. Every `UIKeyCommand`
    /// this backend made lived inside that call, so on iPhone `.commands` and
    /// every shortcut in it did nothing at all, while the same binary worked on
    /// an iPad.
    ///
    /// **That is not "the platform has no API for this".** `UIResponder`
    /// publishes `keyCommands` along the responder chain and a hardware keyboard
    /// on an iPhone dispatches through it, with no menu involved. This is that
    /// route.
    ///
    /// 一個永遠不會建出主選單的裝置,它的那些快捷鍵——以 key command 的形式。
    ///
    /// **在 iPhone 上,`buildMenu(with:)` 從不以 `.main` 被呼叫**,因為那裡沒有選單列可建
    /// ——2026-09-16 在 iPhone 17 Pro Max 上量過,記於 `actions/ios/P71-shortcuts.actions`。
    /// 這個 backend 所造出的每一個 `UIKeyCommand` 都住在那次呼叫之內,因此在 iPhone 上,`.commands`
    /// 與其中的每一個快捷鍵**完全沒有作用**,而同一個二進位檔在 iPad 上卻能用。
    ///
    /// **那不是「這個平台沒有對應的 API」。** `UIResponder` 會沿著 responder chain 公布
    /// `keyCommands`,而 iPhone 上的實體鍵盤正是經由它派送的,完全不牽涉選單。這就是那條路。
    var fallbackKeyCommands: [UIKeyCommand] = []

    /// The menus as the framework laid them out; `buildMenu(with:)` and the phone's menu
    /// button are made from it. 框架排出的選單版面;`buildMenu(with:)` 與手機上的選單按鈕都由它產生。
    var commandLayout: CommandLayout?

    /// Whether the menu system has built a main menu in this process.
    ///
    /// **The published commands are withheld once it has**, or an iPad would
    /// carry each shortcut twice -- once from the menu and once from here -- and
    /// a `UIKeyCommand` that appears twice in the chain runs its action twice.
    /// For a "delete" command that is not a cosmetic difference.
    ///
    /// Read at key-press time rather than when the menu is set, because the
    /// order is the other way round: `setApplicationMenu` asks for a rebuild and
    /// `buildMenu` follows, so at the moment the commands are made nothing knows
    /// yet whether a menu bar exists.
    ///
    /// 在這個行程中,選單系統是否曾建出一個主選單。
    ///
    /// **一旦建過,就不再公布那些 command**,否則 iPad 會把每一個快捷鍵帶兩份——一份來自選單、
    /// 一份來自這裡——而一個在 chain 中出現兩次的 `UIKeyCommand` 會把它的動作執行兩次。
    /// 對一個「刪除」命令來說,那不是外觀上的差別。
    ///
    /// 在**按鍵發生時**讀取,而不是在選單被設定時讀取,因為順序恰好相反:`setApplicationMenu` 先要求
    /// 一次重建、`buildMenu` 隨後才來,因此在那些 command 被造出來的當下,還沒有任何東西知道是否
    /// 存在一條選單列。
    var hasBuiltMainMenu = false

    open override var keyCommands: [UIKeyCommand]? {
        // Command-[ for Back is not a menu item, so it is published whether or
        // not a main menu exists; see UIKitBackend+BackNavigation.swift.
        // 返回用的 Command-[ 不是選單項目，因此不論是否有主選單都公布；見 UIKitBackend+BackNavigation.swift。
        let commands = (hasBuiltMainMenu ? [] : fallbackKeyCommands) + backNavigationKeyCommands
        return commands.isEmpty ? nil : commands
    }

    public required override init() {
        super.init()
    }

    /// Tells the delegate that the app has become active.
    ///
    /// - Important: If you override this method in a subclass, you must call
    /// `super.applicationDidBecomeActive(application)` as the first step of your
    /// implementation.
    /// Every scene is driven by `SceneDelegate`.
    ///
    /// Required, not optional: an app linked against the iOS 27 SDK that does
    /// not adopt the scene life cycle is refused at launch -- measured
    /// 2026-09-30, UIKit logged "Application failed to launch: UIScene life
    /// cycle" and the app went straight to the home screen. The test apps only
    /// ran because their binaries claimed SDK 15, which also made iOS run them
    /// zoomed at 428x926 on a 440x956 screen.
    ///
    /// 每個 scene 都由 `SceneDelegate` 驅動。這是必要的而非可選的:以 iOS 27 SDK 連結、卻未採用
    /// scene 生命週期的 app 會在啟動時被拒——2026-09-30 實測,UIKit 記下「Application failed to
    /// launch: UIScene life cycle」,app 直接回到主畫面。測試 app 之所以能跑,只是因為它們的執行檔宣稱
    /// SDK 15,而那也讓 iOS 在 440x956 的螢幕上以 428x926 放大執行它們。
    open func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: "Default",
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    open func applicationDidBecomeActive(_ application: UIApplication) {
        UIKitBackend.onBecomeActive?()

        // We only want to notify the first time. Otherwise the app's scene
        // graph gets regenerated every time the app gets foregrounded,
        // causing very strange results.
        UIKitBackend.onBecomeActive = nil
    }

    /// Tells the delegate that the launch process is almost done and the app is almost ready
    /// to run.
    ///
    /// If you override this method in a subclass, you should call
    /// `super.application(application, didFinishLaunchingWithOptions: launchOptions)`
    /// at some point in your implementation. You do not necessarily have to return the same
    /// value as this `super` call.
    open func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        if let onReceiveURL = UIKitBackend.onReceiveURL,
           let url = launchOptions?[.url] as? URL
        {
            onReceiveURL(url)
        }

        return true
    }

    /// Asks the delegate to open a resource specified by a URL, and provides a dictionary of launch options.
    ///
    /// If you override this method in a subclass, you should call
    /// `super.application(app, open: url, options: options` at some point in your
    /// implementation. You do not necessarily have to return the same value as this `super`
    /// call.
    open func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        if let onReceiveURL = UIKitBackend.onReceiveURL {
            onReceiveURL(url)
        }

        return true
    }

    /// Map a menu's label to its identifier.
    ///
    /// The commands API only gives control over the label of each menu. Override this method if
    /// you also need to control the menus' identifiers.
    ///
    /// This method is only used on Mac Catalyst.
    open func mapMenuIdentifier(_ label: String) -> UIMenu.Identifier {
        switch label {
            case "File": .file
            case "Edit": .edit
            case "View": .view
            case "Window": .window
            case "Help": .help
            default:
                if let bundleId = Bundle.main.bundleIdentifier {
                    .init(rawValue: "\(bundleId).\(label)")
                } else {
                    .init(rawValue: label)
                }
        }
    }

    /// Asks the receiving responder to add and remove items from a menu system.
    ///
    /// When targeting Mac Catalyst, you should call `super.buildMenu(with: builder)` at some
    /// point in your implementation. If you do not, then calls to
    /// ``SwiftCrossUI/Scene/commands(_:)`` will have no effect.
    open override func buildMenu(with builder: any UIMenuBuilder) {
        guard
            #available(tvOS 14, *),
            builder.system == .main
        else {
            return
        }

        // A fresh generation of shortcut tokens for this rebuild. See
        // `MenuShortcutActions`: a table that only grew would keep every
        // closure from every rebuild, including ones capturing view state that
        // has since been replaced.
        // 為這次重建開始新一代的快捷鍵 token。見 `MenuShortcutActions`:一張只增不減的表,會保留
        // **每一次**重建的每一個 closure,包括那些捕捉了「後來已被替換的 view 狀態」的。
        MenuShortcutActions.beginRebuild()
        // Recorded here, at the one place that proves a menu bar exists. See
        // `hasBuiltMainMenu`.
        // 在此記下,而這裡是唯一能證明「存在一條選單列」的地方。見 `hasBuiltMainMenu`。
        hasBuiltMainMenu = true

        buildCommandMenus(with: builder)
    }
}

/// The root class for scene delegates of SwiftCrossUI apps.
///
/// SwiftCrossUI apps do not have to be scene-based. If you are writing a scene-based app,
/// derive your scene delegate from this class.
open class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    public var window: UIWindow?

    /// Tells the delegate about the addition of a scene to the app.
    ///
    /// The first scene gets the app's main window and starts the app. A later
    /// scene was requested by `show(window:)` for a window SwiftCrossUI had
    /// already created -- a second `WindowGroup` window, or `openWindow` -- and
    /// takes that window rather than making a new one. That is how a
    /// SwiftCrossUI window becomes an iPad window; a sceneless `UIWindow()` is
    /// never drawn.
    ///
    /// 第一個 scene 取得 app 的主視窗並啟動 app。之後的 scene 是 `show(window:)` 為 SwiftCrossUI
    /// 已經建立的視窗所請求的——第二個 `WindowGroup` 視窗,或 `openWindow`——它接手那個視窗,而不是
    /// 另建一個。SwiftCrossUI 的視窗就是這樣成為 iPad 視窗的；沒有 scene 的 `UIWindow()` 永遠不會被繪製。
    ///
    /// - Important: If you override this method in a subclass, you must call
    /// `super.scene(scene, willConnectTo: session, options: connectionOptions)`
    /// at some point in your implementation.
    open func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        if let pending = UIKitBackend.pendingSceneWindows.first {
            UIKitBackend.pendingSceneWindows.removeFirst()
            pending.windowScene = windowScene
            self.window = pending
            pending.makeKeyAndVisible()
            return
        }

        let window = UIKitBackend.mainWindow ?? UIWindow(windowScene: windowScene)
        window.windowScene = windowScene
        self.window = window
        UIKitBackend.mainWindow = window

        UIKitBackend.onBecomeActive?()

        // We only want to notify the first time. Otherwise the app's scene
        // graph gets regenerated every time the app gets foregrounded,
        // causing very strange results.
        UIKitBackend.onBecomeActive = nil

        if let onReceiveURL = UIKitBackend.onReceiveURL,
           let url = connectionOptions.userActivities.first?.webpageURL
        {
            onReceiveURL(url)
        }
    }

    open func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        if let onReceiveURL = UIKitBackend.onReceiveURL,
           let url = userActivity.webpageURL
        {
            onReceiveURL(url)
        }
    }

    open func sceneDidBecomeActive(_ scene: UIScene) {
        UIKitBackend.onWindowEnvironmentChange?()
    }

    open func sceneWillResignActive(_ scene: UIScene) {
        UIKitBackend.onWindowEnvironmentChange?()
    }

    open func sceneWillEnterForeground(_ scene: UIScene) {
        UIKitBackend.onWindowEnvironmentChange?()
    }

    open func sceneDidEnterBackground(_ scene: UIScene) {
        UIKitBackend.onWindowEnvironmentChange?()
    }
}
