#if os(macOS)
    import AppKit
    import CGtk
    import Foundation
    import GtkCHelpers
    import WebKit

    /// The macOS ``GtkWebEngine``: WebKit itself, kept over the GTK box.
    ///
    /// Homebrew has no WebKitGTK for macOS, so the dlopen route Linux takes
    /// (gtk_webkit.c) found nothing and P27 and P38 showed "WebKitGTK could not
    /// start" (2026-10-16). The engine macOS does have is WebKit.
    ///
    /// **A sibling of GDK's view, not a subview.** GDK's content view hosts its own
    /// layer, and AppKit does not support subviews of a layer-hosting view: added
    /// there, the page loaded (P38 reported the navigation) and never showed.
    ///
    /// macOS 的 ``GtkWebEngine``:WebKit 本身，覆蓋在 GTK box 上。Homebrew 沒有 macOS 版的 WebKitGTK,Linux 的
    /// dlopen 路線找不到任何東西,P27 與 P38 顯示「WebKitGTK could not start」(2026-10-16)。**是 GDK view 的兄弟，
    /// 而不是子視圖**:GDK 的 content view 自己承載 layer,AppKit 不支援 layer-hosting view 的子視圖；放在那裡時頁面
    /// 有載入(P38 回報了導覽)卻從未顯示。
    ///
    /// `@unchecked Sendable`: touched only on GTK's thread, which on macOS is the
    /// main thread WebKit requires. 只在 GTK 的執行緒上被觸碰，在 macOS 上就是 WebKit 要求的主執行緒。
    final class WKWebEngine: GtkWebEngine, @unchecked Sendable {
        var onNavigate: ((URL) -> Void)?
        private var webView: WKWebView?
        private var delegate: NavigationDelegate?
        private var pending: URL?

        private final class NavigationDelegate: NSObject, WKNavigationDelegate {
            weak var engine: WKWebEngine?
            // Committed, not finished: a page that loads slowly has still been
            // navigated to, as WebView2's SourceChanged reports it on Windows.
            // 以 commit 而非 finish 為準：載入很慢的頁面也已經被導覽到了，與 Windows 上 WebView2 的 SourceChanged 一致。
            func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
                if let url = webView.url { engine?.onNavigate?(url) }
            }
        }

        init() {
            MainActor.assumeIsolated {
                let view = WKWebView(frame: .zero)
                let delegate = NavigationDelegate()
                delegate.engine = self
                view.navigationDelegate = delegate
                view.isHidden = true
                self.webView = view
                self.delegate = delegate
            }
        }

        deinit {
            let view = webView
            MainActor.assumeIsolated { view?.removeFromSuperview() }
        }

        func attach(to host: UnsafeMutablePointer<GtkWidget>) {}

        func show(in root: UnsafeMutablePointer<GtkWidget>, at frame: GtkWebEngineFrame) {
            // By address: a pointer is not Sendable, and this is GTK's thread anyway.
            // 以位址傳入：指標不是 Sendable,而這裡本來就是 GTK 的執行緒。
            let rootAddress = UInt(bitPattern: root)
            MainActor.assumeIsolated {
                guard let webView,
                    let rootWidget = UnsafeMutablePointer<GtkWidget>(bitPattern: rootAddress),
                    let nativeWindow = scui_window_native_macos(rootWidget),
                    let content = Unmanaged<NSWindow>.fromOpaque(nativeWindow).takeUnretainedValue()
                        .contentView,
                    let frameView = content.superview
                else { return }
                // GTK counts y from the top; AppKit from the bottom unless flipped.
                // GTK 的 y 由上往下;AppKit 由下往上，除非是 flipped。
                let inContent = NSRect(
                    x: frame.x,
                    y: content.isFlipped ? frame.y : content.bounds.height - frame.y - frame.height,
                    width: frame.width,
                    height: frame.height
                )
                if webView.superview !== frameView {
                    frameView.addSubview(webView, positioned: .above, relativeTo: content)
                }
                webView.frame = content.convert(inContent, to: frameView)
                webView.isHidden = false
                if let url = pending {
                    pending = nil
                    webView.load(URLRequest(url: url))
                }
            }
        }

        func hide() {
            let view = webView
            MainActor.assumeIsolated { view?.isHidden = true }
        }

        func navigate(to url: URL) {
            MainActor.assumeIsolated {
                if let webView, webView.superview != nil {
                    webView.load(URLRequest(url: url))
                } else {
                    pending = url
                }
            }
        }
    }
#endif
