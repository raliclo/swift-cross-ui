@_spi(Backends) import SwiftCrossUI

/// `tint(_:)` on Android. The controls here are drawn by AndroidBackendHelpers.kt
/// and CustomSlider.kt in colours of their own -- iOS's systemGreen switch and
/// systemBlue checkbox, colorPrimary for the progress bar, the slider and a
/// button-style toggle -- so the tint goes to the Kotlin side as one more colour
/// argument, which replaces that colour. Labels drawn in colorPrimary (a
/// borderless button, a menu picker) take it through the environment instead;
/// see `accentColor(for:)`.
///
/// Android 上的 `tint(_:)`。此處的控制項由 AndroidBackendHelpers.kt 與 CustomSlider.kt 以它們自己的顏色繪製——
/// iOS 的 systemGreen 開關與 systemBlue 核取方塊，進度條、滑桿與按鈕樣式 toggle 用 colorPrimary——所以 tint 以多一個
/// 顏色參數交給 Kotlin 端，取代那個顏色。以 colorPrimary 繪製的標籤(無框按鈕、選單 picker)則經由 environment 取得它；
/// 見 `accentColor(for:)`。
extension AndroidBackend {
    /// The tint as an ARGB colour int, or 0 for the control's own colour.
    /// A tint that resolves to fully transparent black is 0 too, and draws
    /// the default: a control painted in nothing would vanish.
    /// tint 的 ARGB 色彩整數，0 表示控制項自己的顏色。解析為完全透明黑色的 tint 也是 0,畫成預設：什麼顏色都不畫的控制項會消失。
    func tintColorInt(_ environment: EnvironmentValues) -> Int32 {
        environment.tint?.resolve(in: environment).asColorInt() ?? 0
    }

    /// The accent a label is drawn in: the tint, else colorPrimary.
    /// 標籤所用的強調色:tint,否則 colorPrimary。
    func accentColor(for environment: EnvironmentValues) -> SwiftCrossUI.Color? {
        environment.tint ?? primaryColor(for: environment)
    }
}
