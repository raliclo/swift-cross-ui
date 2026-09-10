import Foundation
@_spi(Backends) import SwiftCrossUI
import WinSDK
import WinUI
import WindowsFoundation

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
        webView.source = WindowsFoundation.Uri(url.absoluteString)
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
final class WebViewWidget: WinUI.WebView2 {
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
        let alreadyLoaded = isLoaded
        logger.info("WebView2: starting core, isLoaded=\(alreadyLoaded)")

        if alreadyLoaded {
            beginEnsureCore()
        } else {
            loadedRegistration = loaded.addHandler { [weak self] _, _ in
                guard let self else { return }
                logger.info("WebView2: Loaded fired, starting core now")
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
        let staProbe = CoInitializeEx(nil, DWORD(COINIT_APARTMENTTHREADED.rawValue))
        logger.info(
            "WebView2: CoInitializeEx(STA) returned \(String(format: "0x%08x", UInt32(bitPattern: staProbe)))"
        )
        if staProbe == S_OK || staProbe == S_FALSE {
            CoUninitialize()
        }

        guard let promise = try? ensureCoreWebView2Async() else {
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
            logger.info("WebView2: the browser process started")
            _ = self
        }
    }

    override init() {
        super.init()

        _ = try? registerPropertyChangedCallback(Self.sourceProperty) { [weak self] _, _ in
            guard let self, let source = self.source else { return }
            guard let url = URL(string: source.absoluteUri) else {
                logger.warning("web view navigated to an unparseable URL")
                return
            }
            self.onNavigate?(url)
        }
    }
}
