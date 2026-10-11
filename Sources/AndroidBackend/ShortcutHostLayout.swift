import AndroidKit
import SwiftJava

/// The Swift side of `ShortcutHostLayout.kt`.
/// `ShortcutHostLayout.kt` 的 Swift 側。
@JavaClass("dev.swiftcrossui.androidbackend.ShortcutHostLayout")
class ShortcutHostLayout: AndroidKit.LinearLayout {
    @JavaMethod
    @_nonoverride convenience init(
        context: AndroidKit.Context?,
        environment: JNIEnvironment? = nil
    )

    @JavaMethod func setShortcutListener(_ listener: SwiftUnhandledKeyListener?)

    /// See ShortcutHostLayout.kt. 見 ShortcutHostLayout.kt。
    @JavaMethod func setOnChromeChange(_ action: SwiftAction?)

    @JavaMethod func hasTopChrome() -> Bool
}
