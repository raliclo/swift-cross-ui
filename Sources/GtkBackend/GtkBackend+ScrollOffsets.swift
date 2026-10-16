import CGtk
import Gtk
@_spi(Backends) import SwiftCrossUI

/// Scroll offsets from the scrolled window's two GtkAdjustments, whose `value`
/// is the scroll position and whose `value-changed` fires for a wheel, a drag,
/// a scroll bar, kinetic scrolling and `gtk_adjustment_set_value` (which is how
/// `scrollContainer(_:to:anchor:)` scrolls) alike.
///
/// 從 scrolled window 的兩個 GtkAdjustment 取得捲動位移：其 `value` 就是捲動位置，而 `value-changed`
/// 在滾輪、拖曳、捲軸、動能捲動與 `gtk_adjustment_set_value`(`scrollContainer(_:to:anchor:)` 就是這樣
/// 捲動的)時都會觸發。
extension GtkBackend: BackendFeatures.ScrollOffsetReporting {
    public func contentOffset(ofScrollContainer scrollView: Widget) -> SIMD2<Double> {
        guard let scrolled = Self.scrolledWindow(of: scrollView) else { return .zero }
        return GtkScrollOffsets.offset(of: scrolled.opaquePointer)
    }

    public func setContentOffsetHandler(
        ofScrollContainer scrollView: Widget,
        to handler: (@MainActor (SIMD2<Double>) -> Void)?
    ) {
        guard let scrolled = Self.scrolledWindow(of: scrollView) else { return }
        GtkScrollOffsets.install(on: scrolled).handler = handler
    }
}

/// The handler of one scrolled window, kept on the window itself with
/// `g_object_set_data_full`, so it lives exactly as long as the adjustments
/// whose signals call it. Installed once; later updates replace the handler.
/// 一個 scrolled window 的 handler,以 `g_object_set_data_full` 存放在該視窗本身上，因此它的壽命恰好與
/// 呼叫它的那些 adjustment 訊號相同。只安裝一次;之後的更新替換 handler。
@MainActor
final class GtkScrollOffsets {
    static let dataKey = "scui-scroll-offsets"

    var handler: (@MainActor (SIMD2<Double>) -> Void)?
    let scrolled: OpaquePointer?

    init(scrolled: OpaquePointer?) {
        self.scrolled = scrolled
    }

    static func offset(of scrolled: OpaquePointer?) -> SIMD2<Double> {
        let x = gtk_scrolled_window_get_hadjustment(scrolled).map { gtk_adjustment_get_value($0) }
        let y = gtk_scrolled_window_get_vadjustment(scrolled).map { gtk_adjustment_get_value($0) }
        return SIMD2(x ?? 0, y ?? 0)
    }

    static func install(on scrolled: ScrolledWindow) -> GtkScrollOffsets {
        let object = scrolled.gobjectPointer
        if let existing = g_object_get_data(object, dataKey) {
            return Unmanaged<GtkScrollOffsets>.fromOpaque(existing).takeUnretainedValue()
        }
        let box = GtkScrollOffsets(scrolled: scrolled.opaquePointer)
        let boxed = Unmanaged.passRetained(box).toOpaque()
        g_object_set_data_full(
            object,
            dataKey,
            boxed,
            { pointer in
                guard let pointer else { return }
                Unmanaged<GtkScrollOffsets>.fromOpaque(pointer).release()
            }
        )
        let callback: @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer) -> Void = {
            _, data in
            MainActor.assumeIsolated {
                let box = Unmanaged<GtkScrollOffsets>.fromOpaque(data).takeUnretainedValue()
                box.handler?(GtkScrollOffsets.offset(of: box.scrolled))
            }
        }
        for adjustment in [
            gtk_scrolled_window_get_hadjustment(scrolled.opaquePointer),
            gtk_scrolled_window_get_vadjustment(scrolled.opaquePointer),
        ] {
            guard let adjustment else { continue }
            g_signal_connect_data(
                UnsafeMutableRawPointer(adjustment),
                "value-changed",
                unsafeBitCast(callback, to: GCallback.self),
                boxed,
                nil,
                GConnectFlags(rawValue: 0)
            )
        }
        return box
    }
}
