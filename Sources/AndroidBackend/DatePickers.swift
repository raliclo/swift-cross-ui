import AndroidKit
import SwiftJava
import JavaTime

@JavaClass(
    "dev.swiftcrossui.androidbackend.datepickers.AbstractDatePicker",
    extends: AndroidKit.LinearLayout.self
)
class AbstractDatePicker: AndroidKit.LinearLayout {
    @JavaMethod
    func setAction(_ action: SwiftAction?)

    @JavaMethod
    func getValue() -> LocalDateTime!

    @JavaMethod
    func setValue(_ newValue: LocalDateTime!)

    @JavaMethod
    func setRange(min: LocalDateTime!, max: LocalDateTime!)

    @JavaMethod
    func setComponents(_ components: Int32)
}

@JavaClass(
    "dev.swiftcrossui.androidbackend.datepickers.CompactDatePicker",
    extends: AbstractDatePicker.self
)
class CompactDatePicker: AbstractDatePicker {
    @JavaMethod
    @_nonoverride convenience init(
        _ activity: FragmentActivity!,
        environment: JNIEnvironment? = nil
    )

    @JavaMethod
    func setForegroundColor(_ color: Int32)
}

@JavaClass(
    "dev.swiftcrossui.androidbackend.datepickers.GraphicalDatePicker",
    extends: AbstractDatePicker.self
)
class GraphicalDatePicker: AbstractDatePicker {
    @JavaMethod
    @_nonoverride convenience init(
        _ context: AndroidKit.Context!,
        environment: JNIEnvironment? = nil
    )
}

/// The `.wheel` style. Same shape as `GraphicalDatePicker`; the difference is
/// the theme its children resolve against, and `WheelDatePicker.kt` records why
/// that is enough.
/// `.wheel` 樣式。與 `GraphicalDatePicker` 形狀相同；差別在於其子元件所解析的主題，而
/// `WheelDatePicker.kt` 記錄了為何那樣就已足夠。
@JavaClass(
    "dev.swiftcrossui.androidbackend.datepickers.WheelDatePicker",
    extends: AbstractDatePicker.self
)
class WheelDatePicker: AbstractDatePicker {
    @JavaMethod
    @_nonoverride convenience init(
        _ context: AndroidKit.Context!,
        environment: JNIEnvironment? = nil
    )
}
