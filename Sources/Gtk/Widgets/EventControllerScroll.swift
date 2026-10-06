import CGtk

/// `GtkEventControllerScroll`, written by hand: GtkCodeGen does not generate
/// it. Signals `scroll-begin`, `scroll`, `scroll-end` and `decelerate`, as
/// GTK 4 documents them; `scroll-begin`/`scroll-end` come only from devices
/// that report phases (touchpads), not from a wheel.
///
/// `GtkEventControllerScroll` 的手寫包裝:GtkCodeGen 不會產生它。信號為 `scroll-begin`、`scroll`、
/// `scroll-end` 與 `decelerate`,與 GTK 4 文件相同;`scroll-begin`/`scroll-end` 只來自會回報階段的裝置
/// (觸控板),不來自滾輪。
open class EventControllerScroll: EventController {
    public convenience init(flags: GtkEventControllerScrollFlags) {
        self.init(gtk_event_controller_scroll_new(flags))
    }

    /// Whether the last event's deltas are in pixels (a touchpad) rather than
    /// in wheel notches.
    /// 上一個事件的 delta 是以像素(觸控板)而非滾輪刻度為單位。
    public var unitIsSurface: Bool {
        gtk_event_controller_scroll_get_unit(opaquePointer) == GDK_SCROLL_UNIT_SURFACE
    }

    open override func registerSignals() {
        super.registerSignals()

        addSignal(name: "scroll-begin") { [weak self] () in
            guard let self else { return }
            self.scrollBegin?(self)
        }

        let scrollHandler: @convention(c) (
            UnsafeMutableRawPointer, Double, Double, UnsafeMutableRawPointer
        ) -> Bool = { _, value1, value2, data in
            ReturningSignalBox2<Double, Double, Bool>.run(data, value1, value2)
        }
        addReturningSignal(name: "scroll", handler: gCallback(scrollHandler)) { [weak self] (
            dx: Double,
            dy: Double
        ) -> Bool in
            guard let self, let handler = self.scroll else { return false }
            return handler(self, dx, dy)
        }

        addSignal(name: "scroll-end") { [weak self] () in
            guard let self else { return }
            self.scrollEnd?(self)
        }
    }

    public var scrollBegin: ((EventControllerScroll) -> Void)?
    public var scroll: ((EventControllerScroll, Double, Double) -> Bool)?
    public var scrollEnd: ((EventControllerScroll) -> Void)?
}
