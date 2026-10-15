import CGtk
import Gtk
@_spi(Backends) import SwiftCrossUI

extension GtkBackend: BackendFeatures.PointerHover {
    public func createPointerHoverTarget(wrapping child: Widget) -> Widget {
        let motion = EventControllerMotion()
        motion.name = "scui-pointer-hover"
        child.addEventController(motion)
        GtkTouchHold.install(on: child)
        return child
    }

    public func updatePointerHoverTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        action: @escaping (PointerHoverPhase) -> Void
    ) {
        // The controller this modifier added, not the one onHover may have added.
        // 這個 modifier 加的那個控制器，而不是 onHover 可能加的那個。
        guard
            let motion = target.eventControllers.first(where: {
                ($0 as? EventControllerMotion)?.name == "scui-pointer-hover"
            }) as? EventControllerMotion
        else { return }
        let isEnabled = environment.isEnabled
        let report: (EventControllerMotion, Double, Double) -> Void = { controller, x, y in
            guard isEnabled else { return }
            // The modifiers held with this motion. / 這次移動時按住的修飾鍵。
            let state = gtk_event_controller_get_current_event_state(
                controller.opaquePointer)
            action(.active(location: SIMD2(x, y), modifiers: Self.eventModifiers(from: state)))
        }
        motion.enter = report
        motion.motion = report
        motion.leave = { _ in
            guard isEnabled else { return }
            action(.ended)
        }
        GtkTouchHold.setHandler(on: target) { phase in
            guard isEnabled else { return }
            action(phase)
        }
    }
}

/// A finger hovers by holding still for GTK's long-press time
/// (`gtk-long-press-time`, 500 ms by default); from then on, until it lifts,
/// every move is reported, and the lift ends it -- as on iOS and Android
/// (queue item 10, 2026-10-15).
///
/// Two controllers, because one is not enough. A touch-only `GestureLongPress`
/// decides the hold, and it is recognised once and reports nothing after it.
/// The moves and the lift come from an `EventControllerLegacy` in the capture
/// phase. A `GestureDrag` beside the long press was tried first and measured
/// on GtkBackend on macOS (2026-10-15, P88, mouse standing in for the finger):
/// the hold was reported once, then nothing -- the panel's own `onDragGesture`
/// claimed the sequence as soon as it moved, and GTK cancels every other
/// gesture on a claimed sequence. A legacy controller is not a gesture, so a
/// claim does not cancel it, and it returns `false` so the event goes on to
/// the child. Only touch events are read, so a mouse is left to the motion
/// controller.
///
/// 手指靜止按住 GTK 的長按時間(`gtk-long-press-time`,預設 500 毫秒)即開始 hover;此後到放開為止每次移動都回報，
/// 放開即結束——與 iOS、Android 相同(queue 第 10 項,2026-10-15)。用兩個控制器，因為一個不夠：只接受觸控的
/// `GestureLongPress` 判定按住，它只辨識一次、之後什麼也不回報;移動與放開來自 capture 階段的 `EventControllerLegacy`。
/// 起初在長按旁放的是 `GestureDrag`,在 macOS 上的 GtkBackend 實測(2026-10-15,P88,以滑鼠代替手指):按住回報一次，
/// 之後就沒有了——面板自己的 `onDragGesture` 一移動就 claim 了這個序列，而 GTK 會取消該序列上其他所有手勢。
/// legacy 控制器不是手勢，claim 不會取消它;它回傳 `false`,事件照樣送到子元件。只讀觸控事件，滑鼠交給 motion 控制器。
@MainActor
private final class GtkTouchHold {
    private static let dataKey = "scui-pointer-touch-hold"

    private let widget: UnsafeMutablePointer<GtkWidget>
    private let longPress = GestureLongPress()
    var handler: ((PointerHoverPhase) -> Void)?
    private var holding = false

    private init(widget: UnsafeMutablePointer<GtkWidget>) {
        self.widget = widget
    }

    static func install(on child: Gtk.Widget) {
        let object = child.gobjectPointer
        guard g_object_get_data(object, dataKey) == nil else { return }
        let hold = GtkTouchHold(widget: child.widgetPointer)

        hold.longPress.touchOnly = true
        hold.longPress.pressed = { [unowned hold] _, x, y in
            hold.holding = true
            hold.handler?(.active(location: SIMD2(x, y), modifiers: []))
        }
        child.addEventController(hold.longPress)

        let boxed = Unmanaged.passRetained(hold).toOpaque()
        // +1 here, released by the destroy notify; the signal borrows it, and
        // GObject disconnects signals in dispose, before qdata goes in finalize.
        // 此處 +1,由 destroy notify 釋放;signal 只借用，GObject 在 dispose 斷開 signal,早於 finalize 銷毀 qdata。
        g_object_set_data_full(
            object,
            dataKey,
            boxed,
            { pointer in
                guard let pointer else { return }
                Unmanaged<GtkTouchHold>.fromOpaque(pointer).release()
            }
        )

        let legacy = gtk_event_controller_legacy_new()!
        gtk_event_controller_set_propagation_phase(legacy, GTK_PHASE_CAPTURE)
        gtk_widget_add_controller(child.widgetPointer, legacy)
        let callback:
            @convention(c) (
                UnsafeMutableRawPointer,
                OpaquePointer,
                UnsafeMutableRawPointer
            ) -> gboolean = { _, event, data in
                MainActor.assumeIsolated {
                    Unmanaged<GtkTouchHold>.fromOpaque(data).takeUnretainedValue()
                        .received(event)
                }
                return 0
            }
        g_signal_connect_data(
            UnsafeMutableRawPointer(legacy),
            "event",
            unsafeBitCast(callback, to: GCallback.self),
            boxed,
            nil,
            GConnectFlags(rawValue: 0)
        )
    }

    static func setHandler(on target: Gtk.Widget, _ handler: @escaping (PointerHoverPhase) -> Void) {
        guard let pointer = g_object_get_data(target.gobjectPointer, dataKey) else { return }
        Unmanaged<GtkTouchHold>.fromOpaque(pointer).takeUnretainedValue().handler = handler
    }

    private func received(_ event: OpaquePointer) {
        guard holding else { return }
        switch gdk_event_get_event_type(event) {
            case GDK_TOUCH_UPDATE:
                if let point = location(of: event) {
                    handler?(.active(location: point, modifiers: []))
                }
            case GDK_TOUCH_END, GDK_TOUCH_CANCEL:
                holding = false
                handler?(.ended)
            default:
                break
        }
    }

    /// The event's position in this widget's coordinates: surface coordinates,
    /// less the native's surface transform, then from the native to the widget.
    /// 事件在此 widget 座標中的位置：surface 座標減去 native 的 surface transform,再由 native 換到 widget。
    private func location(of event: OpaquePointer) -> SIMD2<Double>? {
        var x = 0.0
        var y = 0.0
        guard gdk_event_get_position(event, &x, &y) != 0,
            let native = gtk_widget_get_native(widget)
        else { return nil }
        var offsetX = 0.0
        var offsetY = 0.0
        gtk_native_get_surface_transform(native, &offsetX, &offsetY)
        var source = graphene_point_t(x: Float(x - offsetX), y: Float(y - offsetY))
        var result = graphene_point_t()
        let nativeWidget = UnsafeMutableRawPointer(native).assumingMemoryBound(to: GtkWidget.self)
        guard gtk_widget_compute_point(nativeWidget, widget, &source, &result) != 0 else {
            return nil
        }
        return SIMD2(Double(result.x), Double(result.y))
    }
}
