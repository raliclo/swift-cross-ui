import SwiftJava
import AndroidKit
import AndroidGraphics

@JavaClass(
    "dev.swiftcrossui.androidbackend.PathView",
    extends: AndroidKit.View.self
)
class PathView: JavaObject {
    @JavaMethod
    @_nonoverride convenience init(
        _ activity: Activity?,
        environment: JNIEnvironment? = nil
    )

    @JavaMethod
    func clearGradient(_ stroke: Bool)

    @JavaMethod
    func setGradient(
        _ stroke: Bool,
        _ radial: Bool,
        _ ax: Float,
        _ ay: Float,
        _ bx: Float,
        _ by: Float,
        _ startRadius: Float,
        _ endRadius: Float
    )

    @JavaMethod
    func addGradientStop(_ stroke: Bool, _ color: Int32, _ position: Float)

    @JavaMethod
    func set(
        path: AndroidGraphics.Path?,
        fillPaint: AndroidKit.Paint?,
        strokePaint: AndroidKit.Paint?
    )
}
