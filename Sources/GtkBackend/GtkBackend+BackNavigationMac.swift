#if os(macOS)
    import AppKit
    import CGtk
    import GtkCHelpers
    import Gtk

    /// The trackpad's "Swipe between pages" for GtkBackend on macOS. In its own
    /// file so that only this file imports AppKit beside GTK.
    ///
    /// - **Two fingers.** A touchpad scroll reaches GTK with phases: GDK
    ///   delivers `scrollingDeltaX/Y` negated as smooth scroll deltas and ends
    ///   the gesture with an `is_stop` event, which `EventControllerScroll`
    ///   reports as `scroll-begin` and `scroll-end`. A controller on the window,
    ///   in the bubble phase, sees only the scrolling that no scrolled window
    ///   under the pointer took; when the gesture ends it goes back if it moved
    ///   at least 80 points with the fingers going right and more than twice as
    ///   far across as down, while macOS allows scroll-based swipes
    ///   (`NSEvent.isSwipeTrackingFromScrollEventsEnabled`). GTK has no
    ///   equivalent of `trackSwipeEvent`, so nothing follows the fingers.
    /// - **Three fingers.** An `NSEvent.swipe` that GDK drops; a local monitor
    ///   takes it for the GTK window whose `NSWindow` it was sent to.
    ///
    /// macOS 上 GtkBackend 的觸控板「在頁面之間滑動」。放在獨立檔案，讓只有這裡在 GTK 旁 import AppKit。
    ///
    /// - **雙指。** 觸控板捲動帶著階段抵達 GTK:GDK 把 `scrollingDeltaX/Y` 取負號後當成平滑捲動的 delta 遞送，並以 `is_stop`
    ///   事件結束手勢,`EventControllerScroll` 把它回報為 `scroll-begin` 與 `scroll-end`。掛在視窗上、bubble 階段的 controller
    ///   只看得到指標下沒有任何 scrolled window 接下的捲動；手勢結束時，若手指向右移動至少 80 point、橫向距離超過縱向的兩倍，
    ///   且 macOS 允許以捲動觸發滑動(`NSEvent.isSwipeTrackingFromScrollEventsEnabled`),就返回。GTK 沒有 `trackSwipeEvent`
    ///   的對應物，因此沒有東西跟著手指移動。
    /// - **三指。** GDK 丟掉的 `NSEvent.swipe`;本地監看器替它所送往之 `NSWindow` 所屬的 GTK 視窗接下。
    extension GtkBackNavigation {
        private final class ScrollTotal {
            var dx = 0.0
            var dy = 0.0
            var inverted = false
        }

        private static var swipeMonitor: Any?

        static func attachTrackpad(to window: Gtk.Window, key: UnsafeMutableRawPointer) {
            let total = ScrollTotal()
            let scroll = EventControllerScroll(flags: GTK_EVENT_CONTROLLER_SCROLL_BOTH_AXES)
            scroll.scrollBegin = { _ in
                total.dx = 0
                total.dy = 0
            }
            scroll.scroll = { controller, dx, dy in
                total.dx += dx
                total.dy += dy
                if let event = gtk_event_controller_get_current_event(controller.opaquePointer) {
                    total.inverted =
                        gdk_scroll_event_get_relative_direction(event)
                        == GDK_SCROLL_RELATIVE_DIRECTION_INVERTED
                }
                // Observed, never consumed. 只觀察，從不接下。
                return false
            }
            scroll.scrollEnd = { _ in
                // GDK negates the deltas, so with natural scrolling the fingers
                // move against dx. GDK 把 delta 取負號，因此自然捲動時手指與 dx 反向。
                let fingersDX = total.inverted ? -total.dx : total.dx
                let isSwipe = fingersDX >= 80 && abs(total.dx) > 2 * abs(total.dy)
                total.dx = 0
                total.dy = 0
                if isSwipe, NSEvent.isSwipeTrackingFromScrollEventsEnabled {
                    _ = goBack(key, source: "two-finger swipe (scroll)")
                }
            }
            window.addEventController(scroll)

            guard swipeMonitor == nil else { return }
            swipeMonitor = NSEvent.addLocalMonitorForEvents(matching: .swipe) { event in
                // deltaX is positive for the swipe that goes back.
                // 返回方向的滑動 deltaX 為正。
                guard event.deltaX > 0, let nsWindow = event.window else { return event }
                let native = UInt(bitPattern: Unmanaged.passUnretained(nsWindow).toOpaque())
                let wentBack = MainActor.assumeIsolated { () -> Bool in
                    for key in handlers.keys
                    where scui_window_native_macos(key.assumingMemoryBound(to: GtkWidget.self))
                        .map({ UInt(bitPattern: $0) }) == native
                    {
                        if goBack(key, source: "three-finger swipe (NSEvent.swipe)") { return true }
                    }
                    return false
                }
                return wentBack ? nil : event
            }
        }
    }
#endif
