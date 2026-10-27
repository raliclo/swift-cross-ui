import CGtk
import Gtk
import GtkCHelpers

/// Reports a `Slider`'s editing -- began when the button (or finger) goes down
/// on the scale, ended when it comes up -- and makes a press on the trough jump
/// the slider there and drag it, as `NSSlider` does.
///
/// **A capture-phase `EventControllerLegacy`, not a gesture.** A capture-phase
/// `GestureClick` does not work: `GtkScale` claims the sequence for its own
/// drag the moment the button goes down, which denies every other gesture on
/// it, so the click's `end` came at the press, not the release. Measured on
/// GtkBackend on macOS (P61, 2026-10-16): a drag from the thumb logged began,
/// then ended, then the three values. A legacy controller is not a gesture, a
/// claim does not cancel it -- the shape `GtkTouchHold`
/// (GtkBackend+PointerHover.swift) settled on for the same reason.
///
/// **The trough.** GtkRange jumps to a trough press only when
/// `gtk-primary-button-warps-slider` is set; otherwise it pages, by the page
/// increment, which is 0 on this scale. GDK on macOS sets it from the scroll
/// bar preference, and it read 0 here: P61's drag from the trough logged no
/// value at all (2026-10-16). `NSSlider` jumps and follows whatever that
/// preference says, so when the setting is off this controller takes a drag
/// that starts on the trough: it sets the value under the pointer, follows the
/// motion, and stops the events there so GtkRange does not page as well. A
/// press on the thumb, or with the setting on (GTK's default on Linux), is left
/// to GtkRange.
///
/// 回報 `Slider` 的編輯狀態(按鍵或手指在 scale 上按下為開始、放開為結束),並讓軌道上的按下把滑塊跳到該處並可拖曳，
/// 與 `NSSlider` 相同。用 capture 階段的 `EventControllerLegacy`,不用手勢：capture 階段的 `GestureClick` 在
/// `GtkScale` 一按下就 claim 序列時被否決，它的 `end` 在按下時就來了(P61,2026-10-16,macOS 上的 GtkBackend:從把手
/// 拖曳記下 began、ended,然後才是三個值)。軌道:GtkRange 只有在 `gtk-primary-button-warps-slider` 開啟時才跳到按下處，
/// 否則以 page increment 翻頁，而這個 scale 的 page increment 是 0。macOS 上的 GDK 依捲軸偏好設定它，此處讀到 0:P61
/// 從軌道拖曳完全沒有值(2026-10-16)。`NSSlider` 不論該偏好都會跳並跟隨，所以設定關閉時，由這個控制器接手從軌道開始的
/// 拖曳：設定指標下的值、跟隨移動，並在此攔下事件，免得 GtkRange 又翻頁。按在把手上，或設定開啟時(Linux 上 GTK 的預設),
/// 交給 GtkRange。
@MainActor
final class GtkSliderEditing {
    private static let dataKey = "scui-slider-editing"

    private let range: UnsafeMutablePointer<GtkWidget>
    var onEditingChanged: ((Bool) -> Void)?
    private var editing = false
    private var draggingFromTrough = false

    private init(range: UnsafeMutablePointer<GtkWidget>) {
        self.range = range
    }

    static func install(on scale: Gtk.Widget) {
        let object = scale.gobjectPointer
        guard g_object_get_data(object, dataKey) == nil else { return }
        let boxed = Unmanaged.passRetained(GtkSliderEditing(range: scale.widgetPointer)).toOpaque()
        g_object_set_data_full(
            object,
            dataKey,
            boxed,
            { pointer in
                guard let pointer else { return }
                Unmanaged<GtkSliderEditing>.fromOpaque(pointer).release()
            }
        )

        let legacy = gtk_event_controller_legacy_new()!
        gtk_event_controller_set_propagation_phase(legacy, GTK_PHASE_CAPTURE)
        gtk_widget_add_controller(scale.widgetPointer, legacy)
        let callback:
            @convention(c) (
                UnsafeMutableRawPointer,
                OpaquePointer,
                UnsafeMutableRawPointer
            ) -> gboolean = { _, event, data in
                MainActor.assumeIsolated {
                    Unmanaged<GtkSliderEditing>.fromOpaque(data).takeUnretainedValue()
                        .received(event) ? 1 : 0
                }
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

    static func setHandler(on scale: Gtk.Widget, _ handler: @escaping (Bool) -> Void) {
        guard let pointer = g_object_get_data(scale.gobjectPointer, dataKey) else { return }
        Unmanaged<GtkSliderEditing>.fromOpaque(pointer).takeUnretainedValue()
            .onEditingChanged = handler
    }

    /// Whether the event was taken here and must not reach GtkRange.
    private func received(_ event: OpaquePointer) -> Bool {
        switch gdk_event_get_event_type(event) {
            case GDK_BUTTON_PRESS where gdk_button_event_get_button(event) == 1:
                begin()
                guard scui_primary_button_warps_slider() == 0,
                    let point = location(of: event),
                    !isOnSlider(point)
                else { return false }
                draggingFromTrough = true
                setValue(atX: point.x)
                return true
            case GDK_MOTION_NOTIFY where draggingFromTrough:
                if let point = location(of: event) {
                    setValue(atX: point.x)
                }
                return true
            case GDK_BUTTON_RELEASE where gdk_button_event_get_button(event) == 1:
                let taken = draggingFromTrough
                draggingFromTrough = false
                end()
                return taken
            case GDK_TOUCH_BEGIN:
                begin()
            case GDK_TOUCH_END, GDK_TOUCH_CANCEL:
                end()
            default:
                break
        }
        return false
    }

    private func begin() {
        guard !editing else { return }
        editing = true
        onEditingChanged?(true)
    }

    private func end() {
        guard editing else { return }
        editing = false
        onEditingChanged?(false)
    }

    private func child(of widget: UnsafeMutablePointer<GtkWidget>, named name: String)
        -> UnsafeMutablePointer<GtkWidget>?
    {
        var child = gtk_widget_get_first_child(widget)
        while let current = child {
            if String(cString: gtk_widget_get_css_name(current)) == name { return current }
            child = gtk_widget_get_next_sibling(current)
        }
        return nil
    }

    private func isOnSlider(_ point: SIMD2<Double>) -> Bool {
        var picked = gtk_widget_pick(range, point.x, point.y, GTK_PICK_DEFAULT)
        while let widget = picked, widget != range {
            if String(cString: gtk_widget_get_css_name(widget)) == "slider" { return true }
            picked = gtk_widget_get_parent(widget)
        }
        return false
    }

    /// The value whose slider centre sits at `x`, from the trough's bounds less
    /// half a slider at each end -- where GtkRange itself puts the centre.
    /// 讓滑塊中心落在 `x` 的值：軌道範圍兩端各扣半個滑塊，與 GtkRange 自己放置中心的位置相同。
    private func setValue(atX x: Double) {
        guard let trough = child(of: range, named: "trough") else { return }
        var bounds = graphene_rect_t()
        guard gtk_widget_compute_bounds(trough, range, &bounds) != 0 else { return }
        let sliderWidth = child(of: trough, named: "slider").map {
            Double(gtk_widget_get_width($0))
        } ?? 0
        let travel = Double(bounds.size.width) - sliderWidth
        guard travel > 0 else { return }
        var fraction = (x - Double(bounds.origin.x) - sliderWidth / 2) / travel
        fraction = min(max(fraction, 0), 1)
        let gtkRange = UnsafeMutableRawPointer(range).assumingMemoryBound(to: GtkRange.self)
        if gtk_range_get_inverted(gtkRange) != 0 { fraction = 1 - fraction }
        let adjustment = gtk_range_get_adjustment(gtkRange)
        let lower = gtk_adjustment_get_lower(adjustment)
        let upper = gtk_adjustment_get_upper(adjustment) - gtk_adjustment_get_page_size(adjustment)
        gtk_range_set_value(gtkRange, lower + fraction * (upper - lower))
    }

    /// The event's position in the scale's coordinates: surface coordinates,
    /// less the native's surface transform, then from the native to the scale.
    /// 事件在 scale 座標中的位置:surface 座標減去 native 的 surface transform,再由 native 換到 scale。
    private func location(of event: OpaquePointer) -> SIMD2<Double>? {
        var x = 0.0
        var y = 0.0
        guard gdk_event_get_position(event, &x, &y) != 0,
            let native = gtk_widget_get_native(range)
        else { return nil }
        var offsetX = 0.0
        var offsetY = 0.0
        gtk_native_get_surface_transform(native, &offsetX, &offsetY)
        var source = graphene_point_t(x: Float(x - offsetX), y: Float(y - offsetY))
        var result = graphene_point_t()
        let nativeWidget = UnsafeMutableRawPointer(native).assumingMemoryBound(to: GtkWidget.self)
        guard gtk_widget_compute_point(nativeWidget, range, &source, &result) != 0 else {
            return nil
        }
        return SIMD2(Double(result.x), Double(result.y))
    }
}
