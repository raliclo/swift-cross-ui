import AndroidKit
import SwiftJava

@JavaClass(
    "dev.swiftcrossui.androidbackend.TableContainer",
    extends: AndroidKit.ViewGroup.self
)
class TableContainer: JavaObject {
    @JavaMethod
    @_nonoverride convenience init(
        _ activity: Activity?,
        environment: JNIEnvironment? = nil
    )

    @JavaMethod
    func clearHeaders()

    @JavaMethod
    func addHeader(_ view: AndroidKit.View?)

    @JavaMethod
    func clearCells()

    @JavaMethod
    func addCell(_ view: AndroidKit.View?)

    @JavaMethod
    func addRowHeight(_ height: Int32)

    @JavaMethod
    func setHeaderHeight(_ height: Int32)
}
