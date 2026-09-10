import AndroidKit
import SwiftJava

/// The Swift side of `FrameClockCallback.kt`.
/// `FrameClockCallback.kt` 的 Swift 側。
@JavaClass("dev.swiftcrossui.androidbackend.FrameClockCallback")
class FrameClockCallback: JavaObject {
    @JavaMethod
    @_nonoverride convenience init(action: SwiftAction?, environment: JNIEnvironment? = nil)

    @JavaMethod
    func start()

    @JavaMethod
    func stop()

    @JavaMethod
    func getFrameTimeNanos() -> Int64
}

extension FrameClockCallback {
    convenience init(environment: JNIEnvironment? = nil, action: @escaping () -> Void) {
        let object = SwiftAction(environment: environment, action: action)
        self.init(action: object, environment: environment)
    }
}
