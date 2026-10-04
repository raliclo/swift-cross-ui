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

    public func resolveTextStyle(
        _ textStyle: SwiftCrossUI.Font.TextStyle
    ) -> SwiftCrossUI.Font.TextStyle.Resolved {
        // Android seems to only have four distinct built-in font sizes. These ratios were chosen
        // to more closely match iOS while still respecting system font size preferences.
        let textSize =
            switch textStyle {
                case .largeTitle: helpers.getLargeTextSize(Self.activity) * 1.53
                case .title: helpers.getLargeTextSize(Self.activity) * 1.29
                case .title2: helpers.getLargeTextSize(Self.activity)
                case .title3: helpers.getTitleTextSize(Self.activity)
                case .headline: helpers.getMediumTextSize(Self.activity)
                case .subheadline: helpers.getSmallTextSize(Self.activity) * 1.15
                case .body: helpers.getMediumTextSize(Self.activity)
                case .callout: helpers.getMediumTextSize(Self.activity) * 0.941
                case .caption: helpers.getSmallTextSize(Self.activity) * 0.923
                case .caption2: helpers.getSmallTextSize(Self.activity) * 0.846
                case .footnote: helpers.getSmallTextSize(Self.activity)
            }

        // Android's default system styles all seem to have line height = font size, which doesn't
        // match any other platform and can be a bit cramped. The 1.15 here is somewhat arbitrary
        // but makes it match other platforms a bit more closely.
        let lineHeight = Double(textSize) * 1.15

        return SwiftCrossUI.Font.TextStyle.Resolved(
            pointSize: Double(textSize),
            weight: textStyle == .headline ? .semibold : .regular,
            emphasizedWeight: .semibold,
            lineHeight: lineHeight
        )
    }
}

extension TextView {
    @JavaMethod
    open func setGravity(_ arg0: Int32)
}
