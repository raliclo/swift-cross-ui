import Foundation
import SwiftCrossUI
import WinUI

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
        frameClockToken = CompositionTarget.rendering.addHandler { _, _ in
            MainActor.assumeIsolated {
                WinUIBackend.currentFrameClockHandler?(
                    ProcessInfo.processInfo.systemUptime
                )
            }
        }
    }

    public func stopFrameClock() {
        if let token = frameClockToken {
            CompositionTarget.rendering.removeHandler(token)
        }
        frameClockToken = nil
        Self.currentFrameClockHandler = nil
    }
}
