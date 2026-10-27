import Foundation
@_spi(Backends) import SwiftCrossUI
import WinSDK
import WinUI
import WindowsFoundation

private let webViewDiagnosticsEnabled =
    CommandLine.arguments.contains("--debug")
    || ProcessInfo.processInfo.environment["SCUI_DEBUG_WEBVIEW"] == "1"

func logWebViewDiagnostic(_ message: @autoclosure () -> String) {
    guard webViewDiagnosticsEnabled else { return }
    logger.info("\(message())")
}

/// This thread's COM apartment, as `CoGetApartmentType` states it, for the
/// WebView2 timeline (P38). Logged at three points -- before
/// `SwiftApplication.main()`, in `onLaunched`, and where the web view starts --
/// because one reading can say WHAT the apartment is but not WHEN it became
/// that. `type` 0 STA, 1 MTA, 2 NA, 3 MAINSTA; `qualifier` 6 is an application
/// STA. `hr` 0x800401f0 (`CO_E_NOTINITIALIZED`) means COM is not initialised
/// on this thread yet.
///
/// 本執行緒的 COM apartment,以 `CoGetApartmentType` 的說法表示,供 WebView2 的時間軸使用(P38)。
/// 在三個時間點記錄——`SwiftApplication.main()` 之前、`onLaunched` 之中、web view 啟動之處——
/// 因為**單一讀數說得出 apartment 是什麼,卻說不出它是何時變成那樣的**。
func comApartmentDescription() -> String {
    var aptType = APTTYPE(rawValue: -1)
    var aptQualifier = APTTYPEQUALIFIER(rawValue: -1)
    let result = CoGetApartmentType(&aptType, &aptQualifier)
    return "thread=\(GetCurrentThreadId()) hr=\(String(format: "0x%08x", UInt32(bitPattern: result))) type=\(aptType.rawValue) qualifier=\(aptQualifier.rawValue)"
}

extension WinUIBackend: BackendFeatures.WebViews {
    public func createWebView() -> Widget {
        WebViewWidget()
    }

    public func updateWebView(
        _ webView: Widget,
        environment: EnvironmentValues,
        onNavigate: @escaping (URL) -> Void
    ) {
        let webView = webView as! WebViewWidget
        webView.onNavigate = onNavigate
        webView.startCoreIfNeeded()
    }

    public func navigateWebView(_ webView: Widget, to url: URL) {
        let webView = webView as! WebViewWidget
        webView.control.source = WindowsFoundation.Uri(url.absoluteString)
    }
}

/// A `WebView2` that reports the page it moved to.
///
/// Navigation is observed through the `Source` dependency property rather than
/// the control's `NavigationStarting` event. Both would work, but the event's
/// argument type (`CoreWebView2NavigationStartingEventArgs`) lives in the
/// `WebView2Core` module, which `WinUIBackend` does not depend on; reading
/// `Source` keeps every type used here inside `WinUI`. `Source` is the control's
/// own record of the top-level document, and it is updated for user-initiated
/// navigation as well as for navigation this backend asks for, which is exactly
/// the set of transitions `onNavigate` is meant to report.
///
/// The core is started explicitly; see `startCoreIfNeeded`.
///
/// 核心是明確啟動的；見 `startCoreIfNeeded`。
///
/// **A `Grid` HOLDING a `WebView2`, not a subclass of one -- and subclassing was
/// the crash.** Stack captured 2026-09-17 with cdb (WinDbg 1.2606, installed
/// through winget):
///
///     swiftCore!swift_retainCount+0x3d      read at f777f777`f777f780 -- freed-memory fill
///     P38_WinUI+0x8cd8f1                    Swift
///     Microsoft_UI_Xaml_Controls!com_ptr<IWeakReferenceSource>::release_ref (dtor)
///     Microsoft_UI_Xaml_Controls!WebView2::RegisterCoreEventHandlers+0x330
///     Microsoft_UI_Xaml_Controls!WebView2::CreateCoreWebViewFromEnvironment
///     EmbeddedBrowserWebView!...InitializeWebViewCompleted
///
/// When the core finishes, the control registers its event handlers and takes a
/// weak reference to its OUTER object. With a Swift subclass the outer object is
/// the Swift wrapper, and the release at the end of that call lands on a
/// reference the binding never added: the object is freed, then read. Outside a
/// debugger that surfaces as `c0000374` heap corruption. It never happened under
/// MTA because the core never finished there. A `Grid` subclass is the pattern
/// every other composite widget in this backend already uses; the control
/// inside it has no Swift outer at all.
///
/// **是持有 `WebView2` 的 `Grid`,而不是它的子類別——子類別化正是當機的原因。** 2026-09-17 以 cdb
/// (WinDbg 1.2606,經 winget 安裝)取得堆疊。core 完成時,控制項註冊事件處理器並對**它的外層物件**取一個 weak
/// reference。以 Swift 子類別化時,外層物件就是 Swift 包裝,而該呼叫結尾的 release 落在綁定層從未
/// 增加過的參考上:物件被釋放、接著被讀取。沒有除錯器時,它表現為 `c0000374` heap corruption。MTA 下
/// 從未發生,因為 core 在那裡從未完成。`Grid` 子類別是本 backend 其他複合 widget 早已採用的形狀;
/// 裡面那個控制項完全沒有 Swift 外層。
final class WebViewWidget: WinUI.Grid {
    /// The control, deliberately not subclassed. See the type's documentation.
    /// 控制項本身,刻意不子類別化。見本型別的文件。
    let control = WinUI.WebView2()
    var onNavigate: ((URL) -> Void)?

    private var startedCore = false
    /// Held so the async operation is not released the moment the call that
    /// started it returns. See `beginEnsureCore`.
    /// 持有它，好讓那個非同步操作不會在「啟動它的那次呼叫」一回傳就被釋放。詳見 `beginEnsureCore`。
    private var corePromise: WindowsFoundation.AnyIAsyncAction?
    /// Kept alive for the same reason an event handler always is: dropping the
    /// registration unsubscribes it.
    /// 之所以要讓它活著，理由與任何一個 event handler 相同：丟掉這個註冊，就等於取消訂閱。
    private var loadedRegistration: WindowsFoundation.EventCleanup?
    /// Starts the browser process, once.
    ///
    /// Called explicitly rather than left to the control's first navigation.
    /// Measured 2026-08-27 with P38 -- under the MTA in effect then, see
    /// `beginEnsureCore` -- `source` was set, the element was visible and
    /// sized 760x420, and `coreWebView2` stayed nil for the life of the app.
    /// An explicit call also yields a completion status to log.
    ///
    /// Called from `updateWebView` rather than `init` because
    /// `EnsureCoreWebView2Async` needs the element to be in the visual tree, and
    /// `createWebView` returns it before it is inserted.
    ///
    /// 啟動瀏覽器行程，僅一次。
    ///
    /// 明確呼叫，而不是交給控制項的第一次導覽。2026-08-27 以 P38 實測(當時仍是 MTA,見 `beginEnsureCore`):
    /// `source` 已設定、元素可見且尺寸為 760x420，而 `coreWebView2` 在整個 app 生命週期中始終為 nil。
    /// 明確呼叫也能取得一個可記錄的完成狀態。
    ///
    /// 由 `updateWebView` 呼叫而非 `init`，因為 `EnsureCoreWebView2Async` 需要元素已位於視覺樹中，
    /// 而 `createWebView` 是在其被插入之前就回傳的。
    @MainActor
    func startCoreIfNeeded() {
        guard !startedCore else { return }
        startedCore = true

        // WAIT FOR `Loaded`, do not merely wait for `updateWebView`.
        //
        // Being IN the visual tree is not the same as being LOADED -- there is
        // still a layout pass in between, and `EnsureCoreWebView2Async` wants
        // the second one; `isLoaded` was measured false at `updateWebView`. An
        // operation that never completes looks the same as one that completed
        // with a failure nobody read, so this is not left to chance.
        //
        // `isLoaded` is logged, so a reader can tell which case this was. If it
        // is already true, the element was ready and the wait costs nothing.
        //
        // **等 `Loaded`，而不只是等 `updateWebView`。**
        //
        // **「在視覺樹裡」與「已載入」並不是同一回事**——兩者之間還隔著一次 layout pass，而
        // `EnsureCoreWebView2Async` 要的是後者；實測 `updateWebView` 時 `isLoaded` 為 false。**一個永不
        // 完成的操作，與一個「完成了但沒人讀那個失敗」的操作，看起來一模一樣**,所以此處不碰運氣。
        //
        // 此處會記下 `isLoaded`，好讓讀者能直接看出這是哪一種情況。若它本來就是 true，那元素早已就緒，
        // 這次等待不花任何代價。
        let alreadyLoaded = control.isLoaded
        logWebViewDiagnostic("WebView2: starting core, isLoaded=\(alreadyLoaded)")

        if alreadyLoaded {
            beginEnsureCore()
        } else {
            loadedRegistration = control.loaded.addHandler { [weak self] _, _ in
                guard let self else { return }
                logWebViewDiagnostic("WebView2: Loaded fired, starting core now")
                self.beginEnsureCore()
            }
        }
    }

    /// Calls `EnsureCoreWebView2Async` and KEEPS the operation alive.
    ///
    /// The returned `IAsyncAction` is stored rather than held in a local,
    /// which would be released as soon as this function returned and could
    /// leave the completion handler unreached. A strong reference costs one
    /// property.
    ///
    /// 呼叫 `EnsureCoreWebView2Async`，並且**讓那個操作活著**。
    ///
    /// 回傳的 `IAsyncAction` 存在屬性中，而不是區域變數；區域變數會在函式一回傳時就被釋放，可能讓
    /// completion handler 永遠不被呼叫。**一個強參照的代價不過是一個屬性。**
    @MainActor
    private func beginEnsureCore() {
        let webViewThread = GetCurrentThreadId()
        logWebViewDiagnostic("WebView2: beginEnsureCore on thread \(webViewThread)")
        // Why WebView2 needs a single-threaded apartment when nothing else in
        // this backend does: `EnsureCoreWebView2Async` finishes by posting a
        // completion back to the caller's apartment. An STA has a message
        // queue to post into; an MTA does not, so under MTA the operation is
        // never reported as finished -- no error, no completion, the browser
        // process starts (the loader is apartment-agnostic), and no profile is
        // written. XAML itself is fine in MTA because it has its own
        // `DispatcherQueue`; WebView2 goes through COM's route.
        //
        // The probe below asks `CoInitializeEx` for STA:
        //
        //   RPC_E_CHANGED_MODE (0x80010106) -- the thread is already in another
        //                                      apartment and the request was
        //                                      refused.
        //   S_FALSE (0x1)                   -- already STA.
        //   S_OK (0x0)                      -- was not initialised at all.
        //
        // Balanced with `CoUninitialize` only when it actually initialised,
        // because an unbalanced uninit tears down someone else's apartment.
        //
        // 為什麼本 backend 中只有 WebView2 需要單執行緒 apartment:`EnsureCoreWebView2Async` 的最後一步，
        // 是把「完成」**回投到呼叫端的 apartment**。STA 有訊息佇列可供投遞,MTA **沒有**,因此在 MTA 下
        // 那個操作永遠不會被回報為完成——沒有錯誤、沒有完成、瀏覽器行程起得來(loader 與 apartment 無關)、
        // 沒有 profile 被寫出。XAML 本身在 MTA 下沒問題，因為它有自己的 `DispatcherQueue`;WebView2 走的是
        // COM 那條路。
        //
        // 下方的探針向 `CoInitializeEx` 要求 STA:
        //   RPC_E_CHANGED_MODE(0x80010106)——這條執行緒已處於另一種 apartment,請求被拒絕。
        //   S_FALSE(0x1)——已經是 STA。
        //   S_OK(0x0)——原本根本沒有初始化過。
        //
        // 只有在它**確實初始化了**時才以 `CoUninitialize` 配對，因為不成對的 uninit 會拆掉
        // 別人的 apartment。
        if webViewDiagnosticsEnabled {
            let staProbe = CoInitializeEx(nil, DWORD(COINIT_APARTMENTTHREADED.rawValue))
            logWebViewDiagnostic(
                "WebView2: CoInitializeEx(STA) returned \(String(format: "0x%08x", UInt32(bitPattern: staProbe)))"
            )
            if staProbe == S_OK || staProbe == S_FALSE {
                CoUninitialize()
            }
        }

        // `CoGetApartmentType` as well, because the probe above cannot tell
        // MTA from ASTA: `RPC_E_CHANGED_MODE` means "not a classic STA", and a
        // XAML UI thread is usually an application STA, which refuses a
        // classic STA with the same code. APTTYPE: 0 STA, 1 MTA, 2 NA,
        // 3 MAINSTA; qualifier 6 is APPLICATION_STA.
        //
        // What it established (2026-09-16/17), and why the web view works:
        //
        // (1) Under swift-winui's `SwiftApplication.main()` the thread is type
        //     1, a genuine MTA, because of its `threadingModel: .multi`; under
        //     MTA the core handshake never completes (`EBWebView/` never gains
        //     `Default/` or `Local State`). WinUIApplication+SingleThreaded.swift
        //     starts the app with `.single`, which reads type 3 (MAINSTA).
        // (2) Under STA the handshake completes, and subclassing `WebView2` in
        //     Swift then corrupted the heap (`c0000374`); see `WebViewWidget`.
        //     The widget is a `Grid` holding the control.
        //
        // Both halves are needed: the same `Grid` widget under `.multi` stays
        // type 1 and never completes in 45 s. When editing swift-winui to test
        // this, note that there can be several checkouts (`.build/checkouts`,
        // `testapp/.compile-work-winui/...`, `.compile-work-gtk4/...`); a
        // recompile of the module does not prove the edited copy was compiled.
        //
        // 另外呼叫 `CoGetApartmentType`,因為上面那個探針**分不出 MTA 與 ASTA**:`RPC_E_CHANGED_MODE`
        // 的意思是「不是傳統 STA」,而 XAML 的 UI 執行緒通常是 application STA,在那裡要求傳統 STA,
        // 拒絕碼一模一樣。APTTYPE:0 STA、1 MTA、2 NA、3 MAINSTA;qualifier 6 是 APPLICATION_STA。
        //
        // 它確立了什麼(2026-09-16/17),以及 web view 為何能運作:
        //
        // (1) 在 swift-winui 的 `SwiftApplication.main()` 下，這條執行緒是 type 1,**真正的 MTA**,
        //     來自它的 `threadingModel: .multi`;MTA 下 core 交握永不完成(`EBWebView/` 從未出現
        //     `Default/` 或 `Local State`)。WinUIApplication+SingleThreaded.swift 以 `.single` 啟動
        //     app,讀到的是 type 3(MAINSTA)。
        // (2) STA 下交握會完成，而在 Swift 子類別化 `WebView2` 接著就破壞了 heap(`c0000374`);見
        //     `WebViewWidget`。widget 是持有該控制項的 `Grid`。
        //
        // **兩半都需要**:同一個 `Grid` widget 在 `.multi` 下維持 type 1、45 秒內從未完成。若要修改
        // swift-winui 來測試，注意可能有好幾份 checkout(`.build/checkouts`、`testapp/.compile-work-winui/...`、
        // `.compile-work-gtk4/...`);該模組有重編，並不證明被改的那份有被編到。
        logWebViewDiagnostic("WebView2: apartment at beginEnsureCore \(comApartmentDescription())")

        guard let promise = try? control.ensureCoreWebView2Async() else {
            logger.warning("WebView2: EnsureCoreWebView2Async threw immediately")
            return
        }
        corePromise = promise

        // Two things above are required, not incidental: the wait for `Loaded`
        // (`isLoaded` is false at `updateWebView`) and `corePromise`. Two
        // hypotheses were refuted on 2026-09-10 and need not be re-tested: the
        // WebView2 Runtime is installed (152.0.4191.66) and `msedgewebview2.exe`
        // does start; and polling `coreWebView2` directly, bypassing the
        // handler, stayed nil under MTA for 40 s, so the operation genuinely
        // does not complete there. A 2 s or 6 s window cannot tell "never
        // completes" from "slow cold start".
        //
        // To reproduce with a poller, print BEFORE the polling loop as well: a
        // `Task` with no executor silently never runs, and zero poll lines
        // reads exactly like "polled and always nil".
        //
        // 上方兩件事是必要的，不是附帶的：等待 `Loaded`(`updateWebView` 時 `isLoaded` 為 false)與
        // `corePromise`。2026-09-10 已推翻兩個假設，無須重測:WebView2 Runtime 有裝(152.0.4191.66)且
        // `msedgewebview2.exe` 確實會啟動；繞過 handler 直接輪詢 `coreWebView2`,在 MTA 下 40 秒都是 nil,
        // 所以那個操作在那裡是真的沒有完成。2 秒或 6 秒的窗口分不出「永不完成」與「冷啟動很慢」。
        //
        // 若要以輪詢重現，**在迴圈之前也印一行**:沒有 executor 的 `Task` 會靜默地不執行，而「零行 poll」
        // 看起來與「輪詢了、但每次都是 nil」一模一樣。
        promise.completed = { [weak self] _, status in
            guard status == .completed else {
                logger.warning(
                    "WebView2: the browser process did not start (status \(status))"
                )
                return
            }
            logWebViewDiagnostic("WebView2: the browser process started")
            _ = self
        }
    }

    override init() {
        super.init()
        children.append(control)

        _ = try? control.registerPropertyChangedCallback(WinUI.WebView2.sourceProperty) { [weak self] _, _ in
            guard let self, let source = self.control.source else { return }
            guard let url = URL(string: source.absoluteUri) else {
                logger.warning("web view navigated to an unparseable URL")
                return
            }
            self.onNavigate?(url)
        }
    }
}
