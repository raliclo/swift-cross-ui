import Foundation
import SwiftCrossUI
import WinSDK
// `@preconcurrency` because `CompositionTarget.rendering` is a class property
// that swift-winui does not annotate for concurrency, and Swift 6 refuses a
// bare reference to it: "not concurrency-safe because it involves shared
// mutable state". The attribute says the module predates strict concurrency,
// which is true, and is the smallest correct answer -- the alternatives are to
// wrap the access (tried, made it worse) or to fork the binding.
// 使用 `@preconcurrency`,因為 `CompositionTarget.rendering` 是一個 class property,而
// swift-winui 並未為併發加註它,於是 Swift 6 拒絕對它的裸引用:「not concurrency-safe
// because it involves shared mutable state」。這個屬性的意思是「該模組早於嚴格併發」,
// 而那是事實,也是**最小的正確答案**——其餘選項是包裝該次存取(試過,更糟)或 fork 那份綁定。
@preconcurrency import WinUI

extension WinUIBackend: BackendFeatures.FrameClocks {
    /// `CompositionTarget.Rendering`, which fires once per composed frame.
    ///
    /// It is an app-level event rather than a per-window one, which is what the
    /// protocol wants, and it carries no usable timestamp -- its argument is an
    /// `Any?`, since `RenderingEventArgs` is not bound. The timestamp comes from
    /// the hardware performance counter instead (`monotonicSeconds()`), because
    /// the protocol asks for monotonic seconds and not for the compositor's own
    /// origin.
    ///
    /// `CompositionTarget.Rendering`，每合成一幀觸發一次。
    ///
    /// 它是一個 app 層級的事件，而不是逐視窗的——那正是本協定所要的；而它不帶可用的時間戳記：其引數是
    /// `Any?`,因為 `RenderingEventArgs` 沒有被綁定。此處改用硬體效能計數器(`monotonicSeconds()`),因為
    /// 協定要的是單調秒數，而不是合成器自己的原點。
    public func startFrameClock(handler: @escaping @MainActor (Double) -> Void) {
        stopFrameClock()
        Self.currentFrameClockHandler = handler
        // The access is bare. Swift 6 calls `CompositionTarget.rendering`
        // shared mutable state, and the fix is the `@preconcurrency` on the
        // import above rather than anything here.
        //
        // `MainActor.assumeIsolated { ... }` was tried first and made it worse:
        // it requires its RESULT to be Sendable, and `EventCleanup` is not, so
        // one error became two. Recorded because the wrapper is the obvious
        // reach and it is the wrong one.
        //
        // 此處是**裸用**。Swift 6 視 `CompositionTarget.rendering` 為共享可變狀態,而修法是上方
        // import 的 `@preconcurrency`,不是此處的任何東西。
        //
        // **先試過 `MainActor.assumeIsolated { ... }`,結果更糟**:它要求其**回傳值**符合
        // Sendable,而 `EventCleanup` 並不符合,於是一個錯誤變成兩個。此處記下來,是因為那個包裝
        // 是最直覺的伸手處,而它是錯的那一個。
        // **The timestamp comes from QueryPerformanceCounter, not from the
        // process clock -- and not from the event either, because the binding
        // for that does not exist.**
        //
        // `ProcessInfo.systemUptime` on Windows is backed by a tick count
        // coarser than a frame: measured on Win-WinUI (`fd9efe32`), 262 ticks in
        // 1.86 s with a MEDIAN GAP OF ZERO, so many ticks shared a timestamp.
        // `RenderingEventArgs.renderingTime` would carry the compositor's time,
        // but that type is not bound: 0 hits across swift-winui's generated
        // sources, against 3 for `CompositionTarget`. The event is
        // `Event<EventHandler<Any?>>`, so the second parameter is `Any?` with
        // nothing to cast it to. `QueryPerformanceCounter` is monotonic and
        // ticks with a hardware counter rather than the scheduler.
        //
        // With it (2026-09-11): 265 ticks in 1.86 s = 141.6 Hz, gap min 3.4 ms,
        // MEDIAN 7.0 ms, max 43.2 ms, on a 144 Hz display (`dxdiag /t`: "1920 x
        // 1080 (32 bit) (144Hz)"). One frame is 6.94 ms, so the median gap is
        // one frame: `CompositionTarget.Rendering` fires once per composed
        // frame, and nothing needs coalescing. The ~140 Hz rate that looked
        // suspicious had been compared against an assumed 60 Hz that was never
        // measured.
        //
        // **時間戳記取自 `QueryPerformanceCounter`——不是行程時鐘，也不是那個事件，因為後者的
        // 綁定並不存在。**
        //
        // Windows 上的 `ProcessInfo.systemUptime` 背後是一個比一幀還粗的 tick 計數：在 Win-WinUI 上量到
        // (`fd9efe32`)1.86 秒 262 次，而**間隔中位數為零**,許多次 tick 共用同一個時間戳記。
        // `RenderingEventArgs.renderingTime` 會帶著合成器的時間，但那個型別沒有被綁定：在 swift-winui 產生的
        // 原始碼中零命中，而對照的 `CompositionTarget` 有 3 個。該事件是 `Event<EventHandler<Any?>>`,第二個
        // 參數是 `Any?`,沒有任何東西可以轉型過去。`QueryPerformanceCounter` 是單調的，其週期是硬體計數器的
        // tick,不是排程器的 tick。
        //
        // 改用它之後(2026-09-11):1.86 秒 265 次 = 141.6 Hz,間隔 min 3.4ms、**中位數 7.0ms**、max 43.2ms,
        // 顯示器為 144 Hz(`dxdiag /t`:「1920 x 1080 (32 bit) (144Hz)」)。一幀是 6.94ms,因此中位數**就是一幀**:
        // `CompositionTarget.Rendering` 每合成一幀觸發一次，沒有任何東西需要合併。看似可疑的約 140 Hz,
        // 是拿去和一個從未量過、被假定的 60 Hz 相比。
        frameClockToken = CompositionTarget.rendering.addHandler { _, _ in
            MainActor.assumeIsolated {
                WinUIBackend.currentFrameClockHandler?(monotonicSeconds())
            }
        }
    }

    public func stopFrameClock() {
        // `dispose()`, not `removeHandler(token)`. `EventCleanup` carries the
        // close action with it, which is why the event itself does not have to
        // be reached for again -- and reaching for it again is what does not
        // compile.
        // 用 `dispose()`,不是 `removeHandler(token)`。`EventCleanup` 隨身攜帶著 close action,
        // 這也正是不必再去取用那個 event 本身的原因——而「再去取用它」正是編不過的那件事。
        frameClockToken?.dispose()
        frameClockToken = nil
        Self.currentFrameClockHandler = nil
    }
}

/// The performance counter's tick rate, read once.
///
/// It is fixed at boot -- Microsoft guarantees the frequency cannot change while
/// the system runs -- so this is a `let` rather than a call per frame. Zero means
/// the call failed, which is what `monotonicSeconds()` falls back on.
///
/// 效能計數器的 tick 頻率,只讀一次。
///
/// 它在開機時就固定了——Microsoft 保證該頻率在系統運行期間不會改變——因此此處是一個 `let`,
/// 而不是每一幀呼叫一次。零代表該呼叫失敗,而那正是 `monotonicSeconds()` 用來退回的條件。
private let performanceCounterFrequency: Double = {
    var frequency = LARGE_INTEGER()
    // No `!= 0` on the call. Swift's WinSDK overlay imports `WINBOOL` as `Bool`
    // here, so the C habit is a compile error rather than a silent difference:
    // "cannot convert value of type 'Bool' to expected argument type 'Int'".
    // `QuadPart` IS an integer and does take `!= 0`, which is why one line
    // carries both spellings.
    // 那個呼叫後面**不加** `!= 0`。Swift 的 WinSDK overlay 在此處把 `WINBOOL` 匯入為 `Bool`,
    // 因此那個 C 習慣得到的是編譯錯誤、而不是一個看不出來的差異:「cannot convert value of type
    // 'Bool' to expected argument type 'Int'」。而 `QuadPart` **是**整數、確實可以 `!= 0`——
    // 這正是同一行裡出現兩種寫法的原因。
    guard QueryPerformanceFrequency(&frequency), frequency.QuadPart != 0 else {
        return 0
    }
    return Double(frequency.QuadPart)
}()

/// Monotonic seconds from the hardware performance counter.
///
/// **This exists because `ProcessInfo.systemUptime` is too coarse to time frames
/// with on Windows.** Measured on Win-WinUI (`fd9efe32`): 262 frame-clock ticks
/// across 1.86s, and the MEDIAN gap between consecutive ticks was 0.0ms -- so
/// most consecutive frames read the same timestamp.
///
/// GTK's own Windows backend reaches for the same counter for the same reason
/// (`gdksurface-win32.c:170` calls `QueryPerformanceFrequency`), which is worth
/// recording: it is the platform's answer here, not a workaround invented for
/// this package.
///
/// The origin is arbitrary (it is boot, not the epoch), and that is fine --
/// `FrameClocks` asks for monotonic seconds, not for a wall clock.
///
/// 來自硬體效能計數器的單調秒數。
///
/// **它之所以存在,是因為 `ProcessInfo.systemUptime` 在 Windows 上太粗、無法用來為畫面計時。**
/// 在 Win-WinUI 上量到(`fd9efe32`):1.86 秒內 262 次 frame-clock tick,而相鄰兩次之間的間隔
/// **中位數為 0.0 毫秒**——也就是說大多數相鄰的幀讀到同一個時間戳記。
///
/// GTK 自己的 Windows backend 基於同樣的理由伸手拿同一個計數器(`gdksurface-win32.c:170` 呼叫
/// `QueryPerformanceFrequency`),這點值得記下:它是**這個平台在此處的答案**,而不是為了本套件
/// 才發明的權宜之計。
///
/// 其原點是任意的(是開機,不是 epoch),而那沒有問題——`FrameClocks` 要的是單調秒數,不是牆上時鐘。
private func monotonicSeconds() -> Double {
    var counter = LARGE_INTEGER()
    guard performanceCounterFrequency != 0, QueryPerformanceCounter(&counter) else {
        return ProcessInfo.processInfo.systemUptime
    }
    return Double(counter.QuadPart) / performanceCounterFrequency
}
