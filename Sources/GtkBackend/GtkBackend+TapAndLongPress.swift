import CGtk
import Gtk
@_spi(Backends) import SwiftCrossUI

// A tap and a long press on one view. Not the `.primary` + `.longPress` pair of
// TapGestures: `.primary` fires on press, so every long press would start
// with a tap. Here the tap is reported on release, and only when the long
// press did not fire during that press.
// 同一個 view 上的點按與長按。不是 TapGestures 的 `.primary` 加 `.longPress`:`.primary` 在按下時就觸發，每次長按
// 都會先有一次點按。這裡點按在放開時才回報，而且只在這次按壓中長按沒有觸發時。
extension GtkBackend: BackendFeatures.TapAndLongPressGestures {
    public func createTapAndLongPressTarget(wrapping child: Widget) -> Widget {
        GtkTapAndLongPress.install(on: child)
        return child
    }

    public func updateTapAndLongPressTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        onTap: @escaping () -> Void,
        onLongPress: @escaping () -> Void
    ) {
        guard let recogniser = GtkTapAndLongPress.of(target) else { return }
        let isEnabled = environment.isEnabled
        recogniser.onTap = isEnabled ? onTap : nil
        recogniser.onLongPress = isEnabled ? onLongPress : nil
    }
}

/// The two controllers and the press record they share, kept on the widget
/// as GObject data so a second `install` finds them.
/// 兩個控制器與它們共用的按壓紀錄，以 GObject data 存在 widget 上，讓第二次 `install` 找得到。
@MainActor
final class GtkTapAndLongPress {
    private static let dataKey = "scui-tap-and-long-press"

    private let click = GestureClick()
    private let longPress = GestureLongPress()
    var onTap: (() -> Void)?
    var onLongPress: (() -> Void)?
    /// Set when the long press fires, cleared by the next press.
    /// 長按觸發時設定，下一次按下時清除。
    private(set) var longPressFired = false

    static func install(on child: Gtk.Widget) {
        let object = child.gobjectPointer
        guard g_object_get_data(object, dataKey) == nil else { return }
        let recogniser = GtkTapAndLongPress()

        gtk_gesture_single_set_button(recogniser.click.opaquePointer, guint(GDK_BUTTON_PRIMARY))
        // A press outside the content shape, or one GTK sent here though the
        // pointer is over another widget, is denied to both gestures.
        // content shape 之外的按壓，或指標其實在另一個 widget 上、卻被 GTK 送到此處的按壓，兩個手勢都拒絕。
        recogniser.click.pressed = { [unowned recogniser] gesture, _, x, y in
            recogniser.longPressFired = false
            _ = GtkBackend.admitPress(gesture, x, y)
        }
        recogniser.longPress.begin = { gesture, _ in
            var x = 0.0
            var y = 0.0
            let sequence = gtk_gesture_get_last_updated_sequence(gesture.opaquePointer)
            guard gtk_gesture_get_point(gesture.opaquePointer, sequence, &x, &y) != 0 else {
                return
            }
            _ = GtkBackend.admitPress(gesture, x, y)
        }
        recogniser.click.released = { [unowned recogniser] _, nPress, _, _ in
            guard nPress == 1, !recogniser.longPressFired else { return }
            recogniser.onTap?()
        }
        recogniser.longPress.pressed = { [unowned recogniser] gesture, x, y in
            guard GtkBackend.pressIsInsideShape(gesture, x, y) else { return }
            recogniser.longPressFired = true
            recogniser.onLongPress?()
        }
        child.addEventController(recogniser.click)
        child.addEventController(recogniser.longPress)

        // A press GTK sent elsewhere because no motion came before it: the
        // same tap-or-long-press, made of forwarded events.
        // 因為之前沒有移動而被 GTK 送往別處的按壓：由轉交事件組成的同一個「點按或長按」。
        let forwarded = GtkPressForwarding.LongPress()
        GtkPressForwarding.set("tap-and-long-press", on: child) {
            [unowned recogniser, weak child] phase, button, x, y in
            guard let child, button == UInt32(GDK_BUTTON_PRIMARY) else { return }
            if phase == .pressed,
                !GtkBackend.pointIsInsideShape(of: child.widgetPointer, x, y)
            {
                return
            }
            guard phase == .pressed || forwarded.active else { return }
            forwarded.handle(phase, x, y) { recogniser.onLongPress?() }
            if phase == .released, !forwarded.fired {
                recogniser.onTap?()
            }
        }

        // +1 here, released by the destroy notify with the widget.
        // 此處 +1,由 widget 的 destroy notify 釋放。
        g_object_set_data_full(
            object,
            dataKey,
            Unmanaged.passRetained(recogniser).toOpaque(),
            { pointer in
                guard let pointer else { return }
                Unmanaged<GtkTapAndLongPress>.fromOpaque(pointer).release()
            }
        )
    }

    static func of(_ widget: Gtk.Widget) -> GtkTapAndLongPress? {
        guard let pointer = g_object_get_data(widget.gobjectPointer, dataKey) else { return nil }
        return Unmanaged<GtkTapAndLongPress>.fromOpaque(pointer).takeUnretainedValue()
    }
}
