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
}
