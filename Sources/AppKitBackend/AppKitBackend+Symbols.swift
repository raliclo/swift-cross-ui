import AppKit
@_spi(Backends) import SwiftCrossUI

/// SF Symbols, drawn into the same `NSTextField` that draws text.
///
/// **One widget class for both outcomes, which is what makes the fallback
/// free.** A symbol either resolves to an `NSImage` or it does not, and the
/// second case has to look like text -- so rather than switch between an
/// `NSImageView` and a label at update time, both go into the attributed string
/// of the label that `createTextView()` already builds. Sizing, colour,
/// alignment and the line-height handling all come along unchanged, and the
/// backend has no second code path to keep in step with the first.
///
/// SF Symbols，畫進與文字同一個 `NSTextField` 之中。
///
/// **兩種結果共用一個 widget 類別，而那正是退路之所以「免費」的原因。** 一個符號要嘛解析成
/// `NSImage`、要嘛沒有，而後者必須看起來像文字——因此與其在更新時於 `NSImageView` 與 label 之間切換，
/// 不如讓兩者都進入 `createTextView()` 已經建好的那個 label 的 attributed string。尺寸、顏色、對齊
/// 與行高處理全部原封不動地一併沿用，而 backend 也不會多出第二條必須與第一條保持同步的程式路徑。
extension AppKitBackend {
    public func createSymbolView() -> Widget {
        createTextView()
    }

    public func updateSymbolView(
        _ symbolView: Widget,
        symbol: SystemSymbol,
        environment: EnvironmentValues
    ) {
        let field = symbolView as! NSTextField
        field.attributedStringValue = Self.attributedSymbol(symbol, in: environment)
        field.isSelectable = false
    }

    public func size(
        ofSymbol symbol: SystemSymbol,
        whenDisplayedIn widget: Widget,
        environment: EnvironmentValues
    ) -> SIMD2<Int> {
        // The image's own size, not a bounding-rect measurement of the
        // attachment. `NSTextAttachment` reports a bounds that depends on the
        // layout manager it has been put into, and this is asked before the
        // string reaches a field -- measuring it here gives a height that
        // disagrees with what is drawn a moment later.
        //
        // 使用該圖片自身的尺寸，而非對 attachment 做 bounding-rect 量測。`NSTextAttachment` 回報的
        // bounds 取決於它被放進哪一個 layout manager，而此處是在該字串抵達某個 field 之前被詢問的
        // ——在這裡量測會得到一個與稍後實際畫出來的結果不一致的高度。
        if let image = Self.symbolImage(symbol, in: environment) {
            return SIMD2(
                Int(image.size.width.rounded(.awayFromZero)),
                Int(image.size.height.rounded(.awayFromZero))
            )
        }
        return size(
            of: symbol.textFallback,
            whenDisplayedIn: widget,
            proposedWidth: nil,
            proposedHeight: nil,
            environment: environment
        )
    }

    static func attributedSymbol(
        _ symbol: SystemSymbol,
        in environment: EnvironmentValues
    ) -> NSAttributedString {
        guard let image = symbolImage(symbol, in: environment) else {
            return attributedString(for: symbol.textFallback, in: environment)
        }
        let attachment = NSTextAttachment()
        attachment.image = image
        return NSAttributedString(attachment: attachment)
    }

    /// The SF Symbol at the environment's font size and colour, or `nil` if this
    /// system does not have it.
    ///
    /// `nil` is a normal answer, not an error. `SystemSymbol/unresolved(_:)`
    /// carries an empty `sfSymbol` and lands here on purpose, and a name that is
    /// in the table can still be missing on an older macOS than the one it was
    /// catalogued from. Both take the fallback.
    ///
    /// 該 SF Symbol，套用 environment 的字級與顏色；若本系統沒有它則為 `nil`。
    ///
    /// `nil` 是一個正常的答案，不是錯誤。`SystemSymbol/unresolved(_:)` 帶著空的 `sfSymbol`，正是刻意
    /// 落到這裡；而一個確實在表中的名稱，在比其編目來源更舊的 macOS 上仍可能不存在。兩者都走退路。
    static func symbolImage(
        _ symbol: SystemSymbol,
        in environment: EnvironmentValues
    ) -> NSImage? {
        guard !symbol.sfSymbol.isEmpty else { return nil }
        guard
            let image = NSImage(
                systemSymbolName: symbol.sfSymbol,
                accessibilityDescription: symbol.name
            )
        else { return nil }

        let font = environment.resolvedFont
        let configured =
            image.withSymbolConfiguration(
                NSImage.SymbolConfiguration(
                    pointSize: CGFloat(font.pointSize),
                    weight: weight(for: font.weight)
                )
            ) ?? image

        return tinted(
            configured,
            with: AppKitBackend.resolvedForegroundColor(environment)
        )
    }

    /// Recolours a template image by drawing the colour through it.
    ///
    /// Not `NSImage.SymbolConfiguration(paletteColors:)`, which is the direct
    /// spelling and is macOS 12; this package's floor is macOS 11. Not
    /// `isTemplate` either -- that tints a symbol drawn by a control, and this
    /// one is drawn by a text attachment, which composites the image as-is and
    /// would leave every symbol black on a dark background.
    ///
    /// 以「把顏色透過該圖片畫出來」的方式為 template 圖片重新上色。
    ///
    /// 未使用 `NSImage.SymbolConfiguration(paletteColors:)`——那是最直接的寫法，但它需要 macOS 12，
    /// 而本套件的下限是 macOS 11。也未使用 `isTemplate`——它染的是「由控制項繪製」的符號，而此處這個
    /// 是由 text attachment 繪製的，後者會原樣合成該圖片，於是每一個符號在深色背景上都會是黑的。
    private static func tinted(_ image: NSImage, with color: NSColor) -> NSImage {
        let tintedImage = NSImage(size: image.size)
        tintedImage.lockFocus()
        defer { tintedImage.unlockFocus() }
        let bounds = NSRect(origin: .zero, size: image.size)
        image.draw(in: bounds)
        color.set()
        bounds.fill(using: .sourceIn)
        return tintedImage
    }
}
