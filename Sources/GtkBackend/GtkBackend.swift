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
    BackendFeatures.Clipping
{
    public typealias Window = Gtk.ApplicationWindow
    public typealias Widget = Gtk.Widget
    public typealias Menu = Gtk.PopoverMenu
    public typealias Alert = Gtk.MessageDialog

    public class Sheet: Gtk.Window {
        var onDismiss: (() -> Void)? = nil
        var interactiveDismissDisabled = false
        var nestedSheet: Sheet?
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
    /// change while the app runs. It was `let scrollBarWidth = 0`, and the 0 was
    /// right for the default and unreachable for anything else: with overlay
    /// scrolling off the bars take real width, SwiftCrossUI allots none, and the
    /// content is over-allocated by about a scrollbar.
    ///
    /// The width is measured from a real GtkScrollbar rather than guessed,
    /// because a theme decides it. AppKitBackend likewise asks
    /// `NSScroller.preferredScrollerStyle`; WinUIBackend still returns a
    /// constant 12.
    ///
    /// 當 GTK 的捲軸浮動於內容之上時為 0，而那是它的預設值。
    ///
    /// 此處改為計算屬性而非儲存屬性，因為答案取決於使用者設定，且可能在 app 執行期間改變。原本是
    /// `let scrollBarWidth = 0`：該 0 對預設情況是正確的，對其餘情況則永遠到不了——關閉 overlay
    /// scrolling 後捲軸會佔用實際寬度，而 SwiftCrossUI 未分配任何寬度給它，內容便會超額配置約一個
    /// 捲軸的寬度。
    ///
    /// 寬度取自一個真實的 GtkScrollbar 實測，而非猜測，因為決定它的是主題。AppKitBackend 同樣會去
    /// 詢問 `NSScroller.preferredScrollerStyle`；WinUIBackend 目前仍回傳固定的 12。
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
        debugLogOnce("overlay scrolling is off; scroll bars measure \(Self.measuredScrollBarWidth)pt")
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
    // `.wheel` was absent here until 2026-08-27, with a comment saying GTK "has
    // no wheel widget of any kind, and faking one out of a scrolled list would
    // be a worse lie than the fallback". The premise was wrong. SwiftUI's own
    // documentation describes `.wheel` as showing "each component as columns in
    // a scrollable wheel", and on iOS it is a UIPickerView -- N columns of
    // scrollable text. A scrolled list per component is not a fake of the wheel,
    // it is the wheel. See ``DateWheel``.
    //
    // A style left out of this list is downgraded to `.automatic` by
    // `datePickerStyle(_:)` without a word in a release build, so the list is
    // the only place an omission is visible.
    //
    // `.wheel` 在 2026-08-27 之前並不在此清單中，當時的註解說 GTK「沒有任何形式的滾輪 widget，
    // 而用捲動清單假造一個，會是比退回預設更糟的謊言」。該前提是錯的。SwiftUI 自己的文件把
    // `.wheel` 描述為「將每個組成部分顯示為可捲動滾輪中的欄位」，而在 iOS 上它就是
    // UIPickerView——N 欄可捲動文字。每個組成部分一個捲動清單並非滾輪的贗品，它就是滾輪本身。
    // 詳見 ``DateWheel``。
    public let supportedDatePickerStyles: [BackendDatePickerStyle] = [
        .automatic, .graphical, .compact, .wheel,
    ]
    // `.menu` stays first: `defaultPickerStyle` is the first entry, so it is
    // what `.automatic` resolves to, and a dropdown is what a GTK app shows for
    // a picker with no style of its own.
    public let supportedPickerStyles: [BackendPickerStyle] = [.menu, .segmented, .radioGroup]
    // #386: preferredColorScheme is honoured (see updateWindow). The override is
    // per-display rather than per-window, since GTK has no per-window theme
    // variant, so two windows asking for opposite schemes cannot both win.
    // #386：preferredColorScheme 已被遵從（見 updateWindow）。該 override 為 per-display 而非
    // per-window，因為 GTK 沒有 per-window 的主題變體，故兩個要求相反配色的視窗無法同時如願。
    public let canOverrideWindowColorScheme = true
    public let restoresWindowFrames = false

    let defaultSheetCornerRadius = 10

    var gtkApp: Application
    private var selectableListStates: [ObjectIdentifier: SelectableListState] = [:]

    /// A window to be returned on the next call to ``GtkBackend/createWindow``.
    /// This is necessary because Gtk creates a root window no matter what, and
    /// this needs to be returned on the first call to `createWindow`.
    var precreatedWindow: Window?

    /// All current windows associated with the application. Doesn't include the
    /// precreated window until it gets 'created' via `createWindow`.
    var windows: [Window] = []

    /// The alert currently on screen for a window, keyed by window identity, and
    /// the alerts waiting behind it. SwiftUI shows one alert at a time per
    /// window; a second requested while one is up waits and appears when the
    /// first is dismissed, rather than a pile of modal dialogs fighting over the
    /// window (the P5 regression).
    private var shownAlert: [ObjectIdentifier: Alert] = [:]
    private var pendingAlerts:
        [ObjectIdentifier: [(alert: Alert, window: Window, handler: (Int) -> Void)]] = [:]

    private var rootEnvironmentChangeHandler: (() -> Void)?

    private struct LogLocation: Hashable, Equatable {
        let file: String
        let line: Int
        let column: Int
    }

    private var logsPerformed: Set<LogLocation> = []

    /// Reports a backend limitation to the app author, once per call site.
    ///
    /// The body was wrapped in `#if DEBUG` and is no longer. This project builds
    /// release by default -- see the `testapp/compile.zsh` policy in CLAUDE.md --
    /// so the one message this method carries, "GTK does not support setting
    /// maximum window sizes", printed in no configuration anything is actually
    /// run in. A request the backend silently drops, with nothing said about it,
    /// is #38's defect exactly.
    ///
    /// It is not gated on `SCUI_DEBUG` either: this is not a developer trace but
    /// something the author of the app needs to be told, and needing a special
    /// build to be told is how the silence happened in the first place.
    /// `logger.notice` outranks the release log level (`.info`, set in
    /// `App.logHandler`), and the once-per-location set is what stops a call made
    /// every frame from repeating.
    ///
    /// The name is kept: `UIKitBackend` and `WinUIBackend` declare the same
    /// method, and renaming it in one backend alone costs more than it buys.
    ///
    /// 向 app 作者回報 backend 的限制，每個呼叫點只回報一次。
    ///
    /// 本方法主體原先包在 `#if DEBUG` 之中，現已移除。本專案預設建置 release——見 CLAUDE.md 中的
    /// `testapp/compile.zsh` 政策——因此它唯一攜帶的訊息「GTK does not support setting maximum
    /// window sizes」，在任何實際執行的組態中都不會印出。backend 默默丟棄一項要求、且對此隻字
    /// 未提，正是 #38 的缺陷。
    ///
    /// 它也不以 `SCUI_DEBUG` 為條件：這並非開發者用的追蹤訊息，而是 app 作者必須被告知的事；
    /// 而「必須改用特殊建置才會被告知」，正是當初造成沉默的原因。`logger.notice` 高於 release 的
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
        gtkApp = Application(
            applicationId: appIdentifier ?? "com.example.SwiftCrossUIApp",
            flags: SHIM_G_APPLICATION_HANDLES_OPEN
        )
        gtkApp.registerSession = true
    }

    /// Asks GDK for Direct Composition, so GTK can use a hardware renderer.
    ///
    /// Opt-in through `SCUI_GTK_DCOMP=1`, and off by default because it changes
    /// how every window is composited, not only the transformed ones.
    ///
    /// Why it matters. On this Windows machine GTK cannot realize its GL
    /// renderer -- `Failed to realize renderer 'GskGLRenderer' for surface
    /// 'GdkWin32Toplevel': OpenGL requires Direct Composition` -- and silently
    /// falls back to `GskCairoRenderer`, which is software. That fallback is
    /// what cannot draw a transform node, and paints the hotpink rectangle
    /// recorded in bugs/Gtk4-bugs.md. With this set, GTK uses `GskGLRenderer`
    /// and every P40 transform renders correctly: measured 2026-08-29, 47873
    /// hotpink pixels without it and 0 with it, offset, both scales, both
    /// rotations, the shear and rotated text all correct.
    ///
    /// `GDK_DEBUG=dcomp` is a feature switch rather than a logging category --
    /// GDK lists it as "Enable Direct Composition (Windows)". Appended rather
    /// than assigned, so an existing GDK_DEBUG is not thrown away.
    ///
    /// 向 GDK 要求啟用 Direct Composition，使 GTK 得以採用硬體繪製器。
    ///
    /// 透過 `SCUI_GTK_DCOMP=1` 選擇性啟用，預設關閉——因為它改變的是每一個視窗的合成方式，
    /// 而不只是那些被變換過的視窗。
    ///
    /// 為何重要：在這台 Windows 機器上，GTK 無法實現它的 GL 繪製器——
    /// `Failed to realize renderer 'GskGLRenderer' for surface 'GdkWin32Toplevel':
    /// OpenGL requires Direct Composition`——並靜默退回到軟體的 `GskCairoRenderer`。
    /// 正是這個退路畫不出 transform node，於是畫出 bugs/Gtk4-bugs.md 所記載的那片 hotpink。
    /// 設定本旗標後，GTK 會使用 `GskGLRenderer`，而 P40 的每一項變換都正確繪製：2026-08-29
    /// 實測，未啟用時 47873 個 hotpink 像素，啟用後為 0；位移、兩種縮放、兩種旋轉、推移與
    /// 旋轉後的文字全部正確。
    ///
    /// `GDK_DEBUG=dcomp` 是功能開關而非記錄類別——GDK 自己將它列為
    /// 「Enable Direct Composition (Windows)」。此處採「附加」而非「指派」，以免丟棄既有的
    /// GDK_DEBUG 設定。
    private static func enableDirectCompositionIfRequested() {
        #if os(Windows)
            // `SCUI_GTK_DCOMP` still forces it on, for bisecting against a
            // build that predates `-GPU`.
            // `SCUI_GTK_DCOMP` 仍可強制開啟，以便與早於 `-GPU` 的建置進行二分比對。
            // `>= 2`, not `>= 1`, and this is a correction with a measurement
            // behind it.
            //
            // Direct Composition made the window uncapturable by the old
            // gdigrab/BitBlt window path this project's GTK screenshots used
            // to depend on. Measured 2026-08-29 on P40: with dcomp off, the
            // old path captured the window; with dcomp on, it had to fall back
            // to desktop capture. Defaulting dcomp on therefore broke the
            // meaning of GTK screenshots until the harness moved to wincap.
            //
            // Mapping it to 2 is also the more faithful reading of the number.
            // `1` means "the platform's own default", and GTK's own default
            // here is what it does unaided -- which is to fail to realize GL and
            // fall back to cairo. Asking for hardware is asking for more than
            // the default, which is what `2` means.
            //
            // 此處為 `>= 2` 而非 `>= 1`，而這是一項有量測依據的修正。
            //
            // Direct Composition 會使視窗無法被舊的 gdigrab/BitBlt 視窗路徑擷取，而本專案
            // 的 GTK 截圖曾依賴該路徑。2026-08-29 於 P40 實測：dcomp 關閉時舊路徑可擷取
            // 視窗；dcomp 開啟時只能退回桌面擷取。因此把 dcomp 設為預設開啟，等於在 harness
            // 移到 wincap 之前弄壞了 GTK 截圖的語意。
            //
            // 將它對應到 2，同時也是對這個數字更忠實的解讀。`1` 意指「平台自身的預設」，而 GTK
            // 在此處的自身預設，就是它在無人干預時所做的事——無法實現 GL、退回 cairo。要求硬體
            // 就是要求「比預設更多」，而那正是 `2` 的意思。
            let forced = ProcessInfo.processInfo.environment["SCUI_GTK_DCOMP"] == "1"
            guard forced || DebugFeatures.gpuSelection >= 2 else { return }

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
            let disablesGL = disabled.split(separator: ",").contains { $0.trimmingCharacters(in: .whitespaces) == "gl" }
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
                    String(row.index), quote(row.name), row.primary ? "yes" : "no",
                    row.removable ? "yes" : "no", row.attached ? "yes" : "no",
                    selectedBy, quote(note),
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
                    HKEY_CURRENT_USER, &path, 0, nil, regOptionNonVolatile,
                    regKeySetValue, nil, &key, &disposition
                ) == ERROR_SUCCESS,
                let key
            else { return false }
            defer { RegCloseKey(key) }
            var name = wide(executable)
            let data = wide("GpuPreference=\(value);")
            let bytes = DWORD(data.count * MemoryLayout<UInt16>.size)
            return data.withUnsafeBytes { raw in
                RegSetValueExW(
                    key, &name, 0, regTypeSZ,
                    raw.baseAddress?.assumingMemoryBound(to: BYTE.self), bytes
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

            callback()

            let provider = CSSProvider()
            provider.loadCss(
                from: """
                    list {
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
                    """
            )

            // Keep a reference around so that the provider doesn't get removed as
            // soon as we exit this scope.
            self.globalCSSProvider = provider

            #if !os(macOS)
                Self.mainRunLoopTicklingLoop()
            #endif
        }
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

        if let defaultSize {
            window.defaultSize = Size(
                width: defaultSize.x,
                height: defaultSize.y
            )
        }

        window.setChild(Gtk.Box())

        window.notifyIsActive = { _ in
            self.rootEnvironmentChangeHandler?()
        }

        return window
    }

    public func updateWindow(_ window: Window, environment: EnvironmentValues) {
        // #386, the override half: honour preferredColorScheme by asking GTK for
        // the matching theme variant, so the widgets GTK draws itself (buttons,
        // entries, list rows) follow the app's request too, not just the text
        // SwiftCrossUI colours.
        //
        // Only when the app asks for something other than the ambient theme.
        // Setting it unconditionally feeds our own detection back into GTK, and
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
        // 僅在 app 要求了與環境主題不同的配色時才設定。無條件設定會把我們自己的偵測回饋給 GTK，
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
        // desktop in dark mode, driving actions/win/P15-colour-scheme.csv, which
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
        // 桌面為深色模式下實測，驅動 actions/win/P15-colour-scheme.csv（該檔先按 Light 再按 Dark）：
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
    /// an ordinary `HWND` and `SetWindowPos` works on it. Elsewhere it does not:
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
        #if os(Windows)
            [.automatic, .normal, .floating]
        #else
            [.automatic, .normal]
        #endif
    }

    public func setLevel(ofWindow window: Window, to level: WindowLevel) {
        // Only `.floating` needs anything done, and only the platforms that
        // listed it above get here with it. The caller applies the level after
        // the window is shown, when the platform handle exists.
        _ = scui_window_set_topmost(window.widgetPointer, level == .floating ? 1 : 0)
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
                // Still hardcoded, and the TODO that used to sit here -- "don't
                // hardcode this (if possible), because some Gtk themes may
                // affect the height of the menu bar" -- has been tried. It is
                // not possible at this call site, which is worth recording so
                // the next person does not repeat the attempt.
                //
                // Measured 2026-08-27 on Windows/GTK 4.22.4, with P20 given an
                // application menu for the purpose (no Pn had one before, so
                // this whole branch had never executed):
                //
                //   * `menubarHeight` is called exactly ONCE per run, from
                //     `setSize(ofWindow:)` during initial sizing.
                //   * At that moment the menu bar is not in the widget tree. A
                //     depth-first walk from the ApplicationWindow found only
                //     `GtkCustomRootWidget` and three `GtkPassthroughFixed`.
                //     GTK builds the bar later.
                //
                // So there is nothing to measure when the one question is asked.
                // A real fix has to measure after the bar appears and then
                // re-run the sizing, which is a change to when this is computed
                // rather than to how.
                //
                // How wrong the constant is: the bar drew 23 pt of strip plus a
                // 1 pt rule, sampled down a text-free column of the capture. So
                // 25 is one or two points too tall under this theme, and the
                // window is that much too tall with the content offset to match.
                //
                // 此處仍為寫死的值，而原本擺在這裡的 TODO——「盡可能不要寫死，因為某些 Gtk 主題會
                // 影響選單列的高度」——已經嘗試過了。在這個呼叫點上做不到，此事值得記錄下來，以免
                // 下一個人重複同樣的嘗試。
                //
                // 2026-08-27 於 Windows/GTK 4.22.4 實測（為此特地讓 P20 帶上應用程式選單——在那之前
                // 沒有任何 Pn 有選單，因此這整條分支從未執行過）：`menubarHeight` 每次執行只會被呼叫
                // **一次**，來自初始尺寸設定時的 `setSize(ofWindow:)`；而在那個時間點，選單列並不在
                // widget 樹中——自 ApplicationWindow 進行深度優先走訪，只找到 `GtkCustomRootWidget`
                // 與三個 `GtkPassthroughFixed`，GTK 是稍後才建立該列的。
                //
                // 因此在唯一被提問的時刻，根本沒有東西可以量測。真正的修法必須在選單列出現之後才
                // 量測，並重新執行尺寸計算——那是改變「何時計算」，而非改變「如何計算」。
                //
                // 這個常數錯得多離譜：該列畫出 23 pt 的橫條加上 1 pt 的分隔線（取樣自截圖中一條沒有
                // 文字的直線）。因此在此主題下，25 高了一到兩點，視窗也就高了那麼多，內容隨之偏移。
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
        // AppKitBackend answers `!window.styleMask.contains(.fullScreen)` for
        // the same reason; this was a constant `true` with a TODO next to it,
        // which is the same bug WinUIBackend still carries.
        //
        // 全螢幕視窗必須回答 false，否則版面系統會不斷提出合成器不會允許的尺寸，兩者互相拉扯。
        // AppKitBackend 基於相同理由回傳 `!window.styleMask.contains(.fullScreen)`；此處原本是一個
        // 常數 `true` 加上一則 TODO，而 WinUIBackend 至今仍帶著同一個問題。
        return !window.isFullscreen
    }

    public func setSize(ofWindow window: Window, to newSize: SIMD2<Int>) {
        let child = window.getChild() as! CustomRootWidget
        window.size = Size(
            width: newSize.x,
            height: newSize.y + menubarHeight(ofWindow: window)
        )
        child.preemptAllocatedSize(allocatedWidth: newSize.x, allocatedHeight: newSize.y)
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
    /// Nothing provided this before. On macOS Cmd-Q comes free with AppKit's
    /// standard application menu; GTK has no equivalent, so an app built on this
    /// backend simply had no quit shortcut and the window stayed open.
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
    /// 此前並無任何機制提供它。在 macOS 上，Cmd-Q 隨 AppKit 的標準應用程式選單而來；GTK 沒有對應
    /// 機制，因此以此 backend 建置的 app 根本沒有結束捷徑，視窗會一直開著。
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
        gtkApp.setAccelerators(["<Control>q"], forAction: "app.quit")
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
        ActionFileReplay.replayIfRequested(
            layoutScale: Double(gtk_widget_get_scale_factor(window.widgetPointer))
        )
        #endif
    }

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

        let showMenuBar = !submenus.isEmpty
        for window in windows {
            window.showMenuBar = showMenuBar
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

    private static func runInMainThread(
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
    /// Only Windows: GTK there ships its own theme and does not track the system
    /// light/dark setting, so an app would sit in Adwaita light on a dark
    /// desktop. On Linux the GTK theme *is* the desktop setting, so reading the
    /// theme's colour already answers the question and there is nothing separate
    /// to consult.
    ///
    /// 平台自身所設定的配色，僅在「本 backend 讀得到、且 GTK 尚未跟隨」的情況下提供。
    ///
    /// 僅限 Windows：GTK 在該平台自帶主題，不會追蹤系統的淺色／深色設定，因此 app 會在深色桌面上
    /// 停留於 Adwaita light。在 Linux 上，GTK 主題「就是」桌面的設定，因此讀取主題顏色便已回答了
    /// 這個問題，無須另行查詢。
    private var systemColorScheme: ColorScheme? {
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
        #else
            return nil
        #endif
    }

    /// Samples ``ambientColorScheme``. Must run with GTK initialised.
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
        ambientColorScheme = luma > 0.5 ? .dark : .light

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
        // TODO: React to the desktop switching between light and dark while the
        // app runs. The scheme is read once at launch (see
        // sampleAmbientColorScheme), which covers the common case but means a
        // running app keeps the scheme it started with.
        //
        // Subscribing to the GtkSettings notifications was tried and reverted:
        // the notification arrives inside GTK's own property-change machinery,
        // reached from a window update, and re-sampling has to build a window to
        // read a themed colour from. Doing that there crashed, and deferring it
        // to the next main-loop turn crashed as well. Whatever the fix is, it
        // needs a way to read the theme without building a widget, or a safe
        // point in the update cycle to re-read at -- neither of which is a small
        // change, so it is left as a known gap rather than a half-working one.
        //
        // TODO：讓 app 在執行期間跟隨桌面於淺色與深色之間的切換。目前配色僅於啟動時讀取一次
        //（見 sampleAmbientColorScheme），這涵蓋了常見情境，但執行中的 app 會維持啟動時的配色。
        //
        // 訂閱 GtkSettings 的通知曾經嘗試並已回退：該通知抵達於 GTK 自身的屬性變更流程之中，
        // 而該流程由一次視窗更新所觸發，且重新取樣必須建立一個 widget 才能讀到主題顏色。在該處
        // 建立會崩潰，延到主迴圈下一回合同樣崩潰。無論正確解法為何，都需要「不建立 widget 即可
        // 讀取主題」的方法，或是更新週期中一個安全的重讀時點——兩者都不是小改動，因此將其記為
        // 已知缺口，而非留下一個半可用的實作。
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
        rootEnvironment
            .with(\.scenePhase, window.isActive ? .active : .inactive)
            .with(
                \.windowScaleFactor,
                Double(gtk_widget_get_scale_factor(window.widgetPointer))
            )
    }

    public func setWindowEnvironmentChangeHandler(
        of window: Window,
        to action: @escaping @Sendable @MainActor () -> Void
    ) {
        // `notify::scale-factor`, because the scale factor is the whole of what
        // `computeWindowEnvironment` reads from the window. This body was a bare
        // TODO, which meant a window dragged between displays of different scale
        // kept whatever it started with: `Image` re-renders on this value, so it
        // stayed rendered for the old display until something else forced a
        // recompute.
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
        // 讀取的全部內容。此處原本只有一行 TODO，意味著視窗被拖到不同縮放的顯示器時，會保留它啟動
        // 時的值：`Image` 會依這個值重新繪製，於是它會一直維持著為舊顯示器繪製的結果，直到有別的
        // 事情強迫重新計算為止。
        //
        // 監聽的是該屬性，而非顯示器或螢幕的訊號。GTK 的 scale factor 是它實際排版時所用的 buffer
        // scale——依設計即為整數——而 `computeWindowEnvironment` 刻意回報它、而非顯示器所宣稱的
        // 小數，理由記於該處。改為監聽顯示器，會在 GTK 並未據以動作的變化上觸發，卻錯過 GTK 真正
        // 動作的那一刻。
        //
        // 使用 `MainActor.assumeIsolated` 而非 hop：GTK 在執行 main loop 的執行緒上派送訊號，
        // 而那就是主執行緒，因此隔離性本已成立，hop 只會讓重新計算多延遲一輪。與上方的 action
        // callback 形狀相同。
        // NOT IMPLEMENTED, and the attempt is recorded because the obvious form
        // does not compile:
        //
        //     window.addSignal(name: "notify::scale-factor") { … }
        //     error: 'addSignal' is inaccessible due to 'internal' protection level
        //
        // `addSignal` belongs to the `Gtk` module and is internal to it, and
        // `Gtk` exposes no public equivalent: there is no generated
        // `notifyScaleFactor` on `Widget`, and nothing in this backend reaches
        // `g_signal_connect` directly. Doing this properly means adding a small
        // public API on the `Gtk` side -- an `onScaleFactorChange` in the shape
        // of `Window.onCloseRequest` -- rather than reaching around it from
        // here.
        //
        // 尚未實作，而此處記下這次嘗試，是因為最直覺的寫法無法編譯（錯誤如上）。
        //
        // `addSignal` 屬於 `Gtk` module 且對其為 internal，而 `Gtk` 並未提供公開的對應物：
        // `Widget` 上沒有產生出來的 `notifyScaleFactor`，本 backend 也沒有任何地方直接使用
        // `g_signal_connect`。要正確完成這件事，應在 `Gtk` 那一側新增一個小的公開 API——形狀
        // 比照 `Window.onCloseRequest` 的 `onScaleFactorChange`——而不是從此處繞過它。
        _ = window
        _ = action
    }

    public func setIncomingURLHandler(to action: @escaping (URL) -> Void) {
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

    /// Swaps two children, in GTK as well as in our own bookkeeping.
    ///
    /// The GTK half used to be missing. The comment here said "Gtk.Fixed
    /// doesn't let us rearrange children, so we just swap them in our own list
    /// so that at least everything works on the SCUI side", and named the
    /// consequence: overlapping widgets end up with unexpected z ordering. That
    /// is a `ZStack` whose order is driven by state drawing in the wrong order,
    /// silently, and AppKitBackend and WinUIBackend both did the real thing --
    /// `subviews.swapAt` and a remove/insert pair respectively -- so GtkBackend
    /// was the only one faking it.
    ///
    /// The premise was out of date. `gtk_widget_insert_after` is GTK 4's way to
    /// place a widget among its siblings, and passing `nil` for the sibling
    /// makes it first.
    ///
    /// The whole order is re-established from the array rather than moving just
    /// the two. Moving two requires working out each one's new anchor while the
    /// other is also moving, which is easy to get subtly wrong for the case
    /// where they are adjacent; walking the array is obviously correct by
    /// inspection. It also repairs any order that drifted while the GTK half
    /// was missing, rather than swapping two entries within a sequence that was
    /// already wrong. A `Fixed` holds a handful of children, so the extra work
    /// is not worth the sharper edge.
    ///
    /// 交換兩個子元件——在 GTK 中，以及在我方自己的記帳中。
    ///
    /// GTK 的那一半原本並不存在。此處的註解曾寫著「Gtk.Fixed 不允許我們重排子元件，因此我們只在
    /// 自己的清單裡交換，至少讓 SCUI 這一側能運作」，並指出了後果：重疊的 widget 會得到非預期的
    /// z 順序。那就是「順序由 state 決定的 `ZStack` 以錯誤的順序繪製」，而且是靜默的；
    /// AppKitBackend 與 WinUIBackend 都做了真正的事——分別是 `subviews.swapAt` 與一組移除／插入
    /// ——因此 GtkBackend 是唯一造假的那一個。
    ///
    /// 該前提已經過時。`gtk_widget_insert_after` 正是 GTK 4 用來在兄弟節點之間安置 widget 的方式，
    /// 而 sibling 傳入 `nil` 即代表置於首位。
    ///
    /// 此處是依陣列重建整個順序，而非只搬動那兩個。搬動兩個時，必須在「另一個也正在移動」的情況下
    /// 推算各自的新錨點，對於兩者相鄰的情形很容易出現細微的錯誤；而走訪整個陣列，正確與否一眼可
    /// 判。它同時也會修復「GTK 那一半缺席期間已經飄掉的順序」，而不是在一個本來就錯的序列中交換
    /// 兩個項目。一個 `Fixed` 只有寥寥數個子元件，因此這點額外成本不值得換取更鋒利的邊角。
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
        // is cut to it. AppKit does this with clipsToBounds and WinUI with a
        // geometric clip; GtkBackend was the one backend that only styled and
        // never clipped, which is #389. Clip through the same ClipFixed the
        // explicit clipped() uses -- a plain overflow: hidden does not work here
        // because a GtkFixed over-allocates to an oversized child and then clips
        // the wrong box; the P17-DOE experiment showed this. ClipFixed clips to
        // the size SwiftCrossUI decided instead.
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
        // The clip used to be rectangular whatever the radius, which was exact
        // only at radius 0 (P3's case): at any larger radius an oversized child
        // kept square corners showing underneath a rounded border. AppKit cuts
        // to the shape with clipsToBounds plus a layer corner radius, and WinUI
        // with a rounded-rectangle geometric clip.
        //
        // 分為兩半。CSS 負責把「繪製出來的邊框」變圓，而裁切則被告知依循同一個半徑，使子元件
        // 真的被裁成圓角形狀。
        //
        // 先前不論半徑為何，裁切一律為矩形，那只有在半徑為 0 時才是正確的（P3 的情況）：只要
        // 半徑更大，超尺寸的子元件就會在圓角邊框之下留下方形的角。AppKit 以 clipsToBounds 搭配
        // layer 的圓角半徑裁成該形狀，WinUI 則以圓角矩形的幾何裁切為之。
        widget.css.set(property: .cornerRadius(radius))
        scui_clip_fixed_set_corner_radius(widget.widgetPointer, gint(radius))
    }

    public func naturalSize(of widget: Widget) -> SIMD2<Int> {
        let currentSize = widget.getSizeRequest()
        widget.setSizeRequest(width: -1, height: -1)
        let (width, height) = widget.getNaturalSize()
        widget.setSizeRequest(width: currentSize.width, height: currentSize.height)
        return SIMD2(width, height)
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
        // the natural width at whatever we just asked for and make it useless
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
        return scrollView
    }

    public func updateScrollContainer(
        _ scrollView: Widget,
        environment: EnvironmentValues,
        bounceHorizontally: Bool,
        bounceVertically: Bool,
        hasHorizontalScrollBar: Bool,
        hasVerticalScrollBar: Bool
    ) {
        let scrollView = scrollView as! ScrolledWindow
        scrollView.setScrollBarPresence(
            hasVerticalScrollBar: hasVerticalScrollBar,
            hasHorizontalScrollBar: hasHorizontalScrollBar
        )
    }

    public func createSelectableListView() -> Widget {
        let listView = ListBox()
        listView.selectionMode = .single
        // No `navigation-sidebar` here. It used to be added unconditionally, so
        // every `List` was drawn as a sidebar whether it was one or not --
        // flat, no frame, sidebar row padding. The style now follows
        // `listStyle`, in `updateSelectableListView` below, which is where the
        // environment is available.
        // 此處不加 `navigation-sidebar`。它原本是無條件加上的，因此每一個 `List` 都被畫成側邊欄
        // ——無邊框、扁平、採用側邊欄的列距——無論它是不是側邊欄。樣式現改為跟隨 `listStyle`，
        // 於下方的 `updateSelectableListView` 中處理，因為 environment 在那裡才取得到。
        return listView
    }

    /// Applies `listStyle`, which until 2026-08-27 nothing read.
    ///
    /// `SplitView` set it on its sidebar column and no backend consulted it, so
    /// it was inert -- and the reason nobody noticed is that
    /// `createSelectableListView` added `navigation-sidebar` to *every* list, so
    /// the sidebar case looked right and the default case was wrong in the same
    /// way. Two defects that concealed each other.
    ///
    /// Set on every update rather than only when the value changes, because a
    /// list whose style is bound to state has to lose the class as well as gain
    /// it. `gtk_widget_remove_css_class` on a widget that does not have the
    /// class is a no-op, so the unconditional pair is safe.
    ///
    /// 套用 `listStyle`——在 2026-08-27 之前，沒有任何東西讀取它。
    ///
    /// `SplitView` 會在其側邊欄那一欄設定它，卻沒有任何 backend 去查詢，因此它是 inert 的；而之所以
    /// 沒人察覺，是因為 `createSelectableListView` 為**每一個** list 都加上了 `navigation-sidebar`
    /// ——於是側邊欄的情況看起來是對的，而預設的情況以同樣的方式錯著。兩個缺陷互相遮掩。
    ///
    /// 每次更新都設定，而非僅在值變動時，因為樣式綁定於 state 的 list 不只要能取得該 class，也要能
    /// 失去它。對未持有該 class 的 widget 呼叫 `gtk_widget_remove_css_class` 為 no-op，因此這組
    /// 無條件的成對呼叫是安全的。
    public func updateSelectableListView(
        _ selectableListView: Widget,
        environment: EnvironmentValues
    ) {
        let selectableListView = selectableListView as! ListBox
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
        // NOTE: This implementation works under the same assumptions as
        //   AppKitBackend's implementation. Read the comment in
        //   AppKitBackend.setItems for more details. In short, we assume
        //   that modifications made to `items` between `setItems` calls
        //   are either all pops, or all appends (not a mix).

        let listView = listView as! ListBox
        let state = state(for: listView)

        let previousRowCount = state.rowCount
        state.rowCount = items.count

        state.isProgrammaticSelectionUpdate = true
        defer { state.isProgrammaticSelectionUpdate = false }

        if items.count > previousRowCount {
            for item in items[previousRowCount...] {
                listView.append(item)
            }
        } else if items.count < previousRowCount {
            for _ in 0..<(previousRowCount - items.count) {
                listView.removeRow(at: items.count)
            }
        }

        preserveNilSelection(of: listView, state: state)
    }

    public func setSelectionHandler(
        forSelectableListView listView: Widget,
        to action: @escaping (_ selectedIndex: Int) -> Void
    ) {
        let listView = listView as! ListBox
        let state = state(for: listView)
        listView.rowSelected = { _, selectedRow in
            guard !state.isProgrammaticSelectionUpdate else {
                return
            }
            guard !state.isClearingNilSelection else {
                self.preserveNilSelection(of: listView, state: state)
                return
            }
            guard let selectedRow else {
                return
            }
            let selection = Int(gtk_list_box_row_get_index(selectedRow))
            guard selection != state.selection else {
                return
            }
            state.selection = selection
            action(selection)
        }
    }

    public func setSelectedItem(ofSelectableListView listView: Widget, toItemAt index: Int?) {
        let listView = listView as! ListBox
        let state = state(for: listView)
        state.selection = index
        state.isProgrammaticSelectionUpdate = true
        defer { state.isProgrammaticSelectionUpdate = false }
        if let index {
            listView.selectRow(at: index)
        } else {
            preserveNilSelection(of: listView, state: state)
        }
    }

    private func preserveNilSelection(of listView: ListBox, state: SelectableListState) {
        guard state.selection == nil else {
            state.isClearingNilSelection = false
            return
        }

        state.isClearingNilSelection = true
        state.isProgrammaticSelectionUpdate = true
        listView.unselectAll()
        state.isProgrammaticSelectionUpdate = false

        runInMainThread { [listView, state] in
            guard state.selection == nil else {
                state.isClearingNilSelection = false
                return
            }

            state.isProgrammaticSelectionUpdate = true
            listView.unselectAll()
            state.isProgrammaticSelectionUpdate = false
            state.isClearingNilSelection = false
        }
    }

    private func state(for listView: ListBox) -> SelectableListState {
        let key = ObjectIdentifier(listView)
        if let state = selectableListStates[key] {
            return state
        }
        let state = SelectableListState()
        selectableListStates[key] = state
        return state
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
        textView.css.clear()
        textView.css.set(properties: cssProperties(for: environment))
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

        let pango = Pango(for: widget)
        let (width, height) = pango.getTextSize(
            text,
            ellipsize: proposedHeight == nil ? .none : ellipsize,
            proposedWidth: proposedWidth.map(Double.init),
            proposedHeight: proposedHeight.map(Double.init)
        )

        // No line-limit handling here any more; `Text` applies it, for every
        // backend, from the font's line height. What used to be here measured a
        // synthetic string through a label that was never rooted, so the cap came
        // out at GTK's default font size whatever font was asked for. See the
        // note in Text.computeLayout.
        // 此處不再處理行數限制；`Text` 會為所有 backend 依字型行高統一套用。原本在此的做法是透過
        // 一個從未 root 的 label 量測合成字串，因此無論被要求何種字型，上限都以 GTK 的預設字級算出。
        // 詳見 Text.computeLayout 中的說明。
        return SIMD2(width, height)
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
        let texture = gdk_texture_new_for_pixbuf(pixbuf)!
        imageView.setPaintable(texture)
    }

    // MARK: Controls

    public func createButton() -> Widget {
        return Button()
    }

    public func updateButton(
        _ button: Widget,
        label: String,
        environment: EnvironmentValues,
        action: @escaping () -> Void
    ) {
        // TODO: Update button label color using environment
        let button = button as! Gtk.Button
        button.sensitive = environment.isEnabled
        button.label = label
        button.clicked = { _ in action() }

        // GTK's own class for a destructive action, so the button gets whatever
        // the current theme uses to warn -- red on Adwaita -- rather than a
        // colour this backend picked. `.cancel` gets nothing: GTK has no class
        // for it and inventing one would be this backend's opinion rather than
        // the platform's.
        //
        // Removed as well as added. The widget is reused across updates, so a
        // button that stops being destructive has to stop looking destructive;
        // only adding would make the styling a one-way door.
        //
        // 使用 GTK 自有的「破壞性動作」樣式類別，如此該按鈕便會採用當前主題用來示警的樣式——在
        // Adwaita 上是紅色——而非由本 backend 自行挑選的顏色。`.cancel` 則不套用任何東西：GTK 沒有
        // 對應的類別，而自行發明一個，那會是本 backend 的主張而非平台的主張。
        //
        // 此處會「移除」而不只是「加入」。widget 會在多次更新之間被重複使用，因此一個不再具有破壞性
        // 的按鈕，也必須不再看起來具有破壞性；只加不移會讓這個樣式變成一扇單向門。
        if environment.buttonRole == .destructive {
            gtk_widget_add_css_class(button.widgetPointer, "destructive-action")
        } else {
            gtk_widget_remove_css_class(button.widgetPointer, "destructive-action")
        }

        button.css.clear()
        button.css.set(
            properties: cssProperties(
                for: environment,
                isControl: true,
                // Stand aside for a role, so GTK's own class can paint it. See
                // the note in cssProperties: this backend's provider outranks
                // the theme, so styling the button and adding a style class at
                // the same time means the class loses silently.
                // 為 role 讓路，使 GTK 自己的類別能夠繪製它。詳見 cssProperties 中的說明：本
                // backend 的 provider 位階高於主題，因此「同時樣式化按鈕又加上樣式類別」會讓該類別
                // 靜默落敗。
                deferToThemeStyleClass: environment.buttonRole == .destructive
            )
        )
    }

    public func createToggle() -> Widget {
        return ToggleButton()
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
        toggle.css.clear()
        // This is a control, but we set isControl to false anyway because isControl overrides
        // the button background and makes the on and off states of the toggle look identical.
        toggle.css.set(properties: cssProperties(for: environment, isControl: false))
    }

    public func setState(ofToggle toggle: Widget, to state: Bool) {
        let toggle = toggle as! Gtk.ToggleButton

        toggle.withBlockedSignal(named: "toggled") {
            toggle.active = state
        }
    }

    public func createSwitch() -> Widget {
        return Switch()
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
        return Gtk.CheckButton()
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
        return scale
    }

    public func updateSlider(
        _ slider: Widget,
        minimum: Double,
        maximum: Double,
        decimalPlaces: Int,
        environment: EnvironmentValues,
        onChange: @escaping (Double) -> Void
    ) {
        let slider = slider as! Scale
        slider.sensitive = environment.isEnabled
        slider.minimum = minimum
        slider.maximum = maximum
        slider.digits = decimalPlaces
        slider.valueChanged = { widget in
            onChange(widget.value)
        }
    }

    public func setValue(ofSlider slider: Widget, to value: Double) {
        let slider = slider as! Scale

        slider.withBlockedSignal(named: "value-changed") {
            slider.value = value
        }
    }

    public func createTextField() -> Widget {
        Entry()
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
            onChange(widget.text)
        }
        textField.activate = { _ in
            onSubmit()
        }

        textField.css.clear()
        textField.css.set(properties: cssProperties(for: environment, isControl: true))
    }

    public func setContent(ofTextField textField: Widget, to content: String) {
        let textField = textField as! Entry
        textField.withBlockedSignal(named: "changed") {
            textField.text = content
        }
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
        return textEditor
    }

    public func updateTextEditor(
        _ textEditor: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (String) -> Void
    ) {
        let textEditor = textEditor as! Gtk.TextView

        // Every other control honours `.disabled` through `sensitive` (see
        // updateTextField, updateButton, updateDatePicker); the text editor was
        // the one that did not, so a TextEditor inside a `.disabled(true)`
        // subtree stayed editable on GtkBackend while looking the same as one
        // that was not.
        //
        // 其他每一個控制項都透過 `sensitive` 遵從 `.disabled`（見 updateTextField、updateButton、
        // updateDatePicker）；唯獨 text editor 沒有，因此位於 `.disabled(true)` 子樹中的
        // TextEditor 在 GtkBackend 上仍可編輯，外觀卻與未被 disable 者相同。
        textEditor.sensitive = environment.isEnabled

        textEditor.buffer.changed = { buffer in
            onChange(buffer.text)
        }

        textEditor.css.clear()
        textEditor.css.set(properties: cssProperties(for: environment, isControl: false))
        textEditor.css.set(property: CSSProperty(key: "background", value: "none"))
    }

    public func setContent(ofTextEditor textEditor: Widget, to content: String) {
        let textEditor = textEditor as! Gtk.TextView

        textEditor.buffer.withBlockedSignal(named: "changed") {
            textEditor.buffer.text = content
        }
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
        picker.cssProvider.loadCss(from: block.stringRepresentation)

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
        picker.cssProvider.loadCss(from: block.stringRepresentation)
    }

    public func setSelectedOption(ofPicker picker: Widget, to selectedOption: Int?) {
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
        // isIndeterminate. GtkBackend previously did `fraction = fraction ?? 0`,
        // which is a filled-in 0% bar in both cases.
        //
        // 不確定進度的 ProgressView（沒有值的那一種）必須要有動畫，否則看起來會像「卡在 0%」而
        // 非「進行中」。GTK 不會自行動畫：gtk_progress_bar_pulse 每呼叫一次才移動一格，因此不確定
        // 進度的 bar 需要有東西以計時器持續呼叫它。而只要設定了 `fraction`，該 widget 就會離開
        // activity mode，因此兩者互斥。
        //
        // AppKit 會切換 isIndeterminate 並呼叫 startAnimation；WinUI 設定 isIndeterminate。
        // GtkBackend 先前的做法是 `fraction = fraction ?? 0`，那在兩種情況下都是一條填滿 0% 的 bar。
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
        progressBar.cssProvider.loadCss(
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
            menu.cssProvider.loadCss(from: "")
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
        menu.cssProvider.loadCss(
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
        menu.popUpAtWidget(widget, relativePosition: position)
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
    }

    public func showAlert(
        _ alert: Alert,
        window: Window?,
        responseHandler handleResponse: @escaping (Int) -> Void
    ) {
        let target = window ?? windows[0]
        let key = ObjectIdentifier(target)

        // One alert per window at a time. If this window already has one up,
        // queue this behind it instead of stacking a second modal dialog.
        guard shownAlert[key] == nil else {
            pendingAlerts[key, default: []].append((alert, target, handleResponse))
            return
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
        alert.response = { [weak self] _, responseId in
            guard responseId != Int(UInt32(bitPattern: -4)) else {
                // Ignore escape key for now. Once we support detecting
                // the primary and secondary actions of alerts we can wire
                // this up to whichever action is the default cancellation
                // action.
                return
            }

            alert.destroy()
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
        let next = queue.removeFirst()
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
        // when no xdg-desktop-portal is present, as under WSLg: the response
        // arrives and the app gets the file, but the window stays on screen.
        // A stock GTK4 app using GtkFileDialog closes correctly in the same
        // session, which is what identified the API rather than our use of it.
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

    public func createPathWidget() -> Widget {
        DrawingArea()
    }

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
        let drawingArea = container as! Gtk.DrawingArea

        // We don't actually care about leaking backends, but might as well use
        // a weak reference anyway.
        drawingArea.setDrawFunc { [weak self] cairo, _, _ in
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

            let fillPattern = cairo_pattern_create_rgba(
                Double(fillColor.red),
                Double(fillColor.green),
                Double(fillColor.blue),
                Double(fillColor.opacity)
            )
            cairo_set_source(cairo, fillPattern)
            cairo_fill_preserve(cairo)
            cairo_pattern_destroy(fillPattern)

            let strokePattern = cairo_pattern_create_rgba(
                Double(strokeColor.red),
                Double(strokeColor.green),
                Double(strokeColor.blue),
                Double(strokeColor.opacity)
            )
            cairo_set_source(cairo, strokePattern)
            cairo_stroke(cairo)
            cairo_pattern_destroy(strokePattern)
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
    // already declared near the top of this type, alongside the other backend
    // constants -- they were there before Tables was conformed to, waiting for
    // the rest.
    // defaultTableRowContentHeight 與 defaultTableCellVerticalPadding 已在本型別開頭、與其他
    // backend 常數一同宣告——它們在 Tables 被實作之前就已存在，等著其餘部分補上。

    public func createTable() -> Widget {
        Gtk.Table()
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
        table.css.clear()
        table.css.set(properties: cssProperties(for: environment))
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
        datePicker.update(
            date: date,
            range: range,
            style: environment.backendDatePickerStyle,
            components: components,
            displayCalendar: environment.calendar,
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
    private func cssProperties(
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

        // A control's chrome, for the case where the theme cannot supply it.
        //
        // Added in 5c89d3e0 alongside the `colorScheme` modifier, so that an app
        // forcing a scheme got controls to match. It ran unconditionally, which
        // made it the single most destructive thing this backend did: the
        // provider outranks the theme, so an explicit background here beats
        // every state and style class Adwaita ships -- `:hover`, `:checked`,
        // `.suggested-action`, `.destructive-action`. Measured 2026-08-28: a
        // button carrying `suggested-action` rendered the same flat rgb(73,73,73)
        // as a plain one, while `gtk_widget_has_css_class` confirmed the class
        // was on the widget. The class was landing; this was overruling it.
        //
        // Three call sites had already worked around it one at a time -- the
        // toggle and the text editor pass `isControl: false`, and a button with
        // a role passes `deferToThemeStyleClass` -- which is what says the
        // default was wrong rather than its callers.
        //
        // Now it fires only when the theme is drawing the wrong scheme, which is
        // the case it was written for. When the theme agrees, standing down
        // costs nothing measurable and returns the theme's border: on P2, dark
        // Adwaita, the enforced button had edge and interior both rgb(73,73,73)
        // and the theme's had a distinct rgb(56,56,56) edge.
        //
        // Not to be confused with the entry focus ring, which this block never
        // affected: GTK 4 draws that with `outline`, which is not set here.
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

    public func createSheet(content: Widget) -> Sheet {
        let sheet = Sheet()
        sheet.setChild(content)

        // Listen for interactive dismissals
        sheet.onCloseRequest = { [weak self, weak sheet] _ in
            guard let self, let sheet else {
                return
            }

            self.runInMainThread {
                self.dismissSheet(sheet)
                sheet.onDismiss?()
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
                sheet.onDismiss?()
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
        sheet.css.clear()
        sheet.css.set(
            property: .border(
                color: SwiftCrossUI.Color.gray.resolve(in: environment).gtkColor,
                width: 1
            )
        )

        // Respect corner radius and background Color
        let radius = cornerRadius.map(Int.init) ?? defaultSheetCornerRadius
        sheet.css.set(property: .cornerRadius(radius))
        if let backgroundColor {
            sheet.css.set(property: .backgroundColor(backgroundColor.gtkColor))
        }

        sheet.interactiveDismissDisabled = interactiveDismissDisabled

        // - detents are only supported on mobile so we ignore them.
        // - dragIndicatorVisibility is only supported on mobile so we ignore it.
    }

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

    public func dismissSheet(_ sheet: Sheet, window: Window, parentSheet: Sheet?) {
        dismissSheet(sheet)
        parentSheet?.nestedSheet = nil
    }

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
            nestedSheet.destroy()
            nestedSheet.onDismiss?()
        }

        sheet.destroy()
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

private final class SelectableListState {
    var selection: Int? = nil
    var rowCount = 0
    var isProgrammaticSelectionUpdate = false
    var isClearingNilSelection = false
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

class CustomLabel: Label {
    override func setSizeRequest(width: Int, height: Int) {
        super.setSizeRequest(width: width, height: height)

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
    private let hourMinuteSeparator = Label(string: ":")
    private let minutePicker = SpinButton(range: 0, max: 59, step: 1)
    private var minuteSecondSeparator: Label?
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
                minuteSecondSeparator = Label(string: ":")
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
            grid.css.clear()
            grid.css.set(properties: gridProperties)
        }
        if let button {
            button.css.clear()
            button.css.set(properties: buttonProperties)
            // The grid in the popover is a grid, and gets the grid's treatment.
            button.grid.css.clear()
            button.grid.css.set(properties: gridProperties)
        }
        if let timeRow {
            // A spin button keeps its frame for the same reason the compact
            // button does. The font and colour have to land here rather than on
            // the container, because a spin button's text sits in a `text` node
            // and the descendant `label` selector never reaches it.
            timeRow.css.clear()
            timeRow.css.set(properties: buttonProperties)
        }
    }

    private static func contents(
        for style: BackendDatePickerStyle,
        components: DatePickerComponents,
        calendar: Foundation.Calendar
    ) -> Contents {
        let presentation: Presentation? =
            switch style {
                case .compact:
                    .button
                case .automatic, .graphical:
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
            calendar: time == nil ? nil : calendar
        )
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
                grid.daySelected = { [weak self] grid in
                    self?.daySelected(shownBy: grid)
                }
                // Adding is what registers the signal (see Widget.parentWidget),
                // so the handler has to be in place first.
                add(grid)
                self.grid = grid
            case .button:
                let button = CompactDatePicker()
                button.grid.daySelected = { [weak self] grid in
                    self?.daySelected(shownBy: grid)
                }
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
/// This is not the first attempt in this file. The abandoned `TimePicker` above
/// it recorded "I couldn't get the spin buttons to work"; two reasons it did
/// not, both avoided here:
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

        add(hourField)
        add(Label(string: ":"))
        add(minuteField)
        if let secondField {
            add(Label(string: ":"))
            add(secondField)
        }
        if let meridiemField {
            meridiemField.notifySelected = { [weak self] _, _ in self?.fieldChanged() }
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
