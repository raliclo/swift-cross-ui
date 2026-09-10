import Foundation
import SwiftCrossUI
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
    /// protocol wants, and it carries no timestamp of its own -- the argument is
    /// an `IInspectable` that has to be queried for `RenderingEventArgs`. This
    /// uses the process uptime instead, because the protocol asks for monotonic
    /// seconds and not for the compositor's own origin.
    ///
    /// **NOT COMPILED HERE (2026-09-10).** This machine cannot build
    /// WinUIBackend. What to check, in order: that `CompositionTarget.rendering`
    /// is spelled that way by swift-winui rather than as an `add_Rendering`
    /// method, and that the token it returns is what `removeRendering` takes.
    /// The shape -- subscribe, keep the token, unsubscribe -- is the one every
    /// WinRT event uses, so if the names are wrong the fix is a rename.
    ///
    /// `CompositionTarget.Rendering`，每合成一幀觸發一次。
    ///
    /// 它是一個 app 層級的事件，而不是逐視窗的——那正是本協定所要的;而它自身不帶時間戳記,那個引數是
    /// 一個必須再查詢為 `RenderingEventArgs` 的 `IInspectable`。此處改用行程的 uptime，因為協定要的是
    /// 單調秒數，而不是合成器自己的原點。
    ///
    /// **此處未編譯(2026-09-10)。** 這台機器建不了 WinUIBackend。依序要查的是:swift-winui 是否把
    /// `CompositionTarget.rendering` 寫成這個樣子(而不是一個 `add_Rendering` 方法)，以及它回傳的
    /// token 是不是 `removeRendering` 所接受的那一個。至於形狀——訂閱、留住 token、取消訂閱——那是每一個
    /// WinRT 事件都在用的;因此若名字錯了，修法是改名。
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
        // **The timestamp comes from the event, not from the process clock.**
        //
        // Measured on Win-WinUI (`fd9efe32`): 262 ticks in 1.86s = 140.4 Hz with
        // a MEDIAN GAP OF ZERO. A median of zero means many ticks share a
        // timestamp, which is a statement about the clock being read rather than
        // about how often the event fires -- `ProcessInfo.systemUptime` on
        // Windows is backed by a tick count whose resolution is coarser than a
        // frame, so several composed frames land on the same number and the
        // count divided by the span comes out high.
        //
        // `RenderingEventArgs.renderingTime` is the compositor's own estimate of
        // when the frame will be displayed, which is exactly what the protocol
        // asks for: a monotonic time in seconds from the backend's own clock.
        //
        // If 140 Hz survives this change then the other explanation was the
        // right one -- the event really does fire more than once per frame --
        // and the fix is to coalesce on `renderingTime` instead.
        //
        // **NOT COMPILED HERE.** What to check: that the second parameter can be
        // cast to `RenderingEventArgs`, and that `renderingTime` is a `TimeSpan`
        // whose `duration` is in 100-nanosecond units as WinRT's is elsewhere.
        //
        // **時間戳記取自那個事件，而不是取自行程的時鐘。**
        //
        // 在 Win-WinUI 上量到(`fd9efe32`):1.86 秒 262 次 = 140.4 Hz，而**間隔中位數為零**。中位數
        // 為零代表許多次 tick 共用同一個時間戳記——那是一句關於「被讀取的那個時鐘」的陳述，而不是關於
        // 「事件觸發得多頻繁」:Windows 上的 `ProcessInfo.systemUptime` 背後是一個 tick 計數，其解析度
        // 比一幀還粗，因此數個合成幀會落在同一個數字上，而「次數除以時距」就會偏高。
        //
        // `RenderingEventArgs.renderingTime` 是合成器自己對「這一幀何時會被顯示」的估計，而那正是本
        // 協定所要的:一個來自 backend 自身時鐘、以秒為單位的單調時間。
        //
        // 若改完之後 140 Hz 仍在，那就代表另一個解釋才是對的——該事件確實每幀觸發不只一次——而修法
        // 會變成改以 `renderingTime` 做合併。
        //
        // **此處未編譯。** 要查的是:第二個參數是否能轉型為 `RenderingEventArgs`，以及
        // `renderingTime` 是否為一個 `TimeSpan`、其 `duration` 是否如 WinRT 他處一樣以 100 奈秒為單位。
        frameClockToken = CompositionTarget.rendering.addHandler { _, args in
            let seconds: Double
            if let args = args as? RenderingEventArgs {
                seconds = Double(args.renderingTime.duration) / 10_000_000
            } else {
                seconds = ProcessInfo.processInfo.systemUptime
            }
            MainActor.assumeIsolated {
                WinUIBackend.currentFrameClockHandler?(seconds)
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
