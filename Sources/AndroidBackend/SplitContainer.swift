import AndroidKit
import SwiftJava

@JavaClass(
    "dev.swiftcrossui.androidbackend.SplitContainer",
    extends: AndroidKit.ViewGroup.self
)
class SplitContainer: JavaObject {
    @JavaMethod
    @_nonoverride convenience init(
        _ activity: Activity?,
        environment: JNIEnvironment? = nil
    )

    @JavaMethod
    func setChildren(_ leading: AndroidKit.View?, _ trailing: AndroidKit.View?)

    @JavaMethod
    func setSidebarWidthBounds(_ minimum: Int32, _ maximum: Int32)

    @JavaMethod
    func resolvedSidebarWidth() -> Int32

    @JavaMethod
    func setResizeHandler(_ handler: SwiftAction?)
}
