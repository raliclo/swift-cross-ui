import SwiftJava
import AndroidKit

/// See FittedTextView.kt. 見 FittedTextView.kt。
@JavaClass(
    "dev.swiftcrossui.androidbackend.FittedTextView",
    extends: AndroidKit.TextView.self
)
class FittedTextView: AndroidKit.TextView {
    @JavaMethod
    @_nonoverride convenience init(
        activity: Activity?,
        environment: JNIEnvironment? = nil
    )

    @JavaMethod
    func widestLineWidth() -> Int32

    @JavaMethod
    func clearGradient()

    @JavaMethod
    func setGradient(
        _ radial: Bool,
        _ ax: Float,
        _ ay: Float,
        _ bx: Float,
        _ by: Float,
        _ startRadius: Float,
        _ endRadius: Float
    )

    @JavaMethod
    func addGradientStop(_ color: Int32, _ position: Float)
}
