import AndroidKit
import Foundation
import SwiftCrossUI

extension AndroidBackend: BackendFeatures.FrameClocks {
    /// A main-queue loop, and NOT `Choreographer`, for a reason that is about
    /// this repository rather than about Android.
    ///
    /// **`Choreographer.postFrameCallback` is the right API and cannot be used
    /// from here.** It takes a `Choreographer.FrameCallback`, which AndroidKit
    /// binds as a `@JavaInterface` -- a wrapper for CALLING a Java object, not
    /// something Swift can implement. Every Java-to-Swift callback in this
    /// backend goes through a Java class that holds a `SwiftAction`
    /// (`ViewOnClickListener` is the pattern), and those classes live in
    /// `dev.swiftcrossui.androidbackend`, which is not in this repository. So a
    /// `SwiftFrameCallback` would have to be added there first.
    ///
    /// What this does instead is re-arm a main-queue block every frame period.
    /// It is honestly worse and the difference is worth stating: it is not
    /// vsync-locked, so on a 90 or 120 Hz phone it will neither match the
    /// display nor drift predictably. It is a real clock at a real rate, which
    /// is enough to drive an animation, and it is not what this should end up
    /// using.
    ///
    /// **未編譯於此(2026-09-10)** ——這台機器的 Android SDK 模組是以 Swift 6.3.3 編出來的，而編譯器
    /// 是 6.4。
    ///
    /// 一個主佇列迴圈，而**不是** `Choreographer`;理由關乎這個 repository，而非關乎 Android。
    ///
    /// **`Choreographer.postFrameCallback` 才是對的 API，而它在此處用不了。** 它收一個
    /// `Choreographer.FrameCallback`，而 AndroidKit 把它綁定為 `@JavaInterface`——那是「用來**呼叫**
    /// 一個 Java 物件」的包裝，不是 Swift 能實作的東西。本 backend 中每一個 Java 到 Swift 的回呼，
    /// 都經由一個持有 `SwiftAction` 的 Java 類別(`ViewOnClickListener` 就是那個範式)，而那些類別位於
    /// `dev.swiftcrossui.androidbackend`——它不在這個 repository 裡。因此得先在那裡加一個
    /// `SwiftFrameCallback`。
    ///
    /// 此處的替代做法，是每隔一個幀週期就重新排一個主佇列區塊。它誠實地比較差，而那個差別值得說明:
    /// 它沒有鎖在 vsync 上，因此在 90 或 120 Hz 的手機上，它既不會與顯示器一致、也不會可預測地漂移。
    /// 它是一個以真實速率運作的真實時鐘，足以驅動動畫——但它不該是這件事最終所使用的東西。
    public func startFrameClock(handler: @escaping @MainActor (Double) -> Void) {
        stopFrameClock()
        let generation = Self.frameClockGeneration &+ 1
        Self.frameClockGeneration = generation
        Self.currentFrameClockHandler = handler
        Self.scheduleFrame(generation: generation)
    }

    public func stopFrameClock() {
        // Bumping the generation is what stops the loop: a block already queued
        // cannot be cancelled, so it checks whether it is still the current one
        // and returns if it is not. A boolean would let a stop-then-start inside
        // one frame leave two loops running.
        // 讓迴圈停下來的是「把世代號加一」:一個已經排入佇列的區塊取消不掉，因此它會檢查自己是不是
        // 仍然是當前的那一個，若不是就直接返回。若用布林值，一次「在同一幀內先停再啟」會留下兩個
        // 同時運作的迴圈。
        Self.frameClockGeneration &+= 1
        Self.currentFrameClockHandler = nil
    }

    static func scheduleFrame(generation: UInt64) {
        DispatchQueue.main.asyncAfter(deadline: .now() + frameClockInterval) {
            MainActor.assumeIsolated {
                guard generation == frameClockGeneration,
                    let handler = currentFrameClockHandler
                else { return }
                handler(ProcessInfo.processInfo.systemUptime)
                scheduleFrame(generation: generation)
            }
        }
    }

    /// 60 Hz, stated as a number rather than read from the display, because
    /// reading it needs `Display.getRefreshRate` through an activity and this
    /// path is already the fallback. See the note above.
    /// 60 Hz，以一個數字寫死而非從顯示器讀取——因為讀取它需要透過 activity 取得
    /// `Display.getRefreshRate`，而這條路徑本來就已經是備案。見上方說明。
    static let frameClockInterval = 1.0 / 60.0
}
