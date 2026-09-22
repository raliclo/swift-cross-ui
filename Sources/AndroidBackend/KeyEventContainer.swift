import AndroidKit
import SwiftJava

/// The Swift side of `KeyEventContainer.kt`.
/// `KeyEventContainer.kt` 的 Swift 側。
@JavaClass("dev.swiftcrossui.androidbackend.KeyEventContainer")
class KeyEventContainer: AndroidKit.ViewGroup {
    @JavaMethod
    @_nonoverride convenience init(
        context: AndroidKit.Context?,
        environment: JNIEnvironment? = nil
    )

    @JavaMethod func setOnKey(_ action: SwiftAction?)
    @JavaMethod func getKeyCode() -> Int32
    @JavaMethod func getBareChar() -> Int32
    @JavaMethod func getTypedChar() -> Int32
    @JavaMethod func getMetaState() -> Int32
    @JavaMethod func getPhase() -> Int32
    @JavaMethod func isModifier() -> Bool
}
