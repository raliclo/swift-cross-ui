import Android
import DebugFeatures
import Foundation
import InputEvent
@_spi(Backends) import SwiftCrossUI
import AndroidKit
import AndroidGraphics
import AndroidBackendShim
import Mutex
import DequeModule

// Many force tries are required for the Android backend but we don't really want them
// anywhere else so just disable the lint rule at a file level.
// swiftlint:disable force_try

func log(_ message: String) {
    android_log(Int32(ANDROID_LOG_DEBUG.rawValue), "swift", message)
}

/// A valid AndroidBackend shim must call this to begin execution of the app.
/// Once initial setup and rendering is done, this function returns control
/// back to the JVM (by returning).
@MainActor
@_cdecl("AndroidBackend_entrypoint")
public func entrypoint(_ env: UnsafeMutablePointer<JNIEnv?>, _ object: jobject) {
    AndroidBackend.env = env

    let holder = JavaObjectHolder(object: object, environment: env)
    AndroidBackend.activity = Activity(javaHolder: holder)
    // Every MainActivity.onCreate lands here and runs the app again, so its
    // first window belongs in THIS activity. The flag is a static and outlived
    // the previous run: when the system recreated the activity -- a theme
    // overlay applied shortly after boot does, and configChanges cannot cover
    // an assets change -- the rerun's main window took a token, opened as a
    // ScuiWindowActivity beside a blank MainActivity, and P83 showed an empty
    // screen (API 36 emulator, 2026-10-09; reproduced by toggling
    // `cmd overlay enable com.android.internal.display.cutout.emulation.corner`).
    // 每次 MainActivity.onCreate 都會來到這裡、重新執行 app,所以它的第一個視窗屬於**這個** activity。
    // 這個旗標是 static,活過了上一次執行：系統重建 activity 時(開機後不久套用主題覆蓋層就會，而 configChanges
    // 涵蓋不了 assets 變更),重跑的主視窗拿到 token,變成空白 MainActivity 旁的 ScuiWindowActivity,P83 一片空白。
    AndroidBackend.didCreateMainWindow = false

    // Source: https://phatbl.at/2019/01/08/intercepting-stdout-in-swift.html
    func makeMessageHandler(priority: UInt32) -> @Sendable (FileHandle) -> Void {
        @Sendable
        nonisolated func forward(_ fileHandle: FileHandle) {
            let data = fileHandle.availableData
            guard let string = String(data: data, encoding: .utf8) else {
                return
            }

            android_log(
                Int32(priority),
                "Swift",
                string
            )
        }
        return forward
    }

    AndroidBackend.stdoutPipe.fileHandleForReading.readabilityHandler =
        makeMessageHandler(priority: ANDROID_LOG_INFO.rawValue)

    AndroidBackend.stderrPipe.fileHandleForReading.readabilityHandler =
        makeMessageHandler(priority: ANDROID_LOG_ERROR.rawValue)

    dup2(
        AndroidBackend.stdoutPipe.fileHandleForWriting.fileDescriptor,
        FileHandle.standardOutput.fileDescriptor
    )

    dup2(
        AndroidBackend.stderrPipe.fileHandleForWriting.fileDescriptor,
        FileHandle.standardError.fileDescriptor
    )

    // Line buffering, or `print` reaches logcat only in 4 KB instalments.
    //
    // C stdio picks its buffering from what the descriptor is: a terminal gets
    // line buffering, anything else gets a full 4 KB buffer. The `dup2` above
    // makes stdout a pipe, so from that call onwards `print` writes into a
    // buffer that is flushed when it fills, when the process exits, or never --
    // and an app killed with `am force-stop`, which is how every test here
    // ends, never flushes.
    //
    // stderr is unbuffered by the C standard and needs nothing, which is why
    // `InputEvent`'s `-actionfile:` lines have always appeared while the test
    // apps' own `print` output has not. That asymmetry was recorded as "an
    // Android app's print does not reach logcat" and taken as a platform
    // limitation; it is four lines of buffering.
    //
    // 設為行緩衝，否則 `print` 只會以 4 KB 為單位分批抵達 logcat。
    //
    // C stdio 是依「該描述子是什麼」來決定緩衝方式的：終端機得到行緩衝，其他一切得到完整的 4 KB
    // 緩衝區。上方的 `dup2` 使 stdout 成為一條 pipe，因此自該次呼叫起，`print` 寫入的是一個
    // 「緩衝區滿了才沖、行程結束才沖，或者永遠不沖」的緩衝區——而一個以 `am force-stop` 終結的
    // app（此處每一次測試都是這樣結束的）永遠不會沖。
    //
    // stderr 依 C 標準是無緩衝的，不需要任何處理——這正是為什麼 `InputEvent` 的 `-actionfile:`
    // 各行一直都看得到，而測試 app 自身的 `print` 輸出卻看不到。那個不對稱曾被記錄為「Android app
    // 的 print 到不了 logcat」並當成平台限制；它其實是四行緩衝設定。
    // Both calls moved into `AndroidBackendShim`. `stdout` and `stderr` are
    // mutable C globals and Swift 6 refuses to reference one; the reasoning,
    // and what these two lines are actually for, is in `impl.c` beside them.
    // 這兩個呼叫已移入 `AndroidBackendShim`。`stdout` 與 `stderr` 是可變的 C 全域變數,而 Swift 6
    // 拒絕引用其中任何一個;推理與「這兩行究竟在做什麼」寫在它們旁邊的 `impl.c` 裡。
    android_configure_stdio()

    // Arguments from the launching intent rather than none at all.
    //
    // This was `main(0, argv)` with `argv[0] = nil`, described as "dummy
    // arguments". The cost was not obvious from here: everything downstream
    // reads `CommandLine.arguments`, so `--debug` was never seen on Android,
    // `DebugFeatures.isEnabled` was always false, and `-actionfile` could not
    // arrive -- while `test_android.zsh` accepted the flag and dropped it. See
    // `AndroidBackend+Arguments.swift`.
    //
    // 引數取自啟動它的 intent，而非完全沒有引數。
    //
    // 此處原本是 `main(0, argv)`、`argv[0] = nil`，並註解為「dummy arguments」。其代價從這裡看不
    // 出來：下游的一切都讀取 `CommandLine.arguments`，因此在 Android 上 `--debug` 從未被看見、
    // `DebugFeatures.isEnabled` 恆為 false，而 `-actionfile` 根本無法送達——同時
    // `test_android.zsh` 卻接受了該旗標並把它丟掉。詳見 `AndroidBackend+Arguments.swift`。
    // Registered before `main`, so a replay scheduled by the first window has a
    // synthesiser to find. See `AndroidSynthesiser`.
    // 在 `main` 之前註冊，使「由第一個視窗排定的重放」找得到 synthesiser。詳見 `AndroidSynthesiser`。
    SynthesiserRegistry.register { layoutScale in
        AndroidSynthesiser(layoutScale: layoutScale)
    }

    let arguments = AndroidLaunchArguments.read(from: AndroidBackend.activity)
    AndroidLaunchArguments.withArgv(arguments) { argc, argv in
        main(argc, argv)
    }
}

extension App {
    public typealias Backend = AndroidBackend

    public var backend: AndroidBackend {
        AndroidBackend()
    }
}

/// These two are written out rather than declared with `@Entry`, and the public
/// surface is identical either way.
///
/// **`@Entry` emits `static let defaultValue`, and under Swift 6 an immutable
/// global of a NON-SENDABLE type is still an error** -- `Activity` is a Java
/// object handle and `UnsafeMutablePointer<JNIEnv?>` is a pointer, so neither
/// can be `Sendable`. Teaching the macro to add `nonisolated(unsafe)` was the
/// obvious move and is the wrong one: it would silence the same diagnostic for
/// every entry in the package, including the ones where it is reporting a real
/// problem. The exception belongs where the exception is.
///
/// **Why the assertion is true here.** Both are set once, from
/// `AndroidBackend`'s own start-up on the Android main thread, before any view
/// exists to read them, and never written again. The JNI environment pointer is
/// thread-local by JNI's own rules, which is why nothing else may pick it up
/// and carry it elsewhere -- that restriction predates this annotation and is
/// not created by it.
///
/// 這兩個是手寫的、而不是用 `@Entry` 宣告的;兩種寫法的公開介面完全相同。
///
/// **`@Entry` 產生的是 `static let defaultValue`,而在 Swift 6 底下,一個「非 Sendable 型別」的
/// 不可變全域仍然是錯誤**——`Activity` 是一個 Java 物件 handle,`UnsafeMutablePointer<JNIEnv?>` 是
/// 一個指標,兩者都不可能是 `Sendable`。「教那個 macro 加上 `nonisolated(unsafe)`」是最直覺的做法,
/// 而它是錯的:那會讓整個套件裡**每一個** entry 的同一個診斷都被消音,包括那些它確實在回報真問題的
/// 地方。例外應該待在例外所在之處。
///
/// **為何這個斷言在此處為真。** 兩者都只被設定一次,由 `AndroidBackend` 自己的啟動流程在 Android
/// 主執行緒上設定,時點早於任何 view 存在而能讀它們,之後不再被寫入。那個 JNI environment 指標依
/// JNI 自身的規則就是 thread-local 的,這正是「別的東西不得撿走它並帶到他處」的原因——那個限制早於
/// 這個標註存在,不是它造成的。
private struct __Key_androidActivity: EnvironmentKey {
    // `Value` written out rather than inferred: an implicitly-unwrapped
    // `Activity!` is `Optional<Activity>` wearing different sugar, and the
    // inference through it does not reach the associated type.
    // `Value` 明寫而非交由推論:一個隱式解包的 `Activity!` 只是 `Optional<Activity>` 換了一層語法糖,
    // 而穿過它的推論到不了那個 associated type。
    typealias Value = AndroidKit.Activity?
    nonisolated(unsafe) static let defaultValue: AndroidKit.Activity? = nil
}

private struct __Key_jniEnv: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: UnsafeMutablePointer<JNIEnv?>? = nil
}

extension EnvironmentValues {
    public var androidActivity: AndroidKit.Activity! {
        get { self[__Key_androidActivity.self] }
        set { self[__Key_androidActivity.self] = newValue }
    }

    public var jniEnv: UnsafeMutablePointer<JNIEnv?>? {
        get { self[__Key_jniEnv.self] }
        set { self[__Key_jniEnv.self] = newValue }
    }
}

public final class AndroidBackend: BaseAppBackend {
    /// One SwiftCrossUI window. The first is the activity the app started in;
    /// each later one has a `token` and becomes a `ScuiWindowActivity` of its
    /// own when shown (Kotlin/ScuiWindowActivity.kt).
    /// 一個 SwiftCrossUI 視窗。第一個是 app 啟動時的 activity;之後的每一個都有 `token`,顯示時成為自己的
    /// `ScuiWindowActivity`(Kotlin/ScuiWindowActivity.kt)。
    public final class Window {
        var content: Widget?
        /// `nil` for the first window. 第一個視窗為 `nil`。
        let token: String?
        /// The stack `setChild` built: toolbar rows go here. `setChild` 建的 stack:工具列在這裡。
        var rootStack: AndroidKit.LinearLayout?
        var title = ""
        var closeHandler: (() -> Void)?
        var resizeHandler: ((SIMD2<Int>) -> Void)?
        var environmentChangeHandler: (@MainActor () -> Void)?
        var isOpen = false
        /// What a later window's activity takes as its content. 之後的視窗的 activity 所採用的內容。
        var contentRoot: AndroidKit.View?
        /// The size the app asked for (`.defaultSize`), and the root scroll host
        /// whose mode decides whether it is used -- see `size(ofWindow:)`.
        /// App 要求的尺寸(`.defaultSize`),以及其模式決定是否採用它的 root scroll host——見 `size(ofWindow:)`。
        var defaultSize: SIMD2<Int>?
        var scrollHost: RootScrollHost?

        init(token: String?) {
            self.token = token
        }
    }

    public typealias Widget = AndroidKit.View

    /// The frame clock's handler and the generation that stops it.
    /// frame clock 的 handler，以及那個用來讓它停下來的世代號。
    @MainActor static var currentFrameClockHandler: (@MainActor (Double) -> Void)?
    @MainActor static var frameClockCallback: FrameClockCallback?

    /// One id per adapter, so a list that updates keeps the id it already has
    /// and the provider is replaced rather than accumulated.
    /// 一個 adapter 一個 id——好讓一份更新中的清單沿用它已有的 id，而那個 provider 是被**取代**、
    /// 不是被累積。
    @MainActor static var lazyListIDs: [ObjectIdentifier: Int32] = [:]

    static let stdoutPipe = Pipe()
    static let stderrPipe = Pipe()

    // A placeholder, like `deviceClass` below, and it has to agree with that
    // one: the real list is chosen in `computeRootEnvironment`, and until then
    // this is what a caller sees. `deviceClass` places itself at `.phone`, so
    // this holds the phone list -- and it did not, which is why declaring
    // `.graphical` for phones in `computeRootEnvironment` was not enough on its
    // own. P41 still died on `DatePickerStyleModifier`'s assertion, from a read
    // that happened while this value was still the placeholder.
    //
    // 一個佔位值，與下方的 `deviceClass` 相同，而且必須與它一致：真正的清單是在
    // `computeRootEnvironment` 中選定的，在那之前呼叫端看到的就是這個值。`deviceClass` 把自己置於
    // `.phone`，因此此處持有的是 phone 的清單——而它原本並非如此，這正是為何「只在
    // `computeRootEnvironment` 中為 phone 宣告 `.graphical`」還不夠。P41 依然死在
    // `DatePickerStyleModifier` 的 assert 上，而那次讀取發生在本值仍是佔位值的時候。
    // Computed in `init()` rather than left constant: `.floating` needs an
    // overlay permission the user grants in Settings, and a list that claimed
    // it on a device where they said no would be a promise this backend cannot
    // keep. `EnvironmentValues` captures the list once and before
    // `computeRootEnvironment`, which is why `init()` and not there.
    //
    // 在 `init()` 中計算，而非保持為常數：`.floating` 需要一項由使用者在「設定」中授予的 overlay
    // 權限，而在使用者拒絕的裝置上仍宣稱擁有它的清單，會是這個 backend 兌現不了的承諾。
    // `EnvironmentValues` 只擷取該清單一次，且早於 `computeRootEnvironment`，這正是它放在 `init()`
    // 而不放在那裡的原因。
    let _supportedWindowLevels = Mutex<[WindowLevel]>([.automatic, .normal])

    private let _supportedDatePickerStyles = Mutex<[BackendDatePickerStyle]>(
        [.automatic, .compact, .graphical, .wheel]
    )

    public nonisolated var supportedDatePickerStyles: [BackendDatePickerStyle] {
        _supportedDatePickerStyles.withLock { copy $0 }
    }

    // .phone is a placeholder value -- the real value is set in `computeRootEnvironment`.
    public private(set) var deviceClass = DeviceClass.phone

    public let defaultPaddingAmount = 10
    // True since 2026-10-06: a window after the first is an activity of its
    // own (ScuiWindowActivity.kt) -- a separate task in Recents on a phone, beside
    // the first in split screen on a tablet.
    // 自 2026-10-06 起為 true:第一個之後的視窗是自己的 activity(ScuiWindowActivity.kt)——在手機上是「最近使用」
    // 中的獨立工作，在平板上可在分割畫面中並排。
    public let supportsMultipleWindows = true
    // True since 2026-09-03, and the false it replaced was not a statement about
    // Android. `WindowReference` reads this flag before it does anything: false
    // makes it discard `preferredColorScheme` entirely, so `.colorScheme(.dark)`
    // was accepted by the API, recorded by the app and then dropped upstream of
    // every line of this backend. P15 showed the shape exactly -- its status
    // line read "Requested: dark   Resolved: light".
    //
    // Nothing here was missing. `resolveAdaptiveColor` has always switched on
    // `environment.colorScheme` (AndroidBackend+Colors.swift) and so have the
    // sheets; they were being handed an environment that had already had the
    // request taken out of it. What this needed was the flag and a window
    // background to go with it -- see `updateWindow`.
    //
    // 自 2026-09-03 起為 true，而它所取代的 false 並不是對 Android 的陳述。`WindowReference` 會在
    // 做任何事之前先讀這個旗標：false 會讓它把 `preferredColorScheme` 整個丟棄，於是
    // `.colorScheme(.dark)` 被 API 接受了、被 app 記錄了，然後在抵達本 backend 的任何一行程式碼
    // 之前就被丟掉。P15 精確地呈現了這個形狀——它的狀態列寫著
    // 「Requested: dark   Resolved: light」。
    //
    // 此處沒有任何東西是缺的。`resolveAdaptiveColor` 一直都會對 `environment.colorScheme` 做
    // switch（AndroidBackend+Colors.swift），sheet 也是；它們只是被交付了一個「請求已被拿掉」的
    // environment。真正需要補的是這個旗標，以及與之相配的視窗背景——見 `updateWindow`。
    public let canOverrideWindowColorScheme = true
    public let restoresWindowFrames = false

    static var fileDialogCallback: (([Foundation.URL]) -> Void)?
    static var folderDialogCallback: ((Foundation.URL?) -> Void)?
    /// The content:// URI the save dialog created, or nil when it was cancelled.
    static var saveDialogCallback: ((String?) -> Void)?
    /// The one window's close handler; see `close(window:)`.
    static var closeHandler: (() -> Void)?
    /// Whether the first window -- the launch activity's -- has been created.
    /// 第一個視窗(啟動 activity 的那個)是否已建立。
    nonisolated(unsafe) static var didCreateMainWindow = false

    /// A reference used to keep the tickler alive.
    var tickler: MainRunLoopTickler?

    /// The JNI environment pointer. Set by ``entrypoint``.
    static var env: UnsafeMutablePointer<JNIEnv?>!
    /// The main activity. Set by ``entrypoint``.
    static var activity: Activity!

    /// The vertical LinearLayout that is the window's content view.
    ///
    /// `setChild(ofWindow:to:)` builds it; `setToolbar(ofWindow:to:)` is the
    /// only other thing that touches it. Held here rather than on `Window`
    /// because it is the Activity's content view and there is one Activity.
    ///
    /// 那個作為視窗 content view 的垂直 LinearLayout。
    ///
    /// 由 `setChild(ofWindow:to:)` 建立;唯一另一個會碰它的是 `setToolbar(ofWindow:to:)`。放在此處
    /// 而非 `Window` 上,因為它是該 Activity 的 content view,而 Activity 只有一個。
    nonisolated(unsafe) static var rootStack: AndroidKit.LinearLayout?

    /// The same view as ``rootStack``, kept at its own type so `setApplicationMenu` can hand it
    /// the shortcut table without casting back.
    /// 與 ``rootStack`` 是同一個 view,以它自己的型別另存一份,好讓 `setApplicationMenu` 不必再轉型
    /// 就能把快捷鍵表交給它。
    nonisolated(unsafe) static var shortcutHost: ShortcutHostLayout?

    /// The app-menu shortcut listener, kept so the content view can be given it whichever order
    /// the two arrive in.
    ///
    /// `setApplicationMenu` and the window's content view are created by different passes and
    /// neither is reliably first: on the opening pass the menu is set before there is a content
    /// view, and on a later rebuild the content view is already there. Storing it means both
    /// orders end with the same thing attached, instead of one of them silently ending with none.
    ///
    /// app 選單的快捷鍵 listener,存起來,好讓 content view 不論兩者以哪個順序抵達都能拿到它。
    ///
    /// `setApplicationMenu` 與視窗的 content view 是由不同的階段建立的,而兩者都不保證先到:
    /// 開場那一輪是「選單先設、還沒有 content view」,而之後的重建則是 content view 已經在了。
    /// 存起來,兩種順序就都以「同一個東西被掛上」收尾,而不是其中一種靜默地什麼都沒掛。
    nonisolated(unsafe) static var applicationShortcutListener: SwiftUnhandledKeyListener?

    /// The toolbar row, once one has been asked for. `nil` means no row is in
    /// the stack at all, which is not the same as a row that is empty -- an
    /// empty row still takes its height from the content.
    ///
    /// 工具列那一列,在有人要求之後才存在。`nil` 代表堆疊中根本沒有這一列,那與「一列空的」不同——
    /// 一列空的仍會從內容那裡佔走它的高度。
    nonisolated(unsafe) static var toolbar: AndroidKit.LinearLayout?

    var helpers: AndroidBackendHelpers

    static let maxLocaleCacheSize = 25
    var localeCache = Deque<(Foundation.Locale, AndroidKit.Locale)>()

    public init() {
        helpers = AndroidBackendHelpers(environment: Self.env)

        // Before anything reads `supportedDatePickerStyles`. See the note on
        // `resolveDeviceClass`.
        // 在任何東西讀取 `supportedDatePickerStyles` 之前。見 `resolveDeviceClass` 的說明。
        resolveDeviceClass()

        _supportedWindowLevels.withLock { levels in
            levels =
                helpers.canFloat(Self.activity)
                    ? [.automatic, .normal, .floating]
                    : [.automatic, .normal]
        }

        let fragmentActivity = Self.activity.as(FragmentActivity.self)!

        let filesCallback = FilesActivityCallback(environment: Self.env)
        let filesAction = SwiftAction(environment: Self.env) {
            let urls = filesCallback.getUrlStrings()
            AndroidBackend.fileDialogCallback?(urls.map {
                guard let url = Foundation.URL(string: $0) else {
                    fatalError("Failed to convert Uri to Foundation.URL: \($0)")
                }
                return url
            })
            AndroidBackend.fileDialogCallback = nil
        }
        filesCallback.setAction(filesAction)

        let folderCallback = FolderActivityCallback(environment: Self.env)
        let folderAction = SwiftAction(environment: Self.env) {
            let url = folderCallback.getUrlString()?.toString()
            AndroidBackend.folderDialogCallback?(url.map {
                guard let url = Foundation.URL(string: $0) else {
                    fatalError("Failed to convert Uri to Foundation.URL: \($0)")
                }
                return url
            })
            AndroidBackend.folderDialogCallback = nil
        }
        folderCallback.setAction(folderAction)

        helpers.registerActivityResults(fragmentActivity, filesCallback, folderCallback)

        let saveCallback = FolderActivityCallback(environment: Self.env)
        let saveAction = SwiftAction(environment: Self.env) {
            let uri = saveCallback.getUrlString()?.toString()
            AndroidBackend.saveDialogCallback?(uri)
            AndroidBackend.saveDialogCallback = nil
        }
        saveCallback.setAction(saveAction)
        helpers.registerSaveResult(fragmentActivity, saveCallback)
    }

    public convenience init(delegate: any ActivityDelegate) {
        self.init()

        let delegateObject = SwiftObject(delegate, environment: Self.env)
        let castedActivity = Self.activity.as(FragmentActivity.self)!

        // ActivityListener.init connects it to the Activity, which keeps it alive without Swift
        // needing to keep any references to it.
        _ = ActivityListener(castedActivity, delegateObject, environment: Self.env)

        delegate.onCreate(of: castedActivity, env: Self.env)
    }

    public func runMainLoop(
        _ callback: @escaping @MainActor () -> Void
    ) {
        // Main-queue work runs when it is enqueued, not at the tickler's next
        // 50 ms tick -- see `android_attach_main_queue_to_looper` in
        // AndroidBackendShim. The tickler stays: Foundation `Timer`s on
        // RunLoop.main still need the run loop itself to be run.
        // 主佇列的工作在被排入時就執行，而不是等 tickler 下一次 50 ms 的 tick——見
        // AndroidBackendShim 的 `android_attach_main_queue_to_looper`。tickler 保留:RunLoop.main
        // 上的 Foundation `Timer` 仍需要 run loop 本身被執行。
        let attached = android_attach_main_queue_to_looper()
        if attached != 0 {
            logger.warning(
                "main dispatch queue not attached to the Looper; main-actor work waits for the 50 ms tick",
                metadata: ["status": "\(attached)"]
            )
        }

        let tickler = MainRunLoopTickler(environment: Self.env)
        tickler.start()
        self.tickler = tickler

        // We just fall through to return control to Java when we're done
        // setting up the initial view hierarchy.
        callback()
    }

    public func createWindow(withDefaultSize defaultSize: SIMD2<Int>?, id: String) -> Window {
        // The first window is the activity the app started in; every later one
        // gets a token and its own activity when shown. Until 2026-10-06 this
        // was upstream's TODO and every call returned the same placeholder.
        // 第一個視窗是 app 啟動時的 activity;之後每一個都拿到 token,顯示時有自己的 activity。2026-10-06
        // 之前這裡是上游的 TODO,每次呼叫都回傳同一個佔位物件。
        defer { Self.didCreateMainWindow = true }
        let window = Window(token: Self.didCreateMainWindow ? UUID().uuidString : nil)
        window.defaultSize = defaultSize
        return window
    }

    public func updateWindow(_ window: Window, environment: EnvironmentValues) {
        // The same hook AppKitBackend uses for `window.appearance` and
        // GtkBackend for its theme override: the one place a backend is handed
        // the environment for a window rather than for a widget. See
        // `canOverrideWindowColorScheme` above for why nothing reached here
        // before, and `setWindowBackground` in AndroidBackendHelpers.kt for
        // which colour and why it is not a literal.
        //
        // 與 AppKitBackend 用來設定 `window.appearance`、GtkBackend 用來覆寫主題的是同一個 hook：
        // 那是 backend 唯一一處拿到「某個視窗的」environment 而非「某個 widget 的」environment。
        // 為何此前沒有任何東西抵達這裡，見上方的 `canOverrideWindowColorScheme`；至於用哪個顏色、
        // 以及為何不用字面值，見 AndroidBackendHelpers.kt 的 `setWindowBackground`。
        if let activity = activity(of: window) {
            helpers.setWindowBackground(activity, environment.colorScheme == .dark)
            window.scrollHost?.setChromeDark(environment.colorScheme == .dark)
        }
        updateInsets(ofWindow: window)
    }

    public func setSizeLimits(
        ofWindow window: Window,
        minimum: SIMD2<Int>,
        maximum: SIMD2<Int>?
    ) {
        // Doesn't mean anything on Android until we support split screen
    }


    public func setTitle(ofWindow window: Window, to title: String) {
        // The window's title, not `.navigationTitle` (that is a row in the
        // root stack, AndroidBackend+Toolbar.swift). Upstream's TODO here said
        // "navigation titles"; what was missing was the activity title and the
        // Recents label, which an Android user sees for the window. 2026-10-06.
        // 視窗的標題，不是 `.navigationTitle`(那是 root stack 中的一列，見 AndroidBackend+Toolbar.swift)。
        // 上游在此的 TODO 寫的是「導覽標題」;實際缺的是 activity 標題與「最近使用」中的標籤——Android
        // 使用者看到視窗標題的地方。2026-10-06。
        window.title = title
        if let token = window.token {
            helpers.setTitleOfWindow(token, title)
        } else {
            helpers.setWindowTitle(Self.activity, title)
        }
    }

    public func setResizability(ofWindow window: Window, to resizable: Bool) {}

    public func setChild(ofWindow window: Window, to child: Widget) {
        let container = createContainer()
        insert(child, into: container, at: 0)

        // Hosted in a scroll view rather than set as the content view directly.
        // See `AndroidRootScrollHost` for what this is for and for the
        // measurement behind it.
        // 放進捲動視圖中，而不是直接設為 content view。此舉的用途與其背後的量測，見
        // `AndroidRootScrollHost`。
        //
        // `allowsRootScrollControl`, not `isEnabled`. `isEnabled` also requires
        // `--debug` on the command line, and it is the same distinction
        // UIKitBackend draws: this flag does not switch diagnostics on, it makes
        // an existing piece of interface visible, and a release build is exactly
        // where you cannot rebuild to see it.
        //
        // 使用 `allowsRootScrollControl` 而非 `isEnabled`。`isEnabled` 還要求命令列上有 `--debug`，
        // 而此處的區別與 UIKitBackend 所劃的是同一個：這個旗標並不開啟任何診斷功能，它只是讓一個既有的
        // 介面元件變為可見；而 release 建置恰恰是「無法靠重新建置來看見它」的那種建置。
        // A vertical stack, so `.toolbar` has somewhere to put a bar without
        // overlapping the content. The scroll host takes weight 1 and the
        // toolbar, when there is one, sits above it at its natural height.
        //
        // The stack exists even with no toolbar. Building it only on demand
        // would mean replacing the content view after the window is already up,
        // and Android's `setContentView` on a live window discards the view
        // tree it replaces -- every widget the app had built would be recreated
        // the first time a `.toolbar` appeared, losing scroll position and
        // in-flight text. One always-present LinearLayout costs one view.
        //
        // 一個垂直堆疊,好讓 `.toolbar` 有地方擺放一條列而不與內容重疊。scroll host 取 weight 1,
        // 而工具列(存在時)以其自然高度位於其上。
        //
        // 即使沒有工具列,這個堆疊也一樣存在。若改為按需建立,就意味著要在視窗已經顯示之後替換
        // content view,而 Android 的 `setContentView` 在活著的視窗上會丟棄它所替換掉的整棵 view
        // 樹——app 已建好的每一個 widget 都會在第一次出現 `.toolbar` 時被重建,捲動位置與輸入到
        // 一半的文字也隨之消失。一個恆常存在的 LinearLayout 只值一個 view。
        // `ShortcutHostLayout`, not a plain `LinearLayout`, and the difference is one override.
        // It offers an unconsumed key to the app's shortcut table after the whole hierarchy has
        // declined it -- the same moment an unhandled-key listener would, one level lower, which
        // is the level an action file can reach. Its own header carries why that matters.
        // 用 `ShortcutHostLayout` 而不是一個普通的 `LinearLayout`,差別只有一個覆寫。它會在整個階層都
        // 拒絕一個按鍵之後,把它交給 app 的快捷鍵表——與 unhandled-key listener 同一個時刻,只是低一層,
        // 而那一層正是動作檔抵達得了的。為什麼這件事重要,寫在它自己的檔頭。
        let stack = ShortcutHostLayout(context: Self.activity, environment: Self.env)
        stack.setOrientation(try! JavaClass<AndroidKit.LinearLayout>().VERTICAL)
        let matchParentDimension = try! JavaClass<AndroidKit.ViewGroup.LayoutParams>().MATCH_PARENT
        stack.addView(
            AndroidRootScrollHost.wrap(
                container,
                activity: Self.activity,
                environment: Self.env,
                showModeControl: DebugFeatures.allowsRootScrollControl,
                onHost: { host in window.scrollHost = host }
            ),
            AndroidKit.LinearLayout.LayoutParams(
                matchParentDimension,
                0,
                1,
                environment: Self.env
            )
            .as(AndroidKit.ViewGroup.LayoutParams.self)
        )
        window.rootStack = stack.as(AndroidKit.LinearLayout.self)
        stack.setShortcutListener(Self.applicationShortcutListener)
        window.content = container
        // The mode control changes what size the window reports; lay out again.
        // 模式切換控制項會改變視窗回報的尺寸;重新排版。
        window.scrollHost?.setOnModeChange(
            SwiftAction(environment: Self.env) { [weak self, weak window] in
                guard let self, let window else { return }
                self.updateInsets(ofWindow: window)
                window.resizeHandler?(self.size(ofWindow: window))
            }
        )
        if window.token != nil {
            // A later window: its activity takes `stack` when `show` starts it.
            // 之後的視窗:`show` 啟動它的 activity 時，該 activity 會接手 `stack`。
            window.contentRoot = stack.as(AndroidKit.View.self)
            updateInsets(ofWindow: window)
            return
        }
        Self.activity.setContentView(stack)
        Self.rootStack = stack.as(AndroidKit.LinearLayout.self)
        Self.shortcutHost = stack
        stack.setShortcutListener(Self.applicationShortcutListener)
        window.content = container
        updateInsets(ofWindow: window)
    }

    func hasNavigationTitle(_ window: Window) -> Bool {
        guard let stack = window.rootStack ?? Self.rootStack else { return false }
        return Self.navigationTitleView(in: stack) != nil
    }

    func updateInsets(ofWindow window: Window) {
        guard let container = window.content else {
            logger.warning("Attempted to update insets of window without content")
            return
        }

        let matchParent = try! JavaClass<AndroidKit.ViewGroup.LayoutParams>().MATCH_PARENT

        let insetsActivity = activity(of: window) ?? Self.activity
        let leftInset = Int(helpers.getSafeAreaLeftInset(insetsActivity))
        // A navigation title sits under the status bar and carries that inset itself.
        // 導覽標題位於狀態列下方，自己帶著那段內縮。
        let topInset =
            hasNavigationTitle(window) ? 0 : Int(helpers.getSafeAreaTopInset(insetsActivity))
        let fullWindowSize = SIMD2(Int(matchParent), Int(matchParent))
        setSize(of: container, to: fullWindowSize)
        setPosition(ofChildAt: 0, in: container, to: SIMD2(leftInset, topInset))

        let safeWindowSize = size(ofWindow: window)
        let child = container.as(CustomContainer.self)!.getChildAt(0)!
        setSize(of: child, to: safeWindowSize)
    }

    public func size(ofWindow window: Window) -> SIMD2<Int> {
        // actualView lays an app out at the size it asked for, as on a desktop,
        // not at the phone's: a layout that depends on the screen width is not
        // the app's actual view, and iOS (411 dp vs 440 pt) wrapped differently
        // (user, 2026-10-09: "Actual View 不應該有 screen width 問題", "不該換行").
        // Test builds only -- where the mode control exists; a shipped app sizes
        // to the screen, as SwiftUI ignores defaultSize on a phone. rwdView keeps
        // the screen size and scales.
        // actualView 以 app 要求的尺寸排版，如同在桌面上，而不是以手機的尺寸：依螢幕寬度而定的版面不是 app 的實際樣子，
        // 而且 iOS(411 dp 對 440 pt)換行位置不同(使用者,2026-10-09)。只在有模式切換控制項的測試建置中;正式的 app 依螢幕
        // 排版，如同 SwiftUI 在手機上忽略 defaultSize。rwdView 維持螢幕尺寸並縮放。
        if DebugFeatures.allowsRootScrollControl,
            let defaultSize = window.defaultSize,
            (window.scrollHost?.getModeIndex() ?? 0) == 0
        {
            return defaultSize
        }
        // A later window before its activity exists measures as the first: the
        // same screen, and the activity will report its own size once it runs.
        // 之後的視窗在其 activity 存在前，以第一個視窗的尺寸量測：同一個螢幕，activity 一跑起來就會回報自己的尺寸。
        let sizeActivity = activity(of: window) ?? Self.activity
        let width = Int(helpers.getSafeWindowWidth(sizeActivity))
        // Less the navigation title's bar when there is one. 有導覽標題時扣掉它那一列。
        let height =
            Int(helpers.getSafeWindowHeight(sizeActivity)) - (hasNavigationTitle(window) ? 44 : 0)
        return SIMD2(Int(width), Int(height))
    }

    public func isWindowProgrammaticallyResizable(_ window: Window) -> Bool {
        false
    }

    public func setSize(ofWindow window: Window, to newSize: SIMD2<Int>) {
        log("warning: Attempted to set size of Android window")
    }

    public func setSizeLimits(
        ofWindow window: Void,
        minimum minimumSize: SIMD2<Int>,
        maximum maximumSize: SIMD2<Int>?
    ) {}

    //    public func setBehaviors(ofWindow window: Void, closable: Bool, minimizable: Bool, resizable: Bool) {}

    public func setResizeHandler(
        ofWindow window: Window,
        to action: @escaping (_ newSize: SIMD2<Int>) -> Void
    ) {
        // Rotation and anything else that changes the window's size -- see
        // AndroidBackend+ConfigurationChanges.swift.
        // 旋轉與其他改變視窗大小的事——見 AndroidBackend+ConfigurationChanges.swift。
        window.resizeHandler = action
        register(window)
        installConfigurationListener()
    }

    public func show(window: Window) {
        log("Show window")

        if let token = window.token {
            guard !window.isOpen, let root = window.contentRoot else { return }
            window.isOpen = true
            helpers.openWindow(
                Self.activity,
                token,
                window.title,
                root,
                SwiftAction(environment: Self.env) { [weak window] in
                    guard let window else { return }
                    window.isOpen = false
                    let handler = window.closeHandler
                    window.closeHandler = nil
                    handler?()
                },
                SwiftAction(environment: Self.env) { [weak self, weak window] in
                    guard let self, let window else { return }
                    self.updateInsets(ofWindow: window)
                    window.resizeHandler?(self.size(ofWindow: window))
                }
            )
            return
        }

        #if SCUI_DEBUG
            // Only ever fires for the first window, and only when -actionfile
            // was passed. See InputEvent's ActionFileReplay. AppKitBackend and
            // WinUIBackend do the same thing in the same place.
            // 僅對第一個視窗生效，且僅在有傳入 -actionfile 時。詳見 InputEvent 的 ActionFileReplay。
            // AppKitBackend 與 WinUIBackend 在同一個位置做同一件事。
            ActionFileReplay.replayIfRequested()
        #endif
    }

    public func activate(window: Window) {}

    /// The activity a window lives in: the app's for the first window, the
    /// window's own `ScuiWindowActivity` for a later one once it has started,
    /// `nil` before that.
    /// 視窗所在的 activity:第一個視窗是 app 的 activity,之後的視窗在啟動後是它自己的 `ScuiWindowActivity`,
    /// 啟動前為 `nil`。
    /// The activity to present over for a window, or the first activity when
    /// there is none (no window given, or a later window not started yet).
    /// Sheets, alerts and file dialogs use it, so a presentation from a later
    /// window appears over that window. 2026-10-07.
    /// 為某個視窗做呈現時所用的 activity;沒有時(未指定視窗、或之後的視窗尚未啟動)用第一個 activity。sheet、alert
    /// 與檔案對話框都用它，讓來自之後視窗的呈現出現在那個視窗上。2026-10-07。
    func presentingActivity(for window: Window?) -> Activity {
        window.flatMap { activity(of: $0) } ?? Self.activity
    }

    func activity(of window: Window) -> Activity? {
        guard let token = window.token else { return Self.activity }
        return helpers.windowActivity(token)
    }

    // `setApplicationMenu` is implemented now, in
    // `AndroidBackend+ApplicationMenus.swift`. The stub that stood here carried
    // the TODO "Register app menu items as shortcuts when we support keyboard
    // shortcuts", and that is precisely what it does, keyboard shortcuts having
    // landed on 2026-09-16.
    // `setApplicationMenu` 現已實作,位於 `AndroidBackend+ApplicationMenus.swift`。原本立在此處的樁
    // 帶著 TODO「Register app menu items as shortcuts when we support keyboard shortcuts」,而它做的
    // 正是那件事——鍵盤快捷鍵已於 2026-09-16 落地。

    // `setIncomingURLHandler` is in `AndroidBackend+IncomingURLs.swift` (2026-10-06).
    // `setIncomingURLHandler` 位於 `AndroidBackend+IncomingURLs.swift`(2026-10-06)。

    public func runInMainThread(action: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            action()
        }
    }

    /// Reads the device class and the styles that follow from it.
    ///
    /// Called from `init()` and not only from `computeRootEnvironment`, because
    /// `EnvironmentValues.init(backend:)` captures `supportedDatePickerStyles`
    /// once and runs before `computeRootEnvironment` does. An app that checks
    /// the environment before asking -- which is what P11 does and what P41 now
    /// does -- would otherwise be handed the placeholder list.
    ///
    /// Measured 2026-09-04 on a Wear OS 5 emulator: P41 asked for `.graphical`
    /// because the environment still said it was available, and
    /// `DatePickerStyleModifier` then refused it against the real list and
    /// ended the process. The app's check and the modifier's check were reading
    /// two different answers.
    ///
    /// 讀取 device class，以及由它決定的那些樣式。
    ///
    /// 從 `init()` 呼叫，而不只是從 `computeRootEnvironment` 呼叫，因為
    /// `EnvironmentValues.init(backend:)` 只會擷取一次 `supportedDatePickerStyles`，而它的執行早於
    /// `computeRootEnvironment`。一支「先檢查 environment 再索取」的 app——P11 就是如此，P41 現在
    /// 也是——否則拿到的會是佔位清單。
    ///
    /// 2026-09-04 於 Wear OS 5 emulator 上實測：P41 索取了 `.graphical`，因為 environment 仍說它
    /// 可用；而 `DatePickerStyleModifier` 接著依真實清單拒絕了它，並終結了行程。app 的檢查與
    /// modifier 的檢查讀到的是兩個不同的答案。
    private func resolveDeviceClass() {
        _supportedDatePickerStyles.withLock { supportedDatePickerStyles in
            switch helpers.getDeviceClass(Self.activity) {
                case 0:
                    deviceClass = .desktop
                    supportedDatePickerStyles = [.automatic, .compact, .graphical, .wheel]
                // `.graphical` added for phone and tablet 2026-09-03. The size
                // objection above was real when it was written and the answer
                // to it arrived separately: every window's root child is now
                // hosted in `AndroidRootScrollHost`, so content wider or taller
                // than the screen is reached by scrolling rather than lost. A
                // 350dp calendar also fits across this emulator's 411-point
                // window without scrolling at all.
                //
                // Nothing had to be implemented for this. `GraphicalDatePicker`
                // has always been here and `updateDatePicker` has always had
                // the `.graphical` branch; the style was simply not declared,
                // and `datePickerStyle(_:)` asserts on a style a backend does
                // not list. P41 asks for `.graphical` unconditionally and died
                // at launch on that assertion -- an app that queried
                // `supportedDatePickerStyles` first, as P11 does, would have
                // been quietly downgraded instead.
                //
                // Watch keeps `.compact` and `.wheel` and not `.graphical`,
                // and both halves of that are now measured rather than
                // reasoned. A Wear OS 5 emulator reports 320 x 640 points at
                // density 160, so the 350dp calendar does not fit -- the size
                // objection is real there, unlike on the phone. `.wheel` was
                // verified on the same device on 2026-09-04: P41 draws
                // Jul/Aug/Sep beside 23/24/25 with "2025-08-24" underneath, the
                // same as on the phone.
                //
                // This entry was an assertion when it was written. The watch
                // was added to the SDK, an AVD created and the app run on it
                // precisely because a claim about a device nobody had tried is
                // the kind this repository asks to be demonstrated.
                //
                // `.wheel` is new on every class in this switch, and it needed
                // no size argument at all: it was declared nowhere because it
                // was implemented nowhere. See `WheelDatePicker.kt`.
                //
                // 2026-09-03 為 phone 與 tablet 加入 `.graphical`。上方那個尺寸的反對意見在當時是
                // 成立的，而它的解答是另外抵達的：每個視窗的根子元件現在都寄宿於
                // `AndroidRootScrollHost` 之中，因此比螢幕更寬或更高的內容是靠捲動抵達，而不是遺失。
                // 而且一個 350dp 的日曆在本 emulator 411 點寬的視窗中，根本不需要捲動就放得下。
                //
                // 此處不需要實作任何東西。`GraphicalDatePicker` 一直都在，`updateDatePicker` 也一直
                // 都有 `.graphical` 分支；只是這個 style 從未被宣告，而 `datePickerStyle(_:)` 對於
                // backend 未列出的 style 會觸發 assert。P41 無條件要求 `.graphical`，因而死在那個
                // assert 上——而一個像 P11 那樣先查詢 `supportedDatePickerStyles` 的 app，得到的會是
                // 靜默降級。
                //
                // watch 保留 `.compact` 與 `.wheel`、不含 `.graphical`，而這兩半現在都是量出來的，
                // 不是推出來的。Wear OS 5 emulator 回報 320 x 640 點、density 160，因此 350dp 的
                // 日曆放不下——那個尺寸的反對意見在該處是成立的，與手機上不同。`.wheel` 於
                // 2026-09-04 在同一台裝置上驗證：P41 畫出 Jul/Aug/Sep 與 23/24/25，底下是
                // 「2025-08-24」，與手機上相同。
                //
                // 這一條在寫下時是一項斷言。之所以把手錶映像裝進 SDK、建立 AVD 並在其上執行該 app，
                // 正是因為「關於一台沒有人試過的裝置的主張」，屬於本倉庫要求被證明的那一類。
                //
                // 本 switch 中每一個 device class 的 `.wheel` 都是新加的，而它完全不需要尺寸方面的
                // 論證：它之所以在任何地方都沒有被宣告，是因為它在任何地方都沒有被實作。
                // 見 `WheelDatePicker.kt`。
                case 1:
                    deviceClass = .phone
                    supportedDatePickerStyles = [.automatic, .compact, .graphical, .wheel]
                case 2:
                    deviceClass = .tablet
                    supportedDatePickerStyles = [.automatic, .compact, .graphical, .wheel]
                case 3:
                    deviceClass = .tv
                    supportedDatePickerStyles = [.automatic, .compact, .graphical, .wheel]
                case 4:
                    deviceClass = .watch
                    supportedDatePickerStyles = [.automatic, .compact, .wheel]
                case let x:
                    fatalError("helpers.getDeviceClass returned unexpected value \(x)")
            }
        }
    }

    public func computeRootEnvironment(defaultEnvironment: EnvironmentValues) -> EnvironmentValues {
        var environment = defaultEnvironment

        environment.androidActivity = Self.activity
        environment.jniEnv = Self.env
        // A switch by default, as UIKitBackend sets: the platform's on/off
        // control on both phones. The core default is `.button`, which put a
        // ToggleButton where iOS draws a UISwitch -- P10's 260-wide toggle
        // showed "Transpa" on Android and a labelled switch on iOS (2026-10-09).
        // 預設為 switch,與 UIKitBackend 的設定相同：兩種手機上平台本身的開關控制項。core 的預設是 `.button`,
        // 讓 Android 在 iOS 畫 UISwitch 的地方放了 ToggleButton——P10 那個 260 寬的開關在 Android 上只顯示「Transpa」,
        // iOS 則是帶標籤的開關(2026-10-09)。
        environment.toggleStyle = .switch

        if helpers.isNightMode(Self.activity) {
            environment.colorScheme = .dark
        } else {
            environment.colorScheme = .light
        }

        environment.isCircularScreen = Self.activity
            .getResources()
            .getConfiguration()
            .isScreenRound()

        var timeZone: Foundation.TimeZone?

        if let identifier = helpers.getTimeZoneIdentifier()?.toString() {
            timeZone = Foundation.TimeZone(identifier: identifier)
        }

        // Foundation's own default as well, not only the environment's.
        //
        // `TimeZone.current` does not find the device's zone on Android --
        // that is why these two lines exist at all. But an app does not
        // only read `environment.timeZone`: a plain `DateFormatter` with no
        // zone set uses Foundation's default, and there is no way for the
        // app to know it has to override it. Measured 2026-09-03 on an
        // emulator set to Asia/Taipei: P41 formatted 1756000000 as
        // "2025-08-23" while its own date picker, which goes through
        // `environment.timeZone`, showed 24 August. Both were reading the
        // same instant. The app was not wrong; it asked Foundation and
        // Foundation did not know.
        //
        // Assigned rather than worked around for the same reason
        // `CommandLine.arguments` is in AndroidBackend+Arguments.swift: the
        // platform does not populate something every Swift program expects
        // to be populated, the backend is the one piece of code that knows
        // the real value, and the alternative is every app carrying the
        // workaround.
        //
        // 也設定 Foundation 自己的預設值，而不只是 environment 的。
        //
        // `TimeZone.current` 在 Android 上找不到裝置的時區——那正是上面這兩行存在的原因。但一支
        // app 讀取的不只是 `environment.timeZone`：一個未設定時區的普通 `DateFormatter` 用的是
        // Foundation 的預設值，而 app 沒有任何辦法知道自己必須覆寫它。2026-09-03 於設定為
        // Asia/Taipei 的 emulator 上實測：P41 把 1756000000 格式化為「2025-08-23」，而它自己的
        // 日期選擇器（走 `environment.timeZone`）顯示的是 8 月 24 日。兩者讀的是同一個瞬間。
        // 那支 app 沒有錯；它問了 Foundation，而 Foundation 不知道。
        //
        // 選擇直接指派而非繞過，理由與 AndroidBackend+Arguments.swift 中的
        // `CommandLine.arguments` 相同：平台沒有填入某個「每一支 Swift 程式都預期已被填入」的
        // 東西，而 backend 是唯一知道真實值的那段程式碼；另一種做法是讓每一支 app 各自攜帶
        // 這個變通。
        if let timeZone {
            environment.timeZone = timeZone
            NSTimeZone.default = timeZone
        }

        let (calendar, locale) = getCurrentCalendarAndLocale(timeZone: timeZone)
        environment.calendar = calendar
        environment.locale = locale

        environment
            .appStorageProvider = SharedPreferencesAppStorageProvider(activity: Self.activity)

        // The graphical DatePicker style is ginormous -- the clock and calendar individually are
        // ~350dp wide each, so when stacked next to each other they don't fit on all tablets, and
        // even just one of them doesn't fit by itself on some phones. Watch renders them a bit
        // smaller so they almost fit, but again they don't both fit at the same time.
        resolveDeviceClass()

        return environment
    }

    public func setRootEnvironmentChangeHandler(
        to action: @escaping @Sendable @MainActor () -> Void
    ) {
        // Light/dark and the rest of the configuration -- see
        // AndroidBackend+ConfigurationChanges.swift.
        // 深淺色與其餘設定——見 AndroidBackend+ConfigurationChanges.swift。
        Self.rootEnvironmentChangeHandler = action
        installConfigurationListener()
    }

    public func computeWindowEnvironment(
        window: Window,
        rootEnvironment: EnvironmentValues
    ) -> EnvironmentValues {
        var environment = rootEnvironment
        environment
            .windowScaleFactor = Double(window.content!.getResources().getDisplayMetrics().density)
        return environment
    }

    public func setWindowEnvironmentChangeHandler(
        of window: Window,
        to action: @escaping @Sendable @MainActor () -> Void
    ) {
        // Density and font scale -- see AndroidBackend+ConfigurationChanges.swift.
        // 密度與字體縮放——見 AndroidBackend+ConfigurationChanges.swift。
        window.environmentChangeHandler = action
        register(window)
        installConfigurationListener()
    }

    public func show(widget: Widget) {}

    public func createContainer() -> Widget {
        CustomContainer(Self.activity, environment: Self.env)
            .as(AndroidKit.View.self)!
    }

    public func removeAllChildren(of container: Widget) {
        Self.childPositions.forget(container)
        let container = container.as(CustomContainer.self)!
        container.removeAllViews()
    }

    public func insert(_ child: Widget, into container: Widget, at index: Int) {
        Self.childPositions.forget(container)
        let container = container.as(CustomContainer.self)!
        container.addView(child, Int32(index))
    }

    public func setPosition(
        ofChildAt index: Int,
        in container: Widget,
        to position: SIMD2<Int>
    ) {
        // Unchanged positions cost no JNI at all -- see LastSet.
        // 沒有改變的位置完全不經過 JNI——見 LastSet。
        var known = Self.childPositions.value(for: container) ?? [:]
        if known[index] == position { return }
        known[index] = position
        Self.childPositions.set(known, for: container)
        let density = container.getResources().getDisplayMetrics().density

        let container = container.as(CustomContainer.self)!
        let child = container.getChildAt(Int32(index))!

        let layoutParams = child.getLayoutParams().as(CustomContainer.LayoutParams.self)!
        let x = Int32(Float(position.x) * density)
        let y = Int32(Float(position.y) * density)
        // Nothing to do when the child is already there. `setLayoutParams`
        // calls requestLayout, so every unchanged position still cost an
        // Android layout pass: in P66's animation 94 % of these calls (5796 of
        // 6193) and 96 % of `setSize`'s were unchanged (2026-10-04).
        // 子元件已經在那裡就不做事。`setLayoutParams` 會呼叫 requestLayout,所以每一次沒有改變的位置
        // 仍然花掉一次 Android 排版:P66 的動畫中，這些呼叫有 94%(6193 次中的 5796 次)、`setSize` 有 96%
        // 是沒有改變的(2026-10-04)。
        guard layoutParams.getX() != x || layoutParams.getY() != y else { return }
        layoutParams.setX(x)
        layoutParams.setY(y)

        child.setLayoutParams(layoutParams.as(ViewGroup.LayoutParams.self))
    }

    public func remove(childAt index: Int, from container: Widget) {
        Self.childPositions.forget(container)
        let container = container.as(CustomContainer.self)!
        container.removeViewAt(Int32(index))
    }

    public func swap(childAt firstIndex: Int, withChildAt secondIndex: Int, in container: Widget) {
        Self.childPositions.forget(container)
        let container = container.as(CustomContainer.self)!
        let largerIndex = Int32(max(firstIndex, secondIndex))
        let smallerIndex = Int32(min(firstIndex, secondIndex))
        let view1 = container.getChildAt(smallerIndex)
        let view2 = container.getChildAt(largerIndex)
        container.removeViewAt(largerIndex)
        container.removeViewAt(smallerIndex)
        container.addView(view2, smallerIndex)
        container.addView(view1, largerIndex)
    }

    public func naturalSize(of widget: Widget) -> SIMD2<Int> {
        let density = widget.getResources().getDisplayMetrics().density

        let measureSpecClass = try! JavaClass<AndroidKit.View.MeasureSpec>(
            environment: Self.env
        )
        widget.measure(
            measureSpecClass.UNSPECIFIED,
            measureSpecClass.UNSPECIFIED
        )
        let width = Float(widget.getMeasuredWidth()) / density
        let height = Float(widget.getMeasuredHeight()) / density
        return SIMD2(Int(width.rounded(.up)), Int(height.rounded(.up)))
    }

    public func setSize(of widget: Widget, to size: SIMD2<Int>) {
        if Self.widgetSizes.value(for: widget) == size { return }
        guard let layoutParams = widget.getLayoutParams() else { return }
        // Remembered only once it has actually been applied: with no layout
        // params yet nothing was set, and the next call must try again.
        // 只在真正套用之後才記下：還沒有 layout params 時什麼都沒設，下一次呼叫必須再試。
        Self.widgetSizes.set(size, for: widget)
        let density = widget.getResources().getDisplayMetrics().density
        let width = Self.layoutLength(size.x, density: density)
        let height = Self.layoutLength(size.y, density: density)
        // Unchanged sizes skipped, for the reason `setPosition` gives.
        // 沒有改變的尺寸跳過，理由見 `setPosition`。
        guard layoutParams.width != width || layoutParams.height != height else { return }
        layoutParams.width = width
        layoutParams.height = height
        widget.setLayoutParams(layoutParams)
    }

    /// Points to pixels, except where the number is not a length.
    ///
    /// `ViewGroup.LayoutParams` overloads its width and height: `MATCH_PARENT`
    /// is `-1` and `WRAP_CONTENT` is `-2`. They are sentinels, and multiplying
    /// one by the display density turns it into the other -- at density 2.625,
    /// `Int32(Float(-1) * 2.625)` is `-2`.
    ///
    /// So `updateInsets`, which asks for `MATCH_PARENT` on the root container,
    /// was setting `WRAP_CONTENT` on it, on every device whose density is above
    /// 1. The window rendered anyway while the content fitted, which is what
    /// made it survive: a `WRAP_CONTENT` container is the size of its content,
    /// and that looks identical to filling the parent until the content grows
    /// past it.
    ///
    /// Measured on the emulator, 2026-09-03, before this line existed: nine
    /// presses of P12's "Increment counter" left the page intact at 378953
    /// non-white pixels, and the tenth -- where the count needs a second digit
    /// -- emptied the window to 0. Pressing a tab button or a control with a
    /// longer status line did the same. `adb shell input tap` did it too, so it
    /// was never the action-file machinery. See `bugs/bug-Android.md`.
    ///
    /// 點轉換為像素，但「那個數字不是長度」的情況除外。
    ///
    /// `ViewGroup.LayoutParams` 的 width 與 height 是多載的：`MATCH_PARENT` 是 `-1`，
    /// `WRAP_CONTENT` 是 `-2`。它們是哨兵值，而把其中一個乘上顯示密度會把它變成另一個——在密度
    /// 2.625 下，`Int32(Float(-1) * 2.625)` 就是 `-2`。
    ///
    /// 因此 `updateInsets`（它為根容器要求的是 `MATCH_PARENT`）實際上把它設成了 `WRAP_CONTENT`，
    /// 而且在每一台密度大於 1 的裝置上都是如此。視窗在內容塞得下時照樣算繪，這正是它能存活至今的
    /// 原因：`WRAP_CONTENT` 的容器就是其內容的大小，而在內容尚未超出之前，那看起來與「填滿父容器」
    /// 完全相同。
    ///
    /// 2026-09-03 於 emulator 上、在這一行存在之前量得：按 P12 的「Increment counter」九次，
    /// 頁面完好，非白像素 378953；而第十次——計數需要第二位數時——把視窗清空為 0。按分頁按鈕、
    /// 或按一個會讓狀態文字變長的控制項，結果相同。`adb shell input tap` 也一樣，因此這從來就不是
    /// 動作檔機制的問題。詳見 `bugs/bug-Android.md`。
    static func layoutLength(_ points: Int, density: Float) -> Int32 {
        points < 0 ? Int32(points) : Int32(Float(points) * density)
    }

    public func createSimpleButton() -> Widget {
        let button = AndroidKit.Button(Self.activity, environment: Self.env)
        helpers.styleSimpleButton(button)
        return button
    }

    /// Converts a Swift String to a Java CharSequence.
    static func charSequence(from string: String) -> CharSequence {
        let jstring = JavaString(string, environment: Self.env)
        return jstring.as(CharSequence.self)!
    }

    public func updateSimpleButton(
        _ button: Widget,
        label: String,
        environment: EnvironmentValues,
        action: @escaping () -> Void
    ) {
        let button = button.as(AndroidKit.Button.self)!
        button.setText(Self.charSequence(from: label))
        button.setEnabled(environment.isEnabled)
        let listener = ViewOnClickListener(action: action, environment: Self.env)
        button.setOnClickListener(listener.as(AndroidView.View.OnClickListener.self))
        button.setAllCaps(false)

        // The label in the tint, as UIKit draws a plain UIButton's (Menu).
        // 標籤用 tint 色，與 UIKit 繪製單純 UIButton 的方式相同(Menu)。
        getTextStyle(from: tintedLabelEnvironment(environment)).apply(to: button)
    }

    public func createTextView() -> Widget {
        FittedTextView(activity: Self.activity, environment: Self.env).as(AndroidKit.TextView.self)!
    }

    public func updateTextView(
        _ textView: Widget,
        content: String,
        environment: EnvironmentValues
    ) {
        // In a disabled scope, the default colour at 30%, as UIKitBackend's
        // resolvedForegroundColor gives a Text: P21's disabled checkbox was labelled
        // in full black on Android and grey on iOS (2026-10-10). A colour the app
        // chose is kept. Only Text: buttons dim their own labels.
        // 在停用的範圍內，預設顏色取 30%,與 UIKitBackend 的 resolvedForegroundColor 給 Text 的相同:P21 停用的
        // checkbox 標籤在 Android 上是全黑，在 iOS 上是灰色(2026-10-10)。app 選的顏色則保留。只限 Text:按鈕自行調暗標籤。
        var environment = environment
        if !environment.isEnabled, environment.foregroundColor == nil {
            environment = environment.with(
                \.foregroundColor, environment.suggestedForegroundColor.opacity(0.3)
            )
        }
        // Same text in the same style: nothing to send. setText relays the
        // text out and requests a layout even for an identical string, and
        // about half of P66's calls were identical (2026-10-04); the check is
        // on the Swift side so that it costs no JNI -- see LastSet.
        // 同樣樣式的同樣文字：不必送出。即使字串相同,setText 也會重新排版文字並要求一次排版，而 P66 的呼叫
        // 約有一半是相同的(2026-10-04);比較放在 Swift 這一側，因此不花任何 JNI——見 LastSet。
        let memo = "\(textStyleKey(for: environment))\u{1}\(content)"
        if Self.textContents.value(for: textView) == memo { return }
        Self.textContents.set(memo, for: textView)
        let widget = textView
        let textView = widget.as(AndroidKit.TextView.self)!
        let content = JavaString(content, environment: Self.env)
        textView.setText(content.as(CharSequence.self))
        getTextStyle(from: environment).apply(to: textView)
    }

    public func size(
        of text: String,
        whenDisplayedIn widget: Widget,
        proposedWidth: Int?,
        proposedHeight: Int?,
        environment: EnvironmentValues
    ) -> SIMD2<Int> {
        // Measured once per (text, style, proposal). This used to construct a
        // new Java TextView and apply a full text style for EVERY measurement,
        // and a Text is measured several times per layout pass; on 2026-10-04
        // this function was 50.5 % of P66's main thread during an animation.
        // The answer is a pure function of the key, so it is cached; one
        // TextView, kept, does the measuring when the key is new.
        // 依(文字、樣式、提議尺寸)只量一次。原本**每一次**量測都新建一個 Java TextView 並套用完整文字樣式,
        // 而一個 Text 每次排版會被量好幾次;2026-10-04 動畫期間本函式佔 P66 主執行緒的 50.5%。結果完全由鍵
        // 決定，所以快取;鍵是新的時候，由一個保留下來的 TextView 負責量。
        let key = "\(textStyleKey(for: environment))|\(proposedWidth ?? -1)|"
            + "\(proposedHeight ?? -1)|\(environment.lineLimitSettings.map { "\($0.limit)/\($0.reservesSpace)" } ?? "-")|\(text)"
        if let cached = Self.textSizes[key] {
            return cached
        }
        if Self.textSizes.count > 4096 {
            Self.textSizes.removeAll(keepingCapacity: true)
        }
        let widget: Widget
        if let existing = Self.measuringTextView {
            widget = existing
        } else {
            widget = createTextView()
            // Layout params, although it never joins a parent: once measured,
            // TextView.setText calls checkForRelayout, which reads
            // mLayoutParams.width -- a NullPointerException on a reused view
            // that has none (P66, 2026-10-04). A fresh view per measurement
            // never had a layout, so never got there.
            // 雖然它從不加入任何父 view,仍給它 layout params:量過一次之後,TextView.setText 會呼叫
            // checkForRelayout,讀取 mLayoutParams.width——重複使用且沒有 params 的 view 會丟出
            // NullPointerException(P66,2026-10-04)。每次量測都用新 view 時從未有過 layout,也就走不到那裡。
            widget.setLayoutParams(
                AndroidKit.ViewGroup.LayoutParams(-2, -2, environment: Self.env)
            )
            Self.measuringTextView = widget
        }
        updateTextView(widget, content: text, environment: environment)

        // 0x80000000 = View.MeasureSpec.AT_MOST
        // 0x3FFFFFFF = View.MeasureSpec.makeMeasureSpec(Int32.max, View.MeasureSpec.UNSPECIFIED)
        let widthSpec =
            if let proposedWidth {
                Int32(bitPattern: 0x80000000 |
                    UInt32(Double(proposedWidth) * environment.windowScaleFactor) & ~0x40000000)
            } else {
                0x3FFFFFFF as Int32
            }
        // Height unbounded, then cut to the whole lines the proposal has room
        // for -- at least one -- as UIKit's boundingRect with
        // truncatesLastVisibleLine does. The proposed height used to go in as a
        // bare number, which MeasureSpec reads as UNSPECIFIED, so a Text always
        // took every line it wrapped to: P17's "subject" came out 160 x 64 where
        // iOS gives 159 x 22 (2026-10-10). FittedTextView then draws only the
        // lines that fit, ending in an ellipsis.
        // 高度不設限地量，再裁成提議尺寸放得下的整行(至少一行),與 UIKit 帶 truncatesLastVisibleLine 的
        // boundingRect 相同。提議高度原本以裸數字傳入,MeasureSpec 把它讀成 UNSPECIFIED,所以 Text 永遠佔滿
        // 它換行後的每一行:P17 的 "subject" 量出 160 x 64,iOS 是 159 x 22(2026-10-10)。之後由
        // FittedTextView 只畫放得下的行，並以刪節號結尾。
        widget.measure(widthSpec, 0x3FFFFFFF as Int32)
        var width = Double(widget.getMeasuredWidth()) / environment.windowScaleFactor
        var height = Double(widget.getMeasuredHeight()) / environment.windowScaleFactor
        let measuring = widget.as(AndroidKit.TextView.self)!
        let lineHeight = Double(measuring.getLineHeight()) / environment.windowScaleFactor
        var lines = max(Int(measuring.getLineCount()), 1)
        // A wrapped Text is as wide as its widest line, as UIKit's boundingRect
        // gives it; a TextView reports the whole width it was offered. P37's
        // paragraph took all 724 dp of a 760 dp window where iOS took 702 pt, so
        // the centred column sat 11 further left than on iOS (2026-10-10).
        // 換行的 Text 與它最寬的一行一樣寬，與 UIKit 的 boundingRect 相同;TextView 回報的是給它的整個寬度。
        // P37 的段落在 760 dp 的視窗裡佔滿 724 dp,iOS 是 702 pt,所以置中的那一欄比 iOS 偏左 11(2026-10-10)。
        if lines > 1, let fitted = widget.as(FittedTextView.self) {
            let widest = Double(fitted.widestLineWidth()) / environment.windowScaleFactor
            if widest > 0 { width = min(width, widest) }
        }
        // Every line is one line height, the last included, as UIKitBackend sets
        // it (minimumLineHeight = maximumLineHeight = the font's line height). A
        // TextView leaves the spacing off its last line, so one line measured
        // 20 dp where iOS gives 22, and a readout laid over a 22 dp view showed a
        // strip of it underneath (P17).
        // 每一行都是一個行高，最後一行也是，與 UIKitBackend 的設定相同(minimumLineHeight = maximumLineHeight = 字型行高)。
        // TextView 的最後一行不帶行距，所以一行量出 20 dp,iOS 是 22;疊在 22 dp view 上的讀數底下因此露出一條(P17)。
        if lineHeight > 0 {
            if let proposedHeight, Double(lines) * lineHeight > Double(proposedHeight) {
                lines = max(1, Int((Double(proposedHeight) / lineHeight).rounded(.down)))
            }
            // `.lineLimit`, as UIKitBackend applies it. 與 UIKitBackend 相同地套用 `.lineLimit`。
            if let lineLimitSettings = environment.lineLimitSettings {
                let limit = max(lineLimitSettings.limit, 1)
                if limit < lines || lineLimitSettings.reservesSpace {
                    lines = limit
                }
            }
            height = Double(lines) * lineHeight
        }
        let size = SIMD2(Int(width.rounded(.up)), Int(height.rounded(.up)))
        Self.textSizes[key] = size
        return size
    }

    /// Text measurements by key -- see `size(of:whenDisplayedIn:...)`.
    /// 文字量測結果，依鍵存放——見 `size(of:whenDisplayedIn:...)`。
    @MainActor static var textSizes: [String: SIMD2<Int>] = [:]
    /// The one TextView every measurement uses.
    /// 所有量測共用的那一個 TextView。
    @MainActor static var measuringTextView: Widget?

    // The four of these were `fatalError` until 2026-09-03. `NavigationSplitView`
    // is not an optional part of the framework -- P16 is built around it -- and
    // an unimplemented backend entry point does not degrade the view, it ends
    // the process: P16 died at launch and ActivityManager gave up on it as
    // having crashed too many times.
    //
    // The geometry lives in `SplitContainer.kt`, which also records why this is
    // two columns side by side rather than Android's usual drawer.
    //
    // 這四個在 2026-09-03 之前都是 `fatalError`。`NavigationSplitView` 不是框架中的選配部分——P16
    // 整支 app 就是圍繞它建立的——而一個未實作的 backend 進入點並不會讓該 view 降級，它會終結整個
    // 行程：P16 在啟動時就死掉，接著 ActivityManager 以「crashed too many times」放棄了它。
    //
    // 幾何計算位於 `SplitContainer.kt`，該檔同時記錄了此處為何採用左右兩欄並排，而非 Android 慣用的
    // 抽屜式做法。
    public func createSplitView(leadingChild: Widget, trailingChild: Widget) -> Widget {
        let split = SplitContainer(Self.activity, environment: Self.env)
        split.setChildren(leadingChild, trailingChild)
        return split.as(AndroidKit.View.self)!
    }

    public func setResizeHandler(
        ofSplitView splitView: Widget,
        to action: @escaping () -> Void
    ) {
        splitView.as(SplitContainer.self)!.setResizeHandler(
            SwiftAction(environment: Self.env, action: action)
        )
    }

    // Both of these cross the unit boundary, and the first version of this file
    // did not. `SplitContainer` works in pixels because `layoutParams` does;
    // SwiftCrossUI works in points. Returning the pixel count unconverted told
    // the layout system the sidebar was 288 points wide when it was 288 pixels,
    // which at density 2.625 is 110 -- so the sidebar's rows were laid out for
    // two and a half times the width they had, and P16 drew "Science" and
    // "Humanities" cut off at the divider while its own status line read
    // "sidebar: 288". The drawing was self-consistent, which is what made it
    // look like a clipping bug rather than a unit bug.
    //
    // 這兩個函式都跨越了單位邊界，而本檔的第一版沒有處理。`SplitContainer` 以像素運作，因為
    // `layoutParams` 就是像素；SwiftCrossUI 則以點運作。未經換算就回傳像素值，等於告訴版面系統
    // 側欄有 288 點寬，而它其實是 288 像素——在 density 2.625 下那是 110 點。於是側欄中的列是以
    // 「兩倍半於它實際擁有的寬度」來排版的，P16 因而把 "Science" 與 "Humanities" 畫成在分隔線處
    // 被切斷，而它自己的狀態列卻寫著「sidebar: 288」。繪製本身是自洽的，那正是它看起來像裁切問題
    // 而非單位問題的原因。
    public func sidebarWidth(ofSplitView splitView: Widget) -> Int {
        let density = splitView.getResources().getDisplayMetrics().density
        let pixels = splitView.as(SplitContainer.self)!.resolvedSidebarWidth()
        return Int((Double(pixels) / Double(density)).rounded())
    }

    public func setSidebarWidthBounds(
        ofSplitView splitView: Widget,
        minimum minimumWidth: Int,
        maximum maximumWidth: Int
    ) {
        let density = splitView.getResources().getDisplayMetrics().density

        // Clamped before the multiply. A maximum of `Int.max` means "no upper
        // bound" and is what the layout system sends when the app has not set
        // one; `Float(Int.max) * 2.625` does not fit in an `Int32` and the
        // conversion traps, which would make an unbounded sidebar -- the
        // default -- the one case that crashes.
        //
        // 在乘法之前先夾住。上限為 `Int.max` 的意思是「沒有上限」，而那正是 app 未設定上限時版面
        // 系統會送來的值；`Float(Int.max) * 2.625` 放不進 `Int32`，該轉換會 trap——那會使「未設上限
        // 的側欄」這個預設情況，成為唯一會崩潰的情況。
        let pixelLimit = Int(Int32.max)
        splitView.as(SplitContainer.self)!.setSidebarWidthBounds(
            Self.layoutLength(min(minimumWidth, pixelLimit), density: density),
            maximumWidth >= pixelLimit
                ? Int32.max
                : Self.layoutLength(maximumWidth, density: density)
        )
    }
}
