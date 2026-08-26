import CGtk
import Dispatch
import Foundation
import GtkCHelpers

/// A `GtkGLArea` that draws NV12 video frames, converting them to RGB on the
/// GPU.
///
/// The reason this exists is transport rather than drawing. Handing frames to
/// GTK as `GdkMemoryTexture` requires RGBA, and RGBA at 1080p60 needs 475 MB/s
/// through a decoder pipe that measures between 247 and 416 MB/s, which caps
/// playback at 30-43 fps however fast the decoder is -- hardware decode made no
/// difference at all. NV12 carries the same picture in 12 bits per pixel
/// instead of 32, needing 178 MB/s, but there is no memory-texture format for
/// it and converting on the CPU would return the saving. So the two planes go
/// to the GPU untouched and a fragment shader does the conversion.
///
/// Ownership note: the renderer holds GL objects, which are only valid while
/// this widget's context is current. It is created before realize and its GL
/// side is set up on the first render, because a widget has no context when it
/// is constructed.
/// One-slot mailbox between the decode thread and the widget.
///
/// One slot, not a queue: a frame that has not been drawn yet is stale the
/// moment a newer one arrives, and queueing them would trade latency for
/// nothing. Overwrites are counted by the widget so the loss is visible.
///
/// 解碼執行緒與 widget 之間的單格信箱。
///
/// 只有一格而非佇列：尚未繪製的幀，在更新的一幀抵達的當下就已過期，將它們排入佇列只會以延遲
/// 換取毫無價值的東西。覆蓋次數由 widget 計數，使該項損失可見。
private final class FrameInbox: @unchecked Sendable {
    private let lock = NSLock()
    private var slot: (y: [UInt8], uv: [UInt8], width: Int, height: Int)?
    private var discarded = 0

    /// Frames replaced here before anyone took them.
    ///
    /// Counted because moving the handover to `g_idle_add` moved the discard
    /// point with it. The widget's own overwrite counter then reported 16 while
    /// 509 frames were being dropped in this slot -- a counter that no longer
    /// covered the place the loss happens, which is the same defect twice.
    ///
    /// 在此被取代、且無人取走的幀數。
    ///
    /// 之所以計數，是因為把交遞改到 `g_idle_add` 的同時，也把丟棄點一併移了過來。當時 widget
    /// 自身的覆蓋計數器回報 16，而實際上有 509 幀正在這一格中被丟棄——一個不再涵蓋「損失實際
    /// 發生之處」的計數器，是同一個缺陷犯了第二次。
    var discardedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return discarded
    }

    func store(y: [UInt8], uv: [UInt8], width: Int, height: Int) {
        lock.lock()
        if slot != nil { discarded += 1 }
        slot = (y, uv, width, height)
        lock.unlock()
    }

    private var scheduled = false

    /// True when the caller should add an idle source; false when one is already
    /// in flight.
    /// 回傳 true 表示呼叫端應加入 idle source；false 表示已有一個在途。
    func markScheduled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if scheduled { return false }
        scheduled = true
        return true
    }

    func clearScheduled() {
        lock.lock()
        scheduled = false
        lock.unlock()
    }

    func take() -> (y: [UInt8], uv: [UInt8], width: Int, height: Int)? {
        lock.lock()
        defer { lock.unlock() }
        let value = slot
        slot = nil
        return value
    }
}

/// Carries a weak view reference through a C callback's void pointer.
/// 透過 C callback 的 void 指標攜帶對 view 的弱參照。
private final class WeakViewBox {
    weak var view: NV12GLView?
    init(_ view: NV12GLView?) { self.view = view }
}

public class NV12GLView: GLArea {
    // A var set after `self.init`, not a `let` set in a designated init.
    // GLArea's `init()` is a convenience initialiser, so it cannot be
    // overridden; the pattern the other hand-written widgets use is a
    // convenience init that delegates to the pointer-taking one, and that runs
    // after all stored properties already have values.
    // 這是在 `self.init` 之後設定的 var，而非在 designated init 中設定的 let。GLArea 的
    // `init()` 是 convenience initializer，無法被 override；其他手寫 widget 採用的模式是
    // 由 convenience init 委派給接受指標的那一個，而該流程執行時所有儲存屬性都已具備初值。
    private var renderer: OpaquePointer?
    private var didRealize = false

    /// Set when the shader fails to compile or link. Worth surfacing rather
    /// than leaving the area blank: a blank GL area and a working one that has
    /// received no frame look identical.
    public private(set) var shaderError: String?

    public convenience init() {
        self.init(gtk_gl_area_new())
        // `SCUINV12Renderer` is an opaque struct in C, so Swift imports every
        // reference to it as `OpaquePointer` rather than
        // `UnsafeMutablePointer<SCUINV12Renderer>` -- the type name itself is
        // never visible from Swift. Wrapping or converting the pointer here
        // fails to typecheck for that reason, not because the pointer is wrong.
        // `SCUINV12Renderer` 在 C 中是 opaque struct，因此 Swift 會把對它的所有參照匯入為
        // `OpaquePointer`，而非 `UnsafeMutablePointer<SCUINV12Renderer>`——該型別名稱本身
        // 從 Swift 完全不可見。此處若對指標再做包裝或轉換會無法通過型別檢查，原因在此，
        // 而非指標本身有誤。
        renderer = scui_nv12_renderer_new()

        render = { [weak self] area, _ in
            // GLArea's render signal returns whether the frame was drawn; true
            // stops GTK drawing over it. It could not say so until the generated
            // signals carried a return type (#594).
            // GLArea 的 render signal 回傳「該幀是否已繪製」；true 會使 GTK 不再於其上繪製。
            // 在產生的 signal 具備回傳型別之前（#594），它無法表達這一點。
            guard let self else { return false }
            self.drawFrame(area)
            return true
        }

        installTickCallback()
    }

    deinit {
        scui_nv12_renderer_free(renderer)
    }

    /// Hands one NV12 frame over. `y` is `width * height` bytes and `uv` is
    /// `width * height / 2` bytes of interleaved Cb/Cr, the layout ffmpeg
    /// writes for `-pix_fmt nv12`.
    ///
    /// The upload happens inside the render pass rather than here, because a
    /// GL call without a current context is undefined and the decode thread has
    /// none. The frame is copied so the caller may reuse its buffer.
    /// Hands over a frame from any thread.
    ///
    /// Use this from a decode thread rather than hopping through
    /// `DispatchQueue.main.async`. A GTK app runs GTK's main loop, and nothing
    /// in GtkBackend drains libdispatch's main queue, so blocks posted there are
    /// serviced late and erratically. Measured: with `DispatchQueue.main.async`
    /// the decode loop spent 28 ms per frame waiting for those blocks to run
    /// against 8.4 ms actually reading, capping throughput at about 25 fps while
    /// the widget's own upload cost 0.3 ms.
    ///
    /// `g_idle_add` is GTK's own scheduling primitive and runs in the loop that
    /// is actually turning.
    ///
    /// 從任意執行緒交遞一幀。
    ///
    /// 請在解碼執行緒上使用本方法，而非繞經 `DispatchQueue.main.async`。GTK app 執行的是 GTK
    /// 自己的 main loop，而 GtkBackend 中沒有任何東西在抽取 libdispatch 的 main queue，因此投遞
    /// 至該處的區塊會被延遲且不規律地執行。實測：使用 `DispatchQueue.main.async` 時，解碼迴圈
    /// 每幀花費 28 ms 等待這些區塊執行，而真正的讀取只需 8.4 ms，使吞吐量被限制在約 25 fps；
    /// 同時 widget 自身的上傳成本僅 0.3 ms。
    ///
    /// `g_idle_add` 是 GTK 自己的排程原語，執行於真正在運轉的那個迴圈中。
    public nonisolated func submitFrame(y: [UInt8], uv: [UInt8], width: Int, height: Int) {
        inbox.store(y: y, uv: uv, width: width, height: height)

        // Nothing is scheduled here. A tick callback installed at construction
        // drains the slot once per frame clock tick, which is exactly the
        // cadence a video widget wants.
        //
        // Two idle-based attempts failed in opposite directions, and both were
        // guesses about GLib priorities rather than measurements:
        //
        //   g_idle_add_full at priority 0 (G_PRIORITY_DEFAULT) is *higher* than
        //   GTK's redraw at G_PRIORITY_HIGH_IDLE + 20, so 52 submissions a
        //   second starved the frame clock: `render` fired about 10 times a
        //   second while the widget's own upload cost 0.3 ms.
        //
        //   Priority 200 (G_PRIORITY_DEFAULT_IDLE) is below the redraw and never
        //   ran at all -- accepted and rendered both stayed at 0 while the slot
        //   discarded every frame.
        //
        // The frame clock is not a priority to be picked; it is the thing to
        // synchronise with.
        //
        // 此處不做任何排程。建構時安裝的 tick callback 會在每次 frame clock tick 時抽取該格位，
        // 而那正是影片 widget 所需的節奏。
        //
        // 先前兩次以 idle 為基礎的嘗試朝相反方向失敗，且兩者都是對 GLib 優先權的臆測而非量測：
        //
        //   priority 0（G_PRIORITY_DEFAULT）的 g_idle_add_full *高於* GTK 位於
        //   G_PRIORITY_HIGH_IDLE + 20 的重繪，因此每秒 52 次提交餓死了 frame clock：
        //   `render` 每秒僅觸發約 10 次，而 widget 自身的上傳只需 0.3 ms。
        //
        //   priority 200（G_PRIORITY_DEFAULT_IDLE）低於重繪，結果完全不曾執行——accepted 與
        //   rendered 皆維持為 0，而該格位丟棄了每一幀。
        //
        // frame clock 不是一個「要挑選的優先權」，而是「應該與之同步」的對象。
    }

    /// Installs the frame-clock tick callback. Called once, at construction.
    /// 安裝 frame clock 的 tick callback。僅於建構時呼叫一次。
    private func installTickCallback() {
        let box = Unmanaged.passRetained(WeakViewBox(self)).toOpaque()
        gtk_widget_add_tick_callback(
            castedPointer(),
            { _, _, pointer in
                guard let pointer else { return 0 }
                let box = Unmanaged<WeakViewBox>.fromOpaque(pointer).takeUnretainedValue()
                MainActor.assumeIsolated {
                    box.view?.drainInbox()
                }
                // G_SOURCE_CONTINUE: stay installed for the widget's lifetime.
                // G_SOURCE_CONTINUE：在 widget 的生命週期內持續安裝。
                return 1
            },
            box,
            { pointer in
                guard let pointer else { return }
                Unmanaged<WeakViewBox>.fromOpaque(pointer).release()
            }
        )
    }

    private let inbox = FrameInbox()

    private func drainInbox() {
        tickCallbacks += 1
        guard let frame = inbox.take() else { return }
        setFrame(y: frame.y, uv: frame.uv, width: frame.width, height: frame.height)
    }

    public func setFrame(y: [UInt8], uv: [UInt8], width: Int, height: Int) {
        // A frame still waiting here is one the widget never drew. It is
        // overwritten, and it has to be counted, because from the decoder's side
        // the handover looked like a success.
        //
        // Without this counter the app reported "0 dropped" while running below
        // its target rate, which is not a contradiction so much as a measurement
        // that was never taken: the only drop path counted was an explicit skip
        // in the decode loop, and that is off by default.
        //
        // 若此處仍有一幀在等待，代表該幀從未被本 widget 繪製。它會被覆蓋，而且必須被計數，
        // 因為從解碼端看來，這次交遞看起來是成功的。
        //
        // 少了這個計數器，app 會在低於目標速率執行的同時回報「0 dropped」；與其說是矛盾，
        // 不如說那是一項從未被進行的量測：唯一被計數的丟棄路徑是解碼迴圈中的明確略過，
        // 而該路徑預設是關閉的。
        if pendingFrame != nil {
            framesOverwritten += 1
        }
        framesAccepted += 1
        pendingFrame = (y, uv, width, height)
        queueRender()
    }

    /// Frames handed to the widget.
    /// 交給本 widget 的幀數。
    public private(set) var framesAccepted = 0

    /// Frames handed over that were replaced before the widget drew them. These
    /// reached the GPU never; they were discarded in this object.
    /// 已交遞但在本 widget 繪製之前即被取代的幀數。這些幀從未抵達 GPU，而是在此物件中被丟棄。
    public private(set) var framesOverwritten = 0

    /// Frames actually uploaded and drawn.
    /// 實際上傳並繪製的幀數。
    public private(set) var framesRendered = 0

    /// Time spent uploading the last frame's two planes. Separates "the widget
    /// is slow to upload" from "the widget is rarely asked to draw", which the
    /// render count alone cannot.
    /// 上傳最後一幀兩個平面所耗費的時間。用以區分「widget 上傳很慢」與「widget 很少被要求繪製」
    /// ——僅靠繪製次數無法分辨這兩者。
    public private(set) var lastUploadNanoseconds: UInt64 = 0

    /// Every time GTK emitted `render`, with or without a frame waiting.
    /// Separates "GTK rarely asks us to draw" from "we rarely have anything to
    /// draw when it does".
    /// GTK 每次發出 `render` 的次數，無論當時是否有幀在等待。用以區分「GTK 很少要求我們繪製」
    /// 與「它要求時我們很少有東西可畫」。
    public private(set) var renderCallbacks = 0

    /// Frame clock ticks seen. Distinct from `renderCallbacks`: the tick is GTK
    /// offering us a slot, the render is GTK asking us to draw. Conflating them
    /// made "the clock is slow" and "the redraw is slow" indistinguishable, and
    /// a vsync experiment was run against the wrong one.
    /// 已觀察到的 frame clock tick 次數。與 `renderCallbacks` 不同：tick 是 GTK 提供給我們的時機，
    /// render 則是 GTK 要求我們繪製。把兩者混為一談，會使「時鐘慢」與「重繪慢」無從分辨，而先前
    /// 那次 vsync 實驗正是針對了錯誤的那一個。
    public private(set) var tickCallbacks = 0

    /// Frames discarded in the cross-thread slot before the widget took them.
    /// 在跨執行緒的暫存格中、於 widget 取走之前即被丟棄的幀數。
    public nonisolated var framesDiscardedInInbox: Int { inbox.discardedCount }

    private var pendingFrame: (y: [UInt8], uv: [UInt8], width: Int, height: Int)?

    private func drawFrame(_ area: GLArea) {
        renderCallbacks += 1
        guard let handle = renderer else { return }

        if !didRealize {
            didRealize = true
            if scui_nv12_renderer_realize(handle) == 0 {
                shaderError = scui_nv12_renderer_error(handle).map { String(cString: $0) }
                    ?? "unknown shader failure"
                return
            }
        }
        guard shaderError == nil else { return }

        if let frame = pendingFrame {
            pendingFrame = nil
            framesRendered += 1
            let uploadStart = DispatchTime.now().uptimeNanoseconds
            defer {
                lastUploadNanoseconds = DispatchTime.now().uptimeNanoseconds - uploadStart
            }
            frame.y.withUnsafeBufferPointer { yBuffer in
                frame.uv.withUnsafeBufferPointer { uvBuffer in
                    scui_nv12_renderer_upload(
                        handle,
                        yBuffer.baseAddress,
                        uvBuffer.baseAddress,
                        Int32(frame.width),
                        Int32(frame.height)
                    )
                }
            }
        }

        // No size passed and no viewport set here. GtkGLArea has already bound
        // its framebuffer and viewport; computing one from
        // `gtk_widget_get_width` times the scale factor gave a different number
        // and drew the frame into the right quarter of the area with the rest
        // black -- which reads as a decode fault rather than a viewport one.
        // 此處不傳尺寸、也不設定 viewport。GtkGLArea 已綁定其 framebuffer 與 viewport；若以
        // `gtk_widget_get_width` 乘上 scale factor 自行計算，會得到不同的數值，導致畫面被繪入
        // 區域右側四分之一、其餘全黑——而該現象看起來像解碼缺陷，而非 viewport 問題。
        scui_nv12_renderer_render(handle)
    }

    public func queueRender() {
        gtk_gl_area_queue_render(castedPointer())
    }
}
