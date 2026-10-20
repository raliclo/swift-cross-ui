import CGtk
import Foundation
import Gtk
import GtkCHelpers
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
        Self.currentFrameClockHandler = handler
        // **A clock started before the first window exists still runs.**
        //
        // This returned without installing anything when there was no window yet,
        // the hazard the note above predicted, and AnimationDriver had already
        // marked its clock running, so it never asked again. An animation started
        // in `onAppear` at launch did not move until something stopped and
        // restarted the clock: launched directly on Windows GTK (2026-10-20), P96's
        // driven back.out read peak 0.0019 with 0 ticks, P98's every event waited
        // until 1.8 s, and P97's rows started at 0.33 s. The fallback below now runs
        // from the start whatever happens, and attaches the GTK clock as soon as a
        // window has a frame clock.
        //
        // **在第一個視窗出現之前啟動的時鐘照樣會跑。** 先前沒有視窗時這裡什麼都沒安裝就返回——正是上方說明
        // 預言的陷阱——而 AnimationDriver 已經把時鐘標為執行中，不會再要求一次。於是啟動時在 `onAppear` 裡開始
        // 的動畫，要等到有東西讓時鐘停下再啟動才會動:2026-10-20 在 Windows GTK 直接啟動時,P96 的 driven
        // back.out 峰值 0.0019、0 次 tick,P98 的每個事件都等到 1.8 秒,P97 的各列 0.33 秒才開始。現在下方的
        // 備援無論如何都從一開始就跑，並在視窗一有 frame clock 時掛上 GTK 的時鐘。
        Self.pendingClockBackend = self
        if let widget = frameClockWidget {
            attachFrameClock(to: widget)
        }
        // A fallback until the first tick; see scheduleFallbackTick.
        // 第一個 tick 之前的備援;見 scheduleFallbackTick。
        Self.frameClockHasTicked = false
        Self.fallbackGeneration += 1
        Self.scheduleFallbackTick(generation: Self.fallbackGeneration, after: 0.05)
    }

    /// Installs the tick callback on `widget` once it has a frame clock, which a
    /// window has from realisation on. Without one `begin_updating` could not be
    /// called and GTK would tick once and stop, so this waits for the fallback's
    /// next try instead.
    /// 在 `widget` 有了 frame clock(視窗自 realise 起就有)時安裝 tick callback。沒有的話無法呼叫
    /// `begin_updating`,GTK 只會 tick 一次就停，所以改等備援下一次再試。
    @MainActor
    fileprivate func attachFrameClock(to widget: UnsafeMutablePointer<GtkWidget>) {
        guard gtk_widget_get_frame_clock(widget) != nil else { return }
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
                    GtkBackend.frameClockHasTicked = true
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

        // **Asking for frames, which is the half that was missing.**
        //
        // The Windows side measured this on Win-gtk4 (`8babc4a2`): the callback
        // ran exactly ONCE and then never again, while returning
        // G_SOURCE_CONTINUE every time. That is not a callback asking to be
        // removed; it is a frame clock with nothing to do. GTK's clock produces
        // frames when something needs redrawing, and a tick callback is not
        // itself a reason to redraw -- `gdk_frame_clock_begin_updating` is how a
        // widget says "keep the cycle running", and it is paired with
        // `end_updating` so an idle app stops being woken.
        //
        // This is what their commit named as the remaining candidate: "whether a
        // GtkWindow is a widget that keeps producing frames at all, as opposed
        // to one that produces a frame when something invalidates it". It is the
        // second.
        //
        // **STILL NOT COMPILED HERE.** `gdk_frame_clock_get_frame_time` already
        // builds on their machine from this file, so the GDK symbols are visible;
        // `begin_updating` and `end_updating` are from the same header and the
        // same GDK 4.0. What to check is the RATE, with P64: 1 tick means this
        // was the wrong cause, and about 60 means it was the right one.
        //
        // **要求產生幀——那正是先前缺掉的那一半。**
        //
        // Windows 端在 Win-gtk4 上量到(`8babc4a2`):那個 callback 只執行了**一次**、之後再也沒有，
        // 而它每一次都回傳 G_SOURCE_CONTINUE。那不是一個「要求被移除」的 callback，那是一個
        // 「無事可做」的 frame clock。GTK 的時鐘在「有東西需要重繪」時才產生幀，而一個 tick callback
        // 本身並不構成重繪的理由——`gdk_frame_clock_begin_updating` 才是一個 widget 用來說「請讓這個
        // 循環持續下去」的方式，並與 `end_updating` 成對，好讓閒置的 app 不再被叫醒。
        //
        // 這正是他們那個 commit 所指名的、尚存的那個候選解釋:「一個 GtkWindow 究竟是一個持續產生幀的
        // widget，還是一個在有東西使其失效時才產生一幀的 widget」。答案是後者。
        //
        // **此處仍未編譯。** `gdk_frame_clock_get_frame_time` 已經能在他們的機器上從本檔建置，因此
        // GDK 的符號是看得見的;`begin_updating` 與 `end_updating` 出自同一個標頭、同一個 GDK 4.0。
        // 要查的是**速率**，用 P64:1 次代表這個成因猜錯了，約 60 代表猜對了。
        if let clock = gtk_widget_get_frame_clock(widget) {
            gdk_frame_clock_begin_updating(clock)
            frameClockUpdatingOn = clock
        }
        // **On macOS, GDK's display link keeps running until the stop.**
        //
        // GDK stops its CVDisplayLink after each presented frame and starts it
        // again from the next paint; a link started less than about 10 ms
        // before a refresh calls back one refresh later, so every frame whose
        // tick and paint took more than about 6 ms waited two refreshes, and
        // P96 ticked 33-58 fps with an idle main thread (gtk_frame_trace in
        // testapp/test_support/measure). With the link running the next
        // callback is the next refresh. No effect on other platforms.
        //
        // **macOS 上,GDK 的 display link 持續運轉到 stop 為止。** GDK 在每一幀呈現之後停掉它的
        // CVDisplayLink,並在下一次繪製時再啟動;在更新前不到約 10 毫秒才啟動的 link 會晚一個更新週期才
        // callback,因此 tick 加繪製超過約 6 毫秒的每一幀都等了兩個更新週期，而 P96 在 main thread 閒置的
        // 情況下只有 33-58 fps(testapp/test_support/measure 的 gtk_frame_trace)。link 持續運轉時，下一次
        // callback 就是下一次更新。其他平台不受影響。
        _ = scui_macos_display_link_keep_running(1)
    }

    public func stopFrameClock() {
        if let clock = frameClockUpdatingOn {
            // Paired with `begin_updating`: GTK reference-counts these, so a
            // missing `end` leaves the clock running for the process's life --
            // which looks like nothing at all until a battery is measured.
            // 與 `begin_updating` 成對:GTK 對它們計數，因此少一次 `end` 會讓那個時鐘持續運轉到行程
            // 結束——而那件事在有人量測電池之前，看起來什麼事都沒有。
            gdk_frame_clock_end_updating(clock)
        }
        frameClockUpdatingOn = nil
        // GDK may stop its display link again. / GDK 可以再次停掉它的 display link。
        _ = scui_macos_display_link_keep_running(0)
        if let id = frameClockID, let widget = frameClockAttachedTo {
            gtk_widget_remove_tick_callback(widget, id)
        }
        frameClockID = nil
        frameClockAttachedTo = nil
        Self.currentFrameClockHandler = nil
        Self.fallbackGeneration += 1
        Self.pendingClockBackend = nil
    }

    /// The widget the clock hangs on: the first window there is.
    /// 時鐘所掛的那個 widget:現有的第一個視窗。
    /// Whether the GTK clock has ticked since the last start.
    /// 自上次啟動以來 GTK 的時鐘是否已經 tick 過。
    @MainActor private static var frameClockHasTicked = false
    /// Bumped by every start and stop, so a stale fallback tick stops itself.
    /// 每次啟動與停止都會遞增，讓過時的備援 tick 自行停止。
    @MainActor private static var fallbackGeneration = 0
    /// The backend whose clock was started before it could attach, so the fallback
    /// can attach it once a window exists.
    /// 時鐘在能掛上之前就啟動的那個 backend,讓備援在有視窗之後替它掛上。
    @MainActor private static weak var pendingClockBackend: GtkBackend?

    /// Ticks from the main queue at 60 Hz until the GTK clock delivers its
    /// first tick after a start.
    ///
    /// On macOS (GDK 4.22) a clock started again after `end_updating`, with
    /// nothing on screen invalidated, gave its first tick 1.5 s, 3.4 s and
    /// about 4.2 s late (P108's second fling); without the `end_updating` it
    /// came 2 ms after the start, and neither `request_phase(UPDATE)`,
    /// `queue_draw`, `queue_allocate` nor deferring the `end` changed it. Once
    /// the first fallback frame has moved something the clock runs again, and
    /// the fallback stops at its first tick. The time is
    /// `g_get_monotonic_time`, the clock GDK's frame times are taken from.
    ///
    /// 從 main queue 以 60 Hz tick,直到 GTK 的時鐘在啟動後交出它的第一個 tick。macOS(GDK 4.22)上，在
    /// `end_updating` 之後再次啟動、而畫面上沒有東西失效的時鐘，第一個 tick 晚了 1.5 秒、3.4 秒與約 4.2 秒
    /// (P108 的第二次 fling);不呼叫 `end_updating` 時它在啟動後 2 毫秒到來，而 `request_phase(UPDATE)`、
    /// `queue_draw`、`queue_allocate` 與延後 `end` 都沒有改變它。第一個備援幀移動了東西之後時鐘就會再跑起來，
    /// 備援在它的第一個 tick 時停止。時間取 `g_get_monotonic_time`,也就是 GDK 的幀時間所根據的時鐘。
    @MainActor
    private static func scheduleFallbackTick(generation: Int, after delay: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated {
                guard generation == fallbackGeneration, !frameClockHasTicked,
                    let handler = currentFrameClockHandler
                else { return }
                // Attach to the window as soon as there is one; see startFrameClock.
                // 一有視窗就掛上;見 startFrameClock。
                if let backend = pendingClockBackend, backend.frameClockID == nil,
                    let widget = backend.frameClockWidget
                {
                    backend.attachFrameClock(to: widget)
                }
                handler(Double(g_get_monotonic_time()) / 1_000_000)
                scheduleFallbackTick(generation: generation, after: 1.0 / 60)
            }
        }
    }

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
