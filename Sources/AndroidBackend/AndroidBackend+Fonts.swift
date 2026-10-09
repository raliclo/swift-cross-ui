import AndroidKit
@_spi(Backends) import SwiftCrossUI
import SwiftJava

extension AndroidKit.TextView {
    @JavaMethod
    func setTypeface(_ tf: AndroidKit.Typeface?)
}

// swiftlint:disable force_try
extension AndroidBackend {
    struct TextStyle {
        var color: Int32
        var fontSize: Float
        var lineHeightPixels: Int32
        var typeface: AndroidKit.Typeface
        var multilineTextAlignment: Int32

        func apply(to textView: AndroidKit.TextView) {
            let typedValue = try! JavaClass<AndroidKit.TypedValue>()

            textView.setTypeface(typeface)
            textView.setTextColor(color)
            textView.setTextSize(typedValue.COMPLEX_UNIT_SP, fontSize)
            textView.setLineHeight(lineHeightPixels)
            textView.setGravity(multilineTextAlignment)
            // No font padding above the first line and below the last, so a line
            // is the line height the text style asks for -- what UIKit measures.
            // With it, every Text was about 2 dp taller than on iOS, and a fixed
            // 140-high list showed 4.5 rows on Android to iOS's 5 (P11,
            // 2026-10-09). The measuring TextView goes through here too.
            // 第一行上方與最後一行下方不加字型內距，讓一行就是文字樣式要求的行高——也就是 UIKit 量到的。加了它，每個 Text 都比
            // iOS 高約 2 dp,高度固定的清單在 Android 上露出 4.5 列、iOS 是 5 列(P11,2026-10-09)。量測用的 TextView 也經過這裡。
            textView.setIncludeFontPadding(false)
        }
    }

    /// What a text style is a function of, as a string key. The colour is in
    /// it because a TextStyle carries one; the scale because the line height
    /// is converted to pixels.
    /// 文字樣式所取決的一切，組成字串鍵。顏色在內，因為 TextStyle 帶著顏色;縮放比例在內，因為行高會換算成像素。
    func textStyleKey(for environment: EnvironmentValues) -> String {
        let font = environment.resolvedFont
        let color = environment.suggestedForegroundColor.resolve(in: environment).asColorInt()
        return "\(font.design)|\(font.weight)|\(font.isItalic)|\(font.pointSize)|"
            + "\(font.lineHeight)|\(color)|\(environment.multilineTextAlignment)|"
            + "\(environment.windowScaleFactor)"
    }

    /// TextStyles already built, by `textStyleKey`.
    ///
    /// Building one looks up three Java classes and creates a Typeface, all
    /// through JNI, and it ran for every Text on every update -- and, through
    /// the measurement below, several more times per Text per layout pass.
    /// On 2026-10-04 `getTextStyle` was 19.6 % of P66's main thread.
    /// 已建立的 TextStyle,依 `textStyleKey` 存放。建立一個要經由 JNI 查三個 Java 類別並建立一個
    /// Typeface,而它原本對每個 Text 的每次更新都執行一次——透過下方的量測，每個 Text 每次排版還會再
    /// 執行好幾次。2026-10-04 `getTextStyle` 佔 P66 主執行緒的 19.6%。
    @MainActor static var textStyles: [String: TextStyle] = [:]

    func getTextStyle(from environment: EnvironmentValues) -> TextStyle {
        let key = textStyleKey(for: environment)
        if let cached = Self.textStyles[key] {
            return cached
        }
        let style = makeTextStyle(from: environment)
        Self.textStyles[key] = style
        return style
    }

    private func makeTextStyle(from environment: EnvironmentValues) -> TextStyle {
        let resolvedFont = environment.resolvedFont

        let typefaceClass = try! JavaClass<AndroidKit.Typeface>()

        let baseTypeface =
            switch resolvedFont.design {
                case .default: typefaceClass.DEFAULT
                case .monospaced: typefaceClass.MONOSPACE
            }

        let gravityClass = try! JavaClass<AndroidKit.Gravity>()

        let textAlignment =
            switch environment.multilineTextAlignment {
                case .leading: gravityClass.LEFT
                case .center: gravityClass.CENTER_HORIZONTAL
                case .trailing: gravityClass.RIGHT
            }

        let weightInt: Int32 =
            switch resolvedFont.weight {
                case .ultraLight: 100
                case .thin: 200
                case .light: 300
                case .regular: 400
                case .medium: 500
                case .semibold: 600
                case .bold: 700
                case .heavy: 800
                case .black: 900
            }

        let typeface = typefaceClass.create(baseTypeface, weightInt, resolvedFont.isItalic)!

        let colorInt = environment.suggestedForegroundColor.resolve(in: environment).asColorInt()

        let typedValue = try! JavaClass<AndroidKit.TypedValue>()

        let lineHeightPixels = Int32(
            typedValue.applyDimension(
                typedValue.COMPLEX_UNIT_SP,
                Float(resolvedFont.lineHeight),
                environment.androidActivity.getResources().getDisplayMetrics()
            )
        )

        return TextStyle(
            color: colorInt,
            fontSize: Float(resolvedFont.pointSize),
            lineHeightPixels: lineHeightPixels,
            typeface: typeface,
            multilineTextAlignment: textAlignment
        )
    }

    // No `resolveTextStyle` here: Android takes the core's mobile table, the
    // same points UIKit uses (body 17, title 28, largeTitle 34 ...), in sp so
    // the system font scale still applies. It used to read the theme's
    // TextAppearance_DeviceDefault sizes -- body 18sp against iOS's 17pt -- so
    // Android text ran about 6% wider and wrapped earlier (P4, 2026-10-09;
    // user's decision to align with iOS).
    // 這裡沒有 `resolveTextStyle`:Android 採用 core 的行動裝置字級表，與 UIKit 相同的點數(內文 17、title 28、largeTitle 34…),
    // 以 sp 計，所以系統字型縮放仍然生效。它原本讀取主題的 TextAppearance_DeviceDefault 字級——內文 18sp,iOS 是 17pt——
    // 因此 Android 的文字寬約 6%、較早斷行(P4,2026-10-09;使用者決定與 iOS 對齊)。
}

extension TextView {
    @JavaMethod
    open func setGravity(_ arg0: Int32)

    @JavaMethod
    open func setIncludeFontPadding(_ arg0: Bool)
}
