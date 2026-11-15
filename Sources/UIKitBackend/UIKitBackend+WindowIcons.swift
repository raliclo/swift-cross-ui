import Foundation
import UIKit
@_spi(Backends) import SwiftCrossUI

/// `windowIcon(_:)` on iOS: an alternate app icon declared at build time.
///
/// An iOS window has no icon, and the app's home-screen icon can be switched only
/// to icons the bundle declares under CFBundleIcons > CFBundleAlternateIcons. A PNG
/// chosen at run time cannot be one: on the simulator setAlternateIconName with no
/// declared icons returned NSCocoaErrorDomain 3328 ("the feature is not supported")
/// and supportsAlternateIcons was false, and a device's signed bundle is read-only
/// (2026-11-15). So a URL maps to the declared alternate icon of the same file name,
/// which testapp/test_support/ios_alternate_icons.zsh declares from
/// testapp/icons/<app>/*.png; nil returns to the primary icon. iOS confirms each
/// change with its own alert.
///
/// iOS 上的 `windowIcon(_:)`:建置時宣告的替代 App 圖示。iOS 的視窗沒有圖示，主畫面上的 App 圖示也只能切換到 bundle 在
/// CFBundleIcons > CFBundleAlternateIcons 下宣告過的圖示。執行期才選定的 PNG 不可能是其中之一：模擬器上沒有宣告任何
/// 圖示時,setAlternateIconName 回傳 NSCocoaErrorDomain 3328(「不支援此功能」)、supportsAlternateIcons 為 false,
/// 而真機上簽過章的 bundle 是唯讀的(2026-11-15)。所以 URL 對應到同檔名、已宣告的替代圖示(由
/// testapp/test_support/ios_alternate_icons.zsh 依 testapp/icons/<app>/*.png 宣告);nil 回到主圖示。
/// iOS 會以它自己的提示確認每一次變更。
extension UIKitBackend: BackendFeatures.WindowIcons {
    public func setIcon(ofWindow window: Window, to icon: URL?) {
        let application = UIApplication.shared
        let name = icon?.deletingPathExtension().lastPathComponent
        if let name, !Self.declaredAlternateIcons.contains(name) {
            logger.warning(
                """
                windowIcon: \(name) is not an alternate icon this app declares, so iOS cannot \
                show it (declared: \(Self.declaredAlternateIcons.sorted().joined(separator: ", ")))
                """
            )
            return
        }
        guard application.supportsAlternateIcons else { return }
        // Only while the app is active: asked during launch, before the first scene is
        // in front, iOS cancels the change (NSCocoaErrorDomain 3072, P118 2026-11-15).
        // The last request waits for didBecomeActive instead.
        // 只在 app 為 active 時設定：在啟動途中、第一個 scene 還沒到前景時要求，iOS 會取消這次變更
        // (NSCocoaErrorDomain 3072,P118 2026-11-15)。改為讓最後一次的要求等到 didBecomeActive。
        guard application.applicationState == .active else {
            Self.pendingAlternateIcon = .some(name)
            if Self.activeObserver == nil {
                Self.activeObserver = NotificationCenter.default.addObserver(
                    forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
                ) { _ in
                    MainActor.assumeIsolated {
                        guard case .some(let pending) = UIKitBackend.pendingAlternateIcon else { return }
                        UIKitBackend.pendingAlternateIcon = nil
                        UIKitBackend.applyAlternateIcon(pending)
                    }
                }
            }
            return
        }
        Self.pendingAlternateIcon = nil
        Self.applyAlternateIcon(name)
    }

    /// The icon waiting for the app to become active; `.some(nil)` is the primary one.
    /// 等 app 變成 active 的圖示；`.some(nil)` 是主圖示。
    nonisolated(unsafe) static var pendingAlternateIcon: String??
    nonisolated(unsafe) static var activeObserver: NSObjectProtocol?

    /// The icon last asked of iOS, `.none` until the first request; a change iOS is
    /// still making; the request that waits for it.
    /// 最後向 iOS 要求的圖示(第一次要求前為 `.none`);iOS 仍在進行的變更；等它完成的那個要求。
    nonisolated(unsafe) static var requestedAlternateIcon: String??
    nonisolated(unsafe) static var changeInFlight = false
    nonisolated(unsafe) static var queuedAlternateIcon: String??

    /// One change at a time, and `alternateIconName` read only when none is in flight.
    /// While iOS waits for the user to confirm a change, reading it blocks the main
    /// thread until they do: P118 hung in -[LSApplicationRecord alternateIconName]
    /// (sample, 2026-11-15), and XCUITest then could not snapshot the app. A request
    /// made during a change waits and goes when the change completes; only the last
    /// one is kept.
    /// 一次只做一個變更，而且只在沒有變更進行中時才讀 `alternateIconName`。iOS 等使用者確認變更的期間，讀它會讓主執行緒
    /// 一直等到使用者確認為止:P118 卡在 -[LSApplicationRecord alternateIconName](sample,2026-11-15),XCUITest
    /// 也因此無法擷取 app 的快照。變更期間的要求會等到變更完成才送出；只保留最後一個。
    static func applyAlternateIcon(_ name: String?) {
        if changeInFlight {
            queuedAlternateIcon = .some(name)
            return
        }
        let application = UIApplication.shared
        if requestedAlternateIcon == nil {
            requestedAlternateIcon = .some(application.alternateIconName)
        }
        guard requestedAlternateIcon != .some(name) else { return }
        requestedAlternateIcon = .some(name)
        changeInFlight = true
        application.setAlternateIconName(name) { error in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    changeInFlight = false
                    if let error {
                        requestedAlternateIcon = nil
                        logger.warning("windowIcon: setAlternateIconName(\(name ?? "nil")) failed: \(error)")
                    }
                    if case .some(let next) = queuedAlternateIcon {
                        queuedAlternateIcon = nil
                        applyAlternateIcon(next)
                    }
                }
            }
        }
    }

    /// The alternate icon names the bundle declares. / bundle 宣告的替代圖示名稱。
    static var declaredAlternateIcons: Set<String> {
        let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any]
        let alternates = icons?["CFBundleAlternateIcons"] as? [String: Any]
        return Set(alternates.map { Array($0.keys) } ?? [])
    }
}
