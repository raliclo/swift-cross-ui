import CGtk
import Foundation
import Gtk
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

    public func createWebView() -> Widget {
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
        // Nothing to navigate, so nothing ever calls back. Deliberately not
        // calling `onNavigate` with anything: inventing a navigation the user
        // never made would be worse than staying silent.
        // 沒有可導覽的內容，因此永遠不會回呼。刻意不以任何值呼叫 `onNavigate`：捏造一次使用者
        // 從未進行的導覽，會比保持沉默更糟。
    }

    public func navigateWebView(_ webView: Widget, to url: URL) {
        // Same reasoning as updateWebView. The placeholder does not change to
        // show the URL, because a view that displays a URL as text is not a web
        // view and should not be mistaken for one at a glance.
        // 理由同 updateWebView。此佔位不會改為顯示該 URL，因為「把 URL 當成文字顯示的 view」並非
        // web view，不應在匆匆一瞥之下被誤認為是。
    }
}
