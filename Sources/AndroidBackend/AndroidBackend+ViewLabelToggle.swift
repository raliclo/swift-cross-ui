import AndroidKit
import SwiftJava
@_spi(Backends) import SwiftCrossUI

/// The Kotlin `ViewLabelToggleButton`: a button-style toggle whose label is a
/// SwiftCrossUI view, drawn as the string-label toggle is (see the Kotlin file).
/// Kotlin 的 `ViewLabelToggleButton`:標籤為 SwiftCrossUI view 的按鈕樣式 toggle,畫法與字串標籤 toggle 相同(見 Kotlin 檔)。
@JavaClass(
    "dev.swiftcrossui.androidbackend.ViewLabelToggleButton",
    extends: AndroidKit.FrameLayout.self
)
class ViewLabelToggleButton: AndroidKit.FrameLayout {
    @JavaMethod
    @_nonoverride convenience init(
        _ activity: Activity?,
        environment: JNIEnvironment? = nil
    )

    @JavaMethod
    func set(action: SwiftAction?, isEnabled: Bool)

    @JavaMethod
    func setOn(_ value: Bool)

    @JavaMethod
    func isOn() -> Bool
}

extension JavaClass where JavaClass_T == ViewLabelToggleButton {
    @JavaStaticField(isFinal: true)
    var verticalPadding: Int32
}

extension AndroidBackend: BackendFeatures.ViewLabelToggleButtons {
    public func createToggle(wrapping widget: Widget) -> Widget {
        let toggle = ViewLabelToggleButton(Self.activity, environment: Self.env)
        let content = widget.as(AndroidKit.View.self)!
        toggle.addView(content, 0)
        return toggle.as(AndroidKit.View.self)!
    }

    public func updateToggle(
        _ toggle: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (Bool) -> Void
    ) {
        let toggle = toggle.as(ViewLabelToggleButton.self)!
        let action = SwiftAction(environment: Self.env) {
            onChange(toggle.isOn())
        }
        toggle.set(action: action, isEnabled: environment.isEnabled)
    }

    public func setState(ofViewLabelToggle toggle: Widget, to state: Bool) {
        let toggle = toggle.as(ViewLabelToggleButton.self)!
        toggle.setOn(state)
    }

    /// No inset at the sides and 6 dp above and below, as `styleToggleButton`
    /// pads the string-label toggle; the fill reaches past the sides without
    /// taking part in the layout.
    /// 左右不內縮、上下各 6 dp,與 `styleToggleButton` 對字串標籤 toggle 的 padding 相同；填色超出左右兩側但不參與排版。
    public func toggleButtonPadding(in environment: EnvironmentValues) -> SIMD2<Int> {
        SIMD2(0, Int(Self.viewLabelToggleVerticalPadding) * 2)
    }

    @MainActor static let viewLabelToggleVerticalPadding: Int32 =
        try! JavaClass<ViewLabelToggleButton>().verticalPadding

    /// White on the filled (on) toggle and the theme's primary colour off, both
    /// faded when disabled, as `applyToggleButtonTextColors` colours the
    /// string-label toggle. An app's own colour wins.
    /// 開(填滿)時白色、關時主題的 primary 色，停用時兩者都變淡，與 `applyToggleButtonTextColors` 為字串標籤 toggle 上色的
    /// 方式相同。app 自己的顏色優先。
    public func computeToggleLabelEnvironment(
        from environment: EnvironmentValues,
        isOn: Bool
    ) -> EnvironmentValues {
        guard environment.foregroundColor == nil else { return environment }
        let base: SwiftCrossUI.Color =
            isOn ? .white : (primaryColor(for: environment) ?? environment.suggestedForegroundColor)
        return environment.with(
            \.foregroundColor, environment.isEnabled ? base : base.opacity(0.38)
        )
    }
}
