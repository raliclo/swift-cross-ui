import AndroidKit
import SwiftJava

/// See MaterialSymbols.kt. 見 MaterialSymbols.kt。
@JavaClass(
    "dev.swiftcrossui.androidbackend.MaterialSymbolView",
    extends: AndroidKit.View.self
)
class MaterialSymbolView: AndroidKit.View {
    @JavaMethod
    @_nonoverride convenience init(
        _ context: AndroidKit.Context?,
        environment: JNIEnvironment? = nil
    )

    @JavaMethod
    func setSymbol(_ name: String) -> Bool

    @JavaMethod
    func setColor(_ color: Int32)
}

/// See MaterialSymbols.kt. 見 MaterialSymbols.kt。
@JavaClass("dev.swiftcrossui.androidbackend.MaterialSymbols")
class MaterialSymbols: JavaObject {}

extension JavaClass<MaterialSymbols> {
    @JavaStaticMethod
    func has(_ name: String) -> Bool
}
