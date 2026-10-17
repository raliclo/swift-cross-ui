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
        recogniser.click.pressed = { [unowned recogniser] _, _, _, _ in
            recogniser.longPressFired = false
        }
        recogniser.click.released = { [unowned recogniser] _, nPress, _, _ in
            guard nPress == 1, !recogniser.longPressFired else { return }
            recogniser.onTap?()
        }
        recogniser.longPress.pressed = { [unowned recogniser] _, _, _ in
            recogniser.longPressFired = true
            recogniser.onLongPress?()
        }
        child.addEventController(recogniser.click)
        child.addEventController(recogniser.longPress)

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
