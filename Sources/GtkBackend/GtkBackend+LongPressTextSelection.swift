import CGtk
import Gtk
@_spi(Backends) import SwiftCrossUI

extension GtkBackend: BackendFeatures.LongPressTextSelection {
    /// A held press in an `Entry` or a `TextView`, then a drag, through GTK's
    /// own hit-testing: `gtk_text_view_get_iter_at_position` for the editor,
    /// and for the entry the `GtkText` it delegates to, whose cursor extents
    /// (`gtk_text_compute_cursor_extents`) are searched for the caret nearest
    /// the pointer -- GTK 4 publishes no `xy_to_index` for a `GtkText`, and its
    /// `PangoLayout` is private.
    ///
    /// **A legacy event controller in the capture phase, not a gesture.** A
    /// `GtkGestureDrag` was tried first and measured on 2026-10-17: GtkText
    /// claims the sequence on the press, so a capture-phase drag gesture got
    /// `drag-begin` and then `drag-end` 0.05 ms later, before the delay could
    /// run, and never fired. A legacy controller sees every raw event whatever
    /// any gesture claims. Before the delay the press is the toolkit's -- the
    /// click that places the caret and focuses the field happens as always,
    /// and a move of more than 10 pixels leaves the rest to it too. When the
    /// delay passes, every gesture on the widget is reset (the text's
    /// drag-select, and the drag-and-drop it arms when the press lands on a
    /// selection), and from then on the controller stops each motion and the
    /// release in the capture phase, so no gesture sees them and nothing
    /// scrolls.
    ///
    /// 在 `Entry` 或 `TextView` 裡按住再拖曳，透過 GTK 自己的命中測試：編輯器用
    /// `gtk_text_view_get_iter_at_position`;欄位則用它委派的 `GtkText`,在它的游標範圍
    /// (`gtk_text_compute_cursor_extents`)中找出最接近指標的插入點——GTK 4 沒有為 `GtkText` 公開
    /// `xy_to_index`,它的 `PangoLayout` 也是私有的。**用 capture 階段的 legacy 事件控制器，而不是手勢。**
    /// 先試過 `GtkGestureDrag`,2026-10-17 實測:GtkText 在按下時就 claim 這個 sequence,所以 capture 階段的
    /// 拖曳手勢收到 `drag-begin` 後 0.05 毫秒就是 `drag-end`,延遲根本來不及跑，從未成立。legacy 控制器不論
    /// 哪個手勢 claim 都看得到每個原始事件。延遲之前按壓屬於 toolkit——放插入點並讓欄位取得焦點的那次點擊照常
    /// 發生，先移動超過 10 像素也把剩下的交給它。延遲一過，widget 上的每個手勢都被重設(文字的拖曳選取，以及按在
    /// 選取上時它待命的拖放),之後控制器在 capture 階段攔下每個移動與放開，沒有手勢看得到，也不會捲動。
    public func setLongPressTextSelection(
        ofTextInput textInput: Widget,
        enabled: Bool,
        onChange: (@MainActor (TextDragSelection, TextDragSelectionPhase) -> Void)?
    ) {
        let handler = enabled ? onChange : nil
        if let entry = textInput as? Entry {
            let editable = OpaquePointer(entry.widgetPointer)
            guard let delegate = gtk_editable_get_delegate(editable) else { return }
            let text = UnsafeMutableRawPointer(delegate).assumingMemoryBound(to: GtkWidget.self)
            GtkLongPressSelection.set(handler, on: text, kind: .entry)
        } else if let textView = textInput as? Gtk.TextView {
            GtkLongPressSelection.set(handler, on: textView.widgetPointer, kind: .textView)
        }
    }
}

/// The gesture, the timer and the selection for one field or editor, kept on
/// the widget itself with `g_object_set_data_full` (as `GtkSliderEditing` is),
/// so it lives and dies with it.
/// 某個欄位或編輯器的手勢、計時器與選取，以 `g_object_set_data_full` 存在 widget 本身上(與
/// `GtkSliderEditing` 相同),與它同生共死。
@MainActor
final class GtkLongPressSelection {
    enum Kind {
        /// A `GtkText`, the entry's delegate. / `GtkText`,entry 的委派對象。
        case entry
        /// A `GtkTextView`.
        case textView
    }

    private static let dataKey = "scui-long-press-selection"

    private let widget: UnsafeMutablePointer<GtkWidget>
    private let kind: Kind
    private var handler: (@MainActor (TextDragSelection, TextDragSelectionPhase) -> Void)?
    private var tracker = LongPressSelectionTracker()
    private var origin = SIMD2<Double>(0, 0)
    private var pressTime = 0.0
    private var timer: guint = 0
    private var anchor = 0

    private init(widget: UnsafeMutablePointer<GtkWidget>, kind: Kind) {
        self.widget = widget
        self.kind = kind
    }

    /// Replaces the handler, installing the gesture the first time one is set.
    /// 替換 handler;第一次設定時安裝手勢。
    static func set(
        _ handler: (@MainActor (TextDragSelection, TextDragSelectionPhase) -> Void)?,
        on widget: UnsafeMutablePointer<GtkWidget>,
        kind: Kind
    ) {
        let object = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: CGtk.GObject.self)
        if let existing = g_object_get_data(object, dataKey) {
            Unmanaged<GtkLongPressSelection>.fromOpaque(existing).takeUnretainedValue().handler = handler
            return
        }
        guard handler != nil else { return }
        let state = GtkLongPressSelection(widget: widget, kind: kind)
        state.handler = handler
        let boxed = Unmanaged.passRetained(state).toOpaque()
        g_object_set_data_full(object, dataKey, boxed) { pointer in
            guard let pointer else { return }
            Unmanaged<GtkLongPressSelection>.fromOpaque(pointer).release()
        }
        state.install(boxed)
    }

    private func install(_ boxed: UnsafeMutableRawPointer) {
        let legacy = gtk_event_controller_legacy_new()!
        gtk_event_controller_set_propagation_phase(legacy, GTK_PHASE_CAPTURE)
        gtk_widget_add_controller(widget, legacy)
        let callback:
            @convention(c) (
                UnsafeMutableRawPointer,
                OpaquePointer,
                UnsafeMutableRawPointer
            ) -> gboolean = { _, event, data in
                MainActor.assumeIsolated {
                    Unmanaged<GtkLongPressSelection>.fromOpaque(data).takeUnretainedValue()
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

    private static func now() -> Double {
        Double(g_get_monotonic_time()) / 1_000_000
    }

    /// One raw event, before any gesture on the widget sees it. `true` stops
    /// it there: every motion and the release of a press that has become a
    /// selection, so the text's own gestures never see them.
    /// 一個原始事件，在 widget 上任何手勢看到它之前。回傳 `true` 就停在這裡:已成為選取的那次按壓的每個移動
    /// 與放開，讓文字自己的手勢永遠看不到。
    private func received(_ event: OpaquePointer) -> Bool {
        guard handler != nil else { return false }
        switch gdk_event_get_event_type(event) {
            case GDK_BUTTON_PRESS where gdk_button_event_get_button(event) == 1,
                GDK_TOUCH_BEGIN:
                if let point = location(of: event) { began(at: point) }
                return false
            case GDK_MOTION_NOTIFY, GDK_TOUCH_UPDATE:
                guard tracker.isPending || tracker.isSelecting, let point = location(of: event) else {
                    return false
                }
                handle(tracker.move(to: point, time: Self.now()))
                return tracker.isSelecting
            case GDK_BUTTON_RELEASE where gdk_button_event_get_button(event) == 1,
                GDK_TOUCH_END:
                stopTimer()
                guard tracker.isPending || tracker.isSelecting else { return false }
                let point = location(of: event) ?? origin
                let events = tracker.release(at: point, time: Self.now())
                for item in events { handle(item) }
                return events.contains(.finish)
            case GDK_TOUCH_CANCEL:
                stopTimer()
                handle(tracker.cancel())
                return false
            default:
                return false
        }
    }

    private func began(at point: SIMD2<Double>) {
        stopTimer()
        origin = point
        pressTime = Self.now()
        tracker.press(at: point, time: pressTime)
        let boxed = Unmanaged.passRetained(self).toOpaque()
        timer = g_timeout_add_full(
            G_PRIORITY_DEFAULT,
            guint(tracker.minimumDuration * 1000),
            { data in
                guard let data else { return 0 }
                MainActor.assumeIsolated {
                    let state = Unmanaged<GtkLongPressSelection>.fromOpaque(data).takeUnretainedValue()
                    state.timer = 0
                    state.handle(state.tracker.elapse(to: state.pressTime + state.tracker.minimumDuration))
                }
                return 0
            },
            boxed,
            { data in
                guard let data else { return }
                Unmanaged<GtkLongPressSelection>.fromOpaque(data).release()
            }
        )
    }

    private func stopTimer() {
        if timer != 0 {
            g_source_remove(timer)
            timer = 0
        }
    }

    /// The event's position in the widget's coordinates, as `GtkSliderEditing`
    /// computes it. / 事件在 widget 座標中的位置，算法與 `GtkSliderEditing` 相同。
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

    /// Cancels every gesture on the widget -- the text's click and drag, and
    /// with the drag the drag-and-drop of a selection pressed on -- so that
    /// nothing but this selects from here on.
    /// 取消 widget 上的每個手勢——文字的點擊與拖曳，連同按在選取上時待命的拖放——從此只有這裡在選取。
    private func cancelNativeGestures() {
        let controllers = gtk_widget_observe_controllers(widget)
        defer { g_object_unref(UnsafeMutableRawPointer(controllers)) }
        let gestureType = gtk_gesture_get_type()
        for index in 0..<g_list_model_get_n_items(controllers) {
            guard let item = g_list_model_get_item(controllers, index) else { continue }
            defer { g_object_unref(item) }
            let instance = item.assumingMemoryBound(to: GTypeInstance.self)
            if g_type_check_instance_is_a(instance, gestureType) != 0 {
                gtk_event_controller_reset(OpaquePointer(item))
            }
        }
    }

    private var extent = 0

    private func handle(_ event: LongPressSelectionTracker.Event) {
        switch event {
            case .none:
                break
            case .passThrough:
                stopTimer()
            case .select(let anchorPoint, let extentPoint):
                stopTimer()
                cancelNativeGestures()
                gtk_widget_grab_focus(widget)
                anchor = index(at: anchorPoint)
                extent = index(at: extentPoint)
                apply(.began)
            case .extend(let point):
                extent = index(at: point)
                apply(.changed)
            case .finish:
                apply(.ended)
        }
    }

    /// The character offset (GTK counts scalars) under a point in the
    /// widget's coordinates. / widget 座標中某一點底下的字元位移(GTK 以 scalar 計)。
    private func index(at point: SIMD2<Double>) -> Int {
        switch kind {
            case .textView:
                let view = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GtkTextView.self)
                var bufferX: Int32 = 0
                var bufferY: Int32 = 0
                gtk_text_view_window_to_buffer_coords(
                    view, GTK_TEXT_WINDOW_WIDGET, Int32(point.x.rounded()), Int32(point.y.rounded()),
                    &bufferX, &bufferY
                )
                var iter = GtkTextIter()
                var trailing: Int32 = 0
                gtk_text_view_get_iter_at_position(view, &iter, &trailing, bufferX, bufferY)
                // `trailing` says the point is past the middle of the
                // character: the caret goes after it.
                // `trailing` 表示該點超過字元中線：插入點放在它之後。
                if trailing > 0 { gtk_text_iter_forward_chars(&iter, trailing) }
                return Int(gtk_text_iter_get_offset(&iter))
            case .entry:
                let text = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GtkText.self)
                let editable = OpaquePointer(widget)
                let length = Int(g_utf8_strlen(gtk_editable_get_text(editable), -1))
                // The caret whose strong cursor is nearest the pointer. Single
                // line, so x alone decides.
                // strong cursor 最接近指標的那個插入點。單行，所以只看 x。
                var best = 0
                var bestDistance = Double.infinity
                var strong = graphene_rect_t()
                for position in 0...length {
                    gtk_text_compute_cursor_extents(text, gsize(position), &strong, nil)
                    let distance = abs(Double(strong.origin.x) - point.x)
                    if distance < bestDistance {
                        bestDistance = distance
                        best = position
                    }
                }
                return best
        }
    }

    private func apply(_ phase: TextDragSelectionPhase) {
        let content: String
        let held: (anchor: Int, extent: Int)
        switch kind {
            case .textView:
                let view = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GtkTextView.self)
                let buffer = gtk_text_view_get_buffer(view)
                var insert = GtkTextIter()
                var bound = GtkTextIter()
                gtk_text_buffer_get_iter_at_offset(buffer, &insert, Int32(extent))
                gtk_text_buffer_get_iter_at_offset(buffer, &bound, Int32(anchor))
                gtk_text_buffer_select_range(buffer, &insert, &bound)
                // Read back: the insert mark is the extent, selection_bound the anchor.
                // 讀回:insert mark 是延伸點,selection_bound 是錨點。
                gtk_text_buffer_get_iter_at_mark(buffer, &insert, gtk_text_buffer_get_insert(buffer))
                gtk_text_buffer_get_iter_at_mark(buffer, &bound, gtk_text_buffer_get_selection_bound(buffer))
                held = (Int(gtk_text_iter_get_offset(&bound)), Int(gtk_text_iter_get_offset(&insert)))
                var start = GtkTextIter()
                var end = GtkTextIter()
                gtk_text_buffer_get_bounds(buffer, &start, &end)
                let raw = gtk_text_buffer_get_text(buffer, &start, &end, 0)
                content = raw.map { String(cString: $0) } ?? ""
                g_free(raw)
            case .entry:
                let editable = OpaquePointer(widget)
                gtk_editable_select_region(editable, Int32(anchor), Int32(extent))
                var start: Int32 = 0
                var end: Int32 = 0
                _ = gtk_editable_get_selection_bounds(editable, &start, &end)
                let cursor = Int(gtk_editable_get_position(editable))
                held = cursor == Int(start) ? (Int(end), Int(start)) : (Int(start), Int(end))
                content = String(cString: gtk_editable_get_text(editable))
        }
        let selection = TextDragSelection(
            anchor: TextDragSelection.utf16Offset(ofScalarOffset: held.anchor, in: content),
            extent: TextDragSelection.utf16Offset(ofScalarOffset: held.extent, in: content)
        )
        handler?(selection, phase)
    }
}
