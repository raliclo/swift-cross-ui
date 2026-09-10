import CGtk
import Gtk
import SwiftCrossUI

extension GtkBackend: BackendFeatures.FrameClocks {
    /// `gtk_widget_add_tick_callback`, hung on a window because GTK's clock is
    /// per widget.
    ///
    /// **This is the one backend whose frame clock belongs to a WIDGET**, which
    /// is why the protocol is app-level: making every backend invent a widget
    /// would be worse than making this one pick a window. It picks the first
    /// one, and re-picks if that window is gone -- a clock attached to a closed
    /// window stops ticking, and an animation that stops when an unrelated
    /// window closes would be a very hard thing to explain.
    ///
    /// The tick callback's own hazards are already documented at length in
    /// `Sources/Gtk/Widgets/NV12GLView.swift`, which is where this call shape
    /// comes from: the `Unmanaged` box, why `nonisolated(unsafe)` on a local
    /// does not silence the sending diagnostic, and GTK's rule that the callback
    /// runs on the thread that ran `gtk_init`.
    ///
    /// **NOT COMPILED HERE (2026-09-10).** This machine has no GTK. What to
    /// check: that `frameClockWidget` finds a window at the moment the first
    /// animation starts -- if the clock is started before any window is
    /// realised, this returns without installing anything and the animation
    /// never runs. Starting it lazily from the framework should avoid that, but
    /// only a run proves it.
    ///
    /// `gtk_widget_add_tick_callback`，掛在一個視窗上，因為 GTK 的時鐘是逐 widget 的。
    ///
    /// **這是唯一一個「frame clock 屬於某個 widget」的 backend**——而那正是這個協定採 app 層級的原因:
    /// 讓每一個 backend 都去發明一個 widget，會比讓這一個去挑一個視窗更糟。它挑第一個，而若那個視窗
    /// 已經不在則重新挑——一個附在已關閉視窗上的時鐘會停止跳動，而「一個動畫因為某個無關的視窗被關掉
    /// 而停住」會是一件極難解釋的事。
    ///
    /// 這個 tick callback 自身的各種陷阱，`Sources/Gtk/Widgets/NV12GLView.swift` 已有詳盡記載，而本處
    /// 的呼叫形狀正是取自該檔:那個 `Unmanaged` 盒子、為何在區域變數上標 `nonisolated(unsafe)` 無法
    /// 消除 sending 診斷，以及 GTK 的規則「該 callback 執行於跑過 `gtk_init` 的那條執行緒上」。
    ///
    /// **此處未編譯(2026-09-10)。** 這台機器沒有 GTK。要查的是:`frameClockWidget` 在第一個動畫開始
    /// 的那一刻是否找得到視窗——若時鐘在任何視窗被 realise 之前就啟動，它會什麼都沒安裝就返回，而那個
    /// 動畫永遠不會跑。由框架延遲啟動應該可以避開這件事，但只有跑過一次才算數。
    public func startFrameClock(handler: @escaping @MainActor (Double) -> Void) {
        stopFrameClock()
        guard let widget = frameClockWidget else { return }

        Self.currentFrameClockHandler = handler
        let box = Unmanaged.passRetained(GtkFrameClockBox()).toOpaque()
        let id = gtk_widget_add_tick_callback(
            widget,
            { _, clock, pointer in
                guard pointer != nil else { return 0 }
                // `gdk_frame_clock_get_frame_time` is microseconds since an
                // arbitrary origin, which is exactly the monotonic seconds the
                // protocol asks for once divided.
                // `gdk_frame_clock_get_frame_time` 是「自某個任意原點起的微秒數」，除過之後正是本協定
                // 所要的那個單調秒數。
                let microseconds = clock.map { gdk_frame_clock_get_frame_time($0) } ?? 0
                MainActor.assumeIsolated {
                    GtkBackend.currentFrameClockHandler?(Double(microseconds) / 1_000_000)
                }
                // G_SOURCE_CONTINUE
                return 1
            },
            box,
            { pointer in
                guard let pointer else { return }
                Unmanaged<GtkFrameClockBox>.fromOpaque(pointer).release()
            }
        )
        frameClockID = id
        frameClockAttachedTo = widget
    }

    public func stopFrameClock() {
        if let id = frameClockID, let widget = frameClockAttachedTo {
            gtk_widget_remove_tick_callback(widget, id)
        }
        frameClockID = nil
        frameClockAttachedTo = nil
        Self.currentFrameClockHandler = nil
    }

    /// The widget the clock hangs on: the first window there is.
    /// 時鐘所掛的那個 widget:現有的第一個視窗。
    private var frameClockWidget: UnsafeMutablePointer<GtkWidget>? {
        (windows.first ?? precreatedWindow)?.widgetPointer
    }
}

/// Exists only so the tick callback has something to own and release.
///
/// The callback needs a non-nil user-data pointer to distinguish "installed"
/// from "torn down"; there is no per-clock state to carry, because there is one
/// clock and its handler is a type property.
///
/// 它存在的唯一目的，是讓那個 tick callback 有東西可以持有與釋放。
///
/// 該 callback 需要一個非 nil 的 user-data 指標，才能分辨「已安裝」與「已拆除」;此處沒有任何
/// 逐時鐘的狀態需要攜帶，因為時鐘只有一個，而它的 handler 是一個型別屬性。
final class GtkFrameClockBox: @unchecked Sendable {}
