package dev.swiftcrossui.androidbackend

import android.view.Choreographer

/// Drives a Swift closure once per displayed frame.
///
/// This class exists because `Choreographer.FrameCallback` is an INTERFACE, and
/// AndroidKit binds interfaces as `@JavaInterface` structs -- wrappers for
/// calling a Java object, not something Swift can implement. Every Java-to-Swift
/// callback in this backend goes through a Kotlin class like this one holding a
/// `SwiftAction`; `ViewOnClickListener` is the same shape.
///
/// The timestamp is kept as a property rather than passed to the closure,
/// because `SwiftAction` takes no arguments. `CustomSlider` records the same
/// constraint and works around it a different way (two actions for two states);
/// here there is one event and a number, so the number is read back.
///
/// 每顯示一幀就驅動一次某個 Swift closure。
///
/// 這個類別之所以存在，是因為 `Choreographer.FrameCallback` 是一個**介面**，而 AndroidKit 把介面
/// 綁定為 `@JavaInterface` struct——那是「用來呼叫一個 Java 物件」的包裝，不是 Swift 能實作的東西。
/// 本 backend 中每一個 Java 到 Swift 的回呼，都經由一個像這樣持有 `SwiftAction` 的 Kotlin 類別;
/// `ViewOnClickListener` 就是同一個形狀。
///
/// 時間戳記以屬性保留、而不是傳給那個 closure，因為 `SwiftAction` 不帶參數。`CustomSlider` 記載了
/// 同一項限制，並以另一種方式繞開它(兩種狀態用兩個 action);此處是一個事件加一個數字，所以那個
/// 數字改用讀回的方式取得。
class FrameClockCallback(private val action: SwiftAction) : Choreographer.FrameCallback {
    /// Nanoseconds, as Choreographer reports them. Swift divides.
    /// 奈秒，即 Choreographer 所回報的單位。由 Swift 端去除。
    var frameTimeNanos: Long = 0
        private set

    private var running = false

    fun start() {
        if (running) return
        running = true
        Choreographer.getInstance().postFrameCallback(this)
    }

    fun stop() {
        if (!running) return
        running = false
        Choreographer.getInstance().removeFrameCallback(this)
    }

    override fun doFrame(frameTimeNanos: Long) {
        if (!running) return
        this.frameTimeNanos = frameTimeNanos
        // Re-arm BEFORE calling Swift: a callback is single-shot, and if the
        // Swift side throws or stops the clock the re-arm has already been
        // decided by `running` rather than by where the exception landed.
        // 在呼叫 Swift **之前**重新掛上:一個 callback 只會觸發一次，而若 Swift 端拋出例外或停掉了
        // 時鐘，是否重新掛上已經由 `running` 決定，而不是由「例外落在哪裡」決定。
        Choreographer.getInstance().postFrameCallback(this)
        action.call()
    }
}
