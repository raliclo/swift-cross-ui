import AndroidKit
@_spi(Backends) import SwiftCrossUI
import SwiftJava

// swiftlint:disable force_try

// implements BackendFeatures.ProgressBars & BackendFeatures.ProgressSpinners
extension AndroidBackend {
    public func createProgressBar() -> Widget {
        let Rstyle = try! JavaClass<AndroidKit.R.style>()

        let widget = AndroidKit.ProgressBar(
            Self.activity,
            nil,
            0,
            Rstyle.Widget_ProgressBar_Horizontal,
            environment: Self.env
        )

        widget.setMin(0)
        widget.setMax(10_000)
        helpers.styleProgressBar(widget, 0)

        return widget.as(AndroidKit.View.self)!
    }

    public func updateProgressBar(
        _ widget: Widget,
        progressFraction: Double?,
        environment: EnvironmentValues
    ) {
        let progressBar = widget.as(AndroidKit.ProgressBar.self)!
        // The fill and the indeterminate segment in the tint, 0 for colorPrimary;
        // restyled only when it changes. 填色與不確定狀態的色段用 tint,0 為 colorPrimary;只在改變時重新設定。
        helpers.styleProgressBar(progressBar, tintColorInt(environment))

        if let progressFraction {
            progressBar.setProgress(Int32(progressFraction * 10_000))
            progressBar.setIndeterminate(false)
        } else {
            progressBar.setIndeterminate(true)
        }
    }

    public func createProgressSpinner() -> Widget {
        let Rstyle = try! JavaClass<AndroidKit.R.style>()

        let widget = AndroidKit.ProgressBar(
            Self.activity,
            nil,
            0,
            Rstyle.Widget_ProgressBar_Small,
            environment: Self.env
        )

        widget.setIndeterminate(true)

        return widget.as(AndroidKit.View.self)!
    }

    public func setSize(ofProgressSpinner widget: Widget, to size: SIMD2<Int>) {
        setSize(of: widget, to: size)
    }
}
// swiftlint:enable force_try
