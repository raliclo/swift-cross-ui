import AndroidKit
import Foundation
import SwiftCrossUI

extension AndroidBackend: BackendFeatures.FrameClocks {
    /// `Choreographer`, through a Kotlin class in this package.
    ///
    /// `FrameClockCallback.kt` implements
    /// `Choreographer.FrameCallback` -- which Swift cannot implement, because
    /// AndroidKit binds interfaces as `@JavaInterface`, a wrapper for CALLING a
    /// Java object -- and re-arms itself each frame. The timestamp comes back as
    /// a property because `SwiftAction` takes no arguments; `CustomSlider`
    /// records the same constraint.
    ///
    /// 使用 `Choreographer`，經由本套件中的一個 Kotlin 類別。
    ///
    /// `FrameClockCallback.kt` 實作 `Choreographer.FrameCallback`——那是 Swift
    /// 實作不了的，因為 AndroidKit 把介面綁定為 `@JavaInterface`，一個「用來**呼叫** Java 物件」的包裝
    /// ——並在每一幀重新掛上自己。時間戳記以屬性回傳，因為 `SwiftAction` 不帶參數;`CustomSlider` 記載了
    /// 同一項限制。
    ///
    public func startFrameClock(handler: @escaping @MainActor (Double) -> Void) {
        stopFrameClock()
        Self.currentFrameClockHandler = handler

        let callback = FrameClockCallback {
            MainActor.assumeIsolated {
                guard let callback = AndroidBackend.frameClockCallback,
                    let handler = AndroidBackend.currentFrameClockHandler
                else { return }
                handler(Double(callback.getFrameTimeNanos()) / 1_000_000_000)
            }
        }
        Self.frameClockCallback = callback
        callback.start()
    }

    public func stopFrameClock() {
        Self.frameClockCallback?.stop()
        Self.frameClockCallback = nil
        Self.currentFrameClockHandler = nil
    }
}
