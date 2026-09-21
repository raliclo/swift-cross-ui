import AndroidKit
import SwiftJava

@JavaClass(
    "dev.swiftcrossui.androidbackend.ViewOnContextClickListener",
    implements: AndroidView.View.OnContextClickListener.self
)
class ViewOnContextClickListener: JavaObject {
    @JavaMethod
    @_nonoverride convenience init(action: SwiftAction?, environment: JNIEnvironment? = nil)
}

extension ViewOnContextClickListener {
    convenience init(action: @escaping () -> (), environment: JNIEnvironment? = nil) {
        let object = SwiftAction(environment: environment, action: action)
        self.init(action: object, environment: environment)
    }
}
