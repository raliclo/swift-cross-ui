import AndroidKit
import SwiftJava

@JavaClass("dev.swiftcrossui.androidbackend.CustomSlider")
class CustomSlider: JavaObject {
    @JavaMethod
    @_nonoverride convenience init(
        _ activity: AndroidKit.Activity!,
        environment: JNIEnvironment? = nil
    )

    @JavaMethod
    func setAction(_ action: SwiftAction?)

    /// The two edges Material's `Slider` reports by these names.
    ///
    /// Two setters rather than one taking a Bool: `SwiftAction` carries no
    /// arguments, and a Bool-carrying variant would be a new JNI bridge type
    /// for a value with two states. The platform reports the edges separately
    /// anyway.
    /// Material 的 `Slider` 以這兩個名字回報的兩個邊界。
    ///
    /// 使用兩個 setter 而非一個帶 Bool 的：`SwiftAction` 不帶參數，而為了一個只有兩種狀態的值新增
    /// 一個帶 Bool 的變體，等於新增一個 JNI 橋接型別。反正平台本來就分開回報這兩個邊界。
    @JavaMethod
    func setEditingBeganAction(_ action: SwiftAction?)

    @JavaMethod
    func setEditingEndedAction(_ action: SwiftAction?)

    @JavaMethod
    func setBounds(min: Float, max: Float, places: Int32)

    /// The active track and thumb in the tint, 0 for the theme's; see the Kotlin side.
    /// 已作用的軌道與滑塊用 tint,0 表示主題的顏色；見 Kotlin 端。
    @JavaMethod
    func setTint(_ tint: Int32)

    // Inherited from Slider
    @JavaMethod
    func getValue() -> Float

    @JavaMethod
    func setValue(_ value: Float)

    // Inherited from BaseSlider
    @JavaMethod
    func setEnabled(_ enabled: Bool)
}
