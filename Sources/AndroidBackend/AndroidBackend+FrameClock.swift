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
    /// **COMPILES HERE, since 2026-09-11.** It did not for a while, and the reason
    /// was never this file: the host toolchain was Swift 6.4 while the installed
    /// Android SDK was 6.3.3, so every Android build failed with module-format
    /// errors naming files nobody here wrote. `testapp/compile.zsh` now finds a
    /// matching toolchain and says which one it picked.
    ///
    /// Compiling is not running. Nothing in this file has been executed on a
    /// device or an emulator, and the checks below are still the checks.
    ///
    /// **自 2026-09-11 起，此處編得過。** 它曾有一段時間編不過，而理由從來不在這個檔案:主機的
    /// toolchain 是 Swift 6.4，而安裝的 Android SDK 是 6.3.3，因此每一次 Android 建置都以
    /// 「module 格式」錯誤失敗，指名的是一些此處沒有人寫過的檔案。`testapp/compile.zsh` 現在會找出
    /// 相符的 toolchain，並說出它選了哪一個。
    ///
    /// 編得過不等於跑得起來。本檔中沒有任何東西曾在裝置或模擬器上執行過，而下方那些要查的項目，
    /// 依然要查。
    ///
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
