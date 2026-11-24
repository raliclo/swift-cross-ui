import CGtk
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
    /// is attached to, is inside that widget's content shape, or it has none.
    /// Tap gestures check it as well as `can-target`, so a press that arrives
    /// before any pointer motion was seen is still not counted outside the shape.
    /// 位於手勢所附著 widget 座標中 (x, y) 的按壓是否在該 widget 的 content shape 之內(或它沒有形狀)。
    /// 點擊手勢除了 `can-target` 之外也檢查它，讓「在看到任何指標移動之前就抵達的按壓」仍不會在形狀外被計入。
    static func pressIsInsideShape(_ gesture: EventController, _ x: Double, _ y: Double) -> Bool {
        guard let widget = gtk_event_controller_get_widget(gesture.opaquePointer) else {
            return true
        }
        return scui_content_shape_contains(widget, x, y) != 0
    }
}
