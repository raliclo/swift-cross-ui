import CWinRT
import Foundation
@_spi(Backends) import SwiftCrossUI
import UWP
import WinAppSDK
import WinSDK
import WinUI
import WinUIInterop
@preconcurrency import WindowsFoundation
import Mutex

#if canImport(InputEvent)
    // The one symbol, not the whole module. InputEvent declares a `Point`, and so
    // does WindowsFoundation; a plain `import InputEvent` makes every unqualified
    // `Point` in this file ambiguous, which is 21 errors across the path-geometry
    // code that has nothing to do with action files. Narrowing the import is the
    // fix rather than qualifying twelve use sites, because only this one symbol
    // was ever wanted.
    import enum InputEvent.ActionFileReplay
#endif

// Many force tries are required for the WinUI backend but we don't really want them
// anywhere else so just disable the lint rule at a file level.
// swiftlint:disable force_try

extension App {
    public typealias Backend = WinUIBackend

    public var backend: WinUIBackend {
        WinUIBackend()
    }
}

class WinUIApplication: SwiftApplication, @unchecked Sendable {
    static let callback = Mutex<(@MainActor (WinUIApplication) -> Void)?>(nil)
    static let queuedURLs = Mutex<[URL]>([])
    /// Carries the incoming-URL handler across the `Mutex`.
    ///
    /// A box rather than the bare closure, because the closure is main-actor
    /// isolated -- `setIncomingURLHandler` is on a `@MainActor` type -- and
    /// `Mutex.withLock` hands out an `inout sending` parameter, which under the
    /// Swift 6 language mode refuses to hold isolated state. `nonisolated(unsafe)`
    /// on a local does not help here, which is worth recording: it works for a
    /// reference being passed along, as it does for the drag-and-drop captures,
    /// but it does not strip isolation from a function value's type.
    ///
    /// What the `@unchecked` asserts is the same invariant this file already
    /// relies on: the handler is only ever called from `receive(_:)`, whose only
    /// callers are WinUI application lifecycle callbacks on the UI thread.
    ///
    /// 用一個盒子而非裸露的 closure，因為該 closure 是 main-actor 隔離的——`setIncomingURLHandler`
    /// 所在的型別即是——而 `Mutex.withLock` 交出的是 `inout sending` 參數，在 Swift 6 語言模式下拒絕
    /// 持有受隔離的狀態。此處在區域變數上標 `nonisolated(unsafe)` 並無幫助，這點值得記錄：它對
    /// 「傳遞中的參考」有效（drag-and-drop 的那些捕獲即是），但無法把隔離從一個函式值的型別上剝除。
    ///
    /// `@unchecked` 所擔保的，正是本檔已然依賴的同一項不變式：該 handler 只會由 `receive(_:)`
    /// 呼叫，而其唯一的呼叫者是執行於 UI 執行緒的 WinUI application lifecycle callback。
    struct IncomingURLHandler: @unchecked Sendable {
        let handle: (URL) -> Void
    }

    static let onReceiveURL = Mutex<IncomingURLHandler?>(nil)

    override func onLaunched(_ args: WinUI.LaunchActivatedEventArgs) {
        if let url = Self.url(fromLaunchArguments: args.arguments) {
            Self.receive(url)
        }

        Self.callback.withLock { callback in
            // We can't explicitly hop to the main actor because we haven't set up
            // our WinUI MainActor fix yet.
            MainActor.assumeIsolated {
                callback?(self)
            }
        }
    }

    private static func receive(_ url: URL) {
        if let handler = onReceiveURL.withLock({ $0 }) {
            handler.handle(url)
        } else {
            queuedURLs.withLock { urls in
                urls.append(url)
            }
        }
    }

    private static func url(fromLaunchArguments arguments: String) -> URL? {
        let trimmed = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }

        for argument in CommandLine.arguments.dropFirst() {
            if let url = URL(string: argument), url.scheme != nil {
                return url
            }
        }

        return nil
    }
}

public final class WinUIBackend:
    BaseAppBackend,
    BackendFeatures.ApplicationMenus,
    BackendFeatures.ExternalURLs,
    BackendFeatures.IncomingURLs,
    BackendFeatures.FileDialogs,
    BackendFeatures.CornerRadius,
    BackendFeatures.Gestures,
    BackendFeatures.AttachedMenus,
    BackendFeatures.Paths,
    BackendFeatures.Tooltips,
    BackendFeatures.Colors,
    BackendFeatures.DatePickers,
    BackendFeatures.Windowing,
    BackendFeatures.WindowLevels,
    BackendFeatures.LinearGradients,
    BackendFeatures.RadialGradients
{
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

    public typealias Window = CustomWindow
    public typealias Widget = WinUI.FrameworkElement
    public typealias Menu = WinUI.MenuFlyout
    public typealias Path = GeometryGroupHolder

    public let defaultTableRowContentHeight = 20
    public let defaultTableCellVerticalPadding = 4
    public let defaultPaddingAmount = 10
    public let requiresToggleSwitchSpacer = false
    public let requiresImageUpdateOnScaleFactorChange = false
    public let supportsMultipleWindows = true
    public let deviceClass = DeviceClass.desktop
    public let supportedDatePickerStyles: [BackendDatePickerStyle] = [
        .automatic,
        .graphical,
        .compact,
        .wheel,
    ]
    public let supportedPickerStyles: [BackendPickerStyle] = [.menu, .radioGroup]
    public let canOverrideWindowColorScheme = true
    public let restoresWindowFrames = false

    /// Asked, not assumed. WinUI's `ScrollViewer` overlays its scroll bars by
    /// default and only reserves space for them when the system setting says to
    /// always show them, so a fixed number is wrong in both directions: it
    /// over-allocates for everyone who leaves the default on, and it is not the
    /// theme's number for anyone who turns it off.
    ///
    /// `UISettings.autoHideScrollBars` is the setting itself (Windows 10 1809
    /// and later). WinUIBackend already holds a `UISettings` for the
    /// colour-scheme subscription, which is what makes this cheap.
    ///
    /// The `12` that used to be here stays as the fallback rather than being
    /// deleted, for the case where the property cannot be read: it was the
    /// value shipped for months, so it is the known-survivable answer, and a
    /// guess of 0 would silently overlap content with the bar.
    ///
    /// GtkBackend measures a real `GtkScrollbar` for the same reason and
    /// AppKitBackend asks `NSScroller.preferredScrollerStyle`; this was the last
    /// hardcoded one.
    ///
    /// 這個值是問來的，不是假設的。WinUI 的 `ScrollViewer` 預設會將捲軸疊在內容之上，只有在系統
    /// 設定為「一律顯示捲軸」時才會為它保留空間，因此固定值在兩個方向上都是錯的：對維持預設的
    /// 使用者而言它多配置了空間，對關閉該設定的使用者而言它又不是主題的數值。
    ///
    /// `UISettings.autoHideScrollBars` 就是該設定本身（Windows 10 1809 以後）。WinUIBackend 為了
    /// 配色訂閱本就持有一個 `UISettings`，這使得此處的成本極低。
    ///
    /// 原本寫死的 `12` 保留為 fallback 而非刪除，用於無法讀取該屬性的情況：它是已經出貨數個月的
    /// 值，因此是「已知可存活」的答案；若改猜 0，內容會與捲軸靜默重疊。
    ///
    /// GtkBackend 基於相同理由實測一個真實的 `GtkScrollbar`，AppKitBackend 則詢問
    /// `NSScroller.preferredScrollerStyle`；此處是最後一個寫死的。
    /// A `Brush` for a fill style. Flat colours keep the `SolidColorBrush` they
    /// had, so the existing path is byte-for-byte the same work it was.
    /// 為填充樣式產生一個 `Brush`。平面色仍使用原本的 `SolidColorBrush`，因此既有路徑所做的事
    /// 與先前完全相同。
    static func brush(
        for style: ResolvedFillStyle,
        in environment: EnvironmentValues
    ) -> WinUI.Brush {
        func stops(_ gradient: SwiftCrossUI.Gradient) -> GradientStopCollection {
            let collection = GradientStopCollection()
            for stop in gradient.stops {
                let colour = stop.color.resolve(in: environment)
                let winUIStop = GradientStop()
                winUIStop.color = UWP.Color(
                    a: UInt8(colour.opacity * 255),
                    r: UInt8(colour.red * 255),
                    g: UInt8(colour.green * 255),
                    b: UInt8(colour.blue * 255)
                )
                winUIStop.offset = stop.location
                collection.append(winUIStop)
            }
            return collection
        }

        switch style {
            case .color(let resolved):
                return WinUI.SolidColorBrush(resolved.uwpColor)
            case .linearGradient(let gradient, let start, let end):
                let brush = LinearGradientBrush()
                brush.startPoint = WindowsFoundation.Point(
                    x: Float(start.x),
                    y: Float(start.y)
                )
                brush.endPoint = WindowsFoundation.Point(x: Float(end.x), y: Float(end.y))
                brush.gradientStops = stops(gradient)
                return brush
            case .radialGradient(let gradient, let centre, let startRadius, let endRadius):
                // `startRadius` cannot be carried. XAML's RadialGradientBrush
                // has a centre, a gradient origin and one radius pair -- there
                // is no inner radius, so a gradient asked to begin part-way out
                // starts at the centre here instead. Untested either way: P43
                // exercises linear only.
                //
                // Not silently dropped: a non-zero value says the caller wanted
                // something this backend cannot draw, and drawing a plausible
                // near-miss without saying so is the failure this project keeps
                // finding. Reported once.
                //
                // `startRadius` 無法被承載。XAML 的 RadialGradientBrush 只有中心、漸層原點與一組
                // 半徑——沒有內半徑，因此一個被要求「從中途開始」的漸層，在此會改從中心開始。
                // 兩種情況都尚未測試：P43 只涵蓋線性漸層。
                //
                // 但不是靜默丟棄：非零的值代表呼叫端要的東西是此 backend 畫不出來的，而畫出一個
                // 看似接近卻不說明的結果，正是本專案一再發現的那種失敗。只回報一次。
                if startRadius != 0 {
                    logger.notice(
                        """
                        WinUIBackend cannot express a radial gradient's startRadius \
                        (\(startRadius)); XAML has no inner radius, so the gradient \
                        starts at the centre instead.
                        """
                    )
                }
                let brush = RadialGradientBrush()
                brush.center = WindowsFoundation.Point(
                    x: Float(centre.x),
                    y: Float(centre.y)
                )
                // Double here, Float in Point just above. The projection is not
                // uniform and the compiler is the only thing that says which is
                // which, so do not copy one line's conversion onto another.
                // 此處是 Double，而緊鄰上方的 Point 是 Float。投影出來的型別並不一致，而唯一會說出
                // 哪個是哪個的只有編譯器，因此不要把某一行的轉換照抄到另一行。
                brush.radiusX = endRadius
                brush.radiusY = endRadius
                brush.gradientOrigin = WindowsFoundation.Point(
                    x: Float(centre.x),
                    y: Float(centre.y)
                )
                brush.spreadMethod = .pad
                // Appended, not assigned. `RadialGradientBrush.gradientStops` is
                // get-only where `LinearGradientBrush`'s is settable -- the two
                // brushes do not share this, which is why the linear case above
                // reads differently.
                // 用附加而非指派。`RadialGradientBrush.gradientStops` 是唯讀的，而
                // `LinearGradientBrush` 的可指派——兩種 brush 在這一點上並不相同，這也是上方
                // 線性分支寫法不同的原因。
                for stop in stops(gradient) {
                    brush.gradientStops.append(stop)
                }
                return brush
        }
    }

    public var scrollBarWidth: Int {
        let settings = uiSettings ?? UWP.UISettings()
        guard let autoHides = try? settings.autoHideScrollBars else {
            debugLogOnce("could not read UISettings.autoHideScrollBars; keeping the historical 12")
            return 12
        }
        return autoHides ? 0 : 12
    }

    /// One line per call site, so a value read on every layout pass does not
    /// fill the log. Mirrors `GtkBackend.debugLogOnce`, which exists because a
    /// branch that only runs on an unusual setting is otherwise a number nobody
    /// can see.
    /// 每個呼叫點只記錄一行，避免一個在每次版面計算都會被讀取的值塞爆日誌。形狀比照
    /// `GtkBackend.debugLogOnce`——它的存在理由是：一條只在罕見設定下才執行的分支，否則就是一個
    /// 沒人看得見的數字。
    private func debugLogOnce(
        _ message: String,
        file: String = #file,
        line: Int = #line
    ) {
        let location = "\(file):\(line)"
        if Self.scrollBarLogsPerformed.insert(location).inserted {
            logger.notice("\(message)")
        }
    }

    nonisolated(unsafe) private static var scrollBarLogsPerformed: Set<String> = []

    class InternalState {
        var buttonClickActions: [ObjectIdentifier: () -> Void] = [:]
        var toggleClickActions: [ObjectIdentifier: (Bool) -> Void] = [:]
        var switchClickActions: [ObjectIdentifier: (Bool) -> Void] = [:]
        var sliderChangeActions: [ObjectIdentifier: (Double) -> Void] = [:]
        var textFieldChangeActions: [ObjectIdentifier: (String) -> Void] = [:]
        var textFieldSubmitActions: [ObjectIdentifier: () -> Void] = [:]
        var textFieldContents: [ObjectIdentifier: String] = [:]
        var textEditorContents: [ObjectIdentifier: String] = [:]
    }
    private var rootEnvironmentChangeHandler: (@Sendable @MainActor () -> Void)?

    /// The `UISettings` the system-theme subscription is registered on.
    ///
    /// Held for as long as the backend, because the registration lives on this
    /// object: subscribing to a temporary means the only reference dies at the
    /// end of the statement, and with it the notification that the user switched
    /// the system between light and dark.
    ///
    /// 持有與 backend 同壽，因為該訂閱註冊在此物件上：對一個臨時物件訂閱，代表唯一的參照會在該
    /// 陳述式結束時消失，而「使用者在系統的淺色與深色之間切換」的通知也隨之消失。
    private var uiSettings: UWP.UISettings?

    var internalState: InternalState
    nonisolated(unsafe) private var dispatcherQueue: WinAppSDK.DispatcherQueue?

    var windows: [Window] = []

    private var measurementTextBlock: TextBlock!

    public init() {
        internalState = InternalState()
    }

    struct Error: LocalizedError {
        var message: String

        var errorDescription: String? {
            message
        }
    }

    public static func earlySetup() {
        do {
            try Self.attachToParentConsole()
        } catch {
            // We essentially just ignore if this fails because it's just a QoL
            // debugging feature, and if it fails then any warning we print likely
            // won't get seen anyway. But I don't trust my Windows knowledge enough
            // to assert that it's impossible to view logs on failure, so let's
            // print a warning anyway.
            logger.warning(
                "failed to attach to parent console",
                metadata: ["error": "\(error)"]
            )
        }
    }

    public func runMainLoop(_ callback: @escaping @MainActor () -> Void) {
        do {
            try Self.attachToParentConsole()
        } catch {
            // We essentially just ignore if this fails because it's just a QoL
            // debugging feature, and if it fails then any warning we print likely
            // won't get seen anyway. But I don't trust my Windows knowledge enough
            // to assert that it's impossible to view logs on failure, so let's
            // print a warning anyway.
            logger.warning(
                "failed to attach to parent console",
                metadata: ["error": "\(error)"]
            )
        }

        // Ensure that the app's windows adapt to DPI changes at runtime
        SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)

        WinUIApplication.callback.withLock { launchCallback in
            launchCallback = { application in
                // Toggle Switch has annoying default 'internal margins' (not Control
                // margins that we can set directly) that we can luckily get rid of by
                // overriding the relevant resource values.
                _ = application.resources.insert("ToggleSwitchPreContentMargin", 0.0 as Double)
                _ = application.resources.insert("ToggleSwitchPostContentMargin", 0.0 as Double)

                // Handle theme changes -- the user switching Windows between
                // light and dark while the app is running.
                //
                // The UISettings is kept in a property rather than created
                // inline. The subscription lives on the object, so a temporary
                // one is released at the end of the statement and the app stops
                // being told about theme changes; it then keeps whatever scheme
                // it read at launch until it is restarted.
                //
                // 處理主題變更——使用者在 app 執行期間將 Windows 於淺色與深色之間切換。
                //
                // UISettings 存放於屬性中，而非內聯建立。訂閱寄生於該物件上，因此臨時物件會在該
                // 陳述式結束時被釋放，app 便不再收到主題變更通知；此後它會一直沿用啟動時讀到的
                // 配色，直到重新啟動為止。
                let uiSettings = UWP.UISettings()
                self.uiSettings = uiSettings
                uiSettings.colorValuesChanged.addHandler { _, _ in
                    Task { @MainActor in
                        self.rootEnvironmentChangeHandler?()
                    }
                }

                // TODO: Read in previously hardcoded values from the application's
                // resources dictionary for future-proofing. Example code for getting
                // property values;
                //   let iinspectable =
                //       application.resources.lookup("ToggleSwitchPreContentMargin")!
                //       as! WindowsFoundation.IInspectable
                //   let pv: __ABI_Windows_Foundation.IPropertyValue = try! iinspectable.QueryInterface()
                //   let value = try! pv.GetDoubleImpl()

                self.measurementTextBlock = (self.createTextView() as! TextBlock)

                callback()
            }
        }
        WinUIApplication.main()
    }

    public func createWindow(withDefaultSize size: SIMD2<Int>?, id: String) -> Window {
        let window = CustomWindow()
        windows.append(window)
        window.closed.addHandler { _, _ in
            self.windows.removeAll { other in
                window === other
            }
        }

        if self.dispatcherQueue == nil {
            self.dispatcherQueue = window.dispatcherQueue
        }

        window.installSizeLimitHandler()

        if let size {
            setSize(ofWindow: window, to: size)
        }
        return window
    }

    public func updateWindow(_ window: Window, environment: EnvironmentValues) {
        window.menuBar.requestedTheme = switch environment.colorScheme {
            case .light: .light
            case .dark: .dark
        }

        window.grid.background = windowBackgroundBrush(for: environment)

        applyTitleBarColors(to: window, environment: environment)
    }

    /// The platform's own window background, falling back to plain black or
    /// white if it cannot be found.
    ///
    /// This used to be `.white` and `.black` unconditionally, and it made
    /// WinUIBackend the odd one out: AppKitBackend and GtkBackend both leave a
    /// window's background to the platform, which is also what SwiftUI does.
    /// The mismatch became visible once the title bar started inheriting its
    /// colours -- the bar came out at Windows' own #202020 while the content
    /// behind it was pure black, two shades of "dark" in one window because one
    /// was inherited and one was chosen here.
    ///
    /// `ApplicationPageBackgroundThemeBrush` is the resource WinUI's own pages
    /// use, so it is the same surface colour every other Windows app has, and it
    /// resolves per theme without this needing to know either value.
    ///
    /// The fallback is not defensive padding. A missing resource would otherwise
    /// leave the Grid transparent -- WinUI gives it no background of its own --
    /// and a window showing the desktop through its content is far worse than
    /// one whose black is a shade off.
    ///
    /// 平台自身的視窗背景；若找不到，則退回純黑或純白。
    ///
    /// 此處原本無條件使用 `.white` 與 `.black`，而這使 WinUIBackend 成為異類：AppKitBackend 與
    /// GtkBackend 都把視窗背景交給平台，SwiftUI 亦然。此一落差在標題列開始繼承其色彩之後便顯而易見
    /// ——標題列呈現 Windows 自有的 #202020，而其後方的內容卻是純黑；同一個視窗中出現兩種「深色」，
    /// 只因其一是繼承而來、其一是在此處選定的。
    ///
    /// `ApplicationPageBackgroundThemeBrush` 是 WinUI 自身頁面所使用的資源，因此它與 Windows 上
    /// 其他每一個 app 的表面色相同，且會依主題自行解析，無需此處知道任何一個色值。
    ///
    /// 該退路並非防禦性的填充。若資源缺失而不予處理，Grid 會維持透明——WinUI 不會給它自己的背景
    /// ——而一個「內容處可看見桌面」的視窗，遠比一個「黑得略有偏差」的視窗糟糕得多。
    private func windowBackgroundBrush(for environment: EnvironmentValues) -> WinUI.Brush {
        if let application = WinUI.Application.current,
            let themed = application.resources.lookup("ApplicationPageBackgroundThemeBrush")
                as? WinUI.Brush
        {
            return themed
        }

        let fallback: SwiftCrossUI.Color = switch environment.colorScheme {
            case .light: .white
            case .dark: .black
        }
        let brush = WinUI.SolidColorBrush()
        brush.color = fallback.resolve(in: environment).uwpColor
        return brush
    }

    /// Makes the title bar follow the same colour scheme as the content.
    ///
    /// Without this a dark app keeps a light title bar with dark buttons, which
    /// is the one part of the window that visibly did not get the message.
    ///
    /// No API of its own, deliberately, because SwiftUI has none: a window's
    /// chrome there follows the app's colour scheme and there is nothing to
    /// call. So this reads the scheme SwiftCrossUI has already resolved --
    /// including `preferredColorScheme` and the ambient system one -- rather
    /// than adding a modifier for it.
    ///
    /// The same `.white`/`.black` the content background uses, so the bar and
    /// the view under it cannot disagree. The button colours have to be set
    /// separately: the title bar does not derive them from its own background,
    /// and left alone they stay at the system default, which is the light pair.
    ///
    /// 讓標題列跟隨與內容相同的色彩配置。
    ///
    /// 若不這麼做，深色 app 會維持一條淺色標題列與深色按鈕，成為整個視窗中唯一「顯然沒有收到通知」
    /// 的部分。
    ///
    /// 刻意不提供專屬 API，因為 SwiftUI 也沒有：在 SwiftUI 中，視窗裝飾會跟隨 app 的色彩配置，沒有
    /// 任何東西可呼叫。因此此處讀取 SwiftCrossUI 已解析完成的配置——包含 `preferredColorScheme`
    /// 與環境系統配置——而非為它新增一個修飾器。
    ///
    /// 使用與內容背景相同的 `.white`/`.black`，使標題列與其下方的視圖不可能不一致。按鈕色彩必須另外
    /// 設定：標題列不會從自身背景推導它們，放著不管就會停留在系統預設，也就是淺色那一組。
    private func applyTitleBarColors(to window: Window, environment: EnvironmentValues) {
        window.grid.requestedTheme = switch environment.colorScheme {
            case .light: .light
            case .dark: .dark
        }

        // Cleared, not set. Every colour here is left at the system default so
        // Windows draws its own chrome for that theme -- #202020 and its own
        // hover and pressed shades -- rather than whatever this file thought a
        // dark title bar looks like.
        //
        // The first version painted them explicitly, in pure black and white,
        // and it worked: the bar went dark. It was still wrong. Pure black is
        // not the colour Windows uses, and a title bar that is blacker than
        // every other window's is a thing an app has decided rather than a thing
        // it has inherited. AppKitBackend and GtkBackend both already leave the
        // window background to the platform; WinUIBackend hardcoding `.white`
        // and `.black` for its own is the odd one out, and this at least does
        // not extend that to the chrome.
        //
        // 是「清除」而非「設定」。此處每一個顏色都保持系統預設，好讓 Windows 為該主題繪製它自己的
        // 視窗裝飾——#202020 及其自有的 hover 與 pressed 色階——而不是由本檔認定「深色標題列該長
        // 什麼樣」。
        //
        // 第一版是明確指定顏色的，用純黑與純白，而且它確實有效：標題列變深色了。但它仍然是錯的。
        // 純黑並非 Windows 所使用的顏色，而一條比其他所有視窗都更黑的標題列，是 app「決定」出來的，
        // 而非「繼承」而來的。AppKitBackend 與 GtkBackend 本來就把視窗背景交給平台；
        // WinUIBackend 為自身視窗寫死 `.white` 與 `.black` 是其中的異類，而此處至少不把那份異類
        // 延伸到視窗裝飾上。
        guard let titleBar = window.appWindow.titleBar else { return }
        titleBar.backgroundColor = nil
        titleBar.foregroundColor = nil
        titleBar.inactiveBackgroundColor = nil
        titleBar.inactiveForegroundColor = nil
        titleBar.buttonBackgroundColor = nil
        titleBar.buttonForegroundColor = nil
        titleBar.buttonInactiveBackgroundColor = nil
        titleBar.buttonInactiveForegroundColor = nil
        titleBar.buttonHoverBackgroundColor = nil
        titleBar.buttonHoverForegroundColor = nil
        titleBar.buttonPressedBackgroundColor = nil
        titleBar.buttonPressedForegroundColor = nil
    }

    public func size(ofWindow window: Window) -> SIMD2<Int> {
        let size = window.appWindow.clientSize
        let scaleFactor = window.scaleFactor
        let width = Double(size.width) / scaleFactor
        let height = Double(size.height) / scaleFactor
        let out = SIMD2(
            Int(width.rounded(.towardZero)),
            Int(height.rounded(.towardZero)) - window.contentHeightAdjustment
        )
        return out
    }

    public func isWindowProgrammaticallyResizable(_ window: Window) -> Bool {
        // TODO: Detect whether window is fullscreen
        return true
    }

    public func setSize(ofWindow window: Window, to newSize: SIMD2<Int>) {
        let scaleFactor = window.scaleFactor
        let width = scaleFactor * Double(newSize.x)
        let height = scaleFactor * Double(newSize.y + window.contentHeightAdjustment)
        let size = UWP.SizeInt32(
            width: Int32(width.rounded(.towardZero)),
            height: Int32(height.rounded(.towardZero))
        )
        try! window.appWindow.resizeClient(size)
    }

    public func setSizeLimits(
        ofWindow window: Window,
        minimum minimumSize: SIMD2<Int>,
        maximum maximumSize: SIMD2<Int>?
    ) {
        window.minimumContentSize = minimumSize
        window.maximumContentSize = maximumSize
    }

    public func setResizeHandler(
        ofWindow window: Window,
        to action: @escaping (SIMD2<Int>) -> Void
    ) {
        window.sizeChanged.addHandler { _, args in
            let size = SIMD2(
                Int(args!.size.width.rounded(.awayFromZero)),
                Int(args!.size.height.rounded(.awayFromZero)) - window.contentHeightAdjustment
            )
            action(size)
        }
    }

    public func setTitle(ofWindow window: Window, to title: String) {
        window.title = title
    }

    public func setBehaviors(
        ofWindow window: Window,
        closable: Bool,
        minimizable: Bool,
        resizable: Bool
    ) {
        // Source: https://devblogs.microsoft.com/oldnewthing/20100604-00/?p=13803
        let hwnd = window.getHWND()!
        let flags = if closable { MF_ENABLED } else { MF_DISABLED | MF_GRAYED }
        EnableMenuItem(
            GetSystemMenu(hwnd, false),
            numericCast(SC_CLOSE),
            numericCast(MF_BYCOMMAND | flags)
        )

        (window.appWindow.presenter as? OverlappedPresenter)?.isMinimizable = minimizable
        (window.appWindow.presenter as? OverlappedPresenter)?.isResizable = resizable
    }

    /// Every level, because WinUI has an API for the only one that is hard.
    ///
    /// `OverlappedPresenter.isAlwaysOnTop` is the framework's own switch for it,
    /// so no `SetWindowPos` and no `HWND` are needed here -- and unlike a raw
    /// `HWND_TOPMOST`, the presenter reapplies it when it re-places the window,
    /// so it does not have to be re-asserted after a resize.
    ///
    /// 支援全部 level，因為 WinUI 為其中唯一困難的那一個提供了 API。
    ///
    /// `OverlappedPresenter.isAlwaysOnTop` 就是該框架自己的開關，因此此處不需要 `SetWindowPos`，
    /// 也不需要 `HWND`——而且與裸的 `HWND_TOPMOST` 不同，presenter 會在重新擺放視窗時一併重新套用，
    /// 因此無需在調整尺寸後再次宣告。
    public let supportedWindowLevels: [WindowLevel] = [.automatic, .normal, .floating]

    public func setLevel(ofWindow window: Window, to level: WindowLevel) {
        (window.appWindow.presenter as? OverlappedPresenter)?.isAlwaysOnTop = level == .floating
    }

    public func setChild(ofWindow window: Window, to widget: Widget) {
        window.setChild(widget)
        try! widget.updateLayout()
        widget.actualThemeChanged.addHandler { _, _ in
            Task { @MainActor in
                self.rootEnvironmentChangeHandler?()
            }
        }
    }

    public func show(window: Window) {
        try! window.activate()

        #if canImport(InputEvent)
            if ActionFileReplay.requestedFile != nil {
                FileHandle.standardError.write(
                    Data("-actionfile: WinUIBackend show(window:) scheduling replay\n".utf8)
                )
            }
            // Only ever fires for the first window, and only when -actionfile
            // was passed. See InputEvent's ActionFileReplay.
            //
            // WinUIBackend had no -actionfile support at all. The flag was
            // parsed inside GtkBackend, so Win32Synthesiser -- a Windows
            // implementation -- was reachable only by running the GTK backend
            // on Windows, and an app on this backend ignored the flag in
            // silence. Which backend a Windows build defaults to does not
            // change that: a backend that quietly does nothing with a flag it
            // was given is the inconsistency, whether or not it is the one
            // usually chosen.
            //
            // 僅對第一個視窗生效，且僅在有傳入 -actionfile 時。詳見 InputEvent 的 ActionFileReplay。
            //
            // WinUIBackend 過去完全沒有 -actionfile 支援。該旗標是在 GtkBackend 內解析的，因此
            // Win32Synthesiser——一個 Windows 實作——只能透過「在 Windows 上執行 GTK backend」才取用
            // 得到，而在本 backend 上執行的 app 會靜默地忽略該旗標。Windows 建置預設採用哪個
            // backend 並不改變這件事：一個 backend 收到旗標卻安靜地什麼也不做，本身就是不一致，
            // 無論它是不是通常被選用的那一個。
            ActionFileReplay.replayIfRequested()
        #endif
    }

    public func activate(window: Window) {
        try! window.activate()
    }

    public func close(window: Window) {
        try! window.close()
    }

    public func setCloseHandler(
        ofWindow window: Window,
        to action: @escaping () -> Void
    ) {
        window.closed.addHandler { _, _ in
            action()
        }
    }

    public func openExternalURL(_ url: URL) throws {
        let promise = UWP.Launcher.launchUriAsync(WindowsFoundation.Uri(url.absoluteString))!
        let semaphore = DispatchSemaphore(value: 0)
        promise.completed = { _, status in
            semaphore.signal()

            if status != .completed {
                logger.warning("Failed to open external URL \(url)")
            }
        }

        // Block until the URL has been launched
        semaphore.wait()
    }

    public func runInMainThread(action: @escaping @MainActor () -> Void) {
        _ = try! dispatcherQueue!.tryEnqueue(.normal) {
            MainActor.assumeIsolated(action)
        }
    }

    public func show(widget _: Widget) {}

    private func renderMenuItem(
        _ item: ResolvedMenu.Item,
        environment: EnvironmentValues
    ) -> MenuFlyoutItemBase {
        switch item {
            case .button(let label, let action):
                let widget = MenuFlyoutItem()
                widget.text = label
                widget.click.addHandler { _, _ in
                    action?()
                }
                widget.isEnabled = environment.isEnabled
                return widget
            case .toggle(let label, let value, let onChange):
                let widget = ToggleMenuFlyoutItem()
                widget.text = label
                widget.isChecked = value
                widget.click.addHandler { [weak widget] _, _ in
                    guard let widget else { return }
                    onChange(widget.isChecked)
                }
                widget.isEnabled = environment.isEnabled
                return widget
            case .separator:
                return MenuFlyoutSeparator()
            case .submenu(let submenu):
                let widget = MenuFlyoutSubItem()
                widget.text = submenu.label
                for subitem in submenu.content.items {
                    widget.items.append(
                        renderMenuItem(subitem, environment: environment)
                    )
                }
                return widget
            case .modifiedEnvironment(let item, let modification):
                return renderMenuItem(item, environment: modification(environment))
        }
    }

    public func setApplicationMenu(
        _ submenus: [ResolvedMenu.Submenu],
        environment: EnvironmentValues
    ) {
        let items = submenus.map { submenu in
            let item = MenuBarItem()
            item.title = submenu.label
            for subitem in submenu.content.items {
                item.items.append(
                    renderMenuItem(subitem, environment: environment)
                )
            }
            return item
        }

        for window in windows {
            window.menuBar.items.clear()
            for item in items {
                window.menuBar.items.append(item)
            }
            window.setMenuBarVisible(!items.isEmpty)
            window.menuBar.requestedTheme = .dark
        }
    }

    public func computeRootEnvironment(
        defaultEnvironment: EnvironmentValues
    ) -> EnvironmentValues {
        // Source: https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/ui/apply-windows-themes#know-when-dark-mode-is-enabled
        let backgroundColor = try! UWP.UISettings().getColorValue(.background)

        let green = Int(backgroundColor.g)
        let red = Int(backgroundColor.r)
        let blue = Int(backgroundColor.b)
        let isLight = 5 * green + 2 * red + blue > 8 * 128

        return
            defaultEnvironment
                .with(\.colorScheme, isLight ? .light : .dark)
                .with(\.appPhase, windows.contains(where: \.isActive) ? .active : .inactive)
    }

    public func setRootEnvironmentChangeHandler(
        to action: @escaping @Sendable @MainActor () -> Void
    ) {
        self.rootEnvironmentChangeHandler = action
    }

    public func computeWindowEnvironment(
        window: Window,
        rootEnvironment: EnvironmentValues
    ) -> EnvironmentValues {
        // `window.scaleFactor` already existed and was already computed from
        // `GetDpiForMonitor`; it just was not being written anywhere. The TODO
        // that used to be here said the value was easy but keeping it current
        // was annoying, and stopped at neither -- so the environment carried 1
        // on every display, which is not a stale value but a wrong one.
        //
        // Correct at window creation is strictly better than always 1: `Image`
        // re-renders when this changes, so on a 150% display it was rendering
        // at the wrong scale from the first frame rather than after a move.
        // Keeping it current is the remaining half; see
        // `setWindowEnvironmentChangeHandler` below.
        //
        // `window.scaleFactor` 早已存在，也早已由 `GetDpiForMonitor` 算好，只是從未被寫到任何地方。
        // 原本此處的 TODO 說「值很好取，但要保持更新很麻煩」，結果兩件事都沒做——於是 environment
        // 在任何顯示器上都帶著 1，那不是一個過期的值，而是一個錯的值。
        //
        // 「在建立視窗時正確」嚴格優於「永遠是 1」：`Image` 會在此值變動時重新繪製，因此在 150%
        // 的顯示器上，它從第一個 frame 起就以錯誤的比例繪製，而不是在視窗被移動之後才出錯。保持
        // 更新是剩下的那一半，見下方的 `setWindowEnvironmentChangeHandler`。
        rootEnvironment
            .with(\.scenePhase, window.isActive ? .active : .inactive)
            .with(\.windowScaleFactor, window.scaleFactor)
    }

    public func setWindowEnvironmentChangeHandler(
        of window: Window,
        to action: @escaping @Sendable @MainActor () -> Void
    ) {
        // TODO: Notify when window scale factor changes

        // NB: This event fires when the window is activated _or_ deactivated.
        window.activated.addHandler { _, _ in
            if let rootHandler = self.rootEnvironmentChangeHandler {
                rootHandler()
                // Don't bother calling `action` since this window's environment
                // will be recomputed anyway.
            } else {
                action()
            }
        }
    }

    public func setIncomingURLHandler(to action: @escaping (URL) -> Void) {
        WinUIApplication.queuedURLs.withLock { urls in
            for url in urls {
                action(url)
            }
            urls = []
        }

        // Boxed rather than stored bare; see `IncomingURLHandler` for why the
        // closure cannot cross `Mutex.withLock` on its own.
        // 以盒子包裝而非直接存入；closure 為何無法自行跨越 `Mutex.withLock`，見 `IncomingURLHandler`。
        let boxed = WinUIApplication.IncomingURLHandler(handle: action)
        WinUIApplication.onReceiveURL.withLock { handler in
            handler = boxed
        }
    }

    public func createContainer() -> Widget {
        Canvas()
    }

    public func removeAllChildren(of container: Widget) {
        let container = container as! Canvas
        container.children.clear()
    }

    public func insert(_ child: Widget, into container: Widget, at index: Int) {
        let container = container as! Canvas
        container.children.insertAt(UInt32(index), child)
    }

    public func swap(childAt firstIndex: Int, withChildAt secondIndex: Int, in container: Widget) {
        // TODO: Find out if there's an efficient way to do this without WinUI
        //   getting annoyed at us for having the same element in the list twice.
        let container = container as! Canvas
        let largerIndex = UInt32(max(firstIndex, secondIndex))
        let smallerIndex = UInt32(min(firstIndex, secondIndex))
        let element1 = container.children[Int(smallerIndex)]
        let element2 = container.children[Int(largerIndex)]
        container.children.removeAt(largerIndex)
        container.children.removeAt(smallerIndex)
        container.children.insertAt(smallerIndex, element2)
        container.children.insertAt(largerIndex, element1)
    }

    public func remove(childAt index: Int, from container: Widget) {
        let container = container as! Canvas
        container.children.removeAt(UInt32(index))
    }

    public func setPosition(ofChildAt index: Int, in container: Widget, to position: SIMD2<Int>) {
        let container = container as! Canvas
        guard let child = container.children.getAt(UInt32(index)) else {
            logger.warning("child to set position of not found")
            return
        }

        Canvas.setTop(child, Double(position.y))
        Canvas.setLeft(child, Double(position.x))
    }

    public func createColorableRectangle() -> Widget {
        Canvas()
    }

    public func setColor(
        ofColorableRectangle widget: Widget,
        to color: SwiftCrossUI.Color.Resolved
    ) {
        let canvas = widget as! Canvas
        let brush = WinUI.SolidColorBrush()
        brush.color = color.uwpColor
        canvas.background = brush
    }

    public func createCornerRadiusContainer(wrapping child: Widget) -> Widget {
        child
    }

    public func setCornerRadius(of widget: Widget, to radius: Int) {
        let visual: WinAppSDK.Visual = try! widget.getVisualInternal()

        let geometry = try! visual.compositor.createRoundedRectangleGeometry()!
        geometry.cornerRadius = WindowsFoundation.Vector2(
            x: Float(radius),
            y: Float(radius)
        )

        // We assume that SwiftCrossUI has explicitly set the size of the
        // underlying widget.
        geometry.size = WindowsFoundation.Vector2(
            x: Float(widget.width),
            y: Float(widget.height)
        )

        let clip = try! visual.compositor.createGeometricClip()!
        clip.geometry = geometry

        visual.clip = clip
    }

    public func naturalSize(of widget: Widget) -> SIMD2<Int> {
        Self.naturalSize(of: widget)
    }

    /// A static version of `naturalSize(of:)` for convenience. Used by
    /// WinUIElementRepresentable.
    @MainActor
    public static func naturalSize(of widget: Widget) -> SIMD2<Int> {
        let allocation = WindowsFoundation.Size(
            width: .infinity,
            height: .infinity
        )

        // Some elements don't return any sort of sensible measurement before
        // they've been rendered. For said elements, we just compute their sizes
        // as best we can by roughly replicating WinUI's internal calculations.
        let noPadding = Thickness(left: 0, top: 0, right: 0, bottom: 0)
        if widget is WinUI.Slider {
            // As with buttons, slider sizing also doesn't work before the first
            // view update. The width and height I've hardcoded here were taken
            // from the WinUI source code: https://github.com/microsoft/microsoft-ui-xaml/blob/650b2c1bad272393400403ca323b3cb8745f95d0/src/controls/dev/CommonStyles/Slider_themeresources.xaml#L169
            return SIMD2(
                18 + 8,
                18 + 8
            )
        } else if widget is WinUI.ToggleSwitch {
            // WinUI sets the min-width of switches to 154 for whatever reason,
            // and I don't know how to override that default from Swift, so I'm
            // just hardcoding the size. This keeps getting jankier and
            // jankier...
            return SIMD2(
                40,
                20
            )
        } else if widget is CustomCheckBox {
            // WinUI sets quite a strange default size for checkboxes (with a
            // minimum width of 120), so we just hardcode the correct natural
            // size. The value 20 was taken from the WinUI source code:
            // https://github.com/microsoft/microsoft-ui-xaml/blob/d37afef65a0fc3219ba6b349301d685099fb129d/src/controls/dev/CommonStyles/CheckBox_themeresources.xaml#L270
            return SIMD2(20, 20)
        } else if let picker = widget as? CustomComboBox, picker.padding == noPadding {
            // Pickers can be measured before their options are populated. Use
            // WinUI's minimum picker height and a small default width until a
            // real label exists.
            guard !picker.options.isEmpty else {
                return SIMD2(50, 32)
            }
            let label = TextBlock()
            // A ComboBox can briefly report -1 or a stale index while its item
            // collection is being rebuilt.
            let selectedIndex = min(Int(max(picker.selectedIndex, 0)), picker.options.count - 1)
            label.text = picker.options[selectedIndex]
            label.fontSize = picker.fontSize
            label.fontWeight = picker.fontWeight
            try! label.measure(allocation)

            // These padding values were gathered experimentally. I've found that
            // WinUI generally hardcodes padding, border thickness and such in its
            // default theme, so I feel it's safe enough to use this workaround for
            // now (until https://github.com/microsoft/microsoft-ui-xaml/issues/10278
            // gets an answer).
            let labelSize = label.desiredSize
            return SIMD2(
                Int(labelSize.width) + 50,
                // The default minimum picker height is 32 pixels
                max(Int(labelSize.height) + 12, 32)
            )
        } else if widget is ProgressRing {
            // ProgressRing appears to kind of grow to fill by default, but
            // SwiftCrossUI expects progress spinners to be fixed size, which
            // results in WinUI progress rings getting given astronomically
            // large fixed dimensions and causing crashes. To work around that,
            // we just override their 'natural size' to 32x32, which is based off
            // the defaults set in the following code from the WinUI repository:
            // https://github.com/marcelwgn/microsoft-ui-xaml/blob/ff21f9b212cea2191b959649e45e52486c8465aa/src/controls/dev/ProgressRing/ProgressRing.xaml#L12
            return SIMD2(32, 32)
        } else if let datePicker = widget as? CustomDatePicker {
            // CustomDatePicker is a StackPanel whose individual subviews need to be manually sized
            // and then added together. Its naturalSize(in:) method dispatches back here once for
            // each of its children.
            return datePicker.naturalSize()
        } else if widget is WinUI.DatePicker {
            // Width is 296:
            // https://github.com/marcelwgn/microsoft-ui-xaml/blob/ff21f9b212cea2191b959649e45e52486c8465aa/src/controls/dev/CommonStyles/DatePicker_themeresources.xaml#L261
            // Height is experimentally 29 which I don't see anywhere in that file.
            return SIMD2(296, 29)
        }

        let oldWidth = widget.width
        let oldHeight = widget.height
        defer {
            widget.width = oldWidth
            widget.height = oldHeight
        }

        widget.width = .nan
        widget.height = .nan

        try! widget.measure(allocation)

        let computedSize = widget.desiredSize
        let adjustment = sizeCorrection(for: widget)

        let out = SIMD2(
            Int(computedSize.width) + adjustment.x,
            Int(computedSize.height) + adjustment.y
        )

        return out
    }

    /// Some elements don't get their default padding/border applied until
    /// they've been rendered. For such elements we have to compute our own
    /// adjustment factors based off values taken from WinUI's default theme.
    /// We can detect such elements because their padding property will be set
    /// to zero until first render (and atm WinUIBackend doesn't set this padding
    /// property itself so this is a safe detection method).
    @MainActor
    public static func sizeCorrection(for widget: Widget) -> SIMD2<Int> {
        let adjustment: SIMD2<Int>
        let noPadding = Thickness(left: 0, top: 0, right: 0, bottom: 0)
        let computedSize = widget.desiredSize
        if let button = widget as? WinUI.Button, button.padding == noPadding {
            // WinUI buttons have padding, but the `padding` property returns
            // zero until the button has been rendered at least once. And even
            // if you manually set the button's padding, it gets ignored by
            // `measure()` before first render.
            //
            // The default in my Windows 11 VM seems to be 11 pixels either
            // side, 5 pixels above, and 6 pixels below. I found this hardcoded
            // in the WinUI repository, so hopefully it is the same everywhere...
            // Hardcoded here: https://github.com/microsoft/microsoft-ui-xaml/blob/650b2c1bad272393400403ca323b3cb8745f95d0/src/controls/dev/CommonStyles/Button_themeresources.xaml#L116
            //
            // We'll have to find a more dynamic way of correcting for WinUI's
            // measurement weirdness at some point (which will probably involve
            // figuring out how to access the `ButtonPadding` resource value
            // from Swift).
            //
            // Buttons seem to have 1 pixel of border on each side which also
            // gets ignored before first render.
            adjustment = SIMD2(
                11 + 11 + 2,
                5 + 6 + 2
            )
        } else if let toggleButton = widget as? WinUI.ToggleButton,
                  toggleButton.padding == noPadding
        {
            // See the above comment regarding Button. Very similar situation.
            adjustment = SIMD2(
                11 + 11 + 2,
                5 + 6 + 2
            )
        } else if let textField = widget as? TextBoxProtocol, textField.padding == noPadding {
            // The default padding applied to text boxes can be found here:
            // https://github.com/microsoft/microsoft-ui-xaml/blob/650b2c1bad272393400403ca323b3cb8745f95d0/src/controls/dev/CommonStyles/Common_themeresources.xaml#L12
            // However, text fields return 0x0 before rendering so our adjustment
            // just has to be the entire size of the text field. I've currently just
            // hardcoded a value obtained from one of my example apps.
            adjustment = SIMD2(64, 32)
        } else if widget is CalendarView {
            if computedSize.width == 0 && computedSize.height == 0 {
                // CalendarView can report 0x0 before its template has been rendered.
                // If SwiftCrossUI trusts that, the graphical DatePicker style gets
                // committed as a blank sliver. The fallback is sized for the default
                // month view: 7 columns, 6 weeks, and the header/navigation row.
                adjustment = SIMD2(320, 300)
            } else {
                // I don't actually know why this is necessary, but without it the
                // abbreviations for the weekdays wrap, making it taller than it says
                // it is. Value was derived by trial and error.
                adjustment = SIMD2(20, 0)
            }
        } else if
            computedSize.width == 0 && computedSize.height == 0 && widget is CalendarDatePicker
        {
            // I can't find any source on what the size of CalendarDatePicker is, but it reports 0x0
            // in at least some cases before initial render. In these cases, use a size derived
            // experimentally.
            adjustment = SIMD2(116, 32)
        } else {
            adjustment = .zero
        }
        return adjustment
    }

    public func setSize(of widget: Widget, to size: SIMD2<Int>) {
        widget.width = Double(size.x)
        widget.height = Double(size.y)
    }

    public func createTooltipContainer(wrapping child: Widget) -> Widget {
        // TODO(bbrk24): Look into removing the container, like on AppKit
        TooltipContainer(child: child)
    }

    public func updateTooltipContainer(_ widget: Widget, tooltip: String) {
        let widget = widget as! TooltipContainer
        widget.tooltip.content = tooltip
    }

    public func size(
        of text: String,
        whenDisplayedIn widget: Widget,
        proposedWidth: Int?,
        proposedHeight: Int?,
        environment: EnvironmentValues
    ) -> SIMD2<Int> {
        // Update the text view's environment and measure its desired line height
        updateTextView(measurementTextBlock, content: text, environment: environment)

        // Measure the text's size
        var size = Self.measure(
            measurementTextBlock,
            proposedWidth: proposedWidth,
            proposedHeight: proposedHeight
        )

        var usedHeight = size.y
        let lineHeight = environment.resolvedFont.lineHeight

        if let lineLimitSettings = environment.lineLimitSettings {
            let height = Int(
                Double(max(lineLimitSettings.limit, 1)) * lineHeight
            )

            if height < usedHeight || lineLimitSettings.reservesSpace {
                usedHeight = height
            }
        }

        // Make sure the text doesn't get shorter than a single line of text even if
        // it's empty.
        size.y = max(usedHeight, Int(lineHeight))
        return size
    }

    private static func measure(
        _ textBlock: TextBlock,
        proposedWidth: Int?,
        proposedHeight: Int?
    ) -> SIMD2<Int> {
        let allocation = WindowsFoundation.Size(
            width: proposedWidth.map(Float.init) ?? .infinity,
            height: proposedHeight.map(Float.init) ?? .infinity
        )
        try! textBlock.measure(allocation)

        let computedSize = textBlock.desiredSize
        return SIMD2(
            Int(computedSize.width),
            Int(computedSize.height)
        )
    }

    public func createTextView() -> Widget {
        let textBlock = TextBlock()
        textBlock.textWrapping = .wrap
        textBlock.textTrimming = .characterEllipsis
        textBlock.lineStackingStrategy = .blockLineHeight
        return textBlock
    }

    public func updateTextView(
        _ textView: Widget,
        content: String,
        environment: EnvironmentValues
    ) {
        let block = textView as! TextBlock
        block.text = content
        block.isTextSelectionEnabled = environment.isTextSelectionEnabled
        // TODO: Font design handling (monospace vs normal)
        environment.apply(to: block)
    }

    public func createButton() -> Widget {
        let button = CustomButton()
        button.content = button.label
        button.click.addHandler { [weak internalState] _, _ in
            guard let internalState else { return }
            internalState.buttonClickActions[ObjectIdentifier(button)]?()
        }
        return button
    }

    public func updateButton(
        _ button: Widget,
        label: String,
        environment: EnvironmentValues,
        action: @escaping () -> Void
    ) {
        let button = button as! CustomButton
        if button.label.text != label {
            button.label.text = label
        }
        environment.apply(to: button.label)
        environment.apply(to: button)
        internalState.buttonClickActions[ObjectIdentifier(button)] = action
    }

    public func createPopoverMenu() -> Menu {
        let flyout = MenuFlyout()
        flyout.placement = .bottomEdgeAlignedLeft
        return flyout
    }

    public func updatePopoverMenu(
        _ menu: Menu,
        content: ResolvedMenu,
        environment: EnvironmentValues
    ) {
        menu.items.clear()
        for item in content.items {
            menu.items.append(renderMenuItem(item, environment: environment))
        }
    }

    public func updateButton(
        _ button: Widget,
        label: String,
        menu: Menu,
        environment: EnvironmentValues
    ) {
        let button = button as! CustomButton
        if button.label.text != label {
            button.label.text = label
        }
        environment.apply(to: button.label)
        environment.apply(to: button)
        button.flyout = menu
    }

    public func createScrollContainer(for child: Widget) -> Widget {
        let scrollViewer = WinUI.ScrollViewer()
        scrollViewer.content = child
        child.horizontalAlignment = .left
        child.verticalAlignment = .top
        return scrollViewer
    }

    public func updateScrollContainer(
        _ scrollView: Widget,
        environment: EnvironmentValues,
        bounceHorizontally: Bool,
        bounceVertically: Bool,
        hasHorizontalScrollBar: Bool,
        hasVerticalScrollBar: Bool
    ) {
        let scrollViewer = scrollView as! WinUI.ScrollViewer

        scrollViewer.isHorizontalRailEnabled = hasHorizontalScrollBar
        scrollViewer.horizontalScrollMode = hasHorizontalScrollBar ? .enabled : .disabled
        scrollViewer.horizontalScrollBarVisibility = hasHorizontalScrollBar ? .visible : .hidden

        scrollViewer.isVerticalRailEnabled = hasVerticalScrollBar
        scrollViewer.verticalScrollMode = hasVerticalScrollBar ? .enabled : .disabled
        scrollViewer.verticalScrollBarVisibility = hasVerticalScrollBar ? .visible : .hidden
    }

    class CustomListView: WinUI.ListView {
        var selectionHandler: ((_ selectedIndex: Int) -> Void)?
        var currentItems: [WinUI.ListViewItem] = []
        var cachedSelectedItem: Int? = nil
    }

    public func createSelectableListView() -> Widget {
        let listView = CustomListView()
        listView.selectionMode = .single
        listView.selectionChanged.addHandler { [weak listView] _, _ in
            guard let listView else { return }
            guard listView.selectedRanges.count > 0 else {
                return
            }
            let selection = Int(listView.selectedRanges[0]!.firstIndex)
            guard selection != listView.cachedSelectedItem else {
                return
            }
            listView.selectionHandler?(selection)
        }
        return listView
    }

    public func updateSelectableListView(
        _ selectableListView: Widget,
        environment: EnvironmentValues
    ) {
        let listView = selectableListView as! CustomListView
        listView.isEnabled = environment.isEnabled
    }

    public func baseItemPadding(ofSelectableListView listView: Widget) -> EdgeInsets {
        EdgeInsets(
            top: 8,
            bottom: 8,
            leading: 16,
            trailing: 12
        )
    }

    public func minimumRowSize(ofSelectableListView listView: Widget) -> SIMD2<Int> {
        SIMD2(
            80,
            40
        )
    }

    public func setItems(
        ofSelectableListView listView: Widget,
        to items: [Widget],
        withRowHeights rowHeights: [Int]
    ) {
        let listView = listView as! CustomListView
        listView.itemContainerTransitions.clear()

        for listItem in listView.currentItems {
            listItem.content = nil
        }

        if items.count != listView.currentItems.count {
            listView.items.clear()
        }

        // We add the new items to the list but also to `listView.currentItems`.
        // This is so that we can retrieve the correct list item instances in
        // setSelectedItem. If we just use `listView.items` instead we get separate
        // incorrect instances for whatever reason (symptom is that it crashes stuff).
        var listItems: [WinUI.ListViewItem] = []
        for (index, item) in items.enumerated() {
            let listItem: WinUI.ListViewItem
            if items.count == listView.currentItems.count {
                listItem = listView.currentItems[index]
            } else {
                listItem = WinUI.ListViewItem()
            }
            listItem.horizontalContentAlignment = .left
            listItem.content = item
            listItem.padding = Thickness(left: 16, top: 8, right: 12, bottom: 8)
            if items.count != listView.currentItems.count {
                listItems.append(listItem)
                listView.items.append(listItem)
            }
        }

        if items.count != listView.currentItems.count {
            listView.currentItems = listItems
            listView.cachedSelectedItem = nil
        }
    }

    public func setSelectionHandler(
        forSelectableListView listView: Widget,
        to action: @escaping (_ selectedIndex: Int) -> Void
    ) {
        let listView = listView as! CustomListView
        listView.selectionHandler = action
    }

    public func setSelectedItem(
        ofSelectableListView listView: Widget,
        toItemAt index: Int?
    ) {
        let listView = listView as! CustomListView
        guard index != listView.cachedSelectedItem else {
            return
        }
        listView.cachedSelectedItem = index
        if let index {
            // We use `listView.currentItems` instead of `listView.items` because
            // `listView.items` isn't the original instances we added and WinUI
            // doesn't like that.
            listView.selectedItem = listView.currentItems[index]
        } else {
            listView.selectedItem = nil
        }
    }

    public func createSlider() -> Widget {
        let slider = Slider()
        slider.valueChanged.addHandler { [weak internalState, weak slider] _, event in
            guard
                let internalState,
                let slider
            else { return }

            internalState.sliderChangeActions[ObjectIdentifier(slider)]?(
                Double(event?.newValue ?? 0)
            )
        }
        slider.stepFrequency = 0.01
        return slider
    }

    public func updateSlider(
        _ slider: Widget,
        minimum: Double,
        maximum: Double,
        decimalPlaces _: Int,
        environment: EnvironmentValues,
        onChange: @escaping (Double) -> Void
    ) {
        let slider = slider as! WinUI.Slider
        slider.minimum = minimum
        slider.maximum = maximum
        environment.apply(to: slider)
        internalState.sliderChangeActions[ObjectIdentifier(slider)] = onChange
    }

    public func setValue(ofSlider slider: Widget, to value: Double) {
        let slider = slider as! WinUI.Slider
        slider.value = value
    }

    public func createPicker(style: BackendPickerStyle) -> Widget {
        switch style {
            case .menu:
                let picker = CustomComboBox()
                picker.selectionChanged.addHandler { [weak picker] _, _ in
                    guard let picker else { return }
                    // WinUI can briefly report -1 while opening or rebuilding
                    // the dropdown. Menu pickers do not expose a clear-selection
                    // action, so ignore that transient state instead of writing
                    // nil back into SwiftCrossUI and closing the dropdown.
                    guard picker.selectedIndex >= 0 else {
                        return
                    }
                    picker.onChangeSelection?(Int(picker.selectedIndex))
                }

                // When hovering over a picker, its foreground changes to black,
                // when the pointer exits the picker the foreground color remains
                // black instead of returning to its regular value. I've tried various
                // variations of the solution below and it seems like the only thing
                // that works is fully recreating the brush.
                picker.pointerExited.addHandler { [weak picker] _, _ in
                    guard let picker else { return }
                    // Restoring the theme's colour means clearing the property,
                    // not writing a colour of our own over it. Writing one here
                    // would put back, on the first hover, exactly the pinned
                    // foreground that `apply(to:)` stopped setting.
                    if let color = picker.actualForegroundColor {
                        let brush = SolidColorBrush()
                        brush.color = color
                        picker.foreground = brush
                    } else {
                        try! picker.clearValue(WinUI.Control.foregroundProperty)
                    }
                }

                return picker
            case .radioGroup:
                let picker = CustomRadioButtons()

                picker.selectionChanged.addHandler { [weak picker] _, _ in
                    guard let picker else { return }
                    picker.onChangeSelection?(
                        picker.selectedIndex == -1 ? nil : Int(picker.selectedIndex)
                    )
                }

                return picker
            default:
                let message = "unsupported picker style \(style)"
                logger.critical("\(message)")
                fatalError(message)
        }
    }

    public func updatePicker(
        _ picker: Widget,
        options: [String],
        environment: EnvironmentValues,
        onChange: @escaping (Int?) -> Void
    ) {
        if let picker = picker as? CustomComboBox {
            picker.onChangeSelection = onChange
            environment.apply(to: picker)
            picker.actualForegroundColor =
                environment.foregroundColor?.resolve(in: environment).uwpColor
            // ComboBoxDropDownBackground is left to the theme. It used to be
            // forced to flat white or flat rgb(32,32,32), which is Windows 11's
            // dark value written out by hand -- so it matched only the default
            // theme, and replaced the acrylic brush everywhere else. The scheme
            // is already carried by `requestedTheme`, set in `apply(to:)`.

            if picker.options != options {
                // Keep the existing WinUI item objects where possible so
                // selection and focus state do not churn during incremental
                // updates. Avoid touching items when options are unchanged
                // because rebuilding an open ComboBox closes its dropdown.
                let sharedCount = min(picker.items.count, options.count)
                for i in 0..<sharedCount {
                    picker.items.setAt(UInt32(i), options[i])
                }

                if options.count > picker.items.count {
                    for option in options[picker.items.count...] {
                        picker.items.append(option)
                    }
                } else if picker.items.count > options.count {
                    // Remove from the end so earlier indices stay valid.
                    for i in (options.count..<picker.items.count).reversed() {
                        picker.items.removeAt(UInt32(i))
                    }
                }

                picker.options = options
            }

            // TODO: Picker font handling
        } else if let picker = picker as? CustomRadioButtons {
            for i in 0..<min(picker.items.count, options.count) {
                (picker.items[i] as! TextBlock).text = options[i]
            }

            if picker.items.count > options.count {
                for i in (options.count..<picker.items.count).reversed() {
                    _ = picker.items.remove(at: i)
                }
            } else {
                for option in options[picker.items.count...] {
                    let block = TextBlock()
                    block.text = option
                    environment.apply(to: block)
                    picker.items.append(block)
                }
            }

            picker.onChangeSelection = onChange
        }
    }

    public func setSelectedOption(ofPicker picker: Widget, to selectedOption: Int?) {
        if let picker = picker as? ComboBox {
            let selectedIndex = Int32(selectedOption ?? -1)
            guard picker.selectedIndex != selectedIndex else {
                return
            }
            picker.selectedIndex = selectedIndex
        } else if let picker = picker as? RadioButtons {
            picker.selectedIndex = Int32(selectedOption ?? -1)
        }
    }

    public func createTextEditor() -> Widget {
        let textEditor = TextBox()
        textEditor.textChanged.addHandler { [weak internalState, weak textEditor] _, _ in
            guard
                let internalState,
                let textEditor
            else { return }
            let identifier = ObjectIdentifier(textEditor)
            let text = textEditor.text
            // WinUI may emit TextChanged for text that was already synchronized
            // from SwiftCrossUI. Ignore it so TextEditor does not write the same
            // value back into its Binding during commit.
            guard internalState.textEditorContents[identifier] != text else {
                return
            }
            internalState.textEditorContents[identifier] = text
            // Reuse this storage because it's the same widget type as a text field
            internalState.textFieldChangeActions[identifier]?(text)
        }
        textEditor.acceptsReturn = true
        textEditor.textWrapping = .wrap

        // Remove padding
        textEditor.padding = Thickness(left: 0, top: 0, right: 0, bottom: 0)

        // Remove background color
        let brush = SolidColorBrush()
        brush.color = UWP.Color(a: 0, r: 0, g: 0, b: 0)
        textEditor.background = brush

        // Remove the hover and focus *backgrounds*, so the editor keeps the
        // app's background in every state rather than lighting up a box.
        _ = textEditor.resources.insert("TextControlBackgroundPointerOver", brush)
        _ = textEditor.resources.insert("TextControlBackgroundFocused", brush)

        // TextControlBorderBrushFocused is deliberately NOT blanked here. It was
        // until 2026-08-28, alongside the two above and under the same comment,
        // but it is not a decoration -- it is the accent underline that shows
        // which control has the keyboard, and there is no second indicator
        // behind it.
        //
        // Measured on P2, WinUI, Windows 11 dark, with focus proven by typing
        // (the editor's Length readout went 96 -> 97 and the character appeared,
        // so the keystroke reached it): no accent row anywhere in or below the
        // editor. The control was a TextField in P9 under the same backend and
        // theme, which createTextField leaves alone -- it drew rgb(76,194,255),
        // two rows, 163 px wide.
        //
        // Not the same as #471, the thin border on the *unfocused* editor: that
        // is TextControlBorderBrush, which this has never set.

        return textEditor
    }

    public func updateTextEditor(
        _ textEditor: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (String) -> Void
    ) {
        let textEditor = (textEditor as! TextBox)
        internalState.textFieldChangeActions[ObjectIdentifier(textEditor)] = onChange
        environment.apply(to: textEditor)

        updateInputScope(of: textEditor, textContentType: environment.textContentType)
    }

    public func setContent(ofTextEditor textEditor: Widget, to content: String) {
        let textEditor = textEditor as! TextBox
        let identifier = ObjectIdentifier(textEditor)
        internalState.textEditorContents[identifier] = content
        guard textEditor.text != content else {
            return
        }
        textEditor.text = content
        textEditor.selectionStart = Int32(content.utf16.count)
        textEditor.selectionLength = 0
    }

    public func getContent(ofTextEditor textEditor: Widget) -> String {
        (textEditor as! TextBox).text
    }

    func updateInputScope(
        of textField: some TextBoxProtocol,
        textContentType: TextContentType
    ) {

        let inputScope: InputScopeNameValue? =
            switch textField {
                case is TextBox:
                    switch textContentType {
                        case .decimal(_): .number
                        case .digits(_): .digits
                        case .emailAddress: .emailSmtpAddress
                        case .name: .personalFullName
                        case .phoneNumber: .telephoneNumber
                        case .text: .default
                        case .url: .url
                    }
                case is PasswordBox:
                    switch textContentType {
                        case .digits(_): .numericPin
                        case .text: .password
                        default: nil
                    }
                default: nil
            }
        guard let inputScope else { return }

        let inputScopeName = InputScopeName(inputScope)

        if let inputScope = textField.inputScope,
           inputScope.names.count == 1
        {
            inputScope.names[0] = inputScopeName
        } else {
            let inputScope = InputScope()
            inputScope.names.append(inputScopeName)
            textField.inputScope = inputScope
        }
    }

    public func createImageView() -> Widget {
        WinUI.Image()
    }

    public func updateImageView(
        _ imageView: Widget,
        rgbaData: [UInt8],
        width: Int,
        height: Int,
        targetWidth: Int,
        targetHeight: Int,
        dataHasChanged: Bool,
        environment: EnvironmentValues
    ) {
        let imageView = imageView as! WinUI.Image

        // Reuse the existing bitmap whenever the size matches. Allocating a
        // fresh WriteableBitmap per update costs width*height*4 bytes every
        // time, which for video-rate 4K updates is a 33 MB allocation per
        // frame and dominates the update.
        let bitmap: WriteableBitmap
        if let existing = imageView.source as? WriteableBitmap,
           existing.pixelWidth == Int32(width),
           existing.pixelHeight == Int32(height)
        {
            bitmap = existing
        } else {
            bitmap = WriteableBitmap(Int32(width), Int32(height))
            imageView.source = bitmap
        }

        guard let buffer = try? bitmap.pixelBuffer.buffer else {
            // This used to be `try! bitmap.pixelBuffer.buffer!`, which crashed
            // with no diagnostic when it failed. Skip the frame instead so a
            // failure here is visible (via the console) rather than fatal.
            print("WinUIBackend: WriteableBitmap.pixelBuffer.buffer unavailable, skipping frame update")
            return
        }
        memcpy(buffer, rgbaData, min(Int(bitmap.pixelBuffer.length), rgbaData.count))

        // Convert RGBA to BGRA in-place, and apply janky transparency fix until we
        // figure out how to fix WinUI image blending (non-black transparent pixels
        // just don't seem to get blended at all, or at least pixels that are white
        // enough, haven't tested many colours).
        //
        // Swap whole pixels as UInt32 words rather than three byte accesses:
        // at 4K this loop runs 8.3 million times per frame.
        let pixels = UnsafeMutableRawPointer(buffer)
            .assumingMemoryBound(to: UInt32.self)
        for i in 0..<(width * height) {
            let pixel = pixels[i]
            if pixel & 0xFF00_0000 == 0 {
                // If transparent, make the pixel black (this is the janky blending fix).
                pixels[i] = pixel & 0xFF00_0000
            } else {
                // Swap R and B (RGBA to BGRA), keeping G and A in place.
                pixels[i] =
                    (pixel & 0xFF00_FF00)
                    | ((pixel & 0x00FF_0000) >> 16)
                    | ((pixel & 0x0000_00FF) << 16)
            }
        }

        try? bitmap.invalidate()
    }

    public func createSplitView(leadingChild: Widget, trailingChild: Widget) -> Widget {
        let splitView = CustomSplitView()
        splitView.pane = leadingChild
        splitView.content = trailingChild
        splitView.isPaneOpen = true
        splitView.displayMode = .inline
        splitView.openPaneLength = Double(Self.defaultSidebarWidth)
        return splitView
    }

    public func setResizeHandler(
        ofSplitView splitView: Widget,
        to action: @escaping () -> Void
    ) {
        // WinUI's SplitView currently doesn't support resizing, but we still
        // store the sidebar resize handler because we programmatically resize
        // the sidebar and call the handler whenever the minimum sidebar width
        // changes.
        let splitView = splitView as! CustomSplitView
        splitView.sidebarResizeHandler = action
    }

    public func sidebarWidth(ofSplitView splitView: Widget) -> Int {
        let splitView = splitView as! CustomSplitView
        return Int(splitView.openPaneLength.rounded(.towardZero))
    }

    /// The sidebar width to open at when the content does not ask for more.
    ///
    /// Matches `defaultLeadingWidth` in AppKitBackend and `defaultSidebarWidth`
    /// in GtkBackend, so the three agree on what a navigation sidebar looks
    /// like before anyone resizes it.
    static let defaultSidebarWidth = 200

    public func setSidebarWidthBounds(
        ofSplitView splitView: Widget,
        minimum minimumWidth: Int,
        maximum maximumWidth: Int
    ) {
        let splitView = splitView as! CustomSplitView

        // maximumWidth used to be ignored entirely: the signature took it and
        // the body never read it, so the sidebar could exceed what the layout
        // system allowed without anything noticing.
        let maximumWidth = max(minimumWidth, maximumWidth)

        // The minimum is the width the content cannot go below; it is not a
        // width worth opening at. Pinning the sidebar to it made a list of
        // short labels 87px wide, which clipped every row -- "Elderberry"
        // rendered as "berry". What to open at is what the content would like,
        // floored by the platform's navigation width.
        // `pane` is typed as UIElement, but createSplitView only ever puts a
        // Widget in it; the fallback keeps a surprise from silently sizing the
        // sidebar to zero.
        let naturalWidth = (splitView.pane as? Widget).map { Self.naturalSize(of: $0).x } ?? 0
        let defaultWidth = max(naturalWidth, Self.defaultSidebarWidth)

        let newWidth = Double(min(max(defaultWidth, minimumWidth), maximumWidth))
        if newWidth != splitView.openPaneLength {
            splitView.openPaneLength = newWidth
            splitView.sidebarResizeHandler?()
        }
    }

    public func createToggle() -> Widget {
        let toggle = ToggleButton()
        toggle.click.addHandler { [weak internalState] _, _ in
            guard let internalState else { return }
            internalState.toggleClickActions[ObjectIdentifier(toggle)]?(toggle.isChecked ?? false)
        }
        return toggle
    }

    public func updateToggle(
        _ toggle: Widget,
        label: String,
        environment: EnvironmentValues,
        onChange: @escaping (Bool) -> Void
    ) {
        let toggle = toggle as! ToggleButton
        let block = TextBlock()
        block.text = label
        toggle.content = block

        // Use opposite color scheme for label if checked to match WinUI's default
        // behaviour.
        environment.with(
            \.colorScheme,
            toggle.isChecked == true
                ? environment.colorScheme.opposite
                : environment.colorScheme
        ).apply(to: block)

        environment.apply(to: toggle)

        internalState.toggleClickActions[ObjectIdentifier(toggle)] = { state in
            onChange(state)

            // Update label color scheme just in case the update doesn't get
            // propagated back to us (e.g. if the user passes in a dummy binding)
            environment.with(
                \.colorScheme,
                state ? environment.colorScheme.opposite : environment.colorScheme
            ).apply(to: block)
        }
    }

    public func setState(ofToggle toggle: Widget, to state: Bool) {
        let toggle = toggle as! ToggleButton
        toggle.isChecked = state
    }

    public func createSwitch() -> Widget {
        let toggleSwitch = ToggleSwitch()
        toggleSwitch.offContent = ""
        toggleSwitch.onContent = ""
        toggleSwitch.padding = Thickness(left: 0, top: 0, right: 0, bottom: 0)
        toggleSwitch.toggled.addHandler { [weak internalState] _, _ in
            guard let internalState else { return }
            internalState.switchClickActions[ObjectIdentifier(toggleSwitch)]?(toggleSwitch.isOn)
        }
        return toggleSwitch
    }

    public func updateSwitch(
        _ toggleSwitch: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (Bool) -> Void
    ) {
        let toggleSwitch = toggleSwitch as! ToggleSwitch
        internalState.switchClickActions[ObjectIdentifier(toggleSwitch)] = onChange
        environment.apply(to: toggleSwitch)
    }

    public func setState(ofSwitch switchWidget: Widget, to state: Bool) {
        let switchWidget = switchWidget as! ToggleSwitch
        if switchWidget.isOn != state {
            switchWidget.isOn = state
        }
    }

    class CustomCheckBox: WinUI.CheckBox {
        var onToggle: ((Bool) -> Void)?

        func handleToggle() {
            if isChecked == nil {
                logger.warning("checkbox in limbo")
            }
            onToggle?(isChecked ?? false)
        }
    }

    public func createCheckbox() -> Widget {
        let checkbox = CustomCheckBox()

        // This natural size is hardcoded, but it's the actual visible size of
        // the checkbox. WinUI puts a bunch of extra space around checkboxes
        // by default which messes things up.
        let naturalSize = naturalSize(of: checkbox)
        checkbox.minWidth = Double(naturalSize.x)
        checkbox.minHeight = Double(naturalSize.y)

        checkbox.padding = Thickness(left: 0, top: 0, right: 0, bottom: 0)
        checkbox.checked.addHandler { [weak checkbox] _, _ in
            checkbox?.handleToggle()
        }
        checkbox.unchecked.addHandler { [weak checkbox] _, _ in
            checkbox?.handleToggle()
        }
        return checkbox
    }

    public func updateCheckbox(
        _ checkbox: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (Bool) -> Void
    ) {
        let checkbox = checkbox as! CustomCheckBox
        checkbox.padding = Thickness(left: 0, top: 0, right: 0, bottom: 0)
        checkbox.onToggle = onChange
        environment.apply(to: checkbox)
    }

    public func setState(ofCheckbox checkboxWidget: Widget, to state: Bool) {
        let checkboxWidget = checkboxWidget as! CustomCheckBox
        if checkboxWidget.isChecked != state {
            checkboxWidget.isChecked = state
        }
    }

    public func showOpenDialog(
        fileDialogOptions: FileDialogOptions,
        openDialogOptions: OpenDialogOptions,
        window: Window?,
        resultHandler handleResult: @escaping (DialogResult<[URL]>) -> Void
    ) {
        switch openDialogOptions.singleKindSelectionMode {
            case .files:
                showFileOpenDialog(
                    fileDialogOptions: fileDialogOptions,
                    openDialogOptions: openDialogOptions,
                    window: window,
                    resultHandler: handleResult
                )
            case .directories:
                showFolderOpenDialog(
                    fileDialogOptions: fileDialogOptions,
                    openDialogOptions: openDialogOptions,
                    window: window,
                    resultHandler: handleResult
                )
        }
    }

    private func showFileOpenDialog(
        fileDialogOptions: FileDialogOptions,
        openDialogOptions: OpenDialogOptions,
        window: Window?,
        resultHandler handleResult: @escaping (DialogResult<[URL]>) -> Void
    ) {
        let picker = FileOpenPicker()

        let window = window ?? windows[0]
        let hwnd = window.getHWND()!
        let interface: SwiftIInitializeWithWindow = try! picker.thisPtr.QueryInterface()
        try! interface.initialize(with: hwnd)

        picker.fileTypeFilter.append("*")

        if openDialogOptions.allowMultipleSelections {
            let promise = try! picker.pickMultipleFilesAsync()!
            promise.completed = { operation, status in
                let result: DialogResult<[URL]> = Self.handleAsyncOperationCompletion(
                    operation,
                    status
                ) { result in
                    let files = Array(result).compactMap { $0 }
                        .map(\.path)
                        .map(URL.init(fileURLWithPath:))
                    return .success(files)
                } onFailure: {
                    return .cancelled
                }
                Self.restoreForeground(of: hwnd)
                handleResult(result)
            }
        } else {
            let promise = try! picker.pickSingleFileAsync()!
            promise.completed = { operation, status in
                let result: DialogResult<[URL]> = Self.handleAsyncOperationCompletion(
                    operation,
                    status
                ) { result in
                    let file = URL(fileURLWithPath: result.path)
                    return .success([file])
                } onFailure: {
                    return .cancelled
                }
                Self.restoreForeground(of: hwnd)
                handleResult(result)
            }
        }
    }

    private func showFolderOpenDialog(
        fileDialogOptions: FileDialogOptions,
        openDialogOptions: OpenDialogOptions,
        window: Window?,
        resultHandler handleResult: @escaping (DialogResult<[URL]>) -> Void
    ) {
        precondition(
            !openDialogOptions.allowMultipleSelections,
            "WinUIBackend does not support selecting multiple folders"
        )

        let picker = FolderPicker()

        let window = window ?? windows[0]
        let hwnd = window.getHWND()!
        let interface: SwiftIInitializeWithWindow = try! picker.thisPtr.QueryInterface()
        try! interface.initialize(with: hwnd)

        picker.commitButtonText = fileDialogOptions.defaultButtonLabel
        picker.fileTypeFilter.append("*")

        let promise = try! picker.pickSingleFolderAsync()!
        promise.completed = { operation, status in
            let result: DialogResult<[URL]> = Self.handleAsyncOperationCompletion(
                operation,
                status
            ) { result in
                let folder = URL(fileURLWithPath: result.path)
                return .success([folder])
            } onFailure: {
                return .cancelled
            }
            Self.restoreForeground(of: hwnd)
            handleResult(result)
        }
    }

    public func showSaveDialog(
        fileDialogOptions: FileDialogOptions,
        saveDialogOptions: SaveDialogOptions,
        window: Window?,
        resultHandler handleResult: @escaping (DialogResult<URL>) -> Void
    ) {
        let picker = FileSavePicker()

        let window = window ?? windows[0]
        let hwnd = window.getHWND()!
        let interface: SwiftIInitializeWithWindow = try! picker.thisPtr.QueryInterface()
        try! interface.initialize(with: hwnd)

        _ = picker.fileTypeChoices.insert("Text", [".txt"].toVector())
        let promise = try! picker.pickSaveFileAsync()!
        promise.completed = { operation, status in
            let result: DialogResult<URL> = Self.handleAsyncOperationCompletion(
                operation,
                status
            ) { result in
                let file = URL(fileURLWithPath: result.path)
                return .success(file)
            } onFailure: {
                return .cancelled
            }
            Self.restoreForeground(of: hwnd)
            handleResult(result)
        }
    }

    /// Returns activation to the window that owned a file dialog.
    ///
    /// Windows does not always hand the foreground back when a picker closes;
    /// it goes to the next window in the z-order instead, which for an app
    /// launched from a terminal is the terminal. The owner has to ask for it
    /// back, which this process is allowed to do because it still owns the
    /// foreground at that moment. Without this, choosing a file leaves the app
    /// behind whatever was underneath it.
    /// 把啟動狀態交還給擁有該檔案對話框的視窗。Windows 在 picker 關閉後不一定會把
    /// 前景交還，而是給 z-order 中的下一個視窗；對於從終端機啟動的 app 來說那就是
    /// 終端機。擁有者必須主動要回來，而此時本行程仍持有前景，因此是被允許的。
    /// 少了這步，選完檔案後 app 會留在原本壓在它上面的視窗後面。
    private static func restoreForeground(of hwnd: HWND) {
        _ = SetForegroundWindow(hwnd)
    }

    /// A helper method that abstracts out the common failure case handling code
    /// from all of our file dialog related async operation completion handlers.
    private static func handleAsyncOperationCompletion<T, R>(
        _ operation: AnyIAsyncOperation<T?>?,
        _ status: AsyncStatus,
        onSuccess handleSuccess: (T) -> R,
        onFailure handleFailure: () -> R
    ) -> R {
        guard let operation else {
            logger.warning(
                "operation parameter unexpectedly nil",
                metadata: [
                    "function": #function
                ]
            )
            return handleFailure()
        }

        guard
            status == .completed,
            let result = try? operation.getResults()
        else {
            if status == .error {
                logger.error(
                    "\(WindowsFoundation.Error(hr: operation.errorCode))",
                    metadata: [
                        "function": #function
                    ]
                )

                if UInt32(bitPattern: operation.errorCode) == 0x80004005 {
                    // https://github.com/microsoft/WindowsAppSDK/issues/4625#issuecomment-2281358235
                    logger.warning(
                        """
                        This may indicate that you're attempting to launch a \
                        file picker from an app launched as administrator
                        """
                    )
                }
            }
            return handleFailure()
        }

        return handleSuccess(result)
    }

    public func createTapGestureTarget(wrapping child: Widget, gesture: TapGesture) -> Widget {
        if gesture != .primary {
            fatalError("Unsupported gesture type \(gesture)")
        }
        let tapGestureTarget = TapGestureTarget()
        insert(child, into: tapGestureTarget, at: 0)
        tapGestureTarget.child = child

        // Set a background so that the click target's entire area gets hit
        // tested. The background we set is transparent so that it doesn't
        // change the visual appearance of the view.
        let brush = SolidColorBrush()
        brush.color = UWP.Color(a: 0, r: 0, g: 0, b: 0)
        tapGestureTarget.background = brush

        tapGestureTarget.pointerPressed.addHandler { [weak tapGestureTarget] _, _ in
            guard let tapGestureTarget else { return }
            tapGestureTarget.clickHandler?()
        }
        return tapGestureTarget
    }

    public func updateTapGestureTarget(
        _ tapGestureTarget: Widget,
        gesture: TapGesture,
        environment: EnvironmentValues,
        action: @escaping () -> Void
    ) {
        if gesture != .primary {
            fatalError("Unsupported gesture type \(gesture)")
        }
        let tapGestureTarget = tapGestureTarget as! TapGestureTarget
        tapGestureTarget.clickHandler = environment.isEnabled ? action : {}
    }

    public func createHoverTarget(wrapping child: Widget) -> Widget {
        let hoverTarget = HoverGestureTarget()
        insert(child, into: hoverTarget, at: 0)
        hoverTarget.child = child

        // Ensure the hover target covers the full area of the child.
        // Use a transparent background so the visual appearance doesn't change but
        // the hit-testing covers the whole region.
        let brush = SolidColorBrush()
        brush.color = UWP.Color(a: 0, r: 0, g: 0, b: 0)
        hoverTarget.background = brush

        hoverTarget.pointerEntered.addHandler { [weak hoverTarget] _, _ in
            guard let hoverTarget else { return }
            hoverTarget.enterHandler?()
        }
        hoverTarget.pointerExited.addHandler { [weak hoverTarget] _, _ in
            guard let hoverTarget else { return }
            hoverTarget.exitHandler?()
        }
        return hoverTarget
    }

    public func updateHoverTarget(
        _ hoverTarget: Widget,
        environment: EnvironmentValues,
        action: @escaping (Bool) -> Void
    ) {
        let hoverTarget = hoverTarget as! HoverGestureTarget
        hoverTarget.enterHandler = environment.isEnabled ? { action(true) } : {}
        hoverTarget.exitHandler = environment.isEnabled ? { action(false) } : {}
    }

    public func createProgressSpinner() -> Widget {
        let spinner = ProgressRing()
        spinner.isIndeterminate = true
        return spinner
    }

    public func createProgressBar() -> Widget {
        let progressBar = ProgressBar()
        progressBar.maximum = 10_000
        return progressBar
    }

    public func updateProgressBar(
        _ widget: Widget,
        progressFraction: Double?,
        environment: EnvironmentValues
    ) {
        let progressBar = widget as! ProgressBar
        if let progressFraction {
            progressBar.isIndeterminate = false
            progressBar.value = progressBar.maximum * progressFraction
        } else {
            progressBar.isIndeterminate = true
        }
    }

    public func createPathWidget() -> Widget {
        WinUI.Path()
    }

    public func createPath() -> Path {
        GeometryGroupHolder()
    }

    public func updatePath(
        _ path: Path,
        _ source: SwiftCrossUI.Path,
        bounds: SwiftCrossUI.Path.Rect,
        pointsChanged: Bool,
        environment: EnvironmentValues
    ) {
        path.strokeStyle = source.strokeStyle

        if pointsChanged {
            path.group.children.clear()
            applyActions(source.actions, to: path.group.children)
        }

        path.group.fillRule =
            switch source.fillRule {
                case .evenOdd:
                    .evenOdd
                case .winding:
                    .nonzero
            }
    }

    func requirePathFigure(
        _ collection: WinUI.GeometryCollection,
        lastPoint: Point
    ) -> PathFigure {
        var pathGeometry: PathGeometry
        if collection.size > 0,
           let castedLast = collection.getAt(collection.size - 1) as? PathGeometry
        {
            pathGeometry = castedLast
        } else {
            pathGeometry = PathGeometry()
            collection.append(pathGeometry)
        }

        var figure: PathFigure
        if pathGeometry.figures.size > 0 {
            // Note: the if check and force-unwrap is necessary. You can't do an `if let`
            // here because PathFigureCollection uses unsigned integers for its indices so
            // `size - 1` would underflow (causing a fatalError) if it's empty.
            figure = pathGeometry.figures.getAt(pathGeometry.figures.size - 1)!
        } else {
            figure = PathFigure()
            figure.startPoint = lastPoint
            pathGeometry.figures.append(figure)
        }

        return figure
    }

    func applyActions(_ actions: [SwiftCrossUI.Path.Action], to geometry: WinUI.GeometryCollection)
    {
        var lastPoint = Point(x: 0.0, y: 0.0)

        for action in actions {
            switch action {
                case .moveTo(let point):
                    lastPoint = Point(x: Float(point.x), y: Float(point.y))

                    if geometry.size > 0,
                       let pathGeometry = geometry.getAt(geometry.size - 1) as? PathGeometry,
                       pathGeometry.figures.size > 0
                    {
                        let figure = pathGeometry.figures.getAt(pathGeometry.figures.size - 1)!
                        if figure.segments.size > 0 {
                            let newFigure = PathFigure()
                            newFigure.startPoint = lastPoint
                            pathGeometry.figures.append(newFigure)
                        } else {
                            figure.startPoint = lastPoint
                        }
                    }
                case .lineTo(let point):
                    let wfPoint = Point(x: Float(point.x), y: Float(point.y))
                    defer { lastPoint = wfPoint }

                    let figure = requirePathFigure(geometry, lastPoint: lastPoint)

                    let segment = LineSegment()
                    segment.point = wfPoint
                    figure.segments.append(segment)
                case .quadCurve(let control, let end):
                    let wfControl = Point(x: Float(control.x), y: Float(control.y))
                    let wfEnd = Point(x: Float(end.x), y: Float(end.y))
                    defer { lastPoint = wfEnd }

                    let figure = requirePathFigure(geometry, lastPoint: lastPoint)

                    let segment = QuadraticBezierSegment()
                    segment.point1 = wfControl
                    segment.point2 = wfEnd
                    figure.segments.append(segment)
                case .cubicCurve(let control1, let control2, let end):
                    let wfControl1 = Point(x: Float(control1.x), y: Float(control1.y))
                    let wfControl2 = Point(x: Float(control2.x), y: Float(control2.y))
                    let wfEnd = Point(x: Float(end.x), y: Float(end.y))
                    defer { lastPoint = wfEnd }

                    let figure = requirePathFigure(geometry, lastPoint: lastPoint)

                    let segment = BezierSegment()
                    segment.point1 = wfControl1
                    segment.point2 = wfControl2
                    segment.point3 = wfEnd
                    figure.segments.append(segment)
                case .rectangle(let rect):
                    let rectGeo = RectangleGeometry()
                    rectGeo.rect = Rect(
                        x: Float(rect.x),
                        y: Float(rect.y),
                        width: Float(rect.width),
                        height: Float(rect.height)
                    )
                    geometry.append(rectGeo)
                case .circle(let center, let radius):
                    let ellipse = EllipseGeometry()
                    ellipse.radiusX = radius
                    ellipse.radiusY = radius
                    ellipse.center = Point(x: Float(center.x), y: Float(center.y))
                    geometry.append(ellipse)
                case .arc(
                let center,
                let radius,
                let startAngle,
                let endAngle,
                let clockwise
            ):
                    let startPoint = Point(
                        x: Float(center.x + radius * cos(startAngle)),
                        y: Float(center.y + radius * sin(startAngle))
                    )
                    let endPoint = Point(
                        x: Float(center.x + radius * cos(endAngle)),
                        y: Float(center.y + radius * sin(endAngle))
                    )
                    defer { lastPoint = endPoint }

                    let figure = requirePathFigure(geometry, lastPoint: lastPoint)

                    if startPoint != lastPoint {
                        if figure.segments.size > 0 {
                            let connector = LineSegment()
                            connector.point = startPoint
                            figure.segments.append(connector)
                        } else {
                            figure.startPoint = startPoint
                        }
                    }

                    let segment = ArcSegment()

                    if clockwise {
                        if startAngle < endAngle {
                            segment.isLargeArc = (endAngle - startAngle > .pi)
                        } else {
                            segment.isLargeArc = (startAngle - endAngle < .pi)
                        }
                        segment.sweepDirection = .clockwise
                    } else {
                        if startAngle < endAngle {
                            segment.isLargeArc = (endAngle - startAngle < .pi)
                        } else {
                            segment.isLargeArc = (startAngle - endAngle > .pi)
                        }
                        segment.sweepDirection = .counterclockwise
                    }

                    segment.point = endPoint
                    segment.size = Size(width: Float(radius), height: Float(radius))

                    figure.segments.append(segment)
                case .transform(let transform):
                    let matrixTransform = MatrixTransform()
                    matrixTransform.matrix = Matrix(
                        m11: transform.linearTransform.x,
                        m12: transform.linearTransform.z,
                        m21: transform.linearTransform.y,
                        m22: transform.linearTransform.w,
                        offsetX: transform.translation.x,
                        offsetY: transform.translation.y
                    )

                    for case let geo? in geometry {
                        if geo.transform == nil {
                            geo.transform = matrixTransform
                        } else if let group = geo.transform as? TransformGroup {
                            group.children.append(matrixTransform)
                        } else {
                            let group = TransformGroup()
                            group.children.append(geo.transform)
                            group.children.append(matrixTransform)
                            geo.transform = group
                        }
                    }

                    if geometry.size > 0,
                       let pathGeometry = geometry.getAt(geometry.size - 1) as? PathGeometry,
                       pathGeometry.figures.contains(where: { ($0?.segments.size ?? 0) > 0 })
                    {
                        // Start a new PathGeometry so that transforms don't apply going forward
                        geometry.append(PathGeometry())
                    }
                case .subpath(let actions):
                    let subGeo = GeometryGroup()
                    applyActions(actions, to: subGeo.children)
                    geometry.append(subGeo)
            }
        }

        // Cleanup: remove empty paths
        // Having empty paths in the geometry group causes rendering it to silently crash
        for i in (0..<geometry.size).reversed() {
            if let pathGeo = geometry.getAt(i) as? PathGeometry,
               pathGeo.figures.size == 0
            {
                geometry.removeAt(i)
            }
        }
    }

    public func renderPath(
        _ path: Path,
        container: Widget,
        strokeColor: SwiftCrossUI.Color.Resolved,
        fillColor: SwiftCrossUI.Color.Resolved,
        overrideStrokeStyle: StrokeStyle?
    ) {
        renderPath(
            path,
            container: container,
            strokeStyle: .color(strokeColor),
            fillStyle: .color(fillColor),
            overrideStrokeStyle: overrideStrokeStyle,
            environment: EnvironmentValues(backend: self)
        )
    }

    /// The style-taking overload. `Path.Fill` and `.Stroke` are `Brush`
    /// properties, so a gradient needs a different brush and nothing else --
    /// XAML clips a brush to the geometry it paints, and to the *stroke* when it
    /// is painting a stroke, which is the case a hand-rolled clip gets wrong.
    ///
    /// Conic is deliberately absent: XAML has no conic brush, which is why
    /// `WinUIBackend+AngularGradient.swift` exists as a workaround, and
    /// `ResolvedFillStyle` does not offer the case.
    ///
    /// 接收樣式的多載。`Path.Fill` 與 `.Stroke` 都是 `Brush` 屬性，因此漸層只需要換一個 brush，
    /// 別無其他——XAML 會把 brush 裁切到它所塗繪的幾何，而在塗繪描邊時就是裁切到**描邊**，
    /// 那正是自行實作 clip 時最容易做錯的情況。
    ///
    /// 刻意不含 conic：XAML 沒有 conic brush，這正是 `WinUIBackend+AngularGradient.swift` 作為
    /// 變通存在的原因，而 `ResolvedFillStyle` 也未提供該 case。
    public func renderPath(
        _ path: Path,
        container: Widget,
        strokeStyle strokeFill: ResolvedFillStyle,
        fillStyle: ResolvedFillStyle,
        overrideStrokeStyle: StrokeStyle?,
        environment: EnvironmentValues
    ) {
        let winUiPath = container as! WinUI.Path
        let strokeStyle = overrideStrokeStyle ?? path.strokeStyle!

        winUiPath.fill = Self.brush(for: fillStyle, in: environment)
        winUiPath.stroke = Self.brush(for: strokeFill, in: environment)
        winUiPath.strokeThickness = strokeStyle.width

        switch strokeStyle.cap {
            case .butt:
                winUiPath.strokeStartLineCap = .flat
                winUiPath.strokeEndLineCap = .flat
            case .round:
                winUiPath.strokeStartLineCap = .round
                winUiPath.strokeEndLineCap = .round
            case .square:
                winUiPath.strokeStartLineCap = .square
                winUiPath.strokeEndLineCap = .square
        }

        switch strokeStyle.join {
            case .miter(let limit):
                winUiPath.strokeMiterLimit = limit
                winUiPath.strokeLineJoin = .miter
            case .round:
                winUiPath.strokeLineJoin = .round
            case .bevel:
                winUiPath.strokeLineJoin = .bevel
        }

        winUiPath.data = path.group
    }

    public func createDatePicker() -> Widget {
        return CustomDatePicker()
    }

    public func updateDatePicker(
        _ datePicker: Widget,
        environment: EnvironmentValues,
        date: Date,
        range: ClosedRange<Date>,
        components: DatePickerComponents,
        onChange: @escaping (Date) -> Void
    ) {
        let customDatePicker = datePicker as! CustomDatePicker

        if components.contains(.hourMinuteAndSecond) {
            print(
                "DatePickerComponents.hourMinuteAndSecond is not supported in WinUIBackend. Falling back to .hourAndMinute."
            )
        }

        customDatePicker.toggleTimeView(shown: components.contains(.hourAndMinute))

        if environment.timeZone != .current {
            print("environment.timeZone is has no effect in WinUIBackend.")
        }

        let dateViewType: CustomDatePicker.DateViewType.Discriminator? =
            if components.contains(.date) {
                switch environment.backendDatePickerStyle {
                    case .automatic, .wheel:
                        .datePicker
                    case .compact:
                        .calendarDatePicker
                    case .graphical:
                        .calendarView
                }
            } else {
                nil
            }

        customDatePicker.onChange = onChange
        customDatePicker.changeDateView(to: dateViewType)
        customDatePicker.updateIfNeeded(date: date, calendar: environment.calendar)
        customDatePicker.setDateRange(to: range)
        customDatePicker.setEnabled(to: environment.isEnabled)

        // TODO(parity): foreground color ignored
        // Setting foreground like for other views works for TimePicker and DatePicker but not for
        // CalendarView or CalendarDatePicker.
    }

    // public func createTable(rows: Int, columns: Int) -> Widget {
    //     let grid = Grid()
    //     grid.columnSpacing = 10
    //     grid.rowSpacing = 10
    //     for _ in 0..<rows {
    //         let rowDefinition = RowDefinition()
    //         rowDefinition.height = GridLength(value: 0, gridUnitType: .auto)
    //         grid.rowDefinitions.append(rowDefinition)
    //     }

    //     for _ in 0..<columns {
    //         let columnDefinition = ColumnDefinition()
    //         columnDefinition.width = GridLength(value: 0, gridUnitType: .auto)
    //         grid.columnDefinitions.append(columnDefinition)
    //     }
    //     return grid
    // }

    // public func setRowCount(ofTable table: Widget, to rows: Int) {
    //     let grid = table as! Grid
    //     grid.rowDefinitions.clear()
    //     for _ in 0..<rows {
    //         let rowDefinition = RowDefinition()
    //         rowDefinition.height = GridLength(value: 0, gridUnitType: .auto)
    //         grid.rowDefinitions.append(rowDefinition)
    //     }
    // }

    // public func setColumnCount(ofTable table: Widget, to columns: Int) {
    //     let grid = table as! Grid
    //     grid.columnDefinitions.clear()
    //     for _ in 0..<columns {
    //         let columnDefinition = ColumnDefinition()
    //         columnDefinition.width = GridLength(value: 0, gridUnitType: .auto)
    //         grid.columnDefinitions.append(columnDefinition)
    //     }
    // }

    // public func setCell(at position: CellPosition, inTable table: Widget, to widget: Widget) {
    //     let grid = table as! Grid
    //     Grid.setColumn(widget, Int32(position.column))
    //     Grid.setRow(widget, Int32(position.row))
    //     grid.children.append(widget)
    // }
}

extension EnvironmentValues {
    @MainActor
    var winUIForegroundBrush: WinUI.Brush {
        let brush = SolidColorBrush()
        brush.color = suggestedForegroundColor.resolve(in: self).uwpColor
        return brush
    }

    /// A brush for the colour the application explicitly asked for, or `nil`
    /// when it asked for none.
    ///
    /// `nil` means leave WinUI's own foreground alone. `apply(to:)` sets
    /// `requestedTheme` from the colour scheme, so the theme resources already
    /// resolve to the right light or dark value without help -- and unlike a
    /// brush built here, they carry the disabled and pointer-over variants.
    ///
    /// A `TextBlock` inside a `Button` is what makes this matter. Button's
    /// Disabled visual state sets the *ContentPresenter's* Foreground, which a
    /// child carrying its own local value does not inherit, so a disabled button
    /// kept a full-strength label. Measured on P21, 2026-08-28: the enabled and
    /// disabled labels were both rgb(255,255,255), the two buttons differing
    /// only by a 3-unit fill.
    @MainActor
    var explicitWinUIForegroundBrush: WinUI.Brush? {
        guard let foregroundColor else { return nil }
        let brush = SolidColorBrush()
        brush.color = foregroundColor.resolve(in: self).uwpColor
        return brush
    }

    @MainActor
    func apply(to control: WinUI.Control) {
        let resolvedFont = resolvedFont
        control.fontSize = resolvedFont.pointSize
        control.fontWeight.weight = resolvedFont.winUIFontWeight
        // Cleared rather than skipped: a widget is reused across updates, so a
        // control that stops carrying an explicit colour has to go back to the
        // theme's rather than keep the last one it was given.
        if let brush = explicitWinUIForegroundBrush {
            control.foreground = brush
        } else {
            try! control.clearValue(WinUI.Control.foregroundProperty)
        }
        control.isEnabled = isEnabled
        if resolvedFont.isItalic {
            control.fontStyle = .italic
        }
        switch colorScheme {
            case .light:
                control.requestedTheme = .light
            case .dark:
                control.requestedTheme = .dark
        }
    }

    @MainActor
    func apply(to textBlock: WinUI.TextBlock) {
        let resolvedFont = resolvedFont
        textBlock.fontSize = resolvedFont.pointSize
        textBlock.fontWeight.weight = resolvedFont.winUIFontWeight
        if let brush = explicitWinUIForegroundBrush {
            textBlock.foreground = brush
        } else {
            try! textBlock.clearValue(WinUI.TextBlock.foregroundProperty)
        }
        textBlock.lineHeight = resolvedFont.lineHeight

        if resolvedFont.isItalic {
            textBlock.fontStyle = .italic
        }
    }
}

extension Font.Resolved {
    var winUIFontWeight: UInt16 {
        switch weight {
            case .ultraLight:
                100
            case .thin:
                200
            case .light:
                300
            case .regular:
                400
            case .medium:
                500
            case .semibold:
                600
            case .bold:
                700
            case .heavy:
                800
            case .black:
                900
        }
    }
}

final class CustomComboBox: ComboBox {
    var options: [String] = []
    var onChangeSelection: ((Int?) -> Void)?

    /// The colour `pointerExited` restores, or `nil` to restore the theme's.
    ///
    /// Optional rather than a colour with a default, because no colour means
    /// "whatever the theme would have used". It defaulted to opaque black,
    /// which is the wrong answer under a dark theme and was only ever invisible
    /// because `updatePicker` overwrote it before anyone could hover.
    var actualForegroundColor: UWP.Color?
}

final class CustomButton: WinUI.Button {
    let label = TextBlock()
}

final class CustomRadioButtons: RadioButtons {
    var onChangeSelection: ((Int?) -> Void)?
}

final class CustomSplitView: SplitView {
    var sidebarResizeHandler: (() -> Void)?
}

final class TapGestureTarget: WinUI.Canvas {
    var clickHandler: (() -> Void)?
    var child: WinUI.FrameworkElement?
}

final class HoverGestureTarget: WinUI.Canvas {
    var enterHandler: (() -> Void)?
    var exitHandler: (() -> Void)?
    var child: WinUI.FrameworkElement?
}

final class TooltipContainer: WinUI.Canvas {
    var child: WinUI.FrameworkElement
    var tooltip: ToolTip

    init(child: WinUI.FrameworkElement) {
        self.child = child
        self.tooltip = ToolTip()

        super.init()

        children.append(child)
        ToolTipService.setToolTip(self, tooltip)
    }
}

class SwiftIInitializeWithWindow: WindowsFoundation.IUnknown {
    override class var IID: WindowsFoundation.IID {
        WindowsFoundation.IID(
            Data1: 0x3E68_D4BD,
            Data2: 0x7135,
            Data3: 0x4D10,
            Data4: (0x80, 0x18, 0x9F, 0xB6, 0xD9, 0xF3, 0x3F, 0xA1)
        )
    }

    func initialize(with hwnd: HWND) throws {
        _ = try perform(as: IInitializeWithWindow.self) { pThis in
            try CHECKED(pThis.pointee.lpVtbl.pointee.Initialize(pThis, hwnd))
        }
    }
}

public class CustomWindow: WinUI.Window {
    /// Hardcoded menu bar height from MenuBar_themeresources.xaml in the
    /// microsoft-ui-xaml repository (the MenuBarHeight property)
    private static let menuBarHeight = 40

    var menuBar = WinUI.MenuBar()
    var child: WinUIBackend.Widget?
    var grid: WinUI.Grid
    var cachedAppWindow: WinAppSDK.AppWindow!
    var isActive = false
    var currentAlert: WinUIBackend.Alert?
    var minimumContentSize = SIMD2<Int>(0, 0)
    var maximumContentSize: SIMD2<Int>?
    var originalWindowProc: WNDPROC?

    private(set) var menuBarIsVisible = false
    /// Lets the window procedure find the window an `HWND` belongs to.
    ///
    /// `nonisolated(unsafe)` because the thing that keeps this safe is Win32's
    /// rule rather than anything the compiler can see: a window's messages are
    /// delivered only on the thread that created it, every window here is
    /// created on the UI thread, and the two writers -- `attachWindowProc` and
    /// the `WM_DESTROY` branch -- are on that thread too.
    ///
    /// Isolating it is not an option. The only reader is `windowProc`, which is
    /// a `WNDPROC`: a C function pointer, which cannot carry actor isolation and
    /// cannot await. Under the Swift 6 language mode this is one of ten errors
    /// in this module, and it is the only one where the annotation is the answer
    /// rather than a restructuring.
    ///
    /// 讓 window procedure 能由 `HWND` 找到對應的視窗。
    ///
    /// 標記 `nonisolated(unsafe)`，因為維持其安全的是 Win32 的規則，而非編譯器看得見的任何東西：
    /// 視窗訊息只會投遞至建立該視窗的執行緒，此處每個視窗都建立於 UI 執行緒，而兩處寫入方
    /// ——`attachWindowProc` 與 `WM_DESTROY` 分支——同樣位於該執行緒。
    ///
    /// 加上隔離並不可行。唯一的讀取方 `windowProc` 是一個 `WNDPROC`：C 函式指標無法攜帶 actor
    /// 隔離，也無法 await。在 Swift 6 語言模式下，這是本模組十個錯誤之一，也是其中唯一「標註即是
    /// 答案」而非需要重構的一個。
    private nonisolated(unsafe) static var windowsByHWND: [Int: CustomWindow] = [:]

    /// The amount of height to subtract off the window height to obtain the
    /// window's available content height.
    var contentHeightAdjustment: Int {
        menuBarIsVisible ? Self.menuBarHeight : 0
    }

    var scaleFactor: Double {
        // I'm leaving this code here for future travellers. Be warned that this always
        // seems to return 100% even if the scale factor is set to 125% in settings.
        // Perhaps it's only the device's built-in default scaling? But that seems pretty
        // useless, and isn't what the docs seem to imply.
        //
        //   var deviceScaleFactor = SCALE_125_PERCENT
        //   _ = GetScaleFactorForMonitor(monitor, &deviceScaleFactor)

        let hwnd = cachedAppWindow.getHWND()!
        let monitor = MonitorFromWindow(hwnd, DWORD(bitPattern: MONITOR_DEFAULTTONEAREST))!

        var x: UINT = 0
        var y: UINT = 0
        let result = GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI, &x, &y)

        let windowScaleFactor: Double
        if result == S_OK {
            windowScaleFactor = Double(x) / Double(USER_DEFAULT_SCREEN_DPI)
        } else {
            logger.warning("failed to get window scale factor, defaulting to 1.0")
            windowScaleFactor = 1
        }

        return windowScaleFactor
    }

    public override init() {
        grid = WinUI.Grid()

        super.init()

        let menuBarRowDefinition = WinUI.RowDefinition()
        let contentRowDefinition = WinUI.RowDefinition()
        grid.rowDefinitions.append(menuBarRowDefinition)
        grid.rowDefinitions.append(contentRowDefinition)
        grid.children.append(menuBar)
        WinUI.Grid.setRow(menuBar, 0)
        self.content = grid

        // NB: This event fires when the window is activated _or_ deactivated.
        self.activated.addHandler { [weak self] _, args in
            switch args?.windowActivationState {
                case .codeActivated, .pointerActivated: self?.isActive = true
                case .deactivated: self?.isActive = false
                // NB: The compiler apparently thinks we didn't exhaustively switch
                // over this enum without this `default` (even after adding a `case nil`).
                // Might be because it doesn't treat the underlying C enum as a Swift enum?
                default: break
            }
        }

        // Caching appWindow is apparently a good idea in terms of performance:
        // https://github.com/thebrowsercompany/swift-winrt/issues/199#issuecomment-2611006020
        cachedAppWindow = appWindow
        installSizeLimitHandler()

        // Default to not showing the menu bar; we only want to show it when it's non-empty
        setMenuBarVisible(menuBarIsVisible)
    }

    func installSizeLimitHandler() {
        guard originalWindowProc == nil else {
            return
        }

        guard let hwnd = cachedAppWindow.getHWND() else {
            logger.warning("failed to install WinUI size limit handler; window handle unavailable")
            return
        }

        Self.windowsByHWND[Int(bitPattern: hwnd)] = self
        let previous = SetWindowLongPtrW(
            hwnd,
            GWLP_WNDPROC,
            LONG_PTR(bitPattern: UInt64(UInt(bitPattern: unsafeBitCast(
                Self.windowProc,
                to: UnsafeRawPointer.self
            ))))
        )
        originalWindowProc = unsafeBitCast(previous, to: WNDPROC.self)
    }

    private static let windowProc: WNDPROC = { hwnd, message, wParam, lParam in
        if message == WM_GETMINMAXINFO,
           let hwnd,
           let window = CustomWindow.windowsByHWND[Int(bitPattern: hwnd)],
           let info = UnsafeMutableRawPointer(bitPattern: Int(lParam))?
               .assumingMemoryBound(to: MINMAXINFO.self)
        {
            let minimumWindowSize = window.windowTrackingSize(forContentSize: window.minimumContentSize)
            info.pointee.ptMinTrackSize.x = minimumWindowSize.x
            info.pointee.ptMinTrackSize.y = minimumWindowSize.y

            if let maximumContentSize = window.maximumContentSize {
                let maximumWindowSize = window.windowTrackingSize(forContentSize: maximumContentSize)
                info.pointee.ptMaxTrackSize.x = maximumWindowSize.x
                info.pointee.ptMaxTrackSize.y = maximumWindowSize.y
            }
        }

        if let hwnd,
           let window = CustomWindow.windowsByHWND[Int(bitPattern: hwnd)],
           let originalWindowProc = window.originalWindowProc
        {
            return CallWindowProcW(originalWindowProc, hwnd, message, wParam, lParam)
        } else {
            return DefWindowProcW(hwnd, message, wParam, lParam)
        }
    }

    private func windowTrackingSize(forContentSize contentSize: SIMD2<Int>) -> POINT {
        guard let hwnd = cachedAppWindow.getHWND() else {
            let scaleFactor = scaleFactor
            return POINT(
                x: LONG((Double(contentSize.x) * scaleFactor).rounded(.awayFromZero)),
                y: LONG(
                    (Double(contentSize.y + contentHeightAdjustment) * scaleFactor)
                        .rounded(.awayFromZero)
                )
            )
        }

        let dpi = GetDpiForWindow(hwnd)
        let effectiveDPI = dpi == 0 ? UINT(USER_DEFAULT_SCREEN_DPI) : dpi
        let scaleFactor = Double(effectiveDPI) / Double(USER_DEFAULT_SCREEN_DPI)
        let clientWidth = LONG((Double(contentSize.x) * scaleFactor).rounded(.awayFromZero))
        let clientHeight = LONG(
            (Double(contentSize.y + contentHeightAdjustment) * scaleFactor).rounded(.awayFromZero)
        )

        var rect = RECT(left: 0, top: 0, right: clientWidth, bottom: clientHeight)
        let style = DWORD(bitPattern: Int32(GetWindowLongPtrW(hwnd, GWL_STYLE)))
        let extendedStyle = DWORD(bitPattern: Int32(GetWindowLongPtrW(hwnd, GWL_EXSTYLE)))

        guard AdjustWindowRectExForDpi(
            &rect,
            style,
            false,
            extendedStyle,
            effectiveDPI
        ) else {
            logger.warning("failed to adjust WinUI size limit for window frame")
            return POINT(x: clientWidth, y: clientHeight)
        }

        return POINT(
            x: rect.right - rect.left,
            y: rect.bottom - rect.top
        )
    }

    /// Sets whether the menu bar of the current window is visible. The menu bar
    /// is what holds the in-window app menu, it's not the title bar (the one with
    /// the window controls).
    public func setMenuBarVisible(_ visible: Bool) {
        grid.rowDefinitions[0]!.height = WinUI.GridLength(
            value: visible ? Double(Self.menuBarHeight) : 0,
            gridUnitType: .pixel
        )
        menuBarIsVisible = visible
    }

    public func setChild(_ child: WinUIBackend.Widget) {
        self.child = child
        grid.children.append(child)
        WinUI.Grid.setRow(child, 1)
    }

    deinit {
        if let hwnd = cachedAppWindow?.getHWND() {
            Self.windowsByHWND.removeValue(forKey: Int(bitPattern: hwnd))
            if let originalWindowProc {
                SetWindowLongPtrW(
                    hwnd,
                    GWLP_WNDPROC,
                    LONG_PTR(bitPattern: UInt64(UInt(bitPattern: unsafeBitCast(
                        originalWindowProc,
                        to: UnsafeRawPointer.self
                    ))))
                )
            }
        }
    }
}

public final class GeometryGroupHolder {
    var group = GeometryGroup()
    var strokeStyle: StrokeStyle?
}

@MainActor
final class CustomDatePicker: StackPanel {
    override init() {
        super.init()
        self.spacing = 10
    }

    deinit {
        timeChangedEvent?.dispose()
        dateChangedEvent?.dispose()
    }

    enum DateViewType {
        case calendarView(CalendarView)
        case calendarDatePicker(CalendarDatePicker)
        case datePicker(WinUI.DatePicker)

        var asControl: Control {
            switch self {
                case .calendarView(let calendarView): calendarView
                case .calendarDatePicker(let calendarDatePicker): calendarDatePicker
                case .datePicker(let datePicker): datePicker
            }
        }

        enum Discriminator {
            case calendarView
            case calendarDatePicker
            case datePicker
        }

        var discriminator: Discriminator {
            switch self {
                case .calendarView(_): .calendarView
                case .calendarDatePicker(_): .calendarDatePicker
                case .datePicker(_): .datePicker
            }
        }
    }

    private var dateView: DateViewType?
    private var timeView: TimePicker?
    private var date = Date()
    private var calendar = Calendar.current
    private var needsUpdate = false
    var onChange: ((Date) -> Void)?
    private var timeChangedEvent: EventCleanup?
    private var dateChangedEvent: EventCleanup?

    func toggleTimeView(shown: Bool) {
        guard shown != (self.timeView != nil) else { return }

        if shown {
            let timeView = TimePicker()
            children.append(timeView)
            self.timeView = timeView
            timeChangedEvent = timeView.timeChanged.addHandler { [unowned self] _, change in
                guard let change else { return }
                self.date =
                    calendar.startOfDay(for: date)
                        + Double(change.newTime.duration) / ticksPerSecond
                self.onChange?(self.date)
            }
            needsUpdate = true
        } else {
            timeChangedEvent?.dispose()
            timeChangedEvent = nil
            children.removeAtEnd()
            self.timeView = nil
        }
    }

    func setEnabled(to isEnabled: Bool) {
        dateView?.asControl.isEnabled = isEnabled
        timeView?.isEnabled = isEnabled
    }

    func changeDateView(to newDiscriminator: DateViewType.Discriminator?) {
        guard newDiscriminator != dateView?.discriminator else { return }

        dateChangedEvent?.dispose()
        if dateView != nil {
            children.removeAt(0)
        }

        switch newDiscriminator {
            case .calendarView:
                let calendarView = CalendarView()
                dateView = .calendarView(calendarView)
                children.insertAt(0, calendarView)
                orientation = .vertical
                dateChangedEvent = calendarView.selectedDatesChanged.addHandler {
                    [unowned self] _, _ in

                    guard calendarView.selectedDates.size > 0 else {
                        let (dateTime, _) = foundationDateToComponents(self.date)
                        calendarView.selectedDates.append(dateTime)
                        return
                    }

                    self.date = componentsToFoundationDate(
                        dateTime: calendarView.selectedDates.getAt(0),
                        timeSpan: timeView?.selectedTime
                    )

                    if calendarView.selectedDates.size > 1 {
                        self.needsUpdate = true
                    }

                    self.onChange?(self.date)
                }
                needsUpdate = true
            case .calendarDatePicker:
                let calendarDatePicker = CalendarDatePicker()
                dateView = .calendarDatePicker(calendarDatePicker)
                children.insertAt(0, calendarDatePicker)
                orientation = .horizontal
                dateChangedEvent = calendarDatePicker.dateChanged.addHandler {
                    [unowned self] _, change in

                    guard let newDate = change?.newDate else { return }
                    self.date = componentsToFoundationDate(
                        dateTime: newDate,
                        timeSpan: timeView?.selectedTime
                    )
                    self.onChange?(self.date)
                }
                needsUpdate = true
            case .datePicker:
                let datePicker = WinUI.DatePicker()
                dateView = .datePicker(datePicker)
                children.insertAt(0, datePicker)
                orientation = .horizontal
                dateChangedEvent = datePicker.selectedDateChanged.addHandler {
                    [unowned self] _, _ in

                    guard let selectedDate = datePicker.selectedDate else { return }
                    self.date = componentsToFoundationDate(
                        dateTime: selectedDate,
                        timeSpan: timeView?.selectedTime
                    )
                    self.onChange?(self.date)
                }
                needsUpdate = true
            case nil:
                break
        }
    }

    func setDateRange(to range: ClosedRange<Date>) {
        guard let dateView else { return }

        let (startDate, _) = foundationDateToComponents(range.lowerBound)
        let (endDate, _) = foundationDateToComponents(range.upperBound)

        switch dateView {
            case .calendarView(let calendarView):
                calendarView.minDate = startDate
                calendarView.maxDate = endDate
            case .calendarDatePicker(let calendarDatePicker):
                calendarDatePicker.minDate = startDate
                calendarDatePicker.maxDate = endDate
            case .datePicker(let datePicker):
                datePicker.minYear = startDate
                datePicker.maxYear = endDate
        }
    }

    func updateIfNeeded(date: Date, calendar: Calendar) {
        if !needsUpdate && date == self.date && calendar == self.calendar { return }
        defer { needsUpdate = false }

        self.date = date
        self.calendar = calendar

        let (dateTime, timeSpan) = foundationDateToComponents(date)

        switch dateView {
            case .calendarView(let calendarView):
                calendarView.calendarIdentifier = identifier(for: calendar)
                switch calendarView.selectedDates.size {
                    case 0:
                        calendarView.selectedDates.append(dateTime)
                    case 1:
                        calendarView.selectedDates.setAt(0, dateTime)
                    default:
                        // `append` after clearing, not `setAt(0,)`. The old line
                        // wrote index 0 of a collection that had just been
                        // emptied. Unreached in practice -- a single-selection
                        // CalendarView never holds two dates -- which is why it
                        // survived.
                        // 清空之後要用 `append` 而非 `setAt(0,)`。原本那一行是在「剛被清空的集合」上
                        // 寫入索引 0。實務上不會走到——單選的 CalendarView 不會同時持有兩個日期——
                        // 這也正是它得以存活至今的原因。
                        calendarView.selectedDates.clear()
                        calendarView.selectedDates.append(dateTime)
                }

                // Selecting a date does not scroll to it. Without this the view
                // opens on the current month and the selection sits wherever it
                // is -- a year away, in P41's case, and off screen. What looked
                // like the bound date being ignored was the calendar's own
                // "today" marker being the only thing visible.
                //
                // Measured 2026-08-27 with P41 on WinUI: bound to 2025-08-24,
                // the grid opened on August 2026 with the 27th ringed, while
                // .automatic, .compact and .wheel all showed 2025-08-24 in the
                // same window.
                //
                // 選取某個日期並不會捲動到它。若無此呼叫，該 view 會停在當前月份，而選取項則留在它
                // 原本的位置——以 P41 的情況而言是一年之外，落在畫面之外。看起來像是「綁定值被忽略」
                // 的現象，其實是日曆自身的「今天」標記成了畫面上唯一看得見的東西。
                //
                // 2026-08-27 以 P41 於 WinUI 實測：綁定為 2025-08-24 時，格線開在 2026 年 8 月並圈出
                // 27 日，而同一個視窗中的 .automatic、.compact 與 .wheel 都顯示 2025-08-24。
                try? calendarView.setDisplayDate(dateTime)
            case .calendarDatePicker(let calendarDatePicker):
                calendarDatePicker.calendarIdentifier = identifier(for: calendar)
                calendarDatePicker.date = dateTime
            case .datePicker(let datePicker):
                datePicker.selectedDate = dateTime
            case nil:
                break
        }

        if let timeView {
            timeView.selectedTime = timeSpan
        }
    }

    private func identifier(for calendar: Calendar) -> String {
        switch calendar.identifier {
            case .chinese: return "ChineseLunarCalendar"
            case .gregorian, .iso8601: return "GregorianCalendar"
            case .hebrew: return "HebrewCalendar"
            case .islamicTabular: return "HijriCalendar"
            case .islamicUmmAlQura: return "UmAlQuraCalendar"
            case .japanese: return "JapaneseCalendar"
            case .persian: return "PersianCalendar"
            case .republicOfChina: return "TaiwanCalendar"
            #if compiler(>=6.2)
                case .vietnamese: return "VietnameseLunarCalendar"
            #endif
            case let id:
                print("Unsupported calendar identifier '\(id)'. Falling back to Gregorian.")
                return "GregorianCalendar"
        }
    }

    // Magic numbers taken from https://stackoverflow.com/a/5471380/6253337
    private let ticksPerSecond: Double = 10_000_000
    private let unixEpochInUniversalTime: Int64 = 116_444_736_000_000_000

    private func foundationDateToComponents(_ date: Date) -> (DateTime, TimeSpan) {
        let timeInterval = date.timeIntervalSince(calendar.startOfDay(for: date))

        return (
            DateTime(
                universalTime: Int64(
                    date.timeIntervalSince1970 * ticksPerSecond + Double(unixEpochInUniversalTime)
                )
            ),
            TimeSpan(duration: Int64(timeInterval * ticksPerSecond))
        )
    }

    private func componentsToFoundationDate(dateTime: DateTime, timeSpan: TimeSpan?) -> Date {
        let baseDate = Date(
            timeIntervalSince1970: Double(dateTime.universalTime - unixEpochInUniversalTime)
                / ticksPerSecond
        )

        if let timeSpan {
            let time = Double(timeSpan.duration) / ticksPerSecond
            return calendar.startOfDay(for: baseDate) + time
        } else {
            return baseDate
        }
    }

    func naturalSize() -> SIMD2<Int> {
        let timeViewSize =
            if timeView != nil {
                // Width is 242, as shown in the WinUI repository:
                // https://github.com/marcelwgn/microsoft-ui-xaml/blob/ff21f9b212cea2191b959649e45e52486c8465aa/src/controls/dev/CommonStyles/TimePicker_themeresources.xaml#L116
                // Height is experimentally 29 which I don't see anywhere in that file.
                SIMD2(242, 29)
            } else {
                SIMD2<Int>.zero
            }

        let dateViewSize =
            if let dateControl = dateView?.asControl {
                WinUIBackend.naturalSize(of: dateControl)
            } else {
                SIMD2<Int>.zero
            }

        if orientation == .horizontal {
            return SIMD2(
                x: timeViewSize.x + dateViewSize.x + Int(self.spacing),
                y: max(timeViewSize.y, dateViewSize.y)
            )
        } else {
            return SIMD2(
                x: max(timeViewSize.x, dateViewSize.x),
                y: timeViewSize.y + dateViewSize.y + Int(self.spacing)
            )
        }
    }
}

extension WinUI.FrameworkElement {
    var shouldBlockNextChangedSignal: Bool {
        get {
            (self.tag as? [String: Any])?["shouldBlockNextChangedSignal"] as? Bool ?? false
        }
        set {
            var value = self.tag as? [String: Any] ?? [:]
            value["shouldBlockNextChangedSignal"] = newValue
            self.tag = value
        }
    }
}
