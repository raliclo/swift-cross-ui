import Android
import Foundation
import InputEvent
@_spi(Backends) import SwiftCrossUI
import AndroidKit
import AndroidGraphics
import AndroidBackendShim
import Mutex

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

extension EnvironmentValues {
    @Entry public var androidActivity: AndroidKit.Activity! = nil
    @Entry public var jniEnv: UnsafeMutablePointer<JNIEnv?>? = nil
}

public final class AndroidBackend: BaseAppBackend {
    public final class Window {
        var content: Widget?
    }

    public typealias Widget = AndroidKit.View

    static let stdoutPipe = Pipe()
    static let stderrPipe = Pipe()

    private let _supportedDatePickerStyles = Mutex<[BackendDatePickerStyle]>([.automatic, .compact])

    public nonisolated var supportedDatePickerStyles: [BackendDatePickerStyle] {
        _supportedDatePickerStyles.withLock { copy $0 }
    }

    // .phone is a placeholder value -- the real value is set in `computeRootEnvironment`.
    public private(set) var deviceClass = DeviceClass.phone

    public let defaultPaddingAmount = 10
    public let supportsMultipleWindows = false
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

    /// A reference used to keep the tickler alive.
    var tickler: MainRunLoopTickler?

    /// The JNI environment pointer. Set by ``entrypoint``.
    static var env: UnsafeMutablePointer<JNIEnv?>!
    /// The main activity. Set by ``entrypoint``.
    static var activity: Activity!

    var helpers: AndroidBackendHelpers

    public init() {
        helpers = AndroidBackendHelpers(environment: Self.env)

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
        let tickler = MainRunLoopTickler(environment: Self.env)
        tickler.start()
        self.tickler = tickler

        // We just fall through to return control to Java when we're done
        // setting up the initial view hierarchy.
        callback()
    }

    public func createWindow(withDefaultSize defaultSize: SIMD2<Int>?, id: String) -> Window {
        // TODO(stackotter): Properly support multiple calls to createWindow
        return Window()
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
        helpers.setWindowBackground(Self.activity, environment.colorScheme == .dark)
        updateInsets(ofWindow: window)
    }

    public func setSizeLimits(
        ofWindow window: Window,
        minimum: SIMD2<Int>,
        maximum: SIMD2<Int>?
    ) {
        // Doesn't mean anything on Android until we support split screen
    }

    //    public func setCloseHandler(ofWindow window: Window, to action: @escaping () -> Void) {
    //        // TODO(stackotter): Set close handler?
    //    }

    public func setTitle(ofWindow window: Window, to title: String) {
        // TODO(stackotter): Handle navigation titles.
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
        Self.activity.setContentView(
            AndroidRootScrollHost.wrap(
                container,
                activity: Self.activity,
                environment: Self.env
            )
        )
        window.content = container
        updateInsets(ofWindow: window)
    }

    private func updateInsets(ofWindow window: Window) {
        guard let container = window.content else {
            logger.warning("Attempted to update insets of window without content")
            return
        }

        let matchParent = try! JavaClass<AndroidKit.ViewGroup.LayoutParams>().MATCH_PARENT

        let leftInset = Int(helpers.getSafeAreaLeftInset(Self.activity))
        let topInset = Int(helpers.getSafeAreaTopInset(Self.activity))
        let fullWindowSize = SIMD2(Int(matchParent), Int(matchParent))
        setSize(of: container, to: fullWindowSize)
        setPosition(ofChildAt: 0, in: container, to: SIMD2(leftInset, topInset))

        let safeWindowSize = size(ofWindow: window)
        let child = container.as(CustomContainer.self)!.getChildAt(0)!
        setSize(of: child, to: safeWindowSize)
    }

    public func size(ofWindow window: Window) -> SIMD2<Int> {
        let width = Int(helpers.getSafeWindowWidth(Self.activity))
        let height = Int(helpers.getSafeWindowHeight(Self.activity))
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
        // TODO(stackotter): Handle orientation changes and other changes such
        //   as density changes
    }

    public func show(window: Window) {
        log("Show window")

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

    //    public func setApplicationMenu(
    //        _ submenus: [ResolvedMenu.Submenu],
    //        environment: EnvironmentValues
    //    ) {
    //        // TODO(stackotter): Register app menu items as shortcuts when we support keyboard
    //        //   shortcuts.
    //    }

    //    public func setIncomingURLHandler(to action: @escaping (Foundation.URL) -> Void) {
    //        // TODO(stackotter): Handle incoming URLs
    //    }

    public func runInMainThread(action: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            action()
        }
    }

    public func computeRootEnvironment(defaultEnvironment: EnvironmentValues) -> EnvironmentValues {
        var environment = defaultEnvironment

        environment.androidActivity = Self.activity
        environment.jniEnv = Self.env

        if helpers.isNightMode(Self.activity) {
            environment.colorScheme = .dark
        } else {
            environment.colorScheme = .light
        }

        environment.isCircularScreen = Self.activity
            .getResources()
            .getConfiguration()
            .isScreenRound()

        if let identifier = helpers.getTimeZoneIdentifier()?.toString(),
           let timeZone = Foundation.TimeZone(identifier: identifier)
        {
            environment.timeZone = timeZone
            environment.calendar = getCurrentCalendar(timeZone: timeZone)
        } else {
            environment.calendar = getCurrentCalendar(timeZone: nil)
        }

        environment
            .appStorageProvider = SharedPreferencesAppStorageProvider(activity: Self.activity)

        // The graphical DatePicker style is ginormous -- the clock and calendar individually are
        // ~350dp wide each, so when stacked next to each other they don't fit on all tablets, and
        // even just one of them doesn't fit by itself on some phones. Watch renders them a bit
        // smaller so they almost fit, but again they don't both fit at the same time.
        _supportedDatePickerStyles.withLock { supportedDatePickerStyles in
            switch helpers.getDeviceClass(Self.activity) {
                case 0:
                    deviceClass = .desktop
                    supportedDatePickerStyles = [.automatic, .compact, .graphical]
                case 1:
                    deviceClass = .phone
                    supportedDatePickerStyles = [.automatic, .compact]
                case 2:
                    deviceClass = .tablet
                    supportedDatePickerStyles = [.automatic, .compact]
                case 3:
                    deviceClass = .tv
                    supportedDatePickerStyles = [.automatic, .compact, .graphical]
                case 4:
                    deviceClass = .watch
                    supportedDatePickerStyles = [.automatic, .compact]
                case let x:
                    fatalError("helpers.getDeviceClass returned unexpected value \(x)")
            }
        }

        return environment
    }

    public func setRootEnvironmentChangeHandler(
        to action: @escaping @Sendable @MainActor () -> Void
    ) {
        // TODO(stackotter): Listen for system theme changes
        // and call helpers.clearTextSizeCache()
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
        // TODO(stackotter): React to per-window environment changes. See
        //   computeWindowEnvironment
    }

    public func show(widget: Widget) {}

    public func createContainer() -> Widget {
        CustomContainer(Self.activity, environment: Self.env)
            .as(AndroidKit.View.self)!
    }

    public func removeAllChildren(of container: Widget) {
        let container = container.as(CustomContainer.self)!
        container.removeAllViews()
    }

    public func insert(_ child: Widget, into container: Widget, at index: Int) {
        let container = container.as(CustomContainer.self)!
        container.addView(child, Int32(index))
    }

    public func setPosition(
        ofChildAt index: Int,
        in container: Widget,
        to position: SIMD2<Int>
    ) {
        let density = container.getResources().getDisplayMetrics().density

        let container = container.as(CustomContainer.self)!
        let child = container.getChildAt(Int32(index))!

        let layoutParams = child.getLayoutParams().as(CustomContainer.LayoutParams.self)!
        layoutParams.setX(Int32(Float(position.x) * density))
        layoutParams.setY(Int32(Float(position.y) * density))

        child.setLayoutParams(layoutParams.as(ViewGroup.LayoutParams.self))
    }

    public func remove(childAt index: Int, from container: Widget) {
        let container = container.as(CustomContainer.self)!
        container.removeViewAt(Int32(index))
    }

    public func swap(childAt firstIndex: Int, withChildAt secondIndex: Int, in container: Widget) {
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
        guard let layoutParams = widget.getLayoutParams() else { return }
        let density = widget.getResources().getDisplayMetrics().density
        layoutParams.width = Self.layoutLength(size.x, density: density)
        layoutParams.height = Self.layoutLength(size.y, density: density)
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
    private static func layoutLength(_ points: Int, density: Float) -> Int32 {
        points < 0 ? Int32(points) : Int32(Float(points) * density)
    }

    public func createButton() -> Widget {
        AndroidKit.Button(Self.activity, environment: Self.env)
    }

    /// Converts a Swift String to a Java CharSequence.
    static func charSequence(from string: String) -> CharSequence {
        let jstring = JavaString(string, environment: Self.env)
        return jstring.as(CharSequence.self)!
    }

    public func updateButton(
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

        // The same call AppKitBackend makes here as `button.appearance`. See
        // `setButtonColorScheme` for why the button needs telling separately
        // from the window.
        // 與 AppKitBackend 在此處呼叫 `button.appearance` 是同一件事。為何按鈕必須與視窗分開告知，
        // 見 `setButtonColorScheme`。
        helpers.setButtonColorScheme(button, environment.colorScheme == .dark)

        getTextStyle(from: environment).apply(to: button)
    }

    public func createTextView() -> Widget {
        AndroidKit.TextView(Self.activity, environment: Self.env)
    }

    public func updateTextView(
        _ textView: Widget,
        content: String,
        environment: EnvironmentValues
    ) {
        let textView = textView.as(AndroidKit.TextView.self)!
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
        let widget = createTextView()
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
        let heightSpec =
            if let proposedHeight {
                Int32(Double(proposedHeight) * environment.windowScaleFactor)
            } else {
                0x3FFFFFFF as Int32
            }

        widget.measure(widthSpec, heightSpec)
        let width = Double(widget.getMeasuredWidth()) / environment.windowScaleFactor
        let height = Double(widget.getMeasuredHeight()) / environment.windowScaleFactor
        return SIMD2(Int(width.rounded(.up)), Int(height.rounded(.up)))
    }

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
