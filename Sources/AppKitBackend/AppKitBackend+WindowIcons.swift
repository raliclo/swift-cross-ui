import AppKit
import Foundation
@_spi(Backends) import SwiftCrossUI

/// `windowIcon(_:)` on AppKit: the application's icon in the Dock and the app switcher.
///
/// A macOS window has no icon of its own. Its title bar shows a document proxy icon
/// only for a represented file, and the icon a user sees for a running app is the
/// Dock tile, which `NSApplication.applicationIconImage` sets at run time for a
/// bundled or unbundled app alike; nil restores the bundle's icon. So the icon is
/// per application, not per window: with several windows, the last one set wins.
///
/// AppKit 上的 `windowIcon(_:)`:App 在 Dock 與 App 切換器中的圖示。macOS 的視窗沒有自己的圖示：標題列只有代表檔案時才顯示
/// 文件代理圖示，使用者看到的執行中 App 的圖示是 Dock 圖塊，而 `NSApplication.applicationIconImage` 可在執行期設定它，
/// 打包與否皆可;nil 會恢復 bundle 的圖示。所以圖示是以 App 為單位、不是以視窗為單位：有多個視窗時，最後設定的那一個為準。
extension AppKitBackend: BackendFeatures.WindowIcons {
    public func setIcon(ofWindow window: Window, to icon: URL?) {
        guard let icon else {
            NSApplication.shared.applicationIconImage = nil
            return
        }
        guard let image = NSImage(contentsOf: icon), image.isValid else {
            // Said, not fatal: the app keeps the icon it had.
            // 只說明、不中止:App 保留原本的圖示。
            logger.warning("windowIcon: \(icon.lastPathComponent) is not an image AppKit can read")
            return
        }
        NSApplication.shared.applicationIconImage = image
    }
}
