import ObjectiveC
import UIKit
@_spi(Backends) import SwiftCrossUI

/// Closing a window and stacking one above another.
///
/// Neither existed until 2026-09-30: `dismissWindow()` warned once and did
/// nothing, and `windowLevel(_:)` was substituted with `.normal` and logged.
///
/// 關閉一個視窗，以及把一個視窗疊在另一個之上。2026-09-30 之前兩者都不存在：`dismissWindow()`
/// 只會警告一次、什麼也不做，而 `windowLevel(_:)` 會被替換為 `.normal` 並記錄一筆。
extension UIKitBackend: BackendFeatures.WindowClosing {
    private static var closeHandlerKey: UInt8 = 0

    private final class CloseHandler {
        let action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
    }

    public func setCloseHandler(ofWindow window: Window, to action: @escaping () -> Void) {
        objc_setAssociatedObject(
            window,
            &Self.closeHandlerKey,
            CloseHandler(action),
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    /// Closes the window the way the platform closes one.
    ///
    /// - In an app that supports multiple scenes (iPad, Mac Catalyst), the
    ///   window's scene session is ended, which is how those platforms close a
    ///   window.
    /// - Otherwise, a window with others still showing (the extra `UIWindow`s
    ///   `createWindow` makes) is hidden.
    /// - The app's only window, in an app without multiple scenes, is left
    ///   open. There is no public way to close it: measured on the iOS 27
    ///   simulator 2026-09-30 (P75), `requestSceneSessionDestruction` answers
    ///   "Invalid attempt to call -[UIApplication
    ///   requestSceneSessionDestruction:] from an unsupported device." and the
    ///   window stays. An iPhone app's single window lasts as long as the app;
    ///   SwiftUI's own `dismissWindow` has no effect there either. The close
    ///   handler does not run in that case, because it tells the scene graph
    ///   to release a window that is still on screen.
    ///
    /// 以平台關閉視窗的方式關閉它。支援多個 scene 的 app（iPad、Mac Catalyst）會結束該視窗的
    /// scene session，那正是這些平台關閉視窗的方式。否則，若還有其他視窗顯示中（`createWindow`
    /// 產生的額外 `UIWindow`），就隱藏它。不支援多個 scene 的 app 的**唯一**視窗則保持開啟：沒有公開的
    /// 方法能關閉它——2026-09-30 於 iOS 27 simulator 實測（P75），`requestSceneSessionDestruction`
    /// 回應上述錯誤，視窗仍在。iPhone app 的單一視窗與 app 同壽；SwiftUI 自己的 `dismissWindow`
    /// 在那裡同樣沒有作用。此時不執行 close handler，因為它會讓 scene graph 釋放一個仍在畫面上的視窗。
    public func close(window: Window) {
        let handler = objc_getAssociatedObject(window, &Self.closeHandlerKey) as? CloseHandler
        let othersShowing = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .contains {
                !$0.isHidden && $0 !== window && $0.rootViewController is RootViewController }

        if UIApplication.shared.supportsMultipleScenes, let scene = window.windowScene {
            UIApplication.shared.requestSceneSessionDestruction(
                scene.session,
                options: nil
            ) { error in
                logger.error(
                    "could not end the window's scene session",
                    metadata: ["error": "\(error)"]
                )
            }
        } else if othersShowing {
            window.isHidden = true
        } else {
            logger.notice(
                """
                dismissWindow() left the app's only window open: this app does \
                not support multiple scenes, and UIKit has no public way to \
                close its last window
                """
            )
            return
        }
        objc_setAssociatedObject(
            window,
            &Self.closeHandlerKey,
            nil,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        handler?.action()
    }
}

extension UIKitBackend: BackendFeatures.WindowLevels {
    /// `.floating` is not listed, and that is the answer the protocol asks for
    /// rather than a gap. WindowLevel defines floating as above every window
    /// *including other applications'*, and a UIKit app draws only inside its
    /// own scenes: `UIWindow.windowLevel` orders windows within the app, never
    /// across apps. P37 on iOS shows the consequence -- the app switcher covers
    /// the window. A first version of this listed `.floating` and mapped it to
    /// `.normal + 1`; P37 then printed "floating is supported: this window
    /// should stay in front", which was false, so it was withdrawn the same day
    /// (2026-09-30).
    ///
    /// 不列出 `.floating`——那是協定所要求的回答，而不是缺口。WindowLevel 把 floating 定義為位於
    /// 所有視窗之上、**包括其他 app 的**，而 UIKit app 只在自己的 scene 內繪製：`UIWindow.windowLevel`
    /// 只在 app 內排序，從不跨 app。P37 在 iOS 上呈現了這一點——app 切換器會蓋住視窗。本段第一版曾列出
    /// `.floating` 並映射為 `.normal + 1`；P37 隨即印出「floating is supported: this window should stay
    /// in front」，那是假的，因此同日（2026-09-30）撤回。
    public nonisolated var supportedWindowLevels: [WindowLevel] {
        [.automatic, .normal]
    }

    public func setLevel(ofWindow window: Window, to level: WindowLevel) {
        window.windowLevel = .normal
    }
}
