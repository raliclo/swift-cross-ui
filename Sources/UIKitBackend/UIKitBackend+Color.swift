@_spi(Backends) import SwiftCrossUI
import UIKit

extension UIKitBackend {
    public func resolveAdaptiveColor(
        _ adaptiveColor: Color.SystemAdaptive,
        in environment: EnvironmentValues
    ) -> Color.Resolved {
        let uiColor: UIColor =
            switch adaptiveColor.kind {
                case .blue: .systemBlue
                case .brown: .systemBrown
                case .gray: .systemGray
                case .green: .systemGreen
                case .orange: .systemOrange
                case .purple: .systemPurple
                case .red: .systemRed
                case .yellow: .systemYellow
            }

        let traitCollection = UITraitCollection(
            userInterfaceStyle: environment.colorScheme.userInterfaceStyle
        )
        let resolvedColor = uiColor.resolvedColor(with: traitCollection)
        return Color.Resolved(resolvedColor)
    }
}

extension Color.Resolved {
    init(_ uiColor: UIColor) {
        let ciColor = CIColor(color: uiColor)

        self.init(
            red: Float(ciColor.red),
            green: Float(ciColor.green),
            blue: Float(ciColor.blue),
            opacity: Float(ciColor.alpha)
        )
    }

    var uiColor: UIColor {
        UIColor(
            red: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(opacity)
        )
    }

    /// The colour in sRGB, the space `uiColor` uses. `CGColor(red:green:blue:alpha:)`
    /// is Generic RGB: P95's one-colour gradient, drawn from these, read 216 99 81
    /// beside its 204 77 64 swatch on the iPhone 17 simulator (2026-10-16), with
    /// either a CGGradient or a CAGradientLayer.
    /// sRGB,與 `uiColor` 相同的色彩空間。`CGColor(red:green:blue:alpha:)` 是 Generic RGB:
    /// P95 以它畫的單色漸層在 iPhone 17 模擬器上讀到 216 99 81,旁邊的色塊是 204 77 64(2026-10-16),
    /// 不論用 CGGradient 或 CAGradientLayer 都一樣。
    var cgColor: CGColor {
        CGColor(
            srgbRed: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(opacity)
        )
    }
}
