import AppKit
@_spi(Backends) import SwiftCrossUI

extension AppKitBackend {
    // NB: We deliberately use the default implementation of `resolveAdaptiveColor(_:in:)`,
    // since that uses the adaptive colors from AppKit/UIKit.
}

extension Color.Resolved {
    var nsColor: NSColor {
        // sRGB, as SwiftUI's `Color(red:green:blue:)` and UIKitBackend's `UIColor(red:)`
        // are. Until 2026-10-14 this was `calibratedRed`, i.e. Generic RGB: P95's swatch
        // (0.4, 0.9, 1) read 117 234 255 and (0.8, 0.3, 0.25) read 215 99 81 in sRGB,
        // while the same values drawn through the mesh view's Metal path read 102 230
        // 255 and 204 76 64 (queue item 16).
        // sRGB,與 SwiftUI 的 `Color(red:green:blue:)`、UIKitBackend 的 `UIColor(red:)` 相同。2026-10-14 之前這裡是
        // `calibratedRed`,也就是 Generic RGB:P95 的色塊 (0.4, 0.9, 1) 在 sRGB 中讀到 117 234 255、(0.8, 0.3, 0.25)
        // 讀到 215 99 81,而同樣的值經 mesh view 的 Metal 路徑畫出是 102 230 255 與 204 76 64(queue 第 16 項)。
        NSColor(
            srgbRed: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(opacity)
        )
    }
}
