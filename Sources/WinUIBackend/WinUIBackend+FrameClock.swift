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
        frameClockToken = CompositionTarget.rendering.addHandler { _, _ in
            MainActor.assumeIsolated {
                WinUIBackend.currentFrameClockHandler?(
                    ProcessInfo.processInfo.systemUptime
                )
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
