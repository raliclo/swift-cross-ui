import AndroidKit
import SwiftJava

@JavaClass(
    "dev.swiftcrossui.androidbackend.CustomPopupDismissListener",
    implements: AndroidKit.PopupWindow.OnDismissListener.self
)
class CustomPopupDismissListener: JavaObject {
    @JavaMethod
    @_nonoverride convenience init(
        _ action: SwiftAction?,
        environment: JNIEnvironment? = nil
    )
}
