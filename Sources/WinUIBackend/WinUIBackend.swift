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
        logWebViewDiagnostic("WebView2: apartment in onLaunched \(comApartmentDescription())")
        if let url = Self.url(fromLaunchArguments: args.arguments) {
            Self.receive(url)
        }
        Self.listenForRedirectedLaunches()

        Self.callback.withLock { callback in
            // We can't explicitly hop to the main actor because we haven't set up
            // our WinUI MainActor fix yet.
            MainActor.assumeIsolated {
                callback?(self)
            }
        }
    }

    static func receive(_ url: URL) {
        if let handler = onReceiveURL.withLock({ $0 }) {
            handler.handle(url)
        } else {
            queuedURLs.withLock { urls in
                urls.append(url)
            }
        }
    }

    private static func url(fromLaunchArguments arguments: String) -> URL? {
        // For an unpackaged app `arguments` is empty, and this used to return
        // nil on an empty string before it ever looked at the command line -- so
        // the URL a WinUI app was launched with never arrived: P78 read
        // "received 0" (2026-10-20).
        // 未封裝的 app 的 `arguments` 是空字串，而這裡過去在空字串時就回傳 nil,根本沒看命令列——因此 WinUI app
        // 啟動時帶的 URL 從未送達:P78 讀到「received 0」(2026-10-20)。
        url(inCommandLine: arguments)
            ?? url(inCommandLine: CommandLine.arguments.dropFirst().joined(separator: " "))
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
    BackendFeatures.Popovers,
    BackendFeatures.Paths,
    BackendFeatures.Tooltips,
    BackendFeatures.Colors,
    BackendFeatures.DatePickers,
    BackendFeatures.Windowing,
    BackendFeatures.WindowLevels,
    BackendFeatures.LinearGradients,
    BackendFeatures.RadialGradients,
    // Listed here, so `WinUIBackend+ButtonPressState.swift` must be a bare
    // `extension WinUIBackend { ... }` -- for exactly the reason the
    // `GraphicsAdapters` note directly below records.
    // 在此處列出，因此 `WinUIBackend+ButtonPressState.swift` 必須是不帶 conformance 的
    // `extension WinUIBackend { ... }`——理由與下方 `GraphicsAdapters` 註記所記的完全相同。
    BackendFeatures.ButtonPressState,
    BackendFeatures.Toolbars
{
    // GraphicsAdapters is declared on the extension in
    // WinUIBackend+GraphicsAdapters.swift, NOT here; listing it in both
    // places is `error: redundant conformance`. Only the stored property has
    // to live in the class body, since Swift has no stored properties in
    // extensions. GtkBackend has the same split for the same reason.
    // GraphicsAdapters 宣告於 WinUIBackend+GraphicsAdapters.swift 的 extension 上，**而非此處**；
    // 兩邊都列會得到 `error: redundant conformance`。只有儲存屬性必須放在類別本體，因為 Swift 的
    // extension 不能有儲存屬性。GtkBackend 基於相同理由採用相同的拆法。

    /// Storage for ``BackendFeatures/GraphicsAdapters/adapterRemoved``.
    ///
    /// Here rather than in the extension because Swift has no stored properties
    /// in extensions, which is the same reason `GtkBackend` keeps its copy in
    /// the class body. Assigning a handler starts the watch that calls it:
    /// DXGI's adapters-changed event, then a comparison of the adapters by LUID
    /// (`WinUIAdapterRemoval` in WinUIBackend+GraphicsAdapters.swift).
    ///
    /// ``BackendFeatures/GraphicsAdapters/adapterRemoved`` 的儲存空間。
    ///
    /// 放在類別本體而非 extension，因為 Swift 的 extension 不能有儲存屬性——`GtkBackend` 把它的
    /// 那一份放在類別本體，理由相同。指派 handler 就會啟動呼叫它的監看:DXGI 的 adapters-changed 事件，接著以 LUID
    /// 比對介面卡(WinUIBackend+GraphicsAdapters.swift 中的 `WinUIAdapterRemoval`)。
    public var adapterRemoved: (() -> Void)? {
        didSet {
            if adapterRemoved != nil { WinUIAdapterRemoval.start(for: self) }
        }
    }

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
    public let supportedPickerStyles: [BackendPickerStyle] = [.menu, .segmented, .radioGroup, .wheel]
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
        in environment: EnvironmentValues,
        size: SIMD2<Double>? = nil
    ) -> WinUI.Brush {
        func stops(_ gradientStops: [SwiftCrossUI.Gradient.Stop]) -> GradientStopCollection {
            let collection = GradientStopCollection()
            for stop in gradientStops {
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
                brush.gradientStops = stops(gradient.stops)
                return brush
            case .radialGradient(let gradient, let centre, let startRadius, let endRadius):
                // Radii are POINTS, as SwiftUI reads them for a shape style
                // (c04e4814 for the other four backends). The brush maps
                // relative to the bounds it paints, so a radius in points is the
                // fraction `radius / size` on each axis -- a circle in any
                // rectangle. `size` is the painted bounds; unknown (a text block
                // not yet measured), half the box stands in until it is.
                //
                // An inner radius is carried by the stops, as Android and GSK do:
                // `RadialGradient.adjustedStops` moves each location l to
                // (inner + l * (outer - inner)) / outer, and the pad spread fills
                // the inside with the first colour. This replaced a notice that
                // said the inner radius could not be drawn.
                //
                // 半徑是**點**,如 SwiftUI 對形狀樣式的解讀(其他四個 backend 見 c04e4814)。brush 以所塗繪的外框
                // 做相對對應，所以以點為單位的半徑在每一軸上就是 `radius / size` 這個比例——在任何矩形裡都是圓。
                // `size` 是塗繪的外框；未知時(文字區塊尚未量好)先以外框的一半代替，量好後再算一次。內半徑由停駐點
                // 承載，與 Android、GSK 相同:`RadialGradient.adjustedStops` 把位置 l 移到
                // (inner + l * (outer - inner)) / outer,pad 擴散以第一個顏色填滿內部。這取代了原本「畫不出內半徑」的 notice。
                let outer = max(startRadius, endRadius)
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
                if let size, size.x > 0, size.y > 0 {
                    brush.radiusX = outer / size.x
                    brush.radiusY = outer / size.y
                } else {
                    brush.radiusX = 0.5
                    brush.radiusY = 0.5
                }
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
                let remapped = RadialGradient(
                    gradient: gradient, center: .center, startRadius: startRadius,
                    endRadius: endRadius
                ).adjustedStops
                for stop in stops(remapped) {
                    brush.gradientStops.append(stop)
                }
                return brush
            case .angularGradient(let gradient, let centre, let startAngle, let endAngle):
                // Rasterised into a composition surface: XAML has no conic brush.
                // See ConicGradientBrush. Until the painted size is known (a text
                // block's first update) a square stands in, redrawn on SizeChanged.
                // 點陣化進 composition surface:XAML 沒有錐形 brush。見 ConicGradientBrush。塗繪尺寸未知時(文字區塊的
                // 第一次更新)以正方形代替，於 SizeChanged 時重畫。
                let stops = ResolvedFillStyle.angularTurnStops(
                    gradient, startAngle: startAngle, endAngle: endAngle
                ).map { (location: $0.location, colour: $0.color.resolve(in: environment)) }
                let painted = size.flatMap { $0.x > 0 && $0.y > 0 ? $0 : nil } ?? SIMD2(64, 64)
                return ConicGradientBrush(
                    stops: stops, center: centre, startAngle: startAngle, size: painted)
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
        /// Keyed the same way `sliderChangeActions` is, and for the same reason:
        /// the handler is added once when the slider is created and the closure
        /// it should call is replaced on every update.
        /// 索引方式與 `sliderChangeActions` 相同，理由也相同：handler 只在 slider 建立時加一次，
        /// 而它該呼叫的那個 closure 會在每一次更新時被替換。
        var sliderEditingActions: [ObjectIdentifier: (Bool) -> Void] = [:]
        /// Whether a slider has reported `onEditingChanged(true)` that has not
        /// yet been matched by a `false`. Read before emitting either, so an
        /// edit is reported exactly once however many values it produces, and
        /// so `pointerCaptureLost` cannot emit an unpaired `false`.
        /// 某個 slider 是否已回報過一次尚未被 `false` 配對的 `onEditingChanged(true)`。
        /// 發出任一者之前都會先讀它,如此一來:一次編輯無論產生多少個數值都只回報一次,
        /// 而 `pointerCaptureLost` 也無法發出一個沒有配對的 `false`。
        /// Focus-change handlers, replaced per layout pass, and the set of
        /// widgets whose `gotFocus`/`lostFocus` are already subscribed.
        ///
        /// Two containers because the handler changes every frame while the
        /// subscription must not. Subscribing per frame is the `began=5` shape.
        /// 焦點變更的 handler(每次 layout pass 會被換掉),以及「已訂閱 `gotFocus`/`lostFocus`」
        /// 的 widget 集合。
        ///
        /// 分成兩個容器,是因為 handler 每一幀都會變、而訂閱**不可以**。逐幀訂閱正是 `began=5` 的形狀。
        var focusChangeHandlers: [ObjectIdentifier: (Bool) -> Void] = [:]
        var widgetsWithFocusSubscription: Set<ObjectIdentifier> = []

        var sliderIsEditing: Set<ObjectIdentifier> = []
        /// Sliders whose value is being set from code right now.
        /// `setValue(ofSlider:to:)` raises `valueChanged` exactly as a drag
        /// does, so without this the control in P61 -- "a slider moved from
        /// code must NOT report an edit" -- fails.
        /// 目前正由**程式**設定數值的 slider。`setValue(ofSlider:to:)` 引發 `valueChanged`
        /// 的方式與一次拖曳完全相同,因此若無此集合,P61 的那項對照——「從程式移動的 slider
        /// **不得**回報一次編輯」——就會失敗。
        var slidersBeingSetFromCode: Set<ObjectIdentifier> = []
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

    // Not private: WinUIBackend+Symbols.swift measures a glyph through this
    // same block, and `private` at type scope reaches only the declaring file.
    // 非 private:WinUIBackend+Symbols.swift 會透過同一個 block 量測字符,而型別層級的 `private`
    // 只及於宣告它的那一個檔案。
    var measurementTextBlock: TextBlock!

    // The bordered-button padding measured once by `measureBorderedButtonPadding()`
    // in WinUIBackend+Button.swift, then reused. Measuring means realising a dummy
    // button and a TextBlock, so it is cached rather than repeated per layout pass.
    // GtkBackend and AppKitBackend hold the same property for the same reason.
    // 由 WinUIBackend+Button.swift 中的 `measureBorderedButtonPadding()` 量測一次後重複使用的
    // 帶框按鈕內距。量測需要實體化一個 dummy button 與 TextBlock,因此快取起來,而非每次 layout
    // 都重測。GtkBackend 與 AppKitBackend 基於相同理由持有同一個屬性。
    var borderedButtonPadding: SIMD2<Int>?

    /// The frame clock's subscription token, and the handler it feeds.
    /// frame clock 的訂閱 token，以及它所餵養的 handler。
    /// `addHandler` returns an `EventCleanup`, not an `EventRegistrationToken`.
    /// It is a struct carrying the token AND the close action, so unsubscribing
    /// is `dispose()` rather than a `removeHandler(token)` call.
    /// `addHandler` 回傳的是 `EventCleanup`,不是 `EventRegistrationToken`。它是一個同時攜帶
    /// token **與** close action 的 struct,因此取消訂閱是 `dispose()`,而非 `removeHandler(token)`。
    var frameClockToken: EventCleanup?
    @MainActor static var currentFrameClockHandler: (@MainActor (Double) -> Void)?

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
        // Logged so the WebView2 apartment question can be answered with two
        // thread ids rather than an inference. `SwiftApplication.main()` calls
        // `RoInitialize` on THIS thread; if the WebView's thread id differs,
        // the apartment that was chosen here was never the one WebView2 runs in.
        // 記錄下來,好讓 WebView2 的 apartment 問題能用**兩個執行緒 id** 來回答,而不是用推論。
        // `SwiftApplication.main()` 是在**這條**執行緒上呼叫 `RoInitialize` 的;若 WebView 那條執行緒
        // 的 id 不同,那麼此處所選定的 apartment 從來就不是 WebView2 實際執行所在的那一個。
        logWebViewDiagnostic("WinUIApplication.main() on thread \(GetCurrentThreadId())")
        logWebViewDiagnostic("WebView2: apartment before main \(comApartmentDescription())")
        WinUIApplication.runSingleThreaded()
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
    /// The scheme goes to `requestedTheme` on the window's grid, and every
    /// title-bar colour, buttons included, is cleared to the system default so
    /// Windows draws its own chrome for that scheme; see the body.
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
    /// 配置寫入視窗 grid 的 `requestedTheme`,而標題列的每一個顏色(含按鈕)都清回系統預設，
    /// 讓 Windows 為該配置繪製它自己的視窗裝飾；見函式本體。
    private func applyTitleBarColors(to window: Window, environment: EnvironmentValues) {
        window.grid.requestedTheme = switch environment.colorScheme {
            case .light: .light
            case .dark: .dark
        }

        // Cleared, not set. Every colour here is left at the system default so
        // Windows draws its own chrome for that theme -- #202020 and its own
        // hover and pressed shades -- rather than whatever this file thought a
        // dark title bar looks like. Painting them pure black and white does
        // make the bar dark, but pure black is not the colour Windows uses, and
        // a title bar blacker than every other window's is decided by the app
        // rather than inherited -- the same reason the content background is
        // `ApplicationPageBackgroundThemeBrush`.
        //
        // 是「清除」而非「設定」。此處每一個顏色都保持系統預設，好讓 Windows 為該主題繪製它自己的
        // 視窗裝飾——#202020 及其自有的 hover 與 pressed 色階——而不是由本檔認定「深色標題列該長
        // 什麼樣」。以純黑與純白明確上色雖然也能讓標題列變深，但純黑並非 Windows 所使用的顏色，
        // 一條比其他所有視窗都更黑的標題列是 app「決定」出來的、而非「繼承」而來的——內容背景使用
        // `ApplicationPageBackgroundThemeBrush` 也是同一個理由。
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

    /// The work area of the window's monitor -- the screen without the taskbar
    /// -- from the window's current top-left corner, less its frame, the menu
    /// bar and the toolbar, in DIPs. From the corner and not the whole area
    /// because WinUI places a new window at y 128 at 125%, and a window sized
    /// to the work area from there still runs 128 px off the bottom.
    /// 視窗所在顯示器的工作區(扣掉工作列的螢幕),從視窗目前的左上角算起，再扣掉外框、選單列與工具列，單位為 DIP。
    /// 從左上角算而不是用整個工作區，是因為 WinUI 在 125% 下把新視窗放在 y 128,從那裡開一個工作區高的視窗，底部仍會
    /// 超出 128 px。
    public func maximumSizeOnScreen(ofWindow window: Window) -> SIMD2<Int>? {
        guard let hwnd = window.getHWND(),
            let monitor = MonitorFromWindow(hwnd, DWORD(bitPattern: MONITOR_DEFAULTTONEAREST))
        else { return nil }
        var info = MONITORINFO()
        info.cbSize = DWORD(MemoryLayout<MONITORINFO>.size)
        var windowRect = RECT()
        guard GetMonitorInfoW(monitor, &info), GetWindowRect(hwnd, &windowRect) else {
            return nil
        }
        let work = info.rcWork
        let left = min(max(windowRect.left, work.left), work.right)
        let top = min(max(windowRect.top, work.top), work.bottom)

        let dpi = GetDpiForWindow(hwnd)
        let effectiveDPI = dpi == 0 ? UINT(USER_DEFAULT_SCREEN_DPI) : dpi
        let scaleFactor = Double(effectiveDPI) / Double(USER_DEFAULT_SCREEN_DPI)
        var frame = RECT(left: 0, top: 0, right: 0, bottom: 0)
        let style = DWORD(bitPattern: Int32(GetWindowLongPtrW(hwnd, GWL_STYLE)))
        let extendedStyle = DWORD(bitPattern: Int32(GetWindowLongPtrW(hwnd, GWL_EXSTYLE)))
        _ = AdjustWindowRectExForDpi(&frame, style, false, extendedStyle, effectiveDPI)

        let width = Double(work.right - left - (frame.right - frame.left)) / scaleFactor
        let height = Double(work.bottom - top - (frame.bottom - frame.top)) / scaleFactor
        return SIMD2(
            Int(width.rounded(.towardZero)),
            Int(height.rounded(.towardZero)) - window.contentHeightAdjustment
        )
    }

    public func isWindowProgrammaticallyResizable(_ window: Window) -> Bool {
        // A full-screen window answers false, as AppKitBackend and GtkBackend
        // do, or the layout system keeps proposing sizes the window will not
        // take.
        // 全螢幕視窗回答 false,與 AppKitBackend、GtkBackend 相同，否則版面系統會不斷提出視窗不會接受的尺寸。
        window.appWindow.presenter.kind != .fullScreen
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
        WinUIParentLinks.recordWindowRoot(widget)
        try! widget.updateLayout()
        widget.actualThemeChanged.addHandler { _, _ in
            Task { @MainActor in
                self.rootEnvironmentChangeHandler?()
            }
        }
    }

    /// Whether `SCUI_WINUI_SNAPSHOT_QUIT_TEST` has run; it runs for the first window only.
    /// `SCUI_WINUI_SNAPSHOT_QUIT_TEST` 是否已執行；只對第一個視窗執行。
    nonisolated(unsafe) private static var snapshotQuitTestStarted = false

    public func show(window: Window) {
        try! window.activate()

        // `SCUI_WINUI_SNAPSHOT_QUIT_TEST=1`: once the first window has content, ask the
        // app to exit and take a snapshot while the exit is pending, so the snapshot's
        // nested message pump runs through it. The process must still end; see
        // `pump(until:)` and todo.md's "WinUI snapshot may consume WM_QUIT". Nothing
        // in the public API reaches that pump with an exit pending, hence the switch.
        // Measured 2026-10-20 with P17: the process ended 3-4 s after launch, rc 0,
        // with this pump and with one that swallowed WM_QUIT alike -- WinUI's exit
        // does not depend on a WM_QUIT the nested pump could take. A bare
        // PostQuitMessage, by contrast, ends no WinUI app, pumped or not.
        // `SCUI_WINUI_SNAPSHOT_QUIT_TEST=1`:第一個視窗有內容後，要求 app 結束，並在結束待處理時做一次截圖，讓截圖的
        // 巢狀訊息 pump 經過它。行程仍必須結束；見 `pump(until:)` 與 todo.md「WinUI snapshot 可能吞掉退出訊息」。公開
        // API 走不到「結束待處理時進入那個 pump」,因此用此開關。2026-10-20 以 P17 實測：行程在啟動後 3-4 秒結束、rc 0,
        // 不論是這個 pump 還是會吞掉 WM_QUIT 的 pump——WinUI 的結束不依賴巢狀 pump 拿得走的 WM_QUIT。相對地，單純的
        // PostQuitMessage 無論有沒有 pump,都結束不了 WinUI app。
        if ProcessInfo.processInfo.environment["SCUI_WINUI_SNAPSHOT_QUIT_TEST"] == "1",
            !Self.snapshotQuitTestStarted
        {
            Self.snapshotQuitTestStarted = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                MainActor.assumeIsolated {
                    guard let content = window.content as? FrameworkElement else { return }
                    try? Application.current?.exit()
                    let shot = Self.snapshot(of: content)
                    FileHandle.standardError.write(
                        Data(
                            ("snapshot-quit-test: snapshot "
                                + (shot == nil ? "nil" : "taken")
                                + " after Application.exit()\n").utf8)
                    )
                }
            }
        }

        #if canImport(InputEvent)
            if ActionFileReplay.requestedFile != nil {
                FileHandle.standardError.write(
                    Data("-actionfile: WinUIBackend show(window:) scheduling replay\n".utf8)
                )
            }
            // Only ever fires for the first window, and only when -actionfile
            // was passed. See InputEvent's ActionFileReplay.
            //
            // Handled here, not only in GtkBackend where the flag was first
            // parsed: Win32Synthesiser is a Windows implementation, and a
            // backend that is given a flag and quietly does nothing with it is
            // inconsistent whether or not it is the default.
            //
            // 僅對第一個視窗生效，且僅在有傳入 -actionfile 時。詳見 InputEvent 的 ActionFileReplay。
            //
            // 在此處理，而非只在最先解析該旗標的 GtkBackend 中處理:Win32Synthesiser 是一個 Windows 實作，
            // 而一個 backend 收到旗標卻安靜地什麼也不做，本身就是不一致，無論它是不是預設的那一個。
            // `taplabel`: see WinUIBackend+LabelLocator.swift.
            // `taplabel`:見 WinUIBackend+LabelLocator.swift。
            installLabelLocator(for: window)
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

    /// Hangs a ``KeyboardShortcut`` on a menu item as a `KeyboardAccelerator`.
    ///
    /// WinUI draws the accelerator's text beside the item by itself, so nothing
    /// here has to format "Ctrl+S".
    ///
    /// 以一個 `KeyboardAccelerator` 的形式,把 ``KeyboardShortcut`` 掛到 menu item 上。
    ///
    /// WinUI 會自行在該項目旁邊繪出該加速鍵的文字,因此此處不必格式化「Ctrl+S」。
    private func applyShortcut(_ shortcut: KeyboardShortcut?, to item: MenuFlyoutItemBase) {
        guard let shortcut else { return }
        guard let key = Self.virtualKey(for: shortcut.key) else {
            // Loud rather than silent: an unbindable shortcut is a menu item
            // that looks configured and does nothing when the key is pressed.
            // 說出來而不是沉默:一個綁不上去的快捷鍵,會是一個「看起來設定好了、按下去卻毫無反應」
            // 的 menu item。
            debugLogOnce(
                "no virtual key for keyboard shortcut '\(shortcut.key.character)';"
                    + " that menu item has no shortcut"
            )
            return
        }
        let accelerator = KeyboardAccelerator()
        accelerator.key = key
        accelerator.modifiers = Self.virtualKeyModifiers(for: shortcut.modifiers)
        item.keyboardAccelerators.append(accelerator)
    }

    /// ``EventModifiers`` as WinRT's `VirtualKeyModifiers`.
    ///
    /// **`VirtualKeyModifiers` is a `typealias` to a C enum with `static var`
    /// members bolted on -- NOT a Swift `OptionSet`** -- so there is no `.union`
    /// and combining is a bitwise or on `rawValue` -- the same shape as
    /// `ManipulationModes`, where `.union` fails with "value of type
    /// 'ManipulationModes' has no member 'union'".
    ///
    /// **`.command` becomes Control and `.option` becomes `menu`.** SwiftUI's
    /// default modifier is `.command` because it was written for macOS; Windows
    /// has no Command key and Control plays its role, which is what
    /// ``EventModifiers/command`` documents. WinRT calls the Alt key `menu`,
    /// after the Win32 `VK_MENU` -- it is Alt, not a menu.
    ///
    /// `capsLock` and `numericPad` are dropped. They are keyboard STATES, not
    /// accelerator modifiers, in WinRT exactly as in GTK; there is nothing to
    /// map them to and a shortcut carrying one still binds on its real
    /// modifiers.
    ///
    /// 以 WinRT 的 `VirtualKeyModifiers` 表示的 ``EventModifiers``。
    ///
    /// **`VirtualKeyModifiers` 是一個指向 C enum、再外掛 `static var` 成員的 `typealias`——
    /// 而不是 Swift 的 `OptionSet`**——因此沒有 `.union`,組合的方式是對 `rawValue` 做位元或。
    /// 那與 `ManipulationModes` 是同一個形狀(對它使用 `.union` 會得到「value of type
    /// 'ManipulationModes' has no member 'union'」)。
    ///
    /// **`.command` 變成 Control,`.option` 變成 `menu`。** SwiftUI 的預設修飾鍵是 `.command`,
    /// 因為它是為 macOS 寫的;Windows 沒有 Command 鍵,扮演其角色的是 Control,而
    /// ``EventModifiers/command`` 記載的正是這件事。WinRT 把 Alt 鍵稱為 `menu`,承襲自 Win32 的
    /// `VK_MENU`——它是 Alt,不是選單。
    ///
    /// `capsLock` 與 `numericPad` 會被丟棄。它們在 WinRT 中與在 GTK 中一樣是鍵盤**狀態**、不是加速鍵的
    /// 修飾鍵;沒有東西可以對應過去,而一個帶著它們的快捷鍵仍會以它真正的修飾鍵綁定。
    static func virtualKeyModifiers(for modifiers: EventModifiers) -> UWP.VirtualKeyModifiers {
        var raw = UWP.VirtualKeyModifiers.none.rawValue
        if modifiers.contains(.control) || modifiers.contains(.command) {
            raw |= UWP.VirtualKeyModifiers.control.rawValue
        }
        if modifiers.contains(.shift) { raw |= UWP.VirtualKeyModifiers.shift.rawValue }
        if modifiers.contains(.option) { raw |= UWP.VirtualKeyModifiers.menu.rawValue }
        return UWP.VirtualKeyModifiers(rawValue: raw)
    }

    /// The `VirtualKey` for a ``KeyEquivalent``.
    ///
    /// **Letters and digits are derived by ARITHMETIC on `.a` and `.number0`,
    /// not by naming thirty-six constants.** `VirtualKey`'s raw values are the
    /// Win32 VK codes, where VK_A is 0x41 and VK_0 is 0x30 -- contiguous, and
    /// equal to the ASCII codes of the uppercase forms. Deriving from
    /// `VirtualKey.a.rawValue` also means this code never states what the raw
    /// value's TYPE is, so it cannot be wrong about it.
    ///
    /// `delete` is U+007F, forward delete, and maps to `VirtualKey.delete`. The
    /// separate `VirtualKey.back` (backspace) is deliberately not reachable
    /// here, because ``KeyEquivalent`` has no constant for backspace and its own
    /// documentation warns against conflating the two just because macOS labels
    /// backspace "delete".
    ///
    /// ``KeyEquivalent`` 所對應的 `VirtualKey`。
    ///
    /// **字母與數字是由 `.a` 與 `.number0` 以算術推導的,而不是點名三十六個常數。** `VirtualKey` 的
    /// raw value 就是 Win32 的 VK 碼,其中 VK_A 是 0x41、VK_0 是 0x30——它們是連續的,而且等於其大寫
    /// 形式的 ASCII 碼。從 `VirtualKey.a.rawValue` 推導,也意謂著這段程式碼從未陳述那個 raw value 的
    /// **型別**,因此它不可能把型別寫錯。
    ///
    /// `delete` 是 U+007F 的向前刪除,對應到 `VirtualKey.delete`。另一個 `VirtualKey.back`
    /// (backspace)在此處刻意不可達,因為 ``KeyEquivalent`` 並沒有 backspace 的常數,而它自己的文件
    /// 就在警告:不要只因為 macOS 把 backspace 標示為「delete」就把兩者混為一談。
    static func virtualKey(for key: KeyEquivalent) -> UWP.VirtualKey? {
        let scalars = Array(key.character.unicodeScalars)
        guard scalars.count == 1, let scalar = scalars.first else { return nil }

        switch scalar {
            case "\u{F700}": return .up
            case "\u{F701}": return .down
            case "\u{F702}": return .left
            case "\u{F703}": return .right
            case "\u{1B}": return .escape
            case "\u{7F}": return .delete
            case "\u{F728}": return .delete
            case "\u{F729}": return .home
            case "\u{F72B}": return .end
            case "\u{F72C}": return .pageUp
            case "\u{F72D}": return .pageDown
            case "\u{F739}": return .clear
            case "\u{9}": return .tab
            case " ": return .space
            case "\r": return .enter
            default: break
        }

        let upper = Character(scalar).uppercased()
        guard let ascii = upper.unicodeScalars.first?.value, upper.count == 1 else { return nil }
        if ascii >= 0x41, ascii <= 0x5A {
            return UWP.VirtualKey(
                rawValue: UWP.VirtualKey.a.rawValue + numericCast(ascii - 0x41)
            )
        }
        if ascii >= 0x30, ascii <= 0x39 {
            return UWP.VirtualKey(
                rawValue: UWP.VirtualKey.number0.rawValue + numericCast(ascii - 0x30)
            )
        }
        return nil
    }

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
                // The shortcut arrives in the environment, on the same line as
                // `isEnabled` and for the same reason -- see
                // `EnvironmentValues.keyboardShortcut`.
                // 快捷鍵是從 environment 來的,與 `isEnabled` 在同一行、基於同一個理由——
                // 見 `EnvironmentValues.keyboardShortcut`。
                applyShortcut(environment.keyboardShortcut, to: widget)
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
                applyShortcut(environment.keyboardShortcut, to: widget)
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
        // `SCUI_DEBUG_MENU_DUMP=1`: the menus as built, read back from the
        // MenuBarItems just attached, in the form of `CommandLayout.textDescription`
        // (title, items two spaces in, `---`, submenus one level deeper) so P92 can
        // compare the bar the platform shows with the layout the framework made.
        // `SCUI_DEBUG_MENU_DUMP=1`:讀回剛附加的 MenuBarItem,以 `CommandLayout.textDescription` 的格式印出
        // (標題、項目縮排兩格、`---`、子選單再深一層),讓 P92 比對平台顯示的選單列與框架產生的 layout。
        if ProcessInfo.processInfo.environment["SCUI_DEBUG_MENU_DUMP"] == "1" {
            var lines: [String] = []
            func dump(_ item: MenuFlyoutItemBase, _ depth: Int) {
                let pad = String(repeating: "  ", count: depth)
                if let submenu = item as? MenuFlyoutSubItem {
                    lines.append(pad + submenu.text)
                    for index in 0..<Int(submenu.items.size) {
                        if let child = submenu.items.getAt(UInt32(index)) { dump(child, depth + 1) }
                    }
                } else if item is MenuFlyoutSeparator {
                    lines.append(pad + "---")
                } else if let toggle = item as? ToggleMenuFlyoutItem {
                    lines.append(pad + toggle.text)
                } else if let button = item as? MenuFlyoutItem {
                    lines.append(pad + button.text)
                } else {
                    lines.append(pad + "?\(type(of: item))")
                }
            }
            for menu in items {
                lines.append(menu.title)
                for index in 0..<Int(menu.items.size) {
                    if let child = menu.items.getAt(UInt32(index)) { dump(child, 1) }
                }
            }
            FileHandle.standardError.write(
                Data(("menu-dump begin\n" + lines.joined(separator: "\n") + "\nmenu-dump end\n").utf8))
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

        let locale = Foundation.Locale.windowsCurrent

        return
            defaultEnvironment
                .with(\.colorScheme, isLight ? .light : .dark)
                .with(\.appPhase, windows.contains(where: \.isActive) ? .active : .inactive)
                .with(\.locale, locale)
                .with(\.calendar, locale.calendar)
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
        // `window.scaleFactor` is computed from `GetDpiForMonitor` and written
        // to the environment here; without it the environment carries 1 on
        // every display. Being correct at window creation matters: `Image`
        // re-renders when this changes, so on a 150% display a wrong 1 renders
        // at the wrong scale from the first frame. Keeping it current after a
        // move is `setWindowEnvironmentChangeHandler` below.
        //
        // `window.scaleFactor` 由 `GetDpiForMonitor` 算出，並在此寫入 environment;少了這一步，environment
        // 在任何顯示器上都帶著 1。在建立視窗時就正確是必要的:`Image` 會在此值變動時重新繪製，因此在 150%
        // 的顯示器上，錯誤的 1 會讓它從第一個 frame 起就以錯誤的比例繪製。視窗移動後保持更新則由下方的
        // `setWindowEnvironmentChangeHandler` 負責。
        rootEnvironment
            .with(\.scenePhase, window.isActive ? .active : .inactive)
            .with(\.windowScaleFactor, window.scaleFactor)
    }

    public func setWindowEnvironmentChangeHandler(
        of window: Window,
        to action: @escaping @Sendable @MainActor () -> Void
    ) {
        // A scale change recomputes the environment the same way activation
        // does, so `windowScaleFactor` follows the window across displays.
        // 縮放變更與啟用一樣會重新計算 environment,讓 `windowScaleFactor` 隨視窗跨顯示器更新。
        window.scaleFactorChangeHandler = { [weak self] in
            if let rootHandler = self?.rootEnvironmentChangeHandler {
                rootHandler()
            } else {
                action()
            }
        }

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
        WinUIParentLinks.record(child: child, in: container)
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
        // A fully transparent colour gets no brush at all. XAML hit-tests any
        // element with a brush, Transparent included, and only a null
        // background lets the pointer through; so `Color.clear` laid over a
        // button swallowed its clicks here, while GTK on Windows, GTK under
        // WSLg and AppKit all pass them on. Measured 2026-10-22 on P10: Covered
        // clicks stayed at 0 on WinUI by taplabel and by coordinates alike.
        // 完全透明的顏色不給筆刷。XAML 會對任何有筆刷的元素做命中測試(Transparent 也算),只有 null 背景會讓指標穿過;
        // 所以蓋在按鈕上的 `Color.clear` 在這裡吃掉了點擊，而 Windows 上的 GTK、WSLg 上的 GTK 與 AppKit 都會讓點擊穿過。
        // 2026-10-22 於 P10 實測:WinUI 上不論以 taplabel 或座標點擊，Covered 都停在 0。
        guard color.opacity > 0 else {
            canvas.background = nil
            return
        }
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
        } else if let wheel = widget as? WheelPicker {
            return wheel.naturalSize()
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
                // 320x300 cut the last week off and wrapped "Mo" and "We"
                // (P41, 2026-10-29); 340x360 draws the whole month, as the
                // locale buttons' re-measured size does.
                // 320x300 會裁掉最後一週、讓「Mo」「We」折行(P41,2026-10-29);340x360 畫得出整個月，與 locale 按鈕重新量測後的尺寸一樣。
                adjustment = SIMD2(340, 360)
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
        // A Path's margin is the stroke outset `renderPath` adds; zero means
        // "this is the frame size", which `renderPath` grows from.
        // Path 的 margin 是 `renderPath` 加上的描邊外擴；歸零代表「這是 frame 尺寸」,`renderPath` 由此擴大。
        if widget is WinUI.Path {
            widget.margin = Thickness(left: 0, top: 0, right: 0, bottom: 0)
        }
        // A mesh view draws at its size, and it was not redrawn when that size changed:
        // P95 under SCUI_P95_GROW grew its window to 720 points and the swap chain stayed
        // 360 wide, its drawable never logged again (2026-10-20). SizeChanged did not
        // reach it, so the size that is set here asks for the frame itself.
        // mesh view 依自己的尺寸繪製，而尺寸改變時它沒有重畫:2026-10-20 P95 在 SCUI_P95_GROW 下視窗長到 720 點，
        // swap chain 卻停在 360 寬,drawable 再也沒有記錄。SizeChanged 沒有傳到它，所以在這裡設定尺寸時直接要求重畫。
        if let mesh = widget as? Mesh3DD3DView {
            mesh.requestRender()
        }
        (widget as? ClippedCanvas)?.clipToBounds(width: Double(size.x), height: Double(size.y))
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

    // Not private, for the same reason as `measurementTextBlock` above:
    // WinUIBackend+Symbols.swift measures a glyph through it.
    // 同樣不設為 private,理由與上方的 `measurementTextBlock` 相同:
    // WinUIBackend+Symbols.swift 會透過它量測字符。
    static func measure(
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
        // The width is rounded up and given one DIP more. WinUI rounds layout to
        // physical pixels, so at 125% a TextBlock arranged at the width it
        // measured can come out a fraction of a DIP narrower, and with
        // `.characterEllipsis` that trims the last word: P47's "unknown" drew
        // as "unkno...", P102's "EDITOR (long press, then drag)" lost "drag)".
        // Rounding up alone did not cure either; one DIP more cured both
        // (2026-10-19).
        // 寬度無條件進位後再多給一個 DIP。WinUI 會把版面捨入到實體像素，所以在 125% 下，以量到的寬度
        // 排版的 TextBlock 可能窄了零點幾個 DIP，而在 `.characterEllipsis` 之下那就會截掉最後一個字：
        // P47 的 "unknown" 畫成 "unkno…",P102 的 "EDITOR (long press, then drag)" 掉了 "drag)"。
        // 只進位兩者都沒好，多給一個 DIP 兩者都好了(2026-10-19)。
        return SIMD2(
            Int(computedSize.width.rounded(.up)) + 1,
            Int(computedSize.height)
        )
    }

    /// The radial text gradient each block was last given, for its size-change
    /// handler; see `updateTextView`. 每個區塊最近一次拿到的放射文字漸層，供其尺寸變更 handler 使用。
    nonisolated(unsafe) static var radialTextGradients: [ObjectIdentifier: (ResolvedFillStyle, EnvironmentValues)] = [:]
    /// Blocks that already have that handler. 已經掛上該 handler 的區塊。
    nonisolated(unsafe) static var radialTextGradientBlocks: Set<ObjectIdentifier> = []

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
        environment.apply(to: block)
        // A gradient as the text's brush: XAML maps a brush's points onto the
        // element's bounds, as `EnvironmentValues.textGradient` means them.
        // 漸層作為文字的 brush:XAML 把 brush 的點對應到元素的外框，正是 `EnvironmentValues.textGradient` 的意思。
        if let gradient = environment.textGradient {
            block.foreground = WinUIBackend.brush(
                for: gradient, in: environment,
                size: SIMD2(block.actualWidth, block.actualHeight)
            )
            // A radial radius is in points, so it needs the block's size, which
            // the first update does not have yet: the brush is made again whenever
            // the size changes, from the latest gradient. One handler per block.
            // 放射半徑以點為單位，需要區塊的尺寸，而第一次更新時還沒有：每當尺寸改變，就以最新的漸層重做 brush。
            // 每個區塊只掛一個 handler。
            let key = ObjectIdentifier(block)
            if gradient.needsPaintedSize {
                Self.radialTextGradients[key] = (gradient, environment)
                if Self.radialTextGradientBlocks.insert(key).inserted {
                    block.sizeChanged.addHandler { [weak block] _, _ in
                        MainActor.assumeIsolated {
                            guard let block,
                                let latest = WinUIBackend.radialTextGradients[ObjectIdentifier(block)]
                            else { return }
                            block.foreground = WinUIBackend.brush(
                                for: latest.0, in: latest.1,
                                size: SIMD2(block.actualWidth, block.actualHeight)
                            )
                        }
                    }
                }
            } else {
                Self.radialTextGradients[key] = nil
            }
        }
    }

    public func createSimpleButton() -> Widget {
        let button = CustomButton()
        button.content = button.label
        button.click.addHandler { [weak internalState] _, _ in
            guard let internalState else { return }
            internalState.buttonClickActions[ObjectIdentifier(button)]?()
        }
        return button
    }

    public func updateSimpleButton(
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

        /// `.listStyle(.sidebar)`: drawn as a NavigationView pane is -- the
        /// pane background resource and 36-pixel rows with tighter padding --
        /// rather than as a content list.
        /// `.listStyle(.sidebar)`:畫成 NavigationView 窗格的樣子——窗格背景資源、36 像素高且內距較緊的列——而非內容清單。
        var isSidebar = false

        static let sidebarRowHeight = 36
        static let defaultRowHeight = 40

        var rowPadding: Thickness {
            isSidebar
                ? Thickness(left: 12, top: 6, right: 12, bottom: 6)
                : Thickness(left: 16, top: 8, right: 12, bottom: 8)
        }

        /// The padding and height every row gets, on the eager and lazy paths.
        /// eager 與 lazy 兩條路徑上每一列都套用的內距與高度。
        func styleRow(_ row: WinUI.ListViewItem) {
            row.padding = rowPadding
            if isSidebar {
                row.minHeight = Double(Self.sidebarRowHeight)
            } else {
                try? row.clearValue(WinUI.FrameworkElement.minHeightProperty)
            }
        }

        /// Set by `setLazyRows`. When present, the list is on the lazy path: its
        /// content comes from here per visible row rather than from an eager
        /// array, and selection is addressed by index instead of by holding
        /// `ListViewItem` instances in `currentItems`.
        /// 由 `setLazyRows` 設定。存在時,清單走 lazy 路徑:其內容逐可見列從這裡取得、而非取自一個
        /// eager 陣列,選取也改以索引定址、而不是把 `ListViewItem` 實例留在 `currentItems` 裡。
        var lazyProvider: ((Int) -> (widget: WinUI.FrameworkElement, height: Int)?)?

        /// The `ContainerContentChanging` handler is attached at most once.
        /// Re-attaching on every `setLazyRows` would fire the provider N times
        /// per visible row, the shape this backend's slider hit as `began=5`.
        /// `ContainerContentChanging` 的 handler 最多只掛一次。若每次 `setLazyRows` 都重掛,provider
        /// 會為每一可見列觸發 N 次——正是本 backend slider 撞上的 `began=5` 那個形狀。
        var lazyHandlerAttached = false

        /// Set by `setLazyRowReleaseHandler`. Called with a row's index when the
        /// container that held it is recycled, so the framework can drop that
        /// row's view-graph node.
        /// 由 `setLazyRowReleaseHandler` 設定。當持有某列的容器被回收時,以該列的索引呼叫它,
        /// 好讓框架丟掉那一列的 view-graph 節點。
        var lazyRowReleaseHandler: ((Int) -> Void)?

        // No per-container record of which row it shows is kept. A map keyed
        // by `ObjectIdentifier` does not work -- the binding hands out a fresh
        // Swift wrapper per access, so one address served rows 2-7 and then
        // 14-18 -- and the container's `Tag` does not round-trip through this
        // binding. `ContainerContentChanging`'s `itemIndex` is used instead;
        // see the note in WinUIBackend+LazyListRows.swift.
        // 不為容器記錄它顯示哪一列。以 `ObjectIdentifier` 為鍵的表行不通——綁定層每次存取都新建一個 Swift
        // wrapper,同一個位址先後服務了第 2-7 列與第 14-18 列——而容器的 `Tag` 在這個綁定上無法來回。改用
        // `ContainerContentChanging` 的 `itemIndex`;見 WinUIBackend+LazyListRows.swift 中的註記。
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
        let isSidebar = environment.backendListStyle == .sidebar
        listView.isSidebar = isSidebar
        if isSidebar,
            let pane = WinUI.Application.current?.resources
                .lookup("NavigationViewDefaultPaneBackground") as? WinUI.Brush
        {
            listView.background = pane
        } else {
            try? listView.clearValue(WinUI.Control.backgroundProperty)
        }
    }

    public func baseItemPadding(ofSelectableListView listView: Widget) -> EdgeInsets {
        let padding = (listView as! CustomListView).rowPadding
        return EdgeInsets(
            top: padding.top,
            bottom: padding.bottom,
            leading: padding.left,
            trailing: padding.right
        )
    }

    public func minimumRowSize(ofSelectableListView listView: Widget) -> SIMD2<Int> {
        let listView = listView as! CustomListView
        return SIMD2(
            80,
            listView.isSidebar ? CustomListView.sidebarRowHeight : CustomListView.defaultRowHeight
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
            listView.styleRow(listItem)
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
        // On the lazy path there are no retained `ListViewItem` instances to
        // hand to `selectedItem` -- the containers are virtualized and most do
        // not exist. Address the selection by index instead, which WinUI
        // resolves against the item source whether or not the row is realized.
        // 在 lazy 路徑上,沒有被保留的 `ListViewItem` 實例可以交給 `selectedItem`——容器是虛擬化的,
        // 大多數並不存在。改以索引定址選取,WinUI 會對著 item source 解析它,無論該列是否已被實體化。
        if listView.lazyProvider != nil {
            listView.selectedIndex = Int32(index ?? -1)
            return
        }
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

            let id = ObjectIdentifier(slider)

            // An edit BEGINS at the first value a user interaction produces.
            // See the block below for why this is not `pointerPressed`.
            // 一次編輯**開始於**使用者互動所產生的第一個數值。此處不用 `pointerPressed`
            // 的原因見下方那段。
            if !internalState.slidersBeingSetFromCode.contains(id),
                !internalState.sliderIsEditing.contains(id)
            {
                internalState.sliderIsEditing.insert(id)
                internalState.sliderEditingActions[id]?(true)
            }

            internalState.sliderChangeActions[id]?(
                Double(event?.newValue ?? 0)
            )
        }
        // `pointerCaptureLost` ends the edit rather than `pointerReleased`,
        // because a drag that leaves the control still ends the edit, and a
        // release outside the slider does not raise `pointerReleased` on it --
        // the same reasoning as UIKit taking `.touchUpOutside` and
        // `.touchCancel` alongside `.touchUpInside`. It does fire at the end of
        // a drag: P61 reads `ended=1` with
        // `actions/win/P61-drag-the-trough.actions` (2026-09-10).
        //
        // 以 `pointerCaptureLost` 而非 `pointerReleased` 結束編輯，因為一次「移出控制項之外」的拖曳
        // 仍然結束了那次編輯，而在 slider 之外放開並不會在它身上引發 `pointerReleased`——與 UIKit 除了
        // `.touchUpInside` 之外還要收下 `.touchUpOutside` 與 `.touchCancel` 是同一個道理。它確實會在
        // 拖曳結束時觸發:P61 以 `actions/win/P61-drag-the-trough.actions` 讀到 `ended=1`(2026-09-10)。
        //
        // THE BEGINNING OF AN EDIT DOES NOT COME FROM A POINTER EVENT HERE, and
        // two attempts to make it are recorded below rather than deleted --
        // both compile, and both do nothing.
        //
        //  1. `slider.pointerPressed.addHandler { ... }`. Measured 2026-09-10
        //     with `actions/win/P61-drag-the-trough.actions`: P61 read
        //     `began=0 ended=1`. `Slider`'s own control template handles the
        //     routed event before it reaches a subscriber, so the handler is
        //     never called.
        //  2. `slider.addHandler(UIElement.pointerPressedEvent, handler, true)`
        //     -- `handledEventsToo: true`, which is the documented way past a
        //     handled routed event. Also measured, also `began=0`. The binding
        //     compiles it but `UIElement.AddHandlerImpl` boxes the handler
        //     through `__ABI_.AnyWrapper`, producing a generic `IInspectable`
        //     rather than the `IPointerEventHandler` XAML queries for, and the
        //     delegate is silently never invoked.
        //
        // So the edit begins at the first `valueChanged` that a user
        // interaction produces, and `slidersBeingSetFromCode` is what keeps
        // `setValue(ofSlider:)` from looking like one. GtkBackend arrives at
        // the same place from the other direction: there `pressed` fires and
        // `released` never does, so it ends on `end`.
        //
        // **一次編輯的開始,在此處並非來自 pointer 事件**,而下方記下的是兩次嘗試——不是刪掉——
        // 因為它們**都編譯得過,也都什麼都沒做**。
        //
        //  1. `slider.pointerPressed.addHandler { ... }`。2026-09-10 以
        //     `actions/win/P61-drag-the-trough.actions` 實測:P61 讀到 `began=0 ended=1`。
        //     `Slider` 自己的 control template 在該 routed event 抵達訂閱者**之前**就把它
        //     handle 掉了,因此那個 handler 從未被呼叫。
        //  2. `slider.addHandler(UIElement.pointerPressedEvent, handler, true)`——
        //     `handledEventsToo: true`,那正是文件所述「繞過一個已被 handle 的 routed event」
        //     的做法。同樣實測過,同樣是 `began=0`。binding 編譯得過,但
        //     `UIElement.AddHandlerImpl` 會把 handler 經由 `__ABI_.AnyWrapper` 裝箱,
        //     產出的是一個泛用的 `IInspectable`,而非 XAML 所查詢的 `IPointerEventHandler`,
        //     於是那個 delegate 被靜默地永不呼叫。
        //
        // 因此,編輯開始於使用者互動所產生的**第一個** `valueChanged`,而
        // `slidersBeingSetFromCode` 正是用來讓 `setValue(ofSlider:)` 不會看起來像那樣。
        // GtkBackend 從**反方向**抵達同一個地方:那裡 `pressed` 會觸發而 `released` 永遠不會,
        // 所以它結束於 `end`。
        slider.pointerCaptureLost.addHandler { [weak internalState, weak slider] _, _ in
            guard let internalState, let slider else { return }
            let id = ObjectIdentifier(slider)
            // Only if an edit actually began. Pressing the handle and releasing
            // without moving raises this with no value change, and an unpaired
            // `false` is worse than a missing one.
            // 只在確實開始過一次編輯時才發。按住把手、不移動就放開,同樣會引發本事件卻沒有
            // 任何數值變化,而**一個沒有配對的 `false`,比少一個更糟**。
            guard internalState.sliderIsEditing.remove(id) != nil else { return }
            internalState.sliderEditingActions[id]?(false)
        }
        slider.stepFrequency = 0.01
        return slider
    }

    public func updateSlider(
        _ slider: Widget,
        minimum: Double,
        maximum: Double,
        decimalPlaces: Int,
        environment: EnvironmentValues,
        onChange: @escaping (Double) -> Void,
        onEditingChanged: @escaping (Bool) -> Void
    ) {
        let slider = slider as! WinUI.Slider
        slider.minimum = minimum
        slider.maximum = maximum
        environment.apply(to: slider)
        // Rounded to `decimalPlaces` before it is reported, as UIKit, AppKit
        // and Android do (GTK sets `digits`).
        // 回報前先依 `decimalPlaces` 四捨五入，與 UIKit、AppKit、Android 相同(GTK 設定 `digits`)。
        let scale = pow(10.0, Double(max(0, min(decimalPlaces, 17))))
        internalState.sliderChangeActions[ObjectIdentifier(slider)] = { value in
            onChange((value * scale).rounded(.toNearestOrEven) / scale)
        }
        internalState.sliderEditingActions[ObjectIdentifier(slider)] = onEditingChanged
    }

    public func setValue(ofSlider slider: Widget, to value: Double) {
        let slider = slider as! WinUI.Slider
        // Marked for the duration, because `valueChanged` cannot tell a code
        // assignment from a drag and this backend now begins an edit there.
        // GtkBackend's equivalent is `withBlockedSignal(named: "value-changed")`
        // -- GTK can silence the signal outright, WinUI cannot, so the flag has
        // to be read on the other side instead.
        // 全程標記,因為 `valueChanged` 分不出「程式指派」與「一次拖曳」,而本 backend 現在
        // 正是在那裡開始一次編輯。GtkBackend 的對應寫法是
        // `withBlockedSignal(named: "value-changed")`——GTK 可以直接讓訊號噤聲,WinUI 不行,
        // 因此只能改為在**另一端**讀這個旗標。
        let id = ObjectIdentifier(slider)
        internalState.slidersBeingSetFromCode.insert(id)
        defer { internalState.slidersBeingSetFromCode.remove(id) }
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
            case .segmented:
                return SegmentedPicker()
            case .wheel:
                return WheelPicker()
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
            // ComboBoxDropDownBackground is left to the theme. Forcing flat
            // white or flat rgb(32,32,32) -- Windows 11's dark value written out
            // by hand -- matches only the default theme and replaces the acrylic
            // brush everywhere else. The scheme is already carried by
            // `requestedTheme`, set in `apply(to:)`.

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

            // Font: `environment.apply(to: picker)` above already sets size,
            // weight, style and family, and the drop-down items inherit them --
            // P74 with `.font(.system(size: 22).italic())` showed Apple, Banana and
            // Cherry at 22 pt italic when open (2026-10-07).
            // 字型:上方的 `environment.apply(to: picker)` 已設定大小、粗細、樣式與家族，下拉項目會繼承——P74 以
            // `.font(.system(size: 22).italic())` 展開時，三個項目皆為 22 pt 斜體(2026-10-07)。
        } else if let picker = picker as? CustomRadioButtons {
            // `apply(to:)` is what carries `.disabled` (it sets `isEnabled`);
            // without it a disabled radioGroup takes a click, changes the
            // selection and draws undimmed (P74-choose-in-every-style.actions,
            // "radioGroup -> Green", 2026-10-08). The segmented and wheel styles
            // apply it too.
            // `apply(to:)` 正是傳遞 `.disabled` 的地方(它設定 `isEnabled`);少了它，停用的 radioGroup 會接受點擊、
            // 改變選取，且不會變暗(P74-choose-in-every-style.actions 的「radioGroup -> Green」,2026-10-08)。
            // segmented 與 wheel 樣式也會套用。
            environment.apply(to: picker)
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
        } else if let picker = picker as? SegmentedPicker {
            picker.update(options: options, environment: environment)
            picker.onChangeSelection = onChange
        } else if let picker = picker as? WheelPicker {
            picker.update(options: options, environment: environment)
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
        } else if let picker = picker as? SegmentedPicker {
            picker.setSelectedIndex(to: selectedOption)
        } else if let picker = picker as? WheelPicker {
            picker.setSelectedIndex(to: selectedOption)
        }
    }

    public func createTextEditor() -> Widget {
        let textEditor = LongPressTextBox()
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

        // TextControlBorderBrushFocused is deliberately NOT blanked here: it is
        // not a decoration but the accent underline that shows which control
        // has the keyboard, and there is no second indicator behind it.
        //
        // Measured with it blanked (P2, WinUI, Windows 11 dark), focus proven by typing
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
            // Skip the frame rather than `try!`, which crashed with no
            // diagnostic; a failure here is visible on the console, not fatal.
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
            } else if pixel >> 24 != 0xFF {
                // Translucent. WriteableBitmap is premultiplied BGRA and these
                // bytes are straight RGBA (see ImagePixels), so the colour is
                // scaled by alpha as well as R and B being swapped; without it
                // a translucent pixel is brightened (measured on AppKit; WinUI not run).
                // 半透明。WriteableBitmap 是預乘 BGRA,傳入的是未預乘 RGBA(見 ImagePixels),
                // 所以除了交換 R 與 B,顏色還要乘上 alpha;否則半透明像素會變亮(AppKit 實測;WinUI 未執行)。
                let alpha = pixel >> 24
                func scaled(_ channel: UInt32) -> UInt32 {
                    let product = channel * alpha + 128
                    return (product + (product >> 8)) >> 8
                }
                let red = scaled(pixel & 0xFF)
                let green = scaled((pixel >> 8) & 0xFF)
                let blue = scaled((pixel >> 16) & 0xFF)
                pixels[i] = (alpha << 24) | (red << 16) | (green << 8) | blue
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

        // Clamped to `maximumWidth` too, so the sidebar cannot exceed what the
        // layout system allowed.
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

    // Both dialogs go through the Win32 shell `IFileDialog`: the WinRT pickers
    // cannot take a start folder, a title, hidden files or a name-field label,
    // and abort on more than one folder. See WinUIBackend+FileDialogs.swift
    // for the measurement.
    // 兩種對話框都經由 Win32 shell 的 `IFileDialog`:WinRT picker 無法指定起始資料夾、標題、
    // 隱藏檔或檔名欄標籤,選多個資料夾還會中止行程。量測記錄見 WinUIBackend+FileDialogs.swift。
    public func showOpenDialog(
        fileDialogOptions: FileDialogOptions,
        openDialogOptions: OpenDialogOptions,
        window: Window?,
        resultHandler handleResult: @escaping (DialogResult<[URL]>) -> Void
    ) {
        let window = window ?? windows[0]
        let hwnd = window.getHWND()!
        let kind: ShellDialogKind =
            switch openDialogOptions.singleKindSelectionMode {
                case .files: .openFiles(multiple: openDialogOptions.allowMultipleSelections)
                case .directories: .openFolders(multiple: openDialogOptions.allowMultipleSelections)
            }
        let urls = Self.runShellFileDialog(kind, options: fileDialogOptions, owner: hwnd)
        Self.restoreForeground(of: hwnd)
        if let urls, !urls.isEmpty {
            handleResult(.success(urls))
        } else {
            handleResult(.cancelled)
        }
    }

    public func showSaveDialog(
        fileDialogOptions: FileDialogOptions,
        saveDialogOptions: SaveDialogOptions,
        window: Window?,
        resultHandler handleResult: @escaping (DialogResult<URL>) -> Void
    ) {
        let window = window ?? windows[0]
        let hwnd = window.getHWND()!
        let urls = Self.runShellFileDialog(
            .save(saveDialogOptions), options: fileDialogOptions, owner: hwnd
        )
        Self.restoreForeground(of: hwnd)
        if let url = urls?.first {
            handleResult(.success(url))
        } else {
            handleResult(.cancelled)
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

    /// How long a press must last to count as a long press.
    ///
    /// SwiftUI's `onLongPressGesture` defaults to 0.5s and Windows' own touch
    /// hold is about the same, so the two agree here and no divergence has to
    /// be documented.
    ///
    /// 一次按壓要持續多久才算長按。
    ///
    /// SwiftUI 的 `onLongPressGesture` 預設為 0.5 秒,而 Windows 自身的觸控長按也差不多,
    /// 因此兩者在此一致,無需記載任何分歧。
    static let longPressDuration: TimeInterval = 0.5

    public func createTapGestureTarget(wrapping child: Widget, gesture: TapGesture) -> Widget {
        // `.secondary` and `.longPress` are wired here and in
        // `updateTapGestureTarget` just as `.primary` is. A `fatalError` for
        // them would let one `.onTapGesture(gesture: .secondary)` -- a right
        // click -- take the whole application down.
        //
        // `.secondary` 與 `.longPress` 在此處與 `updateTapGestureTarget` 中都與 `.primary` 一樣接上事件。
        // 若它們撞上 `fatalError`,一個 `.onTapGesture(gesture: .secondary)`——也就是一次右鍵——就會讓
        // **整個應用程式終止**。
        let tapGestureTarget = TapGestureTarget()
        insert(child, into: tapGestureTarget, at: 0)
        tapGestureTarget.child = child

        // Set a background so that the click target's entire area gets hit
        // tested. The background we set is transparent so that it doesn't
        // change the visual appearance of the view.
        let brush = SolidColorBrush()
        brush.color = UWP.Color(a: 0, r: 0, g: 0, b: 0)
        tapGestureTarget.background = brush

        switch gesture.kind {
            case .primary:
                tapGestureTarget.pointerPressed.addHandler { [weak tapGestureTarget] _, _ in
                    guard let tapGestureTarget else { return }
                    tapGestureTarget.clickHandler?()
                }

            case .secondary:
                // `rightTapped`, not `pointerPressed` with a button test. WinUI
                // raises this one for a right mouse click AND for the pen
                // barrel button and a touch hold, which is what "secondary" is
                // on each of those devices -- reimplementing it from raw
                // pointer state would quietly cover only the mouse.
                // 用 `rightTapped`,而不是「`pointerPressed` 再判斷按鍵」。WinUI 會為右鍵點擊、
                // 觸控筆側鍵以及觸控長按都發出這個事件,而那正是「次要」在各該裝置上的意義;
                // 從原始 pointer 狀態自行重寫,會悄悄地只涵蓋到滑鼠。
                tapGestureTarget.rightTapped.addHandler { [weak tapGestureTarget] _, _ in
                    guard let tapGestureTarget else { return }
                    tapGestureTarget.clickHandler?()
                }

            case .longPress:
                // NOT `holding`. WinUI raises `Holding` for touch and pen only
                // -- a mouse never produces it, by design, because Windows
                // reserves press-and-hold-with-a-mouse for other things. On a
                // desktop backend that would have made this gesture untestable
                // with a mouse and silently dead for most users: correct-looking
                // code that does nothing.
                //
                // So the duration is timed here. `pointerPressed` starts a
                // generation and schedules the callback; anything that ends the
                // press moves the generation on, and the scheduled closure
                // finds a number that is not its own.
                //
                // **不用 `holding`。** WinUI 只為觸控與觸控筆發出 `Holding`——滑鼠**永遠不會**產生
                // 它,而且那是刻意的,因為 Windows 把「以滑鼠按住不放」保留給別的用途。在桌面
                // backend 上,那會讓這個手勢無法以滑鼠測試、並對多數使用者靜默失效:看起來正確、實際
                // 什麼都不做的程式碼。
                //
                // 因此時長在此自行計時。`pointerPressed` 推進一個 generation 並排程回呼;任何結束
                // 該次按壓的事件都會再推進 generation,而已排程的 closure 便會發現那個數字不是自己的。
                tapGestureTarget.pointerPressed.addHandler { [weak tapGestureTarget] _, _ in
                    guard let tapGestureTarget else { return }
                    tapGestureTarget.pressGeneration += 1
                    let generation = tapGestureTarget.pressGeneration
                    DispatchQueue.main.asyncAfter(
                        deadline: .now() + WinUIBackend.longPressDuration
                    ) { [weak tapGestureTarget] in
                        guard let tapGestureTarget,
                            tapGestureTarget.pressGeneration == generation
                        else { return }
                        tapGestureTarget.clickHandler?()
                    }
                }
                // Both, because a press can end in two ways and only one of
                // them is a release: dragging off the target ends it too, and
                // GTK, AppKit and UIKit all treat that as a cancelled press.
                // 兩者都要,因為一次按壓有兩種結束方式,而其中只有一種是放開:把指標拖離目標同樣會
                // 結束它,而 GTK、AppKit 與 UIKit 都把那視為一次被取消的按壓。
                tapGestureTarget.pointerReleased.addHandler { [weak tapGestureTarget] _, _ in
                    tapGestureTarget?.pressGeneration += 1
                }
                tapGestureTarget.pointerExited.addHandler { [weak tapGestureTarget] _, _ in
                    tapGestureTarget?.pressGeneration += 1
                }
        }
        return tapGestureTarget
    }

    public func updateTapGestureTarget(
        _ tapGestureTarget: Widget,
        gesture: TapGesture,
        environment: EnvironmentValues,
        action: @escaping () -> Void
    ) {
        // No gesture check. The kind was fixed when the target was created and
        // decided which events were wired; all three then arrive at the same
        // `clickHandler`, so there is nothing here that varies by kind.
        // 此處不再檢查手勢種類。kind 在建立 target 時就已固定,並據以決定接上哪些事件;三者最後都
        // 抵達同一個 `clickHandler`,因此此處沒有任何隨 kind 而異的東西。
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

        // **No brush at all for an invisible fill, not a transparent one.** XAML
        // hit-tests a transparent brush and skips a null one. A stroked shape
        // therefore swallowed every click inside its outline. `.border` is an
        // overlay of `Rectangle().stroke(...)`, so on 2026-09-17 P50's popover
        // `press me` did nothing for a real click from the user, while UIA
        // Invoke on the same button logged `popover counter 1`. The panel
        // carries `.border(accent, width: 2)`. SwiftUI does not hit-test the
        // clear inside of a stroke either.
        // **看不見的填色就完全不給筆刷,而不是給透明筆刷。** XAML 會對透明筆刷做點擊判定、對 null 則略過,
        // 於是描邊形狀吞掉了外框內的每一次點擊。`.border` 是一個疊在上方的 `Rectangle().stroke(...)`,
        // 因此 2026-09-17 P50 popover 裡的 `press me` 對使用者的真實點擊毫無反應,而對同一顆按鈕做 UIA
        // Invoke 卻記下 `popover counter 1`——那塊面板帶著 `.border(accent, width: 2)`。SwiftUI 也不會對
        // 描邊內部的透明區域做點擊判定。
        // The geometry's bounds: what a relative brush maps onto, and what a
        // radial radius in points is a fraction of (see `brush(for:in:size:)`).
        // 幾何的外框：相對 brush 所對應的範圍，也是以點為單位的放射半徑所換算的分母(見 `brush(for:in:size:)`)。
        let geometryBounds = path.group.bounds
        let paintedSize = SIMD2(Double(geometryBounds.width), Double(geometryBounds.height))
        if case .color(let colour) = fillStyle, colour.opacity == 0 {
            winUiPath.fill = nil
        } else {
            winUiPath.fill = Self.brush(for: fillStyle, in: environment, size: paintedSize)
        }
        winUiPath.stroke = Self.brush(for: strokeFill, in: environment, size: paintedSize)
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

        // Room for the stroke outside the frame. A stroke is centred on the
        // path, so half of it -- more at a miter -- lies outside the shape's
        // frame, and XAML lays a layout clip on an element whose content wants
        // more room than its Width/Height: P43's 14-wide gradient ring on a
        // 120x120 Circle was cut flat on all four sides (2026-10-19) where
        // SwiftUI and GtkBackend draw the whole ring. So the element grows by
        // `outset` on every side, a negative margin of the same keeps its slot
        // in the Canvas at the frame, and the geometry moves by `outset` to sit
        // where it did. Leaving Width/Height unset instead drew no shape at all
        // in P43, fills included. `setSize` zeroes the margin, which is how the
        // frame size is told apart from a size already grown here -- an
        // animation redraws through this method with no `setSize` between.
        // 為 frame 外的描邊留出空間。描邊以路徑為中心，一半(在斜接處更多)落在形狀的 frame 之外，而當元素
        // 的內容需要的空間大於其 Width/Height 時,XAML 會套用 layout clip:P43 中 120x120 Circle 上 14 寬
        // 的漸層圓環四邊都被切平(2026-10-19),而 SwiftUI 與 GtkBackend 都畫出完整圓環。因此元素四邊各擴大
        // `outset`,以相同的負 margin 讓它在 Canvas 中的位置仍是 frame,幾何再平移 `outset` 回到原處。
        // 改成不設 Width/Height 時,P43 一個形狀都沒畫出來，填色也一樣。`setSize` 會把 margin 歸零，
        // 藉此分辨「frame 尺寸」與「已在此擴大過的尺寸」——動畫逐幀經由本方法重畫，中間不經過 `setSize`。
        let outset = strokeStyle.width.rounded(.up)
        let previous = -winUiPath.margin.left
        if !winUiPath.width.isNaN, !winUiPath.height.isNaN {
            winUiPath.width = max(winUiPath.width - 2 * previous, 0) + 2 * outset
            winUiPath.height = max(winUiPath.height - 2 * previous, 0) + 2 * outset
        }
        winUiPath.margin = Thickness(left: -outset, top: -outset, right: -outset, bottom: -outset)
        let shift = MatrixTransform()
        shift.matrix = Matrix(m11: 1, m12: 0, m21: 0, m22: 1, offsetX: outset, offsetY: outset)
        path.group.transform = shift
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

        // WinUI's TimePicker has no seconds and writes AM/PM in the app's
        // language whatever `\.locale` says (P90), so the whole row, seconds
        // included, is drawn by LocaleTimeRow -- the same H:M:S shape
        // GtkBackend draws with spin buttons. Falling back to `.hourAndMinute`
        // is not acceptable: it dropped the bound value's seconds at launch
        // with no user input (P41, 2026-09-17: 09:46:40 was written back as
        // 09:46:00).
        //
        // WinUI 的 TimePicker 沒有秒，而且不管 `\.locale` 怎麼說都以 app 的語言寫上午/下午(P90),
        // 所以整列(含秒)由 LocaleTimeRow 繪製——與 GtkBackend 用 spin button 畫出的 H:M:S 同一個形狀。
        // 退回 `.hourAndMinute` 不可接受:**綁定值會在啟動時、沒有任何使用者操作之下就失去秒數**
        // (P41,2026-09-17:09:46:40 被寫回成 09:46:00)。
        customDatePicker.toggleTimeView(
            shown: components.contains(.hourAndMinute),
            seconds: components.contains(.hourMinuteAndSecond)
        )

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
        // The month names, column order and AM/PM come from the calendar's
        // locale, and `environment.calendar` does not follow `\.locale` -- the
        // same fix as GtkBackend's updateDatePicker (P90, 2026-10-20). The range
        // goes in first, because the wheel's year column is cut to it.
        // 月份名稱、欄位順序與上午/下午取自 calendar 的 locale,而 `environment.calendar` 不會跟著 `\.locale`——
        // 與 GtkBackend 的 updateDatePicker 同一個修正(P90,2026-10-20)。範圍先放入，因為滾輪的年份欄依它裁切。
        var displayCalendar = environment.calendar
        displayCalendar.locale = environment.locale
        customDatePicker.setDateRange(to: range)
        customDatePicker.updateIfNeeded(
            date: date, calendar: displayCalendar, environment: environment
        )
        customDatePicker.setEnabled(to: environment.isEnabled)

        customDatePicker.setForeground(to: environment.explicitWinUIForegroundBrush)
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
        // Set both ways for the same reason: italic used to be set and never
        // cleared, so a reused control stayed italic. 同一理由兩個方向都設：斜體原本只設不清，重用的控制項會一直是斜體。
        control.fontStyle = resolvedFont.isItalic ? .italic : .normal
        if let family = resolvedFont.winUIFontFamily {
            control.fontFamily = family
        } else if control.fontFamily?.source == winUIMonospacedFontFamilies {
            try! control.clearValue(WinUI.Control.fontFamilyProperty)
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
        textBlock.fontStyle = resolvedFont.isItalic ? .italic : .normal
        if let family = resolvedFont.winUIFontFamily {
            textBlock.fontFamily = family
        } else if textBlock.fontFamily?.source == winUIMonospacedFontFamilies {
            try! textBlock.clearValue(WinUI.TextBlock.fontFamilyProperty)
        }
    }
}

/// The families `Font.Design.monospaced` maps to: Cascadia Mono ships with
/// Windows 11, Consolas with every Windows since Vista, Courier New with all.
/// Only this exact family is cleared when the design returns to default, so a
/// family someone else set -- the icon fonts in WinUIBackend+Symbols.swift --
/// is left alone.
/// `Font.Design.monospaced` 對應的字型家族:Windows 11 內建 Cascadia Mono,Vista 起皆有 Consolas,Courier New 則
/// 處處皆有。設計回到預設時只清除這個確切的家族，別人設定的家族——WinUIBackend+Symbols.swift 的圖示字型——不受影響。
let winUIMonospacedFontFamilies = "Cascadia Mono, Consolas, Courier New"

extension Font.Resolved {
    @MainActor
    var winUIFontFamily: FontFamily? {
        switch design {
            case .monospaced: FontFamily(winUIMonospacedFontFamilies)
            case .default: nil
        }
    }

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
    /// "whatever the theme would have used". A default such as opaque black
    /// is wrong under a dark theme.
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

    /// Bookkeeping for `.longPress`, unused by the other two kinds.
    ///
    /// A counter rather than a cancellable timer, because the delayed work is a
    /// `DispatchQueue.main.asyncAfter` closure that cannot be called back. When
    /// the press ends the counter moves, and the closure that eventually runs
    /// sees a number that is no longer its own and does nothing. A stale timer
    /// firing after the finger lifted would report a long press the user never
    /// made -- and nothing downstream could tell that apart from a real one.
    ///
    /// 供 `.longPress` 記帳之用,另外兩種 kind 不使用。
    ///
    /// 採計數器而非可取消的計時器,因為那份延遲工作是一個無法回收的
    /// `DispatchQueue.main.asyncAfter` closure。按壓結束時計數器前進,而最終執行的那個 closure
    /// 會看到一個不再屬於自己的數字,於是什麼都不做。一個在手指抬起後才觸發的過期計時器,會回報
    /// 一次**使用者從未做過**的長按——而下游沒有任何東西能把它與真的長按區分開來。
    var pressGeneration = 0
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

    /// The toolbar row's height, in the same hardcoded style as
    /// ``menuBarHeight`` above and for the same reason: there is no theme
    /// resource to ask. 40 matches the menu bar so the two stack evenly when a
    /// window has both.
    /// 工具列該列的高度，與上方 ``menuBarHeight`` 同樣採用寫死的做法，理由也相同：沒有可供查詢的
    /// theme resource。取 40 與選單列一致，使視窗同時具備兩者時能整齊堆疊。
    private static let toolbarHeight = 40

    var menuBar = WinUI.MenuBar()

    /// The window's toolbar: a horizontal `StackPanel` of ordinary buttons.
    ///
    /// **Not a `CommandBar`, and that is measured rather than chosen.**
    /// ``ToolbarItem`` names `CommandBar` as the WinUI shape, which is correct
    /// for WinUI itself but not for the bindings this backend actually compiles
    /// against. Searched 2026-09-08 in
    /// `.build/checkouts/swift-winui/Sources/WinUI/Generated` (56 files):
    /// `CommandBar`, `AppBarButton`, `FontIcon`, `SymbolIcon` and
    /// `AppBarSeparator` are all **absent**, while `MenuBar`, `Button` and
    /// `StackPanel` are present. The positive control matters here -- `MenuBar`
    /// resolving with the same pattern is what makes the five zeros absence
    /// rather than a broken search.
    ///
    /// So the row is composed from the primitives that do exist. That is the
    /// same answer CLAUDE.md requires: "the platform has no API for this" is a
    /// claim to verify, and the answer is still to find the way the platform
    /// does do it.
    ///
    /// 本視窗的工具列：一列水平的 `StackPanel`，內含一般按鈕。
    ///
    /// **不是 `CommandBar`，而且這是量出來的、不是選出來的。** ``ToolbarItem`` 把 `CommandBar` 指為
    /// WinUI 的對應形狀，那對 WinUI 本身是正確的，但對本 backend 實際編譯所依據的那組綁定並不成立。
    /// 2026-09-08 於 `.build/checkouts/swift-winui/Sources/WinUI/Generated`（56 個檔案）搜尋：
    /// `CommandBar`、`AppBarButton`、`FontIcon`、`SymbolIcon` 與 `AppBarSeparator` **全部不存在**，
    /// 而 `MenuBar`、`Button`、`StackPanel` 存在。此處正對照是關鍵——`MenuBar` 以同一個樣式找得到，
    /// 才使那五個零成為「缺席」而非「搜尋壞了」。
    ///
    /// 因此這一列改以確實存在的原件組成。那正是 CLAUDE.md 要求的答案：「這個平台沒有對應的 API」是
    /// 一項待查證的主張，而答案仍然是去找出該平台**做得到**的方式。
    var toolbar = WinUI.StackPanel()

    var child: WinUIBackend.Widget?
    var grid: WinUI.Grid
    var cachedAppWindow: WinAppSDK.AppWindow!
    var isActive = false
    var currentAlert: WinUIBackend.Alert?
    var minimumContentSize = SIMD2<Int>(0, 0)
    var maximumContentSize: SIMD2<Int>?
    var originalWindowProc: WNDPROC?
    /// Called from the window procedure on `WM_DPICHANGED`; set by
    /// `setWindowEnvironmentChangeHandler`. 由視窗程序在 `WM_DPICHANGED` 時呼叫。
    var scaleFactorChangeHandler: (() -> Void)?
    /// What Back does in this window, set by `setBackNavigationHandler`; it
    /// returns whether it went back. See WinUIBackend+BackNavigation.swift.
    /// 此視窗中「返回」所做的事，由 `setBackNavigationHandler` 設定；它回傳是否返回了。見 WinUIBackend+BackNavigation.swift。
    var backNavigationHandler: (@MainActor () -> Bool)?
    /// The sheet shown over this window, if any; while it is presenting, the
    /// window ignores Back. 顯示在此視窗之上的 sheet;它呈現期間，視窗忽略返回。
    weak var presentedSheet: WinUIBackend.Sheet?

    private(set) var menuBarIsVisible = false
    private(set) var toolbarIsVisible = false
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

    /// The window an `HWND` belongs to, for the Back message hook in
    /// WinUIBackend+BackNavigation.swift. `HWND` 所屬的視窗，供 WinUIBackend+BackNavigation.swift 的返回訊息 hook 使用。
    static func window(forHWND hwnd: HWND) -> CustomWindow? {
        windowsByHWND[Int(bitPattern: hwnd)]
    }

    /// The amount of height to subtract off the window height to obtain the
    /// window's available content height.
    /// Both chrome rows count. Omitting the toolbar here would leave the
    /// content believing it has 40px more height than the grid will give it,
    /// which does not error -- it just clips the bottom of every window that
    /// has a toolbar.
    /// 兩列外框都要計入。若此處漏掉工具列，內容會誤以為自己比 grid 實際給的高度多出 40px，那不會
    /// 產生任何錯誤——它只會把每一個帶工具列的視窗底部裁掉。
    var contentHeightAdjustment: Int {
        (menuBarIsVisible ? Self.menuBarHeight : 0)
            + (toolbarIsVisible ? Self.toolbarHeight : 0)
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

        // Three rows now: menu bar, toolbar, content. The toolbar sits between
        // them because that is where Windows puts a command surface -- under the
        // menus, above the document.
        // 現在是三列：選單列、工具列、內容。工具列位於兩者之間，因為那正是 Windows 放置命令介面的
        // 位置——在選單之下、文件之上。
        let menuBarRowDefinition = WinUI.RowDefinition()
        let toolbarRowDefinition = WinUI.RowDefinition()
        let contentRowDefinition = WinUI.RowDefinition()
        grid.rowDefinitions.append(menuBarRowDefinition)
        grid.rowDefinitions.append(toolbarRowDefinition)
        grid.rowDefinitions.append(contentRowDefinition)
        grid.children.append(menuBar)
        WinUI.Grid.setRow(menuBar, 0)
        toolbar.orientation = .horizontal
        grid.children.append(toolbar)
        WinUI.Grid.setRow(toolbar, 1)
        self.content = grid
        // Alt+Left, the Back key and the mouse's back button; see
        // WinUIBackend+BackNavigation.swift.
        // Alt+Left、返回鍵與滑鼠返回鍵；見 WinUIBackend+BackNavigation.swift。
        installBackNavigation()

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
        // Same for the toolbar: a zero-height row until something asks for one.
        // 工具列亦同：在有東西要求之前，它是一列高度為零的列。
        setToolbarVisible(toolbarIsVisible)
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
            // WinUI's own procedure first, then the limits, so ours are the last
            // word. They used to be written first and the message then forwarded,
            // which left WinUI free to rewrite them (review, 2026-10-29). Not seen
            // to happen: measured the same day, P41's minimum width held with the
            // old order (SetWindowPos to 120 x 120 gave 1681 x 120).
            // 先跑 WinUI 自己的 procedure,再寫入限制，讓我們的值是最後的決定。以前是先寫入再轉送，WinUI 因此
            // 可以改寫它們(審查,2026-10-29)。實際上沒看到發生：同一天量測，舊順序下 P41 的最小寬度仍成立
            // (SetWindowPos 到 120 x 120 得到 1681 x 120)。
            if let originalWindowProc = window.originalWindowProc {
                _ = CallWindowProcW(originalWindowProc, hwnd, message, wParam, lParam)
            }
            let minimumWindowSize = window.windowTrackingSize(forContentSize: window.minimumContentSize)
            info.pointee.ptMinTrackSize.x = minimumWindowSize.x
            info.pointee.ptMinTrackSize.y = minimumWindowSize.y

            if let maximumContentSize = window.maximumContentSize {
                let maximumWindowSize = window.windowTrackingSize(forContentSize: maximumContentSize)
                info.pointee.ptMaxTrackSize.x = maximumWindowSize.x
                info.pointee.ptMaxTrackSize.y = maximumWindowSize.y
            }
            return 0
        }

        // The window moved to a display with another scale, or the scale was
        // changed in Settings. Reported on the next turn of the main queue,
        // after the default processing has resized the window to the new DPI,
        // so the environment is recomputed with `scaleFactor` already current.
        // 視窗移到另一個縮放比例的顯示器，或在設定中改了縮放。於主佇列下一輪回報——那時預設處理已把視窗依新的 DPI
        // 調整好大小——因此重新計算 environment 時，`scaleFactor` 已是新值。
        // Back from a device that sends WM_APPCOMMAND; the other Back inputs are
        // taken before dispatch, see WinUIBackend+BackNavigation.swift.
        // 來自送出 WM_APPCOMMAND 之裝置的返回；其他返回輸入在派送之前就接下，見 WinUIBackend+BackNavigation.swift。
        if message == UINT(WM_APPCOMMAND), let hwnd,
           let window = CustomWindow.windowsByHWND[Int(bitPattern: hwnd)],
           MainActor.assumeIsolated({ WinUIBackNavigation.handleAppCommand(lParam, in: window) })
        {
            return 1
        }

        if message == WM_DPICHANGED, let hwnd {
            let key = Int(bitPattern: hwnd)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    CustomWindow.windowsByHWND[key]?.scaleFactorChangeHandler?()
                }
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

    /// A content size in pixels as a LONG, clamped. A view that fills its window
    /// reports no maximum, an "infinite" size that arrives here as a huge Int, and
    /// converting that straight to Int32 trapped: P95 under SCUI_P95_GROW crashed in
    /// WM_GETMINMAXINFO with "Double value cannot be converted to Int32" (2026-10-20).
    /// Half the range, so AdjustWindowRectExForDpi can still add the frame.
    /// 以 LONG 表示、夾住範圍的像素內容尺寸。填滿視窗的 view 不回報上限，「無限」尺寸到這裡是一個極大的 Int,
    /// 直接轉成 Int32 會中止:2026-10-20 P95 在 SCUI_P95_GROW 下於 WM_GETMINMAXINFO 當掉(「Double value cannot be
    /// converted to Int32」)。取範圍的一半，讓 AdjustWindowRectExForDpi 仍能加上框架。
    private static func trackingPixels(_ value: Double) -> LONG {
        let limit = Double(LONG.max / 2)
        guard value.isFinite else { return value < 0 ? -LONG(limit) : LONG(limit) }
        return LONG(max(-limit, min(limit, value.rounded(.awayFromZero))))
    }

    private func windowTrackingSize(forContentSize contentSize: SIMD2<Int>) -> POINT {
        guard let hwnd = cachedAppWindow.getHWND() else {
            let scaleFactor = scaleFactor
            return POINT(
                x: Self.trackingPixels(Double(contentSize.x) * scaleFactor),
                y: Self.trackingPixels(
                    (Double(contentSize.y) + Double(contentHeightAdjustment)) * scaleFactor)
            )
        }

        let dpi = GetDpiForWindow(hwnd)
        let effectiveDPI = dpi == 0 ? UINT(USER_DEFAULT_SCREEN_DPI) : dpi
        let scaleFactor = Double(effectiveDPI) / Double(USER_DEFAULT_SCREEN_DPI)
        let clientWidth = Self.trackingPixels(Double(contentSize.x) * scaleFactor)
        let clientHeight = Self.trackingPixels(
            (Double(contentSize.y) + Double(contentHeightAdjustment)) * scaleFactor)

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

    /// Sets whether the toolbar row of the current window is visible.
    ///
    /// Row 1, collapsed to zero height rather than hidden, exactly as
    /// ``setMenuBarVisible(_:)`` treats row 0. A `Visibility.collapsed` on the
    /// panel would leave the row's height in the grid and cost 40px of content
    /// for a bar nobody can see.
    ///
    /// 設定本視窗的工具列該列是否可見。
    ///
    /// 對象是第 1 列，做法是把高度收為零而非隱藏 widget，與 ``setMenuBarVisible(_:)`` 處理第 0 列
    /// 的方式完全相同。對該面板設 `Visibility.collapsed` 會讓那一列的高度仍留在 grid 中，等於為一條
    /// 沒有人看得見的橫條付出 40px 的內容高度。
    public func setToolbarVisible(_ visible: Bool) {
        grid.rowDefinitions[1]!.height = WinUI.GridLength(
            value: visible ? Double(Self.toolbarHeight) : 0,
            gridUnitType: .pixel
        )
        toolbarIsVisible = visible
    }

    public func setChild(_ child: WinUIBackend.Widget) {
        self.child = child
        grid.children.append(child)
        // Row 2, not 1: the toolbar row was inserted above. This line is the
        // one that breaks silently if the row count changes again -- the child
        // would be laid into the toolbar's row and the two would overlap, with
        // no error from either.
        // 第 2 列，不是第 1 列：工具列那一列插在其上。若日後列數再變，靜默出錯的正是這一行——子元件
        // 會被排進工具列那一列、兩者重疊，而雙方都不會產生任何錯誤。
        WinUI.Grid.setRow(child, 2)
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
        dateChangedEvent?.dispose()
    }

    /// The date part. `.datePicker` is the wheel style (`.automatic` and
    /// `.wheel`), drawn by `LocaleDateWheel` since 2026-10-20 rather than by
    /// `WinUI.DatePicker`, which formats with the app's languages only and so
    /// ignored `\.locale` (P90). See WinUIBackend+LocaleWheels.swift.
    /// 日期部分。`.datePicker` 是滾輪樣式(`.automatic` 與 `.wheel`),自 2026-10-20 起由 `LocaleDateWheel`
    /// 繪製，不再用只依 app 語言格式化、因而無視 `\.locale` 的 `WinUI.DatePicker`(P90)。
    enum DateViewType {
        case calendarView(CalendarView)
        case calendarDatePicker(CalendarDatePicker)
        case datePicker(LocaleDateWheel)

        var asElement: FrameworkElement {
            switch self {
                case .calendarView(let calendarView): calendarView
                case .calendarDatePicker(let calendarDatePicker): calendarDatePicker
                case .datePicker(let wheel): wheel
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
    /// Hours, minutes, optionally seconds and AM/PM, in the locale's order.
    /// One child of this panel, appended after the date view, so the date view
    /// stays at index 0. It replaced a WinUI TimePicker plus a seconds ComboBox
    /// on 2026-10-20: the TimePicker wrote AM/PM in the app's language whatever
    /// `\.locale` said.
    /// 依 locale 順序排列的時、分、可選的秒與上午/下午。它是本 panel 的單一子元件，排在日期檢視之後，因此日期
    /// 檢視維持在索引 0。2026-10-20 取代了 WinUI TimePicker 加秒數 ComboBox:TimePicker 不管 `\.locale`
    /// 怎麼說，都以 app 的語言寫上午/下午。
    private var timeRow: LocaleTimeRow?
    private var date = Date()
    private var calendar = Calendar.current
    private var range = Date.distantPast...Date.distantFuture
    private var needsUpdate = false
    var onChange: ((Date) -> Void)?
    private var dateChangedEvent: EventCleanup?

    /// True while `updateIfNeeded` is pushing the bound value INTO the controls.
    ///
    /// **Programmatic assignment raises the controls' changed events**, and
    /// those events were treated as user edits. Measured on P41 2026-09-17: at
    /// launch, with no input, `.hourAndMinute` wrote 09:46:40 back as 09:46 and
    /// `.hourMinuteAndSecond` as 09:46:00 -- TimePicker truncates, so the echo
    /// of setting it is a different value, and that value went to the binding.
    /// Handlers also skip `onChange` when the computed date equals the current
    /// one, in case an echo arrives after this flag is cleared.
    ///
    /// `updateIfNeeded` 正在把綁定值**推進**控制項時為 true。
    ///
    /// **以程式設定值會觸發控制項的 changed 事件**,而那些事件先前被當成使用者的編輯。2026-09-17 於
    /// P41 實測:啟動時沒有任何輸入,`.hourAndMinute` 就把 09:46:40 寫回成 09:46,
    /// `.hourMinuteAndSecond` 寫成 09:46:00——TimePicker 會截斷,所以「設定它」的回聲是一個不同的值,
    /// 而那個值進了 binding。為防回聲在旗標清除後才抵達,handler 在算出的日期與目前相同時也不呼叫
    /// `onChange`。
    private var isApplyingUpdate = false

    private func timeOfDay(_ date: Date) -> TimeInterval {
        date.timeIntervalSince(calendar.startOfDay(for: date))
    }

    /// The bound value's time of day, for a DATE edit to keep, so picking a
    /// day does not zero the seconds. `nil` when no time is shown, which keeps
    /// the previous behaviour there.
    /// 綁定值的時刻,供**日期**編輯保留,以免選一天就把秒歸零。未顯示時間時為 `nil`,維持該處原本的行為。
    private var keptTimeOfDay: TimeSpan? {
        guard timeRow != nil else { return nil }
        return TimeSpan(duration: Int64(timeOfDay(date) * ticksPerSecond))
    }

    private func report(_ newDate: Date) {
        guard !isApplyingUpdate, newDate != self.date else { return }
        self.date = newDate
        onChange?(newDate)
    }

    func toggleTimeView(shown: Bool, seconds: Bool) {
        guard shown != (timeRow != nil) || (shown && seconds != timeRow?.showsSeconds) else {
            return
        }

        // Tear down whatever is there, then build what is asked for. Always
        // the last child: the date view is inserted at 0 and the row appended.
        // Not an identity search -- wrapper identity is not stable in this
        // binding (see WinUIBackend+LazyListRows.swift).
        // 先拆掉現有的，再建出所要求的。永遠是最後一個子元件：日期檢視插在 0,這一列則是 append。不做身分搜尋——
        // 這個綁定的包裝身分並不穩定(見 WinUIBackend+LazyListRows.swift)。
        if timeRow != nil {
            children.removeAtEnd()
            timeRow = nil
        }

        guard shown else { return }

        let row = LocaleTimeRow()
        row.configure(calendar: calendar, showsSeconds: seconds)
        row.onChange = { [unowned self] hour, minute, second in
            // Seconds from the bound value when the row shows none, so an
            // hour or minute edit does not zero them.
            // 列上沒有秒時，秒取自綁定值，以免改時或分就把秒歸零。
            let keptSeconds = second.map(Double.init)
                ?? timeOfDay(self.date).truncatingRemainder(dividingBy: 60)
            report(
                calendar.startOfDay(for: self.date)
                    + Double(hour * 3600 + minute * 60) + keptSeconds
            )
            DispatchQueue.main.async { [weak self] in self?.paintTemplateText() }
        }
        row.loaded.addHandler { [weak self] _, _ in
            DispatchQueue.main.async { [weak self] in self?.paintTemplateText() }
        }
        children.append(row)
        timeRow = row
        needsUpdate = true
    }

    func setEnabled(to isEnabled: Bool) {
        switch dateView {
            case .calendarView(let view): view.isEnabled = isEnabled
            case .calendarDatePicker(let picker): picker.isEnabled = isEnabled
            case .datePicker(let wheel): wheel.setEnabled(isEnabled)
            case nil: break
        }
        timeRow?.setEnabled(isEnabled)
    }

    /// The environment's explicit foreground on every part, or the theme's
    /// when there is none. Measured on P41 with `.foregroundColor(.red)`,
    /// 2026-10-07: `Foreground` reddened the DatePicker and TimePicker; a
    /// `CalendarView`'s day numbers needed `CalendarItemForeground`; its month
    /// header, a `CalendarDatePicker`'s date and the seconds box's selected
    /// value needed `paintTemplateText()`. Days of the neighbouring months keep
    /// the theme's dimmed colour, which is how the view marks them.
    /// environment 明確指定的前景色套到每個部分，沒有時就用主題的。2026-10-07 在 P41 以 `.foregroundColor(.red)` 實測:
    /// `Foreground` 讓 DatePicker 與 TimePicker 變紅;`CalendarView` 的日期數字需要 `CalendarItemForeground`;其月份標題、
    /// `CalendarDatePicker` 的日期與秒數框選中的值需要 `paintTemplateText()`。相鄰月份的日期維持主題的淡色，那是該 view
    /// 標示它們的方式。
    func setForeground(to brush: WinUI.Brush?) {
        foregroundBrush = brush
        func apply(_ control: Control?) {
            guard let control else { return }
            if let brush {
                control.foreground = brush
            } else {
                try? control.clearValue(Control.foregroundProperty)
            }
        }
        for box in timeRow?.boxes ?? [] {
            apply(box)
        }
        for separator in timeRow?.separators ?? [] {
            if let brush {
                separator.foreground = brush
            } else {
                try? separator.clearValue(WinUI.TextBlock.foregroundProperty)
            }
        }
        switch dateView {
            case .datePicker(let wheel):
                for column in wheel.columns {
                    apply(column)
                }
            case .calendarView(let view):
                apply(view)
                if let brush {
                    view.calendarItemForeground = brush
                } else {
                    try? view.clearValue(CalendarView.calendarItemForegroundProperty)
                }
            case .calendarDatePicker(let picker):
                apply(picker)
            case nil:
                break
        }
        paintTemplateText()
        // Again once the templates exist: a control created in this update
        // has no template parts until it is laid out.
        // template 存在後再一次：本次更新中建立的控制項，在排版之前沒有 template 零件。
        DispatchQueue.main.async { [weak self] in
            self?.paintTemplateText()
        }
    }

    private var foregroundBrush: WinUI.Brush?

    /// `Foreground` did not reach the text of a `CalendarDatePicker` (the
    /// date it shows) or of a `ComboBox` (the selected value): on P41 both
    /// stayed in the theme's colour with everything else red, and so did
    /// overriding the `CalendarDatePickerTextForeground` and
    /// `ComboBoxForeground` resources (2026-10-07). So the colour is set on
    /// the text blocks inside their templates, a local value that wins over
    /// the template's; cleared again when there is no colour. A ComboBox
    /// rebuilds its displayed item when the selection changes, so the time
    /// row's change handler calls this too. The `CalendarView` month header
    /// is painted the same way.
    /// `Foreground` 到不了 `CalendarDatePicker` 的文字(它顯示的日期)與 `ComboBox` 的文字(選中的值):在 P41 上，
    /// 其他東西都變紅時這兩者仍是主題顏色，覆寫 `CalendarDatePickerTextForeground` 與 `ComboBoxForeground` 資源也一樣
    /// (2026-10-07)。因此把顏色設在它們 template 內的 text block 上——本地值勝過 template 的值；沒有顏色時再清除。ComboBox
    /// 在選取改變時會重建顯示項目，所以時間列的變更 handler 也會呼叫這裡。`CalendarView` 的月份標題也以同樣方式上色。
    func paintTemplateText() {
        func walk(_ element: WinUI.UIElement) {
            if let text = element as? WinUI.TextBlock {
                if let foregroundBrush {
                    text.foreground = foregroundBrush
                } else {
                    try? text.clearValue(WinUI.TextBlock.foregroundProperty)
                }
            }
            for child in scuiChildren(of: element) {
                walk(child)
            }
        }
        switch dateView {
            case .calendarDatePicker(let picker):
                walk(picker)
            // The month header; the day numbers take `CalendarItemForeground`.
            // 月份標題；日期數字則用 `CalendarItemForeground`。
            case .calendarView(let view):
                walk(view)
            case .datePicker, nil:
                break
        }
        for box in timeRow?.boxes ?? [] {
            walk(box)
        }
    }

    func changeDateView(to newDiscriminator: DateViewType.Discriminator?) {
        guard newDiscriminator != dateView?.discriminator else { return }

        dateChangedEvent?.dispose()
        dateChangedEvent = nil
        if dateView != nil {
            children.removeAt(0)
            dateView = nil
        }

        switch newDiscriminator {
            case .calendarView:
                let calendarView = CalendarView()
                dateView = .calendarView(calendarView)
                children.insertAt(0, calendarView)
                // A new CalendarView draws a blank weekday row and starts the
                // week on Monday, whatever its Language and the system's first
                // day (Sunday here); a Language change on the loaded control
                // redraws both correctly (P41, 2026-10-29: blank at launch
                // under en_US and zh_TW, right after the locale buttons). So
                // the Language is changed once after load and set back.
                // 新建的 CalendarView 會畫出空白的星期列、一週從星期一開始，不論 Language 與系統的每週第一天(本機是週日);
                // 在已載入的控制項上換一次 Language,兩者都會正確重畫(P41,2026-10-29:啟動時 en_US 與 zh_TW 皆空白，
                // 按下 locale 按鈕後正確)。因此載入後換一次 Language 再換回來。
                //
                // Once only, so that a second Loaded cannot repeat it. On the
                // next main-loop pass, not in Loaded itself: changed inside
                // the handler the grid went to January 1. And back to the
                // selected date afterwards, which the change loses.
                // 只做一次，以免再次觸發的 Loaded 又重做。在下一輪主迴圈做，不在 Loaded 裡直接做：在 handler 裡換的話，
                // 格線跑到 January 1。換完要捲回選定日期，因為換語言會把它弄丟。
                var didReset = false
                calendarView.loaded.addHandler { [weak calendarView] _, _ in
                    guard !didReset else { return }
                    didReset = true
                    DispatchQueue.main.async { [weak calendarView] in
                        guard let calendarView else { return }
                        let language = calendarView.language
                        calendarView.language = language == "en-GB" ? "en-US" : "en-GB"
                        calendarView.language = language
                        if calendarView.selectedDates.size > 0 {
                            try? calendarView.setDisplayDate(calendarView.selectedDates.getAt(0))
                        }
                    }
                }
                orientation = .vertical
                dateChangedEvent = calendarView.selectedDatesChanged.addHandler {
                    [unowned self] _, _ in

                    guard calendarView.selectedDates.size > 0 else {
                        let (dateTime, _) = foundationDateToComponents(self.date)
                        calendarView.selectedDates.append(dateTime)
                        return
                    }

                    let picked = componentsToFoundationDate(
                        dateTime: calendarView.selectedDates.getAt(0),
                        timeSpan: keptTimeOfDay
                    )

                    if calendarView.selectedDates.size > 1 {
                        self.needsUpdate = true
                    }

                    report(picked)
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
                    report(componentsToFoundationDate(dateTime: newDate, timeSpan: keptTimeOfDay))
                }
                needsUpdate = true
            case .datePicker:
                let wheel = LocaleDateWheel()
                dateView = .datePicker(wheel)
                children.insertAt(0, wheel)
                orientation = .horizontal
                wheel.onChange = { [unowned self] year, month, day in
                    // The time of day is kept, as the WinUI DatePicker's DateTime kept it.
                    // 保留一天中的時刻，與 WinUI DatePicker 的 DateTime 保留它的方式相同。
                    guard
                        let picked = calendar.date(
                            from: DateComponents(year: year, month: month, day: day)
                        )
                    else { return }
                    report(calendar.startOfDay(for: picked) + timeOfDay(self.date))
                }
                needsUpdate = true
            case nil:
                break
        }
    }

    func setDateRange(to range: ClosedRange<Date>) {
        if range != self.range {
            self.range = range
            needsUpdate = true
        }
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
            case .datePicker:
                // The wheel's year column is cut to the range in `updateIfNeeded`.
                // 滾輪的年份欄在 `updateIfNeeded` 中依範圍裁切。
                break
        }
    }

    /// The years a wheel offers: a hundred either side of the bound year, as
    /// GtkBackend's wheel offers, cut to the range.
    /// 滾輪提供的年份：綁定年份前後各一百年(與 GtkBackend 的滾輪相同),再依範圍裁切。
    private func wheelYears(around year: Int) -> ClosedRange<Int> {
        let low = max(year - 100, calendar.component(.year, from: range.lowerBound))
        let high = min(year + 100, calendar.component(.year, from: range.upperBound))
        return low <= high ? low...high : year...year
    }

    /// `calendar` carries the environment's locale (`updateDatePicker` puts it
    /// there), so a locale change is a calendar change and reaches the wheels.
    /// `calendar` 帶著 environment 的 locale(由 `updateDatePicker` 放入),因此 locale 改變就是 calendar 改變，
    /// 會傳到滾輪。
    func updateIfNeeded(date: Date, calendar: Calendar, environment: EnvironmentValues) {
        if !needsUpdate && date == self.date && calendar == self.calendar { return }
        isApplyingUpdate = true
        defer {
            needsUpdate = false
            isApplyingUpdate = false
        }

        self.date = date
        self.calendar = calendar

        let (dateTime, _) = foundationDateToComponents(date)

        switch dateView {
            case .calendarView(let calendarView):
                // The grid's month and weekday names follow
                // FrameworkElement.Language, not `\.locale`; without this they
                // stay in the app's language (English) under
                // SCUI_P41_LOCALE=zh_TW. BCP-47 wants "zh-TW", not "zh_TW".
                // 格線的月份與星期名稱取自 FrameworkElement.Language 而非 `\.locale`;少了這行，在
                // SCUI_P41_LOCALE=zh_TW 下仍是 app 的語言(英文)。BCP-47 要的是 "zh-TW" 而非 "zh_TW"。
                let language = (calendar.locale ?? .current).identifier(.bcp47)
                if calendarView.language != language {
                    calendarView.language = language
                }
                calendarView.calendarIdentifier = identifier(for: calendar)
                switch calendarView.selectedDates.size {
                    case 0:
                        calendarView.selectedDates.append(dateTime)
                    case 1:
                        calendarView.selectedDates.setAt(0, dateTime)
                    default:
                        // `append` after clearing, not `setAt(0,)`: index 0 of a
                        // collection that has just been emptied is out of range.
                        // The path is rarely reached -- a single-selection
                        // CalendarView never holds two dates.
                        // 清空之後要用 `append` 而非 `setAt(0,)`:剛被清空的集合沒有索引 0。
                        // 這條路徑很少走到——單選的 CalendarView 不會同時持有兩個日期。
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
                // The text in the locale's numeric order; see LocaleDateFormat.
                // 依 locale 數字日期順序顯示的文字；見 LocaleDateFormat。
                if let format = LocaleDateFormat.numeric(for: calendar.locale ?? .current),
                    format != calendarDatePicker.dateFormat
                {
                    calendarDatePicker.dateFormat = format
                }
                calendarDatePicker.date = dateTime
            case .datePicker(let wheel):
                let parts = calendar.dateComponents([.year, .month, .day], from: date)
                if let year = parts.year, let month = parts.month, let day = parts.day {
                    wheel.configure(
                        calendar: calendar, years: wheelYears(around: year), environment: environment
                    )
                    wheel.show(year: year, month: month, day: day)
                }
            case nil:
                break
        }

        if let timeRow {
            timeRow.configure(calendar: calendar, showsSeconds: timeRow.showsSeconds)
            let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
            timeRow.show(hour: parts.hour ?? 0, minute: parts.minute ?? 0, second: parts.second ?? 0)
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
        let timeRowSize = timeRow?.naturalSize() ?? .zero

        let dateViewSize: SIMD2<Int> =
            switch dateView {
                // `WheelPicker.naturalSize` measures at its fixed five-row
                // height; the generic measure would lay every row out (P74).
                // `WheelPicker.naturalSize` 以固定的五列高度量測；通用量測會把所有列都排開(P74)。
                case .datePicker(let wheel): wheel.naturalSize()
                case .some(let view): WinUIBackend.naturalSize(of: view.asElement)
                case nil: .zero
            }

        if orientation == .horizontal {
            return SIMD2(
                x: timeRowSize.x + dateViewSize.x + Int(self.spacing),
                y: max(timeRowSize.y, dateViewSize.y)
            )
        } else {
            return SIMD2(
                x: max(timeRowSize.x, dateViewSize.x),
                y: timeRowSize.y + dateViewSize.y + Int(self.spacing)
            )
        }
    }
}
