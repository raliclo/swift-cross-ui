import AndroidKit
import SwiftJava

/// The Swift side of `ContinuousGestureContainer.kt`.
/// `ContinuousGestureContainer.kt` 的 Swift 側。
@JavaClass("dev.swiftcrossui.androidbackend.ContinuousGestureContainer")
class ContinuousGestureContainer: AndroidKit.ViewGroup {
    @JavaMethod
    @_nonoverride convenience init(
        context: AndroidKit.Context?,
        kind: Int32,
        environment: JNIEnvironment? = nil
    )

    @JavaMethod func setOnChange(_ action: SwiftAction?)
    @JavaMethod func setOnEnd(_ action: SwiftAction?)
    @JavaMethod func getStartX() -> Float
    @JavaMethod func getStartY() -> Float
    @JavaMethod func getCurrentX() -> Float
    @JavaMethod func getCurrentY() -> Float
    @JavaMethod func getMagnification() -> Float
    @JavaMethod func getRadians() -> Float
}
