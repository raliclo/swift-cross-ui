import CGtk
import Foundation
import Gtk
import GtkCHelpers
import SwiftCrossUI

// contentShape: the region goes to C, where an emission hook on
// GdkSurface::event makes the widget's `can-target` follow the pointer, so a
// press outside the shape is picked through to whatever is underneath. See
// scui_content_shape_set in gtk_helpers.c.
// contentShape:區域交給 C,由 GdkSurface::event 上的 emission hook 讓 widget 的 `can-target` 跟隨
// 指標，於是形狀外的按壓會被挑選穿透到下方的東西。見 gtk_helpers.c 的 scui_content_shape_set。
extension GtkBackend: BackendFeatures.ContentShapes {
    public func setContentShape(of widget: Widget, to region: HitRegion?) {
        GtkPressForwarding.installOnce()
        guard let region else {
            scui_content_shape_set(widget.widgetPointer, nil, nil, -1, 0)
            return
        }
        let points = region.flattenedPoints
        let counts = region.contourPointCounts.map { Int32($0) }
        points.withUnsafeBufferPointer { points in
            counts.withUnsafeBufferPointer { counts in
                scui_content_shape_set(
                    widget.widgetPointer,
                    points.baseAddress,
                    counts.baseAddress,
                    Int32(counts.count),
                    region.evenOdd ? 1 : 0
                )
            }
        }
    }

    /// Whether a press at (x, y), in the coordinates of the widget the gesture
    /// is attached to, belongs to that widget: inside its content shape (or it
    /// has none), and not a misdirected press that GTK delivered here while
    /// the widget the pointer is over is another one
    /// (`scui_content_shape_press_reaches`). Every gesture of this backend
    /// checks it as well as `can-target`, so a press that arrives before any
    /// pointer motion was seen is still not counted outside the shape.
    ///
    /// 位於手勢所附著 widget 座標中 (x, y) 的按壓是否屬於該 widget:在其 content shape 之內(或它沒有
    /// 形狀),且不是 GTK 送錯到此處、而指標實際所在的是另一個 widget 的按壓
    /// (`scui_content_shape_press_reaches`)。本 backend 的每個手勢除了 `can-target` 之外也檢查它，讓
    /// 「在看到任何指標移動之前就抵達的按壓」仍不會在形狀外被計入。
    static func pressIsInsideShape(_ gesture: EventController, _ x: Double, _ y: Double) -> Bool {
        guard let widget = gtk_event_controller_get_widget(gesture.opaquePointer) else {
            return true
        }
        return scui_content_shape_contains(widget, x, y) != 0
            && scui_content_shape_press_reaches(widget) != 0
    }

    /// ``pressIsInsideShape(_:_:_:)``, and a gesture that does not take the
    /// press is denied it, so it reports nothing more for this press -- no
    /// release, no drag update, no long press.
    ///
    /// 即 ``pressIsInsideShape(_:_:_:)``;不接下該按壓的手勢會被拒絕這個序列，因此對這次按壓不再回報
    /// 任何東西——沒有放開、沒有拖曳更新、沒有長按。
    static func admitPress(_ gesture: EventController, _ x: Double, _ y: Double) -> Bool {
        guard pressIsInsideShape(gesture, x, y) else {
            gtk_gesture_set_state(gesture.opaquePointer, GTK_EVENT_SEQUENCE_DENIED)
            return false
        }
        return true
    }

    /// ``admitPress(_:_:_:)`` for a two-finger gesture (magnify, rotate), at
    /// the centre of its touch points: a pinch that starts outside the content
    /// shape is denied. / 雙指手勢(縮放、旋轉)版本的 ``admitPress(_:_:_:)``,以觸控點的中心判斷：
    /// 從 content shape 之外開始的捏合會被拒絕。
    static func admitTwoFingerGesture(_ gesture: EventController) -> Bool {
        var x = 0.0
        var y = 0.0
        guard gtk_gesture_get_bounding_box_center(gesture.opaquePointer, &x, &y) != 0 else {
            return true
        }
        return admitPress(gesture, x, y)
    }

    /// Whether (x, y), in `widget`'s coordinates, is inside its content shape,
    /// for hover: the pointer is over the widget only where the shape is.
    /// (x, y)(`widget` 座標)是否位於其 content shape 之內，供懸停使用：指標只有在形狀之處才算在 widget 上。
    static func pointIsInsideShape(of widget: UnsafeMutablePointer<GtkWidget>?, _ x: Double, _ y: Double)
        -> Bool
    {
        guard let widget else { return true }
        return scui_content_shape_contains(widget, x, y) != 0
    }
}

/// Runs the gestures of the widgets a misdirected press should have reached.
///
/// GTK sends a button press to the widget it picked at the last pointer motion
/// and does not pick again; a press that arrives with no motion before it --
/// onto a content shape or off one -- goes to the wrong widget, and GTK offers
/// no public way to re-pick or to make an event (gtk_helpers.c explains the
/// detection). The C hook refuses the press to the wrong chain and hands it
/// here with the widget GTK should have picked. Each gesture of this backend
/// registers what a press, the motions after it and its release mean to it
/// (``set(_:on:handler:)``), and ``forward(target:stale:phase:button:x:y:)``
/// walks from that widget up to where the two chains meet -- the widgets above
/// that point get the real events -- running them in each widget's own
/// coordinates. A `GtkButton` on the way, the widget `Button` makes, is clicked
/// at a release inside it.
///
/// 執行被送錯的按壓本應抵達之 widget 的手勢。
///
/// GTK 把按鍵按下送往它在上一次指標移動時挑選的 widget,且不重新挑選；沒有先移動就抵達的按壓——落在
/// content shape 上或其外——會被送到錯的 widget,而 GTK 沒有公開的方式重新挑選或建立事件(偵測方式見
/// gtk_helpers.c)。C hook 讓錯的那條鏈拒絕該按壓，並把它連同 GTK 本應挑中的 widget 交到這裡。本 backend
/// 的每個手勢都登記按下、其後的移動與放開對它的意義(``set(_:on:handler:)``),而
/// ``forward(target:stale:phase:button:x:y:)`` 從那個 widget 往上走到兩條鏈交會之處——其上的 widget
/// 會收到真正的事件——並以各 widget 自己的座標執行它們。途中的 `GtkButton`(`Button` 所建的 widget)在其內
/// 放開時會被點擊。
@MainActor
final class GtkPressForwarding {
    enum Phase {
        case pressed
        case moved
        case released
    }

    typealias Handler = (_ phase: Phase, _ button: UInt32, _ x: Double, _ y: Double) -> Void

    private static let dataKey = "scui-forwarded-press"
    private static var installed = false

    private var handlers: [String: Handler] = [:]

    static func installOnce() {
        guard !installed else { return }
        installed = true
        scui_content_shape_set_press_forwarder { target, stale, phase, button, x, y in
            guard let target else { return }
            let phase: Phase =
                switch Int(phase) {
                    case Int(SCUI_PRESS_PRESSED): .pressed
                    case Int(SCUI_PRESS_MOTION): .moved
                    default: .released
                }
            MainActor.assumeIsolated {
                GtkPressForwarding.forward(
                    target: target, stale: stale, phase: phase, button: button, x: x, y: y)
            }
        }
    }

    /// Registers (or with `nil` removes) what a forwarded press means to the
    /// gesture `kind` on `widget`. / 登記(或以 `nil` 移除)被轉交的按壓對 `widget` 上 `kind` 手勢的意義。
    static func set(_ kind: String, on widget: Gtk.Widget, handler: Handler?) {
        let object = widget.gobjectPointer
        if let pointer = g_object_get_data(object, dataKey) {
            Unmanaged<GtkPressForwarding>.fromOpaque(pointer).takeUnretainedValue()
                .handlers[kind] = handler
            return
        }
        guard let handler else { return }
        let record = GtkPressForwarding()
        record.handlers[kind] = handler
        // +1 here, released by the destroy notify with the widget.
        // 此處 +1,由 widget 的 destroy notify 釋放。
        g_object_set_data_full(
            object,
            dataKey,
            Unmanaged.passRetained(record).toOpaque(),
            { pointer in
                guard let pointer else { return }
                Unmanaged<GtkPressForwarding>.fromOpaque(pointer).release()
            }
        )
    }

    static func forward(
        target: UnsafeMutablePointer<GtkWidget>,
        stale: UnsafeMutablePointer<GtkWidget>?,
        phase: Phase,
        button: UInt32,
        x: Double,
        y: Double
    ) {
        var current: UnsafeMutablePointer<GtkWidget>? = target
        while let widget = current {
            // From here up, GTK's own delivery reaches the widget.
            // 從這裡往上，GTK 自己的遞送就會抵達該 widget。
            if let stale, widget == stale || gtk_widget_is_ancestor(stale, widget) != 0 {
                break
            }
            var point = graphene_point_t(x: Float(x), y: Float(y))
            var local = graphene_point_t(x: 0, y: 0)
            if gtk_widget_compute_point(target, widget, &point, &local) != 0 {
                let lx = Double(local.x)
                let ly = Double(local.y)
                if let pointer = g_object_get_data(
                    UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self), dataKey)
                {
                    let record = Unmanaged<GtkPressForwarding>.fromOpaque(pointer)
                        .takeUnretainedValue()
                    for handler in Array(record.handlers.values) {
                        handler(phase, button, lx, ly)
                    }
                }
                let instance = UnsafeMutableRawPointer(widget).assumingMemoryBound(
                    to: GTypeInstance.self)
                if phase == .released, button == UInt32(GDK_BUTTON_PRIMARY),
                    g_type_check_instance_is_a(instance, gtk_button_get_type()) != 0,
                    gtk_widget_contains(widget, lx, ly) != 0
                {
                    _ = gtk_widget_activate(widget)  // GtkButton activates by clicking. / GtkButton 的 activate 即點擊。
                }
            }
            current = gtk_widget_get_parent(widget)
        }
    }

    /// A long press made of forwarded events: `action` runs once the button
    /// has been held for GTK's long-press time without a release or a move of
    /// more than a few pixels. / 由轉交事件組成的長按：按鍵按住 GTK 的長按時間、期間沒有放開也沒有移動
    /// 超過數個像素時，`action` 執行一次。
    @MainActor
    final class LongPress {
        private var generation = 0
        private var start = SIMD2<Double>(0, 0)
        var fired = false
        /// Between a press this long press took and its release.
        /// 介於本長按接下的按壓與其放開之間。
        private(set) var active = false

        func handle(_ phase: Phase, _ x: Double, _ y: Double, action: @escaping () -> Void) {
            switch phase {
                case .pressed:
                    generation += 1
                    fired = false
                    active = true
                    start = SIMD2(x, y)
                    let generation = generation
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: UInt64(Self.duration * 1_000_000_000))
                        guard let self, self.generation == generation else { return }
                        self.fired = true
                        action()
                    }
                case .moved:
                    let moved = SIMD2(x, y) - start
                    if (moved * moved).sum() > 8 * 8 { generation += 1 }
                case .released:
                    generation += 1
                    active = false
            }
        }

        /// GTK's default `gtk-long-press-time`, the 500 ms its own
        /// `GestureLongPress` waits. / GTK 預設的 `gtk-long-press-time`,即其 `GestureLongPress`
        /// 等待的 500 毫秒。
        static let duration: TimeInterval = 0.5
    }
}

/// Whether the pointer was last inside a hover target's content shape, kept on
/// the motion controller as GObject data so every update of the view finds the
/// same record and the handler hears only changes.
///
/// 指標上次是否位於懸停目標的 content shape 之內，以 GObject data 存在 motion 控制器上，讓 view 的每次
/// 更新都找到同一份紀錄，而 handler 只聽到變化。
@MainActor
final class GtkHoverInside {
    private static let dataKey = "scui-hover-inside"
    var inside = false

    static func of(_ controller: EventController) -> GtkHoverInside {
        let object = controller.gobjectPointer
        if let pointer = g_object_get_data(object, dataKey) {
            return Unmanaged<GtkHoverInside>.fromOpaque(pointer).takeUnretainedValue()
        }
        let record = GtkHoverInside()
        g_object_set_data_full(
            object,
            dataKey,
            Unmanaged.passRetained(record).toOpaque(),
            { pointer in
                guard let pointer else { return }
                Unmanaged<GtkHoverInside>.fromOpaque(pointer).release()
            }
        )
        return record
    }

    /// Records `inside` and returns whether it changed.
    /// 記錄 `inside`,並回傳它是否改變。
    func update(_ inside: Bool) -> Bool {
        guard inside != self.inside else { return false }
        self.inside = inside
        return true
    }
}
