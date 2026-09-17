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
/// **This used to say the control starts its rendering process on demand, so
/// nothing had to call `EnsureCoreWebView2Async`. That is false**, and it is the
/// reason the web view drew nothing at all for as long as it has existed. See
/// `startCoreIfNeeded`, and the still-open half of the problem recorded in
/// todo.md.
///
/// **此處原本寫著：控制項會按需啟動其繪製行程，因此無須任何人呼叫 `EnsureCoreWebView2Async`。
/// 那是錯的**，而那正是這個 web view 自存在以來什麼都畫不出來的原因。詳見 `startCoreIfNeeded`，
/// 以及記錄於 todo.md、尚未解決的另一半問題。
///
/// **A `Grid` HOLDING a `WebView2`, not a subclass of one -- and subclassing was
/// the crash.** Stack captured 2026-09-17 with cdb (WinDbg 1.2606, installed
/// through winget; an earlier note said this machine had no debugger, which
/// was checked only against PATH and `Windows Kits\10\Debuggers`):
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
/// 取得堆疊(WinDbg 1.2606,經 winget 安裝;先前寫「本機沒有除錯器」的那句,只查過 PATH 與
/// `Windows Kits\10\Debuggers`)。core 完成時,控制項註冊事件處理器並對**它的外層物件**取一個 weak
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
    /// The documentation on this class used to say the control starts the
    /// rendering process on demand the first time it is asked to navigate, so
    /// nothing had to call this. Measured 2026-08-27 with P38: it does not.
    /// `source` was set to the requested URL, the element was visible and sized
    /// 760x420, and `coreWebView2` stayed nil for the life of the app while the
    /// frame drew nothing.
    ///
    /// Called from `updateWebView` rather than `init` because
    /// `EnsureCoreWebView2Async` needs the element to be in the visual tree, and
    /// `createWebView` returns it before it is inserted.
    ///
    /// 啟動瀏覽器行程，僅一次。
    ///
    /// 本類別先前的文件說：控制項會在第一次被要求導覽時自行按需啟動繪製行程，因此無須任何人呼叫
    /// 此方法。2026-08-27 以 P38 實測：它並不會。`source` 已設為所要求的 URL、元素可見且尺寸為
    /// 760x420，而 `coreWebView2` 在整個 app 生命週期中始終為 nil，該框也什麼都沒畫。
    ///
    /// 由 `updateWebView` 呼叫而非 `init`，因為 `EnsureCoreWebView2Async` 需要元素已位於視覺樹中，
    /// 而 `createWebView` 是在其被插入之前就回傳的。
    @MainActor
    func startCoreIfNeeded() {
        guard !startedCore else { return }
        startedCore = true

        // WAIT FOR `Loaded`, do not merely wait for `updateWebView`.
        //
        // The previous version called `EnsureCoreWebView2Async` straight from
        // `updateWebView`, on the reasoning that the element is in the visual
        // tree by then. Being IN the tree is not the same as being LOADED --
        // there is still a layout pass in between, and `EnsureCoreWebView2Async`
        // wants the second one. Measured symptom (todo.md): `coreWebView2` nil
        // at +2s and +6s, and the completion handler never firing with ANY
        // status. An operation that never completes looks the same as one that
        // completed with a failure nobody read.
        //
        // `isLoaded` is logged, so the next reader can tell which case this was
        // rather than re-deriving it. If it is already true, the element was
        // ready and the wait costs nothing.
        //
        // **等 `Loaded`，而不只是等 `updateWebView`。**
        //
        // 先前的版本直接從 `updateWebView` 呼叫 `EnsureCoreWebView2Async`，理由是到那時元素已經
        // 位於視覺樹中。**「在樹裡」與「已載入」並不是同一回事**——兩者之間還隔著一次 layout pass，
        // 而 `EnsureCoreWebView2Async` 要的是後者。實測到的症狀（見 todo.md）：`coreWebView2`
        // 在 +2 秒與 +6 秒時皆為 nil，而 completion handler 帶著**任何** status 都不曾觸發。
        // **一個永不完成的操作，與一個「完成了但沒人讀那個失敗」的操作，看起來一模一樣。**
        //
        // 此處會記下 `isLoaded`，好讓下一位讀者能直接看出這是哪一種情況，而不必重新推導。
        // 若它本來就是 true，那元素早已就緒，這次等待不花任何代價。
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
    /// The returned `IAsyncAction` was a local before, so it was released as
    /// soon as this function returned. That is the second candidate for a
    /// completion handler that never fires, and it is stored now rather than
    /// argued about -- a strong reference costs one property.
    ///
    /// 呼叫 `EnsureCoreWebView2Async`，並且**讓那個操作活著**。
    ///
    /// 先前它回傳的 `IAsyncAction` 是一個區域變數，因此函式一回傳它就被釋放。那是
    /// 「completion handler 從不觸發」的第二個候選原因；此處直接把它存起來，而不是拿它來爭論——
    /// **一個強參照的代價不過是一個屬性。**
    @MainActor
    private func beginEnsureCore() {
        let webViewThread = GetCurrentThreadId()
        logWebViewDiagnostic("WebView2: beginEnsureCore on thread \(webViewThread)")
        // ============================================================
        // THE CAUSE, CONFIRMED 2026-09-10: this thread is MTA, and WebView2
        // needs STA.
        //
        // The line below prints `0x80010106` -- `RPC_E_CHANGED_MODE`. That
        // return means the thread is ALREADY in a different apartment and the
        // request to make it single-threaded was refused. It is not an
        // inference; it is COM saying which apartment it is in.
        //
        // WHY: `SwiftApplication.main()` in swift-winui wraps the whole app in
        // `WindowsAppRuntimeInitializer(threadingModel: .multi)`. So the UI
        // thread is MTA by construction, in a dependency, before any of this
        // runs.
        //
        // WHY THAT BREAKS EXACTLY THIS AND NOTHING ELSE: `EnsureCoreWebView2Async`
        // finishes by posting a completion back to the caller's apartment. An
        // STA has a message queue to post into; an MTA does not. So the
        // operation is never reported as finished -- and every symptom follows
        // from that one fact:
        //
        //   no error          nobody failed, nobody was told
        //   no completion     there is no queue to deliver it on
        //   browser starts    that is the loader, which is apartment-agnostic
        //   no profile        that is written after the handshake completes
        //
        // XAML itself is fine in MTA because it has its own `DispatcherQueue`.
        // WebView2 goes through COM's route, not XAML's, which is why every
        // other control in this backend works.
        //
        // THE FIX IS UPSTREAM and is one word: `.multi` -> `.single` in
        // swift-winui. It was tried here on 2026-09-10 by editing the checkout,
        // and the experiment did NOT run -- SwiftPM never recompiled the module
        // (`Compiling WinUI` zero hits; the object file was a day OLDER than the
        // edited source). The checkout was restored. So the fix is identified
        // and NOT yet verified, and this comment says which of those two it is.
        //
        // ~~"THE FIX IS UPSTREAM and is one word: `.multi` -> `.single`"~~
        // **RUN AND REFUTED, 2026-09-16.** The experiment was made to actually
        // run this time, and the fix does not work.
        //
        //   `.multi` -> `.single` in the checkout, then the WinUI module's build
        //   products deleted so it could not be skipped. POSITIVE CONTROL:
        //   `Compiling WinUI` = 2 hits, against the 0 that made the first
        //   attempt meaningless. The change was genuinely in the binary.
        //
        //   The probe still returned `0x80010106`.
        //
        // The obvious escape -- "RoInitialize ran on a different thread from the
        // WebView" -- was measured and closed too: `WinUIApplication.main()`
        // logs thread 18076 and `beginEnsureCore` logs thread 18076. Same
        // thread. So `RoInitialize(RO_INIT_SINGLETHREADED)` succeeded on this
        // very thread and the thread was STILL not STA by the time WebView2
        // asked.
        //
        // What that leaves: something between `RoInitialize` and here puts the
        // thread into the multi-threaded apartment -- `Application.start`, the
        // WindowsAppRuntime bootstrapper, or the XAML dispatcher setup. THAT is
        // the next thing to measure, and it is a different question from the one
        // this comment used to answer.
        //
        // ~~「修法在上游,而且只有一個字:`.multi` → `.single`」~~
        // **2026-09-16 實際跑過並推翻。** 這一次那個實驗被真正跑起來了,而該修法**無效**。
        //
        //   在 checkout 中把 `.multi` 改為 `.single`,接著刪掉 WinUI 模組的建置產物,使它無法被略過。
        //   **正對照組**:`Compiling WinUI` **命中 2 次**,相對於讓第一次嘗試毫無意義的那個 0。
        //   那個改動確實進到了二進位檔裡。
        //
        //   而探針**仍然**回傳 `0x80010106`。
        //
        // 那個顯而易見的脫身說法——「`RoInitialize` 跑在與 WebView 不同的執行緒上」——也已量測並排除:
        // `WinUIApplication.main()` 記錄的是執行緒 18076,`beginEnsureCore` 記錄的也是 18076。
        // **同一條。** 因此 `RoInitialize(RO_INIT_SINGLETHREADED)` 就是在這條執行緒上成功的,
        // 而等到 WebView2 來問的時候,它**依然**不是 STA。
        //
        // 剩下的可能:在 `RoInitialize` 與此處之間,有東西把這條執行緒放進了多執行緒 apartment
        // ——`Application.start`、WindowsAppRuntime 的 bootstrapper,或 XAML 的 dispatcher 設定。
        // **那才是下一個該量的東西**,而它與本註解原先所回答的,是不同的問題。
        //
        // ============================================================
        // **成因,2026-09-10 已確認:這條執行緒是 MTA,而 WebView2 需要 STA。**
        //
        // 下方那一行印出 `0x80010106`——`RPC_E_CHANGED_MODE`。該回傳值的意思是:這條執行緒
        // **已經**處於另一種 apartment,而「把它改成單執行緒」的請求被拒絕了。**這不是推論,
        // 而是 COM 自己說出它在哪一種 apartment。**
        //
        // **為什麼**:swift-winui 的 `SwiftApplication.main()` 用
        // `WindowsAppRuntimeInitializer(threadingModel: .multi)` 包住了整個 app。因此 UI 執行緒
        // 從構造上就是 MTA——發生在一個相依套件裡,而且早於此處的一切。
        //
        // **為什麼那恰好只弄壞這一項**:`EnsureCoreWebView2Async` 的最後一步,是把「完成」
        // **回投到呼叫端的 apartment**。STA 有訊息佇列可供投遞,MTA **沒有**。於是那個操作永遠
        // 不會被回報為完成——而此處每一個症狀都由這一件事推導而出:沒有錯誤(沒有人失敗,
        // 只是沒有人被通知)、沒有完成(沒有佇列可送達)、瀏覽器起得來(那是 loader,與
        // apartment 無關)、沒有 profile(那要等交握完成之後才寫)。
        //
        // XAML 本身在 MTA 下沒問題,因為它有自己的 `DispatcherQueue`。**WebView2 走的是 COM
        // 那條路,不是 XAML 那條**,這正是本 backend 中其他每一個控制項都能運作的原因。
        //
        // **修法在上游,而且只有一個字**:swift-winui 裡的 `.multi` → `.single`。2026-09-10
        // 曾以修改 checkout 的方式在此嘗試,而**那次實驗並未執行**——SwiftPM 從未重新編譯該模組
        // (`Compiling WinUI` 零命中;目的檔比被編輯的原始檔還**舊**一天)。該 checkout 已還原。
        // 因此:**修法已確認、尚未驗證**,而本註解明說它是這兩者中的哪一個。
        // `CoInitializeEx` asking for STA rather than `CoGetApartmentType`,
        // because it needs no COM enum types in scope and gives a sharper
        // answer:
        //
        //   RPC_E_CHANGED_MODE (0x80010106) -- the thread is ALREADY MTA, and
        //                                      the request to make it STA was
        //                                      refused. That is the hypothesis.
        //   S_FALSE (0x1)                   -- already STA. Hypothesis dead.
        //   S_OK (0x0)                      -- was not initialised at all.
        //
        // Balanced with `CoUninitialize` only when it actually initialised,
        // because an unbalanced uninit tears down someone else's apartment.
        //
        // 此處用「向 `CoInitializeEx` 要求 STA」而非 `CoGetApartmentType`,因為它不需要任何 COM
        // 列舉型別在 scope 中,而且給出的答案更銳利:
        //   RPC_E_CHANGED_MODE(0x80010106)——這條執行緒**已經是 MTA**,而「把它變成 STA」的
        //                                    請求被拒絕。**那正是本假設。**
        //   S_FALSE(0x1)——已經是 STA。假設當場死亡。
        //   S_OK(0x0)——原本根本沒有初始化過。
        //
        // 只有在它**確實初始化了**時才以 `CoUninitialize` 配對,因為不成對的 uninit 會拆掉
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

        // `CoGetApartmentType` as well, because the probe above CANNOT tell MTA
        // from ASTA and the whole diagnosis above rests on it being MTA.
        // `RPC_E_CHANGED_MODE` means "not a classic STA" -- a XAML UI thread is
        // usually an APPLICATION STA (ASTA), and asking an ASTA thread for a
        // classic STA is refused with the same code. The comment above chose
        // `CoInitializeEx` because it "needs no COM enum types", and that
        // convenience is exactly the ambiguity. APTTYPE: 0 STA, 1 MTA, 2 NA,
        // 3 MAINSTA; qualifier 6 is APPLICATION_STA.
        //
        // 另外呼叫 `CoGetApartmentType`,因為上面那個探針**分不出 MTA 與 ASTA**,而上方整段診斷
        // 都建立在「它是 MTA」之上。`RPC_E_CHANGED_MODE` 的意思是「不是傳統 STA」——XAML 的 UI
        // 執行緒通常是 **APPLICATION STA(ASTA)**,而在 ASTA 執行緒上要求傳統 STA,拒絕碼一模一樣。
        // 上方選 `CoInitializeEx` 的理由是「不需要 COM 列舉型別」,而那份方便正是這個歧義的來源。
        //
        // ============================================================
        // 2026-09-16, THIRD PASS: the "RUN AND REFUTED" above was itself wrong,
        // and the real state is one step further along.
        //
        // (1) THE APARTMENT, measured with `CoGetApartmentType` at three points
        //     (`comApartmentDescription`): before `SwiftApplication.main()` the
        //     thread is `CO_E_NOTINITIALIZED` -- nothing initialised COM first --
        //     and in `onLaunched` and here it is type 1, a genuine MTA with no
        //     qualifier. Not ASTA. So `.multi` in swift-winui is the whole cause
        //     of the MTA, and nothing "between RoInitialize and here" changes it.
        //
        // (2) WHY THE `.single` EXPERIMENT SAID OTHERWISE: there are THREE
        //     swift-winui checkouts -- `.build/checkouts`,
        //     `testapp/.compile-work-winui/...` and `.compile-work-gtk4/...` --
        //     and P38-WinUI is built from `.compile-work-winui`. The record says
        //     "checkout edited" without saying which, and its positive control
        //     (`Compiling WinUI` = 2 hits) proves a recompile, NOT that the
        //     edited copy was the one compiled. Edited in `.compile-work-winui`
        //     this time, the apartment reads type 3 (MAINSTA) and
        //     `CoInitializeEx(STA)` returns S_FALSE. The fix DOES take effect.
        //
        // (3) AND WITH IT, THE HANDSHAKE COMPLETES: `EBWebView/` gains
        //     `Default/` and `Local State`, which it never had under MTA. So the
        //     MTA diagnosis was right all along.
        //
        // (4) BUT THE PROCESS THEN DIES: `c0000374` STATUS_HEAP_CORRUPTION in
        //     ntdll (Windows Error Reporting, Application Error 1000), roughly a
        //     second after core init starts, before the first `onAppear`. A
        //     non-WebView app (P42-WinUI) under the same `.single` build is
        //     fine: MAINSTA, renders, stays up. Bisected with environment
        //     switches, all under STA, 15 s each:
        //
        //       no core init, no Source set     -> alive, renders
        //       Source set only (implicit init) -> heap corruption
        //       ensureCoreWebView2Async only    -> heap corruption
        //       both                            -> heap corruption
        //
        //     and separately, with the `completed` handler AND the `Source`
        //     property callback both skipped -> still heap corruption. So it is
        //     not this file's callbacks: ANY WebView2 core initialisation
        //     corrupts the heap once COM lets it proceed. Under MTA the same
        //     code path was simply never reached, because the handshake never
        //     completed.
        //
        // ~~NEXT, and it needs a debugger this machine does not have (no cdb,
        // WinDbg or procdump)~~ -- WRONG: WinDbg 1.2606 IS installed, through
        // winget, and `cdbX64.exe` is an execution alias under
        // `%LOCALAPPDATA%\Microsoft\WindowsApps`. The check looked only at PATH
        // and `Windows Kits\10\Debuggers`; the user asked for winget and scoop
        // to be checked and winget had it.
        //
        // (5) RESOLVED 2026-09-17 with that debugger. The stack is on
        //     `WebViewWidget`: subclassing `WebView2` in Swift is the heap
        //     corruption, and the widget is now a `Grid` holding one. Under
        //     `.single` P38 then renders example.com and reports two
        //     navigations. CONTROL: the same `Grid` widget under `.multi` stays
        //     type 1 and never completes in 45 s -- so BOTH halves are needed,
        //     the container and the single-threaded apartment.
        //
        // ~~下一步需要本機沒有的除錯器~~——**錯**:WinDbg 1.2606 **有裝**(winget),`cdbX64.exe`
        // 是 `%LOCALAPPDATA%\Microsoft\WindowsApps` 下的執行別名。先前只查了 PATH 與
        // `Windows Kits\10\Debuggers`;使用者要求查 winget 與 scoop,winget 就有。
        //
        // (5) **2026-09-17 以該除錯器解決。** 堆疊記在 `WebViewWidget` 上:**在 Swift 子類別化
        //     `WebView2` 就是 heap corruption 的原因**,widget 已改為持有它的 `Grid`。在 `.single`
        //     下 P38 顯示 example.com 並回報兩次導覽。**對照組**:同一個 `Grid` widget 在 `.multi`
        //     下維持 type 1、45 秒內從未完成——所以**兩半都需要**,容器與單執行緒 apartment。
        //
        // ============================================================
        // **2026-09-16 第三輪:上面那段「實際跑過並推翻」本身是錯的,真實狀態還要再往前一步。**
        //
        // (1) **apartment**:以 `CoGetApartmentType` 在三個時間點量測。`SwiftApplication.main()`
        //     之前是 `CO_E_NOTINITIALIZED`(沒有任何東西先初始化 COM);`onLaunched` 與此處是
        //     type 1,**真正的 MTA**,不是 ASTA。所以 MTA 完全來自 swift-winui 的 `.multi`。
        // (2) **為什麼 `.single` 的實驗說不是**:swift-winui 有**三份** checkout,P38-WinUI 用的是
        //     `.compile-work-winui` 那份。紀錄只寫「checkout edited」沒說哪份,而正對照組
        //     (`Compiling WinUI` 命中 2 次)證明的是**有重編**,不是**被改的那份有被編到**。
        //     這次改在 `.compile-work-winui`,apartment 讀到 type 3(MAINSTA),改動確實生效。
        // (3) **交握隨之完成**:`EBWebView/` 出現 `Default/` 與 `Local State`,MTA 下從未有過。
        // (4) **但行程接著死掉**:ntdll 的 `c0000374` STATUS_HEAP_CORRUPTION,core 開始初始化後約
        //     一秒、第一次 `onAppear` 之前。沒有 WebView 的 P42-WinUI 在同一個 `.single` 下完全正常。
        //     以環境開關二分(全在 STA、各 15 秒):不初始化 core 也不設 Source → 存活;只設
        //     Source(隱式初始化)→ 當;只呼叫 ensureCore → 當;兩者 → 當。另外把 `completed`
        //     handler 與 `Source` 屬性回呼**都跳過** → 仍然當。所以不是本檔的回呼:**只要 COM 放行,
        //     任何 WebView2 core 初始化都會破壞 heap。** MTA 下這條路徑根本到不了。
        //
        // **下一步需要本機沒有的除錯器**(沒有 cdb、WinDbg、procdump):取得破壞點的堆疊,最好開
        // page heap 讓它在寫壞的那一刻就中斷。上游沒有人用過 WebView2(swift-winui 在 Generated/
        // 之外零個呼叫處),這條綁定路徑很可能從沒跑過。二分用的開關已移除,每一臂都只是一個
        // 提早 `return`。
        logWebViewDiagnostic("WebView2: apartment at beginEnsureCore \(comApartmentDescription())")

        guard let promise = try? control.ensureCoreWebView2Async() else {
            logger.warning("WebView2: EnsureCoreWebView2Async threw immediately")
            return
        }
        corePromise = promise

        // ============================================================
        // STILL BROKEN, and here is exactly what was ruled out, 2026-09-10.
        // The web view frame is empty on WinUI and P38 reports "Navigations
        // reported: 0". Four hypotheses were tested by running, not argued:
        //
        //  1. "The element is not Loaded yet." TRUE, and fixed above --
        //     `isLoaded` logged FALSE from `updateWebView`. Necessary, not
        //     sufficient: the frame is still empty with the wait in place.
        //  2. "The IAsyncAction is released before it completes." Plausible;
        //     fixed by `corePromise` above. Did not change the outcome either.
        //  3. "It completed and `promise.completed` never registered the
        //     handler." REFUTED. A `Task` polled `coreWebView2` directly,
        //     bypassing the handler entirely: nil at every one of 40 one-second
        //     samples, from a deleted user-data folder. The operation genuinely
        //     does not complete.
        //  4. "The WebView2 Runtime is missing." REFUTED. Registry reports
        //     152.0.4191.66 and three versions are installed under
        //     `Program Files (x86)/Microsoft/EdgeWebView/Application`.
        //     `msedgewebview2.exe` DOES start -- one of its processes reaches
        //     96 MB, so the browser is running, not stillborn.
        //
        // What the evidence now points at: the host and the browser process
        // start but never complete their handshake. `EBWebView/` contains only
        // `EBWebViewMetrics` -- no `Default/`, no `Local State` -- so the
        // profile is never created. That is downstream of process start and
        // upstream of `CoreWebView2` existing.
        //
        // NOTE THE OLD MEASUREMENT WAS TOO SHORT. todo.md records "nil at +2s
        // and +6s", which cannot distinguish "never completes" from "slow cold
        // start". 40 seconds can, and does.
        //
        // To reproduce: re-add a `Task` that polls `coreWebView2` once a
        // second and print BEFORE the loop as well -- with no executor the Task
        // silently never runs, and zero poll lines reads exactly like "polled
        // and always nil".
        //
        // ============================================================
        // **仍然壞著,而以下是 2026-09-10 已經排除掉的東西。**
        // web view 的框在 WinUI 上是空的,而 P38 回報「Navigations reported: 0」。
        // 四個假設**以執行來檢驗,而非以論證**:
        //
        //  1.「元素尚未 Loaded。」**為真**,且已於上方修正——`isLoaded` 在 `updateWebView`
        //     時記錄為 FALSE。**必要但不充分**:加上等待之後,那個框仍然是空的。
        //  2.「IAsyncAction 在完成前就被釋放。」有此可能;已由上方的 `corePromise` 修正。
        //     同樣沒有改變結果。
        //  3.「它完成了,而 `promise.completed` 從未註冊上 handler。」**已推翻。** 一個 `Task`
        //     直接輪詢 `coreWebView2`、完全繞過該 handler:在**刪除過 user-data 資料夾**的情況下,
        //     40 次每秒取樣**全部**為 nil。那個操作是真的沒有完成。
        //  4.「WebView2 Runtime 沒裝。」**已推翻。** registry 回報 152.0.4191.66,且
        //     `Program Files (x86)/Microsoft/EdgeWebView/Application` 下裝有三個版本。
        //     `msedgewebview2.exe` **確實會啟動**——其中一個行程達到 96 MB,所以瀏覽器是活的,
        //     不是一啟動就死。
        //
        // **證據現在指向的方向**:host 與瀏覽器行程都啟動了,卻從未完成它們之間的交握。
        // `EBWebView/` 裡只有 `EBWebViewMetrics`——沒有 `Default/`、沒有 `Local State`——
        // 因此 profile 從未被建立。那個位置**在行程啟動的下游、在 `CoreWebView2` 存在的上游**。
        //
        // **注意舊的量測窗口太短。** todo.md 記的是「+2 秒與 +6 秒皆為 nil」,而那**分不出**
        // 「永不完成」與「冷啟動很慢」。40 秒分得出來,而且分出來了。
        //
        // **重現方式**:重新加一個每秒輪詢 `coreWebView2` 的 `Task`,並且**在迴圈之前也印一行**
        // ——若沒有 executor,那個 Task 會靜默地不執行,而「零行 poll」看起來會與
        // 「輪詢了、但每次都是 nil」一模一樣。
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
