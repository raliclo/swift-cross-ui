@_spi(Backends) import SwiftCrossUI
import AndroidKit

// implements BackendFeatures.Sliders
extension AndroidBackend {
    public func createSlider() -> Widget {
        CustomSlider(Self.activity, environment: Self.env).as(AndroidKit.View.self)!
    }

    public func updateSlider(
        _ slider: Widget,
        minimum: Double,
        maximum: Double,
        decimalPlaces: Int,
        environment: EnvironmentValues,
        onChange: @escaping (Double) -> Void,
        onEditingChanged: @escaping (Bool) -> Void
    ) {
        let slider = slider.as(CustomSlider.self)!

        slider.setEnabled(environment.isEnabled)
        slider.setAction(SwiftAction(environment: Self.env) {
            onChange(Double(slider.getValue()))
        })
        // The two edges Material reports by those names, passed through
        // unchanged. Nothing here infers a boundary from the value.
        // Material 以這兩個名字回報的兩個邊界，原樣轉交。此處不從數值去推斷任何界線。
        slider.setEditingBeganAction(SwiftAction(environment: Self.env) {
            onEditingChanged(true)
        })
        slider.setEditingEndedAction(SwiftAction(environment: Self.env) {
            onEditingChanged(false)
        })
        slider.setBounds(min: Float(minimum), max: Float(maximum), places: Int32(decimalPlaces))
    }

    public func setValue(ofSlider slider: Widget, to value: Double) {
        slider.as(CustomSlider.self)!.setValue(Float(value))
    }
}
