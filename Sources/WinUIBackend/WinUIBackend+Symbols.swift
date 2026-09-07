@_spi(Backends) import SwiftCrossUI
import WinUI

/// Segoe icon glyphs, drawn into the same `TextBlock` that draws text.
///
/// The same shape as the two Apple backends, and possible for the same reason:
/// a Segoe icon **is** text -- a code point in the Private Use Area rendered by
/// an icon font -- so both outcomes are one `TextBlock` with a different font
/// family, and no container is needed the way GTK and Android need one.
///
/// **Two families are named, not one.** Segoe Fluent Icons ships with Windows 11
/// and is absent from a default Windows 10, where the equivalent font is Segoe
/// MDL2 Assets; WinAppSDK supports Windows 10 1809 and later, and MDL2 has
/// shipped in every Windows 10. XAML's `FontFamily` takes a comma-separated
/// list and uses the first family present, so naming both means the glyph is
/// drawn on either. A missing icon font would otherwise render every symbol as
/// an empty box -- the Windows form of the same silent blank this feature
/// exists to prevent.
///
/// Segoe 圖示字符，畫進與文字同一個 `TextBlock` 之中。
///
/// 與兩個 Apple backend 形狀相同，而其可行的理由也相同：一個 Segoe 圖示**就是**文字——由圖示字型
/// 繪製的一個 Private Use Area 碼位——因此兩種結果都是同一個 `TextBlock` 換一個字型家族，不需要
/// GTK 與 Android 所需的那種容器。
///
/// **此處指名兩個家族，不是一個。** Segoe Fluent Icons 隨 Windows 11 出貨，在預設安裝的 Windows 10
/// 上並不存在，而該系統上的對應字型是 Segoe MDL2 Assets；WinAppSDK 支援 Windows 10 1809 以後的版本，
/// 而 MDL2 在每一個 Windows 10 中都有出貨。XAML 的 `FontFamily` 接受以逗號分隔的清單，並採用其中
/// 第一個存在的家族，因此同時指名兩者即可讓字符在任一系統上都畫得出來。否則，缺少圖示字型會使每一個
/// 符號都成為一個空白方框——那正是本功能所要防止的、同一種靜默空白的 Windows 版本。
extension WinUIBackend {
    public func createSymbolView() -> Widget {
        createTextView()
    }

    public func updateSymbolView(
        _ symbolView: Widget,
        symbol: SystemSymbol,
        environment: EnvironmentValues
    ) {
        Self.apply(symbol, to: symbolView as! TextBlock, environment: environment)
    }

    public func size(
        ofSymbol symbol: SystemSymbol,
        whenDisplayedIn widget: Widget,
        environment: EnvironmentValues
    ) -> SIMD2<Int> {
        // Through the same measurement block `size(of:...)` uses, so a symbol is
        // measured by the mechanism that measures text -- with the icon font
        // applied, since a glyph's advance width is nothing like the fallback
        // string's.
        // 透過 `size(of:...)` 所使用的同一個量測 block，如此符號便是由「量測文字的那套機制」量出來的
        // ——並且套用了圖示字型，因為一個字符的前進寬度與退路字串完全不同。
        Self.apply(symbol, to: measurementTextBlock, environment: environment)
        var size = Self.measure(
            measurementTextBlock,
            proposedWidth: nil,
            proposedHeight: nil
        )
        size.y = max(size.y, Int(environment.resolvedFont.lineHeight))
        return size
    }

    /// The families tried, in order, for a symbol's glyph.
    ///
    /// XAML resolves this left to right and uses the first one installed.
    /// 為符號字符所嘗試的字型家族，依序排列。XAML 由左至右解析，並採用其中第一個已安裝者。
    static let iconFontFamilies = "Segoe Fluent Icons, Segoe MDL2 Assets"

    private static func apply(
        _ symbol: SystemSymbol,
        to block: TextBlock,
        environment: EnvironmentValues
    ) {
        if symbol.segoeScalar == 0 {
            // No glyph was catalogued for this symbol -- SystemSymbol.unresolved
            // is the case that reaches here. Draw the fallback in the ordinary
            // font, and clear any icon family a previous update left behind.
            // 此符號沒有編目任何字符——會走到這裡的是 SystemSymbol.unresolved。以一般字型畫出退路，
            // 並清除先前某次更新可能遺留下來的圖示家族。
            block.text = symbol.textFallback
            try! block.clearValue(TextBlock.fontFamilyProperty)
        } else {
            block.text = symbol.segoeGlyph
            block.fontFamily = FontFamily(iconFontFamilies)
        }
        block.isTextSelectionEnabled = false
        environment.apply(to: block)
    }
}
