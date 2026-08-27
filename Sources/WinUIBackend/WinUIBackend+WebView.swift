import Foundation
@_spi(Backends) import SwiftCrossUI
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

        // The completion is observed, not discarded. `EnsureCoreWebView2Async`
        // reports its failure asynchronously, so `_ = try? ensureCoreWebView2Async()`
        // cannot fail visibly -- the browser simply never appears and the frame
        // stays empty, which is what this looked like for a whole session.
        // 此處會觀察完成結果，而非丟棄它。`EnsureCoreWebView2Async` 是以非同步方式回報失敗的，因此
        // `_ = try? ensureCoreWebView2Async()` 不可能明顯地失敗——瀏覽器只是永遠不出現、該框保持
        // 空白，而那正是它在整個工作階段中所呈現的樣子。
        guard let promise = try? ensureCoreWebView2Async() else {
            logger.warning("WebView2: EnsureCoreWebView2Async threw immediately")
            return
        }
        promise.completed = { [weak self] _, status in
            guard status != .completed else { return }
            logger.warning("WebView2: the browser process did not start (status \(status))")
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
