@_spi(Backends) import SwiftCrossUI
import UIKit

/// SF Symbols, drawn into the same `TextView` that draws text.
///
/// The same shape as `AppKitBackend+Symbols.swift`, for the same reason: a
/// symbol either resolves to an image or it has to look like text, and putting
/// both into the attributed string of the view `createTextView()` already
/// builds means sizing, colour, alignment and line-height are inherited rather
/// than reimplemented. The two files differ only where the frameworks do.
///
/// SF Symbols，畫進與文字同一個 `TextView` 之中。
///
/// 與 `AppKitBackend+Symbols.swift` 形狀相同，理由也相同：一個符號要嘛解析成圖片、要嘛必須看起來
/// 像文字，而讓兩者都進入 `createTextView()` 已經建好的那個 view 的 attributed string，意味著尺寸、
/// 顏色、對齊與行高是被繼承下來的，而不是重新實作一遍。這兩個檔案只在兩套框架本身有差異之處不同。
extension UIKitBackend {
    public func createSymbolView() -> Widget {
        createTextView()
    }

    public func updateSymbolView(
        _ symbolView: Widget,
        symbol: SystemSymbol,
        environment: EnvironmentValues
    ) {
        let wrapper = symbolView as! WrapperWidget<TextView>
        wrapper.child.overrideUserInterfaceStyle = environment.colorScheme.userInterfaceStyle
        wrapper.child.attributedText = Self.attributedSymbol(symbol, environment: environment)
        wrapper.child.isSelectable = false
    }

    public func size(
        ofSymbol symbol: SystemSymbol,
        whenDisplayedIn widget: Widget,
        environment: EnvironmentValues
    ) -> SIMD2<Int> {
        // The image's own size rather than a bounding-rect measurement of the
        // attachment, for the reason given in the AppKit file: an attachment's
        // bounds depend on the layout manager it is placed in, and this is
        // asked before the string reaches one.
        //
        // 使用圖片自身的尺寸，而非對 attachment 做 bounding-rect 量測，理由見 AppKit 那個檔案：
        // attachment 的 bounds 取決於它被放進哪一個 layout manager，而此處是在該字串抵達某個
        // layout manager 之前被詢問的。
        if let image = Self.symbolImage(symbol, environment: environment) {
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
        environment: EnvironmentValues
    ) -> NSAttributedString {
        guard let image = symbolImage(symbol, environment: environment) else {
            return attributedString(text: symbol.textFallback, environment: environment)
        }
        let attachment = NSTextAttachment()
        attachment.image = image
        return NSAttributedString(attachment: attachment)
    }

    /// The SF Symbol at the environment's font size and colour, or `nil` if this
    /// system does not have it.
    ///
    /// `nil` is a normal answer: ``SystemSymbol/unresolved(_:)`` carries an
    /// empty `sfSymbol` and lands here on purpose, and a catalogued name can
    /// still be missing on an iOS older than the one it was catalogued from.
    ///
    /// 該 SF Symbol，套用 environment 的字級與顏色；若本系統沒有它則為 `nil`。
    ///
    /// `nil` 是一個正常的答案：``SystemSymbol/unresolved(_:)`` 帶著空的 `sfSymbol`，正是刻意落到
    /// 這裡；而一個已編目的名稱，在比其編目來源更舊的 iOS 上仍可能不存在。
    static func symbolImage(
        _ symbol: SystemSymbol,
        environment: EnvironmentValues
    ) -> UIImage? {
        guard !symbol.sfSymbol.isEmpty else { return nil }
        let resolvedFont = environment.resolvedFont
        guard
            let image = UIImage(
                systemName: symbol.sfSymbol,
                withConfiguration: UIImage.SymbolConfiguration(
                    pointSize: resolvedFont.pointSize
                )
            )
        else { return nil }

        // `withTintColor` rather than a composite draw. UIKit has had it since
        // iOS 13, which is this package's floor, so the AppKit file's reason for
        // colouring by hand does not apply here.
        // 使用 `withTintColor` 而非合成繪製。UIKit 自 iOS 13 起即具備它，而那正是本套件的下限，
        // 因此 AppKit 那個檔案中「手動上色」的理由在此並不適用。
        let color =
            environment.foregroundColor?.resolve(in: environment).uiColor ?? .label
        return image.withTintColor(color, renderingMode: .alwaysOriginal)
    }
}
