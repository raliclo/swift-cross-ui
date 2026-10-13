import AndroidKit
import SwiftCrossUI
import SwiftJava

/// The Swift side of `FocusableContainer.kt`, which carries the notes.
/// `FocusableContainer.kt` 的 Swift 側;說明在那個檔案裡。
@JavaClass(
    "dev.swiftcrossui.androidbackend.FocusableContainer",
    extends: AndroidKit.ViewGroup.self
)
class FocusableContainer: AndroidKit.ViewGroup {
    @JavaMethod
    @_nonoverride convenience init(
        _ activity: AndroidKit.Activity!,
        environment: JNIEnvironment? = nil
    )

    @JavaMethod func setFocusableNow(_ value: Bool)
    @JavaMethod func getFocusableNow() -> Bool
}

extension AndroidBackend: BackendFeatures.FocusableTargets {
    public func createFocusableTarget(wrapping child: Widget) -> Widget {
        let container = FocusableContainer(Self.activity, environment: Self.env)
        container.addView(child)
        return container.as(AndroidKit.View.self)!
    }

    public func updateFocusableTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        isFocusable: Bool
    ) {
        target.as(FocusableContainer.self)?
            .setFocusableNow(isFocusable && environment.isEnabled)
    }
}
