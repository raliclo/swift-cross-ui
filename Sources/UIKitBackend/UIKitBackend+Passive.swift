@_spi(Backends) import SwiftCrossUI
import UIKit

extension UIKitBackend {
    static func attributedString(
        text: String,
        environment: EnvironmentValues,
        defaultForegroundColor: UIColor = .label
    ) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment =
            switch environment.multilineTextAlignment {
                case .center:
                    .center
                case .leading:
                    .natural
                case .trailing:
                    UITraitCollection.current.layoutDirection == .rightToLeft ? .left : .right
            }
        paragraphStyle.lineBreakMode = .byWordWrapping

        // This is definitely what these properties were intended for
        let resolvedFont = environment.resolvedFont
        paragraphStyle.minimumLineHeight = CGFloat(resolvedFont.lineHeight)
        paragraphStyle.maximumLineHeight = CGFloat(resolvedFont.lineHeight)
        paragraphStyle.lineSpacing = 0

        return NSAttributedString(
            string: text,
            attributes: [
                .font: resolvedFont.uiFont,
                .foregroundColor: environment.foregroundColor?
                    .resolve(in: environment).uiColor ?? defaultForegroundColor,
                .paragraphStyle: paragraphStyle,
            ]
        )
    }

    public func createTextView() -> Widget {
        WrapperWidget<TextView>()
    }

    public func updateTextView(
        _ textView: Widget,
        content: String,
        environment: EnvironmentValues
    ) {
        let wrapper = textView as! WrapperWidget<TextView>
        wrapper.child.overrideUserInterfaceStyle = environment.colorScheme.userInterfaceStyle
        wrapper.child.attributedText = UIKitBackend.attributedString(
            text: content,
            environment: environment
        )
        wrapper.child.isSelectable = environment.isTextSelectionEnabled
    }

    public func size(
        of text: String,
        whenDisplayedIn widget: Widget,
        proposedWidth: Int?,
        proposedHeight: Int?,
        environment: EnvironmentValues
    ) -> SIMD2<Int> {
        let attributedString = UIKitBackend.attributedString(text: text, environment: environment)
        let size = attributedString.boundingRect(
            with: CGSize(
                width: proposedWidth.map(Double.init) ?? .greatestFiniteMagnitude,
                height: proposedHeight.map(Double.init) ?? .greatestFiniteMagnitude
            ),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            context: nil
        )

        var height = size.height

        if let lineLimitSettings = environment.lineLimitSettings {
            let limitedHeight =
                Double(max(lineLimitSettings.limit, 1)) * environment.resolvedFont.lineHeight

            if limitedHeight < height || lineLimitSettings.reservesSpace {
                height = limitedHeight
            }
        }

        return SIMD2(
            Int(size.width.rounded(.awayFromZero)),
            Int(height.rounded(.awayFromZero))
        )
    }

    public func createImageView() -> Widget {
        WrapperWidget<UIImageView>()
    }

    public func updateImageView(
        _ imageView: Widget,
        rgbaData: [UInt8],
        width: Int,
        height: Int,
        targetWidth: Int,
        targetHeight: Int,
        dataHasChanged: Bool,
        environment: EnvironmentValues
    ) {
        guard dataHasChanged else { return }
        let wrapper = imageView as! WrapperWidget<UIImageView>
        let ciImage = CIImage(
            bitmapData: Data(rgbaData),
            bytesPerRow: width * 4,
            size: CGSize(width: CGFloat(width), height: CGFloat(height)),
            format: .RGBA8,
            colorSpace: .init(name: CGColorSpace.sRGB)
        )
        wrapper.child.image = .init(ciImage: ciImage)
    }
}

extension UIKitBackend {
    public final class TextView: UIView {
        public var isSelectable: Bool = false

        public var attributedText: NSAttributedString {
            get {
                textStorage
            }
            set {
                textStorage.setAttributedString(newValue)
                setNeedsDisplay()
            }
        }

        public var text: String {
            attributedText.string
        }

        public var layoutManager: NSLayoutManager
        public var textStorage: NSTextStorage
        public var textContainer: NSTextContainer

        public override init(frame: CGRect) {
            layoutManager = NSLayoutManager()

            textStorage = NSTextStorage(attributedString: NSAttributedString(string: ""))
            textStorage.addLayoutManager(layoutManager)

            textContainer = NSTextContainer(size: frame.size)
            textContainer.lineBreakMode = .byTruncatingTail
            textContainer.lineFragmentPadding = 0
            layoutManager.addTextContainer(textContainer)

            super.init(frame: frame)

            isOpaque = false

            // Inspired by https://medium.com/kinandcartacreated/making-uilabel-accessible-5f3d5c342df4
            // Thank you to Sam Dods for the base idea
            #if !os(tvOS)
                let longPress = UILongPressGestureRecognizer(
                    target: self,
                    action: #selector(didLongPress)
                )
                addGestureRecognizer(longPress)
                isUserInteractionEnabled = true
            #endif
        }

        public required init?(coder aDecoder: NSCoder) {
            fatalError("init?(coder:) not implemented")
        }

        public override var canBecomeFirstResponder: Bool {
            isSelectable
        }

        public override func layoutSubviews() {
            super.layoutSubviews()
            if textContainer.size != bounds.size {
                textContainer.size = bounds.size
                setNeedsDisplay()
            }
        }

        public override func draw(_ rect: CGRect) {
            let range = layoutManager.glyphRange(for: textContainer)
            layoutManager.drawBackground(forGlyphRange: range, at: bounds.origin)
            layoutManager.drawGlyphs(forGlyphRange: range, at: bounds.origin)
        }

        @objc private func didLongPress(_ gesture: UILongPressGestureRecognizer) {
            #if !os(tvOS)
                guard
                    isSelectable,
                    gesture.state == .began,
                    !text.isEmpty
                else {
                    return
                }
                window?.endEditing(true)
                guard becomeFirstResponder() else { return }

                let menu = UIMenuController.shared
                if !menu.isMenuVisible {
                    menu.showMenu(from: self, rect: bounds)
                }
            #endif
        }

        public override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
            return action == #selector(copy(_:))
        }

        private func cancelSelection() {
            #if !os(tvOS)
                let menu = UIMenuController.shared
                menu.hideMenu(from: self)
            #endif
        }

        @objc public override func copy(_ sender: Any?) {
            #if !os(tvOS)
                cancelSelection()
                let board = UIPasteboard.general
                board.string = text
            #endif
        }
    }
}

extension UIKitBackend {
    /// The colour to paint with: what the application asked for, or the
    /// platform's own label colour when it asked for nothing.
    ///
    /// The same rule `attributedString(text:environment:defaultForegroundColor:)`
    /// already followed, extracted so the sites that were NOT following it can.
    /// `environment.suggestedForegroundColor` is never `nil`, so obeying it
    /// unconditionally paints plain black or white whenever the application
    /// chose nothing, and `UIColor.label`'s secondary, disabled and
    /// increased-contrast variants are lost with it.
    ///
    /// 要拿來繪製的顏色:應用程式所要求的顏色,或在它什麼都沒要求時,該平台自己的 label 色。
    ///
    /// 這正是 `attributedString(text:environment:defaultForegroundColor:)` 已經在遵守的規則,把它抽出來,
    /// 好讓那些**沒有**在遵守的地方也能用。`environment.suggestedForegroundColor` 永遠不會是 `nil`,
    /// 因此無條件照用它,會在應用程式什麼都沒選時畫成純黑或純白,而 `UIColor.label` 的次要、停用與
    /// 「提高對比」等變體也一併失去。
    static func resolvedForegroundColor(
        _ environment: EnvironmentValues,
        default defaultColor: UIColor = .label
    ) -> UIColor {
        if let chosen = environment.foregroundColor {
            return chosen.resolve(in: environment).uiColor
        }
        // UIKit has no `UIColor.disabled`, so the alpha is the framework's own
        // disabled opacity rather than a platform constant -- 0.3, the value
        // `Buttons.swift` already uses for a disabled bordered label, so a
        // disabled text field and a disabled button agree.
        //
        // Only the default path is dimmed: an application that chose a colour
        // keeps it. Filling in a missing value and overriding a chosen one are
        // different decisions.
        //
        // UIKit 沒有 `UIColor.disabled`,因此這個 alpha 是本框架自己的停用透明度,而不是某個平台常數
        // ——0.3,那正是 `Buttons.swift` 已經用在停用的 bordered 標籤上的值,如此一來「停用的文字欄位」
        // 與「停用的按鈕」才會一致。
        //
        // 只調暗預設路徑:選了顏色的應用程式會保留它。「補上缺失的值」與「覆寫已選的值」是兩個不同的決定。
        return environment.isEnabled ? defaultColor : defaultColor.withAlphaComponent(0.3)
    }
}
