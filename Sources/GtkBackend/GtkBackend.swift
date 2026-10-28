import CGtk
import DebugFeatures
import Foundation
import Gtk
@_spi(Backends) import SwiftCrossUI
import GtkCHelpers

#if os(Windows)
    import WinSDK
#endif

#if SCUI_DEBUG
    import InputEvent
#endif

extension App {
    public typealias Backend = GtkBackend

    public var backend: GtkBackend {
        GtkBackend(appIdentifier: Self.metadata?.identifier)
    }
}

public final class GtkBackend:
    BaseAppBackend,
    BackendFeatures.IncomingURLs,
    BackendFeatures.ExternalURLs,
    BackendFeatures.RevealFiles,
    BackendFeatures.ApplicationMenus,
    BackendFeatures.FileDialogs,
    BackendFeatures.Alerts,
    BackendFeatures.Sheets,
    BackendFeatures.CornerRadius,
    BackendFeatures.Gestures,
    BackendFeatures.PopoverMenus,
    BackendFeatures.Popovers,
    BackendFeatures.Tables,
    BackendFeatures.Paths,
    BackendFeatures.Tooltips,
    BackendFeatures.Colors,
    BackendFeatures.DatePickers,
    BackendFeatures.Windowing,
    BackendFeatures.WindowLevels,
    BackendFeatures.LinearGradients,
    BackendFeatures.RadialGradients,
    BackendFeatures.AngularGradients,
    BackendFeatures.WebViews,
    BackendFeatures.HitTesting,
    BackendFeatures.DragAndDrop,
    BackendFeatures.Clipping,
    BackendFeatures.Toolbars,
    // Listed here, so `GtkBackend+ButtonPressState.swift` must be a bare
    // `extension GtkBackend { ... }`. Naming the protocol in both places is
    // `error: redundant conformance`.
    // 在此處列出，因此 `GtkBackend+ButtonPressState.swift` 必須是不帶 conformance 的
    // `extension GtkBackend { ... }`。兩處都寫上該 protocol 會得到 `error: redundant conformance`。
    BackendFeatures.ButtonPressState
{
    public typealias Window = Gtk.ApplicationWindow
    public typealias Widget = Gtk.Widget
    public typealias Menu = Gtk.PopoverMenu
    public typealias Alert = Gtk.MessageDialog

    public class Sheet: Gtk.Window {
        var onDismiss: (() -> Void)? = nil
        var interactiveDismissDisabled = false
        var nestedSheet: Sheet?
        /// Whether this sheet has already been torn down by `tearDown(_:)`.
        ///
        /// Not a record of WHICH path closed the sheet -- there is deliberately
        /// no such flag. This only says that the teardown has happened, so that
        /// the destroy and the `onDismiss` each run once per presentation.
        ///
        /// A `Sheet` is never re-presented after teardown, so this never needs
        /// resetting: `SheetModifier.commit` nils `sheetContentNode` along with
        /// `sheet` when a sheet is dismissed, and its presenting branch builds a
        /// fresh `createSheet` whenever `sheetContentNode == nil`.
        ///
        /// 本 sheet 是否已經被 `tearDown(_:)` 拆除。
        ///
        /// 它不是「用來記錄是哪一條路關閉了 sheet」的旗標——此處刻意沒有那種東西。這裡只表示拆除已經發生，
        /// 好讓 destroy 與 `onDismiss` 在每一次呈現中各只執行一次。
        ///
        /// `Sheet` 在拆除之後不會再被重新呈現，因此這個旗標永遠不需要重設：`SheetModifier.commit`
        /// 在關閉 sheet 時會連同 `sheet` 一併把 `sheetContentNode` 設為 nil，而它的呈現分支只要見到
        /// `sheetContentNode == nil` 就會以 `createSheet` 造一個全新的。
        var hasBeenTornDown = false
    }

    public final class Path {
        var path: SwiftCrossUI.Path?
    }

    public let defaultTableRowContentHeight = 20
    public let defaultTableCellVerticalPadding = 4
    public let defaultPaddingAmount = 10
    /// 0 while GTK's scrollbars float over the content, which is its default.
    ///
    /// Computed rather than stored, because the answer is a user setting and can
    /// change while the app runs: with overlay scrolling off the bars take real
    /// width, and a constant 0 would leave the content over-allocated by about a
    /// scrollbar.
    ///
    /// The width is measured from a real GtkScrollbar rather than guessed,
    /// because a theme decides it. AppKitBackend likewise asks
    /// `NSScroller.preferredScrollerStyle`, and WinUIBackend reads
    /// `UISettings.autoHideScrollBars`.
    ///
    /// 當 GTK 的捲軸浮動於內容之上時為 0，而那是它的預設值。
    ///
    /// 此處為計算屬性而非儲存屬性，因為答案取決於使用者設定，且可能在 app 執行期間改變：關閉 overlay
    /// scrolling 後捲軸會佔用實際寬度，固定的 0 會讓內容超額配置約一個捲軸的寬度。
    ///
    /// 寬度取自一個真實的 GtkScrollbar 實測，而非猜測，因為決定它的是主題。AppKitBackend 同樣會去
    /// 詢問 `NSScroller.preferredScrollerStyle`,WinUIBackend 則讀取 `UISettings.autoHideScrollBars`。
    public var scrollBarWidth: Int {
        if Settings.default?.overlayScrolling ?? true {
            return 0
        }
        // Reported, because otherwise this branch is a number no one can see:
        // it only runs on a desktop that has turned overlay scrolling off, and
        // a wrong measurement there would show up as content over-allocated by
        // a few points -- which reads as a layout bug anywhere but here.
        // 此處會回報，否則這條分支就是一個沒人看得見的數字：它只在關閉了 overlay scrolling 的桌面
        // 上執行，而該處若量錯了，症狀會是「內容超額配置了幾個點」——那在任何其他地方看起來都像
        // 版面 bug，唯獨不像出在這裡。
        debugLogOnce(
            "overlay scrolling is off; scroll bars measure \(Self.measuredScrollBarWidth)pt"
        )
        return Self.measuredScrollBarWidth
    }

    /// Measured once. A scrollbar's width does not change without the theme
    /// changing, and building a widget on every layout pass to ask would be a
    /// lot of work for a number that almost never moves.
    ///
    /// The probe sits inside a window, for the reason recorded on
    /// ``sampleAmbientColorScheme``: GTK resolves theme CSS only for a widget
    /// that has a root, and a loose one reports built-in defaults rather than
    /// what the theme would actually draw. Neither is presented.
    ///
    /// 只量測一次。捲軸寬度不會在主題不變的情況下改變，而為了一個幾乎不會變動的數字在每次 layout
    /// 都建立一個 widget，代價過高。
    ///
    /// 探針置於一個視窗之內，理由記錄於 ``sampleAmbientColorScheme``：GTK 只會為「具有 root」的
    /// widget 解析主題 CSS，游離的 widget 回報的是內建預設值，而非主題實際會繪製的樣子。兩者皆不
    /// 會被顯示。
    private nonisolated(unsafe) static let measuredScrollBarWidth: Int = {
        // Rebound rather than cast: gtk_window_new hands back a GtkWidget * and
        // gtk_window_set_child wants a GtkWindow *, which is the same object.
        // 這裡是重新繫結而非型別轉換：gtk_window_new 交出的是 GtkWidget *，而 gtk_window_set_child
        // 需要的是 GtkWindow *，兩者指的是同一個物件。
        guard let probeWidget = gtk_window_new() else { return 0 }
        let probeWindow = UnsafeMutableRawPointer(probeWidget)
            .assumingMemoryBound(to: GtkWindow.self)
        let scrollbar = gtk_scrollbar_new(GTK_ORIENTATION_VERTICAL, nil)
        gtk_window_set_child(probeWindow, scrollbar)

        var minimum: Int32 = 0
        var natural: Int32 = 0
        gtk_widget_measure(
            scrollbar,
            GTK_ORIENTATION_HORIZONTAL,
            -1,
            &minimum,
            &natural,
            nil,
            nil
        )

        gtk_window_destroy(probeWindow)
        return Int(natural)
    }()
    public let requiresToggleSwitchSpacer = false
    public let requiresImageUpdateOnScaleFactorChange = false
    public let supportsMultipleWindows = true
    public let deviceClass = DeviceClass.desktop
    // `.wheel` is a scrolled list per component, which is what SwiftUI's
    // `.wheel` is; see ``DateWheel``.
    //
    // A style left out of this list is downgraded to `.automatic` by
    // `datePickerStyle(_:)` without a word in a release build, so the list is
    // the only place an omission is visible.
    //
    // `.wheel` 是每個組成部分一個捲動清單，那正是 SwiftUI 的 `.wheel`;詳見 ``DateWheel``。
    //
    // Split by host because `BackendDatePickerStyle.wheel` is
    // `@available(macOS, unavailable)`, and GtkBackend does build for macOS --
    // GTK 4 comes from Homebrew and testapp runs GTK apps there. Naming the
    // case unconditionally makes `swift test` on a Mac fail to compile this
    // file -- a failure in GtkBackend, four targets away from anything about
    // date pickers, that takes the whole suite with it.
    //
    // The macOS list is not a lesser version of the other one. A style the
    // shared enum does not offer on this host cannot be asked for on this host,
    // so there is nothing to support.
    //
    // 依主機平台分開，因為 `BackendDatePickerStyle.wheel` 帶有
    // `@available(macOS, unavailable)`，而 GtkBackend 的確會為 macOS 建置——GTK 4 來自
    // Homebrew，testapp 也在該處執行 GTK app。無條件指名該 case，會使 Mac 上的 `swift test`
    // 無法編譯本檔——失敗出現在 GtkBackend，距離任何與日期選擇器相關的東西有四個 target 之遠，
    // 卻連帶拖垮整個測試套件。
    //
    // macOS 的清單並非另一份清單的簡化版。共用的 enum 在此主機上不提供的樣式，在此主機上就無從
    // 被要求，因此也沒有什麼可支援的。
    #if os(macOS)
        public let supportedDatePickerStyles: [BackendDatePickerStyle] = [
            .automatic,
            .graphical,
            .compact,
        ]
    #else
        public let supportedDatePickerStyles: [BackendDatePickerStyle] = [
            .automatic,
            .graphical,
            .compact,
            .wheel,
        ]
    #endif
    /// A time row of spin buttons for every style, so `.rows` is the native picker here.
    /// 每種樣式都是一列 spin button 的時間列，所以 `.rows` 在這裡就是原生選擇器。
    public let nativeTimePresentation: TimePickerPresentation? = .rows
    // `.menu` stays first: `defaultPickerStyle` is the first entry, so it is
    // what `.automatic` resolves to, and a dropdown is what a GTK app shows for
    // a picker with no style of its own.
    // `.wheel` since 2026-10-06 (WheelPicker.swift). `.wheel` 自 2026-10-06 起(WheelPicker.swift)。
    public let supportedPickerStyles: [BackendPickerStyle] = [
        .menu,
        .segmented,
        .radioGroup,
        .wheel
    ]
    // #386: preferredColorScheme is honoured (see updateWindow). The override is
    // per-display rather than per-window, since GTK has no per-window theme
    // variant, so two windows asking for opposite schemes cannot both win.
    // #386：preferredColorScheme 已被遵從（見 updateWindow）。該 override 為 per-display 而非
    // per-window，因為 GTK 沒有 per-window 的主題變體，故兩個要求相反配色的視窗無法同時如願。
    public let canOverrideWindowColorScheme = true
    public let restoresWindowFrames = false

    let defaultSheetCornerRadius = 10

    var gtkApp: Application

    /// Focus-change handlers, replaced per layout pass, and the set of widgets
    /// whose `GtkEventControllerFocus` is already installed.
    ///
    /// Two containers because the handler changes every frame while the
    /// controller must not. Adding a controller per frame is the defect this
    /// backend's slider showed as `began=5`.
    /// 焦點變更的 handler(每次 layout pass 會被換掉),以及「已安裝 `GtkEventControllerFocus`」
    /// 的 widget 集合。
    ///
    /// 分成兩個容器,是因為 handler 每一幀都會變、而控制器**不可以**。逐幀新增控制器,正是本 backend
    /// 的 slider 顯示為 `began=5` 的那個缺陷。
    var focusChangeHandlers: [ObjectIdentifier: (Bool) -> Void] = [:]
    var widgetsWithFocusController: Set<ObjectIdentifier> = []

    /// A window to be returned on the next call to ``GtkBackend/createWindow``.
    /// This is necessary because Gtk creates a root window no matter what, and
    /// this needs to be returned on the first call to `createWindow`.
    var precreatedWindow: Window?

    /// The frame clock's callback id and the widget it is attached to.
    /// frame clock 的 callback id，以及它所附著的那個 widget。
    var frameClockID: UInt32?
    var frameClockAttachedTo: UnsafeMutablePointer<GtkWidget>?
    /// The clock `begin_updating` was called on, so `end_updating` can be paired
    /// with it exactly once.
    /// 曾對它呼叫 `begin_updating` 的那個時鐘——好讓 `end_updating` 與它恰好配對一次。
    var frameClockUpdatingOn: OpaquePointer?
    @MainActor static var currentFrameClockHandler: (@MainActor (Double) -> Void)?

    /// All current windows associated with the application. Doesn't include the
    /// precreated window until it gets 'created' via `createWindow`.
    var windows: [Window] = []

    /// The buttons currently packed into a window's header bar, keyed by window
    /// identity, held so that their handlers survive.
    ///
    /// GTK refcounts the `GtkWidget` once it is packed, so the C object is safe
    /// without this. What is not safe is the Swift ``Gtk/Button`` wrapper: it
    /// owns the `clicked` closure, and nothing else refers to a toolbar button
    /// the way the view graph refers to an ordinary widget it created. Without
    /// this table the wrapper deallocates at the end of `setToolbar`, and the
    /// button then draws correctly and does nothing when pressed -- the same
    /// shape as `NSToolbarItem.target` being unowned on AppKit, recorded there
    /// for the same reason.
    ///
    /// 目前裝進某視窗 header bar 的按鈕，以視窗身分為鍵，持有它們是為了讓其 handler 存活。
    ///
    /// widget 一旦被 pack 進去，GTK 就會對該 `GtkWidget` 進行參照計數，因此 C 物件本身不需要這張表。
    /// 不安全的是 Swift 的 ``Gtk/Button`` wrapper：`clicked` closure 由它持有，而工具列按鈕不像
    /// view graph 所建立的一般 widget 那樣有東西指向它。少了這張表，wrapper 會在 `setToolbar` 結束時
    /// 被釋放，於是該按鈕畫得出來、按下去卻毫無反應——與 AppKit 上 `NSToolbarItem.target` 為 unowned
    /// 的形狀相同，該處也基於同樣理由留有註記。
    /// Internal rather than `private` because the implementation lives in
    /// `GtkBackend+Toolbar.swift`, and Swift's `private` on a member is
    /// file-scoped: an extension in another file cannot see it.
    /// 使用 internal 而非 `private`，因為實作位於 `GtkBackend+Toolbar.swift`；Swift 的 `private`
    /// 是以檔案為範圍的，另一個檔案中的 extension 看不見它。
    var toolbarButtons: [ObjectIdentifier: [Gtk.Button]] = [:]
    /// The titlebar height `createWindow` added to each window's default size.
    /// `createWindow` 為每個視窗的預設尺寸加上的標題列高度。
    var titlebarAllowances: [ObjectIdentifier: Int] = [:]

    /// The alert currently on screen for a window, keyed by window identity, and
    /// the alerts waiting behind it. SwiftUI shows one alert at a time per
    /// window; a second requested while one is up waits and appears when the
    /// first is dismissed, rather than a pile of modal dialogs fighting over the
    /// window (the P5 regression).
    private var shownAlert: [ObjectIdentifier: Alert] = [:]
    /// The macOS appearance observer (`watchSystemColorSchemeChanges`), kept so it lives.
    private var colorSchemeObserver: (any NSObjectProtocol)?
    private var shownAlertHandler: [ObjectIdentifier: (Int) -> Void] = [:]
    /// Alerts with exactly one button, which Escape answers (P31).
    private var oneButtonAlerts: Set<ObjectIdentifier> = []
    /// The Escape-swallowing controller each alert was created with.
    private var alertEscapeControllers: [ObjectIdentifier: OpaquePointer] = [:]
    private var pendingAlerts:
        [ObjectIdentifier: [(alert: Alert, window: Window, handler: (Int) -> Void)]] = [:]

    private var rootEnvironmentChangeHandler: (() -> Void)?

    var borderedButtonPadding: SIMD2<Int>?

    private struct LogLocation: Hashable, Equatable {
        let file: String
        let line: Int
        let column: Int
    }

    private var logsPerformed: Set<LogLocation> = []

    /// Reports a backend limitation to the app author, once per call site.
    ///
    /// Not wrapped in `#if DEBUG`. This project builds release by default --
    /// see the `testapp/compile.zsh` policy in CLAUDE.md -- so a message such as
    /// "GTK does not support setting maximum window sizes" would print in no
    /// configuration anything is actually run in. A request the backend
    /// silently drops, with nothing said about it, is #38's defect exactly.
    ///
    /// It is not gated on `SCUI_DEBUG` either: this is not a developer trace but
    /// something the author of the app needs to be told, and needing a special
    /// build to be told amounts to silence.
    /// `logger.notice` outranks the release log level (`.info`, set in
    /// `App.logHandler`), and the once-per-location set is what stops a call made
    /// every frame from repeating.
    ///
    /// The name is kept: `UIKitBackend` and `WinUIBackend` declare the same
    /// method, and renaming it in one backend alone costs more than it buys.
    ///
    /// 向 app 作者回報 backend 的限制，每個呼叫點只回報一次。
    ///
    /// 不包在 `#if DEBUG` 之中。本專案預設建置 release——見 CLAUDE.md 中的 `testapp/compile.zsh` 政策——因此像
    /// 「GTK does not support setting maximum window sizes」這樣的訊息，在任何實際執行的組態中都不會印出。
    /// backend 默默丟棄一項要求、且對此隻字未提，正是 #38 的缺陷。
    ///
    /// 它也不以 `SCUI_DEBUG` 為條件：這並非開發者用的追蹤訊息，而是 app 作者必須被告知的事；
    /// 而「必須改用特殊建置才會被告知」，等同於沉默。`logger.notice` 高於 release 的
    /// log 層級（`.info`，設定於 `App.logHandler`），而「每個位置只報一次」的集合則使得逐幀呼叫
    /// 不會重複輸出。
    ///
    /// 名稱維持不變：`UIKitBackend` 與 `WinUIBackend` 都宣告了同名方法，只在單一 backend 改名，
    /// 代價高於收益。
    func debugLogOnce(
        _ message: String,
        file: String = #file,
        line: Int = #line,
        column: Int = #column
    ) {
        let location = LogLocation(file: file, line: line, column: column)
        if logsPerformed.insert(location).inserted {
            logger.notice("\(message)")
        }
    }

    // A separate initializer to satisfy `BackendFeatures.Core`'s requirements.
    public convenience init() {
        self.init(appIdentifier: nil)
    }

    /// Creates a backend instance. If `appIdentifier` is `nil`, the default
    /// identifier `com.example.SwiftCrossUIApp` is used.
    public init(appIdentifier: String?) {
        #if os(Windows)
            // Both of these may not return, and that is deliberate. `-GPU list`
            // is a query and exits without starting anything; applying a
            // `-GPU N` preference means restarting the process, because Windows
            // fixes the adapter at process creation.
            // 這兩者都有可能不會返回，而且這是刻意的。`-GPU list` 是查詢，會直接結束而不啟動任何
            // 東西；而套用 `-GPU N` 偏好設定意味著重新啟動行程，因為 Windows 是在行程建立時就決定
            // 了介面卡。
            Self.printAdapterTableIfRequested()
            Self.ensureGpuPreference()
        #endif
        Self.enableDirectCompositionIfRequested()
        Self.enablePerMonitorDPIAwareness()
        Self.useFontconfigForPango()
        #if os(Linux)
            Self.addWindowsUIFontUnderWSL()
        #endif
        // SCUI_GTK_APP_ID overrides both, and exists for running two test apps at
        // once. A SwiftPM executable has no metadata, so every app that does not
        // supply an identifier gets the SAME one -- and GApplication is
        // single-instance per identifier, so the second one hands its arguments
        // to the first and exits 0 with an empty log. Measured again 2026-09-16:
        // P61 launched while P42 was up produced no output at all, which reads
        // exactly like a build that renders nothing.
        //
        // An environment variable rather than a flag: it has to be read before
        // GApplication is constructed, which is before any argument parsing the
        // app itself does.
        //
        // SCUI_GTK_APP_ID 會覆蓋以上兩者,其存在的目的是**同時執行兩支測試 app**。SwiftPM 的
        // 可執行檔沒有 metadata,因此每一支未自行提供識別碼的 app 都拿到**同一個**——而
        // GApplication 對同一識別碼是單一實例的,於是第二支會把自己的引數交給第一支,然後以 0
        // 結束、留下一份空的 log。2026-09-16 再次實測:在 P42 開著時啟動 P61,完全沒有任何輸出,
        // 而那讀起來與「一個什麼都畫不出來的建置」一模一樣。
        //
        // 用環境變數而非旗標:它必須在 GApplication 建構**之前**被讀到,而那早於 app 自己所做的
        // 任何引數解析。
        gtkApp = Application(
            applicationId: ProcessInfo.processInfo.environment["SCUI_GTK_APP_ID"]
                ?? appIdentifier ?? "com.example.SwiftCrossUIApp",
            flags: SHIM_G_APPLICATION_HANDLES_OPEN
        )
        gtkApp.registerSession = true
    }

    /// Asks GDK to make the process per-monitor DPI aware on Windows, so the
    /// display scale it reports follows the setting instead of freezing.
    ///
    /// **Without this the value is frozen, not merely late.** GTK's default
    /// leaves the process SYSTEM_AWARE (`GetAwarenessFromDpiAwarenessContext`
    /// reads 1), and Windows tells such a process the system DPI *as of process
    /// start* and never sends it `WM_DPICHANGED` -- by design. Measured
    /// 2026-09-16: with the display moved from 125% to 100% under a running
    /// window, `GetDpiForWindow` called directly every two seconds reported 1.25
    /// for 99 consecutive readings. Windows bitmap-scales the window instead, so
    /// the app stays readable and stays blurry.
    ///
    /// With it, the same probe reads awareness 2, and moving the display
    /// 100% -> 150% -> 125% -> 100% produced `windowScaleFactor`
    /// 1.0 -> 1.5 -> 1.25 -> 1.0, with `windowDpi` 96 -> 144 -> 120 -> 96
    /// alongside.
    ///
    /// **The geometry cost is zero, and that was the reason to measure rather
    /// than decide.** Every coordinate in `testapp/actions/win/` was measured
    /// against the current window geometry, so a mode that changed it would
    /// invalidate all of them. Captured at 125% in both modes: `748x428` and
    /// `748x428`. The two only differ AFTER a change, which is the case this is
    /// for.
    ///
    /// `overwrite` is false, so `GDK_WIN32_PER_MONITOR_HIDPI=0` still wins --
    /// this changes the default, it does not take the knob away. GDK reads it
    /// when the display is opened, which is after this runs and before any
    /// window exists.
    ///
    /// 在 Windows 上要求 GDK 讓行程成為 per-monitor DPI aware,使它回報的顯示器縮放會**跟隨設定**
    /// 而非凍結。
    ///
    /// **沒有它,那個值是凍住的,而不只是慢。** GTK 的預設會讓行程停在 SYSTEM_AWARE
    /// (`GetAwarenessFromDpiAwarenessContext` 讀到 1),而 Windows **依設計**只告訴這種行程
    /// 「行程啟動當下」的系統 DPI,而且**永遠不送 `WM_DPICHANGED`**。2026-09-16 實測:視窗執行中
    /// 把顯示器由 125% 改成 100%,每兩秒直接呼叫一次 `GetDpiForWindow`,連續 99 次都回報 1.25。
    /// Windows 改為對視窗做點陣縮放,於是 app 仍然可讀、而且一直是糊的。
    ///
    /// 加上它之後,同一支探針讀到 awareness 為 2,而把顯示器由 100% → 150% → 125% → 100%
    /// 時,`windowScaleFactor` 記到 1.0 → 1.5 → 1.25 → 1.0,旁邊的 `windowDpi` 為
    /// 96 → 144 → 120 → 96。
    ///
    /// **幾何成本為零,而這正是「要量、不要用判斷的」的理由。** `testapp/actions/win/` 中每一個座標
    /// 都是對著現行視窗幾何量出來的,因此一個會改變它的模式會讓那些檔案全部失效。在 125% 下兩種模式
    /// 各擷一次:`748x428` 與 `748x428`。兩者只在**變更之後**才有差別——而那正是本設定的用途。
    ///
    /// `overwrite` 為 false,因此 `GDK_WIN32_PER_MONITOR_HIDPI=0` 仍然勝出——這裡改的是預設值,
    /// 不是把那個開關拿走。GDK 會在開啟 display 時讀取它,那晚於此處執行、早於任何視窗存在。
    private static func enablePerMonitorDPIAwareness() {
        #if os(Windows)
            g_setenv("GDK_WIN32_PER_MONITOR_HIDPI", "1", 0)
        #endif
    }

    /// Asks PangoCairo for its fontconfig font map on Windows, so a character
    /// followed by U+FE0F is drawn in colour.
    ///
    /// `EmojiKeywordModel.displayed` adds U+FE0F to a text-style emoji (🅿 ✈ ❤)
    /// so it is drawn in colour. Pango then asks for the family `emoji` with
    /// colour, and the win32 font map resolves neither that nor an explicit
    /// "Segoe UI Emoji": `couldn't load font "emoji Not-Rotated With-Color 20"`,
    /// `All font fallbacks failed`, and a hex box -- P103's 🅿 ✈ ❤ on GTK 4.22.4
    /// and 4.24.1 alike. Measured 2026-10-29 with a small GTK program drawing
    /// the three with and without U+FE0F in five font families: under the win32
    /// map every U+FE0F case was a box (15 warnings); under fontconfig all were
    /// drawn in colour from Segoe UI Emoji, with no warnings, and the plain
    /// characters stayed monochrome.
    ///
    /// `overwrite` is false, so `PANGOCAIRO_BACKEND=win32` still wins.
    ///
    /// 在 Windows 上要求 PangoCairo 使用 fontconfig 字型對應，讓後接 U+FE0F 的字元以彩色繪製。
    /// `EmojiKeywordModel.displayed` 會替文字樣式的 emoji(🅿 ✈ ❤)加上 U+FE0F 以彩色繪製。Pango 接著要求帶顏色的
    /// `emoji` 家族，而 win32 字型對應既解析不出它，也解析不出明確指定的「Segoe UI Emoji」:先是
    /// `couldn't load font "emoji Not-Rotated With-Color 20"`、`All font fallbacks failed`,然後畫成 hex 方框——
    /// P103 的 🅿 ✈ ❤ 在 GTK 4.22.4 與 4.24.1 上都是如此。2026-10-29 以一支小 GTK 程式實測(三個字元帶與不帶
    /// U+FE0F,五種字型家族):win32 對應下每個帶 U+FE0F 的都是方框(15 則警告);fontconfig 下全部由 Segoe UI Emoji
    /// 畫成彩色、沒有警告，不帶選擇符的字元仍是單色。`overwrite` 為 false,因此 `PANGOCAIRO_BACKEND=win32` 仍然勝出。
    private static func useFontconfigForPango() {
        #if os(Windows)
            g_setenv("PANGOCAIRO_BACKEND", "fc", 0)
        #endif
    }

    /// Asks GDK for Direct Composition, so GTK can use a hardware renderer.
    ///
    /// ON BY DEFAULT. `-GPU 0` turns it off along with the rest of hardware
    /// rendering, and `SCUI_GTK_DCOMP=0` turns off just this, for bisecting.
    ///
    /// Why it matters. On Windows GTK cannot realize its GL
    /// renderer -- `Failed to realize renderer 'GskGLRenderer' for surface
    /// 'GdkWin32Toplevel': OpenGL requires Direct Composition` -- and silently
    /// falls back to `GskCairoRenderer`, which is software: no OpenGL for
    /// `GtkGLArea`, and every frame drawn on the CPU. Geometric effects render
    /// on both renderers (see AffineTransform2D for what the cairo renderer
    /// needs).
    ///
    /// `GDK_DEBUG=dcomp` is a feature switch rather than a logging category --
    /// GDK lists it as "Enable Direct Composition (Windows)". Appended rather
    /// than assigned, so an existing GDK_DEBUG is not thrown away.
    ///
    /// 向 GDK 要求啟用 Direct Composition，使 GTK 得以採用硬體繪製器。
    ///
    /// **預設開啟**。`-GPU 0` 會連同其餘硬體繪製一併關閉它；`SCUI_GTK_DCOMP=0` 則只關閉這一項，供二分比對。
    ///
    /// 為何重要：在 Windows 上，GTK 無法實現它的 GL 繪製器——
    /// `Failed to realize renderer 'GskGLRenderer' for surface 'GdkWin32Toplevel':
    /// OpenGL requires Direct Composition`——並靜默退回到軟體的 `GskCairoRenderer`:沒有 OpenGL 可供
    /// `GtkGLArea` 使用，每一幀都由 CPU 繪製。幾何效果在兩種繪製器上都會繪出(cairo 繪製器需要什麼，見
    /// AffineTransform2D)。
    ///
    /// `GDK_DEBUG=dcomp` 是功能開關而非記錄類別——GDK 自己將它列為
    /// 「Enable Direct Composition (Windows)」。此處採「附加」而非「指派」，以免丟棄既有的
    /// GDK_DEBUG 設定。
    private static func enableDirectCompositionIfRequested() {
        #if os(Windows)
            // `>= 1`, so Direct Composition is on by default, as
            // `DebugFeatures.gpuSelection` documents `1` ("the default, asks for
            // hardware"). `-GPU 0` is the software opt-out, and
            // `SCUI_GTK_DCOMP=0` turns off just this.
            //
            // Without dcomp GTK falls back to GskCairoRenderer, which is
            // software. Geometric effects render on both: GtkBackend writes
            // each transform as translate, rotate and scale steps, which the
            // cairo renderer accepts (see AffineTransform2D). P11, P15-DARK
            // and P25 captured both ways differ only in glyph antialiasing and
            // colour rounding between the cairo and GL renderers: of P25's
            // 128,510 differing pixels, 711 exceed a delta of 8.
            //
            // `>= 1`,亦即 Direct Composition **預設開啟**,與 `DebugFeatures.gpuSelection` 文件中 `1` 的意義
            // (「預設值，要求硬體」)一致。`-GPU 0` 是軟體退路，而 `SCUI_GTK_DCOMP=0` 只關閉這一項。
            //
            // 沒有 dcomp 時 GTK 會退回軟體的 GskCairoRenderer。幾何效果在兩者上都會繪製:GtkBackend 把每個變換寫成
            // cairo renderer 接受的平移、旋轉與縮放步驟(見 AffineTransform2D)。P11、P15-DARK 與 P25 各擷取兩次
            // 比對，唯一的差異是 cairo 與 GL 兩種 renderer 之間的字形反鋸齒與色彩捨入:P25 的 128,510 個相異像素中，
            // 僅 711 個差幅超過 8。
            let forcedOff = ProcessInfo.processInfo.environment["SCUI_GTK_DCOMP"] == "0"
            guard !forcedOff, DebugFeatures.gpuSelection >= 1 else { return }

            // The guard has to come BEFORE asking, because the failure it
            // prevents is a segmentation fault and there is nothing to catch.
            // Measured 2026-08-29 on P40, GL disabled through
            // GDK_DISABLE=gl,vulkan,d3d11,d3d12:
            //
            //   dcomp off -> alive, falls back to GskCairoRenderer
            //   dcomp on  -> SIGSEGV before a window appears
            //
            // So "ask for it and fall back if it fails" is not available. The
            // fallback has to be a decision made in advance.
            //
            // 這道防護必須在「提出要求之前」，因為它所預防的失敗是 segmentation fault，
            // 沒有任何東西可以攔截。2026-08-29 於 P40 實測，以
            // GDK_DISABLE=gl,vulkan,d3d11,d3d12 停用 GL：
            //
            //   dcomp 關閉 -> 存活，退回 GskCairoRenderer
            //   dcomp 開啟 -> 視窗出現前即 SIGSEGV
            //
            // 因此「先要求，失敗再退回」這條路並不存在。退回必須是事前就做好的決定。
            // The global `logger`, not `debugLogOnce`: this runs before there is
            // an instance to hold the once-per-site set, and it happens once per
            // process anyway.
            // 使用全域的 `logger` 而非 `debugLogOnce`：此處執行時尚無實例可持有「每處僅記一次」
            // 的集合，而且它本來每個行程也只會發生一次。
            // Respect an explicit GDK_DISABLE. Asking for Direct Composition
            // after the caller has switched GL off is the exact combination
            // measured to crash, and it is the one case of "GL is unavailable"
            // that can be detected for certain rather than guessed at.
            // 尊重明確設定的 GDK_DISABLE。在呼叫端已關閉 GL 之後仍要求 Direct Composition，
            // 正是實測會當機的那個組合，而且它是「GL 不可用」諸情況中唯一能被確定偵測、
            // 而非用猜的那一個。
            let disabled = ProcessInfo.processInfo.environment["GDK_DISABLE"] ?? ""
            let disablesGL = disabled.split(separator: ",")
                .contains { $0.trimmingCharacters(in: .whitespaces) == "gl" }
            guard !disablesGL else {
                logger.notice(
                    """
                    GDK_DISABLE contains gl, so Direct Composition was not requested. \
                    Asking for it with GL switched off crashes GTK rather than degrading.
                    """
                )
                return
            }

            guard hasHardwareDisplayAdapter() else {
                logger.notice(
                    """
                    No hardware display adapter found, so Direct Composition was not \
                    requested and GTK will render in software. Asking for it without one \
                    crashes GTK rather than degrading. This is what -GPU 0 selects \
                    explicitly.
                    """
                )
                return
            }

            let existing = ProcessInfo.processInfo.environment["GDK_DEBUG"]
            let value = existing.map { $0.isEmpty ? "dcomp" : "\($0),dcomp" } ?? "dcomp"
            // `g_setenv`, not `setenv`: the latter is not in scope in Swift on
            // Windows, and GLib's is what GDK itself reads back.
            // 使用 `g_setenv` 而非 `setenv`：後者在 Windows 的 Swift 中不在作用域內，而前者正是
            // GDK 自己會讀回的那一個。
            _ = g_setenv("GDK_DEBUG", value, 1)
        #endif
    }

    #if os(Windows)
        /// Whether Windows reports a display adapter that is not a software one.
        ///
        /// Enumerates adapters and rejects the two names Windows uses when there
        /// is no driver -- "Microsoft Basic Display Adapter" and "Microsoft
        /// Basic Render Driver". A machine showing only those has no GL for GTK
        /// to realize, which is the case that crashes.
        ///
        /// A name test rather than a capability test, and that is a real
        /// limitation: an adapter present but with a driver too old for GL 3.3
        /// would pass this and still fail. The honest probe is to create a WGL
        /// context and see, which is a great deal more code; this catches the
        /// case that actually occurs -- a VM or a session with no GPU at all.
        ///
        /// Windows 是否回報了「非軟體」的顯示介面卡。
        ///
        /// 列舉所有介面卡，並排除 Windows 在沒有驅動程式時使用的兩個名稱——
        /// 「Microsoft Basic Display Adapter」與「Microsoft Basic Render Driver」。只顯示
        /// 這兩者之一的機器，沒有任何 GL 可供 GTK 實現，而那正是會導致當機的情況。
        ///
        /// 這是「比對名稱」而非「檢測能力」，此為真實的侷限：一張存在、但驅動程式舊到不支援
        /// GL 3.3 的介面卡會通過此檢查卻仍然失敗。誠實的探測方式是實際建立一個 WGL context
        /// 來看結果，那需要多得多的程式碼；此處攔截的是實際會發生的情況——虛擬機，或完全沒有
        /// GPU 的工作階段。
        private static func hasHardwareDisplayAdapter() -> Bool {
            var index: DWORD = 0
            while true {
                var device = DISPLAY_DEVICEW()
                device.cb = DWORD(MemoryLayout<DISPLAY_DEVICEW>.size)
                guard EnumDisplayDevicesW(nil, index, &device, 0) else { break }
                index += 1
                let name = withUnsafeBytes(of: device.DeviceString) { raw -> String in
                    guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt16.self) else {
                        return ""
                    }
                    return String(decodingCString: base, as: UTF16.self)
                }
                if !name.isEmpty && !name.hasPrefix("Microsoft Basic") {
                    return true
                }
            }
            return false
        }

        /// `-GPU list`: print the adapters as a `.csv2` table and stop.
        ///
        /// A query, not a launch. It writes to stdout so it can be piped
        /// straight into `csv2`, and exits rather than starting the
        /// application, because the caller asked what is available and not to
        /// run anything.
        ///
        /// Two header rows, English then Traditional Chinese, which is what
        /// `.csv2` means in this project -- the same shape as
        /// matrix_coverage/*.csv2, so the same tools read it.
        ///
        /// `selected_by` is the honest column and the reason this exists. On
        /// GtkBackend/Windows an adapter is chosen by POLICY, not by number, so
        /// several rows can carry the same answer and no row is addressable on
        /// its own. Printing "2" against a card the flag cannot actually pick
        /// would be the lie this whole flag is meant to avoid.
        ///
        /// `-GPU list`：以 `.csv2` 表格印出所有介面卡，然後結束。
        ///
        /// 這是查詢，不是啟動。它輸出到 stdout，以便直接管線給 `csv2`；並且結束而不啟動應用程式，
        /// 因為呼叫者問的是「有哪些可用」，而非要執行任何東西。
        ///
        /// 兩列標頭、先英文後繁體中文，這正是本專案中 `.csv2` 的定義——與 matrix_coverage/*.csv2
        /// 同一種形狀，因此同一套工具讀得動。
        ///
        /// `selected_by` 是最誠實的一欄，也是本功能存在的理由。在 GtkBackend/Windows 上，介面卡是
        /// 依**政策**而非依編號選取的，因此多列可能帶有相同的答案，而且沒有任何一列可被單獨定址。
        /// 若在一張旗標其實選不到的卡旁邊印上「2」，那正是這個旗標本身要避免的謊言。
        static func printAdapterTableIfRequested() {
            guard DebugFeatures.value(after: "-GPU")?.lowercased() == "list" else { return }

            var rows: [(index: Int, name: String, primary: Bool, removable: Bool, attached: Bool)] =
                []
            var index: DWORD = 0
            while true {
                var device = DISPLAY_DEVICEW()
                device.cb = DWORD(MemoryLayout<DISPLAY_DEVICEW>.size)
                guard EnumDisplayDevicesW(nil, index, &device, 0) else { break }
                let name = withUnsafeBytes(of: device.DeviceString) { raw -> String in
                    guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt16.self) else {
                        return ""
                    }
                    return String(decodingCString: base, as: UTF16.self)
                }
                // winnt.h / wingdi.h flags, spelled out because Swift imports
                // values and not macros.
                // 取自 winnt.h / wingdi.h 的旗標，之所以寫成字面值，是因為 Swift 匯入的是值而非巨集。
                let attachedToDesktop = device.StateFlags & 0x0000_0001 != 0
                let primaryDevice = device.StateFlags & 0x0000_0004 != 0
                let removable = device.StateFlags & 0x0000_0020 != 0
                if !name.isEmpty, !rows.contains(where: { $0.name == name }) {
                    rows.append(
                        (rows.count, name, primaryDevice, removable, attachedToDesktop)
                    )
                }
                index += 1
            }

            let hardware = rows.filter { !$0.name.hasPrefix("Microsoft Basic") }
            // Hand-written, because `csv2` is a command-line tool and this is a
            // library that must not shell out. That makes this the one place in
            // the project writing CSV without it, so it is written to make the
            // failure csv2 exists to prevent impossible rather than unlikely.
            //
            // Two rules, both from `.csv2` itself:
            //   * a record is ONE line -- so a newline inside a field is
            //     escaped to the two characters \n, never emitted raw. An
            //     adapter name will not contain one, but "will not" is not a
            //     guarantee, and a raw newline here would silently split one
            //     record into two and misalign every column after it.
            //   * a field containing a comma or a quote is quoted, with inner
            //     quotes doubled, which is ordinary RFC 4180.
            //
            // Verified by round-tripping the output through the real csv2:
            // `csv2 --json` reports 7 fields per record with the values intact,
            // which is the alignment test. Reading the pretty-printed table is
            // not -- a misquoted field still looks like a table.
            //
            // 此處為手寫，因為 `csv2` 是命令列工具，而這是一個不該去 shell out 的函式庫。這使得
            // 本處成為全專案唯一不透過它寫出 CSV 的地方，因此寫法上要讓「csv2 存在所要防止的那種
            // 失敗」變成**不可能**，而不只是「不太可能」。
            //
            // 兩條規則，皆源自 `.csv2` 本身：
            //   * 一筆紀錄就是**一行**——因此欄位內的換行會被逸出為 \n 兩個字元，絕不原樣輸出。
            //     介面卡名稱不會含有換行，但「不會」並不是保證；此處若出現原始換行，會靜默地把
            //     一筆紀錄拆成兩筆，並使其後每一欄都錯位。
            //   * 含有逗號或引號的欄位會加上引號，內部引號加倍，此即一般的 RFC 4180。
            //
            // 已透過真正的 csv2 做來回驗證：`csv2 --json` 回報每筆 7 欄且值皆完好，那才是對齊測試。
            // 讀那張排版漂亮的表格則不是——欄位引號錯了，它看起來仍然像一張表。
            func quote(_ s: String) -> String {
                let flattened =
                    s
                        .replacingOccurrences(of: "\r\n", with: #"\n"#)
                        .replacingOccurrences(of: "\n", with: #"\n"#)
                        .replacingOccurrences(of: "\r", with: #"\n"#)
                guard flattened.contains(",") || flattened.contains("\"") else { return flattened }
                return "\"\(flattened.replacingOccurrences(of: "\"", with: "\"\""))\""
            }

            var out = "index,name,primary,removable,attached,selected_by,note\n"
            out += "索引,名稱,主要,可移除,已接上,由哪個 -GPU 選取,備註\n"
            for row in rows {
                let isSoftware = row.name.hasPrefix("Microsoft Basic")
                let selectedBy: String
                let note: String
                if isSoftware {
                    selectedBy = "0"
                    note = "software adapter; -GPU 0 renders here"
                } else if hardware.count < 2 {
                    selectedBy = "1 or 2"
                    note = "only one hardware adapter, so every policy resolves to it"
                } else if row.primary {
                    selectedBy = "1"
                    note = "power saving / default"
                } else {
                    selectedBy = "2"
                    note = "high performance; -GPU 3 and above clamp to this"
                }
                out += [
                    String(row.index),
                    quote(row.name),
                    row.primary ? "yes" : "no",
                    row.removable ? "yes" : "no",
                    row.attached ? "yes" : "no",
                    selectedBy,
                    quote(note),
                ].joined(separator: ",")
                out += "\n"
            }
            FileHandle.standardOutput.write(Data(out.utf8))
            exit(0)
        }

        /// Every non-software display adapter, by name.
        /// 所有非軟體的顯示介面卡名稱。
        // Internal rather than private: GtkBackend+GraphicsAdapters.swift is a
        // separate file and needs these to implement the protocol over the same
        // code, instead of enumerating the adapters a second time.
        // 使用 internal 而非 private：GtkBackend+GraphicsAdapters.swift 是另一個檔案，需要用到
        // 這些函式，以便在「同一份程式碼」之上實作該協定，而不是再列舉一次介面卡。
        static func hardwareAdapterNames() -> [String] {
            var names: [String] = []
            var index: DWORD = 0
            while true {
                var device = DISPLAY_DEVICEW()
                device.cb = DWORD(MemoryLayout<DISPLAY_DEVICEW>.size)
                guard EnumDisplayDevicesW(nil, index, &device, 0) else { break }
                index += 1
                let name = withUnsafeBytes(of: device.DeviceString) { raw -> String in
                    guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt16.self) else {
                        return ""
                    }
                    return String(decodingCString: base, as: UTF16.self)
                }
                if !name.isEmpty, !name.hasPrefix("Microsoft Basic"), !names.contains(name) {
                    names.append(name)
                }
            }
            return names
        }

        private static let gpuRelaunchMarker = "SCUI_GPU_RELAUNCHED"
        private static let gpuPreferencesKey =
            #"Software\Microsoft\DirectX\UserGpuPreferences"#

        private static func wide(_ string: String) -> [UInt16] { Array(string.utf16) + [0] }

        // Spelled out because these are C macros, and Swift imports values, not
        // macros -- `KEY_READ` and friends are not in scope. Values from
        // winnt.h; KEY_READ is STANDARD_RIGHTS_READ | KEY_QUERY_VALUE |
        // KEY_ENUMERATE_SUB_KEYS | KEY_NOTIFY.
        // 之所以寫成字面值，是因為這些是 C 巨集，而 Swift 匯入的是「值」而非「巨集」——
        // `KEY_READ` 之類根本不在作用域內。數值取自 winnt.h；KEY_READ 為
        // STANDARD_RIGHTS_READ | KEY_QUERY_VALUE | KEY_ENUMERATE_SUB_KEYS | KEY_NOTIFY。
        private static let regKeyRead: DWORD = 0x2_0019
        private static let regKeySetValue: DWORD = 0x0002
        private static let regOptionNonVolatile: DWORD = 0
        private static let regTypeSZ: DWORD = 1

        static func executablePath() -> String? {
            var buffer = [UInt16](repeating: 0, count: 32768)
            let length = Int(GetModuleFileNameW(nil, &buffer, DWORD(buffer.count)))
            guard length > 0 else { return nil }
            return String(decoding: buffer.prefix(length), as: UTF16.self)
        }

        static func readGpuPreference(for executable: String) -> Int? {
            var key: HKEY?
            var path = wide(gpuPreferencesKey)
            guard
                RegOpenKeyExW(HKEY_CURRENT_USER, &path, 0, regKeyRead, &key) == ERROR_SUCCESS,
                let key
            else { return nil }
            defer { RegCloseKey(key) }

            var name = wide(executable)
            var size: DWORD = 0
            guard RegQueryValueExW(key, &name, nil, nil, nil, &size) == ERROR_SUCCESS, size > 0
            else { return nil }
            var data = [UInt8](repeating: 0, count: Int(size) + 2)
            guard RegQueryValueExW(key, &name, nil, nil, &data, &size) == ERROR_SUCCESS
            else { return nil }
            let text = data.withUnsafeBytes { raw -> String in
                guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt16.self) else {
                    return ""
                }
                return String(decodingCString: base, as: UTF16.self)
            }
            guard let marker = text.range(of: "GpuPreference=") else { return nil }
            return Int(text[marker.upperBound...].prefix { $0.isNumber })
        }

        private static func writeGpuPreference(_ value: Int, for executable: String) -> Bool {
            var key: HKEY?
            var path = wide(gpuPreferencesKey)
            var disposition: DWORD = 0
            guard
                RegCreateKeyExW(
                    HKEY_CURRENT_USER,
                    &path,
                    0,
                    nil,
                    regOptionNonVolatile,
                    regKeySetValue,
                    nil,
                    &key,
                    &disposition
                ) == ERROR_SUCCESS,
                let key
            else { return false }
            defer { RegCloseKey(key) }
            var name = wide(executable)
            let data = wide("GpuPreference=\(value);")
            let bytes = DWORD(data.count * MemoryLayout<UInt16>.size)
            return data.withUnsafeBytes { raw in
                RegSetValueExW(
                    key,
                    &name,
                    0,
                    regTypeSZ,
                    raw.baseAddress?.assumingMemoryBound(to: BYTE.self),
                    bytes
                ) == ERROR_SUCCESS
            }
        }

        /// Applies `-GPU N` by pinning this executable, after asking.
        ///
        /// Windows fixes an OpenGL process's adapter **when the process is
        /// created**, from `HKCU\Software\Microsoft\DirectX\UserGpuPreferences`.
        /// Nothing a running process does changes its own adapter, so `-GPU 2`
        /// cannot take effect in the run that asked for it -- the value has to
        /// be written and the process started again.
        ///
        /// It asks first because it writes to the user's registry and then
        /// replaces the running process, neither of which should happen merely
        /// because a flag was passed. `-y` does not skip the prompt; it decides
        /// which way a blank answer falls, and a blank answer is what a run with
        /// nothing on stdin gets, so `-y` is also what makes this scriptable.
        ///
        /// 在詢問之後，透過釘定本執行檔來套用 `-GPU N`。
        ///
        /// Windows 是在**行程建立的當下**，依 `HKCU\Software\Microsoft\DirectX\UserGpuPreferences`
        /// 決定一個 OpenGL 行程取得哪張介面卡。執行中的行程無法改變自己的介面卡，因此 `-GPU 2`
        /// 不可能在「提出要求的那一次執行」中生效——必須先寫入該值，然後重新啟動行程。
        ///
        /// 之所以先詢問，是因為它會寫入使用者的登錄檔並取代正在執行的行程，這兩件事都不該只因為
        /// 「傳了一個旗標」就發生。`-y` 並不會略過提示；它決定「空白回答」倒向哪一邊，而 stdin
        /// 未接任何東西的執行所得到的正是空白回答，因此 `-y` 也是讓這件事可被腳本使用的關鍵。
        static func ensureGpuPreference() {
            var wanted = DebugFeatures.gpuSelection

            // Windows cannot express "the nth adapter" for OpenGL. Its
            // UserGpuPreferences takes exactly three values -- 0 unspecified,
            // 1 power saving, 2 high performance -- and a WGL context has no
            // per-adapter selection. Writing GpuPreference=3 would put a value
            // there that Windows does not define.
            //
            // Said loudly, on stderr, not through the logger. A request that
            // cannot be honoured must not be answered by quietly doing
            // something else -- that is the failure this whole flag exists to
            // avoid, and a notice-level log line is exactly how it would go
            // unnoticed.
            //
            // This is a GtkBackend limit, NOT a Windows one: WinUIBackend
            // reaches the same adapters through DXGI, where
            // D3D11CreateDevice takes an explicit adapter and EnumAdapters1
            // gives a real index. See testapp/plan/plan-gpu-selection.md.
            //
            // Windows 無法為 OpenGL 表達「第 n 張介面卡」。其 UserGpuPreferences 只接受三個
            // 值——0 未指定、1 省電、2 高效能——而 WGL context 沒有逐一介面卡的選擇機制。寫入
            // GpuPreference=3 等於在該處放進一個 Windows 並未定義的值。
            //
            // 此訊息大聲輸出至 stderr，而非透過 logger。一個無法被遵從的要求，絕不能以「安靜地
            // 做別的事」來回應——那正是這個旗標存在所要避免的失敗，而 notice 等級的日誌正是它
            // 會被忽略的方式。
            //
            // 這是 GtkBackend 的限制，**而非 Windows 的限制**：WinUIBackend 透過 DXGI 觸及同一批
            // 介面卡，那裡的 D3D11CreateDevice 可接受明確指定的 adapter，EnumAdapters1 也提供真正
            // 的索引。詳見 testapp/plan/plan-gpu-selection.md。
            if wanted > 2 {
                let adapters = hardwareAdapterNames()
                FileHandle.standardError.write(
                    Data(
                        """

                        ============================================================
                        -GPU \(wanted) CANNOT BE HONOURED ON GtkBackend/Windows.

                        GTK renders through OpenGL (WGL), and Windows selects an
                        OpenGL adapter only by policy, not by number:
                            0 unspecified   1 power saving   2 high performance

                        Using 2 (high performance) instead. On a machine with an
                        external GPU that is the one it resolves to.

                        Adapters seen: \(adapters.joined(separator: ", "))

                        For per-adapter selection use WinUIBackend, which goes
                        through DXGI and can take an explicit adapter.
                        ============================================================

                        """.utf8
                    )
                )
                wanted = 2
            }
            // 0 is software and not an adapter choice; 1 is Windows' own default
            // and needs no pinning.
            // 0 是軟體繪製、並非選擇介面卡；1 是 Windows 自己的預設值，無須釘定。
            guard wanted >= 2 else { return }
            guard ProcessInfo.processInfo.environment[gpuRelaunchMarker] != "1" else {
                logger.notice("Already relaunched once for -GPU \(wanted); not trying again.")
                return
            }
            guard let executable = executablePath() else { return }
            if readGpuPreference(for: executable) == wanted { return }

            let adapters = hardwareAdapterNames()
            guard adapters.count >= 2 else {
                logger.notice(
                    """
                    -GPU \(wanted) asks for a high-performance adapter, but this machine \
                    reports \(adapters.count) hardware adapter(s): \
                    \(adapters.joined(separator: ", ")). Every preference resolves to the \
                    same one, so nothing was changed.
                    """
                )
                return
            }

            let current = readGpuPreference(for: executable).map(String.init) ?? "unset"
            let defaultsToYes = CommandLine.arguments.contains("-y")
            FileHandle.standardError.write(
                Data(
                    """

                    -GPU \(wanted) needs a Windows setting this process cannot change while \
                    running.

                      registry  HKCU\\\(gpuPreferencesKey)
                      value     \(executable)
                      change    GpuPreference \(current) -> \(wanted)
                      adapters  \(adapters.joined(separator: ", "))

                    Windows picks the adapter when a process starts, so applying this means \
                    writing the value and restarting this program.

                    Write it and restart? \(defaultsToYes ? "[Y/n]" : "[y/N]")
                    """.utf8
                )
            )

            let typed = readLine(strippingNewline: true)?
                .trimmingCharacters(in: .whitespaces).lowercased()
            let answer = (typed?.isEmpty ?? true) ? (defaultsToYes ? "y" : "n") : typed!
            guard answer == "y" || answer == "yes" else {
                FileHandle.standardError.write(
                    Data("Cancelled; continuing on the current adapter.\n".utf8)
                )
                return
            }
            guard writeGpuPreference(wanted, for: executable) else {
                logger.notice("Could not write the GPU preference; continuing unchanged.")
                return
            }
            FileHandle.standardError.write(Data("Written. Restarting.\n".utf8))

            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = Array(CommandLine.arguments.dropFirst())
            var environment = ProcessInfo.processInfo.environment
            environment[gpuRelaunchMarker] = "1"
            process.environment = environment
            do {
                try process.run()
            } catch {
                logger.notice("Could not relaunch to apply the GPU preference: \(error)")
                return
            }
            exit(0)
        }
    #endif

    /// Storage for ``BackendFeatures/GraphicsAdapters/adapterRemoved``.
    ///
    /// Here rather than in the conformance because a Swift extension cannot add
    /// stored properties. Not yet signalled by this backend: GTK on Windows has
    /// no adapter-removal notification wired up, so nothing calls it. Declared
    /// anyway, because the protocol is what makes the gap visible instead of
    /// leaving each backend to invent its own answer.
    ///
    /// ``BackendFeatures/GraphicsAdapters/adapterRemoved`` 的儲存空間。
    ///
    /// 之所以放在此處而非 conformance 中，是因為 Swift 的 extension 無法新增 stored property。
    /// 本 backend 目前**尚未**發出此訊號：Windows 上的 GTK 並未接上任何介面卡移除通知，因此不會有
    /// 東西呼叫它。仍然宣告它，是因為協定的作用正是讓這個缺口「看得見」，而不是任由各 backend
    /// 各自發明答案。
    public var adapterRemoved: (() -> Void)?

    var globalCSSProvider: CSSProvider?

    /// Kept alive for as long as the backend is. A `GSimpleAction` added to the
    /// application is referenced by it, but the Swift wrapper holds the closure,
    /// and letting it go would leave the accelerator firing into freed memory.
    /// 需與 backend 同壽。加入 application 的 `GSimpleAction` 會被其持有，但 Swift wrapper 才是
    /// 持有 closure 的一方；若讓它被釋放，加速鍵便會觸發到已釋放的記憶體。
    private var quitAction: GSimpleAction?

    public func runMainLoop(_ callback: @escaping @MainActor () -> Void) {
        installQuitShortcut()
        gtkApp.run { window in
            self.precreatedWindow = window

            // #386: read the ambient theme here, where GTK is initialised and
            // before anything has asked for an override. See ambientColorScheme.
            // #386：於此讀取環境主題——此處 GTK 已初始化，且尚無任何 override 被要求。
            self.sampleAmbientColorScheme()

            // #27: and keep following it. Must come AFTER the sample above, so
            // the handler's "did it change" comparison has a baseline; before
            // it, the first notification would compare against a default and
            // fire for nothing.
            // #27：並且持續跟隨它。必須在上方取樣**之後**，好讓 handler 的「是否改變」比較有一個
            // 基準值；若置於其前，第一次通知會與預設值比較，於是白白觸發一次。
            self.subscribeToAmbientColorSchemeChanges()

            // Before any window can receive touch: a device removed while a
            // gesture still points at it crashes GTK. See the declaration.
            // `SCUI_GTK_KEEP_REMOVED_DEVICES=0` turns it off, to test whether a
            // newer GTK still needs it (as SCUI_GTK_WARMUP=0 does for the warm-up).
            // 必須在任何視窗能收到觸控之前:裝置在手勢仍指著它時被移除,會讓 GTK 崩潰。詳見宣告處。
            // `SCUI_GTK_KEEP_REMOVED_DEVICES=0` 可關閉它，用來測試較新的 GTK 是否仍需要
            // (與 SCUI_GTK_WARMUP=0 之於 warm-up 相同)。
            if ProcessInfo.processInfo.environment["SCUI_GTK_KEEP_REMOVED_DEVICES"] != "0" {
                scui_retain_removed_devices()
            }

            // Before the app's first view, not after: Button measures its padding
            // once, from a probe button, and caches it (measureBorderedButtonPadding),
            // so rules loaded after `callback()` never reached a button's size --
            // platformMetricsCSS drew P52's buttons as tall as before (2026-10-18).
            // 在 app 的第一個 view 之前、而不是之後:Button 只用探針按鈕量一次內距並快取
            // (measureBorderedButtonPadding),所以 `callback()` 之後才載入的規則永遠影響不到按鈕的尺寸——
            // platformMetricsCSS 讓 P52 的按鈕畫得和之前一樣高(2026-10-18)。
            let provider = CSSProvider()
            provider.loadCss(
                from: """
                    /* A List draws no background of its own, as AppKit's
                       NSTableView with a clear background: a GtkListView
                       (node listview) otherwise paints the theme's view colour
                       over whatever sits behind it (P3's black columns).
                       List 不畫自己的背景，如同背景透明的 AppKit NSTableView;否則 GtkListView(節點 listview)
                       會把主題的 view 顏色蓋在後面的東西上(P3 的黑色欄位)。 */
                    list, listview {
                        background: none;
                    }

                    list > row {
                        padding: 0;
                        min-height: 0;
                    }

                    .navigation-sidebar {
                        margin: 0;
                        padding: 0;
                    }

                    .navigation-sidebar > row { margin: 0;
                        padding: 0;
                    }

                    /* #390: make disabled controls clearly distinct. GTK's
                       default theme dims an insensitive widget only subtly --
                       mostly its label colour -- so a disabled button reads as
                       enabled at a glance. SwiftUI fades the whole control;
                       fade it here too. sensitive = false is already set on
                       each control (see updateButton et al.), which is what
                       :disabled matches. */
                    button:disabled,
                    checkbutton:disabled,
                    switch:disabled,
                    entry:disabled,
                    scale:disabled,
                    spinbutton:disabled {
                        opacity: 0.5;
                    }
                    """ + Self.platformMetricsCSS
            )

            // Keep a reference around so that the provider doesn't get removed as
            // soon as we exit this scope.
            self.globalCSSProvider = provider

            callback()

            #if !os(macOS)
                Self.mainRunLoopTicklingLoop()
                // The tickler serves RunLoop timers; the main dispatch queue is
                // drained the moment it has work (gtk_dispatch_main_queue.c, P66).
                // tickler 服務 RunLoop 的計時器；主 dispatch 佇列則一有工作就排空(gtk_dispatch_main_queue.c,P66)。
                _ = scui_watch_dispatch_main_queue()
            #endif
        }
    }

    /// Control metrics close to AppKit's on macOS, where the two backends are
    /// compared side by side and AppKit is the reference there (P52, P91,
    /// 2026-10-18). Adwaita's button is about 34 px tall with 17 px of side
    /// padding and its entry 34 px; AppKit's regular push button and text field
    /// are 22. So P52's grid of 48 one-letter buttons overflowed its column on
    /// GTK, and P91's buttons and field stood half as tall again. Elsewhere GTK
    /// keeps its own theme's metrics, which is what its desktops expect. A
    /// horizontal scale drops Adwaita's 12 px side padding, so its trough spans the
    /// slider's frame as NSSlider's does, and its knob drops the negative side
    /// margins that let it stand past the trough, so at either end it stays inside
    /// the frame as NSSlider's knob does (P32, P99).
    /// macOS 上接近 AppKit 的控制項尺寸：兩個 backend 在那裡並排比較，而 macOS 上以 AppKit 為準(P52、P91,
    /// 2026-10-18)。Adwaita 的按鈕約 34 px 高、左右內距 17 px,輸入框 34 px;AppKit 的一般按鈕與文字欄是 22。
    /// 所以 P52 由 48 個單字母按鈕組成的格子在 GTK 上溢出了它的欄，P91 的按鈕與欄位高出一半。其他平台上 GTK 保留它
    /// 自己主題的尺寸，那是它的桌面所預期的。水平 scale 拿掉 Adwaita 左右 12 px 的內距，讓軌道與 NSSlider 一樣撐滿滑桿的框;
    /// 滑塊也拿掉讓它凸出軌道的左右負 margin,所以在兩端時與 NSSlider 的滑塊一樣留在框內(P32、P99)。
    static var platformMetricsCSS: String {
        #if os(macOS)
            """

            button {
                min-height: 20px;
                min-width: 16px;
                padding: 1px 10px;
            }

            button.image-button {
                padding: 1px 4px;
            }

            entry {
                min-height: 20px;
                padding-top: 0;
                padding-bottom: 0;
            }

            scale.horizontal {
                padding-left: 0;
                padding-right: 0;
            }

            scale.horizontal > trough > slider {
                margin-left: 0;
                margin-right: 0;
            }
            """
        #else
            ""
        #endif
    }

    private static func mainRunLoopTicklingLoop(nextDelayMilliseconds: Int? = nil) {
        Self.runInMainThread(afterMilliseconds: nextDelayMilliseconds ?? 50) {
            // This performs one pass through the run loop
            let nextDate = RunLoop.main.limitDate(forMode: .default)

            // This isn't expected to be nil, but if it is we can just loop
            // again quickly with the default delay.
            let nextDelay = nextDate.map {
                return max(min(Int($0.timeIntervalSinceNow * 1000), 50), 0)
            }
            mainRunLoopTicklingLoop(nextDelayMilliseconds: nextDelay)
        }
    }

    public func createWindow(withDefaultSize defaultSize: SIMD2<Int>?, id: String) -> Window {
        let window: Gtk.ApplicationWindow
        if let precreatedWindow {
            self.precreatedWindow = nil
            window = precreatedWindow
        } else {
            window = Gtk.ApplicationWindow(application: gtkApp)
        }

        windows.append(window)
        // Super held, from the key events; see GtkHeldSuperKey.
        // 由按鍵事件得知的 Super 按住狀態；見 GtkHeldSuperKey。
        GtkHeldSuperKey.track(window)

        if let defaultSize {
            // `SCUI_DEBUG_DECORATION=1|2|3`: what `Window.titlebarNaturalHeight`
            // reports before the window is mapped, printed and appended to
            // decoration-debug.log. The window's size itself comes from the
            // allowance below.
            //
            // GTK on Windows and under WSLg loses the same 39 to its header bar;
            // only the frame thickness differs (+28/+29 against WinUI's +16/+39;
            // P16 asking for 900x600, `SCUI_DEBUG_SPLIT=1`, 2026-09-03).
            //
            // `SCUI_DEBUG_DECORATION=1|2|3`:視窗被 map 之前 `Window.titlebarNaturalHeight` 回報的值，會被印出並附加到
            // decoration-debug.log。視窗本身的尺寸來自下方的額度。
            //
            // Windows 與 WSLg 上的 GTK 被標題列吃掉的同樣是 39;兩者相差的只有外框厚度(+28/+29 對 WinUI 的
            // +16/+39;P16 要求 900x600,`SCUI_DEBUG_SPLIT=1`,2026-09-03)。
            let decorationProbe = ProcessInfo.processInfo.environment["SCUI_DEBUG_DECORATION"]
            if decorationProbe == "1" || decorationProbe == "2" || decorationProbe == "3" {
                // `1` measures as is and reports titlebar=nil: GTK's own
                // decoration is not a titlebar widget. `2` and `3` install a
                // GtkHeaderBar first, so the same measurement runs against a
                // titlebar that exists (47, against GTK's own 39).
                //
                // `1` 照原樣量測並回報 titlebar=nil:GTK 自身的裝飾不是一個 titlebar widget。`2` 與 `3` 會先裝上
                // 一個 GtkHeaderBar,使同一個量測得以對著一個確實存在的 titlebar 執行(47,相對於 GTK 自身的 39)。
                if decorationProbe == "2" || decorationProbe == "3" {
                    window.installMeasurableTitlebar()
                }
                let measured = window.titlebarNaturalHeight
                let line =
                    "[decoration] probe=\(decorationProbe ?? "?") titlebar="
                        + (measured.map(String.init) ?? "nil")
                        + " requested=\(defaultSize.x)x\(defaultSize.y)\n"
                print(line, terminator: "")
                if let data = line.data(using: .utf8) {
                    let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                        .appendingPathComponent("decoration-debug.log")
                    if let handle = try? FileHandle(forWritingTo: url) {
                        _ = try? handle.seekToEnd()
                        try? handle.write(contentsOf: data)
                        try? handle.close()
                    } else {
                        try? data.write(to: url)
                    }
                }
            }
        }

        // Outside the `SCUI_DEBUG_DECORATION` block, so it runs whether or not
        // the variable is set.
        //
        // 放在 `SCUI_DEBUG_DECORATION` 區塊之外，因此不論該變數是否設定都會執行。
        if let defaultSize {
            // `.gtkOwnDecoration`, not `.bare`. The other probes all report 47
            // because each measures a `GtkHeaderBar` this code created, while
            // the header GTK lays out for itself is 39; adding 47 overshot by
            // 8-9 (`shortfall 0x-9`, 2026-09-16). This probe walks a realized,
            // never-presented window's children for GTK's OWN header bar and
            // reports 39 before present -- the decoration measured rather than a
            // constant written down (#79 option (c)).
            // 用 `.gtkOwnDecoration`,不是 `.bare`。其他探針全都回報 47,因為它們量的都是**這段程式碼自己建立的**
            // `GtkHeaderBar`,而 GTK 為它自己排版的那條是 39;加 47 會超出 8~9(`shortfall 0x-9`,2026-09-16)。
            // 這個探針會在一個 realize 過、從不 present 的視窗子節點中找出 **GTK 自己的** header bar,並在 present
            // 之前回報 39——**量出來的**裝飾，而不是一個被寫死的常數(#79 選項 (c))。
            let titlebarAllowance = Gtk.Window.probeHeaderBarHeight(.gtkOwnDecoration) ?? 0
            titlebarAllowances[ObjectIdentifier(window)] = titlebarAllowance
            window.defaultSize = Size(
                width: defaultSize.x,
                height: defaultSize.y + titlebarAllowance
            )
            DebugFeatures.log(
                "titlebar allowance: defaultSize=\(defaultSize.x)x\(defaultSize.y) "
                    + "+\(titlebarAllowance) -> \(defaultSize.y + titlebarAllowance)"
            )
        } else {
            // Says so out loud: a silent skip here and an allowance that does
            // not work produce the same screen.
            // 明講出來：此處若靜默跳過，與「額度無效」會產生同一個畫面。
            DebugFeatures.log("titlebar allowance: SKIPPED, defaultSize is nil")
        }

        window.setChild(Gtk.Box())

        // The window's own children and the header-bar probes before
        // `present`, for comparison with the AFTER line `reportContentSizeShortfall`
        // prints once the window is mapped. Walking the window's children finds
        // any widget GTK put there, whoever created it, where
        // `gtk_window_get_titlebar` answers NULL for GTK's own decoration.
        //
        // 在 `present` 之前輸出視窗自己的子項與各個 header bar 探針，以便與視窗 map 之後
        // `reportContentSizeShortfall` 印出的 AFTER 那行對照。遍歷視窗的子項能找到 GTK 放在那裡的任何
        // widget,無論它是誰建立的;`gtk_window_get_titlebar` 對 GTK 自身的裝飾則回答 NULL。
        DebugFeatures.log(
            "decoration probe BEFORE present: "
                + (window.childMeasurements.isEmpty
                    ? "no children"
                    : window.childMeasurements
                    .map { "\($0.typeName)=\($0.naturalHeight)" }
                    .joined(separator: " "))
                + " | headerbar bare="
                + (Gtk.Window.probeHeaderBarHeight(.bare).map(String.init) ?? "nil")
                + " titlebarClass="
                + (Gtk.Window.probeHeaderBarHeight(.withTitlebarClass).map(String.init) ?? "nil")
                + " inWindow="
                + (Gtk.Window.probeHeaderBarHeight(.insideAWindow).map(String.init) ?? "nil")
                + " gtkOwn="
                + (Gtk.Window.probeHeaderBarHeight(.gtkOwnDecoration).map(String.init) ?? "nil")
        )

        // Kept so `reportContentSizeShortfall` can compare what was asked for
        // with what the content got. It runs from `updateWindow`, on every
        // layout pass, because the "map" signal is too early: instrumented, it
        // reports `contentAllocation=0x0` -- the window is mapped before its
        // child has any allocation at all.
        //
        // 保存下來，讓 `reportContentSizeShortfall` 能比較所要求的與內容實際拿到的。它由 `updateWindow` 在每次
        // 版面計算時執行，因為 `"map"` signal 太早：加上診斷後它回報 `contentAllocation=0x0`——視窗被 map 時，
        // 其 child 根本還沒有任何配置。
        if let defaultSize {
            requestedContentSizes[ObjectIdentifier(window)] = defaultSize
        }

        window.notifyIsActive = { _ in
            self.rootEnvironmentChangeHandler?()
        }

        // Before the content exists, so the first GPU frame does not land
        // after `onAppear` (P97). See `warmUpRenderer(of:)`.
        // 在內容存在之前執行，讓第一個 GPU 幀不會落在 `onAppear` 之後(P97)。見 `warmUpRenderer(of:)`。
        #if os(Windows) || os(Linux)
            warmUpRenderer(of: window)
        #endif

        return window
    }

    /// The content size each window was created with, for
    /// `reportContentSizeShortfall`.
    /// 各視窗建立時所要求的內容尺寸，供 `reportContentSizeShortfall` 使用。
    private var requestedContentSizes: [ObjectIdentifier: SIMD2<Int>] = [:]

    /// Logs, through `DebugFeatures.log`, the difference between the content
    /// size a window asked for and the size its content was allocated.
    ///
    /// `gtk_window_set_default_size` sizes the window, and under client-side
    /// decorations the header bar is inside it, so without the allowance
    /// `createWindow` adds an app asking for 900x600 got 900x561 of content on
    /// WSLg. AppKit and WinUI both treat the request as content -- on macOS the
    /// same app gets a 900x628 frame around 900x600, on Windows a 916x639 frame
    /// around a 900x600 client. This only reports; see the note in the body for
    /// why it does not correct.
    ///
    /// 透過 `DebugFeatures.log` 記錄視窗所要求的內容尺寸與其內容實際配置到的尺寸之差。
    ///
    /// `gtk_window_set_default_size` 設定的是視窗，而在 client-side decoration 之下標題列位於其內，因此若沒有
    /// `createWindow` 加上的額度，一支要求 900x600 的 app 在 WSLg 上只拿到 900x561 的內容。AppKit 與 WinUI 都把
    /// 該要求視為內容——macOS 上同一支 app 得到 900x628 的外框包著 900x600,Windows 上是 916x639 的外框包著
    /// 900x600 的 client。本方法只回報；為何不修正，見方法內的註記。
    private func reportContentSizeShortfall(of window: Window) {
        let key = ObjectIdentifier(window)
        guard let requested = requestedContentSizes[key],
              let content = window.getChild()
        else { return }

        let allocated = content.allocatedSize

        // Still zero means the allocation has not happened yet, so this is not
        // the pass that can measure it; the next pass tries again.
        // 仍為零代表配置尚未發生，因此這一輪無法量測；下一輪會再試。
        guard allocated.width > 0, allocated.height > 0 else { return }

        // Once per window. `updateWindow` runs on every layout pass; reporting on
        // each one would repeat the same lines and, in SCUI_DEBUG builds, queue two
        // more timers every time. The first real allocation is the reading.
        // 每個視窗只回報一次。`updateWindow` 每次排版都會執行；每次都回報會重複印出相同的行，而且在 SCUI_DEBUG
        // 建置中每次都再排兩個計時器。第一次真正的配置就是要的讀數。
        requestedContentSizes[key] = nil

        let shortfallX = requested.x - allocated.width
        let shortfallY = requested.y - allocated.height

        // Reported from INSIDE the layout system, which is the only place the
        // answer is not a guess. Measuring this from a screenshot was tried on
        // 2026-09-04 and abandoned: a GTK4 window on Windows carries an
        // invisible resize border that `GetWindowRect` includes and nothing
        // paints, so a ruler laid on the visible edge and a ruler laid on the
        // reported frame disagree by a number that itself has to be measured.
        // Task #78 reached the same conclusion for #160 and it holds here.
        //
        // Printed whatever the value, because "shortfall 0" is the result that
        // says the window got what it asked for, and a diagnostic that only
        // speaks when something is wrong cannot tell "fixed" from "not running".
        //
        // 由**版面系統內部**回報，那是唯一不需要猜測的地方。2026-09-04 曾嘗試從截圖量測並放棄：
        // Windows 上的 GTK4 視窗帶有一圈隱形的調整邊框，`GetWindowRect` 把它算進去而沒有任何東西
        // 去畫它，因此「量可見邊緣的尺」與「量回報框架的尺」會相差一個本身還得先被量出來的數字。
        // 任務 #78 對 #160 得到相同結論，此處亦然。
        //
        // **無論數值為何都輸出**，因為「shortfall 0」正是「視窗拿到了它所要求的」的結果——而一個只在
        // 出錯時才出聲的診斷，無法區分「已修好」與「根本沒有執行」。
        DebugFeatures.log(
            "content size: requested \(requested.x)x\(requested.y) "
                + "allocated \(allocated.width)x\(allocated.height) "
                + "shortfall \(shortfallX)x\(shortfallY)"
        )

        // Compare with the BEFORE line printed in `createWindow`: the same list
        // of the window's children, after mapping.
        // 與 `createWindow` 中輸出的那行 BEFORE 對照:同一份視窗子節點清單，只是在 map 之後。
        DebugFeatures.log(
            "decoration probe AFTER map: "
                + (window.childMeasurements.isEmpty
                    ? "no children"
                    : window.childMeasurements
                    .map { "\($0.typeName)=\($0.naturalHeight)" }
                    .joined(separator: " "))
        )

        // No correction here. `gtk_window_set_default_size` is a launch hint
        // once the window is realised -- `setSizeLimits` says the same of a size
        // request -- and this runs after mapping, because the allocation is not
        // real before then. Measured twice: a correction by the shortfall logged
        // "grew the window to 900x639" while the content stayed 900x561 at
        // +250 ms and +1500 ms (P16, 2026-09-04), and one by the window's own
        // 39 px header gave window 620x459 and content still 620x428
        // (2026-09-10). The allowance `createWindow` adds before present is
        // what works.
        //
        // Re-read later, because `updateWindow`, the only caller, is not called
        // again in an app that simply sits there (measured 2026-09-04, also with
        // `actions/win/P16-force-update.actions`). The later readings tell a
        // permanent shortfall -- an app given less than it asked for, for the
        // whole run -- from a transient of startup layout. On a timeout rather
        // than an idle callback, so the reading comes after GTK's own resize.
        //
        // 此處不做修正。視窗一旦 realise,`gtk_window_set_default_size` 就只是啟動提示——`setSizeLimits`
        // 對 size request 也這麼寫——而本方法在 map 之後才執行，因為配置在那之前並不真實。實測兩次：依差額
        // 修正時記錄了「grew the window to 900x639」,內容在 +250ms 與 +1500ms 仍停在 900x561(P16,
        // 2026-09-04);依視窗自己 39 px 的 header 修正時，視窗為 620x459,內容仍是 620x428(2026-09-10)。
        // 有效的是 `createWindow` 在 present 之前加上的那份額度。
        //
        // 稍後重讀，因為唯一的呼叫端 `updateWindow` 在一個就這麼放著的 app 中不會被再次呼叫(2026-09-04
        // 實測，連用 `actions/win/P16-force-update.actions` 也一樣)。稍後的讀數能分辨永久性的短少——app
        // 在整個執行期間都拿到比它所要求的更少——與啟動版面的暫態。使用 timeout 而非 idle callback,讓讀數
        // 落在 GTK 自身的 resize 之後。
        #if SCUI_DEBUG
            // Two delays: a timing artefact shows two DIFFERENT numbers, a
            // permanent shortfall the same number twice.
            //
            // 兩個延遲：時序造成的假象會顯示**兩個不同的**數字，永久性的短少則會把同一個數字印兩次。
            for delay in [250, 1500] {
                Self.runInMainThread(afterMilliseconds: delay) { [weak window] in
                    guard let window, let content = window.getChild() else { return }
                    let settled = content.allocatedSize
                    DebugFeatures.log(
                        "content size settled (+\(delay)ms): "
                            + "requested \(requested.x)x\(requested.y) "
                            + "allocated \(settled.width)x\(settled.height) "
                            + "shortfall \(requested.x - settled.width)x"
                            + "\(requested.y - settled.height)"
                    )
                }
            }
        #endif
    }

    public func updateWindow(_ window: Window, environment: EnvironmentValues) {
        reportContentSizeShortfall(of: window)

        // #386, the override half: honour preferredColorScheme by asking GTK for
        // the matching theme variant, so the widgets GTK draws itself (buttons,
        // entries, list rows) follow the app's request too, not just the text
        // SwiftCrossUI colours.
        //
        // Only when the app asks for something other than the ambient theme.
        // Setting it unconditionally feeds this backend's own detection back into GTK, and
        // the setting is global and sticky, so it would outlive the app: a run
        // that requested dark leaves the next run reporting dark under a light
        // theme, which is light text on a light background.
        //
        // The setting is per-display, not per-window -- GTK has no per-window
        // theme variant -- so two windows asking for opposite schemes cannot both
        // win. That is a real limitation of doing this on GTK, and one AppKit
        // avoids by having a per-window appearance. The common case, an app that
        // prefers one scheme, works.
        //
        // #386 的 override 部分：遵從 preferredColorScheme，向 GTK 要求對應的主題變體，使 GTK
        // 自行繪製的 widget（按鈕、輸入框、清單列）也跟隨 app 的要求，而不僅是 SwiftCrossUI 自行
        // 上色的文字。
        //
        // 僅在 app 要求了與環境主題不同的配色時才設定。無條件設定會把本 backend 自己的偵測回饋給 GTK，
        // 而該設定為全域且具黏性，其效果會比 app 存活更久：一次要求 dark 的執行，會使下一次在
        // light 主題下的執行回報 dark，結果是淺色文字畫在淺色背景上。
        //
        // 此設定為 per-display 而非 per-window（GTK 沒有 per-window 的主題變體），因此兩個要求
        // 相反配色的視窗無法同時如願。這是在 GTK 上實作的真實限制，AppKit 因具備 per-window
        // appearance 而無此問題。常見情境（整個 app 偏好單一配色）可正常運作。
        let requested = environment.colorScheme

        // Before the guard below, deliberately. On Windows a GTK window wears a
        // native Win32 title bar, which follows neither GTK's theme nor the
        // override underneath -- so it needs telling on every update, not only
        // on the updates where the app is asking for something other than the
        // ambient scheme. Skipping it there would leave the common case, an app
        // that simply follows the system, with a light bar over dark content.
        //
        // No API of its own, because SwiftUI has none: a window's chrome there
        // follows the app's colour scheme and there is nothing to call. The
        // return value is ignored for the same reason as in setLevel -- it is
        // false before the window is realized, and the next update is the retry.
        //
        // 刻意置於下方 guard 之前。在 Windows 上，GTK 視窗配戴的是原生 Win32 標題列，它既不跟隨
        // GTK 的主題、也不跟隨其下的 override——因此每次更新都必須告知它，而非僅在「app 要求了與
        // 環境不同的配色」的那些更新。若略過，最常見的情境（app 單純跟隨系統）就會得到淺色標題列
        // 配深色內容。
        //
        // 刻意不提供專屬 API，因為 SwiftUI 也沒有：在 SwiftUI 中視窗裝飾跟隨 app 的色彩配置，沒有
        // 任何東西可呼叫。回傳值被忽略的理由與 setLevel 相同——視窗完成 realize 之前它會是 false，
        // 而下一次更新即是重試。
        _ = scui_window_set_dark_titlebar(window.widgetPointer, requested == .dark ? 1 : 0)

        // Against what GTK is currently showing, not against the ambient scheme.
        //
        // Comparing with the ambient scheme was wrong in one direction only, and
        // that direction is a round trip. Measured 2026-08-27 on Windows with the
        // desktop in dark mode, driving actions/win/P15-colour-scheme.actions, which
        // presses Light and then Dark: the Light press differs from ambient, so
        // it writes `false` and GTK goes light; the Dark press equals ambient, so
        // the guard returns and nothing writes `true` back. GTK stays light while
        // the environment says dark, so SwiftCrossUI draws light text on it --
        // P15 ends up reporting `Requested: dark  Resolved: dark` over a window
        // that is almost entirely illegible.
        //
        // Tracking the write keeps the property the old guard was there for. An
        // app that never overrides still writes nothing after the startup sample,
        // so the "global and sticky, outlives the app" concern is unchanged; the
        // only new write is the one that returns GTK to where it started.
        //
        // 與「GTK 目前實際顯示的狀態」比較，而非與環境配色比較。
        //
        // 與環境配色比較只在單一方向上是錯的，而那個方向就是「來回切換」。2026-08-27 於 Windows、
        // 桌面為深色模式下實測，驅動 actions/win/P15-colour-scheme.actions（該檔先按 Light 再按 Dark）：
        // Light 那次與 ambient 不同，於是寫入 `false`，GTK 轉為淺色；Dark 那次與 ambient 相同，
        // guard 直接 return，沒有任何地方把 `true` 寫回去。GTK 停留在淺色，而 environment 說是深色，
        // 於是 SwiftCrossUI 在其上繪製淺色文字——P15 最後回報 `Requested: dark  Resolved: dark`，
        // 而視窗幾乎完全無法閱讀。
        //
        // 追蹤寫入值可保留舊 guard 所要維護的性質：從不覆寫配色的 app，在啟動取樣之後依然不會寫入
        // 任何東西，因此「全域且具黏性、效果比 app 存活更久」這項顧慮並未改變；唯一新增的寫入，
        // 正是那次「把 GTK 帶回它原本狀態」的寫入。
        let wantsDarkTheme = (requested == .dark)
        guard wantsDarkTheme != gtkPrefersDarkTheme else { return }
        Gtk.Settings.default?.preferDarkTheme = wantsDarkTheme
        gtkPrefersDarkTheme = wantsDarkTheme
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
        // FIXME: This doesn't seem to work on macOS at least
        window.deletable = closable

        // TODO: Figure out if there's some magic way to disable minimization
        //   in a framework where the minimize button usually doesn't even exist

        window.resizable = resizable
    }

    /// `.floating` only where the platform underneath GTK can provide it.
    ///
    /// GTK 4 removed `gtk_window_set_keep_above` and has no replacement, so the
    /// answer is never GTK's -- it is the platform's. On Windows a GTK window is
    /// an ordinary `HWND` and `SetWindowPos` works on it; on macOS it is an
    /// `NSWindow` in this process and its level is set (2026-10-16). Elsewhere it does not:
    /// Wayland forbids a client raising itself above another application by
    /// design, and while X11's `_NET_WM_STATE_ABOVE` would serve where a window
    /// manager implements it, WSLg's does not advertise it (measured
    /// 2026-08-26 -- see `scui_window_set_topmost` for the atom list and how to
    /// re-check).
    ///
    /// A property rather than a constant because it is genuinely not one: this
    /// same backend answers differently on two platforms.
    ///
    /// 僅在 GTK 底下的平台能夠提供時才支援 `.floating`。
    ///
    /// GTK 4 移除了 `gtk_window_set_keep_above` 且無替代品，因此答案從來不由 GTK 決定——而是由平台
    /// 決定。在 Windows 上，GTK 視窗底層就是普通的 `HWND`，`SetWindowPos` 對它有效。在其他平台則
    /// 不然：Wayland 依設計禁止 client 把自己抬到其他應用程式之上；而 X11 的 `_NET_WM_STATE_ABOVE`
    /// 雖然在窗口管理員有實作之處可用，WSLg 的並未宣告支援它（實測於 2026-08-26——atom 清單與重新
    /// 確認的方式見 `scui_window_set_topmost`）。
    ///
    /// 採用 property 而非常數，是因為它確實不是常數：同一個 backend 在兩個平台上的答案並不相同。
    public var supportedWindowLevels: [WindowLevel] {
        #if os(Windows) || os(macOS)
            [.automatic, .normal, .floating]
        #else
            // `.floating` where the window manager implements it (X11 with
            // _NET_WM_STATE_ABOVE); see scui_window_topmost_supported.
            // 視窗管理員有實作時才提供 `.floating`(X11 且有 _NET_WM_STATE_ABOVE);見 scui_window_topmost_supported。
            // Or under WSL, done on the Windows side; see GtkWSLTopmost.
            // 或在 WSL 下，從 Windows 那一側完成；見 GtkWSLTopmost。
            scui_window_topmost_supported() != 0 || GtkWSLTopmost.isAvailable
                ? [.automatic, .normal, .floating] : [.automatic, .normal]
        #endif
    }

    public func setLevel(ofWindow window: Window, to level: WindowLevel) {
        // Only `.floating` needs anything done, and only the platforms that
        // listed it above get here with it. The caller applies the level after
        // the window is shown, when the platform handle exists.
        let done = scui_window_set_topmost(window.widgetPointer, level == .floating ? 1 : 0) != 0
        #if os(Linux)
            // No window manager support under WSLg; Windows does it instead.
            // WSLg 下視窗管理員不支援，改由 Windows 完成。
            if !done {
                GtkWSLTopmost.set(window.widgetPointer, topmost: level == .floating)
            }
        #else
            _ = done
        #endif
    }

    public func setChild(ofWindow window: Window, to child: Widget) {
        let container = wrapInCustomRootContainer(child)
        window.setChild(container)
    }

    private func menubarHeight(ofWindow window: Window) -> Int {
        #if os(macOS)
            return 0
        #else
            if window.showMenuBar {
                // Hardcoded, because there is nothing to measure when this is
                // asked: `menubarHeight` is called once per run, from
                // `setSize(ofWindow:)` during initial sizing, before GTK has
                // built the bar -- a depth-first walk from the ApplicationWindow
                // found only `GtkCustomRootWidget` and three `GtkPassthroughFixed`
                // (Windows/GTK 4.22.4, P20 with an application menu, 2026-08-27).
                // Measuring would mean re-running the sizing after the bar
                // appears, a change to when this is computed rather than to how.
                //
                // The bar drew 23 pt of strip plus a 1 pt rule, sampled down a
                // text-free column of the capture, so 25 is one or two points too
                // tall under that theme, and the window that much too tall with
                // the content offset to match.
                //
                // 寫死，因為在被詢問的時刻沒有東西可以量測:`menubarHeight` 每次執行只會被呼叫一次，來自初始尺寸
                // 設定時的 `setSize(ofWindow:)`,早於 GTK 建立選單列——自 ApplicationWindow 進行深度優先走訪，只找到
                // `GtkCustomRootWidget` 與三個 `GtkPassthroughFixed`(Windows/GTK 4.22.4,帶應用程式選單的 P20,
                // 2026-08-27)。要量測就得在選單列出現之後重新執行尺寸計算，那是改變「何時計算」，而非改變「如何計算」。
                //
                // 該列畫出 23 pt 的橫條加上 1 pt 的分隔線(取樣自截圖中一條沒有文字的直線)。因此在該主題下,25 高了
                // 一到兩點，視窗也就高了那麼多，內容隨之偏移。
                25
            } else {
                0
            }
        #endif
    }

    public func size(ofWindow window: Window) -> SIMD2<Int> {
        let child = window.getChild() as! CustomRootWidget
        let size = child.getSize()
        return SIMD2(size.width, size.height)
    }

    public func isWindowProgrammaticallyResizable(_ window: Window) -> Bool {
        // A fullscreen window must answer false, or the layout system keeps
        // proposing sizes the compositor will not grant and the two fight.
        // AppKitBackend answers `!window.styleMask.contains(.fullScreen)` and
        // WinUIBackend checks its presenter kind, for the same reason.
        //
        // 全螢幕視窗必須回答 false，否則版面系統會不斷提出合成器不會允許的尺寸，兩者互相拉扯。
        // AppKitBackend 基於相同理由回傳 `!window.styleMask.contains(.fullScreen)`,WinUIBackend 則檢查其
        // presenter 的種類。
        return !window.isFullscreen
    }

    public func setSize(ofWindow window: Window, to newSize: SIMD2<Int>) {
        let child = window.getChild() as! CustomRootWidget
        // The titlebar is chrome INSIDE the window that eats content height,
        // exactly like the menu bar beside it. This is the second place the
        // requested CONTENT size is turned into a WINDOW size, after
        // `createWindow`; without the titlebar here, `setSize` would write the
        // unadjusted request back and the content would come out short by the
        // header's height (553 for 600 with a 47 px titlebar, 2026-09-04).
        //
        // The window's own header is preferred once it has one. The standalone
        // probe bar reports 47 whether realized or not, inside a window or not,
        // while the same `gtk_widget_measure` against the window's own header
        // returns 39 (2026-09-10): the number depends on the header being that
        // window's. A window that owns a titlebar -- under the probe, or a
        // toolbar's -- measures that titlebar first.
        //
        // titlebar 是**視窗內部**會吃掉內容高度的裝飾，與它旁邊的 menu bar 完全同類。這是繼 `createWindow` 之後，
        // 「把所要求的**內容**尺寸換算成**視窗**尺寸」的第二個地點；此處若不加上 titlebar,`setSize` 會把未經
        // 調整的請求寫回去，內容就會短少 header 的高度(titlebar 為 47 px 時,600 只剩 553,2026-09-04)。
        //
        // **一旦視窗有了自己的 header,就優先採用它。** 獨立的探針 bar 無論是否 realize、是否置於視窗之內都回報
        // 47,而同一個 `gtk_widget_measure` 對**視窗自己的** header 呼叫則回傳 39(2026-09-10):這個數字取決於
        // 那條 header 屬於那個視窗。擁有 titlebar 的視窗——在探針之下，或 toolbar 的那條——優先量它。
        let liveHeaderHeight = window.childMeasurements
            .first { $0.typeName == "GtkHeaderBar" }?
            .naturalHeight
        // The last resort is `.gtkOwnDecoration` rather than `.bare`: a header
        // bar built here measures 47 and the window's own lays out at 39, while
        // GTK's own decoration measured on a throwaway realized window agrees
        // with the live reading.
        // 最後的退路用 `.gtkOwnDecoration` 而非 `.bare`:在此處建立的 header bar 量得 47,而視窗自己的那條排版成
        // 39;在一個用完即棄、realize 過的視窗上量測 **GTK 自己的**裝飾，則與實際讀數一致。
        let titlebarHeight =
            window.titlebarNaturalHeight
                ?? liveHeaderHeight
                ?? Gtk.Window.probeHeaderBarHeight(.gtkOwnDecoration)
                ?? 0
        let previousSize = child.getSize()
        window.size = Size(
            width: newSize.x,
            height: newSize.y + menubarHeight(ofWindow: window) + titlebarHeight
        )
        child.preemptAllocatedSize(allocatedWidth: newSize.x, allocatedHeight: newSize.y)
        // A smaller size has to be applied by hand on Windows, where GDK grows a
        // mapped window to a new default size but never shrinks it (see
        // `Window.applyDefaultSizeNow`). Measured 2026-10-21 with P95 grow mode:
        // the core clamped the window to 360 every time its content went back
        // to 360, and the window stayed 720 wide with the content in its left half.
        // 在 Windows 上，較小的尺寸必須手動套用:GDK 會把已顯示的視窗長到新的 default size,卻永遠不會把它縮小
        // (見 `Window.applyDefaultSizeNow`)。2026-10-21 以 P95 成長模式實測：內容每次回到 360,核心都把視窗夾到
        // 360,而視窗始終維持 720 寬，內容擠在左半邊。
        #if os(Windows)
            if newSize.x < previousSize.width || newSize.y < previousSize.height {
                window.applyDefaultSizeNow()
            }
        #endif
    }

    public func setSizeLimits(
        ofWindow window: Window,
        minimum minimumSize: SIMD2<Int>,
        maximum maximumSize: SIMD2<Int>?
    ) {
        window.setMinimumSize(to: Size(width: minimumSize.x, height: minimumSize.y))

        // A size request on the toplevel is only honoured as a launch hint; once
        // the window is realised GTK lets the user drag it below that, and the
        // content is clipped. What GTK does keep enforcing is the *child's*
        // measured minimum, so the enforced minimum has to live on the custom
        // root widget too -- and because this runs on every window update, it
        // tracks the content as it grows (the #289 case: taller content did not
        // raise the floor, so the window shrank into it).
        let root = window.getChild() as! CustomRootWidget
        root.setMinimumSize(minimumWidth: minimumSize.x, minimumHeight: minimumSize.y)

        // NB: GTK does not support setting maximum sizes for widgets. It just doesn't.
        // https://discourse.gnome.org/t/how-to-build-fixed-size-windows-in-gtk-4/22807/10
        if maximumSize != nil {
            debugLogOnce("GTK does not support setting maximum window sizes")
        }
    }

    public func setResizeHandler(
        ofWindow window: Window,
        to action: @escaping (_ newSize: SIMD2<Int>) -> Void
    ) {
        let child = window.getChild() as! CustomRootWidget
        child.setResizeHandler { size in
            self.runInMainThread {
                action(SIMD2(size.width, size.height))
            }
        }
    }

    /// Ctrl-Q quits, which is the GTK convention and issue #478.
    ///
    /// On macOS Cmd-Q comes free with AppKit's standard application menu; GTK
    /// has no equivalent, so without this an app built on this backend has no
    /// quit shortcut.
    ///
    /// A `GAction` plus an accelerator rather than a key controller on each
    /// window: an accelerator is application-wide, so it works whichever window
    /// has focus and keeps working for windows created later.
    ///
    /// `g_application_quit` rather than closing windows one by one. Closing them
    /// runs each close handler, and an app that vetoes a close would refuse the
    /// shortcut -- which is the behaviour of a close request, not of a quit.
    ///
    /// Ctrl-Q 結束程式，這是 GTK 的慣例，也是 issue #478。
    ///
    /// 在 macOS 上，Cmd-Q 隨 AppKit 的標準應用程式選單而來；GTK 沒有對應機制，因此少了這一步，以此
    /// backend 建置的 app 就沒有結束捷徑。
    ///
    /// 使用 `GAction` 加上加速鍵，而非在每個視窗掛上 key controller：加速鍵是應用程式層級的，因此
    /// 無論哪個視窗取得焦點都有效，對日後才建立的視窗亦然。
    ///
    /// 使用 `g_application_quit` 而非逐一關閉視窗。逐一關閉會執行每個 close handler，而會否決關閉
    /// 的 app 將因此拒絕此捷徑——那是「關閉請求」的行為，不是「結束程式」的行為。
    private func installQuitShortcut() {
        let action = GSimpleAction(name: "quit") { [weak self] in
            self?.gtkApp.quit()
        }
        gtkApp.addAction(action)
        quitAction = action
        gtkApp.setAccelerators([Self.isDarwin ? "<Meta>q" : "<Control>q"], forAction: "app.quit")
    }

    public func show(window: Window) {
        // present(), not show(). `Widget.show()` is gtk_widget_set_visible,
        // which maps the window without raising it or giving it focus; GTK 4
        // documents gtk_window_present as the way to show a window, and on
        // Windows it is what makes it the foreground window.
        //
        // Observed with set_visible: the window appeared but never became
        // foreground, so AppActivate could not raise it and screenshots of the
        // "whole desktop" photographed whatever was in front instead. Worse, a
        // GtkDropDown's popover opened from an unfocused window read as a
        // detached window that would not come forward and did not dismiss on
        // selection.
        //
        // 使用 present() 而非 show()。`Widget.show()` 實為 gtk_widget_set_visible，它只會把視窗
        // map 出來，不會將其提到最上層、也不會給予焦點；GTK 4 明確以 gtk_window_present 作為
        // 顯示視窗的方式，而在 Windows 上它正是使視窗成為前景視窗的呼叫。
        //
        // 使用 set_visible 時的實際觀察：視窗會出現但從未成為前景，因此 AppActivate 無法喚起
        // 它，而「整個桌面」的截圖只會拍到當時位於前方的其他內容。更嚴重的是，從一個未取得焦點
        // 的視窗開啟的 GtkDropDown popover，表現為一個無法被帶到前面、且選取後不會關閉的
        // 分離視窗。
        window.present()
        #if os(macOS)
            // After present(), when the NSWindow exists. See GtkBackend+ColourSpace.swift.
            // 在 present() 之後，此時 NSWindow 已存在。見 GtkBackend+ColourSpace.swift。
            tagColourSpace(ofWindow: window)
        #endif
        #if SCUI_DEBUG
            // GTK's own scale, not the display's. `gtk_widget_get_scale_factor` is
            // an integer by design -- it is the buffer scale GTK rendered at -- and
            // on Windows that is what makes it disagree with `GetDpiForWindow`: at
            // 125% Windows reports 1.25 and GTK laid out at 1. Handing the number
            // over here is what makes an action file mean the same thing at every
            // display scale. See InputEvent's WindowGeometry.scale.
            //
            // 傳的是 GTK 自己的比例，而非顯示器的。`gtk_widget_get_scale_factor` 依設計即為整數——它
            // 是 GTK 實際繪製時所用的 buffer scale——而在 Windows 上，這正是它與 `GetDpiForWindow`
            // 產生分歧之處：125% 時 Windows 回報 1.25，GTK 卻是以 1 排版。在此把這個數字交出去，才
            // 使得一個動作檔在任何顯示縮放下都代表同一件事。詳見 InputEvent 的 WindowGeometry.scale。
            // `taplabel`: the first mapped GtkLabel or GtkButton with that text, as the
            // middle of it in the surface -- the widget's bounds in the window plus the
            // surface transform, which is where client-side decoration puts the
            // window inside its surface. Asked from the replay thread, answered on
            // the GTK thread.
            // `taplabel`:第一個已 map、文字相同的 GtkLabel 或 GtkButton,以它在 surface 中的中心表示——即 widget 在視窗內的
            // 邊界加上 surface transform(client-side decoration 把視窗放在 surface 裡的位置)。由重放執行緒詢問、在 GTK 執行緒回答。
            nonisolated(unsafe) let root = window.widgetPointer
            ActionFileReplay.locateLabel = { [weak self] label in
                guard let self else { return nil }
                let done = DispatchSemaphore(value: 0)
                nonisolated(unsafe) var place: (x: Double, y: Double)?
                self.runInMainThread {
                    defer { done.signal() }
                    func find(_ widget: UnsafeMutablePointer<GtkWidget>)
                        -> UnsafeMutablePointer<GtkWidget>?
                    {
                        guard gtk_widget_get_mapped(widget) != 0 else { return nil }
                        let instance = UnsafeMutableRawPointer(widget)
                            .assumingMemoryBound(to: GTypeInstance.self)
                        if g_type_check_instance_is_a(instance, gtk_label_get_type()) != 0,
                           let text = gtk_label_get_text(OpaquePointer(widget)),
                           String(cString: text) == label
                        {
                            return widget
                        }
                        if g_type_check_instance_is_a(instance, gtk_button_get_type()) != 0,
                           let text = gtk_button_get_label(
                               UnsafeMutableRawPointer(widget)
                                   .assumingMemoryBound(to: GtkButton.self)
                           ),
                           String(cString: text) == label
                        {
                            return widget
                        }
                        var child = gtk_widget_get_first_child(widget)
                        while let current = child {
                            if let found = find(current) { return found }
                            child = gtk_widget_get_next_sibling(current)
                        }
                        return nil
                    }
                    // The active toplevel, as AppKit's locator takes the key window: a
                    // sheet or cover is a window of its own, and searching the first
                    // window only failed `taplabel Close` on P49's cover (2026-10-20).
                    // 作用中的頂層視窗，如同 AppKit 的定位器取 key window:sheet 或 cover 是自己的視窗，只搜第一個視窗會讓 P49
                    // cover 上的 `taplabel Close` 失敗(2026-10-20)。
                    let target = Self.activeToplevel(or: root)
                    guard let found = find(target) else { return }
                    var bounds = graphene_rect_t()
                    guard gtk_widget_compute_bounds(found, target, &bounds) != 0 else { return }
                    var offsetX = 0.0
                    var offsetY = 0.0
                    gtk_native_get_surface_transform(OpaquePointer(target), &offsetX, &offsetY)
                    place = (
                        x: Double(bounds.origin.x + bounds.size.width / 2) + offsetX,
                        y: Double(bounds.origin.y + bounds.size.height / 2) + offsetY
                    )
                }
                done.wait()
                return place
            }
            #if os(Linux)
                // Where the content starts below a title bar GTK draws itself. WSL
                // runs use X11 with GTK_CSD=1 (test_common.zsh), and action files
                // were written against the content; see
                // ActionFileReplay.clientContentOffset. A window with a custom
                // titlebar (a toolbar's GtkHeaderBar) was client-side decorated
                // before GTK_CSD=1 too, and its files were measured with the bar
                // inside, so it reports no offset.
                // GTK 自己畫的標題列之下，內容從哪裡開始。WSL 執行以 X11 加 GTK_CSD=1 啟動(test_common.zsh),而動作檔是對內容量的；
                // 見 ActionFileReplay.clientContentOffset。自訂 titlebar 的視窗(工具列的 GtkHeaderBar)在 GTK_CSD=1 之前就已是
                // client-side decoration,它的檔案量測時就把標題列算在內，所以回報零位移。
                ActionFileReplay.clientContentOffset = { [weak self] in
                    guard let self else { return (x: 0, y: 0) }
                    let done = DispatchSemaphore(value: 0)
                    nonisolated(unsafe) var offset = (x: 0.0, y: 0.0)
                    self.runInMainThread {
                        defer { done.signal() }
                        let target = Self.activeToplevel(or: root)
                        let window = UnsafeMutableRawPointer(target)
                            .assumingMemoryBound(to: GtkWindow.self)
                        guard gtk_window_get_titlebar(window) == nil,
                            let child = gtk_window_get_child(window)
                        else { return }
                        var bounds = graphene_rect_t()
                        guard gtk_widget_compute_bounds(child, target, &bounds) != 0 else { return }
                        var surfaceX = 0.0
                        var surfaceY = 0.0
                        gtk_native_get_surface_transform(OpaquePointer(target), &surfaceX, &surfaceY)
                        offset = (
                            x: Double(bounds.origin.x) + surfaceX,
                            y: Double(bounds.origin.y) + surfaceY
                        )
                    }
                    done.wait()
                    return offset
                }
            #endif
            ActionFileReplay.replayIfRequested(
                layoutScale: Double(gtk_widget_get_scale_factor(window.widgetPointer))
            )
        #endif
    }

    #if SCUI_DEBUG
        /// The active, mapped toplevel, or `fallback` when none is: a sheet or
        /// cover is a window of its own, so an action file aims at whichever one
        /// has the focus. Shared by the `taplabel` locator and the client content
        /// offset in `show(window:)`; call it on the GTK thread.
        /// 作用中、已 map 的頂層視窗；沒有時傳回 `fallback`。sheet 或 cover 是自己的視窗，所以動作檔瞄準的是擁有焦點的
        /// 那一個。由 `show(window:)` 裡的 `taplabel` 定位器與 client 內容位移共用；請在 GTK 執行緒呼叫。
        static func activeToplevel(
            or fallback: UnsafeMutablePointer<GtkWidget>
        ) -> UnsafeMutablePointer<GtkWidget> {
            var target = fallback
            if let list = gtk_window_list_toplevels() {
                var node: UnsafeMutablePointer<GList>? = list
                while let current = node {
                    if let data = current.pointee.data {
                        let candidate = data.assumingMemoryBound(to: GtkWindow.self)
                        let widget = data.assumingMemoryBound(to: GtkWidget.self)
                        if gtk_window_is_active(candidate) != 0, gtk_widget_get_mapped(widget) != 0 {
                            target = widget
                        }
                    }
                    node = current.pointee.next
                }
                g_list_free(list)
            }
            return target
        }
    #endif

    public func activate(window: Window) {
        window.present()
    }

    public func close(window: Window) {
        window.close()
    }

    public func setCloseHandler(
        ofWindow window: Window,
        to action: @escaping () -> Void
    ) {
        window.onCloseRequest = { _ in
            action()
            window.destroy()
        }
    }

    public func openExternalURL(_ url: URL) throws {
        // Used instead of gtk_uri_launcher_launch to maintain <4.10 compatibility
        gtk_show_uri(nil, url.absoluteString, guint(GDK_CURRENT_TIME))
    }

    public func revealFile(_ url: URL) throws {
        var success = false

        #if !os(Windows)
            let fileURI = url.absoluteString.replacingOccurrences(
                of: ",",
                with: "\\,"
            )
            let process = Process()
            process.arguments = [
                "dbus-send",
                "--print-reply",
                "--dest=org.freedesktop.FileManager1",
                "/org/freedesktop/FileManager1",
                "org.freedesktop.FileManager1.ShowItems",
                "array:string:\(fileURI)",
                "string:",
            ]
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")

            do {
                try process.run()
                process.waitUntilExit()

                success = process.terminationStatus == 0
            } catch {

            }
        #endif

        if !success {
            // Fall back to opening the parent directory without highlighting
            // the file.
            try openExternalURL(url.deletingLastPathComponent())
        }
    }

    /// Binds a ``KeyboardShortcut`` to a GAction, if there is one.
    ///
    /// `gtk_application_set_accels_for_action` is already how this backend gives
    /// Ctrl+Q to `app.quit` (see `setUpQuitAction`), so the mechanism is one this
    /// tree has run rather than one read from a header.
    ///
    /// 若有快捷鍵,就把一個 ``KeyboardShortcut`` 綁到某個 GAction 上。
    ///
    /// 本 backend 把 Ctrl+Q 給 `app.quit` 用的正是 `gtk_application_set_accels_for_action`
    /// (見 `setUpQuitAction`),因此這個機制是這棵樹**跑過**的,不是從標頭讀來的。
    private func applyShortcut(_ shortcut: KeyboardShortcut?, toAction action: String) {
        // Cleared when the item has none. Action names are positions ("<prefix>_<i>"), so a
        // rebuilt menu hands a name to another item, and the accelerator set for the old one
        // stayed on it: in P92's `before` mode the menu is built twice at launch, and
        // BEFORE-saveItem, now where Close had been, showed Close's Command-W (2026-10-20).
        // 項目沒有快捷鍵時清空。action 名稱是位置(「<前綴>_<i>」),選單重建時同一個名稱會交給另一個項目，而為舊項目設的快捷鍵
        // 會留在上面:P92 的 `before` 模式在啟動時建了兩次選單，排到 Close 原本位置的 BEFORE-saveItem 顯示了 Close 的 Command-W。
        guard let shortcut else {
            gtkApp.setAccelerators([], forAction: action)
            return
        }
        guard let accelerator = Self.gtkAccelerator(for: shortcut) else {
            // Loud rather than silent: an unbindable shortcut is a menu item
            // that looks configured and does nothing when the key is pressed.
            // 說出來而不是沉默:一個綁不上去的快捷鍵,會是一個「看起來設定好了、按下去卻毫無反應」
            // 的 menu item。
            debugLogOnce(
                "no GTK accelerator for keyboard shortcut '\(shortcut.key.character)'"
                    + " with modifiers \(shortcut.modifiers.rawValue); \(action) has no shortcut"
            )
            gtkApp.setAccelerators([], forAction: action)
            return
        }
        gtkApp.setAccelerators([accelerator], forAction: action)
    }

    /// A ``KeyboardShortcut`` in the syntax `gtk_accelerator_parse` accepts.
    ///
    /// **`.command` becomes Control, except on macOS, where it is Meta.** SwiftUI's default modifier is `.command`
    /// because it was written for macOS; on GTK there is no Command key, and the
    /// key that plays its role is Control. ``EventModifiers/command`` documents
    /// the same mapping, so a shortcut written against SwiftUI's names means
    /// here what a user of this platform would expect.
    ///
    /// **`capsLock` and `numericPad` are dropped, and that is not a gap.** They
    /// are not accelerator modifiers in GTK, X11 or Win32 -- they are keyboard
    /// STATES. There is nothing to map them to and nothing is lost by ignoring
    /// them; a shortcut carrying one still binds on its real modifiers.
    ///
    /// 以 `gtk_accelerator_parse` 所接受的語法表示的 ``KeyboardShortcut``。
    ///
    /// **`.command` 會變成 Control。** SwiftUI 的預設修飾鍵是 `.command`,因為它是為 macOS 寫的;
    /// GTK 上沒有 Command 鍵,而扮演其角色的是 Control。``EventModifiers/command`` 記載的是同一個
    /// 對應,因此照 SwiftUI 名稱所寫的快捷鍵,在此處的意義正是本平台使用者所預期的。
    ///
    /// **`capsLock` 與 `numericPad` 會被丟棄,而那不是一個缺口。** 它們在 GTK、X11 或 Win32 中都
    /// **不是**加速鍵的修飾鍵——它們是鍵盤**狀態**。沒有東西可以對應過去,忽略它們也不會失去任何東西;
    /// 一個帶著它們的快捷鍵,仍會以它真正的修飾鍵綁定。
    static func gtkAccelerator(for shortcut: KeyboardShortcut) -> String? {
        guard let key = gtkKeyName(for: shortcut.key) else { return nil }

        var prefix = ""
        // On macOS the Command key exists and GTK calls it Meta. Control there drew ^Q in the
        // menu and left Command-Q, and every `.command` shortcut, doing nothing (P71, 2026-10-14).
        // macOS 上有 Command 鍵，GTK 稱它為 Meta。在那裡用 Control,選單畫的是 ^Q,而 Command-Q 與每個 `.command`
        // 快捷鍵都沒有作用(P71,2026-10-14)。
        #if canImport(Darwin)
            if shortcut.modifiers.contains(.command) { prefix += "<Meta>" }
            if shortcut.modifiers.contains(.control) { prefix += "<Control>" }
        #else
            if shortcut.modifiers.contains(.control) || shortcut.modifiers.contains(.command) {
                prefix += "<Control>"
            }
        #endif
        if shortcut.modifiers.contains(.shift) { prefix += "<Shift>" }
        if shortcut.modifiers.contains(.option) { prefix += "<Alt>" }
        return prefix + key
    }

    /// The GDK key name for a ``KeyEquivalent``.
    ///
    /// **The named keys are matched on their SCALAR, not by comparing against
    /// `KeyEquivalent.escape` and friends.** Those constants are built from
    /// specific scalars -- `escape` is U+001B, `delete` is U+007F, the arrows
    /// are in the U+F700 private-use block that SwiftUI uses -- and matching the
    /// scalar means a `KeyEquivalent("\u{1B}")` written by hand maps the same
    /// way as `.escape`, which a `==` against the constant would also do but
    /// less obviously.
    ///
    /// `delete` being U+007F and NOT U+0008 matters here: this returns GDK's
    /// `Delete` (forward delete) for it, and `BackSpace` is a different key that
    /// ``KeyEquivalent`` has no constant for. The type's own documentation warns
    /// about the same conflation, which is why it is honoured rather than
    /// quietly "corrected" to BackSpace because macOS labels that key delete.
    ///
    /// ``KeyEquivalent`` 所對應的 GDK 鍵名。
    ///
    /// **具名的鍵是以其 scalar 比對的,而不是拿去和 `KeyEquivalent.escape` 之類的常數相比。**
    /// 那些常數本身就是由特定 scalar 建成的——`escape` 是 U+001B、`delete` 是 U+007F、方向鍵位於
    /// SwiftUI 所使用的 U+F700 私有使用區——而比對 scalar 意謂著手寫的 `KeyEquivalent("\u{1B}")`
    /// 與 `.escape` 對應到同一個地方。
    ///
    /// `delete` 是 U+007F 而**不是** U+0008,這件事在此處是有意義的:此處為它回傳 GDK 的 `Delete`
    /// (向前刪除),而 `BackSpace` 是另一個鍵、``KeyEquivalent`` 並沒有對應的常數。該型別自己的文件
    /// 就在警告同一種混淆,這正是此處遵守它、而不是因為「macOS 把那個鍵標示為 delete」就悄悄把它
    /// 「修正」成 BackSpace 的原因。
    private static func gtkKeyName(for key: KeyEquivalent) -> String? {
        let scalars = Array(key.character.unicodeScalars)
        guard scalars.count == 1, let scalar = scalars.first else {
            // A grapheme cluster of more than one scalar has no single key.
            // 由多個 scalar 組成的字素叢集,沒有單一的鍵可以對應。
            return nil
        }

        switch scalar {
            case "\u{F700}": return "Up"
            case "\u{F701}": return "Down"
            case "\u{F702}": return "Left"
            case "\u{F703}": return "Right"
            case "\u{1B}": return "Escape"
            case "\u{7F}": return "Delete"
            case "\u{F728}": return "Delete"
            case "\u{F729}": return "Home"
            case "\u{F72B}": return "End"
            case "\u{F72C}": return "Page_Up"
            case "\u{F72D}": return "Page_Down"
            case "\u{F739}": return "Clear"
            case "\u{9}": return "Tab"
            case " ": return "space"
            case "\r": return "Return"
            default: break
        }

        // Anything else has to be a printable character GTK can name directly.
        // The private-use block is checked explicitly: an unmapped F7xx scalar
        // would otherwise be handed to GTK as a literal character, and
        // `gtk_accelerator_parse` accepts it -- binding the shortcut to a key
        // that does not exist, which is a silent failure rather than a refusal.
        // 其餘的必須是 GTK 能直接命名的可列印字元。此處明確檢查私有使用區:否則一個未對應的 F7xx
        // scalar 會被當成字面字元交給 GTK,而 `gtk_accelerator_parse` **會接受它**——把快捷鍵綁到一個
        // 不存在的鍵上,那是一次沉默的失敗,而不是一次拒絕。
        guard scalar.value >= 0x20, !(0xF700...0xF8FF).contains(scalar.value) else { return nil }
        // A letter or digit is its own name. Punctuation is not: `gtk_accelerator_parse`
        // reads "<Meta>?" as malformed ("Unable to parse accelerator", Gtk-CRITICAL) and
        // installs nothing, so the Help item's Command-? did not exist on GtkBackend
        // (P92 on macOS, 2026-10-20). GDK's own name for the key is used instead:
        // `question`, `comma`, `slash`.
        // 字母與數字的名稱就是它自己。標點不是:`gtk_accelerator_parse` 把「<Meta>?」視為格式錯誤(Gtk-CRITICAL)
        // 而什麼都不安裝，於是 Help 項目的 Command-? 在 GtkBackend 上不存在(macOS 上的 P92,2026-10-20)。改用 GDK 自己的按鍵名稱。
        if let character = Character(scalar).asciiValue, !Character(scalar).isLetter, !Character(scalar).isNumber,
            let name = gdk_keyval_name(gdk_unicode_to_keyval(UInt32(character)))
        {
            return String(cString: name)
        }
        return String(scalar)
    }

    private func renderMenu(
        _ menu: ResolvedMenu,
        actionMap: any GActionMap,
        actionNamespace: String,
        actionPrefix: String?,
        environment: EnvironmentValues
    ) -> GMenu {
        var currentSection = GMenu()
        var previousSections: [GMenu] = []

        for (i, item) in menu.items.enumerated() {
            let actionName =
                if let actionPrefix {
                    "\(actionPrefix)_\(i)"
                } else {
                    "\(i)"
                }

            render(item: item, environment: environment)
            func render(item: ResolvedMenu.Item, environment: EnvironmentValues) {
                switch item {
                    case .button(let label, let action):
                        if let action {
                            let gAction = GSimpleAction(name: actionName, action: action)
                            gAction.enabled = environment.isEnabled
                            actionMap.addAction(gAction)
                        }

                        // The shortcut arrives in the environment, on the same
                        // line as `isEnabled` and for the same reason -- see
                        // `EnvironmentValues.keyboardShortcut`.
                        // 快捷鍵是從 environment 來的,與 `isEnabled` 在同一行、基於同一個理由——
                        // 見 `EnvironmentValues.keyboardShortcut`。
                        applyShortcut(
                            environment.keyboardShortcut,
                            toAction: "\(actionNamespace).\(actionName)"
                        )

                        currentSection.appendItem(
                            label: label,
                            actionName: "\(actionNamespace).\(actionName)"
                        )
                    case .toggle(let label, let value, let onChange):
                        let gAction = GSimpleAction(
                            name: actionName,
                            state: value,
                            action: onChange
                        )
                        gAction.enabled = environment.isEnabled
                        actionMap.addAction(gAction)

                        applyShortcut(
                            environment.keyboardShortcut,
                            toAction: "\(actionNamespace).\(actionName)"
                        )

                        currentSection.appendItem(
                            label: label,
                            actionName: "\(actionNamespace).\(actionName)"
                        )
                    case .separator:
                        // GTK[3] doesn't have explicit separators per se, but instead deals with
                        // sections (actually quite similar to what you can do in SwiftUI with the
                        // Section view). It'll automatically draw separators between sections.
                        previousSections.append(currentSection)
                        currentSection = GMenu()
                    case .submenu(let submenu):
                        currentSection.appendSubmenu(
                            label: submenu.label,
                            content: renderMenu(
                                submenu.content,
                                actionMap: actionMap,
                                actionNamespace: actionNamespace,
                                actionPrefix: actionName,
                                environment: environment
                            )
                        )
                    case .modifiedEnvironment(let item, let modification):
                        render(item: item, environment: modification(environment))
                }
            }
        }

        if previousSections.isEmpty {
            // There are no dividers; just return the current section to keep the menu tree flat.
            return currentSection
        } else {
            let model = GMenu()
            for section in previousSections + [currentSection] {
                model.appendSection(label: nil, content: section)
            }
            return model
        }
    }

    private func renderMenuBar(
        _ submenus: [ResolvedMenu.Submenu],
        environment: EnvironmentValues
    ) -> GMenu {
        let model = GMenu()
        for (i, submenu) in submenus.enumerated() {
            model.appendSubmenu(
                label: submenu.label,
                content: renderMenu(
                    submenu.content,
                    actionMap: gtkApp,
                    actionNamespace: "app",
                    actionPrefix: "\(i)",
                    environment: environment
                )
            )
        }

        return model
    }

    public func setApplicationMenu(
        _ submenus: [ResolvedMenu.Submenu],
        environment: EnvironmentValues
    ) {
        let model = renderMenuBar(submenus, environment: environment)
        gtkApp.menuBarModel = model
        // `SCUI_DEBUG_MENU_DUMP=1`: the menu bar model as GTK holds it, read back
        // through GMenuModel in the form of `CommandLayout.textDescription`, so P92
        // can compare it with the layout the framework made. Sections are where the
        // separators went (renderMenu), so a section boundary is printed as `---`.
        // `SCUI_DEBUG_MENU_DUMP=1`:經由 GMenuModel 讀回 GTK 持有的選單列模型，以 `CommandLayout.textDescription`
        // 的格式印出，讓 P92 與框架產生的 layout 比對。分隔線在 renderMenu 裡變成 section,因此 section 邊界印成 `---`。
        if ProcessInfo.processInfo.environment["SCUI_DEBUG_MENU_DUMP"] == "1" {
            var lines: [String] = []
            func describe(_ menu: UnsafeMutablePointer<GMenuModel>, _ depth: Int) {
                let pad = String(repeating: "  ", count: depth)
                var firstSection = true
                for index in 0..<g_menu_model_get_n_items(menu) {
                    var label = "?"
                    if let value = g_menu_model_get_item_attribute_value(menu, index, "label", nil) {
                        label = String(cString: g_variant_get_string(value, nil))
                        g_variant_unref(value)
                    }
                    if let section = g_menu_model_get_item_link(menu, index, "section") {
                        if !firstSection { lines.append(pad + "---") }
                        firstSection = false
                        describe(section, depth)
                        g_object_unref(UnsafeMutableRawPointer(section))
                    } else if let submenu = g_menu_model_get_item_link(menu, index, "submenu") {
                        lines.append(pad + label)
                        describe(submenu, depth + 1)
                        g_object_unref(UnsafeMutableRawPointer(submenu))
                    } else {
                        lines.append(pad + label)
                    }
                }
            }
            describe(UnsafeMutablePointer(model.pointer), 0)
            FileHandle.standardError.write(
                Data(("menu-dump begin\n" + lines.joined(separator: "\n") + "\nmenu-dump end\n").utf8))
        }
        #if canImport(Darwin)
            // The framework names the application menu after the process and puts it first.
            // Now if the bar is already up, and once more when the loop runs: before start-up
            // GTK has not built the bar yet.
            // 框架以行程名稱命名 app 選單並放在第一個。選單列已經建好就現在做，主迴圈跑起來時再做一次:啟動之前 GTK 還沒建選單列。
            if submenus.first?.label == ProcessInfo.processInfo.processName {
                adoptApplicationMenuOnMac()
                runInMainThread { [weak self] in self?.adoptApplicationMenuOnMac() }
            }
        #endif

        let showMenuBar = !submenus.isEmpty
        for window in windows {
            window.showMenuBar = showMenuBar
            if showMenuBar {
                GtkContentFocus.track(
                    UnsafeMutableRawPointer(window.widgetPointer).assumingMemoryBound(to: GtkWindow.self)
                )
            }
        }
    }

    class ThreadActionContext {
        var action: @MainActor () -> Void

        init(action: @escaping @MainActor () -> Void) {
            self.action = action
        }
    }

    public func runInMainThread(action: @escaping @MainActor () -> Void) {
        let action = ThreadActionContext(action: action)
        g_idle_add_full(
            0,
            { context in
                guard let context else {
                    fatalError("Gtk action callback called without context")
                }

                let action = Unmanaged<ThreadActionContext>.fromOpaque(context)
                    .takeUnretainedValue()
                let innerAction = action.action
                MainActor.assumeIsolated {
                    innerAction()
                }

                return 0
            },
            Unmanaged<ThreadActionContext>.passRetained(action).toOpaque(),
            { _ in }
        )
    }

    static func runInMainThread(
        afterMilliseconds delay: Int,
        action: @escaping @MainActor () -> Void
    ) {
        let action = ThreadActionContext(action: action)
        g_timeout_add_full(
            0,
            guint(max(delay, 0)),
            { context in
                guard let context else {
                    fatalError("Gtk action callback called without context")
                }

                let action = Unmanaged<ThreadActionContext>.fromOpaque(context)
                    .takeUnretainedValue()
                let innerAction = action.action
                MainActor.assumeIsolated {
                    innerAction()
                }

                // Cancel the recurring timeout after one iteration
                return 0
            },
            Unmanaged<ThreadActionContext>.passRetained(action).toOpaque(),
            { _ in }
        )
    }

    public func computeRootEnvironment(defaultEnvironment: EnvironmentValues) -> EnvironmentValues {
        // #386: report the ambient theme, so text drawn under a dark theme is
        // light instead of staying at its light-mode colour and turning
        // near-invisible. suggestedForegroundColor is
        // colorScheme.defaultForegroundColor, so getting this right is what makes
        // the rest follow.
        //
        // #386：回報環境主題，使在深色主題下繪製的文字為淺色，而非維持 light 模式的顏色而幾乎
        // 不可見。suggestedForegroundColor 即 colorScheme.defaultForegroundColor，因此把這裡
        // 弄對，其餘便隨之而正確。
        return defaultEnvironment
            .with(\.appPhase, windows.contains(where: \.isActive) ? .active : .inactive)
            .with(\.colorScheme, ambientColorScheme)
    }

    /// The colour scheme of the GTK theme the app started under.
    ///
    /// Read from the colour the theme gives a plain label, not from a settings
    /// flag, because the flags do not carry the answer. Measured under GTK 4,
    /// one process per theme:
    ///
    ///     GTK_THEME       label fg luma   gtk-theme-name   prefer-dark
    ///     Adwaita         0.20 (light)    Default          false
    ///     Adwaita:dark    0.93 (dark)     Default          false
    ///     unset           0.20 (light)    Default          false
    ///
    /// The colour tracks the theme exactly, while `gtk-theme-name` and
    /// `gtk-application-prefer-dark-theme` do not move at all -- so a backend
    /// that trusts them reports "light" while the screen is dark, which is #386.
    ///
    /// Sampled once at the start of the main loop rather than on demand, for two
    /// reasons. GTK has to be initialised before a label carries theme colours at
    /// all. And honouring `preferredColorScheme` changes those colours, so a
    /// later reading would report back whatever the app last asked for, losing
    /// the ambient value an override is defined against.
    ///
    /// 由主題賦予一般 label 的顏色讀取，而非讀設定旗標，因為旗標並不帶有答案（上表為 GTK 4 實測，
    /// 每個主題各一個獨立行程）：顏色完全跟隨主題，而 `gtk-theme-name` 與
    /// `gtk-application-prefer-dark-theme` 完全不動——因此信任它們的 backend 會回報「light」而畫面
    /// 是深色的，這正是 #386。
    ///
    /// 於主迴圈啟動時取樣一次而非即時讀取，有兩個理由：GTK 必須先初始化，label 才會帶有主題顏色；
    /// 且遵從 `preferredColorScheme` 會改變那些顏色，因此較晚的讀取只會回報 app 最後一次的要求，
    /// 使 override 所要對照的環境值遺失。
    private var ambientColorScheme: ColorScheme = .light

    /// Which variant GTK is currently drawing, as far as this backend knows.
    ///
    /// Not read back from `Gtk.Settings`, because the flag does not carry the
    /// answer -- that is the measurement recorded on ``ambientColorScheme``,
    /// where `Adwaita:dark` leaves `gtk-application-prefer-dark-theme` at false.
    /// It does report a value this backend wrote, though, which is all
    /// `updateWindow` needs to know: whether its own last write still stands.
    ///
    /// 就本 backend 所知，GTK 目前正在繪製的變體。
    ///
    /// 並非自 `Gtk.Settings` 讀回，因為該旗標並不帶有答案——這正是記錄於 ``ambientColorScheme``
    /// 的實測結果：`Adwaita:dark` 之下 `gtk-application-prefer-dark-theme` 仍為 false。不過它確實
    /// 能回報「本 backend 曾寫入的值」，而那正是 `updateWindow` 所需的全部資訊：它自己上一次的
    /// 寫入是否仍然有效。
    private var gtkPrefersDarkTheme = false

    /// The colour scheme the desktop itself is set to, where the platform has
    /// one this backend can read and GTK does not already follow it.
    ///
    /// Windows, macOS and WSL (Windows read through interop): GTK there ships its own theme and does not track the system
    /// light/dark setting, so an app would sit in Adwaita light on a dark
    /// desktop. On a Linux desktop the GTK theme *is* the desktop setting, so reading the
    /// theme's colour already answers the question and there is nothing separate
    /// to consult.
    ///
    /// 平台自身所設定的配色，僅在「本 backend 讀得到、且 GTK 尚未跟隨」的情況下提供。
    ///
    /// Windows、macOS 與 WSL(經 interop 讀取 Windows):GTK 在這些平台自帶主題，不會追蹤系統的淺色／深色設定，因此 app 會在深色桌面上
    /// 停留於 Adwaita light。在 Linux 上，GTK 主題「就是」桌面的設定，因此讀取主題顏色便已回答了
    /// 這個問題，無須另行查詢。
    private var systemColorScheme: ColorScheme? {
        if let forced = Self.forcedColorScheme { return forced }
        #if os(Windows)
            // HKCU\...\Themes\Personalize\AppsUseLightTheme, the value the
            // Settings app writes for "Choose your default app mode": 0 is dark,
            // 1 is light. Documented for exactly this purpose.
            // 此即「Settings 中『選擇您的預設應用程式模式』」所寫入的值：0 為深色、1 為淺色。
            var value: DWORD = 1
            var size = DWORD(MemoryLayout<DWORD>.size)
            let status = "Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize"
                .withCString(encodedAs: UTF16.self) { subKey in
                    "AppsUseLightTheme".withCString(encodedAs: UTF16.self) { name in
                        RegGetValueW(
                            HKEY_CURRENT_USER,
                            subKey,
                            name,
                            DWORD(RRF_RT_REG_DWORD),
                            nil,
                            &value,
                            &size
                        )
                    }
                }
            guard status == ERROR_SUCCESS else { return nil }
            return value == 0 ? .dark : .light
        #elseif os(macOS)
            // The system appearance, which GTK on macOS does not follow: Homebrew's
            // GTK draws Adwaita light on a dark Mac, so P3's headings were the light
            // scheme's dark grey on the app's black (2026-10-16). AppleInterfaceStyle
            // is "Dark" in dark mode and absent in light mode.
            // 系統外觀,macOS 上的 GTK 不會跟隨:Homebrew 的 GTK 在深色的 Mac 上畫 Adwaita 淺色，因此 P3 的標題
            // 是淺色配置的深灰色，畫在 app 的黑底上(2026-10-16)。深色模式下 AppleInterfaceStyle 為 "Dark",淺色時不存在。
            return UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" ? .dark : .light
        #elseif os(Linux)
            // Under WSL the desktop is Windows, and WSLg's GTK has no setting of its
            // own to follow: every app drew Adwaita light on a dark Windows desktop,
            // while the same app is dark on Windows GTK and on GTK on the Mac
            // (2026-10-20). So the Windows value is read through interop, once.
            // WSL 之下桌面是 Windows,WSLg 的 GTK 沒有自己可跟隨的設定：每支 app 都在深色的 Windows 桌面上畫
            // Adwaita 淺色，而同一支 app 在 Windows GTK 與 Mac 上的 GTK 都是深色(2026-10-20)。因此經由 interop
            // 讀取 Windows 的值，只讀一次。
            return Self.wslHostColorScheme
        #else
            return nil
        #endif
    }

    /// A light/dark choice forced through `SCUI_GTK_COLOR_SCHEME` (`dark` or
    /// `light`), which outranks ``systemColorScheme``'s platform reading; any
    /// other value, or none, leaves the platform in charge. The test harness
    /// sets it to `dark` by default so GtkBackend draws the same scheme on
    /// Windows, under WSL and on the Mac: on 2026-10-22 the three-way deck had
    /// Windows and the Mac dark while WSL was light on P0 and P44, which made
    /// the comparison about the theme rather than the layout.
    ///
    /// 經 `SCUI_GTK_COLOR_SCHEME`(`dark` 或 `light`)強制指定的淺色／深色，優先於 ``systemColorScheme`` 對平台的讀取；
    /// 其他值或未設定時，仍由平台決定。測試工具預設設為 `dark`,讓 GtkBackend 在 Windows、WSL 與 Mac 上畫同一種配色：
    /// 2026-10-22 的三方簡報中 Windows 與 Mac 是深色，WSL 在 P0 與 P44 卻是淺色，比較的變成主題而不是版面。
    private static let forcedColorScheme: ColorScheme? = {
        switch ProcessInfo.processInfo.environment["SCUI_GTK_COLOR_SCHEME"] {
            case "dark": return .dark
            case "light": return .light
            default: return nil
        }
    }()

    #if os(Linux)
        /// Windows' "default app mode" when this process runs under WSL, else nil.
        ///
        /// Read once, with `reg.exe` through WSL interop (59 ms measured), because
        /// ``systemColorScheme`` is consulted repeatedly and a process per call
        /// would be absurd. The cost is that a WSL app does not follow a change
        /// made while it runs; it does follow it on the next launch. A run that
        /// cannot start `reg.exe` within two seconds gets nil, which leaves GTK's
        /// own theme in charge, not an error.
        ///
        /// 本行程在 WSL 下執行時的 Windows「預設應用程式模式」,否則為 nil。以 `reg.exe` 經 WSL interop 讀取一次
        /// (實測 59 ms),因為 ``systemColorScheme`` 會被反覆查詢，每次都開行程並不合理。代價是 WSL 的 app 不會跟隨
        /// 執行期間的切換，下次啟動時才會。兩秒內無法啟動 `reg.exe` 時得到 nil,即不讀 Windows 設定時的行為(GTK 自己的主題),而非錯誤。
        /// Whether this process runs under WSL. / 本行程是否在 WSL 下執行。
        private static let isWSL: Bool =
            ProcessInfo.processInfo.environment["WSL_DISTRO_NAME"] != nil
            || FileManager.default.fileExists(atPath: "/proc/sys/fs/binfmt_misc/WSLInterop")

        /// Whether Segoe UI was added to fontconfig for this process.
        /// 本行程是否已把 Segoe UI 加入 fontconfig。
        nonisolated(unsafe) private static var usesWindowsUIFont = false

        /// Under WSL, makes Windows' Segoe UI available to GTK; see gtk_wsl_fonts.c
        /// for why (P22's nine weights drew as two in DejaVu Sans). Runs before
        /// GApplication exists, because Pango reads fontconfig once, when it builds
        /// its font map. SCUI_GTK_NO_WINDOWS_FONT=1 keeps the distro's font.
        /// 在 WSL 下讓 GTK 可使用 Windows 的 Segoe UI;原因見 gtk_wsl_fonts.c(P22 的九種字重在 DejaVu Sans 中只畫出兩種)。
        /// 在 GApplication 建立前執行，因為 Pango 只在建立 font map 時讀一次 fontconfig。SCUI_GTK_NO_WINDOWS_FONT=1
        /// 保留發行版自己的字型。
        static func addWindowsUIFontUnderWSL() {
            guard isWSL, ProcessInfo.processInfo.environment["SCUI_GTK_NO_WINDOWS_FONT"] != "1"
            else { return }
            // segoeui* is regular, bold, italic and light; seguisb*, seguibl* and
            // seguisli/seguili are semibold, black and the light italics. Not segui*
            // as a whole, which would also add the emoji and symbol fonts.
            // segoeui* 是一般、粗體、斜體與細體;seguisb*、seguibl* 與 seguisli/seguili 是半粗、特粗與細斜體。
            // 不用整個 segui*,那會連 emoji 與符號字型一起加入。
            let prefixes = ["segoeui", "seguisb", "seguibl", "seguili", "seguisli"]
            let added = prefixes.reduce(0) { $0 + Int(scui_add_font_files("/mnt/c/Windows/Fonts", $1)) }
            usesWindowsUIFont = added > 0
        }

        /// Swaps the family in `gtk-font-name` for Segoe UI and keeps its size;
        /// the system font sets only size and weight, so this is the family every
        /// Text gets. / 把 `gtk-font-name` 的家族換成 Segoe UI 並保留字級；系統字型只設定字級與字重，
        /// 因此這就是每個 Text 得到的家族。
        static func applyWindowsUIFontUnderWSL() {
            guard usesWindowsUIFont, let settings = Gtk.Settings.default else { return }
            let size = settings.fontName.split(separator: " ").last.flatMap { Double($0) } ?? 11
            let sizeText = size == size.rounded() ? String(Int(size)) : String(size)
            settings.fontName = "Segoe UI \(sizeText)"
        }

        private static let wslHostColorScheme: ColorScheme? = {
            guard isWSL else { return nil }
            let files = FileManager.default
            let reg = "/mnt/c/Windows/System32/reg.exe"
            guard files.isExecutableFile(atPath: reg) else { return nil }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: reg)
            process.arguments = [
                "query", #"HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"#,
                "/v", "AppsUseLightTheme",
            ]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return nil }
            let deadline = Date().addingTimeInterval(2)
            while process.isRunning && Date() < deadline { usleep(10_000) }
            if process.isRunning {
                process.terminate()
                return nil
            }
            let text = String(
                decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            // `    AppsUseLightTheme    REG_DWORD    0x0`: 0 is dark, 1 is light.
            // 0 為深色,1 為淺色。
            guard
                let line = text.split(whereSeparator: \.isNewline)
                    .first(where: { $0.contains("AppsUseLightTheme") }),
                let value = line.split(whereSeparator: \.isWhitespace).last
            else { return nil }
            switch value.lowercased() {
                case "0x0": return .dark
                case "0x1": return .light
                default: return nil
            }
        }()
    #endif

    /// What the current GTK theme's foreground colour implies, and NOTHING else.
    ///
    /// It assigns nothing, unlike ``sampleAmbientColorScheme``, which also
    /// WRITES `Settings.default?.preferDarkTheme` (#27). Calling that from a
    /// `notify::` handler would push a value back into the object whose change
    /// caused the notification -- a feedback loop. This one only reads. Must
    /// run with GTK initialised.
    ///
    /// 目前 GTK 主題的前景色所蘊含的配色，**且僅止於此**。
    ///
    /// 它不指派任何東西，不同於 ``sampleAmbientColorScheme``——後者同時會**寫入**
    /// `Settings.default?.preferDarkTheme`(#27)。若從 `notify::` 的 handler 呼叫後者，等於把一個值推回
    /// 「其變更觸發了該通知」的那個物件——那是一個回饋迴圈。這一個只讀。必須在 GTK 初始化後執行。
    private func readAmbientColorScheme() -> ColorScheme {
        // A throwaway label in a throwaway window, neither ever shown.
        //
        // Two things this has to get right, both measured rather than assumed.
        // The widget must be one nothing has styled: reading a label
        // SwiftCrossUI has already coloured (the measurement label, say) reads
        // back what was last written to it rather than the theme -- a loop that
        // returns the app's own last answer. And it must sit inside a window:
        // GTK only resolves theme CSS for a widget that has a root, so a loose
        // label reports the default white (measured: 1.0/1.0/1.0 under every
        // theme, which reads as "dark" everywhere and is wrong everywhere).
        // Being in a window is enough; the window need not be presented.
        //
        // 一個暫時性的 label 放在一個暫時性的視窗中，兩者皆不顯示。
        //
        // 此處有兩件事必須正確，且皆為實測而非假設。其一，該 widget 必須是沒有任何東西為其上色過
        // 的：讀取 SwiftCrossUI 已上色的 label（例如測量用的那個）會讀回最後被寫入的顏色而非主題
        // 色——該迴圈只會回傳 app 自己上次的答案。其二，它必須位於視窗之內：GTK 只會為「具有
        // root」的 widget 解析主題 CSS，因此游離的 label 會回報預設的白色（實測：在每個主題下皆為
        // 1.0/1.0/1.0，於是到處都判為「dark」，也就到處都是錯的）。置於視窗中即已足夠，該視窗
        // 不需要被 present。
        //
        // BUILDING A WINDOW HERE IS SAFE, including from a notification handler:
        // both inline and via `g_idle_add` it built the throwaway Window+Label
        // and returned the correct new value, 0.180 -> 0.933 (2026-08-26). What
        // crashes is a `notify` handler declared with two parameters instead of
        // the marshalled three (instance, GParamSpec*, user_data);
        // `Gtk.GObject.addNotificationSignal` declares three.
        //
        // **在此建立視窗是安全的**，從通知 handler 中呼叫亦然：直接呼叫與透過 `g_idle_add` 兩種方式，
        // 都成功建立了暫時性的 Window+Label 並回傳了正確的新值(0.180 → 0.933,2026-08-26)。會崩潰的是
        // 只宣告兩個參數、而非封送的三個 (instance, GParamSpec*, user_data) 的 `notify` handler;
        // `Gtk.GObject.addNotificationSignal` 宣告的是三個。
        let probeWindow = Gtk.Window()
        let probeLabel = Gtk.Label(string: "")
        probeWindow.setChild(probeLabel)
        let color = probeLabel.getColor()
        probeWindow.destroy()

        // Rec. 601 luma, the weighting used to decide whether text should be
        // black or white on a background. A foreground lighter than mid-grey
        // means the theme draws light text, so onto a dark background. The two
        // measured values (0.20 and 0.93) are far from the midpoint.
        let luma = 0.299 * color.red + 0.587 * color.green + 0.114 * color.blue
        return luma > 0.5 ? .dark : .light
    }

    /// Subscribes to the two GtkSettings properties that report a desktop
    /// light/dark change, and to no others.
    ///
    /// **`notify::gtk-application-prefer-dark-theme` is deliberately absent.**
    /// This backend WRITES that property itself, in `updateWindow` and in
    /// `sampleAmbientColorScheme`, so subscribing to it is a guaranteed feedback
    /// loop -- the app changes the theme, GTK notifies, the app re-samples and
    /// changes it again. Measured 2026-08-26: setting `prefer-dark-theme` leaves
    /// `gtk-theme-name` unchanged, so the two properties chosen here are
    /// feedback-free with respect to everything this backend writes.
    ///
    /// The handler is idempotent by value: it re-reads, compares against the
    /// stored scheme, and only then tells the environment. GTK emits `notify`
    /// for a set-to-the-same-value as well, and a handler that fired the
    /// environment change unconditionally would rebuild every view for nothing.
    ///
    /// **Not verifiable on stock WSLg, and that is measured rather than
    /// assumed.** `gsettings set org.gnome.desktop.interface color-scheme
    /// prefer-dark` produced ZERO notifications on any of GtkSettings' 55
    /// properties, under both Wayland and X11, because stock WSLg has no
    /// xdg-desktop-portal, no XSettings manager, no libadwaita and an empty
    /// `XDG_CURRENT_DESKTOP`. With xdg-desktop-portal and -gtk installed, whose
    /// Settings interface carries the color scheme, it has not been measured.
    /// Verification needs a real GNOME desktop, or a Windows theme switch for
    /// the Windows branch.
    ///
    /// 訂閱兩個「會回報桌面淺色／深色變更」的 GtkSettings 屬性，且僅此兩個。
    ///
    /// **`notify::gtk-application-prefer-dark-theme` 是刻意排除的。** 本 backend 自己會**寫入**該
    /// 屬性（於 `updateWindow` 與 `sampleAmbientColorScheme` 之中），因此訂閱它必然造成回饋迴圈
    /// ——app 改變主題、GTK 發出通知、app 重新取樣後再改一次。**2026-08-26 實測**：設定
    /// `prefer-dark-theme` 不會改變 `gtk-theme-name`，因此此處所選的兩個屬性，相對於本 backend 會
    /// 寫入的一切都是無回饋的。
    ///
    /// 該 handler 以**值**保證冪等：它重新讀取、與已存的配色比較，唯有不同時才通知環境。GTK 在
    /// 「設定為相同的值」時同樣會發出 `notify`，而一個無條件觸發環境變更的 handler，會為了什麼都
    /// 沒發生而重建每一個 view。
    ///
    /// **在原版 WSLg 下無法驗證，而這是實測而非臆測。**
    /// `gsettings set org.gnome.desktop.interface color-scheme prefer-dark` 在 Wayland 與 X11 下，
    /// 對 GtkSettings 的 55 個屬性**皆未產生任何通知**，因為原版 WSLg 沒有 xdg-desktop-portal、沒有
    /// XSettings manager、沒有 libadwaita，且 `XDG_CURRENT_DESKTOP` 為空。裝有 xdg-desktop-portal 與
    /// -gtk(其 Settings 介面帶有配色)時尚未量測。驗證需要一個真正的 GNOME 桌面，或針對 Windows 分支
    /// 做一次 Windows 主題切換。
    /// Carries a weak ``GtkBackend`` and an `HKEY` across a thread boundary.
    ///
    /// `@unchecked Sendable` for the reason spelled out at its use site: this
    /// module is on Swift 6, neither member is Sendable on its own, and the box
    /// is written once and read thereafter. Modelled on `WeakViewBox` in
    /// `Gtk/Widgets/NV12GLView.swift`, which crosses the same boundary the same
    /// way.
    ///
    /// Declared unconditionally rather than inside `#if os(Windows)` so that a
    /// change here is compiled on every platform. A type that exists on one
    /// platform is a type that can be broken on the others without anyone
    /// noticing until that platform is built.
    ///
    /// 跨執行緒邊界攜帶一個 weak 的 ``GtkBackend`` 與一個 `HKEY`。
    ///
    /// 標為 `@unchecked Sendable`，理由寫在它的使用處：本模組處於 Swift 6，兩個成員各自都不是
    /// Sendable，而此 box 只寫入一次、其後只被讀取。仿自 `Gtk/Widgets/NV12GLView.swift` 中的
    /// `WeakViewBox`——它以相同方式跨越相同的邊界。
    ///
    /// 此處**不**包在 `#if os(Windows)` 之內而是無條件宣告，如此對它的改動會在每個平台上都被編譯。
    /// 一個只存在於單一平台的型別，就是一個「可以在其他平台上被弄壞、而在那個平台被建置之前沒有人會
    /// 發現」的型別。
    private final class ColorSchemeWatchBox: @unchecked Sendable {
        weak var backend: GtkBackend?
        #if os(Windows)
            let key: HKEY
            init(backend: GtkBackend?, key: HKEY) {
                self.backend = backend
                self.key = key
            }
        #else
            init(backend: GtkBackend?) {
                self.backend = backend
            }
        #endif
    }

    /// Windows only: watch the registry key ``systemColorScheme`` reads.
    ///
    /// **The GtkSettings subscription below is not enough on Windows, and that
    /// is not a shortcoming of it.** GTK there ships its own theme and does not
    /// track the system light/dark setting -- which is the whole reason
    /// ``systemColorScheme`` exists -- so `notify::gtk-theme-name` will very
    /// likely never fire for a desktop change. Two platforms, two triggers, one
    /// handler.
    ///
    /// **Why a registry watch rather than `WM_SETTINGCHANGE`.** The conventional
    /// Win32 answer is `WM_SETTINGCHANGE` with `lParam == "ImmersiveColorSet"`,
    /// and it was rejected for a specific reason rather than unfamiliarity: GTK
    /// owns the message loop, so receiving it means subclassing the toplevel's
    /// HWND -- which requires the window to be realised, has to be installed and
    /// removed per window, and puts a Win32 `WNDPROC` in the path of every
    /// message GTK handles. `RegNotifyChangeKeyValue` watches the same key
    /// ``systemColorScheme`` already reads, needs no window, and touches nothing
    /// GTK owns. If it ever proves to miss a change that `WM_SETTINGCHANGE`
    /// catches, that is the reason to revisit -- not elegance.
    ///
    /// `REG_NOTIFY_THREAD_AGNOSTIC` so the subscription outlives this call
    /// rather than the thread that made it; without it the notification is
    /// cancelled when the calling thread exits, which is a silent failure, not
    /// an error.
    ///
    /// The thread is detached and never joined. It ends when the process does.
    /// That is deliberate: there is no teardown path for the backend, and a
    /// thread parked in `WaitForSingleObject` costs one kernel wait.
    ///
    /// **僅限 Windows:監看 ``systemColorScheme`` 所讀取的那個登錄檔鍵。**
    ///
    /// **下方的 GtkSettings 訂閱在 Windows 上不夠用,而那不是它的缺陷。** GTK 在該平台自帶主題、
    /// 不追蹤系統的淺色／深色設定——那正是 ``systemColorScheme`` 存在的全部理由——因此
    /// `notify::gtk-theme-name` 極可能永遠不會因為桌面切換而觸發。兩個平台、兩個觸發源、同一個 handler。
    ///
    /// **為何用登錄檔監看而非 `WM_SETTINGCHANGE`。** Win32 的慣用答案是 `WM_SETTINGCHANGE` 搭配
    /// `lParam == "ImmersiveColorSet"`,此處捨棄它有具體理由、而非因為不熟:GTK 擁有訊息迴圈,因此要
    /// 收到它就必須子類化 toplevel 的 HWND——那需要視窗已 realise、必須逐視窗安裝與移除,並且會把一個
    /// Win32 `WNDPROC` 插進 GTK 所處理的**每一則訊息**的路徑上。`RegNotifyChangeKeyValue` 監看的是
    /// ``systemColorScheme`` 本來就在讀的同一個鍵,不需要視窗,也不碰任何 GTK 擁有的東西。若日後證實
    /// 它會漏掉 `WM_SETTINGCHANGE` 抓得到的變更,**那才是**重新考慮的理由——而不是優雅與否。
    ///
    /// 使用 `REG_NOTIFY_THREAD_AGNOSTIC`,好讓該訂閱的存續不繫於發出它的執行緒;少了它,呼叫端執行緒
    /// 結束時通知會被取消,而那是一次靜默的失敗,不是錯誤。
    ///
    /// 該執行緒是分離的,永不 join,隨行程結束而結束。這是刻意的:backend 沒有拆除路徑,而一個停在
    /// `WaitForSingleObject` 的執行緒只佔用一次核心等待。
    private func watchSystemColorSchemeChanges() {
        #if os(Windows)
            var key: HKEY?
            let opened = "Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize"
                .withCString(encodedAs: UTF16.self) { subKey in
                    RegOpenKeyExW(HKEY_CURRENT_USER, subKey, 0, DWORD(KEY_NOTIFY), &key)
                }
            guard opened == ERROR_SUCCESS, let key else {
                DebugFeatures.log(
                    "GtkBackend: could not open the Personalize key (\(opened)); "
                        + "the app will not follow a Windows light/dark change while running."
                )
                return
            }

            // ONE box carrying both the weak backend and the key, `@unchecked
            // Sendable`, because `GtkBackend` is not Sendable and `HKEY` is a
            // raw pointer -- and this module is on Swift 6, where capturing
            // either in a `Thread` closure is an ERROR, not a warning.
            //
            // This is the shape `Gtk/Widgets/NV12GLView.swift` already uses to
            // cross the same boundary (`WeakViewBox`, passed as an opaque
            // pointer, dereferenced under `MainActor.assumeIsolated` on the
            // other side). Copied rather than reinvented: a second way of doing
            // one thing is a second thing to get wrong.
            //
            // What makes the `@unchecked` honest: the box is written once here
            // and only ever READ afterwards, the weak reference is the only
            // mutable state and ARC makes that access atomic, and the backend
            // itself is touched only on GTK's thread.
            //
            // **一個 box 同時攜帶 weak backend 與那個 key**，標為 `@unchecked Sendable`，因為
            // `GtkBackend` 不是 Sendable 而 `HKEY` 是裸指標——而本模組處於 Swift 6，在其中把兩者之一
            // 捕獲進 `Thread` 閉包是**錯誤**，不是警告。
            //
            // 這正是 `Gtk/Widgets/NV12GLView.swift` 已經在用來跨越同一道邊界的形狀（`WeakViewBox`，
            // 以不透明指標傳遞，在另一側於 `MainActor.assumeIsolated` 之下解參考）。此處是**沿用**而非
            // 重新發明：同一件事有第二種做法，就是第二個會出錯的地方。
            //
            // 讓這個 `@unchecked` 誠實的理由：此 box 只在此處寫入一次，之後只會被**讀取**；唯一的可變
            // 狀態是那個 weak 參照，而 ARC 使該存取為原子；至於 backend 本身，只會在 GTK 的執行緒上被碰觸。
            let box = ColorSchemeWatchBox(backend: self, key: key)

            let thread = Thread {
                while true {
                    guard let event = CreateEventW(nil, false, false, nil) else { return }
                    defer { CloseHandle(event) }

                    let armed = RegNotifyChangeKeyValue(
                        box.key,
                        false,
                        DWORD(REG_NOTIFY_CHANGE_LAST_SET) | DWORD(REG_NOTIFY_THREAD_AGNOSTIC),
                        event,
                        true
                    )
                    guard armed == ERROR_SUCCESS else {
                        DebugFeatures.log(
                            "GtkBackend: RegNotifyChangeKeyValue failed (\(armed)); "
                                + "no further light/dark changes will be followed."
                        )
                        return
                    }

                    guard WaitForSingleObject(event, INFINITE) == WAIT_OBJECT_0 else { return }
                    guard box.backend != nil else { return }

                    // Back to GTK's thread before touching anything.
                    // `runInMainThread` already exists on this type and wraps
                    // `g_idle_add_full`, which is GTK's own scheduling primitive
                    // and runs in the loop that is actually turning. Doing the
                    // re-sample here would build a GTK widget -- the probe
                    // Window and Label -- from a thread GTK knows nothing about.
                    //
                    // 先回到 GTK 的執行緒再碰任何東西。`runInMainThread` 本型別上已經有了，它包裝的是
                    // `g_idle_add_full`——GTK 自己的排程原語，執行於真正在運轉的那個迴圈中。若在此處
                    // 直接重新取樣，等於從一個 GTK 一無所知的執行緒建立 GTK widget（那個探針用的
                    // Window 與 Label）。
                    // The box crosses as an opaque pointer and is dereferenced
                    // on the other side, exactly as NV12GLView does it. Passing
                    // a Swift closure that captured the backend would put a
                    // non-Sendable value across the boundary, which is the thing
                    // the box exists to avoid.
                    //
                    // `passRetained` here, `release` in the destroy notify: the
                    // idle source owns one reference for as long as it is
                    // pending, so the box cannot be collected between the post
                    // and the callback.
                    //
                    // box 以不透明指標跨越，並在另一側解參考，做法與 NV12GLView 完全相同。若改為傳遞
                    // 一個捕獲了 backend 的 Swift 閉包，等於把一個非 Sendable 的值送過邊界——而那正是
                    // 這個 box 所要避免的事。
                    //
                    // 此處用 `passRetained`、在 destroy notify 中 `release`：只要該 idle source 仍在
                    // 等待，它就持有一份參照，因此 box 不會在「送出」與「回呼」之間被回收。
                    g_idle_add_full(
                        0,
                        { pointer in
                            guard let pointer else { return 0 }
                            let box = Unmanaged<ColorSchemeWatchBox>
                                .fromOpaque(pointer)
                                .takeUnretainedValue()
                            MainActor.assumeIsolated {
                                box.backend?.recheckAmbientColorScheme()
                            }
                            return 0
                        },
                        Unmanaged.passRetained(box).toOpaque(),
                        { pointer in
                            guard let pointer else { return }
                            Unmanaged<ColorSchemeWatchBox>.fromOpaque(pointer).release()
                        }
                    )
                }
            }
            thread.stackSize = 1 << 18
            thread.start()
        #elseif os(macOS)
            // The appearance switch in System Settings posts this distributed
            // notification; GTK on macOS does not follow it, which is why
            // `systemColorScheme` has a macOS branch at all. The handler hops to
            // GTK's thread through `g_idle_add`, as the Windows watch does.
            // 系統設定中的外觀切換會發出這個分散式通知;macOS 上的 GTK 不會跟隨它，這正是 `systemColorScheme`
            // 有 macOS 分支的原因。handler 經由 `g_idle_add` 回到 GTK 的執行緒，與 Windows 的監看相同。
            let box = ColorSchemeWatchBox(backend: self)
            colorSchemeObserver = DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
                object: nil,
                queue: nil
            ) { _ in
                g_idle_add_full(
                    0,
                    { pointer in
                        guard let pointer else { return 0 }
                        let box = Unmanaged<ColorSchemeWatchBox>.fromOpaque(pointer)
                            .takeUnretainedValue()
                        MainActor.assumeIsolated {
                            box.backend?.recheckAmbientColorScheme()
                        }
                        return 0
                    },
                    Unmanaged.passRetained(box).toOpaque(),
                    { pointer in
                        guard let pointer else { return }
                        Unmanaged<ColorSchemeWatchBox>.fromOpaque(pointer).release()
                    }
                )
            }
        #endif
    }

    private func subscribeToAmbientColorSchemeChanges() {
        watchSystemColorSchemeChanges()

        guard let settings = Gtk.Settings.default else { return }

        // `registerNotification`, NOT `addNotificationSignal`. The latter is
        // declared with no access modifier inside `open class GObject`, so it is
        // internal to the `Gtk` module and a call from here does not compile.
        // `Settings` already exposes exactly this wrapper, and it takes the full
        // name including the `notify::` prefix.
        // Raw GTK plumbing belongs in the `Gtk` module, with a named method
        // crossing the boundary -- the same shape as
        // `Window.setHeaderBar(leading:trailing:)`.
        //
        // 此處用 `registerNotification`，**不是** `addNotificationSignal`。後者宣告於
        // `open class GObject` 內且沒有存取修飾詞，因此僅在 `Gtk` 模組內可見，從這裡呼叫編不過。
        // `Settings` 已經公開了正是這個包裝，而且它接受含 `notify::` 前綴的完整名稱。
        //
        // **原始的 GTK 管線屬於 `Gtk` 模組**，並以一個具名方法跨越邊界——與
        // `Window.setHeaderBar(leading:trailing:)` 是同一種形狀。
        for property in ["gtk-interface-color-scheme", "gtk-theme-name"] {
            settings.registerNotification(named: "notify::\(property)") { [weak self] in
                self?.recheckAmbientColorScheme()
            }
        }
    }

    /// Re-read the scheme and, only if it moved, apply it and tell the
    /// environment.
    ///
    /// **ONE body, two triggers**, and that is the point of it being a method
    /// rather than a closure: the GtkSettings notification (Linux, and Windows
    /// in principle) and the registry watch (Windows, in practice) must not
    /// drift apart. Two copies of a rule about which reading wins would.
    ///
    /// Idempotent by value. GTK emits `notify` for a set-to-the-same-value as
    /// well, and the registry watch fires for any change under the key -- there
    /// are other values in `Personalize` -- so an unconditional call would
    /// rebuild every view for nothing.
    ///
    /// **一個本體、兩個觸發源**,而這正是它是方法而非閉包的理由:GtkSettings 的通知(Linux,以及理論上
    /// 的 Windows)與登錄檔監看(Windows,實務上)**不可以漂移開來**。「哪一個讀數優先」這條規則若有兩份
    /// 副本，就會漂移。
    ///
    /// 以**值**保證冪等。GTK 在「設定為相同的值」時同樣會發出 `notify`,而登錄檔監看則會為該鍵底下的
    /// **任何**變更觸發——`Personalize` 之下還有別的值——因此無條件呼叫會為了什麼都沒發生而重建每一個
    /// view。
    private func recheckAmbientColorScheme() {
        // `systemColorScheme` FIRST, and this is not a detail. It is a
        // computed property that reads the Windows registry on every
        // access, so it is live; and where it has a value, it WINS --
        // that is the whole reason the Windows branch of
        // `sampleAmbientColorScheme` exists. Taking `readAmbientColorScheme()`
        // unconditionally would let a GTK theme change on Windows overwrite
        // the user's system preference.
        //
        // **先取 `systemColorScheme`,而這不是細節。** 它是一個計算屬性，每次存取都會讀取
        // Windows 登錄檔，因此它是即時的；而在它有值之處，它**優先**——那正是
        // `sampleAmbientColorScheme` 的 Windows 分支存在的全部理由。無條件採用 `readAmbientColorScheme()`,
        // 會讓 Windows 上的一次 GTK 主題變更**覆蓋掉使用者的系統偏好**。
        let fresh = systemColorScheme ?? readAmbientColorScheme()
        guard fresh != ambientColorScheme else { return }

        // Re-run the sampler rather than assigning here, so the
        // precedence rule and the `preferDarkTheme` write live in ONE
        // place. It costs a second probe window, which is a throwaway
        // Window plus Label and not on any hot path.
        //
        // Writing `preferDarkTheme` from here does NOT re-enter: the
        // subscriptions above are on `gtk-theme-name` and
        // `gtk-interface-color-scheme`, and it was measured on
        // 2026-08-26 that setting `prefer-dark-theme` leaves
        // `gtk-theme-name` unchanged. That measurement is what makes
        // this safe, not the shape of the code.
        //
        // 此處重新執行取樣器、而非就地指派，好讓「優先順序規則」與「寫入 `preferDarkTheme`」
        // 留在**同一處**。代價是多一個探針視窗——一個暫時性的 Window 加 Label，且不在任何
        // 熱路徑上。
        //
        // 從此處寫入 `preferDarkTheme` **不會**重入：上方訂閱的是 `gtk-theme-name` 與
        // `gtk-interface-color-scheme`，而 2026-08-26 已實測「設定 `prefer-dark-theme` 不會
        // 改變 `gtk-theme-name`」。**讓這件事安全的是那次量測，不是程式碼的形狀。**
        sampleAmbientColorScheme()

        // `gtkPrefersDarkTheme` is not set here: `sampleAmbientColorScheme`
        // already ends by setting it from `ambientColorScheme`, and a second
        // copy of that rule could disagree with the first.
        //
        // 此處不設定 `gtkPrefersDarkTheme`:`sampleAmbientColorScheme` 結尾已經依 `ambientColorScheme`
        // 設定過它，而那條規則的第二份副本可能與第一份不一致。
        rootEnvironmentChangeHandler?()
    }

    private func sampleAmbientColorScheme() {
        // A throwaway label in a throwaway window, neither ever shown.
        //
        // Two things this has to get right, both measured rather than assumed.
        // The widget must be one nothing has styled: reading a label
        // SwiftCrossUI has already coloured (the measurement label, say) reads
        // back what was last written to it rather than the theme -- a loop that
        // returns the app's own last answer. And it must sit inside a window:
        // GTK only resolves theme CSS for a widget that has a root, so a loose
        // label reports the default white (measured: 1.0/1.0/1.0 under every
        // theme, which reads as "dark" everywhere and is wrong everywhere).
        // Being in a window is enough; the window need not be presented.
        //
        // 一個暫時性的 label 放在一個暫時性的視窗中，兩者皆不顯示。
        //
        // 此處有兩件事必須正確，且皆為實測而非假設。其一，該 widget 必須是沒有任何東西為其上色過
        // 的：讀取 SwiftCrossUI 已上色的 label（例如測量用的那個）會讀回最後被寫入的顏色而非主題
        // 色——該迴圈只會回傳 app 自己上次的答案。其二，它必須位於視窗之內：GTK 只會為「具有
        // root」的 widget 解析主題 CSS，因此游離的 label 會回報預設的白色（實測：在每個主題下皆為
        // 1.0/1.0/1.0，於是到處都判為「dark」，也就到處都是錯的）。置於視窗中即已足夠，該視窗
        // 不需要被 present。
        ambientColorScheme = readAmbientColorScheme()

        // Where the platform has a light/dark setting of its own that GTK does
        // not follow -- Windows -- that setting wins, and GTK is asked for the
        // matching variant so its own widgets match as well. Without this an app
        // sits in GTK's light theme on a dark desktop, which is the same
        // readability problem as #386 arriving from the other direction.
        //
        // 若平台本身有 GTK 不會跟隨的淺色／深色設定——即 Windows——則以該設定為準，並向 GTK 要求
        // 對應的變體，使 GTK 自身的 widget 也一致。若無此段，app 會在深色桌面上停留於 GTK 的淺色
        // 主題，那與 #386 是同一個可讀性問題、只是從另一個方向出現。
        if let systemColorScheme, systemColorScheme != ambientColorScheme {
            Gtk.Settings.default?.preferDarkTheme = (systemColorScheme == .dark)
            ambientColorScheme = systemColorScheme
        }

        #if os(Linux)
            Self.applyWindowsUIFontUnderWSL()
        #endif

        // Seeded from the scheme rather than from the branch above, because both
        // paths end with GTK drawing `ambientColorScheme`: with the branch taken
        // because it just wrote the flag, without it because the flag was never
        // needed. `updateWindow` compares against this.
        // 由配色本身設定，而非由上方分支設定，因為兩條路徑最終都是「GTK 正在繪製
        // `ambientColorScheme`」：走進分支時是因為剛寫入旗標，未走進時則是因為根本不需要寫。
        // `updateWindow` 即以此值作為比較對象。
        gtkPrefersDarkTheme = (ambientColorScheme == .dark)
    }

    public func setRootEnvironmentChangeHandler(
        to action: @escaping @Sendable @MainActor () -> Void
    ) {
        // The desktop switching between light and dark while the app runs is
        // followed through a subscription made once, in `runMainLoop`; see
        // ``subscribeToAmbientColorSchemeChanges`` for which two properties and
        // why not the third. Building the throwaway probe window from that
        // handler is safe, inline and via `g_idle_add` (measured 2026-08-26,
        // 0.180 -> 0.933), provided the `notify` handler is declared with all
        // three marshalled parameters (instance, GParamSpec*, user_data) -- with
        // two, `Unmanaged.fromOpaque` is handed the GParamSpec and the process
        // crashes in `swift_retain` -- and `Settings.default` is cached, since a
        // fresh wrapper's `deinit` disconnects the handlers it registered.
        //
        // 桌面於執行期間在淺色與深色之間的切換，透過在 `runMainLoop` 中只做一次的訂閱來跟隨；至於是哪兩個
        // 屬性、以及為何不含第三個，見 ``subscribeToAmbientColorSchemeChanges``。從該 handler 中建立暫時性
        // 探針視窗是安全的，直接呼叫與經由 `g_idle_add` 皆然(2026-08-26 實測,0.180 → 0.933),前提是
        // `notify` handler 宣告了全部三個封送參數 (instance, GParamSpec*, user_data)——只宣告兩個時,
        // `Unmanaged.fromOpaque` 拿到的是 GParamSpec,行程會崩潰於 `swift_retain`——而且 `Settings.default`
        // 有快取，因為一個全新 wrapper 的 `deinit` 會斷開它所註冊的 handler。
        self.rootEnvironmentChangeHandler = action
    }

    public func computeWindowEnvironment(
        window: Window,
        rootEnvironment: EnvironmentValues
    ) -> EnvironmentValues {
        // `gtk_widget_get_scale_factor`, which is the same number
        // `ActionFileReplay` is handed for the synthesiser -- see
        // InputEvent's `WindowGeometry.scale`. It is an integer by design: it
        // is the buffer scale GTK rendered at, not the fraction the display
        // reports, and on Windows those disagree at 125%.
        //
        // Using the toolkit's own answer rather than the display's is the same
        // decision made there, for the same reason: `Image` re-renders when
        // this changes, and rendering at a scale GTK did not lay out with
        // produces an image that is crisp at the wrong size.
        //
        // 使用 `gtk_widget_get_scale_factor`，與 `ActionFileReplay` 交給 synthesiser 的是同一個數字
        // ——見 InputEvent 的 `WindowGeometry.scale`。它依設計為整數：那是 GTK 實際繪製時所用的
        // buffer scale，而非顯示器所回報的小數；在 Windows 上、125% 時兩者並不一致。
        //
        // 採用 toolkit 自己的答案而非顯示器的答案，與該處是同一項決定、同一個理由：`Image` 會在此值
        // 變動時重新繪製，而以「GTK 並未據以排版的比例」繪製，會得到一張「在錯誤尺寸上很銳利」的圖。
        //
        // `windowScaleFactor` is the exception. ActionFileReplay gets the
        // integer -- every action file's coordinates were measured against it
        // -- but an app asking for `windowScaleFactor` is asking what the
        // DISPLAY is at, and GTK's buffer scale reports 1.0 on a 125% Windows
        // display where WinUIBackend, on the same desktop, reports 1.25.
        //
        // `scui_window_display_scale` returns 0 where it has nothing to say --
        // before the window is realized, and on every platform but Win32, where
        // GDK's own fraction IS the display's and stays the source. So this is
        // additive: nothing outside Windows changes.
        //
        // `windowScaleFactor` 是例外。`ActionFileReplay` 拿的是整數——每一個 action file 的座標都是據它
        // 量出來的——但 app 詢問 `windowScaleFactor` 時,問的是**顯示器**處於什麼比例,而 GTK 的 buffer
        // scale 在 125% 的 Windows 顯示器上回報 1.0,同一個桌面上的 WinUIBackend 則回報 1.25。
        //
        // `scui_window_display_scale` 在無話可說時回傳 0——視窗 realize 之前,以及除 Win32 以外的
        // 每個平台(在那些平台上 GDK 自己的小數就是顯示器的,並繼續作為來源)。因此這是**附加**的:
        // Windows 以外沒有任何改變。
        let gtkBufferScale = Double(gtk_widget_get_scale_factor(window.widgetPointer))
        let displayScale = scui_window_display_scale(window.widgetPointer)
        return
            rootEnvironment
                .with(\.scenePhase, window.isActive ? .active : .inactive)
                .with(
                    \.windowScaleFactor,
                    displayScale > 0 ? displayScale : gtkBufferScale
                )
    }

    public func setWindowEnvironmentChangeHandler(
        of window: Window,
        to action: @escaping @Sendable @MainActor () -> Void
    ) {
        // `notify::scale-factor`, because the scale factor is the whole of what
        // `computeWindowEnvironment` reads from the window. Without it a window
        // dragged between displays of different scale keeps whatever it started
        // with: `Image` re-renders on this value, so it stays rendered for the
        // old display until something else forces a recompute.
        //
        // The property, not a display or monitor signal. GTK's scale factor is
        // the buffer scale it actually laid out at -- an integer by design --
        // and `computeWindowEnvironment` deliberately reports that rather than
        // the fraction the display advertises, for the reason recorded there.
        // Watching the display instead would fire on changes GTK did not act on,
        // and miss the moment GTK did.
        //
        // `MainActor.assumeIsolated` rather than a hop: GTK delivers signals on
        // the thread running the main loop, which is the main thread, so the
        // isolation already holds and a hop would only delay the recompute by a
        // turn. Same shape as the action callback above.
        //
        // 使用 `notify::scale-factor`，因為 scale factor 就是 `computeWindowEnvironment` 從視窗
        // 讀取的全部內容。少了它，視窗被拖到不同縮放的顯示器時，會保留它啟動時的值:`Image` 會依這個值
        // 重新繪製，於是它會一直維持著為舊顯示器繪製的結果，直到有別的事情強迫重新計算為止。
        //
        // 監聽的是該屬性，而非顯示器或螢幕的訊號。GTK 的 scale factor 是它實際排版時所用的 buffer
        // scale——依設計即為整數——而 `computeWindowEnvironment` 刻意回報它、而非顯示器所宣稱的
        // 小數，理由記於該處。改為監聽顯示器，會在 GTK 並未據以動作的變化上觸發，卻錯過 GTK 真正
        // 動作的那一刻。
        //
        // 使用 `MainActor.assumeIsolated` 而非 hop：GTK 在執行 main loop 的執行緒上派送訊號，
        // 而那就是主執行緒，因此隔離性本已成立，hop 只會讓重新計算多延遲一輪。與上方的 action
        // callback 形狀相同。
        //
        // Through `Window.onScaleFactorChange`, because `addSignal` is internal
        // to the `Gtk` module: the signal is registered inside the module, by
        // `Window.registerSignals()`, which runs for a top-level window --
        // `ApplicationWindow.init(application:)` calls it directly, rather than
        // via `didMoveToParent`, which never fires for a window with no parent.
        //
        // 透過 `Window.onScaleFactorChange`,因為 `addSignal` 對 `Gtk` 模組為 internal:訊號在模組之內由
        // `Window.registerSignals()` 註冊，而它會為頂層視窗執行——`ApplicationWindow.init(application:)` 直接
        // 呼叫它，而非經由對「沒有 parent 的視窗」永不觸發的 `didMoveToParent`。
        window.onScaleFactorChange = { _ in
            MainActor.assumeIsolated {
                action()
            }
        }

        // NOTHING WINDOWS-SPECIFIC IS NEEDED HERE, and that is a measurement
        // rather than an omission: do not add a WM_DPICHANGED hook.
        //
        // `notify::scale-factor` is silent across a fractional change -- GTK's
        // integer scale is 1 at 100% and 1 at 125% -- but Windows resizes a
        // per-monitor-aware window on a DPI change, the resize runs a layout
        // pass, and the layout pass recomputes this environment. Measured
        // 2026-09-16 with two PER_MONITOR_AWARE instances at once, one with a
        // window-procedure subclass for WM_DPICHANGED and one without: with the
        // display moved 100% -> 150% -> 125%, BOTH recorded `1.0 -> 1.5 -> 1.25`
        // at the same timestamps, and the subclass logged nothing.
        //
        // What makes that mechanism reliable is `enablePerMonitorDPIAwareness()`
        // above; without it the window is not resized and the reported scale is
        // frozen for the life of the process.
        //
        // **此處不需要任何 Windows 專屬的東西,而這是量出來的、不是漏掉的:不要加 `WM_DPICHANGED` hook。**
        //
        // `notify::scale-factor` 對小數變化是沉默的——GTK 的整數縮放在 100% 是 1、125% 也是 1——但 Windows
        // 會在 DPI 改變時調整 per-monitor aware 視窗的大小,resize 會跑一次 layout pass,而那次 layout pass
        // 就會重算這個 environment。2026-09-16 同時跑兩個 PER_MONITOR_AWARE 實例實測,一個裝了攔截
        // WM_DPICHANGED 的 window procedure subclass、一個沒有:顯示器由 100% → 150% → 125% 時,
        // **兩邊都在同樣的時間戳記下記到 `1.0 → 1.5 → 1.25`**,而那支 subclass 一行都沒印。
        //
        // 讓那個機制可靠的是上方的 `enablePerMonitorDPIAwareness()`;少了它,視窗不會被調整大小,
        // 而回報的縮放會在行程的整個生命期內凍住。
    }

    public func setIncomingURLHandler(to action: @escaping (URL) -> Void) {
        #if os(macOS)
            installAppleEventURLHandler(action)
        #endif
        gtkApp.onOpen = { urls in
            for url in urls {
                action(url)
            }
        }
    }

    public func show(widget: Widget) {
        widget.show()
    }

    public func tag(widget: Widget, as tag: String) {
        widget.tag(as: tag)
    }

    // MARK: Containers

    public func createContainer() -> Widget {
        // Passthrough, not a plain Fixed. These containers draw nothing, and a
        // plain GtkFixed claims every point its children do not cover -- so an
        // overlay made everything beneath it unreachable by the pointer. See
        // gtk_passthrough_fixed.c.
        //
        // 使用 passthrough 而非一般的 Fixed。這些容器不繪製任何內容，而一般的 GtkFixed 會攔截
        // 其子元件未覆蓋的每一個點——因此 overlay 會使其下方的一切都無法被指標觸及。
        // 詳見 gtk_passthrough_fixed.c。
        let container = PassthroughFixed()
        container.overflow = .visible
        return container
    }

    public func removeAllChildren(of container: Widget) {
        let container = container as! Fixed
        container.removeAllChildren()
    }

    public func insert(_ child: Widget, into container: Widget, at index: Int) {
        let container = container as! Fixed
        container.put(child, index: index, x: 0, y: 0)
    }

    public func setPosition(ofChildAt index: Int, in container: Widget, to position: SIMD2<Int>) {
        let container = container as! Fixed
        container.move(container.children[index], x: Double(position.x), y: Double(position.y))
    }

    public func remove(childAt index: Int, from container: Widget) {
        let container = container as! Fixed
        let child = container.children[index]
        container.remove(child)
    }

    /// Swaps two children, in GTK as well as in this backend's own list.
    ///
    /// Swapping only the list would leave overlapping widgets in the wrong z
    /// order -- a `ZStack` whose order is driven by state drawing in the wrong
    /// order, silently. AppKitBackend and WinUIBackend reorder their views too
    /// (`subviews.swapAt` and a remove/insert pair). `gtk_widget_insert_after`
    /// is GTK 4's way to place a widget among its siblings, and passing `nil`
    /// for the sibling makes it first.
    ///
    /// The whole order is re-established from the array rather than moving just
    /// the two. Moving two requires working out each one's new anchor while the
    /// other is also moving, which is easy to get subtly wrong for the case
    /// where they are adjacent; walking the array is obviously correct by
    /// inspection, and repairs any order that has drifted rather than swapping
    /// two entries within a sequence that was already wrong. A `Fixed` holds a
    /// handful of children, so the extra work is not worth the sharper edge.
    ///
    /// 交換兩個子元件——在 GTK 中，以及在本 backend 自己的清單中。
    ///
    /// 只交換清單會讓重疊的 widget 得到錯誤的 z 順序——也就是「順序由 state 決定的 `ZStack` 以錯誤的
    /// 順序繪製」，而且是靜默的。AppKitBackend 與 WinUIBackend 也會重排它們的 view(分別是
    /// `subviews.swapAt` 與一組移除／插入)。`gtk_widget_insert_after` 正是 GTK 4 用來在兄弟節點之間
    /// 安置 widget 的方式，而 sibling 傳入 `nil` 即代表置於首位。
    ///
    /// 此處是依陣列重建整個順序，而非只搬動那兩個。搬動兩個時，必須在「另一個也正在移動」的情況下
    /// 推算各自的新錨點，對於兩者相鄰的情形很容易出現細微的錯誤；而走訪整個陣列，正確與否一眼可
    /// 判，也會修復已經飄掉的順序，而不是在一個本來就錯的序列中交換兩個項目。一個 `Fixed` 只有寥寥
    /// 數個子元件，因此這點額外成本不值得換取更鋒利的邊角。
    public func swap(childAt firstIndex: Int, withChildAt secondIndex: Int, in container: Widget) {
        let container = container as! Fixed
        container.children.swapAt(firstIndex, secondIndex)

        var previous: Widget?
        for child in container.children {
            gtk_widget_insert_after(
                child.widgetPointer,
                container.widgetPointer,
                previous?.widgetPointer
            )
            previous = child
        }
    }

    public func createColorableRectangle() -> Widget {
        // The same passthrough widget the containers use, so a fully
        // transparent rectangle can decline the points it covers. See setColor.
        // 與各容器所使用的同一個 passthrough widget，如此完全透明的矩形便能放棄其所覆蓋的點。
        // 詳見 setColor。
        return PassthroughFixed()
    }

    public func setColor(
        ofColorableRectangle widget: Widget,
        to color: SwiftCrossUI.Color.Resolved
    ) {
        widget.css.set(property: .backgroundColor(color.gtkColor))

        // A fully transparent rectangle stops claiming the points it covers.
        //
        // Same rule as the containers: something that draws nothing does not
        // take the pointer from what is behind it. Without this, `Color.clear`
        // in a ZStack above a button swallows every click -- measured on P10,
        // where `Direct clicks` reached 2 while `Covered clicks` stayed at 0
        // with the overlay present, and the button worked the moment it was
        // removed. That is issue #454.
        //
        // Through the widget's own flag rather than `can-target`. `can-target`
        // belongs to `allowsHitTesting`, and having two things write it would
        // make the last writer win. The flag is read at hit time and combines
        // with the event-controller test, so `Color.clear` carrying a tap
        // gesture stays clickable whichever order the two are applied in.
        //
        // Set on every call rather than only when clear, because a colour
        // animating from transparent to opaque has to take clicks again.
        //
        // SwiftUI does let `Color.clear` take hits, with
        // `allowsHitTesting(false)` as the escape hatch. Diverging here is
        // deliberate and is what #454 asks for: a transparent layer that
        // silently eats input is the more surprising of the two behaviours, and
        // `allowsHitTesting` now exists for anyone who wants the other one.
        //
        // 完全透明的矩形不再攔截其所覆蓋的點。
        //
        // 與各容器同一條規則：不繪製任何內容的東西，不應從其後方的元件手中奪走指標。若無此段，
        // ZStack 中位於按鈕上方的 `Color.clear` 會吞掉每一次點擊——在 P10 實測，overlay 存在時
        // `Direct clicks` 達到 2 而 `Covered clicks` 停在 0，而移除 overlay 的當下按鈕即恢復正常。
        // 這就是 issue #454。
        //
        // 透過該 widget 自身的旗標而非 `can-target`。`can-target` 屬於 `allowsHitTesting`，若有
        // 兩處都寫入它，結果將取決於誰最後寫。此旗標於 hit 時讀取，並與 event controller 的判斷
        // 組合運作，因此帶有 tap gesture 的 `Color.clear` 無論兩者以何順序套用都仍可點擊。
        //
        // 每次呼叫都設定，而非僅在透明時設定，因為由透明漸變為不透明的顏色必須重新接收點擊。
        //
        // SwiftUI 確實讓 `Color.clear` 接收點擊，其逃生口是 `allowsHitTesting(false)`。此處刻意
        // 分歧，而這正是 #454 所要求的：「靜默吞掉輸入的透明圖層」是兩種行為中較令人意外的那一個，
        // 而想要另一種行為的人，現在已有 `allowsHitTesting` 可用。
        gtk_passthrough_fixed_set_opaque(widget.widgetPointer, color.opacity > 0 ? 1 : 0)
    }

    /// `can-target`, which GTK already defines as subtree-wide: hit testing
    /// skips a widget that cannot be targeted and does not descend into it.
    /// That is exactly `allowsHitTesting`'s meaning, so there is nothing to
    /// emulate.
    ///
    /// 使用 `can-target`，GTK 對它的定義本就及於整個子樹：hit testing 會略過無法被指定為目標的
    /// widget，也不會往其內部遞迴。這正是 `allowsHitTesting` 的語意，因此無需任何模擬。
    public func setHitTesting(of widget: Widget, to allowsHitTesting: Bool) {
        gtk_widget_set_can_target(widget.widgetPointer, allowsHitTesting ? 1 : 0)
    }

    public func createCornerRadiusContainer(wrapping child: Widget) -> Widget {
        // SwiftUI's cornerRadius rounds *and* clips: a child larger than the box
        // is cut to it (#389). AppKit does this with clipsToBounds and WinUI with
        // a geometric clip. Clip through the same ClipFixed the explicit
        // clipped() uses -- a plain overflow: hidden does not work here because
        // a GtkFixed over-allocates to an oversized child and then clips the
        // wrong box; the P17-DOE experiment showed this. ClipFixed clips to the
        // size SwiftCrossUI decided instead.
        let container = ClipFixed()
        container.put(child, x: 0, y: 0)
        return container
    }

    // The explicit counterpart, clipped(), through the same clipping container.
    public func createClippedContainer() -> Widget {
        ClipFixed()
    }

    public func setCornerRadius(of widget: Widget, to radius: Int) {
        // Two halves. The CSS rounds the border that is drawn, and the clip is
        // told to follow the same radius so the child is actually cut to the
        // rounded shape.
        //
        // A rectangular clip is exact only at radius 0 (P3's case): at any
        // larger radius an oversized child would keep square corners showing
        // underneath a rounded border. AppKit cuts to the shape with
        // clipsToBounds plus a layer corner radius, and WinUI with a
        // rounded-rectangle geometric clip.
        //
        // 分為兩半。CSS 負責把「繪製出來的邊框」變圓，而裁切則被告知依循同一個半徑，使子元件
        // 真的被裁成圓角形狀。
        //
        // 矩形裁切只有在半徑為 0 時才是正確的（P3 的情況）：只要半徑更大，超尺寸的子元件就會在圓角
        // 邊框之下留下方形的角。AppKit 以 clipsToBounds 搭配 layer 的圓角半徑裁成該形狀，WinUI 則以
        // 圓角矩形的幾何裁切為之。
        widget.css.set(property: .cornerRadius(radius))
        scui_clip_fixed_set_corner_radius(widget.widgetPointer, gint(radius))
    }

    public func naturalSize(of widget: Widget) -> SIMD2<Int> {
        let currentSize = widget.getSizeRequest()
        widget.setSizeRequest(width: -1, height: -1)
        let (width, height) = widget.getNaturalSize()
        widget.setSizeRequest(width: currentSize.width, height: currentSize.height)
        if let dropDown = widget as? DropDown {
            return SIMD2(width + dropDownWidestExtra(dropDown), height)
        }
        return SIMD2(width, height)
    }

    /// How much wider a menu picker is with its widest option than with the selected
    /// one. GtkDropDown measures only the selected item, so a picker showing "S" was
    /// 52 points wide beside an option 350 points long (P17); SwiftUI's menu picker,
    /// and AppKit's NSPopUpButton, take the widest option, so the width does not jump
    /// with the selection. Measured with the font of the dropdown's own label, where
    /// the picker's CSS puts it.
    /// menu picker 用最寬選項時比用目前選項時寬多少。GtkDropDown 只量選中的那一項，所以顯示「S」的 picker 只有
    /// 52 點寬，旁邊的選項卻有 350 點長(P17);SwiftUI 的 menu picker 與 AppKit 的 NSPopUpButton 都取最寬的選項，
    /// 寬度不會隨選取跳動。以 dropdown 自己那個 label 的字型量測，picker 的 CSS 就套在那裡。
    private func dropDownWidestExtra(_ dropDown: DropDown) -> Int {
        guard let model = dropDown.model else { return 0 }
        func label(in widget: UnsafeMutablePointer<GtkWidget>) -> UnsafeMutablePointer<GtkWidget>? {
            let instance = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GTypeInstance.self)
            if g_type_check_instance_is_a(instance, gtk_label_get_type()) != 0 {
                return widget
            }
            var child = gtk_widget_get_first_child(widget)
            while let current = child {
                if let found = label(in: current) { return found }
                child = gtk_widget_get_next_sibling(current)
            }
            return nil
        }
        let measuring = label(in: dropDown.widgetPointer) ?? dropDown.widgetPointer
        func textWidth(_ text: String) -> Int {
            guard let layout = gtk_widget_create_pango_layout(measuring, text) else { return 0 }
            var width: Int32 = 0
            var height: Int32 = 0
            pango_layout_get_pixel_size(layout, &width, &height)
            g_object_unref(UnsafeMutableRawPointer(layout))
            return Int(width)
        }
        var widest = 0
        var selected = 0
        var index: guint = 0
        while let item = gtk_string_list_get_string(model, index) {
            let width = textWidth(String(cString: item))
            widest = max(widest, width)
            if Int(index) == dropDown.selected { selected = width }
            index += 1
        }
        return max(0, widest - selected)
    }

    public func setSize(of widget: Widget, to size: SIMD2<Int>) {
        widget.setSizeRequest(width: size.x, height: size.y)
    }

    /// The sidebar width to open at when the content does not ask for more.
    ///
    /// Matches `defaultLeadingWidth` in AppKitBackend, so the two agree on what
    /// a navigation sidebar looks like before anyone drags it.
    static let defaultSidebarWidth = 200

    public func createSplitView(leadingChild: Widget, trailingChild: Widget) -> Widget {
        let widget = CustomPaned(orientation: .horizontal)
        let leadingContainer = wrapInCustomRootContainer(leadingChild)
        let trailingContainer = wrapInCustomRootContainer(trailingChild)

        widget.startChild = leadingContainer
        widget.endChild = trailingContainer
        widget.shrinkStartChild = false
        widget.shrinkEndChild = false

        // A starting guess only. The layout system reads sidebarWidth(ofSplitView:)
        // during layout, which runs before the first commit, so the divider needs
        // some value; setSidebarWidthBounds replaces it as soon as the sidebar's
        // real minimum and natural widths are known.
        widget.position = Self.defaultSidebarWidth
        return widget
    }

    public func setResizeHandler(
        ofSplitView splitView: Widget,
        to action: @escaping () -> Void
    ) {
        let splitView = splitView as! Paned
        splitView.notifyPosition = { _ in
            action()
        }
    }

    public func sidebarWidth(ofSplitView splitView: Widget) -> Int {
        let splitView = splitView as! CustomPaned
        return splitView.position
    }

    public func setSidebarWidthBounds(
        ofSplitView splitView: Widget,
        minimum minimumWidth: Int,
        maximum maximumWidth: Int
    ) {
        let splitView = splitView as! CustomPaned
        show(widget: splitView.startChild!)

        // Measured before the size requests below, which would otherwise floor
        // the natural width at whatever was just asked for and make it useless
        // as a measure of what the content wants.
        let naturalSidebarWidth = splitView.startChild?.getNaturalSize().width ?? 0

        // The caller derives the maximum from the total width minus the
        // trailing pane's minimum, which can fall below the leading pane's
        // minimum when the split view is cramped.
        let maximumWidth = max(minimumWidth, maximumWidth)

        // SplitView.commit calls setSize(of:to:) immediately before this, and
        // that writes layout.size into the widget's size request, so reading it
        // back gives the width the two panes have to divide up. getNaturalSize()
        // answers a different question -- what the content would like -- so
        // using it here made the trailing pane's minimum wrong, and negative
        // whenever the natural width came out under the maximum.
        let requestedWidth = splitView.getSizeRequest().width
        let totalWidth = requestedWidth > 0 ? requestedWidth : splitView.getNaturalSize().width

        splitView.startChild?.setSizeRequest(width: minimumWidth, height: 0)
        splitView.endChild?.setSizeRequest(width: max(0, totalWidth - maximumWidth), height: 0)

        if splitView.hasEstablishedPosition {
            // Respect a divider the user has dragged, but keep it in range.
            splitView.position = min(max(splitView.position, minimumWidth), maximumWidth)
        } else {
            // First layout with real numbers. The minimum is what the content
            // cannot go below; the width to *open* at is what it would like,
            // floored by the platform's navigation width so a sidebar of short
            // labels still looks like a sidebar rather than a sliver.
            let defaultWidth = max(naturalSidebarWidth, Self.defaultSidebarWidth)
            splitView.position = min(max(defaultWidth, minimumWidth), maximumWidth)
            splitView.hasEstablishedPosition = true
        }
    }

    public func createScrollContainer(for child: Widget) -> Widget {
        let scrollView = ScrolledWindow()
        scrollView.setChild(child)
        // Wrapped, so `.refreshable` can float a button over it (ScrollContainer).
        // 包起來，讓 `.refreshable` 能在上方浮一顆按鈕(ScrollContainer)。
        return ScrollContainer(scrollView)
    }

    public func updateScrollContainer(
        _ scrollView: Widget,
        environment: EnvironmentValues,
        bounceHorizontally: Bool,
        bounceVertically: Bool,
        hasHorizontalScrollBar: Bool,
        hasVerticalScrollBar: Bool
    ) {
        guard let scrollView = Self.scrolledWindow(of: scrollView) else { return }
        scrollView.setScrollBarPresence(
            hasVerticalScrollBar: hasVerticalScrollBar,
            hasHorizontalScrollBar: hasHorizontalScrollBar
        )
    }

    /// A virtualized GtkListView inside a bounded GtkScrolledWindow (#117).
    /// Natural-height propagation stays off so row count cannot enlarge the window.
    /// 以原生 factory 按需建列；保留 ScrolledWindow 的視口高度限制。
    public func createSelectableListView() -> Widget {
        let listView = Gtk.ListView()
        // No `navigation-sidebar` here, or every `List` would be drawn as a
        // sidebar whether it was one or not -- flat, no frame, sidebar row
        // padding. The style follows `listStyle`, in `updateSelectableListView`
        // below, which is where the environment is available.
        // 此處不加 `navigation-sidebar`,否則每一個 `List` 都會被畫成側邊欄——無邊框、扁平、採用側邊欄的
        // 列距——無論它是不是側邊欄。樣式跟隨 `listStyle`，於下方的 `updateSelectableListView` 中處理，
        // 因為 environment 在那裡才取得到。
        let scrolled = ScrolledWindow()
        scrolled.setChild(listView)
        // Vertical only. A horizontal scroll bar on a list would let rows be
        // narrower than the list, which is not what a `List` means anywhere
        // else in this framework.
        // 只有垂直方向。清單若出現水平捲軸，就等於允許列比清單本身還窄，而那不是 `List` 在本框架
        // 其他任何地方的意思。
        scrolled.setScrollBarPresence(
            hasVerticalScrollBar: true,
            hasHorizontalScrollBar: false
        )
        return scrolled
    }

    /// The `GtkListView` inside the scrolled window `createSelectableListView`
    /// returned.
    ///
    /// Force-unwrapped rather than optional-returning on purpose. Every caller
    /// received its argument from `createSelectableListView`, so a miss here is
    /// a framework bug and not a state a `List` can reach -- and an optional
    /// would turn that bug into a silently ignored update, which is the failure
    /// mode this whole task exists to remove.
    ///
    /// 位於 `createSelectableListView` 所回傳之 scrolled window 內部的那個 `GtkListView`。
    ///
    /// 刻意採強制解包而非回傳 optional。每一個呼叫端的引數都來自 `createSelectableListView`，
    /// 因此此處失手代表的是框架的 bug，而不是某個 `List` 到得了的狀態——而 optional 會把那個 bug
    /// 變成一次靜默被忽略的更新，那正是整個任務所要消除的失效樣態。
    func lazyList(of listView: Widget) -> Gtk.ListView {
        (listView as! ScrolledWindow).getChild() as! Gtk.ListView
    }

    /// Applies `listStyle`, which `SplitView` sets on its sidebar column.
    ///
    /// Set on every update rather than only when the value changes, because a
    /// list whose style is bound to state has to lose the class as well as gain
    /// it. `gtk_widget_remove_css_class` on a widget that does not have the
    /// class is a no-op, so the unconditional pair is safe.
    ///
    /// 套用 `listStyle`,`SplitView` 會在其側邊欄那一欄設定它。
    ///
    /// 每次更新都設定，而非僅在值變動時，因為樣式綁定於 state 的 list 不只要能取得該 class，也要能
    /// 失去它。對未持有該 class 的 widget 呼叫 `gtk_widget_remove_css_class` 為 no-op，因此這組
    /// 無條件的成對呼叫是安全的。
    public func updateSelectableListView(
        _ selectableListView: Widget,
        environment: EnvironmentValues
    ) {
        let selectableListView = lazyList(of: selectableListView)
        selectableListView.sensitive = environment.isEnabled

        let pointer = selectableListView.widgetPointer
        switch environment.backendListStyle {
            case .sidebar:
                gtk_widget_add_css_class(pointer, "navigation-sidebar")
            case .default:
                gtk_widget_remove_css_class(pointer, "navigation-sidebar")
        }
    }

    public func baseItemPadding(
        ofSelectableListView listView: Widget
    ) -> SwiftCrossUI.EdgeInsets {
        SwiftCrossUI.EdgeInsets()
    }

    public func minimumRowSize(ofSelectableListView listView: Widget) -> SIMD2<Int> {
        .zero
    }

    public func setItems(
        ofSelectableListView listView: Widget,
        to items: [Widget],
        withRowHeights rowHeights: [Int]
    ) {
        // Any mix of insertions and removals is fine: this body appends
        // nothing, it hands the list a provider closure over `items` and a
        // count, and GtkListView asks for whatever it needs.
        //
        // 插入與移除任意混用都沒有問題:**本函式不 append 任何東西**,它交給清單的是一個對 `items` 取值的
        // provider closure 與一個列數,而 GtkListView 需要什麼就來要什麼。

        let listView = lazyList(of: listView)
        listView.rowProvider = { index in
            guard items.indices.contains(index) else { return nil }
            return items[index]
        }
        listView.setRowCount(items.count)
        listView.refreshBoundRows()
    }

    public func setSelectionHandler(
        forSelectableListView listView: Widget,
        to action: @escaping (_ selectedIndex: Int) -> Void
    ) {
        lazyList(of: listView).onSelectionChange = { index in
            if let index { action(index) }
        }
    }

    public func setSelectedItem(ofSelectableListView listView: Widget, toItemAt index: Int?) {
        lazyList(of: listView).selectedIndex = index
    }

    public func createTooltipContainer(wrapping child: Widget) -> Widget {
        TooltipContainer(child)
    }

    public func updateTooltipContainer(_ widget: Widget, tooltip: String) {
        let widget = widget as! TooltipContainer
        widget.setTooltip(text: tooltip)
    }

    // MARK: Passive views

    public func createTextView() -> Widget {
        let textView = CustomLabel(string: "")
        textView.horizontalAlignment = .start
        textView.wrap = true
        textView.lineWrapMode = .wordCharacter
        textView.ellipsize = .end
        textView.yalign = 0.0
        return textView
    }

    public func updateTextView(
        _ textView: Widget,
        content: String,
        environment: EnvironmentValues
    ) {
        let textView = textView as! CustomLabel
        textView.label = content
        textView.justify =
            switch environment.multilineTextAlignment {
                case .leading:
                    Justification.left
                case .center:
                    Justification.center
                case .trailing:
                    Justification.right
            }

        textView.selectable = environment.isTextSelectionEnabled
        // A gradient is painted by the label's container with the glyphs as
        // its mask (gtk_text_paint.c), so the glyphs are drawn opaque. Below
        // GTK 4.14 there are no gradient nodes and the text takes the
        // gradient's middle colour, which `Text` sets as the foreground colour.
        // 漸層由 label 的容器以字形為遮罩畫出(gtk_text_paint.c),所以字形以不透明色繪製。GTK 4.14 以下沒有漸層節點，文字
        // 取漸層的中間色——`Text` 已把它設為前景色。
        var textEnvironment = environment
        if let gradient = environment.textGradient, gtk_passthrough_drawing_area_supports_shapes() != 0 {
            withShapePaint(gradient, flattenedTo: gradient.flattened(in: environment), environment: environment) {
                scui_widget_set_text_paint(textView.widgetPointer, $0)
            }
            textEnvironment = environment.with(\.foregroundColor, .black)
        } else {
            scui_widget_set_text_paint(textView.widgetPointer, nil)
        }
        // One assignment, so an unchanged style reloads nothing. Every widget's
        // provider is added for the whole display, so each load restyles every
        // widget, and `css.clear()` then `css.set(...)` loaded twice per update
        // even when nothing changed. P96 on Windows GTK, one Text changed per
        // frame: about 27 ms of each frame in GTK's layout phase, 25.0 / 27.7 /
        // 29.3 fps; with this, 46.0 / 55.0 / 56.0 (interleaved, 2026-10-23).
        // 只賦值一次，樣式未變就不重新載入。每個 widget 的 provider 都加在整個 display 上，所以每次載入都會重新替
        // 所有 widget 套樣式，而 `css.clear()` 再 `css.set(...)` 即使沒有任何改變，每次更新也載入兩次。Windows GTK
        // 上的 P96 每幀改一個 Text:每幀約 27 毫秒花在 GTK 的 layout 階段,25.0 / 27.7 / 29.3 fps;改成這樣後為
        // 46.0 / 55.0 / 56.0(交錯量測,2026-10-23)。
        textView.css.set(properties: cssProperties(for: textEnvironment), clear: true)
        scaleColourEmoji(in: textView, text: content, size: environment.resolvedFont.pointSize)
    }

    public func size(
        of text: String,
        whenDisplayedIn widget: Widget,
        proposedWidth: Int?,
        proposedHeight: Int?,
        environment: EnvironmentValues
    ) -> SIMD2<Int> {
        let ellipsize: EllipsizeMode
        if let widget = widget as? CustomLabel {
            ellipsize = widget.ellipsize
        } else if widget as? TextView != nil {
            // We don't ellipsize multi-line text editors
            ellipsize = .none
        } else {
            logger.warning(
                "\(#function) called with unexpected widget type \(type(of: widget))"
            )
            ellipsize = .none
        }

        let pango = widget is Gtk.Label ? Pango(likeLabel: widget) : Pango(for: widget)

        // A width that cannot hold one character holds one clipped line, as
        // NSTextField measures it (measured: width 0 or 1 gives one 16 pt line).
        // Pango wraps at every character instead, and P9's zero-width frame
        // became a hyphenated column that pushed the buttons below it down by
        // about 120 pt (2026-10-16).
        // 容不下一個字元的寬度，就容納一行被裁切的文字，與 NSTextField 的量測相同(實測：寬 0 或 1
        // 得到一行 16 pt)。Pango 則在每個字元處換行,P9 的零寬框變成一串加了連字號的直欄，把下方按鈕
        // 往下推了約 120 pt(2026-10-16)。
        if let proposedWidth, let first = text.first {
            let oneCharacter = pango.getTextSize(
                String(first),
                ellipsize: .none,
                proposedWidth: nil,
                proposedHeight: nil
            )
            if proposedWidth < oneCharacter.width {
                return SIMD2(max(proposedWidth, 0), oneCharacter.height)
            }
        }
        let (width, measuredHeight) = pango.getTextSize(
            text,
            ellipsize: proposedHeight == nil ? .none : ellipsize,
            proposedWidth: proposedWidth.map(Double.init),
            proposedHeight: proposedHeight.map(Double.init)
        )
        // Whole lines of one line's height, as AppKit sets them; see
        // ``wholeLineHeight(of:in:measuredHeight:ellipsize:proposedWidth:proposedHeight:)``.
        // 以單行高度計的整行，與 AppKit 排行相同；見 ``wholeLineHeight``。
        let height =
            (widget as? CustomLabel).map {
                wholeLineHeight(
                    of: text,
                    in: $0,
                    measuredHeight: measuredHeight,
                    ellipsize: proposedHeight == nil ? .none : ellipsize,
                    proposedWidth: proposedWidth,
                    proposedHeight: proposedHeight
                )
            } ?? measuredHeight

        // No line-limit handling here; `Text` applies it, for every backend,
        // from the font's line height. See the note in Text.computeLayout.
        // 此處不處理行數限制；`Text` 會為所有 backend 依字型行高統一套用。詳見 Text.computeLayout 中的說明。
        if let label = widget as? CustomLabel {
            if let inked = inkBox(of: text, in: label, proposedWidth: proposedWidth) {
                gtk_label_set_xalign(label.opaquePointer, 0)
                return inked
            }
            gtk_label_set_xalign(label.opaquePointer, 0.5)
        }
        return SIMD2(width, height)
    }

    /// The size of a single line whose drawing runs past its logical box, sized
    /// to what is drawn, with the label set to draw it from its leading edge.
    /// Pango on macOS reports Apple Color Emoji 20 points wide at 20 points while
    /// drawing it 26 wide and starting at the top of a 27-high line, so an emoji
    /// overflowed its label 6 to the right and sat 1 high: P103's circles had
    /// their emoji 2.5 points right of centre and 1.5 up, where AppKit, whose
    /// CoreText advance is 25, centres it. Sized as 2 x + width and 2 y + height
    /// of the ink box, the drawing is centred in the label, and the label is
    /// placed like any other.
    /// 單行文字畫出的範圍超出它的邏輯框時，改以畫出的範圍決定尺寸，並讓 label 從前緣開始畫。macOS 上的 Pango 在 20 點時
    /// 把 Apple Color Emoji 回報為 20 點寬，畫出來卻有 26 寬，且從 27 高的行的頂端開始，所以 emoji 往右溢出它的 label 6 點、
    /// 位置偏高 1 點:P103 圓圈裡的 emoji 偏右 2.5 點、偏上 1.5 點;AppKit 的 CoreText 字寬是 25,會把它置中。以 ink 框的
    /// 2 x + 寬與 2 y + 高決定尺寸，畫出的內容就在 label 中置中,label 本身則照常排版。
    private func inkBox(of text: String, in label: CustomLabel, proposedWidth: Int?) -> SIMD2<Int>? {
        guard !text.isEmpty, !text.contains("\n"),
            let template = gtk_label_get_layout(label.opaquePointer),
            let layout = pango_layout_copy(template)
        else { return nil }
        defer { g_object_unref(UnsafeMutableRawPointer(layout)) }
        // A copy of the label's own layout, so that the emoji scale on its
        // attributes (scaleColourEmoji) is measured too.
        // label 自己 layout 的複本，因此它屬性上的 emoji 縮放(scaleColourEmoji)也一併量到。
        pango_layout_set_text(layout, text, Int32(text.utf8.count))
        pango_layout_set_width(layout, -1)
        pango_layout_set_height(layout, -1)
        var ink = PangoRectangle()
        var logical = PangoRectangle()
        pango_layout_get_pixel_extents(layout, &ink, &logical)
        let inkWidth = Int(2 * ink.x + ink.width)
        guard ink.x >= 0, ink.y >= 0, ink.x + ink.width > logical.width + 1,
            proposedWidth.map({ $0 >= inkWidth }) ?? true
        else { return nil }
        return SIMD2(inkWidth, Int(2 * ink.y + ink.height))
    }

    /// The height of a wrapped paragraph when each line takes the height of its
    /// first line, rounded up to whole points, as AppKit sets
    /// lines. Pango sets a wrapped paragraph's lines at fractional heights, so
    /// three lines of the 13 pt system font measured 46 while one measured 16.
    /// `Text` takes a height that fills its proposal as clamped and keeps the
    /// whole lines of the one-line height that fit, so a paragraph proposed its
    /// own 46 kept 2 of its 3 lines and drew the second with an ellipsis (P17's
    /// "idealWidth 160 + fixedSize(h:)", where AppKit draws 3 lines in 48).
    /// 換行段落中每一行都取第一行的高度、無條件進位到整點時的總高度，與 AppKit 排行的方式相同。Pango 以小數高度
    /// 排列換行段落的各行，13 pt 系統字型三行量得 46,單獨一行卻是 16。`Text` 把填滿提議的高度視為被壓住的高度，只保留
    /// 放得下的整行(以單行高度計),所以一段被提議自己的 46 的文字只留下 3 行中的 2 行，第二行以刪節號結束(P17 的
    /// 「idealWidth 160 + fixedSize(h:)」;AppKit 以 48 畫出 3 行)。
    private func wholeLineHeight(
        of text: String,
        in label: CustomLabel,
        measuredHeight: Int,
        ellipsize: EllipsizeMode,
        proposedWidth: Int?,
        proposedHeight: Int?
    ) -> Int {
        guard !text.isEmpty, let template = gtk_label_get_layout(label.opaquePointer),
            let layout = pango_layout_copy(template)
        else { return measuredHeight }
        defer { g_object_unref(UnsafeMutableRawPointer(layout)) }
        pango_layout_set_text(layout, text, Int32(text.utf8.count))
        pango_layout_set_wrap(layout, PANGO_WRAP_WORD_CHAR)
        pango_layout_set_ellipsize(layout, ellipsize.toGtk())
        pango_layout_set_width(layout, proposedWidth.map { Int32($0) * PANGO_SCALE } ?? -1)
        pango_layout_set_height(layout, proposedHeight.map { Int32($0) * PANGO_SCALE } ?? -1)
        let lines = Int(pango_layout_get_line_count(layout))
        guard lines >= 2 else { return measuredHeight }

        var oneLine = PangoRectangle()
        pango_layout_line_get_extents(pango_layout_get_line_readonly(layout, 0), nil, &oneLine)
        let lineHeight = Int((Double(oneLine.height) / Double(PANGO_SCALE)).rounded(.up))
        return max(measuredHeight, lines * lineHeight)
    }

    public func createImageView() -> Widget {
        let imageView = Gtk.Picture()
        imageView.keepAspectRatio = false
        imageView.canShrink = true
        return imageView
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
        guard dataHasChanged else {
            return
        }

        let imageView = imageView as! Gtk.Picture
        let texture = Self.texture(fromStraightRGBA: rgbaData, width: width, height: height)
        imageView.setPaintable(texture)
    }

    /// The texture `updateImageView` shows: the bytes as they come, no
    /// premultiplying, because a `GdkPixbuf` with alpha is straight
    /// (non-premultiplied) RGBA by definition -- the opposite of AppKit, UIKit,
    /// Android and WinUI, which premultiply through `ImagePixels`. Measured
    /// 2026-10-09 on macOS (GTK 4.24.1): GDK hands (200, 0, 0, 128) back as
    /// premultiplied (100, 0, 0, 128), i.e. (227, 127, 127) over white; P84's
    /// half-transparent rects read src x a + bg x (1 - a) on screen. See
    /// `GtkImageAlphaTests`.
    ///
    /// `updateImageView` 顯示的 texture:位元組原樣交出、不預乘，因為帶 alpha 的 `GdkPixbuf` 依定義就是
    /// 未預乘 RGBA——與經 `ImagePixels` 預乘的 AppKit、UIKit、Android、WinUI 相反。2026-10-09 於 macOS
    /// (GTK 4.24.1)實測:GDK 把 (200, 0, 0, 128) 讀回為預乘的 (100, 0, 0, 128),即白底上的
    /// (227, 127, 127);P84 的半透明矩形在畫面上量得 src x a + bg x (1 - a)。見 `GtkImageAlphaTests`。
    static func texture(
        fromStraightRGBA rgbaData: [UInt8],
        width: Int,
        height: Int
    ) -> OpaquePointer {
        let buffer = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: rgbaData.count)
        memcpy(buffer.baseAddress!, rgbaData, rgbaData.count)
        let pixbuf = gdk_pixbuf_new_from_data(
            buffer.baseAddress,
            GDK_COLORSPACE_RGB,
            1,
            8,
            Int32(width),
            Int32(height),
            Int32(width * 4),
            { buffer, _ in
                buffer?.deallocate()
            },
            nil
        )
        return gdk_texture_new_for_pixbuf(pixbuf)!
    }

    // MARK: Controls

    // `createSimpleButton` and `updateSimpleButton` are in
    // `GtkBackend+Button.swift`, with the destructive-action style class and
    // its `deferToThemeStyleClass:` argument.
    //
    // `createSimpleButton` 與 `updateSimpleButton` 位於 `GtkBackend+Button.swift`，連同
    // destructive-action 樣式類別及其 `deferToThemeStyleClass:` 參數。

    public func createToggle() -> Widget {
        return Self.withoutFocusOnClick(ToggleButton())
    }

    public func updateToggle(
        _ toggle: Widget,
        label: String,
        environment: EnvironmentValues,
        onChange: @escaping (Bool) -> Void
    ) {
        let toggle = toggle as! Gtk.ToggleButton
        toggle.sensitive = environment.isEnabled
        toggle.label = label
        toggle.toggled = { widget in
            onChange(widget.active)
        }
        // This is a control, but we set isControl to false anyway because isControl overrides
        // the button background and makes the on and off states of the toggle look identical.
        toggle.css.set(properties: cssProperties(for: environment, isControl: false), clear: true)
    }

    public func setState(ofToggle toggle: Widget, to state: Bool) {
        let toggle = toggle as! Gtk.ToggleButton

        toggle.withBlockedSignal(named: "toggled") {
            toggle.active = state
        }
    }

    public func createSwitch() -> Widget {
        return Self.withoutFocusOnClick(Switch())
    }

    public func updateSwitch(
        _ switchWidget: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (Bool) -> Void
    ) {
        let switchWidget = switchWidget as! Gtk.Switch
        switchWidget.sensitive = environment.isEnabled
        switchWidget.notifyActive = { widget, _ in
            onChange(widget.active)
        }
    }

    public func setState(ofSwitch switchWidget: Widget, to state: Bool) {
        let switchWidget = switchWidget as! Gtk.Switch

        switchWidget.withBlockedSignal(named: "notify::active") {
            switchWidget.active = state
        }
    }

    public func createCheckbox() -> Widget {
        return Self.withoutFocusOnClick(Gtk.CheckButton())
    }

    public func updateCheckbox(
        _ checkboxWidget: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (Bool) -> Void
    ) {
        let checkboxWidget = checkboxWidget as! Gtk.CheckButton
        checkboxWidget.sensitive = environment.isEnabled
        checkboxWidget.notifyActive = { widget, _ in
            onChange(widget.active)
        }
    }

    public func setState(ofCheckbox checkboxWidget: Widget, to state: Bool) {
        let checkboxWidget = checkboxWidget as! Gtk.CheckButton

        checkboxWidget.withBlockedSignal(named: "notify::active") {
            checkboxWidget.active = state
        }
    }

    public func createSlider() -> Widget {
        let scale = Scale()
        scale.expandHorizontally = true

        // The controller that reports editing is added HERE, once, and only its
        // callbacks are replaced in `updateSlider`. This mirrors
        // `createTapGestureTarget`/`updateTapGestureTarget` below, which is the
        // established shape in this file for a controller whose closure has to
        // change on every update.
        //
        // Adding the controller in `updateSlider` instead adds a NEW one on
        // every view update and removes none: P61 reported `began=5` for a
        // SINGLE press -- not GTK firing five times, but five accumulated
        // controllers firing once each (2026-09-10). It compounds, because
        // `onEditingChanged` changes state, which schedules the update that adds
        // the next controller.
        //
        // 回報編輯狀態的控制器在**此處**加入，只加一次，而 `updateSlider` 只替換它的
        // callback。這與本檔下方的 `createTapGestureTarget`／`updateTapGestureTarget`
        // 同形——那是本檔中「closure 每次 update 都要更換的 controller」既有的寫法。
        //
        // 改在 `updateSlider` 裡加，等於每次 view update 都**新增**一個、且一個都不移除：P61 對
        // **單獨一次**按下回報 `began=5`——那不是 GTK 觸發了五次，而是五個累積下來的 controller
        // 各觸發一次(2026-09-10)。而且它會滾雪球，因為 `onEditingChanged` 會改變 state，而那正好
        // 排程了下一次「再加一個 controller」的 update。
        GtkSliderEditing.install(on: scale)

        return scale
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
        let slider = slider as! Scale
        slider.sensitive = environment.isEnabled
        slider.minimum = minimum
        slider.maximum = maximum
        slider.digits = decimalPlaces
        slider.valueChanged = { widget in
            onChange(widget.value)
        }

        // Began at the press and ended at the release, from a capture-phase
        // legacy controller: see `GtkSliderEditing` for why not a gesture. A
        // 2026-09-10 probe here (pressed 1, released 0, end 1) measured what a
        // GestureClick does once GtkScale claims the sequence -- and `end` came at
        // the claim, at the press, before the drag's values (P61, 2026-10-16).
        // 開始於按下、結束於放開，來自 capture 階段的 legacy 控制器：為何不用手勢見 `GtkSliderEditing`。
        // 2026-09-10 的探針(pressed 1、released 0、end 1)量到的是 GtkScale claim 序列後 GestureClick 的行為——
        // 而 `end` 在 claim 時、也就是按下時就來了，早於拖曳的值(P61,2026-10-16)。
        GtkSliderEditing.setHandler(on: slider, onEditingChanged)
    }

    public func setValue(ofSlider slider: Widget, to value: Double) {
        let slider = slider as! Scale

        slider.withBlockedSignal(named: "value-changed") {
            slider.value = value
        }
    }

    public func createTextField() -> Widget {
        let entry = Entry()
        // Its undo history is the framework's: see `TextUndoHistory`.
        // 它的復原歷史由框架保存:見 `TextUndoHistory`。
        TextUndoHistory.install(on: entry)
        return entry
    }

    public func updateTextField(
        _ textField: Widget,
        placeholder: String,
        environment: EnvironmentValues,
        onChange: @escaping (String) -> Void,
        onSubmit: @escaping () -> Void
    ) {
        let textField = textField as! Entry
        textField.sensitive = environment.isEnabled
        textField.placeholderText = placeholder
        textField.changed = { widget in
            TextUndoHistory.byPointer[UnsafeMutableRawPointer(widget.widgetPointer)]?
                .record(widget.text)
            onChange(widget.text)
        }
        textField.activate = { _ in
            onSubmit()
        }

        var properties = cssProperties(for: environment, isControl: true)
        // See `GtkBackend+TextFieldStyle.swift`. This also flips `has-frame`,
        // which is why it takes the entry and not just the style.
        // 見 `GtkBackend+TextFieldStyle.swift`。它同時會切換 `has-frame`，這正是它除了 style 之外
        // 還要收下該 entry 的原因。
        properties += textFieldStyleProperties(
            environment.backendTextFieldStyle,
            applyingTo: textField
        )
        textField.css.set(properties: properties, clear: true)
    }

    public func setContent(ofTextField textField: Widget, to content: String) {
        let textField = textField as! Entry
        textField.withBlockedSignal(named: "changed") {
            textField.text = content
        }
        TextUndoHistory.byPointer[UnsafeMutableRawPointer(textField.widgetPointer)]?
            .record(content, fromApp: true)
    }

    public func getContent(ofTextField textField: Widget) -> String {
        (textField as! Entry).text
    }

    public func createSecureField() -> Widget {
        let entry = Entry()
        entry.visibility = false
        return entry
    }

    public func updateSecureField(
        _ secureField: Widget,
        placeholder: String,
        environment: EnvironmentValues,
        onChange: @escaping (String) -> Void,
        onSubmit: @escaping () -> Void
    ) {
        updateTextField(
            secureField,
            placeholder: placeholder,
            environment: environment,
            onChange: onChange,
            onSubmit: onSubmit
        )
    }

    public func setContent(ofSecureField secureField: Widget, to content: String) {
        setContent(ofTextField: secureField, to: content)
    }

    public func getContent(ofSecureField secureField: Widget) -> String {
        getContent(ofTextField: secureField)
    }

    public func createTextEditor() -> Widget {
        let textEditor = Gtk.TextView()
        textEditor.wrapMode = .wordCharacter
        // Its undo history is the framework's, as a text field's: see `TextUndoHistory`.
        // 它的復原歷史與文字欄位一樣由框架保存:見 `TextUndoHistory`。
        TextUndoHistory.install(on: textEditor)
        return textEditor
    }

    public func updateTextEditor(
        _ textEditor: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (String) -> Void
    ) {
        let textEditor = textEditor as! Gtk.TextView

        // The text editor honours `.disabled` through `sensitive`, as every other
        // control does (see updateTextField, updateButton, updateDatePicker);
        // without it a TextEditor inside a `.disabled(true)` subtree stays
        // editable while looking the same as one that is not.
        //
        // text editor 與其他每一個控制項一樣，透過 `sensitive` 遵從 `.disabled`（見 updateTextField、
        // updateButton、updateDatePicker）；少了它，位於 `.disabled(true)` 子樹中的 TextEditor 仍可編輯，
        // 外觀卻與未被 disable 者相同。
        textEditor.sensitive = environment.isEnabled

        let undoKey = UnsafeMutableRawPointer(textEditor.widgetPointer)
        textEditor.buffer.changed = { buffer in
            TextUndoHistory.byPointer[undoKey]?.record(buffer.text)
            onChange(buffer.text)
        }

        textEditor.css.set(
            properties: cssProperties(for: environment, isControl: false)
                + [CSSProperty(key: "background", value: "none")],
            clear: true)
    }

    public func setContent(ofTextEditor textEditor: Widget, to content: String) {
        let textEditor = textEditor as! Gtk.TextView

        textEditor.buffer.withBlockedSignal(named: "changed") {
            textEditor.buffer.text = content
        }
        TextUndoHistory.byPointer[UnsafeMutableRawPointer(textEditor.widgetPointer)]?
            .record(content, fromApp: true)
    }

    public func getContent(ofTextEditor textEditor: Widget) -> String {
        let textEditor = textEditor as! Gtk.TextView
        return textEditor.buffer.text
    }

    public func createPicker(style: BackendPickerStyle) -> Widget {
        switch style {
            case .menu:
                return DropDown(strings: [])
            case .segmented:
                return SegmentedPicker()
            case .radioGroup:
                return RadioGroupPicker()
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
        if let picker = picker as? SegmentedPicker {
            picker.sensitive = environment.isEnabled
            picker.update(options: options)
            applyLabelStyles(to: picker, environment: environment)
            picker.onChange = onChange
            return
        } else if let picker = picker as? RadioGroupPicker {
            picker.sensitive = environment.isEnabled
            picker.update(options: options)
            applyLabelStyles(to: picker, environment: environment)
            picker.onChange = onChange
            return
        } else if let picker = picker as? WheelPicker {
            picker.sensitive = environment.isEnabled
            picker.update(options: options)
            applyLabelStyles(to: picker, environment: environment)
            picker.onChange = onChange
            return
        }

        let picker = picker as! DropDown
        picker.sensitive = environment.isEnabled

        // Check whether the options need to be updated or not (avoiding unnecessary updates is
        // required to prevent an infinite loop caused by the onChange handler)
        var hasChanged = false
        for index in 0..<options.count {
            guard
                let item = gtk_string_list_get_string(picker.model, guint(index)),
                String(cString: item) == options[index]
            else {
                hasChanged = true
                break
            }
        }

        // picker.model could be longer than options
        if gtk_string_list_get_string(picker.model, guint(options.count)) != nil {
            hasChanged = true
        }

        // Apply the current text styles to the dropdown's labels
        var block = CSSBlock(forClass: picker.css.cssClass + " label")
        block.set(properties: cssProperties(for: environment))
        picker.loadCSSText(from: block.stringRepresentation)

        guard hasChanged else {
            return
        }

        picker.model = gtk_string_list_new(
            UnsafePointer(
                options
                    .map({ UnsafePointer($0.unsafeUTF8Copy().baseAddress) })
                    .unsafeCopy()
                    .baseAddress
            )
        )

        picker.notifySelected = { picker, _ in
            if picker.selected == Int(Int32(bitPattern: GTK_INVALID_LIST_POSITION)) {
                onChange(nil)
            } else {
                onChange(picker.selected)
            }
        }
    }

    /// Styles the labels GTK draws inside a picker's own widgets.
    ///
    /// The environment's font and foreground colour belong on the labels, not
    /// on the picker itself, because the picker's node draws the control's
    /// frame and none of the text. Hence the descendant selector.
    private func applyLabelStyles(to picker: Widget, environment: EnvironmentValues) {
        var block = CSSBlock(forClass: picker.css.cssClass + " label")
        block.set(properties: cssProperties(for: environment))
        picker.loadCSSText(from: block.stringRepresentation)
    }

    public func setSelectedOption(ofPicker picker: Widget, to selectedOption: Int?) {
        if let picker = picker as? WheelPicker {
            picker.setSelectedIndex(to: selectedOption)
            return
        }
        if let picker = picker as? SegmentedPicker {
            picker.setSelectedIndex(to: selectedOption)
            return
        } else if let picker = picker as? RadioGroupPicker {
            picker.setSelectedIndex(to: selectedOption)
            return
        }

        let picker = picker as! DropDown
        if selectedOption != picker.selected {
            picker.selected = selectedOption ?? Int(Int32(bitPattern: GTK_INVALID_LIST_POSITION))
        }
    }

    public func createProgressSpinner() -> Widget {
        let spinner = Spinner()
        spinner.spinning = true
        return spinner
    }

    public func createProgressBar() -> Widget {
        ProgressBar()
    }

    /// The pulse timers driving indeterminate progress bars, by widget.
    /// 驅動不確定進度條的 pulse 計時器，以 widget 為索引。
    private var progressPulseTimers: [ObjectIdentifier: guint] = [:]

    /// Carries a progress bar into a C callback without keeping it alive.
    ///
    /// Weak on purpose: the timer outlives the widget if the view goes away
    /// before the timer is cancelled, and a strong reference would both leak the
    /// widget and let the callback pulse something no longer on screen.
    ///
    /// 將進度條帶入 C callback，但不延長其生命週期。
    ///
    /// 刻意使用弱引用：若 view 在計時器被取消前就消失，計時器會比 widget 活得更久，而強引用會
    /// 同時造成 widget 洩漏，並讓 callback 對一個已不在畫面上的東西呼叫 pulse。
    private final class ProgressBarBox {
        weak var progressBar: ProgressBar?

        init(_ progressBar: ProgressBar) {
            self.progressBar = progressBar
        }
    }

    /// Starts pulsing a progress bar, if it is not already.
    /// 開始 pulse 某個進度條（若尚未在 pulse）。
    private func startPulsing(_ progressBar: ProgressBar) {
        let key = ObjectIdentifier(progressBar)
        guard progressPulseTimers[key] == nil else { return }

        // 100ms is GTK's own cadence for this in its demos: fast enough to read
        // as motion, slow enough not to spend the frame budget on a widget that
        // is only saying "still working".
        // 100ms 是 GTK 自身範例採用的節奏：快到足以被讀成「在動」，又慢到不會為一個只是在說
        // 「還在處理」的 widget 耗掉繪製預算。
        let timer = g_timeout_add_full(
            0,
            100,
            { context in
                guard let context else { return 0 }
                let box = Unmanaged<ProgressBarBox>.fromOpaque(context).takeUnretainedValue()
                guard let progressBar = box.progressBar else {
                    // The widget is gone, so stop the timer rather than pulse a
                    // freed pointer. Weakly held for exactly this reason.
                    // widget 已不存在，因此停止計時器，而非對已釋放的指標呼叫 pulse。以弱引用持有
                    // 正是為了這個原因。
                    return 0
                }
                gtk_progress_bar_pulse(progressBar.opaquePointer)
                return 1
            },
            Unmanaged.passRetained(ProgressBarBox(progressBar)).toOpaque(),
            { context in
                guard let context else { return }
                Unmanaged<ProgressBarBox>.fromOpaque(context).release()
            }
        )
        progressPulseTimers[key] = timer
    }

    /// Stops pulsing a progress bar, so a determinate fraction can be shown.
    /// 停止 pulse 某個進度條，使其可顯示確定的進度值。
    private func stopPulsing(_ progressBar: ProgressBar) {
        let key = ObjectIdentifier(progressBar)
        guard let timer = progressPulseTimers.removeValue(forKey: key) else { return }
        g_source_remove(timer)
    }

    public func updateProgressBar(
        _ widget: Widget,
        progressFraction: Double?,
        environment: EnvironmentValues
    ) {
        let progressBar = widget as! ProgressBar

        // An indeterminate ProgressView -- one with no value -- has to animate,
        // or it reads as a bar stuck at zero rather than as work in progress.
        // GTK does not animate on its own: gtk_progress_bar_pulse moves the
        // block one step per call, so an indeterminate bar needs something
        // calling it on a timer. Setting `fraction` at all switches the widget
        // out of activity mode, so the two are mutually exclusive.
        //
        // AppKit flips isIndeterminate and calls startAnimation; WinUI sets
        // isIndeterminate. `fraction = fraction ?? 0` would be a filled-in 0%
        // bar.
        //
        // 不確定進度的 ProgressView（沒有值的那一種）必須要有動畫，否則看起來會像「卡在 0%」而
        // 非「進行中」。GTK 不會自行動畫：gtk_progress_bar_pulse 每呼叫一次才移動一格，因此不確定
        // 進度的 bar 需要有東西以計時器持續呼叫它。而只要設定了 `fraction`，該 widget 就會離開
        // activity mode，因此兩者互斥。
        //
        // AppKit 會切換 isIndeterminate 並呼叫 startAnimation；WinUI 設定 isIndeterminate。
        // `fraction = fraction ?? 0` 會是一條填滿 0% 的 bar。
        if let progressFraction {
            stopPulsing(progressBar)
            progressBar.fraction = progressFraction
        } else {
            startPulsing(progressBar)
        }
        let backgroundColor: Gtk.Color
        switch environment.colorScheme {
            case .light:
                backgroundColor = Gtk.Color.eightBit(61, 61, 61, 38)
            case .dark:
                backgroundColor = Gtk.Color.eightBit(90, 90, 90)
        }
        progressBar.loadCSSText(
            from: """
                trough {
                    background-color: \(CSSProperty.rgba(backgroundColor));
                }
                """
        )
    }

    public func createPopoverMenu() -> PopoverMenu {
        let menu = Gtk.PopoverMenu()
        menu.hasArrow = false
        GtkMenuKeyboardStart.attach(to: menu)
        return menu
    }

    public func updatePopoverMenu(
        _ menu: Menu,
        content: ResolvedMenu,
        environment: EnvironmentValues
    ) {
        // Update menu model and action handlers
        let actionGroup = Gtk.GSimpleActionGroup()
        menu.model = renderMenu(
            content,
            actionMap: actionGroup,
            actionNamespace: "menu",
            actionPrefix: nil,
            environment: environment
        )
        menu.insertActionGroup("menu", actionGroup)

        // These are Adwaita's own numbers, and they go on at
        // GTK_STYLE_PROVIDER_PRIORITY_APPLICATION, so applying them
        // unconditionally replaces every other theme's menu -- high contrast,
        // Yaru, Breeze -- with a guess the theme cannot answer. Measured
        // 2026-08-28 on P20: the popover interior was rgb(44,44,44), this
        // backend's value rather than the theme's.
        //
        // Cleared rather than merely skipped, because the provider outlives a
        // single update: a menu that stops needing the override has to stop
        // carrying it.
        guard !themeDraws(environment.colorScheme) else {
            menu.loadCSSText(from: "")
            return
        }

        // Compute styles
        let menuBackground: Gtk.Color
        let menuItemHoverBackground: Gtk.Color
        let foreground = environment.suggestedForegroundColor.resolve(in: environment).gtkColor
        switch environment.colorScheme {
            case .light:
                menuBackground = Gtk.Color(1, 1, 1)
                menuItemHoverBackground = Gtk.Color(0.9, 0.9, 0.9)
            case .dark:
                menuBackground = Gtk.Color(0.175, 0.175, 0.175)
                menuItemHoverBackground = Gtk.Color(1, 1, 1, 0.1)
        }

        // Set styles
        menu.loadCSSText(
            from: """
                contents {
                    background: \(CSSProperty.rgba(menuBackground));
                }
                contents modelbutton:hover, contents modelbutton:selected {
                    background: \(CSSProperty.rgba(menuItemHoverBackground));
                }
                contents modelbutton label {
                    color: \(CSSProperty.rgba(foreground));
                }
                contents modelbutton {
                    color: \(CSSProperty.rgba(foreground));
                }
                """
        )
    }

    public func showPopoverMenu(
        _ menu: Menu,
        at position: SIMD2<Int>,
        relativeTo widget: Widget,
        closeHandler handleClose: @escaping () -> Void
    ) {
        // Keys start where an NSMenu's do; see GtkMenuKeyboardStart.
        // 按鍵從 NSMenu 開始的地方開始；見 GtkMenuKeyboardStart。
        let keyboardStart = GtkMenuKeyboardStart.of(menu)
        keyboardStart?.willOpen()
        menu.popUpAtWidget(widget, relativePosition: position)
        keyboardStart?.didOpen()
        menu.onHide = {
            handleClose()
        }
    }

    public func createAlert() -> Alert {
        let dialog = Gtk.MessageDialog()

        // Register a custom shortcut controller to disable the default Escape-to-close
        // action. In future we'll probably want to conditionally re-enable this
        // shortcut in scenarios where we know which action button is the cancel action.
        let controller = gtk_shortcut_controller_new()
        let trigger = gtk_shortcut_trigger_parse_string("Escape")
        let action = gtk_callback_action_new({ _, _, _ in return 1 }, nil, { _ in })
        let shortcut = gtk_shortcut_new(trigger, action)
        gtk_shortcut_controller_add_shortcut(controller, shortcut)
        gtk_widget_add_controller(dialog.widgetPointer, controller)
        alertEscapeControllers[ObjectIdentifier(dialog)] = controller

        return dialog
    }

    public func updateAlert(
        _ alert: Alert,
        title: String,
        actionLabels: [String],
        environment: EnvironmentValues
    ) {
        alert.text = title
        for (i, label) in actionLabels.enumerated() {
            alert.addButton(label: label, responseId: i)
        }
        // One button: let Escape through to it (see `present`). The controller
        // `createAlert` added swallows Escape, so it comes off.
        // 一顆按鈕：讓 Escape 送到它(見 `present`)。`createAlert` 加上的控制器會吞掉 Escape,因此移除。
        if actionLabels.count == 1 {
            oneButtonAlerts.insert(ObjectIdentifier(alert))
            if let controller = alertEscapeControllers.removeValue(forKey: ObjectIdentifier(alert)) {
                gtk_widget_remove_controller(alert.widgetPointer, controller)
            }
        }
    }

    public func showAlert(
        _ alert: Alert,
        window: Window?,
        responseHandler handleResponse: @escaping (Int) -> Void
    ) {
        let target = window ?? windows[0]
        let key = ObjectIdentifier(target)

        // One alert per window on screen at a time, the latest on top: an alert
        // already up is hidden and comes back when this one is answered, so they
        // are answered newest first, as on AppKit (P5, #675: C, B, A).
        // 每個視窗同時只顯示一個 alert,最新的在上面：已顯示的那個先隱藏，等這個被回應後再回來，
        // 因此回應順序是由新到舊，與 AppKit 相同(P5、#675:C、B、A)。
        if let current = shownAlert[key], let currentHandler = shownAlertHandler[key] {
            current.hide()
            pendingAlerts[key, default: []].append((current, target, currentHandler))
        }

        present(alert, on: target, key: key, responseHandler: handleResponse)
    }

    private func present(
        _ alert: Alert,
        on target: Window,
        key: ObjectIdentifier,
        responseHandler handleResponse: @escaping (Int) -> Void
    ) {
        shownAlert[key] = alert
        shownAlertHandler[key] = handleResponse
        alert.response = { [weak self] _, responseId in
            var responseId = responseId
            // Escape on a one-button alert answers it with that button, as on AppKit
            // (P31): the button can mean nothing but "acknowledged". Alerts with more
            // buttons still ignore Escape until the cancel action can be told apart.
            // 只有一顆按鈕的 alert,Escape 以那顆按鈕回應，與 AppKit 相同(P31)。多顆按鈕的仍忽略 Escape。
            if responseId == Int(UInt32(bitPattern: -4)),
                self?.oneButtonAlerts.contains(ObjectIdentifier(alert)) == true
            {
                responseId = 0
            }
            guard responseId != Int(UInt32(bitPattern: -4)) else {
                // Ignore escape key for now. Once we support detecting
                // the primary and secondary actions of alerts we can wire
                // this up to whichever action is the default cancellation
                // action.
                return
            }

            alert.destroy()
            self?.oneButtonAlerts.remove(ObjectIdentifier(alert))
            self?.alertEscapeControllers[ObjectIdentifier(alert)] = nil
            self?.advanceAlerts(for: key)
            handleResponse(responseId)
        }
        alert.isModal = true
        alert.isDecorated = false
        alert.setTransient(for: target)
        alert.show()
    }

    /// Clears the shown alert for a window and presents the next one waiting on
    /// it, if any.
    private func advanceAlerts(for key: ObjectIdentifier) {
        shownAlert[key] = nil
        guard var queue = pendingAlerts[key], !queue.isEmpty else { return }
        // The most recent one waiting is the one that was on top before.
        // 等待中最新的那一個，就是之前在最上面的那一個。
        let next = queue.removeLast()
        pendingAlerts[key] = queue.isEmpty ? nil : queue
        present(next.alert, on: next.window, key: key, responseHandler: next.handler)
    }

    public func dismissAlert(_ alert: Alert, window: Window?) {
        // The alert may be the one on screen or still waiting in a queue.
        if let key = shownAlert.first(where: { $0.value === alert })?.key {
            alert.destroy()
            advanceAlerts(for: key)
            return
        }
        for (key, queue) in pendingAlerts {
            if let index = queue.firstIndex(where: { $0.alert === alert }) {
                var queue = queue
                queue.remove(at: index)
                pendingAlerts[key] = queue.isEmpty ? nil : queue
                break
            }
        }
        alert.destroy()
    }

    public func showOpenDialog(
        fileDialogOptions: FileDialogOptions,
        openDialogOptions: OpenDialogOptions,
        window: Window?,
        resultHandler handleResult: @escaping (DialogResult<[URL]>) -> Void
    ) {
        // GtkFileDialog picks the call rather than a mode flag: selecting
        // several files is a different entry point from selecting one, and
        // folders are a third.
        let kind: FileDialogKind = switch openDialogOptions.singleKindSelectionMode {
            case .files:
                openDialogOptions.allowMultipleSelections ? .openMultiple : .openSingle
            case .directories:
                .selectFolder
        }

        showFileChooserDialog(
            fileDialogOptions: fileDialogOptions,
            kind: kind,
            defaultFileName: nil,
            window: window ?? windows[0],
            resultHandler: handleResult
        )
    }

    public func showSaveDialog(
        fileDialogOptions: FileDialogOptions,
        saveDialogOptions: SaveDialogOptions,
        window: Window?,
        resultHandler handleResult: @escaping (DialogResult<URL>) -> Void
    ) {
        showFileChooserDialog(
            fileDialogOptions: fileDialogOptions,
            kind: .save,
            defaultFileName: saveDialogOptions.defaultFileName,
            window: window ?? windows[0]
        ) { result in
            switch result {
                case .success(let urls):
                    handleResult(.success(urls[0]))
                case .cancelled:
                    handleResult(.cancelled)
            }
        }

    }

    /// Which GtkFileDialog call a request maps to.
    private enum FileDialogKind {
        case openSingle
        case openMultiple
        case selectFolder
        case save
    }

    /// Carries the Swift result handler through GtkFileDialog's C callback.
    ///
    /// The async calls take a `gpointer` of user data, so the closure is boxed,
    /// passed as an opaque pointer and taken back out with a matching
    /// `takeRetainedValue`. That keeps it alive for exactly as long as the
    /// dialog is open, without the retain cycle the old GtkFileChooserNative
    /// code needed for the same purpose.
    private final class FileDialogRequest {
        let kind: FileDialogKind
        let handleResult: (DialogResult<[URL]>) -> Void

        init(kind: FileDialogKind, handleResult: @escaping (DialogResult<[URL]>) -> Void) {
            self.kind = kind
            self.handleResult = handleResult
        }
    }

    private func showFileChooserDialog(
        fileDialogOptions: FileDialogOptions,
        kind: FileDialogKind,
        defaultFileName: String?,
        window: Window?,
        resultHandler handleResult: @escaping (DialogResult<[URL]>) -> Void
    ) {
        // GtkFileDialog rather than GtkFileChooserNative, which the GIR marks
        // deprecated. The old API also does not close its dialog on Wayland
        // when no xdg-desktop-portal is present, as on stock WSLg: the response
        // arrives and the app gets the file, but the window stays on screen. A
        // stock GTK4 app using GtkFileDialog closes correctly in the same
        // session, which identifies the API rather than this backend's use of it.
        //
        // With xdg-desktop-portal installed under WSLg, GtkFileDialog hands the
        // dialog to xdg-desktop-portal-gtk, and systemd starts that without
        // DISPLAY or WAYLAND_DISPLAY: no dialog reaches the screen and the request
        // never completes. That is the session's environment, not this call, and
        // testapp's test_common.zsh `wslg_portal_display` repairs it before a run.
        // WSLg 裝了 xdg-desktop-portal 時,GtkFileDialog 會把對話框交給 xdg-desktop-portal-gtk,而 systemd
        // 啟動它時沒有 DISPLAY 也沒有 WAYLAND_DISPLAY:對話框到不了螢幕，請求也永遠不會完成。那是工作階段的
        // 環境，不是這個呼叫的問題;testapp 的 test_common.zsh `wslg_portal_display` 會在測試前修好它。
        let dialog = gtk_file_dialog_new()
        gtk_file_dialog_set_title(dialog, fileDialogOptions.title)
        gtk_file_dialog_set_accept_label(dialog, fileDialogOptions.defaultButtonLabel)
        gtk_file_dialog_set_modal(dialog, 1)

        if let initialDirectory = fileDialogOptions.initialDirectory {
            let folder = g_file_new_for_path(initialDirectory.path)
            gtk_file_dialog_set_initial_folder(dialog, folder)
            g_object_unref(UnsafeMutableRawPointer(folder))
        }

        if let defaultFileName {
            gtk_file_dialog_set_initial_name(dialog, defaultFileName)
        }

        // One filter per content type, by MIME type and by suffix, so a file
        // whose type GIO cannot sniff is still matched by its name; then "All
        // files" when other types are allowed. The first filter is the one
        // shown. Without filters every GTK file dialog offers every file and a
        // save has no type.
        // 每個內容型別一個 filter,依 MIME 型別也依副檔名，讓 GIO 判斷不出型別的檔案仍能以檔名符合；允許
        // 其他型別時再加「All files」。顯示的是第一個 filter。沒有 filter 時，每個 GTK 檔案對話框都提供所有
        // 檔案，儲存也沒有型別。
        if !fileDialogOptions.allowedContentTypes.isEmpty {
            let filters = g_list_store_new(gtk_file_filter_get_type())
            var filtersToAdd: [(
                name: String,
                mimeTypes: [String],
                suffixes: [String],
                patterns: [String]
            )] =
                fileDialogOptions.allowedContentTypes.map {
                    // Opening also takes the narrower types by suffix (`swift` for
                    // plain text): on Windows GIO types files by extension, so the
                    // MIME type alone does not reach them. A save keeps its own.
                    // 開檔時也依後綴接受較窄的型別(純文字的 `swift`):在 Windows 上 GIO 依副檔名判斷
                    // 型別，單靠 MIME 型別碰不到它們。存檔維持型別自己的副檔名。
                    (
                        $0.name,
                        $0.mimeTypes,
                        kind == .save ? $0.fileExtensions : $0.fileExtensions + $0
                            .conformingFileExtensions,
                        []
                    )
                }
            if fileDialogOptions.allowOtherContentTypes {
                filtersToAdd.append(("All files", [], [], ["*"]))
            }
            for (index, entry) in filtersToAdd.enumerated() {
                let filter = gtk_file_filter_new()
                gtk_file_filter_set_name(filter, entry.name)
                for mimeType in entry.mimeTypes {
                    gtk_file_filter_add_mime_type(filter, mimeType)
                }
                for suffix in entry.suffixes {
                    gtk_file_filter_add_suffix(filter, suffix)
                }
                for pattern in entry.patterns {
                    gtk_file_filter_add_pattern(filter, pattern)
                }
                g_list_store_append(filters, UnsafeMutableRawPointer(filter))
                if index == 0 {
                    gtk_file_dialog_set_default_filter(dialog, filter)
                }
                g_object_unref(UnsafeMutableRawPointer(filter))
            }
            gtk_file_dialog_set_filters(dialog, filters)
            g_object_unref(UnsafeMutableRawPointer(filters))
        }

        let request = FileDialogRequest(kind: kind, handleResult: handleResult)
        let userData = Unmanaged.passRetained(request).toOpaque()
        let parent: UnsafeMutablePointer<GtkWindow>? = (window ?? windows.first)?
            .widgetPointer.cast()

        let callback: GAsyncReadyCallback = { source, result, userData in
            guard let userData else { return }
            let request = Unmanaged<FileDialogRequest>.fromOpaque(userData)
                .takeRetainedValue()
            // GtkFileDialog has no named Swift type; it arrives as an opaque
            // pointer, which is what the _finish calls expect.
            let dialog = OpaquePointer(source)

            var error: UnsafeMutablePointer<GError>? = nil
            var urls: [URL] = []

            switch request.kind {
                case .openMultiple:
                    if let list = gtk_file_dialog_open_multiple_finish(dialog, result, &error) {
                        let count = g_list_model_get_n_items(list)
                        for index in 0..<count {
                            guard let item = g_list_model_get_item(list, index) else { continue }
                            if let path = g_file_get_path(OpaquePointer(item)) {
                                urls.append(URL(fileURLWithPath: String(cString: path)))
                                g_free(path)
                            }
                            g_object_unref(item)
                        }
                        g_object_unref(UnsafeMutableRawPointer(list))
                    }
                case .openSingle, .selectFolder, .save:
                    let file =
                        switch request.kind {
                            case .selectFolder:
                                gtk_file_dialog_select_folder_finish(dialog, result, &error)
                            case .save:
                                gtk_file_dialog_save_finish(dialog, result, &error)
                            default:
                                gtk_file_dialog_open_finish(dialog, result, &error)
                        }
                    if let file {
                        if let path = g_file_get_path(file) {
                            urls.append(URL(fileURLWithPath: String(cString: path)))
                            g_free(path)
                        }
                        g_object_unref(UnsafeMutableRawPointer(file))
                    }
            }

            // A dismissed dialog reports an error rather than an empty result,
            // so anything that produced no URLs is treated as a cancellation.
            // That covers the dismissal case and any failure to read the
            // selection back, neither of which the caller can act on
            // differently.
            if let error {
                g_error_free(error)
            }

            if urls.isEmpty {
                request.handleResult(.cancelled)
            } else {
                request.handleResult(.success(urls))
            }
        }

        switch kind {
            case .openSingle:
                gtk_file_dialog_open(dialog, parent, nil, callback, userData)
            case .openMultiple:
                gtk_file_dialog_open_multiple(dialog, parent, nil, callback, userData)
            case .selectFolder:
                gtk_file_dialog_select_folder(dialog, parent, nil, callback, userData)
            case .save:
                gtk_file_dialog_save(dialog, parent, nil, callback, userData)
        }

        // The dialog holds itself for the duration of the async call, so the
        // reference taken by `new` can go now.
        g_object_unref(UnsafeMutableRawPointer(dialog))
    }

    public func createTapGestureTarget(wrapping child: Widget, gesture: TapGesture) -> Widget {
        var gtkGesture: GestureSingle
        switch gesture.kind {
            case .primary:
                gtkGesture = GestureClick()
            case .secondary:
                gtkGesture = GestureClick()
                gtk_gesture_single_set_button(gtkGesture.opaquePointer, guint(GDK_BUTTON_SECONDARY))
            case .longPress:
                gtkGesture = GestureLongPress()
        }
        child.addEventController(gtkGesture)
        return child
    }

    public func updateTapGestureTarget(
        _ tapGestureTarget: Widget,
        gesture: TapGesture,
        environment: EnvironmentValues,
        action: @escaping () -> Void
    ) {
        switch gesture.kind {
            case .primary:
                let gesture =
                    tapGestureTarget.eventControllers.first {
                        $0 is GestureClick
                            && gtk_gesture_single_get_button($0.opaquePointer) == GDK_BUTTON_PRIMARY
                    } as! GestureClick
                gesture.pressed = { _, nPress, _, _ in
                    guard environment.isEnabled, nPress == 1 else {
                        return
                    }
                    action()
                }
            case .secondary:
                let gesture =
                    tapGestureTarget.eventControllers.first {
                        $0 is GestureClick &&
                            (gtk_gesture_single_get_button($0.opaquePointer) ==
                                GDK_BUTTON_SECONDARY)
                    } as! GestureClick
                gesture.pressed = { _, nPress, _, _ in
                    guard environment.isEnabled, nPress == 1 else {
                        return
                    }
                    action()
                }
            case .longPress:
                let gesture =
                    tapGestureTarget.eventControllers.lazy.compactMap { $0 as? GestureLongPress }
                        .first!
                gesture.pressed = { _, _, _ in
                    guard environment.isEnabled else {
                        return
                    }
                    action()
                }
        }
    }

    public func createHoverTarget(wrapping child: Widget) -> Widget {
        child.addEventController(EventControllerMotion())
        return child
    }

    public func updateHoverTarget(
        _ hoverTarget: Widget,
        environment: EnvironmentValues,
        action: @escaping (Bool) -> Void
    ) {
        let gesture =
            hoverTarget.eventControllers.first { $0 is EventControllerMotion }
                as! EventControllerMotion
        gesture.enter = { _, _, _ in
            guard environment.isEnabled else { return }
            action(true)
        }
        gesture.leave = { _ in
            guard environment.isEnabled else { return }
            action(false)
        }
    }

    // MARK: Drag and drop

    public func createDropTarget(wrapping child: Widget) -> Widget {
        child.addEventController(DropTarget())
        return child
    }

    public func updateDropTarget(
        _ dropTarget: Widget,
        acceptedTypes: [DropType],
        environment: EnvironmentValues,
        onHover: @escaping (Bool) -> Void,
        onDrop: @escaping ([DropItem]) -> Bool
    ) {
        let target =
            dropTarget.eventControllers.first { $0 is DropTarget } as! DropTarget

        // Map the cross-platform type identifiers onto the two GTypes the GTK
        // drop target negotiates over. An unknown identifier is simply not
        // offered, so a drag of that type is refused rather than mishandled.
        let acceptsFiles = acceptedTypes.contains(.fileURL)
        let acceptsText = acceptedTypes.contains(.plainText)
        target.setAcceptedTypes(fileURLs: acceptsFiles, text: acceptsText)

        target.onHover = { hovering in
            guard environment.isEnabled else { return }
            onHover(hovering)
        }

        // GTK delivers the payload as one value of the negotiated type. Rebuild
        // the DropItem with the matching identifier and the bytes verbatim -- a
        // file drop keeps its text/uri-list form, which is the platform
        // difference P25 exists to show.
        target.onDrop = { kind, contents in
            guard environment.isEnabled else { return false }
            let item: DropItem
            switch kind {
                case .fileURIList:
                    item = DropItem(type: .fileURL, data: Data(contents.utf8))
                case .text:
                    item = DropItem(type: .plainText, data: Data(contents.utf8))
            }
            return onDrop([item])
        }
    }

    // MARK: Paths

    /// A drawing area that does not take clicks for a path it did not fill.
    ///
    /// Not a `DrawingArea()`, and that was task #111. A path widget covers the
    /// view it decorates, and a plain `GtkDrawingArea` claims every point in its
    /// allocation -- so `.border(_:width:)`, which is an overlaid stroked
    /// `Rectangle`, swallowed every click meant for what it surrounded. Measured
    /// with `gtk_widget_pick` inside P50's popover: the chain ended
    /// `GtkDrawingArea < GtkPassthroughFixed x7 < GtkPopoverContent`, with no
    /// button in it at all.
    ///
    /// Wrapped in a `DrawingArea` rather than given a Swift subclass of its own,
    /// because there is nothing for a subclass to add: the behaviour is entirely
    /// in the GObject class, and `renderPath` still needs the value to be a
    /// `Gtk.DrawingArea` for `setDrawFunc`.
    ///
    /// 一個不會為「自己並未填色的路徑」接下點擊的 drawing area。
    ///
    /// 不是 `DrawingArea()`,而這正是任務 #111。路徑 widget 覆蓋著它所裝飾的那個 view,而一般的
    /// `GtkDrawingArea` 會攔截其配置範圍內的每一個點——因此 `.border(_:width:)`(它是一個疊加其上、
    /// 帶描邊的 `Rectangle`)吞掉了每一次原本要給它所包圍之物的點擊。以 `gtk_widget_pick` 在 P50 的
    /// popover 內實測:該鏈以 `GtkDrawingArea < GtkPassthroughFixed ×7 < GtkPopoverContent` 作結,
    /// 其中**根本沒有按鈕**。
    ///
    /// 以 `DrawingArea` 包裝而非另立 Swift 子類別,因為子類別無事可做:行為完全位於 GObject 類別中,
    /// 而 `renderPath` 仍需要這個值是一個 `Gtk.DrawingArea` 才能呼叫 `setDrawFunc`。
    public func createPathWidget() -> Widget {
        DrawingArea(gtk_passthrough_drawing_area_new())
    }

    static let drawsShapesWithGsk =
        gtk_passthrough_drawing_area_supports_shapes() != 0
        && ProcessInfo.processInfo.environment["SCUI_GTK_CAIRO_PATHS"] != "1"

    public func createPath() -> Path {
        Path()
    }

    public func updatePath(
        _ path: Path,
        _ source: SwiftCrossUI.Path,
        bounds: SwiftCrossUI.Path.Rect,
        pointsChanged: Bool,
        environment: EnvironmentValues
    ) {
        path.path = source
    }

    /// Assumes that the path backing widget has already been given the correct
    /// size.
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

    /// The style-taking overload, which is where the drawing actually happens.
    ///
    /// Cairo needs no persuading here: a gradient is a `cairo_pattern_t` just as
    /// a flat colour is, so the only change from the two-colour version is which
    /// constructor makes the pattern. See `testapp/plan/plan-shape-styles.md`.
    ///
    /// 接收樣式的多載，實際繪製發生在此。
    ///
    /// Cairo 在此不需要任何說服：漸層與平面色同樣都是 `cairo_pattern_t`，因此與兩色版本唯一的
    /// 差別，只在於由哪一個建構函式產生該 pattern。見 `testapp/plan/plan-shape-styles.md`。
    public func renderPath(
        _ path: Path,
        container: Widget,
        strokeStyle fillStyleForStroke: ResolvedFillStyle,
        fillStyle: ResolvedFillStyle,
        overrideStrokeStyle: StrokeStyle?,
        environment: EnvironmentValues
    ) {
        let strokeColor = fillStyleForStroke.flattened(in: environment)
        let fillColor = fillStyle.flattened(in: environment)
        let drawingArea = container as! Gtk.DrawingArea

        // Whether this path takes clicks, decided by whether it fills anything.
        //
        // Set here rather than at creation because it depends on the style, and
        // the style arrives with every update: a shape whose fill is bound to
        // state has to be able to stop taking clicks as well as start.
        //
        // The flat colour is the right thing to read even for a gradient. A
        // gradient's `flattened` is its representative colour, and a gradient
        // with zero opacity throughout paints nothing -- the case this is
        // distinguishing -- while any visible gradient gives a visible flat
        // colour.
        //
        // 此路徑是否接下點擊,由「它有沒有填任何東西」決定。
        //
        // 設在此處而非建立時,因為它取決於樣式,而樣式在每次更新時都會送達:一個填色綁定於 state
        // 的形狀,必須既能「開始」也能「停止」接下點擊。
        //
        // 即使對漸層而言,讀取平面色也是正確的做法。漸層的 `flattened` 是它的代表色,而一個通篇
        // 零不透明度的漸層什麼都不會畫——那正是此處要分辨的情況——而任何看得見的漸層,都會給出一個
        // 看得見的平面色。
        gtk_passthrough_drawing_area_set_opaque(
            drawingArea.widgetPointer,
            fillColor.opacity > 0 ? 1 : 0
        )

        // We don't actually care about leaking backends, but might as well use
        // a weak reference anyway.
        // Room for what the stroke adds outside the path: half its width, or that
        // times the miter limit where joins are mitred. See
        // gtk_passthrough_drawing_area.c for the circle that was a rounded square.
        // 留給線條在路徑之外所增加的部分：線寬的一半；接合為 miter 時再乘上 miter limit。那個變成圓角方塊的圓見
        // gtk_passthrough_drawing_area.c。
        let outline = overrideStrokeStyle ?? path.path?.strokeStyle
        var overflow = 0.0
        if let outline, strokeColor.opacity > 0 {
            var reach = outline.width / 2
            if case .miter(let limit) = outline.join { reach *= max(limit, 1) }
            overflow = min(reach.rounded(.up) + 1, 256)
        }
        // GSK nodes where GTK has GskPath (GtkBackend+ShapePath.swift), unless
        // SCUI_GTK_CAIRO_PATHS=1 asks for the cairo draw function below, for
        // comparing the two. / GTK 有 GskPath 時用 GSK 節點(GtkBackend+ShapePath.swift);SCUI_GTK_CAIRO_PATHS=1
        // 時改用下方的 cairo 繪製函式，用來比較兩者。
        if Self.drawsShapesWithGsk, let source = path.path {
            setShape(
                source,
                on: drawingArea.widgetPointer,
                strokeStyle: overrideStrokeStyle ?? source.strokeStyle,
                strokeFill: fillStyleForStroke,
                strokeColor: strokeColor,
                fill: fillStyle,
                fillColor: fillColor,
                overflow: overflow,
                environment: environment
            )
            return
        }
        final class DrawBox {
            let draw: (OpaquePointer) -> Void
            init(_ draw: @escaping (OpaquePointer) -> Void) { self.draw = draw }
        }
        let draw: (OpaquePointer) -> Void = { [weak self] cairo in
            guard let self, let path = path.path else {
                return
            }

            let fillRule: cairo_fill_rule_t
            switch path.fillRule {
                case .evenOdd:
                    fillRule = CAIRO_FILL_RULE_EVEN_ODD
                case .winding:
                    fillRule = CAIRO_FILL_RULE_WINDING
            }
            cairo_set_fill_rule(cairo, fillRule)

            let strokeStyle = overrideStrokeStyle ?? path.strokeStyle
            let strokeCap: cairo_line_cap_t
            switch strokeStyle.cap {
                case .butt:
                    strokeCap = CAIRO_LINE_CAP_BUTT
                case .round:
                    strokeCap = CAIRO_LINE_CAP_ROUND
                case .square:
                    strokeCap = CAIRO_LINE_CAP_SQUARE
            }
            cairo_set_line_cap(cairo, strokeCap)

            let strokeJoin: cairo_line_join_t
            switch strokeStyle.join {
                case .bevel:
                    strokeJoin = CAIRO_LINE_JOIN_BEVEL
                case .miter(let limit):
                    strokeJoin = CAIRO_LINE_JOIN_MITER
                    cairo_set_miter_limit(cairo, limit)
                case .round:
                    strokeJoin = CAIRO_LINE_JOIN_ROUND
            }
            cairo_set_line_join(cairo, strokeJoin)

            cairo_set_line_width(cairo, strokeStyle.width)

            self.renderPathActions(path.actions, to: cairo)

            // The path's own extents, not the widget's. A gradient's unit points
            // are in the shape's space, which is what lets it be clipped to a
            // circle instead of filling a rectangle the way the gradient views
            // do -- that difference is the entire feature.
            // 使用路徑自身的範圍，而非 widget 的。漸層的單位座標位於形狀的空間中，這正是它能被裁進
            // 一個圓形、而非像漸層視圖那樣填滿一個矩形的原因——那個差別就是這項功能的全部。
            var x1 = 0.0
            var y1 = 0.0
            var x2 = 0.0
            var y2 = 0.0
            cairo_path_extents(cairo, &x1, &y1, &x2, &y2)
            let box = (x: x1, y: y1, width: x2 - x1, height: y2 - y1)

            let fillPattern = self.cairoPattern(
                for: fillStyle,
                flattenedTo: fillColor,
                in: box,
                environment: environment
            )
            cairo_set_source(cairo, fillPattern)
            cairo_fill_preserve(cairo)
            cairo_pattern_destroy(fillPattern)

            let strokePattern = self.cairoPattern(
                for: fillStyleForStroke,
                flattenedTo: strokeColor,
                in: box,
                environment: environment
            )
            cairo_set_source(cairo, strokePattern)
            cairo_stroke(cairo)
            cairo_pattern_destroy(strokePattern)
        }
        gtk_passthrough_drawing_area_set_overflowing_draw_func(
            drawingArea.widgetPointer,
            overflow,
            { _, cairo, _, _, data in
                Unmanaged<DrawBox>.fromOpaque(data!).takeUnretainedValue().draw(cairo!)
            },
            Unmanaged.passRetained(DrawBox(draw)).toOpaque(),
            { data in Unmanaged<DrawBox>.fromOpaque(data!).release() }
        )
    }

    /// Builds the Cairo pattern for a fill style, in the path's own coordinates.
    ///
    /// `flattenedTo` is passed in rather than recomputed so the flat case costs
    /// only one `cairo_pattern_create_rgba`, with no environment work inside the
    /// draw callback.
    ///
    /// 在路徑自身的座標系中，為一個填充樣式建立 Cairo pattern。
    ///
    /// `flattenedTo` 是傳入而非重新計算的，好讓平面色的情況只花一次
    /// `cairo_pattern_create_rgba`，且 draw callback 內不做任何 environment 相關的工作。
    private func cairoPattern(
        for style: ResolvedFillStyle,
        flattenedTo flat: SwiftCrossUI.Color.Resolved,
        in box: (x: Double, y: Double, width: Double, height: Double),
        environment: EnvironmentValues
    ) -> OpaquePointer? {
        func solid() -> OpaquePointer? {
            cairo_pattern_create_rgba(
                Double(flat.red),
                Double(flat.green),
                Double(flat.blue),
                Double(flat.opacity)
            )
        }

        // A zero-extent path has no space for a gradient to run across, and
        // Cairo would take the degenerate pattern without complaint. Falling
        // back to the flat colour keeps that from being an invisible shape.
        // 範圍為零的路徑沒有讓漸層延展的空間，而 Cairo 會毫無怨言地接受那個退化的 pattern。
        // 退回平面色可避免那變成一個看不見的形狀。
        guard box.width > 0, box.height > 0 else { return solid() }

        func addStops(_ pattern: OpaquePointer?, _ gradient: Gradient) {
            for stop in gradient.stops {
                let colour = stop.color.resolve(in: environment)
                cairo_pattern_add_color_stop_rgba(
                    pattern,
                    stop.location,
                    Double(colour.red),
                    Double(colour.green),
                    Double(colour.blue),
                    Double(colour.opacity)
                )
            }
        }

        switch style {
            case .color:
                return solid()
            case .linearGradient(let gradient, let start, let end):
                let pattern = cairo_pattern_create_linear(
                    box.x + start.x * box.width,
                    box.y + start.y * box.height,
                    box.x + end.x * box.width,
                    box.y + end.y * box.height
                )
                addStops(pattern, gradient)
                return pattern
            case .radialGradient(let gradient, let center, let startRadius, let endRadius):
                let cx = box.x + center.x * box.width
                let cy = box.y + center.y * box.height
                // Radii are points, as in SwiftUI's `RadialGradient`: not scaled
                // by the shape, so a circle stays a circle in any path.
                // 半徑以點為單位，與 SwiftUI 的 `RadialGradient` 相同：不隨形狀縮放，圓形在任何路徑中都是圓形。
                let pattern = cairo_pattern_create_radial(
                    cx,
                    cy,
                    startRadius,
                    cx,
                    cy,
                    endRadius
                )
                addStops(pattern, gradient)
                return pattern
            case .angularGradient(let gradient, let center, let startAngle, let endAngle):
                // Cairo has no conic gradient; a mesh of 72 patches, each a 5 degree
                // sector from the centre to a circle past every corner, its two edges
                // in the colours at their angles and its arc a Bezier. Angles as
                // SwiftUI's: from three o'clock, clockwise in cairo's y-down space.
                // Cairo 沒有錐形漸層：以 72 片 mesh 拼成，每片是從中心到一個超過每個角的圓的 5 度扇形，兩邊是各自角度的顏色，
                // 弧以 Bezier 曲線畫出。角度同 SwiftUI:自三點鐘方向起，在 cairo 的 y 向下座標中順時針。
                let stops = ResolvedFillStyle.angularTurnStops(gradient, startAngle: startAngle, endAngle: endAngle)
                    .map { ($0.location, $0.color.resolve(in: environment)) }
                guard !stops.isEmpty else { return solid() }
                let cx = box.x + center.x * box.width
                let cy = box.y + center.y * box.height
                let reach = [(box.x, box.y), (box.x + box.width, box.y), (box.x, box.y + box.height),
                             (box.x + box.width, box.y + box.height)]
                    .map { hypot($0.0 - cx, $0.1 - cy) }.max()! + 1
                func colour(_ t: Double) -> SwiftCrossUI.Color.Resolved {
                    if t <= stops[0].0 { return stops[0].1 }
                    guard let i = stops.firstIndex(where: { $0.0 > t }) else { return stops[stops.count - 1].1 }
                    let (l0, c0) = stops[i - 1], (l1, c1) = stops[i]
                    let f = Float(l1 > l0 ? (t - l0) / (l1 - l0) : 1)
                    return SwiftCrossUI.Color.Resolved(
                        red: c0.red + (c1.red - c0.red) * f, green: c0.green + (c1.green - c0.green) * f,
                        blue: c0.blue + (c1.blue - c0.blue) * f, opacity: c0.opacity + (c1.opacity - c0.opacity) * f
                    )
                }
                let pattern = cairo_pattern_create_mesh()
                let patches = 72
                let step = 2 * Double.pi / Double(patches)
                let k = 4.0 / 3.0 * tan(step / 4) * reach
                for i in 0..<patches {
                    let a0 = startAngle.radians + Double(i) * step, a1 = a0 + step
                    let c0 = colour(Double(i) / Double(patches)), c1 = colour(Double(i + 1) / Double(patches))
                    cairo_mesh_pattern_begin_patch(pattern)
                    cairo_mesh_pattern_move_to(pattern, cx, cy)
                    cairo_mesh_pattern_line_to(pattern, cx + cos(a0) * reach, cy + sin(a0) * reach)
                    cairo_mesh_pattern_curve_to(
                        pattern,
                        cx + cos(a0) * reach - sin(a0) * k, cy + sin(a0) * reach + cos(a0) * k,
                        cx + cos(a1) * reach + sin(a1) * k, cy + sin(a1) * reach - cos(a1) * k,
                        cx + cos(a1) * reach, cy + sin(a1) * reach
                    )
                    cairo_mesh_pattern_line_to(pattern, cx, cy)
                    for (corner, c) in [(0, c0), (1, c0), (2, c1), (3, c1)] {
                        cairo_mesh_pattern_set_corner_color_rgba(
                            pattern, UInt32(corner), Double(c.red), Double(c.green), Double(c.blue), Double(c.opacity)
                        )
                    }
                    cairo_mesh_pattern_end_patch(pattern)
                }
                return pattern
        }
    }

    private func renderPathActions(
        _ actions: [SwiftCrossUI.Path.Action],
        to cairo: OpaquePointer
    ) {
        for action in actions {
            switch action {
                case .transform(let transform):
                    var matrix = cairo_matrix_t()
                    matrix.xx = transform.linearTransform.x
                    matrix.xy = transform.linearTransform.y
                    matrix.yx = transform.linearTransform.z
                    matrix.yy = transform.linearTransform.w
                    matrix.x0 = transform.translation.x
                    matrix.y0 = transform.translation.y
                    cairo_transform(cairo, &matrix)
                default:
                    break
            }
        }

        for (index, action) in actions.enumerated() {
            switch action {
                case .moveTo(let point):
                    cairo_move_to(cairo, point.x, point.y)
                case .lineTo(let point):
                    if index == 0 {
                        cairo_move_to(cairo, 0, 0)
                    }
                    cairo_line_to(cairo, point.x, point.y)
                case .quadCurve(let control, let end):
                    if index == 0 {
                        cairo_move_to(cairo, 0, 0)
                    }
                    var startX = 0.0
                    var startY = 0.0
                    cairo_get_current_point(cairo, &startX, &startY)
                    let start = SIMD2(startX, startY)
                    let control1 = (start + 2 * control) / 3
                    let control2 = (end + 2 * control) / 3
                    cairo_curve_to(
                        cairo,
                        control1.x,
                        control1.y,
                        control2.x,
                        control2.y,
                        end.x,
                        end.y
                    )
                case .cubicCurve(let control1, let control2, let end):
                    if index == 0 {
                        cairo_move_to(cairo, 0, 0)
                    }
                    cairo_curve_to(
                        cairo,
                        control1.x,
                        control1.y,
                        control2.x,
                        control2.y,
                        end.x,
                        end.y
                    )
                case .rectangle(let rect):
                    cairo_rectangle(
                        cairo,
                        rect.origin.x,
                        rect.origin.y,
                        rect.size.x,
                        rect.size.y
                    )
                case .circle(let center, let radius):
                    cairo_arc(cairo, center.x, center.y, radius, 0, 2 * .pi)
                case .arc(
                    let center,
                    let radius,
                    let startAngle,
                    let endAngle,
                    let clockwise
                ):
                    let arcFunc = clockwise ? cairo_arc : cairo_arc_negative
                    arcFunc(
                        cairo,
                        center.x,
                        center.y,
                        radius,
                        startAngle,
                        endAngle
                    )
                case .transform(let transform):
                    var matrix = cairo_matrix_t()
                    matrix.xx = transform.linearTransform.x
                    matrix.xy = transform.linearTransform.y
                    matrix.yx = transform.linearTransform.z
                    matrix.yy = transform.linearTransform.w
                    matrix.x0 = transform.translation.x
                    matrix.y0 = transform.translation.y
                    cairo_matrix_invert(&matrix)
                    cairo_transform(cairo, &matrix)
                case .subpath(let subpathActions):
                    renderPathActions(subpathActions, to: cairo)
            }
        }
    }

    // MARK: Tables

    // defaultTableRowContentHeight and defaultTableCellVerticalPadding are
    // declared near the top of this type, alongside the other backend
    // constants.
    // defaultTableRowContentHeight 與 defaultTableCellVerticalPadding 已在本型別開頭、與其他
    // backend 常數一同宣告。

    public func createTable() -> Widget {
        Gtk.Table()
    }

    public func headerHeight(ofTable table: Widget) -> Int {
        (table as! Gtk.Table).headerHeight
    }

    public func setRowCount(ofTable table: Widget, to rows: Int) {
        (table as! Gtk.Table).setRowCount(rows)
    }

    public func setColumnLabels(
        ofTable table: Widget,
        to labels: [String],
        environment: EnvironmentValues
    ) {
        let table = table as! Gtk.Table
        table.setColumnLabels(labels)
        table.css.set(properties: cssProperties(for: environment), clear: true)
    }

    public func setCells(
        ofTable table: Widget,
        to cells: [Widget],
        withRowHeights rowHeights: [Int]
    ) {
        (table as! Gtk.Table).setCells(cells, rowHeights: rowHeights)
    }

    public func setTextSelectability(ofTable table: Widget, to isSelectable: Bool) {
        (table as! Gtk.Table).setTextSelectable(isSelectable)
    }

    public func setColumnWidths(ofTable table: Widget, to widths: [Double?]) {
        (table as! Gtk.Table).setColumnWidths(widths)
    }

    public func createDatePicker() -> Widget {
        DatePickerWidget()
    }

    public func updateDatePicker(
        _ datePicker: Widget,
        environment: EnvironmentValues,
        date: Date,
        range: ClosedRange<Date>,
        components: DatePickerComponents,
        onChange: @escaping (Date) -> Void
    ) {
        let datePicker = datePicker as! DatePickerWidget
        // The month names, field order and AM/PM come from the calendar's
        // locale, and `environment.calendar` does not follow `\.locale`: P90 set
        // zh_TW and the wheels still said August (WSL and Windows GTK,
        // 2026-10-20). A changed locale makes the calendar differ, which
        // `update` already answers by rebuilding the contents.
        // 月份名稱、欄位順序與上午/下午取自 calendar 的 locale,而 `environment.calendar` 不會跟著
        // `\.locale` 變:P90 設了 zh_TW,滾輪仍寫 August(WSL 與 Windows GTK,2026-10-20)。locale
        // 改變會讓 calendar 不同,而 `update` 本來就會因此重建內容。
        var displayCalendar = environment.calendar
        displayCalendar.locale = environment.locale
        datePicker.update(
            date: date,
            range: range,
            style: environment.backendDatePickerStyle,
            components: components,
            displayCalendar: displayCalendar,
            timeZone: environment.timeZone,
            isEnabled: environment.isEnabled,
            onChange: onChange
        )

        // The grid keeps the `isControl` treatment it has always had, which
        // flattens the border and box-shadow away. The compact button does not
        // get it: it is a button, and stripping its border and shadow would
        // leave a floating word that does not look pressable.
        datePicker.applyStyles(
            toGrid: cssProperties(for: environment, isControl: true),
            toButton: cssProperties(for: environment)
        )

        // The font and foreground belong on the labels GTK draws inside, not on
        // the container, which draws none of the text. Hence the descendant
        // selector, the same one the pickers use.
        applyLabelStyles(to: datePicker, environment: environment)
    }

    // MARK: Helpers

    private func wrapInCustomRootContainer(_ widget: Widget) -> Widget {
        let container = CustomRootWidget()
        container.setChild(to: widget)
        return container
    }

    /// Whether the GTK theme on screen right now draws the colour scheme the
    /// application asked for.
    ///
    /// When it does, this backend has nothing to add, and every property it
    /// leaves unset is one the theme gets to decide. Compared against
    /// `gtkPrefersDarkTheme`, which tracks what this backend last wrote into
    /// GTK's settings, rather than the startup sample in `ambientColorScheme`:
    /// the question is what is on screen now, not what was there at launch.
    /// `updateWindow` switches the theme itself to honour a
    /// `preferredColorScheme`, so the two normally agree.
    private func themeDraws(_ colorScheme: ColorScheme) -> Bool {
        (colorScheme == .dark) == gtkPrefersDarkTheme
    }

    /// The CSS this backend puts directly on a widget.
    ///
    /// Only what the application actually asked for, plus what the GTK theme
    /// currently on screen cannot supply on its own. Everything here is
    /// installed at GTK_STYLE_PROVIDER_PRIORITY_APPLICATION, which outranks the
    /// theme, so a property emitted here is one that no theme and no style class
    /// can ever change again. Emitting one the application never asked for
    /// spends that authority on a guess.
    /// Internal rather than `private` because `GtkBackend+Button.swift` needs
    /// it. Made `private`, the error points somewhere else entirely:
    /// `Self.cssProperties(...)` resolves to an unbound method reference, so the
    /// compiler complains that a `(EnvironmentValues, Bool, Bool) -> [CSSProperty]`
    /// is not a `[CSSProperty]`, which reads like a type mistake rather than an
    /// access one.
    ///
    /// 標記為 internal 而非 `private`，因為 `GtkBackend+Button.swift` 需要它。若改成 `private`，錯誤會指向
    /// 完全不同的地方：`Self.cssProperties(...)` 解析成一個未綁定的方法參考，於是編譯器抱怨
    /// `(EnvironmentValues, Bool, Bool) -> [CSSProperty]` 不是 `[CSSProperty]`，讀起來像是型別錯誤
    /// 而非存取權錯誤。
    func cssProperties(
        for environment: EnvironmentValues,
        isControl: Bool = false,
        deferToThemeStyleClass: Bool = false
    ) -> [CSSProperty] {
        let themeDrawsRequestedScheme = themeDraws(environment.colorScheme)

        var properties: [CSSProperty] = []
        if !deferToThemeStyleClass {
            // Only when the application named a colour, or when the theme is
            // drawing the wrong scheme. With neither, the theme's own `color` is
            // already correct, and setting it here would replace a system label
            // colour -- which has secondary, disabled and high-contrast variants
            // -- with flat black or white. See `suggestedForegroundColor`.
            let color =
                environment.foregroundColor
                    ?? (themeDrawsRequestedScheme ? nil : environment.suggestedForegroundColor)
            if let color {
                properties.append(.foregroundColor(color.resolve(in: environment).gtkColor))
            }
        }
        let font = environment.resolvedFont
        switch font.identifier.kind {
            case .system:
                properties.append(.fontSize(font.pointSize))
                // For some reason I had to tweak these a bit to make them match
                // up with AppKit's font weights. The Gtk3 backend, since
                // removed, needed no such tweaking; it matched SwiftUI's text
                // layout and rendering remarkably well.
                let weightNumber =
                    switch font.weight {
                        case .ultraLight:
                            200
                        case .thin:
                            300
                        case .light:
                            400
                        case .regular:
                            500
                        case .medium:
                            600
                        case .semibold:
                            700
                        case .bold:
                            700
                        case .heavy:
                            800
                        case .black:
                            900
                    }
                properties.append(.fontWeight(weightNumber))
                switch font.design {
                    case .monospaced:
                        properties.append(.fontFamily("monospace"))
                    case .default:
                        break
                }
        }

        if font.isItalic {
            properties.append(.fontStyle("italic"))
        }

        // A control's chrome, only when the theme is drawing the wrong scheme
        // -- the case it exists for, an app forcing a scheme the theme does not
        // match. The provider outranks the theme, so an explicit background
        // here beats every state and style class Adwaita ships -- `:hover`,
        // `:checked`, `.suggested-action`, `.destructive-action`. Applied
        // unconditionally, a button carrying `suggested-action` rendered the
        // same flat rgb(73,73,73) as a plain one while `gtk_widget_has_css_class`
        // confirmed the class was on the widget (2026-08-28), and on P2, dark
        // Adwaita, the theme's distinct rgb(56,56,56) edge was lost.
        //
        // Not to be confused with the entry focus ring, which this block never
        // affects: GTK 4 draws that with `outline`, which is not set here.
        if isControl && !deferToThemeStyleClass && !themeDrawsRequestedScheme {
            switch environment.colorScheme {
                case .light:
                    properties.append(.backgroundColor(Color(0.9, 0.9, 0.9, 1)))
                case .dark:
                    properties.append(.backgroundColor(Color(1, 1, 1, 0.1)))
            }
            properties.append(CSSProperty(key: "border", value: "none"))
            properties.append(CSSProperty(key: "box-shadow", value: "none"))
        }

        return properties
    }

    static func controlBackgroundColor(for environment: borrowing EnvironmentValues) -> Gtk.Color {
        switch environment.colorScheme {
            case .light:
                Color(0.9, 0.9, 0.9, 1)
            case .dark:
                Color(1, 1, 1, 0.1)
        }
    }

    public func createSheet(content: Widget) -> Sheet {
        let sheet = Sheet()
        sheet.setChild(content)

        // Listen for interactive dismissals.
        //
        // Neither handler runs `onDismiss`; `dismissSheet(_:)` does, and it is
        // the only place that tears a sheet down. The programmatic entry point
        // `dismissSheet(_:window:parentSheet:)` -- the one `SheetModifier` calls
        // when `isPresented` goes false -- ends in `gtk_window_destroy`, which
        // does not emit `close-request` (`gtk_window_close` does; nothing here
        // uses it). So a callback run only from the block below would be
        // unreachable on the programmatic path.
        //
        // 監聽互動式關閉。
        //
        // 這兩個 handler 都不執行 `onDismiss`；由 `dismissSheet(_:)` 執行，而它是唯一會拆除 sheet 的地方。
        // 程式化的進入點 `dismissSheet(_:window:parentSheet:)`——也就是 `isPresented` 轉為 false 時
        // `SheetModifier` 所呼叫的那一個——最後走到的是 `gtk_window_destroy`，而它不會發出 `close-request`
        // （會發出的是 `gtk_window_close`，而此處沒有任何地方使用它）。因此只從下面這個區塊執行的回呼，
        // 在程式化那條路上會抵達不了。
        sheet.onCloseRequest = { [weak self, weak sheet] _ in
            guard let self, let sheet else {
                return
            }

            self.runInMainThread {
                self.dismissSheet(sheet)
            }
        }

        // Allow the escape key to be used to dismiss interactively dismissible
        // sheets.
        sheet.setEscapeKeyPressedHandler { [weak self, weak sheet] in
            guard let self, let sheet, !sheet.interactiveDismissDisabled else {
                return
            }

            self.runInMainThread {
                self.dismissSheet(sheet)
            }
        }

        return sheet
    }

    public func updateSheet(
        _ sheet: Sheet,
        window: Window,
        environment: EnvironmentValues,
        size: SIMD2<Int>,
        onDismiss: @escaping () -> Void,
        cornerRadius: Double?,
        detents: [PresentationDetent],
        dragIndicatorVisibility: Visibility,
        backgroundColor: SwiftCrossUI.Color.Resolved?,
        interactiveDismissDisabled: Bool
    ) {
        sheet.size = Size(width: size.x, height: size.y)
        sheet.onDismiss = onDismiss

        // Add a slight border to not be just a flat corner
        // Built whole and set once: each change of `css` reloads a provider the
        // whole display shares, so clear-then-set restyled every widget twice
        // (see updateTextView).
        // 先組好再一次設定:`css` 每改一次就重新載入整個 display 共用的 provider,先清空再設定會讓每個 widget
        // 重新套樣式兩次(見 updateTextView)。
        var sheetProperties: [CSSProperty] = [
            .border(
                color: SwiftCrossUI.Color.gray.resolve(in: environment).gtkColor,
                width: 1
            )
        ]

        // Respect corner radius and background Color
        let radius = cornerRadius.map(Int.init) ?? defaultSheetCornerRadius
        sheetProperties.append(.cornerRadius(radius))
        if let backgroundColor {
            sheetProperties.append(.backgroundColor(backgroundColor.gtkColor))
        }
        sheet.css.set(properties: sheetProperties, clear: true)

        sheet.interactiveDismissDisabled = interactiveDismissDisabled

        // - detents are only supported on mobile so we ignore them.
        // - dragIndicatorVisibility is only supported on mobile so we ignore it.
    }

    /// Nothing to lift: a GTK sheet window is sized by `updateSheet`, and a cover
    /// is given its window's size (P49 on macOS GTK fills the window).
    /// 沒有限制可拿掉:GTK 的 sheet 視窗由 `updateSheet` 決定大小，而 cover 拿到的是視窗的大小(macOS GTK 上的 P49 填滿視窗)。
    public func setPresentationFillsWindow(of sheet: Sheet, window: Window, _ fillsWindow: Bool) {}

    public func presentSheet(_ sheet: Sheet, window: Window, parentSheet: Sheet?) {
        let parent = parentSheet ?? window
        sheet.isModal = true
        sheet.isDecorated = false
        sheet.destroyWithParent = true
        if let parentSheet {
            parentSheet.nestedSheet = sheet
        }
        sheet.setTransient(for: parent)
        sheet.present()
    }

    /// The programmatic path: `SheetModifier` calling in because `isPresented`
    /// went false.
    ///
    /// It runs `onDismiss` via `dismissSheet(_:)` (issue #104). It does not fire
    /// twice for one dismissal -- `SheetModifier.commit`'s `else` branch is only
    /// entered when `isPresented` is already false and nils `children.sheet`
    /// immediately afterwards, and state updates are queued rather than
    /// delivered synchronously, so nothing re-enters that branch while this call
    /// is in progress. The argument is written out in full at the branch itself.
    ///
    /// 程式化的那條路：`SheetModifier` 因 `isPresented` 轉為 false 而呼叫進來。
    ///
    /// 它經由 `dismissSheet(_:)` 執行 `onDismiss`(issue #104)。它不會為同一次關閉觸發兩次——
    /// `SheetModifier.commit` 的 `else` 分支只有在 `isPresented` 已經為 false 時才會進入，且隨即把
    /// `children.sheet` 設為 nil，而 state 更新是排入佇列而非同步送達的，因此在本呼叫進行期間不會有
    /// 任何東西重入該分支。完整論證寫在該分支本身。
    public func dismissSheet(_ sheet: Sheet, window: Window, parentSheet: Sheet?) {
        dismissSheet(sheet)
        parentSheet?.nestedSheet = nil
    }

    /// Tears down a sheet and everything nested inside it.
    ///
    /// Reached from three places, and all three want the same thing: the
    /// `close-request` handler, the escape handler, and the public
    /// `dismissSheet(_:window:parentSheet:)` that `SheetModifier` calls. Each
    /// sheet involved gets destroyed once and notified once, whichever of the
    /// three arrived.
    ///
    /// 拆除一個 sheet，以及嵌在它裡面的一切。
    ///
    /// 有三處會抵達這裡，而三者要的是同一件事：`close-request` handler、escape handler，以及
    /// `SheetModifier` 所呼叫的公開 `dismissSheet(_:window:parentSheet:)`。無論是三者中的哪一個
    /// 抵達，牽涉到的每一個 sheet 都恰好被摧毀一次、被通知一次。
    private func dismissSheet(_ sheet: Sheet) {
        // Dismiss the nested sheets from the topmost down. We could use
        // recursion here, but then unbounded nested sheets would allow for
        // users to cause programs to run out of stack relatively easily.
        var nestedSheets: [Sheet] = []
        var currentSheet = sheet
        while let nestedSheet = currentSheet.nestedSheet {
            nestedSheets.append(nestedSheet)
            currentSheet = nestedSheet
        }
        for nestedSheet in nestedSheets.reversed() {
            tearDown(nestedSheet)
        }

        tearDown(sheet)
    }

    /// Destroys one sheet and runs its `onDismiss`, at most once per sheet.
    ///
    /// Destroy first, then notify, because `SheetModifier` documents the
    /// callback as running *after* the underlying UI framework has dismissed the
    /// sheet.
    ///
    /// The guard is not defensive decoration. Both interactive handlers in
    /// `createSheet` defer their work through `runInMainThread`, so an escape
    /// press and a `close-request` naming the same sheet queue two teardowns
    /// that each run on a later main loop iteration; without the flag the second
    /// would call `gtk_window_destroy` on an already-destroyed window and run
    /// the caller's closure a second time. The flag is also what lets the
    /// programmatic path share this function with the interactive ones at all.
    ///
    /// 摧毀單一 sheet 並執行它的 `onDismiss`，每個 sheet 至多一次。
    ///
    /// 先摧毀、再通知，因為 `SheetModifier` 的文件寫明該回呼是在底層 UI 框架關閉 sheet **之後**才
    /// 執行。
    ///
    /// 這個 guard 不是防禦性的裝飾。`createSheet` 中的兩個互動 handler 都透過 `runInMainThread`
    /// 延後其工作，因此一次 escape 按鍵與一次指向同一個 sheet 的 `close-request` 會排入兩次拆除，
    /// 而兩者各自在往後的某一輪 main loop 中執行；少了這個旗標，第二次會對一個已被摧毀的視窗呼叫
    /// `gtk_window_destroy`，並把呼叫端的 closure 再執行一次。這個旗標同時也正是「程式化那條路能與
    /// 互動那兩條路共用這個函式」的前提。
    private func tearDown(_ sheet: Sheet) {
        guard !sheet.hasBeenTornDown else {
            return
        }
        sheet.hasBeenTornDown = true

        sheet.destroy()
        sheet.onDismiss?()
    }

    public func size(ofSheet sheet: Sheet) -> SIMD2<Int> {
        return SIMD2(x: sheet.size.width, y: sheet.size.height)
    }
}

extension UnsafeMutablePointer {
    func cast<T>() -> UnsafeMutablePointer<T> {
        let pointer = UnsafeRawPointer(self).bindMemory(to: T.self, capacity: 1)
        return UnsafeMutablePointer<T>(mutating: pointer)
    }
}

/// A custom label subclass that supports ellipsizing multi-line text. Regular
/// `Label`s only display a single line of text when ellipsizing is enabled
/// because they don't pass their size request to their underlying Pango layout.
/// A `Paned` that remembers whether its divider has been placed using real
/// layout numbers yet.
///
/// The layout system treats the sidebar width as backend-owned state: it reads
/// `sidebarWidth(ofSplitView:)` and lays the panes out around whatever comes
/// back, only ever passing bounds the other way. Without this flag there is no
/// telling the initial guess apart from a width the user chose, so the divider
/// would either ignore its content forever or fight every drag.
class CustomPaned: Paned {
    var hasEstablishedPosition = false
}

/// Qualified as `Gtk.Label`, and it has to be.
///
/// `SwiftCrossUI.Label` was added on 2026-09-04 for SwiftUI parity. This file
/// imports both modules, so from that moment a bare `Label` here is ambiguous
/// and the compiler says so at the SUBCLASS line -- followed by a cascade
/// blaming `CustomLabel` for having no superclass and no members, which points
/// at this class rather than at the name clash that caused it.
///
/// Every other bare `Label` in GtkBackend is qualified for the same reason.
/// Do not "fix" a future recurrence by renaming the SwiftCrossUI view: `Label`
/// is the SwiftUI spelling, and parity is the whole point of it existing.
///
/// 限定為 `Gtk.Label`，而且必須如此。
///
/// `SwiftCrossUI.Label` 於 2026-09-04 為 SwiftUI parity 而新增。本檔案同時 import 兩個模組，
/// 因此自那時起，此處未限定的 `Label` 即為歧義，而編譯器會在**子類別那一行**報錯，接著串出一連串
/// 「`CustomLabel` 沒有父類別、沒有任何成員」的錯誤——那些訊息指向這個類別，而非指向真正的肇因：
/// 名稱衝突。
///
/// GtkBackend 中其餘未限定的 `Label` 也基於同樣理由一併限定。日後若再度發生，請勿以「改掉
/// SwiftCrossUI 那個 view 的名字」來「修正」它：`Label` 正是 SwiftUI 的寫法，而 parity 正是
/// 它存在的全部理由。
class CustomLabel: Gtk.Label {
    override func setSizeRequest(width: Int, height: Int) {
        super.setSizeRequest(width: width, height: height)

        // A label given no width draws nothing, as on AppKit. GTK will not size a
        // label below its minimum, which with ellipsizing is the "…" itself, so a
        // zero-width frame still showed one (P9, 2026-10-16). Not mapping it keeps
        // its size request and draws nothing.
        // 沒有寬度的 label 什麼也不畫，與 AppKit 相同。GTK 不會把 label 縮到最小寬度以下，而有省略時
        // 最小寬度就是「…」本身，所以零寬的框仍會顯示一個(P9,2026-10-16)。不映射它，保留尺寸要求而不繪製。
        gtk_widget_set_child_visible(widgetPointer, width > 0 ? 1 : 0)

        // Override the label's layout height. We do this so that the label grows
        // vertically to fill available space even though we have ellipsizing
        // enabled (which generally causes labels to limit themselves to a single line).
        //
        // This code relies on the assumption that the layout won't get recreated
        // until after the label gets rendered. The docs recommend against mutating
        // the layout returned by gtk_label_get_layout.
        //
        // Ideally we'd use an Inscription instead, because it has this behavior
        // by default, but that's only available from Gtk 4.8, and the predecessor
        // CellRendererText isn't a widget.
        let layout = gtk_label_get_layout(opaquePointer)
        pango_layout_set_height(
            layout,
            Int32(
                (Double(height) * Double(PANGO_SCALE))
                    .rounded(.towardZero)
            )
        )
    }
}

final class TooltipContainer: Fixed {
    private var tooltip: UnsafeMutableBufferPointer<CChar>

    init(_ child: Widget) {
        self.tooltip = UnsafeMutableBufferPointer(start: nil, count: 0)
        super.init()
        self.put(child, x: 0, y: 0)
    }

    deinit {
        deallocateText()
    }

    func setTooltip(text: String) {
        text.utf8CString.withUnsafeBufferPointer { buf in
            // TODO(bbrk24): Should this be `>=` or `==`?
            if tooltip.count >= buf.count {
                strcpy(tooltip.baseAddress!, buf.baseAddress!)
            } else {
                deallocateText()

                tooltip = .allocate(capacity: buf.count)
                tooltip.initialize(from: buf)
            }
        }

        gtk_widget_set_tooltip_text(widgetPointer, tooltip.baseAddress)
    }

    private func deallocateText() {
        if tooltip.count > 0 {
            tooltip.deinitialize()
            tooltip.deallocate()
        }

        tooltip = UnsafeMutableBufferPointer(start: nil, count: 0)
    }
}

// This class is incomplete and unused. It was meant to implement time components for DatePicker,
// but I couldn't get the spin buttons to work. TODOs include:
// - Fix the spin buttons
// - Update the strings in the AM/PM picker when the locale changes
// - Replace the calls to calendar.date(bySetting:value:of:) with something that actually does what we need
// - Implement range when possible
@available(macOS 13, *)
final class TimePicker: Box {
    private var hourCycle: Locale.HourCycle
    private let hourPicker: SpinButton
    // Qualified for the reason recorded at ``CustomLabel``: SwiftCrossUI now has
    // a Label of its own and a bare one here is ambiguous.
    // 依 ``CustomLabel`` 處所記錄的理由加以限定：SwiftCrossUI 現在自己也有一個 Label，
    // 此處未限定即為歧義。
    private let hourMinuteSeparator = Gtk.Label(string: ":")
    private let minutePicker = SpinButton(range: 0, max: 59, step: 1)
    private var minuteSecondSeparator: Gtk.Label?
    private var secondPicker: SpinButton?
    private var amPmPicker: DropDown?

    var onChange: ((Date) -> Void)?

    init() {
        let hourCycle = Locale.current.hourCycle

        self.hourCycle = hourCycle
        self.hourPicker = SpinButton(
            range: TimePicker.minHour(for: hourCycle),
            max: TimePicker.maxHour(for: hourCycle),
            step: 1
        )

        super.init(gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0))

        self.hourPicker.wrap = true
        self.hourPicker.orientation = .vertical
        self.hourPicker.numeric = true
        self.minutePicker.wrap = true
        self.minutePicker.orientation = .vertical
        self.minutePicker.numeric = true

        self.add(self.hourPicker)
        self.add(self.hourMinuteSeparator)
        self.add(self.minutePicker)
    }

    func setEnabled(to isEnabled: Bool) {
        hourPicker.sensitive = isEnabled
    }

    private static func minHour(for hourCycle: Locale.HourCycle) -> Double {
        switch hourCycle {
            case .zeroToEleven, .zeroToTwentyThree: 0
            case .oneToTwelve, .oneToTwentyFour: 1
            #if os(macOS)
                @unknown default: fatalError("Unrecognized hourCycle \(hourCycle)")
            #endif
        }
    }

    private static func maxHour(for hourCycle: Locale.HourCycle) -> Double {
        switch hourCycle {
            case .zeroToEleven: 11
            case .oneToTwelve: 12
            case .zeroToTwentyThree: 23
            case .oneToTwentyFour: 24
            #if os(macOS)
                @unknown default: fatalError("Unrecognized hourCycle \(hourCycle)")
            #endif
        }
    }

    func update(calendar: Foundation.Calendar, date: Date, showSeconds: Bool) {
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)

        if showSeconds {
            let secondsRange = calendar.range(of: .second, in: .minute, for: date) ?? 0..<60
            if let secondPicker {
                secondPicker.setRange(
                    min: Double(secondsRange.lowerBound),
                    max: Double(secondsRange.upperBound - 1)
                )
            } else {
                minuteSecondSeparator = Gtk.Label(string: ":")
                secondPicker = SpinButton(
                    range: Double(secondsRange.lowerBound),
                    max: Double(secondsRange.upperBound - 1),
                    step: 1
                )
                secondPicker!.numeric = true
                secondPicker!.wrap = true
                secondPicker!.text = "\(components.second!)"
                insert(child: minuteSecondSeparator!, after: minutePicker)
                insert(child: secondPicker!, after: minuteSecondSeparator!)
            }
        } else {
            if let minuteSecondSeparator {
                remove(minuteSecondSeparator)
                self.minuteSecondSeparator = nil
            }
            if let secondPicker {
                remove(secondPicker)
                self.secondPicker = nil
            }
        }

        let minutesRange = calendar.range(of: .minute, in: .hour, for: date) ?? 0..<60
        minutePicker.setRange(
            min: Double(minutesRange.lowerBound),
            max: Double(minutesRange.upperBound - 1)
        )
        minutePicker.text = "\(components.minute!)"
        minutePicker.valueChanged = { [unowned self] minutePicker in
            guard
                let value = Int(exactly: minutePicker.value),
                let newDate = calendar.date(bySetting: .minute, value: value, of: date)
            else {
                return
            }
            self.onChange?(newDate)
        }

        let hoursRange = calendar.range(of: .hour, in: .day, for: date)
        self.hourCycle = (calendar.locale ?? .current).hourCycle
        let effectiveHours = hoursRange?.map {
            TimePicker.transformToRange($0, hourCycle: self.hourCycle)
        }

        hourPicker.setRange(
            min: effectiveHours?.min().map(Double.init(_:))
                ?? TimePicker.minHour(for: self.hourCycle),
            max: effectiveHours?.max().map(Double.init(_:))
                ?? TimePicker.maxHour(for: self.hourCycle)
        )

        if self.hourCycle == .oneToTwelve || self.hourCycle == .zeroToEleven {
            if let amPmPicker {
                // update strings if necessary
            } else {
                amPmPicker = DropDown(strings: [calendar.amSymbol, calendar.pmSymbol])
                add(amPmPicker!)
            }
        } else {
            if let amPmPicker {
                remove(amPmPicker)
                self.amPmPicker = nil
            }
        }

        hourPicker.text =
            "\(TimePicker.transformToRange(components.hour!, hourCycle: self.hourCycle))"
        hourPicker.valueChanged = { [unowned self] hourPicker in
            guard
                let value = Int(exactly: hourPicker.value),
                let newDate = calendar.date(bySetting: .hour, value: value, of: date)
            else {
                return
            }
            self.onChange?(newDate)
        }
    }

    private static func transformToRange(_ value: Int, hourCycle: Locale.HourCycle) -> Int {
        switch hourCycle {
            case .zeroToEleven: value % 12
            case .oneToTwelve: (value + 11) % 12 + 1
            case .zeroToTwentyThree: value % 24
            case .oneToTwentyFour: (value + 23) % 24 + 1
            #if os(macOS)
                @unknown default: fatalError("Unrecognized hourCycle \(hourCycle)")
            #endif
        }
    }
}

/// A picker drawn as one horizontal strip of buttons, of which exactly one is
/// pressed -- SwiftUI's segmented control.
///
/// GTK has no segmented-control widget. What GNOME's own apps and the Adwaita
/// stylesheet use instead is a horizontal box carrying the `linked` style
/// class, which draws its children as a single continuous strip, filled with
/// toggle buttons that are grouped so only one of them can be active.
///
/// Two things about a GTK group are worth knowing, both measured against GTK
/// 4.22 rather than assumed, because the picker protocol asks about both:
///
/// - Switching selection emits `toggled` twice, first for the button being
///   turned off and then for the one being turned on, so a handler that does
///   not look at `active` reports the wrong index (or two indices).
/// - GTK refuses to deactivate a group's active member in response to a click,
///   but not in response to a programmatic `active = false`, which turns the
///   whole group off. So `setSelectedIndex(to: nil)` is expressible, while a
///   user clicking the selected segment to clear it is not -- and neither is
///   re-picking the option that is already selected, which emits nothing at
///   all. The dropdown style has the same blind spot for the same reason.
final class SegmentedPicker: Box {
    /// Reports a selection the user made. Deliberately not called for one
    /// applied by ``setSelectedIndex(to:)``: SwiftCrossUI writes the selection
    /// it already holds back into the picker on every layout pass, and
    /// reporting that back as a fresh choice would fight anything else trying
    /// to move the binding.
    var onChange: ((Int?) -> Void)?

    private var buttons: [ToggleButton] = []

    /// The index the picker believes is selected. Kept here rather than read
    /// back out of the buttons so that a redundant `setSelectedIndex(to:)` can
    /// be skipped entirely.
    private var selectedIndex: Int?

    /// Set while a selection is being applied programmatically. GTK emits
    /// `toggled` for such a change exactly as it does for a click, so this is
    /// what tells the two apart.
    private var isApplyingSelection = false

    init() {
        super.init(gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0))
        gtk_widget_add_css_class(widgetPointer, "linked")

        // Equal-width segments, as every platform's segmented control has.
        // Without this the widest label decides one segment's width and the
        // rest shrink to their own text.
        homogeneous = true
    }

    func update(options: [String]) {
        for (button, option) in zip(buttons, options) {
            button.label = option
        }

        if options.count > buttons.count {
            for option in options[buttons.count...] {
                let button = ToggleButton(label: option)

                // Grouping is what makes the strip a picker rather than a row
                // of independent toggles: GTK keeps at most one member active
                // and turns the previous one off itself. Every button joins the
                // group through the first one, which is the head that outlives
                // the others (options are only ever dropped from the end).
                button.setGroup(buttons.first)

                let index = buttons.count
                button.toggled = { [weak self] button in
                    self?.buttonToggled(button, at: index)
                }

                // Adding is what registers the `toggled` signal (see
                // Widget.parentWidget), so the handler has to be in place
                // first.
                add(button)
                buttons.append(button)
            }
        } else if options.count < buttons.count {
            for button in buttons[options.count...] {
                remove(button)
            }
            buttons.removeSubrange(options.count...)

            // The selected option may have been one of the removed ones, in
            // which case GTK has already dropped the selection and the picker
            // must agree, or the next setSelectedIndex(to:) would be skipped as
            // redundant.
            if let selectedIndex, selectedIndex >= buttons.count {
                self.selectedIndex = nil
            }
        }
    }

    func setSelectedIndex(to index: Int?) {
        guard index != selectedIndex else { return }
        selectedIndex = index

        isApplyingSelection = true
        defer { isApplyingSelection = false }

        if let index {
            buttons[index].active = true
        } else {
            // Turning the active member off clears the group; nothing else
            // expresses "no selection", which the picker protocol allows.
            for button in buttons where button.active {
                button.active = false
            }
        }
    }

    private func buttonToggled(_ button: ToggleButton, at index: Int) {
        guard !isApplyingSelection else { return }

        // The other half of the pair of signals a switch emits is the old
        // segment going inactive, which is not a selection.
        guard button.active else { return }

        selectedIndex = index
        onChange?(index)
    }
}

/// A picker drawn as a vertical column of radio buttons.
///
/// GTK 4 has no radio button widget: a `GtkCheckButton` that has been put in a
/// group draws a radio indicator instead of a check, and that is the whole of
/// it. The grouping semantics, and this picker's handling of them, are the same
/// as ``SegmentedPicker``'s -- see the notes there.
final class RadioGroupPicker: Box {
    /// Reports a selection the user made. Not called for one applied by
    /// ``setSelectedIndex(to:)``; see ``SegmentedPicker/onChange``.
    var onChange: ((Int?) -> Void)?

    private var buttons: [CheckButton] = []

    private var selectedIndex: Int?

    private var isApplyingSelection = false

    init() {
        super.init(gtk_box_new(GTK_ORIENTATION_VERTICAL, 0))
    }

    func update(options: [String]) {
        for (button, option) in zip(buttons, options) {
            button.label = option
        }

        if options.count > buttons.count {
            for option in options[buttons.count...] {
                let button = CheckButton(label: option)
                button.setGroup(buttons.first)

                let index = buttons.count
                button.toggled = { [weak self] button in
                    self?.buttonToggled(button, at: index)
                }

                add(button)
                buttons.append(button)
            }
        } else if options.count < buttons.count {
            for button in buttons[options.count...] {
                remove(button)
            }
            buttons.removeSubrange(options.count...)

            if let selectedIndex, selectedIndex >= buttons.count {
                self.selectedIndex = nil
            }
        }
    }

    func setSelectedIndex(to index: Int?) {
        guard index != selectedIndex else { return }
        selectedIndex = index

        isApplyingSelection = true
        defer { isApplyingSelection = false }

        if let index {
            buttons[index].active = true
        } else {
            for button in buttons where button.active {
                button.active = false
            }
        }
    }

    private func buttonToggled(_ button: CheckButton, at index: Int) {
        guard !isApplyingSelection, button.active else { return }

        selectedIndex = index
        onChange?(index)
    }
}

/// The widget `createDatePicker()` hands back, whichever style the picker ends
/// up wearing.
///
/// `createDatePicker()` is given no style. The style arrives later, through
/// `environment.datePickerStyle` on the update path, by which point the widget
/// is already in the view tree -- so what `createDatePicker()` returns has to
/// be a container able to swap its contents when the style changes. That is the
/// shape WinUIBackend uses for the same reason
/// (`CustomDatePicker.changeDateView(to:)`).
///
/// It holds up to two things, per `DatePickerComponents`: the date, as either a
/// `GtkCalendar` grid or a ``CompactDatePicker``, and the time, as a
/// ``TimeRow``. Either may be absent, and a picker asked for neither is empty,
/// which is what was asked for.
///
/// # What a GtkCalendar can actually hold
///
/// The obvious implementation -- hand GTK a `GDateTime` and read one back -- is
/// wrong in three separate ways. All three were measured against GTK 4.22.4 and
/// then confirmed in `gtk/gtkcalendar.c`:
///
/// - `gtk_calendar_select_day` returns early unless the year, month or day
///   differs (`calendar_select_day_internal`). Setting the same day at a
///   different time of day, or in a different time zone, silently does nothing,
///   so the widget cannot be used to carry a time of day.
/// - Clicking a day rebuilds the value as
///   `g_date_time_new_local(year, month, day, 0, 0, 0)`
///   (`calendar_select_and_focus_day`): the time of day is discarded and the
///   *machine's* time zone is forced, whatever was set.
/// - `day-selected` fires for a programmatic set exactly as for a click, so a
///   handler that does not tell the two apart reports the app's own writes back
///   into the binding.
///
/// The way past all three is to treat a `GtkCalendar` as storing a year, month
/// and day and nothing else. This class keeps the bound `Date` itself and
/// rebuilds it from the widget's day plus its own time of day, resolved in
/// `environment.timeZone`. Nothing reads an instant back out of GTK.
///
/// # Where GTK's model does not reach
///
/// - `environment.calendar` cannot reach the grid. A `GtkCalendar` is
///   Gregorian, with no calendar-system property among its 43 properties, and
///   its month names come from the C locale rather than from anything the
///   caller passes. The grid is therefore always Gregorian; only the compact
///   style's label, which goes through a `DateFormatter`, honours the
///   environment's calendar.
/// - `range` cannot be enforced. `GtkCalendar` has no minimum or maximum date,
///   so out-of-range days stay clickable and the picker clamps afterwards --
///   which is what the protocol asks for anyway, since it calls `range` a hint.
/// - GTK keeps the browsed month in the very same field as the selection, and
///   emits no `day-selected` when the header arrows move it. Browsing is
///   therefore invisible to SwiftCrossUI, which is right -- browsing is not
///   choosing -- but it also means the widget's idea of "the date" drifts away
///   from the binding while a user is looking around. Measured: browse to
///   February, change some unrelated state, and the next layout pass writes the
///   binding back and returns the grid to March mid-decision. There is no fix
///   short of not using `GtkCalendar`, because one field is being asked to hold
///   two things. Browsing away from the 31st is the same fault with teeth: GTK
///   clamps the day (`g_date_time_add_months`) and emits nothing, so the widget
///   is showing a day nobody chose.
final class DatePickerWidget: Box {
    /// Reports a date the user picked. Deliberately not called for one applied
    /// by ``update(date:range:style:components:displayCalendar:timeZone:isEnabled:onChange:)``:
    /// SwiftCrossUI writes the date it already holds back into the picker on
    /// every layout pass, and GTK emits `day-selected` for that write just as it
    /// does for a click.
    private var onChange: ((Date) -> Void)?

    /// The shapes this picker knows how to wear. Narrower than `BackendDatePickerStyle`
    /// on purpose: several styles land on the same widget, and resolving them
    /// once keeps the swap keyed on what is actually built.
    private enum Presentation {
        /// A whole calendar grid, always visible.
        case grid
        /// A small button that opens the grid in a popover.
        case button
        /// One scrollable column per component. See ``DateWheel``.
        case wheel
    }

    /// What the picker is currently built out of. Compared as a whole so that
    /// one comparison decides whether anything has to be torn down.
    private struct Contents: Equatable {
        /// How the date is shown, or nil when `.date` was not asked for.
        var presentation: Presentation?
        /// Whether the time row is shown, and whether it has seconds.
        var time: TimeRow.Precision?
        /// The calendar the time row was built for. Part of the identity of the
        /// contents rather than something updated in place, because whether the
        /// row has an AM/PM dropdown at all depends on the calendar's locale.
        var calendar: Foundation.Calendar?
    }

    private var contents: Contents?
    private var grid: Gtk.Calendar?
    private var button: CompactDatePicker?
    private var wheel: DateWheel?
    private var timeRow: TimeRow?

    /// The bound date, as last handed in or last reported. The picker's own
    /// copy, because the widget cannot hold the time of day (see above).
    private var date = Date()

    private var range = Date.distantPast...Date.distantFuture

    /// Used for every conversion between ``date`` and the widget's day.
    /// Gregorian regardless of `environment.calendar`, because the grid is:
    /// feeding it, say, a Buddhist year would print 2569 over a Gregorian
    /// month.
    private var gregorian = Foundation.Calendar(identifier: .gregorian)

    /// Used only for the compact button's label, where a `DateFormatter` can
    /// honour a non-Gregorian calendar even though the grid cannot.
    private var displayCalendar = Foundation.Calendar.current
    private var timeZone = TimeZone.current

    /// Set while a date is being written into the widget. GTK emits
    /// `day-selected` for such a write exactly as it does for a click, so this
    /// is what tells the two apart.
    private var isApplyingDate = false

    private var labelFormatter: DateFormatter?

    init() {
        super.init(gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6))
        gregorian.timeZone = timeZone
    }

    func update(
        date: Date,
        range: ClosedRange<Date>,
        style: BackendDatePickerStyle,
        components: DatePickerComponents,
        displayCalendar: Foundation.Calendar,
        timeZone: TimeZone,
        isEnabled: Bool,
        onChange: @escaping (Date) -> Void
    ) {
        self.onChange = onChange
        self.date = date
        self.range = range

        // The formatter is rebuilt rather than reconfigured, and only when one
        // of its inputs moves: `update` runs on every layout pass, and building
        // a DateFormatter each time is not free.
        if self.timeZone != timeZone || self.displayCalendar != displayCalendar {
            labelFormatter = nil
        }
        self.timeZone = timeZone
        self.displayCalendar = displayCalendar
        gregorian.timeZone = timeZone

        install(
            Self.contents(for: style, components: components, calendar: displayCalendar)
        )

        sensitive = isEnabled
        applyDate()
    }

    /// Applies the styling the backend computed. Two sets, because the grid and
    /// the button want opposite things from the `isControl` treatment.
    func applyStyles(toGrid gridProperties: [CSSProperty], toButton buttonProperties: [CSSProperty])
    {
        if let grid {
            grid.css.set(properties: gridProperties, clear: true)
        }
        if let button {
            button.css.set(properties: buttonProperties, clear: true)
            // The grid in the popover is a grid, and gets the grid's treatment.
            button.grid.css.set(properties: gridProperties, clear: true)
        }
        if let timeRow {
            // A spin button keeps its frame for the same reason the compact
            // button does. The font and colour have to land here rather than on
            // the container, because a spin button's text sits in a `text` node
            // and the descendant `label` selector never reaches it.
            timeRow.css.set(properties: buttonProperties, clear: true)
        }
    }

    private static func contents(
        for style: BackendDatePickerStyle,
        components: DatePickerComponents,
        calendar: Foundation.Calendar
    ) -> Contents {
        let presentation: Presentation? =
            switch style {
                // `.automatic` is the compact button, as SwiftUI's `.automatic` is the
                // compact field on macOS and iOS and as GNOME apps show a date, so
                // that P41's `.automatic` and `.graphical` are different pictures.
                // `.automatic` 是精簡按鈕，與 SwiftUI 在 macOS、iOS 上 `.automatic` 為精簡欄位、以及 GNOME
                // app 顯示日期的方式一致，因此 P41 的 `.automatic` 與 `.graphical` 是兩張不同的圖。
                case .automatic, .compact:
                    .button
                case .graphical:
                    .grid
                case .wheel:
                    .wheel
            }

        // `hourMinuteAndSecond` includes `hourAndMinute`, by SwiftUI's bitfield
        // and by intent, so the wider one has to be tested first.
        let time: TimeRow.Precision? =
            if components.contains(.hourMinuteAndSecond) {
                .hourMinuteSecond
            } else if components.contains(.hourAndMinute) {
                .hourMinute
            } else {
                nil
            }

        return Contents(
            presentation: components.contains(.date) ? presentation : nil,
            time: time,
            // The wheel names its months from the calendar too, so it needs it as
            // much as the time row does: a nil here never differs and never
            // rebuilds, and P90's date-only wheel kept English months after zh_TW
            // that way (Windows GTK, 2026-10-20).
            // 滾輪的月份名稱同樣取自 calendar,所以它和時間列一樣需要它：這裡的 nil 永遠不會不同，也就永遠不會重建,
            // P90 只有日期的滾輪就曾因此在 zh_TW 之後仍是英文月份(Windows GTK,2026-10-20)。
            calendar: time != nil || (components.contains(.date) && presentation == .wheel)
                ? calendar : nil
        )
    }

    /// Every way a `GtkCalendar`'s date changes, not only `day-selected`. The month
    /// and year arrows move the selected day into the new month, and clicking that
    /// day afterwards emits nothing because it is already selected -- so P41's
    /// picker showed 24 September highlighted while the binding still read
    /// 2025-08-24 (2026-10-16).
    /// `GtkCalendar` 日期改變的每一種方式，而不只是 `day-selected`。月份與年份箭頭會把選取的日子移到新的
    /// 月份，之後再點那一天不會發出任何訊號，因為它已經是選取狀態——於是 P41 的選擇器顯示 9 月 24 日被選取，
    /// 綁定卻仍是 2025-08-24(2026-10-16)。
    private func wireDateChanges(of grid: Gtk.Calendar) {
        let changed: (Gtk.Calendar) -> Void = { [weak self] grid in
            self?.daySelected(shownBy: grid)
        }
        grid.daySelected = changed
        grid.nextMonth = changed
        grid.prevMonth = changed
        grid.nextYear = changed
        grid.prevYear = changed
    }

    private func install(_ contents: Contents) {
        guard contents != self.contents else { return }
        self.contents = contents

        removeAll()
        grid = nil
        button = nil
        wheel = nil
        timeRow = nil

        switch contents.presentation {
            case .grid:
                let grid = Gtk.Calendar()
                wireDateChanges(of: grid)
                // Adding is what registers the signal (see Widget.parentWidget),
                // so the handler has to be in place first.
                add(grid)
                self.grid = grid
            case .button:
                let button = CompactDatePicker()
                wireDateChanges(of: button.grid)
                add(button)
                self.button = button
            case .wheel:
                // The year span is fixed rather than taken from `range`, which
                // the protocol calls a hint and which is unbounded by default --
                // a column from .distantPast to .distantFuture is not a widget.
                // Centred on the shown date so the current year is reachable
                // without scrolling for the ordinary case.
                // 年份範圍為固定值，而非取自 `range`：protocol 稱該範圍為「提示」，且預設是無界的
                // ——一個從 .distantPast 排到 .distantFuture 的欄位不成其為 widget。此處以顯示中的
                // 日期為中心，使一般情況下無須捲動即可看到當年。
                let shownYear = gregorian.component(.year, from: date)
                let wheel = DateWheel(
                    calendar: contents.calendar ?? .current,
                    yearRange: (shownYear - 100)...(shownYear + 100)
                )
                wheel.onChange = { [weak self] date in
                    self?.wheelPicked(date)
                }
                add(wheel)
                self.wheel = wheel
            case nil:
                break
        }

        if let precision = contents.time {
            let timeRow = TimeRow(precision: precision, calendar: contents.calendar ?? .current)
            timeRow.onChange = { [weak self] hour, minute, second in
                self?.timeEntered(hour: hour, minute: minute, second: second)
            }
            add(timeRow)
            self.timeRow = timeRow
        }
    }

    /// Writes ``date`` into whichever widgets are installed.
    private func applyDate() {
        let parts = gregorian.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        guard
            let year = parts.year, let month = parts.month, let dayOfMonth = parts.day,
            let hour = parts.hour, let minute = parts.minute, let second = parts.second
        else {
            return
        }

        let wanted = DateComponents(year: year, month: month, day: dayOfMonth)
        if let grid = grid ?? button?.grid, grid.selectedDay != wanted {
            // Only when it differs. GTK would ignore an identical write anyway
            // -- `calendar_select_day_internal` returns early -- so this saves a
            // GDateTime per layout pass rather than changing what happens.
            //
            // It does not, and cannot, spare a user who is browsing: the browsed
            // month lives in the same field as the selection, so it genuinely
            // does differ, and this write is what pulls them back. See the note
            // on the class.
            isApplyingDate = true
            grid.selectDay(year: year, month: month, day: dayOfMonth)
            isApplyingDate = false
        }

        button?.label = formatted(date)
        wheel?.apply(date)
        timeRow?.show(hour: hour, minute: minute, second: second)
    }

    /// Takes the day the wheel reports and keeps the time this picker holds.
    ///
    /// Same split as ``daySelected(shownBy:)``: the wheel chooses a day and
    /// knows nothing about the time of day, so composing them here is what stops
    /// picking a date from resetting the clock to midnight.
    /// 與 ``daySelected(shownBy:)`` 相同的分工：滾輪選的是日期，對當日時間一無所知，因此在此處
    /// 合成兩者，正是「選日期不會把時間重設為午夜」的原因。
    private func wheelPicked(_ picked: Date) {
        guard !isApplyingDate else { return }

        let day = gregorian.dateComponents([.year, .month, .day], from: picked)
        var components = gregorian.dateComponents(
            [.hour, .minute, .second, .nanosecond],
            from: date
        )
        components.year = day.year
        components.month = day.month
        components.day = day.day

        report(components)
    }

    private func daySelected(shownBy grid: Gtk.Calendar) {
        guard !isApplyingDate else { return }

        let day = grid.selectedDay

        // The time of day comes from the picker's own copy, not from the
        // widget, which has just thrown its own away.
        var components = gregorian.dateComponents(
            [.hour, .minute, .second, .nanosecond],
            from: date
        )
        components.year = day.year
        components.month = day.month
        components.day = day.day

        report(components)
    }

    private func timeEntered(hour: Int, minute: Int, second: Int?) {
        var components = gregorian.dateComponents(
            [.year, .month, .day, .second, .nanosecond],
            from: date
        )
        components.hour = hour
        components.minute = minute
        // A row with no second field is not a request to zero the seconds. The
        // binding keeps its own, the same way the day click keeps the time of
        // day: a picker should not throw away what it does not display.
        if let second {
            components.second = second
        }

        report(components)
    }

    /// Turns a set of components into the bound date, clamps it, pushes it back
    /// into the widgets and tells SwiftCrossUI.
    private func report(_ components: DateComponents) {
        guard let picked = gregorian.date(from: components) else { return }

        // Clamping after the fact, since neither GtkCalendar nor a spin button
        // holding an hour knows anything about the range.
        date = min(max(picked, range.lowerBound), range.upperBound)
        applyDate()
        onChange?(date)
    }

    private func formatted(_ date: Date) -> String {
        let formatter: DateFormatter
        if let labelFormatter {
            formatter = labelFormatter
        } else {
            formatter = DateFormatter()
            formatter.calendar = displayCalendar
            formatter.locale = displayCalendar.locale ?? .current
            formatter.timeZone = timeZone
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            labelFormatter = formatter
        }
        return formatter.string(from: date)
    }
}

/// A date picker drawn as a small button that opens a calendar in a popover.
///
/// SwiftUI describes `.compact` as "a smaller date input ... a text field, or a
/// button that opens a calendar pop-up". GTK has no compact date widget, but
/// the second of those shapes is precisely `GtkMenuButton`: a button that owns
/// a popover, draws its own disclosure arrow, and handles the toggling,
/// keyboard activation and accessibility relationship itself.
///
/// It is genuinely the smaller input the style asks for, not merely a different
/// one. Measured on GTK 4.22.4, the button asks for 127x34 where a bare
/// `GtkCalendar` asks for 256x203.
///
/// The popover keeps GTK's default `autohide`, so a click outside it or Escape
/// closes it. It deliberately does not close when a day is picked: `GtkPopover`
/// pops down by itself only for menu items, and the popover is also where a
/// user changes their mind about the month, so closing on the first click would
/// take the grid away mid-decision.
/// The hour and minute (and optionally second) half of a date picker.
///
/// GTK has no time widget at all -- not a `GtkTimePicker`, not a time mode on
/// `GtkCalendar`. GNOME's own apps build one out of spin buttons, and so does
/// this: `hh : mm` , plus `: ss` when asked, plus an AM/PM dropdown where the
/// locale wants one.
///
/// The unused upstream `TimePicker` above it does not work, for two reasons,
/// both avoided here:
///
/// - It wrote `spinButton.text = "\(value)"`, which sets the entry's text
///   without telling the underlying `GtkAdjustment` anything, so the value the
///   widget reports back never moved. This writes `value`.
/// - It rebuilt a date with `Foundation.Calendar.date(bySetting:value:of:)`,
///   which searches for the *next* instant having that component and can land
///   on another day. This reports the fields and lets ``DatePickerWidget``
///   assemble them in one go, which is the only way the result is the date the
///   user typed.
///
/// Programmatic writes go through `withBlockedSignal(named: "value-changed")`,
/// so pushing the binding back in on every layout pass does not read as typing.
final class TimeRow: Box {
    enum Precision {
        case hourMinute
        case hourMinuteSecond
    }

    /// Reports a time the user typed or stepped, always on a 24-hour clock
    /// whatever the locale draws. The second is nil when the row has no second
    /// field, which is not the same as zero.
    var onChange: ((_ hour: Int, _ minute: Int, _ second: Int?) -> Void)?

    /// Whether the locale writes times as 1-12 with a meridiem. Decided with
    /// `DateFormatter.dateFormat(fromTemplate: "j", ...)`, the skeleton whose
    /// whole job is "however this locale writes an hour", rather than with
    /// `Locale.hourCycle`, which is macOS 13 or newer and would drag an
    /// availability annotation across this whole class.
    ///
    /// Fixed at construction, along with the meridiem symbols. A locale change
    /// is a rebuild rather than an update, because it can add or remove the
    /// dropdown -- see ``DatePickerWidget/Contents``.
    private let isTwelveHour: Bool

    private let hourField = SpinButton(range: 0, max: 23, step: 1)
    private let minuteField = SpinButton(range: 0, max: 59, step: 1)
    private let secondField: SpinButton?
    private let meridiemField: DropDown?

    /// Set while a time is being written in. `value-changed` fires for such a
    /// write exactly as it does for typing, and this is what tells them apart.
    /// Belt as well as braces alongside `withBlockedSignal`, which cannot cover
    /// the dropdown -- `notify::selected` is not a blockable signal name.
    private var isApplyingTime = false

    init(precision: Precision, calendar: Foundation.Calendar) {
        let locale = calendar.locale ?? .current
        let template = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale)
        isTwelveHour = template?.contains("a") ?? false

        secondField = precision == .hourMinuteSecond ? SpinButton(range: 0, max: 59, step: 1) : nil
        meridiemField =
            isTwelveHour ? DropDown(strings: [calendar.amSymbol, calendar.pmSymbol]) : nil

        super.init(gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 2))

        if isTwelveHour {
            hourField.setRange(min: 1, max: 12)
        }

        for field in [hourField, minuteField, secondField].compactMap({ $0 }) {
            field.numeric = true
            // Stepping past the end of a field carries no meaning here: a
            // minute rolling from 59 to 0 must not take the hour, and an hour
            // rolling past midnight must not take the day. The date is chosen
            // in the grid.
            field.wrap = true
            field.widthChars = 2

            // Spin buttons render a bare integer, so 09:05 would read "9:5"
            // without this. Returning true tells GTK the text has been dealt
            // with.
            field.output = { field in
                field.text = String(format: "%02d", Int(field.value))
                return true
            }
            field.valueChanged = { [weak self] _ in self?.fieldChanged() }
        }

        // AM/PM where the locale writes it: before the hour in zh_TW (上午 09:46),
        // after it in en_US. The order is the `jm` pattern's, as WinUIBackend's
        // LocaleTimeRow and SwiftCrossUI's .rows and .clock have it.
        // 上午/下午放在 locale 書寫的位置:zh_TW 在時之前(上午 09:46),en_US 在之後。依 `jm` 樣式排列，
        // 與 WinUIBackend 的 LocaleTimeRow 以及 SwiftCrossUI 的 .rows、.clock 相同。
        let meridiemFirst: Bool = {
            let pattern = DateFormatter.dateFormat(fromTemplate: "jm", options: 0, locale: locale) ?? ""
            guard
                let hour = pattern.firstIndex(where: { "hHkK".contains($0) }),
                let meridiem = pattern.firstIndex(where: { "abB".contains($0) })
            else { return false }
            return meridiem < hour
        }()
        meridiemField?.notifySelected = { [weak self] _, _ in self?.fieldChanged() }
        if meridiemFirst, let meridiemField {
            add(meridiemField)
        }
        add(hourField)
        add(Gtk.Label(string: ":"))
        add(minuteField)
        if let secondField {
            add(Gtk.Label(string: ":"))
            add(secondField)
        }
        if !meridiemFirst, let meridiemField {
            add(meridiemField)
        }
    }

    /// Shows a 24-hour time, translating it into whatever the locale draws.
    func show(hour: Int, minute: Int, second: Int) {
        isApplyingTime = true
        defer { isApplyingTime = false }

        hourField.withBlockedSignal(named: "value-changed") {
            self.hourField.value = Double(self.isTwelveHour ? (hour + 11) % 12 + 1 : hour)
        }
        minuteField.withBlockedSignal(named: "value-changed") {
            self.minuteField.value = Double(minute)
        }
        secondField?.withBlockedSignal(named: "value-changed") {
            self.secondField?.value = Double(second)
        }
        if let meridiemField {
            let wanted = hour < 12 ? 0 : 1
            if meridiemField.selected != wanted {
                meridiemField.selected = wanted
            }
        }
    }

    private func fieldChanged() {
        guard !isApplyingTime else { return }

        var hour = Int(hourField.value)
        if isTwelveHour {
            // 12 AM is hour 0 and 12 PM is hour 12, which is the one case where
            // the arithmetic is not "add twelve for the afternoon".
            hour %= 12
            if meridiemField?.selected == 1 {
                hour += 12
            }
        }

        onChange?(hour, Int(minuteField.value), secondField.map { Int($0.value) })
    }
}

final class CompactDatePicker: MenuButton {
    let grid = Gtk.Calendar()

    init() {
        super.init(gtk_menu_button_new())

        let popover = Popover()
        popover.setChild(grid)

        // Acquiring a parent is what registers a widget's signals (see
        // Widget.parentWidget). A Box does this for its children; a Popover has
        // no such bookkeeping, so the grid would never hear `day-selected`
        // without this line.
        grid.parentWidget = popover

        // MenuButton keeps the Swift-side reference that keeps the popover, and
        // with it the grid's signal handlers, alive.
        setPopover(popover)
    }
}
