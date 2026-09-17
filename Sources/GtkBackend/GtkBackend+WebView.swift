import CGtk
import Foundation
import Gtk
import GtkCHelpers
@_spi(Backends) import SwiftCrossUI

extension GtkBackend {
    // A placeholder web view, not a real one.
    //
    // GtkBackend did not conform to `BackendFeatures.WebViews` at all, and a
    // missing conformance is not a degradation: `@CastBackend` expands to
    // `fatalError("'GtkBackend' does not implement 'BackendFeatures.WebViews'")`,
    // so an app containing a `WebView` aborted the moment that view was laid
    // out -- on Linux and on Windows `-gtk4` alike. An app cannot guard against
    // that; there is no way to ask a backend what it supports before using it.
    //
    // Rendering web content needs WebKitGTK, which would mean adding
    // `webkitgtk-6.0` to Package.swift as a system dependency. That changes what
    // every person building this project has to have installed -- it is not
    // available on this machine, for instance -- so it is a packaging decision
    // rather than a fix for the crash, and the two are separable.
    //
    // What this does instead is what the project already does for optional
    // features (see the no-op defaults on `HitTesting`, `Clipping` and
    // `DragAndDrop`): conform, and degrade in a way the author can see. A
    // labelled placeholder is preferred over a silent blank -- a blank area
    // looks like a layout bug, whereas the text says which feature is missing
    // and why. When a WebKitGTK implementation lands it replaces this file.
    //
    // DECISION, 2026-09-04: `webkitgtk-6.0` CANNOT be a plain system dependency,
    // and the reason is not cost or taste. It is measured:
    //
    //   Linux (WSL, Ubuntu 26.04) `apt-cache policy libwebkitgtk-6.0-dev`
    //     -> Candidate: 2.52.6-0ubuntu0.26.04.1     available, installable
    //   Windows (gvsbuild, C:/gtk4) `ls C:/gtk4/bin/*webkit*`, and pkg-config
    //     -> nothing at all                          WebKitGTK has no Windows port
    //
    // GtkBackend ships on Linux, on WSL AND on Windows. Adding the dependency
    // unconditionally would take the Windows GTK build from "renders a labelled
    // placeholder" to "does not configure", which is strictly worse and breaks a
    // shipped target to fix a different one. So the decision is not yes/no; the
    // question had a hidden third answer.
    //
    // What it has to be instead, and this is the shape any implementation must
    // take: a CONDITIONAL dependency, present where the platform has it, with
    // the Windows GTK build keeping a real implementation of its own. Windows
    // does have an engine -- WebView2, which `WinUIBackend+WebView.swift`
    // already drives -- and GTK4 on Windows can hand out an HWND for its
    // surface, so hosting WebView2 as a child of that HWND is the route. That is
    // work, not a flag, and it is why this file still exists.
    //
    // What is NOT acceptable, per this project's rules: leaving the placeholder
    // as the permanent answer on three of the six shipped platforms. It is a
    // truthful report of a missing feature, which is not the same as a feature.
    //
    // **決策，2026-09-04：`webkitgtk-6.0` 不能成為單純的系統相依**，理由不是成本或喜好，而是實測：
    //
    //   Linux（WSL、Ubuntu 26.04）`apt-cache policy libwebkitgtk-6.0-dev`
    //     -> Candidate: 2.52.6-0ubuntu0.26.04.1      有，可安裝
    //   Windows（gvsbuild、C:/gtk4）`ls C:/gtk4/bin/*webkit*` 與 pkg-config
    //     -> 完全沒有                                 WebKitGTK 沒有 Windows 版本
    //
    // GtkBackend 同時出貨於 Linux、WSL **與 Windows**。無條件加入該相依，會讓 Windows 的 GTK 建置
    // 從「畫出一個有說明文字的佔位」變成「根本無法 configure」——那是為了修好某個目標而弄壞另一個
    // 已出貨的目標，嚴格來說更糟。因此這個決策不是「要或不要」；這個問題有一個被忽略的第三種答案。
    //
    // 它必須改成什麼，而任何實作也都得是這個形狀：**條件式相依**，在平台具備時才引入，而 Windows
    // 的 GTK 建置保有它自己的真實實作。Windows 確實有引擎——WebView2，
    // `WinUIBackend+WebView.swift` 已經在驅動它——而 GTK4 在 Windows 上能交出其 surface 的 HWND，
    // 因此「把 WebView2 掛為該 HWND 的子視窗」就是那條路。那是工作量，不是一個旗標，而這正是本檔
    // 至今仍存在的原因。
    //
    // 依本專案規則**不可接受**的是：把這個佔位當成六個已出貨平台中三個的永久答案。它是對一項缺失
    // 功能的如實回報，而那與「擁有一項功能」是兩回事。
    //
    // 這是一個佔位用的 web view，而非真正的 web view。
    //
    // GtkBackend 先前完全沒有 conform `BackendFeatures.WebViews`，而缺少 conformance 並非降級：
    // `@CastBackend` 會展開為 `fatalError("'GtkBackend' does not implement ...")`，因此含有
    // `WebView` 的 app 會在該 view 進行版面配置的當下中止——Linux 與 Windows `-gtk4` 皆然。app
    // 無法對此設防；沒有任何方式可在使用某功能前詢問 backend 是否支援它。
    //
    // 要真正繪製網頁內容需要 WebKitGTK，那意味著必須把 `webkitgtk-6.0` 加入 Package.swift 作為
    // 系統相依。這會改變每一位建置本專案者所需安裝的東西——例如本機上就沒有它——因此那是一個
    // 封裝決策，而非此崩潰的修正，兩者可以分開處理。
    //
    // 此處改為採用本專案對選配功能既有的做法（見 `HitTesting`、`Clipping` 與 `DragAndDrop` 的
    // no-op 預設實作）：先 conform，並以作者看得見的方式降級。此處選擇「有文字說明的佔位」而非
    // 「靜默空白」——空白區域看起來像版面 bug，而文字會說出缺少的是哪一個功能、以及原因。待
    // WebKitGTK 的實作完成時，即可取代此檔案。

    // ============================================================
    // 2026-09-17: WINDOWS HAS THE REAL IMPLEMENTATION the decision above called
    // for. `WebViewHost` below is a GTK widget that GTK lays out, with a WebView2
    // browser kept over it as a child of the window's HWND (gtk_webview2.c).
    // Measured before this: P38 on Windows -gtk4 showed the placeholder text and
    // "Navigations reported: 0" (results.csv2, p38-gtk4-test-20260917-082518.png).
    //
    // ~~The placeholder below is still what Linux and WSL get~~ -- superseded the
    // same day: Linux and WSL load WebKitGTK 6.0 with dlopen (gtk_webkit.c), so
    // no build dependency is added and the 2026-09-04 constraint still holds. A
    // machine without libwebkitgtk-6.0-4 gets a frame naming the package. The
    // placeholder below is now only for Windows builds made without WebView2.h.
    //
    // 2026-09-17:**Windows 已有上面那段決策所要求的真實實作。** 下方的 `WebViewHost` 是一個由 GTK
    // 排版的 widget,WebView2 瀏覽器以視窗 HWND 子視窗的形式保持覆蓋在它上面(gtk_webview2.c)。
    // 在此之前實測:P38 於 Windows -gtk4 顯示佔位文字與「Navigations reported: 0」。
    //
    // ~~下方的佔位仍是 Linux 與 WSL 所得到的~~——同日已被取代:Linux 與 WSL 以 dlopen 載入
    // WebKitGTK 6.0(gtk_webkit.c),因此不增加建置相依,2026-09-04 的限制依然成立。沒有
    // libwebkitgtk-6.0-4 的機器會得到一個寫出套件名稱的框。下方的佔位現在只給沒有 WebView2.h 的 Windows 建置。
    public func createWebView() -> Widget {
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
/// A `Box` rather than the `Label` the first Windows version used, because on
/// Linux the browser is a real GtkWidget that has to go INSIDE the host, and a
/// label cannot hold children. The C side still puts a label in the box when
/// the engine cannot start, so the frame says what is missing.
///
/// web view 所在的 GTK box:在 Windows 上 WebView2 覆蓋其上,在 Linux/WSL 上 WebKitWebView 被加進去。
///
/// 用 `Box` 而非第一版 Windows 所用的 `Label`,因為在 Linux 上瀏覽器是真正的 GtkWidget,必須放進
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
