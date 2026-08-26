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
/// The rendering process is started on demand by the control the first time it
/// is asked to navigate, so nothing here has to call `EnsureCoreWebView2Async`.
/// A machine without the Edge WebView2 runtime installed shows an empty control
/// and raises `CoreProcessFailed`; that is the platform's own failure, and it is
/// visible rather than silent.
final class WebViewWidget: WinUI.WebView2 {
    var onNavigate: ((URL) -> Void)?

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
