import AndroidKit
import SwiftJava

@JavaClass("dev.swiftcrossui.androidbackend.DropListener")
class DropListener: JavaObject {
    @JavaMethod
    @_nonoverride convenience init(
        _ activity: Activity?,
        environment: JNIEnvironment? = nil
    )

    @JavaMethod
    func setAcceptedTypes(_ types: String)

    @JavaMethod
    func setHoverAction(_ action: SwiftAction?)

    @JavaMethod
    func setDropAction(_ action: SwiftAction?)

    @JavaMethod
    func isHovering() -> Bool

    @JavaMethod
    func getDroppedTypes() -> String

    @JavaMethod
    func getDroppedValues() -> String

    @JavaMethod
    func setDropAccepted(_ accepted: Bool)
}
