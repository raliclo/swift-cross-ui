import SwiftJava
import AndroidKit

/// The Swift side of `Kotlin/CustomSegmentedGroup.kt`: `.segmented` on Android.
/// `Kotlin/CustomSegmentedGroup.kt` 的 Swift 那一側:Android 上的 `.segmented`。
@JavaClass(
    "dev.swiftcrossui.androidbackend.CustomSegmentedGroup",
    extends: AndroidKit.RadioGroup.self
)
class CustomSegmentedGroup: JavaObject {
    @JavaMethod
    @_nonoverride convenience init(
        _ activity: Activity?,
        environment: JNIEnvironment? = nil
    )

    @JavaMethod
    func update(
        _ onChange: SwiftAction?,
        _ options: [String],
        _ isEnabled: Bool,
        color: Int32,
        fontSize: Float,
        lineHeight: Int32,
        _ typeface: AndroidKit.Typeface?
    )

    @JavaMethod
    func getSelectedOption() -> Int32

    @JavaMethod
    func selectOption(_ index: Int32)
}
