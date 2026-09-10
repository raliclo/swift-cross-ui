import AndroidKit
import Foundation
import SwiftCrossUI

extension AndroidBackend: BackendFeatures.FrameClocks {
    /// `Choreographer`, through a Kotlin class in this package.
    ///
    /// **The first version of this file used a main-queue loop and said the
    /// bridging classes "live outside this repository". That was wrong.**
    /// `Sources/AndroidBackend/Kotlin/` holds thirty-nine of them, including
    /// the `SwiftAction` every callback in this backend goes through. I had
    /// looked for `.java` files, found none outside build output, and stopped
    /// -- they are `.kt`. The claim was in a doc comment for about an hour,
    /// which is the shape this tree keeps catching: a statement about what is
    /// possible, made from an absence that was never checked properly.
    ///
    /// So this is the real thing. `FrameClockCallback.kt` implements
    /// `Choreographer.FrameCallback` -- which Swift cannot implement, because
    /// AndroidKit binds interfaces as `@JavaInterface`, a wrapper for CALLING a
    /// Java object -- and re-arms itself each frame. The timestamp comes back as
    /// a property because `SwiftAction` takes no arguments; `CustomSlider`
    /// records the same constraint.
    ///
    /// **NOT COMPILED HERE (2026-09-10)**, because this machine's Android SDK
    /// modules are built with Swift 6.3.3 against a 6.4 compiler and
    /// `compile.zsh -android` fails before reaching this file. What to check:
    /// that the Kotlin file is picked up (it is in the same directory as the
    /// thirty-nine that already are), and that `getFrameTimeNanos` is the
    /// generated accessor name for a Kotlin `val` with a private setter.
    ///
    /// 使用 `Choreographer`，經由本套件中的一個 Kotlin 類別。
    ///
    /// **本檔的第一版用的是主佇列迴圈，並寫著那些橋接類別「不在這個 repository 裡」。那是錯的。**
    /// `Sources/AndroidBackend/Kotlin/` 裡有三十九個，包括本 backend 每一個回呼都會經過的 `SwiftAction`。
    /// 我當時去找 `.java` 檔、在建置產物之外找不到，就停下來了——它們是 `.kt`。那句話在一份 doc comment
    /// 裡待了大約一小時，而那正是這棵樹一再抓到的形狀:一個關於「什麼做得到」的陳述，建立在一個從未被
    /// 好好查證過的「不存在」之上。
    ///
    /// 因此這一份才是真的。`FrameClockCallback.kt` 實作 `Choreographer.FrameCallback`——那是 Swift
    /// 實作不了的，因為 AndroidKit 把介面綁定為 `@JavaInterface`，一個「用來**呼叫** Java 物件」的包裝
    /// ——並在每一幀重新掛上自己。時間戳記以屬性回傳，因為 `SwiftAction` 不帶參數;`CustomSlider` 記載了
    /// 同一項限制。
    ///
    /// **此處未編譯(2026-09-10)**，因為這台機器的 Android SDK 模組是以 Swift 6.3.3 建置、而編譯器是
    /// 6.4，`compile.zsh -android` 在抵達本檔之前就失敗了。要查的是:那個 Kotlin 檔有沒有被納入建置
    /// (它與已被納入的那三十九個位於同一個目錄)，以及 `getFrameTimeNanos` 是不是「一個 setter 為
    /// private 的 Kotlin `val`」所產生的取值方法名稱。
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
