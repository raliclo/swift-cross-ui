import AndroidKit
import SwiftJava

/// The Swift side of `ScrollGestureContainer.kt`.
/// `ScrollGestureContainer.kt` 的 Swift 側。
@JavaClass("dev.swiftcrossui.androidbackend.ScrollGestureContainer")
class ScrollGestureContainer: AndroidKit.ViewGroup {
    @JavaMethod
    @_nonoverride convenience init(
        context: AndroidKit.Context?,
        environment: JNIEnvironment? = nil
    )

    @JavaMethod func setOnChange(_ action: SwiftAction?)
    @JavaMethod func setOnEnd(_ action: SwiftAction?)
    @JavaMethod func getDeltaX() -> Float
    @JavaMethod func getDeltaY() -> Float
    @JavaMethod func getTravelX() -> Float
    @JavaMethod func getTravelY() -> Float
    @JavaMethod func isPrecise() -> Bool
}
