import CGtk
import Foundation
import Gtk
import GtkCHelpers
@_spi(Backends) import SwiftCrossUI

extension GtkBackend {
    // How each platform gets a web view:
    //
    //   - macOS: WKWebView kept over the GTK box (GtkBackend+WebEngine.swift,
    //     +WebViewMac.swift); Homebrew has no WebKitGTK.
    //   - Windows: `WebViewHost`, a GTK widget that GTK lays out, with a
    //     WebView2 browser kept over it as a child of the window's HWND
    //     (gtk_webview2.c).
    //   - Linux and WSL: WebKitGTK 6.0 loaded with dlopen (gtk_webkit.c), so no
    //     build dependency is added. A machine without libwebkitgtk-6.0-4 gets a
    //     frame naming the package.
    //
    // `webkitgtk-6.0` cannot be a plain system dependency: it is installable on
    // Linux (`apt-cache policy libwebkitgtk-6.0-dev` on Ubuntu 26.04) but has no
    // Windows port (nothing in gvsbuild's C:/gtk4), so a hard dependency would
    // stop the Windows GTK build from configuring (measured 2026-09-04).
    //
    // The labelled placeholder below is only for Windows builds made without
    // WebView2.h. A label rather than a blank, because a blank area looks like
    // a layout bug, whereas the text says which feature is missing and why.
    //
    // 各平台取得 web view 的方式:
    //
    //   - macOS:覆蓋在 GTK box 上的 WKWebView(GtkBackend+WebEngine.swift、+WebViewMac.swift);
    //     Homebrew 沒有 WebKitGTK。
    //   - Windows:`WebViewHost`,一個由 GTK 排版的 widget,WebView2 瀏覽器以視窗 HWND 子視窗的形式
    //     保持覆蓋在它上面(gtk_webview2.c)。
    //   - Linux 與 WSL:以 dlopen 載入 WebKitGTK 6.0(gtk_webkit.c),因此不增加建置相依。沒有
    //     libwebkitgtk-6.0-4 的機器會得到一個寫出套件名稱的框。
    //
    // `webkitgtk-6.0` 不能成為單純的系統相依:它在 Linux 上可安裝(Ubuntu 26.04 上的
    // `apt-cache policy libwebkitgtk-6.0-dev`),但沒有 Windows 版本(gvsbuild 的 C:/gtk4 中完全沒有),
    // 因此硬性相依會讓 Windows 的 GTK 建置無法 configure(2026-09-04 實測)。
    //
    // 下方有文字說明的佔位只給沒有 WebView2.h 的 Windows 建置。用文字而不是空白，因為空白區域看起來像
    // 版面 bug,而文字會說出缺少的是哪一個功能、以及原因。
    public func createWebView() -> Widget {
        #if os(macOS)
            // WebKit itself, kept over the box (GtkBackend+WebEngine.swift, +WebViewMac.swift).
            // WebKit 本身，覆蓋在 box 上(GtkBackend+WebEngine.swift、+WebViewMac.swift)。
            return GtkWebViewHost(engine: WKWebEngine())
        #endif
        if scui_webview_is_compiled_in() != 0 {
            return WebViewHost()
        }
        // A plain Gtk.Label, not the CustomLabel that createTextView returns.
        // CustomLabel is SwiftCrossUI's own widget and expects to be driven by
        // updateTextView; handing one back from a different feature left it
        // never configured, and the app exited cleanly at launch on Windows
        // instead of showing a window -- exit code 0, no output, nothing to
        // diagnose from. Bisected by building the same app with the web view
        // removed, which then ran.
        //
        // 使用一般的 Gtk.Label，而非 createTextView 所回傳的 CustomLabel。CustomLabel 是
        // SwiftCrossUI 自有的 widget，預期由 updateTextView 驅動；從另一個功能交回一個
        // CustomLabel，會使它永遠未被設定，於是 app 在 Windows 上啟動時乾淨地退出而不顯示視窗
        // ——結束碼 0、沒有輸出、無從診斷。以「移除 web view 後重建同一支 app」二分法確認，
        // 移除後即可執行。
        let placeholder = Gtk.Label(
            string: "WebView is not available in this build (GtkBackend has no WebKitGTK)"
        )
        placeholder.wrap = true
        return placeholder
    }

    public func updateWebView(
        _ webView: Widget,
        environment: EnvironmentValues,
        onNavigate: @escaping (URL) -> Void
    ) {
        #if os(macOS)
            if let host = webView as? GtkWebViewHost {
                host.engine.onNavigate = onNavigate
                return
            }
        #endif
        if let host = webView as? WebViewHost {
            host.onNavigate = onNavigate
            return
        }
        // Nothing to navigate, so nothing ever calls back. Deliberately not
        // calling `onNavigate` with anything: inventing a navigation the user
        // never made would be worse than staying silent.
        // 沒有可導覽的內容，因此永遠不會回呼。刻意不以任何值呼叫 `onNavigate`：捏造一次使用者
        // 從未進行的導覽，會比保持沉默更糟。
    }

    public func navigateWebView(_ webView: Widget, to url: URL) {
        #if os(macOS)
            if let host = webView as? GtkWebViewHost {
                host.engine.navigate(to: url)
                return
            }
        #endif
        if let host = webView as? WebViewHost {
            host.navigate(to: url)
            return
        }
        // Same reasoning as updateWebView. The placeholder does not change to
        // show the URL, because a view that displays a URL as text is not a web
        // view and should not be mistaken for one at a glance.
        // 理由同 updateWebView。此佔位不會改為顯示該 URL，因為「把 URL 當成文字顯示的 view」並非
        // web view，不應在匆匆一瞥之下被誤認為是。
    }
}

/// The GTK box a web view lives in: on Windows WebView2 is kept over it, on
/// Linux/WSL the WebKitWebView is appended to it.
///
/// A `Box` rather than a `Label`, because on
/// Linux the browser is a real GtkWidget that has to go INSIDE the host, and a
/// label cannot hold children. The C side still puts a label in the box when
/// the engine cannot start, so the frame says what is missing.
///
/// web view 所在的 GTK box:在 Windows 上 WebView2 覆蓋其上,在 Linux/WSL 上 WebKitWebView 被加進去。
///
/// 用 `Box` 而非 `Label`,因為在 Linux 上瀏覽器是真正的 GtkWidget,必須放進
/// host **裡面**,而 label 不能有子元件。引擎無法啟動時,C 端仍會在 box 裡放一個 label 說明缺了什麼。
final class WebViewHost: Gtk.Box {
    var onNavigate: ((URL) -> Void)?
    private var view: OpaquePointer?

    /// Holds the host weakly for the C callback, and is released by the C side
    /// when the widget is destroyed -- so neither side outlives the other.
    /// 為 C 回呼弱持有 host,並由 C 端在 widget 銷毀時釋放——兩邊都不會活得比對方久。
    private final class CallbackBox {
        weak var host: WebViewHost?
        init(_ host: WebViewHost) { self.host = host }
    }

    init() {
        // The raw constructor: `Box.init(orientation:spacing:)` is a convenience
        // initialiser, unreachable through `super` (same as GestureBox).
        // 使用原生建構式:`Box.init(orientation:spacing:)` 是 convenience initialiser,無法經由
        // `super` 呼叫(與 GestureBox 相同)。
        super.init(gtk_box_new(GTK_ORIENTATION_VERTICAL, 0))
        view = scui_webview_new(widgetPointer)
        guard let view else { return }
        let box = Unmanaged.passRetained(CallbackBox(self)).toOpaque()
        scui_webview_set_navigated_callback(
            view,
            { uri, userData in
                guard let uri, let userData else { return }
                let box = Unmanaged<CallbackBox>.fromOpaque(userData).takeUnretainedValue()
                guard let host = box.host, let url = URL(string: String(cString: uri)) else {
                    return
                }
                host.onNavigate?(url)
            },
            box,
            { userData in
                guard let userData else { return }
                Unmanaged<CallbackBox>.fromOpaque(userData).release()
            }
        )
    }

    func navigate(to url: URL) {
        guard let view else { return }
        scui_webview_navigate(view, url.absoluteString)
    }
}
