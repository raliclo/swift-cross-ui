import CGtk
import Foundation
import Gtk

/// A browser engine GtkBackend hosts in a GTK box: the platform half of a web view.
///
/// One protocol so each platform writes only what is its own -- which engine,
/// and how it sits in the window -- and the part every platform needs, keeping
/// the engine where GTK laid the box out, is written once in ``GtkWebViewHost``.
/// macOS conforms with WKWebView (GtkBackend+WebViewMac.swift). Windows (WebView2
/// over the window's HWND) and Linux (WebKitGTK, a GtkWidget appended to the box)
/// are still the C hosts in gtk_webview2.c and gtk_webkit.c; porting them to this
/// protocol, and testing them on those platforms, is queue item 23.
///
/// GtkBackend 在 GTK box 中承載的瀏覽器引擎：網頁視圖中與平台有關的那一半。用一個 protocol,讓每個平台只寫
/// 自己的部分(哪個引擎、怎麼放進視窗),而每個平台都需要的部分(讓引擎待在 GTK 排好的 box 位置)只在
/// ``GtkWebViewHost`` 寫一次。macOS 以 WKWebView 實作;Windows(覆蓋在 HWND 上的 WebView2)與 Linux
/// (加進 box 的 WebKitGTK)仍是 C 版本;把它們移植到本 protocol 並在那些平台上測試，是 queue 第 23 項。
protocol GtkWebEngine: AnyObject {
    /// Called with each new top-level URL. 每個新的頂層 URL 都會呼叫。
    var onNavigate: ((URL) -> Void)? { get set }
    /// Once, with the box the engine belongs to. An engine that is itself a
    /// GtkWidget appends itself here; one kept over the window does nothing.
    /// 只呼叫一次，傳入引擎所屬的 box。本身是 GtkWidget 的引擎在此把自己加進去；覆蓋在視窗上的則什麼都不做。
    func attach(to host: UnsafeMutablePointer<GtkWidget>)
    /// The box is drawn at `frame` in the window `root`, in points from the
    /// top-left of the window's surface. Called only when the frame changed.
    /// box 畫在視窗 `root` 的 `frame` 位置，以點為單位、自視窗 surface 左上角起算。只在 frame 改變時呼叫。
    func show(in root: UnsafeMutablePointer<GtkWidget>, at frame: GtkWebEngineFrame)
    /// The box is not drawn (unmapped, or not placed yet). box 未被繪製(未映射或尚未放置)。
    func hide()
    func navigate(to url: URL)
}

/// Where a web view's box is, in points from the top-left of its window's surface.
/// 網頁視圖的 box 所在位置，以點為單位、自其視窗 surface 的左上角起算。
struct GtkWebEngineFrame: Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

/// The GTK box a web view lives in, for any ``GtkWebEngine``.
///
/// **The engine is moved when GTK paints, not on a timer.** While the box is
/// mapped this listens to its frame clock's `after-paint`. GTK runs a frame only
/// when something changed -- a relayout, a scroll, an animation -- so an idle
/// window costs nothing, and a move lands in the same frame. The 50 ms poll
/// gtk_webview2.c uses wakes 20 times a second for ever and lags a drag by up to
/// 50 ms; `size_allocate` alone would miss a scroll, which moves a child by
/// transform without allocating it again. The engine hears only changes.
///
/// 任何 ``GtkWebEngine`` 所在的 GTK box。**引擎在 GTK 繪製時移動，而不是靠計時器**:box 映射期間監聽其 frame clock
/// 的 `after-paint`。GTK 只在有東西改變時才跑影格(重新排版、捲動、動畫),因此閒置的視窗沒有成本，移動在同一影格內
/// 對齊。gtk_webview2.c 的 50 毫秒輪詢會永遠每秒醒來 20 次，拖曳時最多延遲 50 毫秒；只靠 `size_allocate` 會漏掉捲動，
/// 因為捲動以 transform 移動子元件而不重新配置它。引擎只會聽到變化。
///
/// `@unchecked Sendable`: touched only on GTK's thread. 只在 GTK 的執行緒上被觸碰。
final class GtkWebViewHost: Gtk.Box, @unchecked Sendable {
    let engine: any GtkWebEngine
    private var clock: OpaquePointer?
    private var paintHandler: gulong = 0
    private var shown: GtkWebEngineFrame?

    /// Holds the host weakly for the GLib signal handlers. 為 GLib 訊號 handler 弱持有 host。
    private final class HostBox {
        weak var host: GtkWebViewHost?
        init(_ host: GtkWebViewHost) { self.host = host }
    }

    private typealias Handler = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void

    init(engine: any GtkWebEngine) {
        self.engine = engine
        super.init(gtk_box_new(GTK_ORIENTATION_VERTICAL, 0))
        engine.attach(to: widgetPointer)
        _ = connect(UnsafeMutableRawPointer(widgetPointer), "map") { _, data in
            GtkWebViewHost.host(from: data)?.startFollowing()
        }
        _ = connect(UnsafeMutableRawPointer(widgetPointer), "unmap") { _, data in
            GtkWebViewHost.host(from: data)?.stopFollowing()
        }
    }

    deinit {
        stopFollowing()
    }

    private static func host(from data: UnsafeMutableRawPointer?) -> GtkWebViewHost? {
        guard let data else { return nil }
        return Unmanaged<HostBox>.fromOpaque(data).takeUnretainedValue().host
    }

    private func connect(_ instance: UnsafeMutableRawPointer, _ signal: String, _ handler: Handler) -> gulong {
        g_signal_connect_data(
            instance,
            signal,
            unsafeBitCast(handler, to: GCallback.self),
            Unmanaged.passRetained(HostBox(self)).toOpaque(),
            { data, _ in
                guard let data else { return }
                Unmanaged<HostBox>.fromOpaque(data).release()
            },
            GConnectFlags(rawValue: 0)
        )
    }

    private func startFollowing() {
        stopFollowing()
        guard let frameClock = gtk_widget_get_frame_clock(widgetPointer) else { return }
        clock = frameClock
        paintHandler = connect(UnsafeMutableRawPointer(frameClock), "after-paint") { _, data in
            GtkWebViewHost.host(from: data)?.follow()
        }
        // One frame now, so the engine is placed without waiting for a change.
        // 現在就要一個影格，讓引擎不必等到有變化才被放好。
        gtk_widget_queue_draw(widgetPointer)
    }

    private func stopFollowing() {
        if let clock, paintHandler != 0 {
            g_signal_handler_disconnect(UnsafeMutableRawPointer(clock), paintHandler)
        }
        clock = nil
        paintHandler = 0
        if shown != nil {
            shown = nil
            engine.hide()
        }
    }

    private func follow() {
        guard let root = gtk_widget_get_root(widgetPointer),
            let native = gtk_widget_get_native(widgetPointer)
        else { return }
        let rootWidget = UnsafeMutableRawPointer(root).assumingMemoryBound(to: GtkWidget.self)
        var rect = graphene_rect_t()
        guard gtk_widget_compute_bounds(widgetPointer, rootWidget, &rect) != 0 else {
            if shown != nil {
                shown = nil
                engine.hide()
            }
            return
        }
        var surfaceX = 0.0
        var surfaceY = 0.0
        gtk_native_get_surface_transform(native, &surfaceX, &surfaceY)
        let frame = GtkWebEngineFrame(
            x: Double(rect.origin.x) + surfaceX,
            y: Double(rect.origin.y) + surfaceY,
            width: Double(rect.size.width),
            height: Double(rect.size.height)
        )
        guard frame != shown else { return }
        shown = frame
        engine.show(in: rootWidget, at: frame)
    }
}
