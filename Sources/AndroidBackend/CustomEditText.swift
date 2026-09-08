import SwiftJava
import AndroidKit

@JavaClass(
    "dev.swiftcrossui.androidbackend.CustomEditText",
    extends: AndroidKit.EditText.self
)
class CustomEditText: AndroidKit.EditText {
    @JavaMethod
    @_nonoverride convenience init(
        activity: Activity?,
        environment: JNIEnvironment? = nil
    )

    @JavaMethod
    func setOnChange(_ action: SwiftAction?)

    @JavaMethod
    func setOnSubmit(_ action: SwiftAction?)

    @JavaMethod
    func setTextFromSwift(_ text: String)

    /// Puts back the background and padding the theme gave this EditText at
    /// construction. See `Kotlin/CustomEditText.kt` for why the Kotlin side
    /// saves them rather than the Swift side reading them back.
    ///
    /// 把主題在建構時給予這個 EditText 的背景與 padding 放回去。至於為何是由 Kotlin 端存下它們、
    /// 而非由 Swift 端事後讀回，見 `Kotlin/CustomEditText.kt`。
    @JavaMethod
    func restoreDefaultChrome()
}

@JavaClass("dev.swiftcrossui.androidbackend.SecureEditText", extends: CustomEditText.self)
class SecureEditText: CustomEditText {
    @JavaMethod
    @_nonoverride convenience init(
        activity: Activity?,
        environment: JNIEnvironment? = nil
    )
}
