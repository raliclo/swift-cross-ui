import AndroidKit
import Foundation
import SwiftJava

/// The Swift side of `RootScrollHost.kt`.
///
/// Only what crosses the boundary is bound. The mode is an `Int32` rather than
/// a Swift enum because JNI carries primitives and objects, not Kotlin enums,
/// and a two-case integer needs no marshalling on either side. `titleFor` is
/// not bound at all: the Kotlin control writes its own label, and a second
/// place that knows what the two modes are called is a second place to get it
/// wrong.
///
/// `RootScrollHost.kt` 的 Swift 這一側。
///
/// 只綁定會跨越邊界的東西。模式以 `Int32` 而非 Swift enum 表示，因為 JNI 承載的是基本型別與物件，
/// 而不是 Kotlin 的 enum，而一個只有兩個值的整數在兩側都不需要任何轉換。`titleFor` 完全沒有綁定：
/// 標籤由 Kotlin 那側的控制項自行寫入，而「第二個知道那兩個模式叫什麼的地方」，就是「第二個會寫錯
/// 它們的地方」。
@JavaClass("dev.swiftcrossui.androidbackend.RootScrollHost")
class RootScrollHost: AndroidView.View {
    @JavaMethod
    @_nonoverride convenience init(
        _ context: AndroidContent.Context?,
        environment: JNIEnvironment? = nil
    )

    /// Puts a view in the scrolling area. Replaces whatever was there.
    /// 把一個 view 放進捲動區域，並取代原本在那裡的東西。
    @JavaMethod
    func host(_ view: AndroidView.View?)

    @JavaMethod
    func getModeIndex() -> Int32

    @JavaMethod
    func setModeIndex(_ mode: Int32)

    /// Adds the floating mode control.
    ///
    /// Not called unless ``DebugFeatures/allowsRootScrollControl`` is true. The
    /// gate is on this side because the flag is: Kotlin has no view of
    /// `CommandLine.arguments` or of `#if SCUI_DEBUG`.
    ///
    /// 加入那個浮動的模式控制項。
    ///
    /// 除非 ``DebugFeatures/allowsRootScrollControl`` 為真，否則不會被呼叫。這個判斷之所以在這一側，
    /// 是因為那個旗標在這一側：Kotlin 看不到 `CommandLine.arguments`，也看不到 `#if SCUI_DEBUG`。
    @JavaMethod
    func installModeButton(_ activity: Activity?)
}
