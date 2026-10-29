import AppKit
@_spi(Backends) import SwiftCrossUI

/// `BackendFeatures.BackNavigation` and `SheetBackNavigation` on macOS:
/// Command-[, the mouse's back button and the trackpad's "Swipe between
/// pages", taken by the window itself (`NSCustomWindow.backNavigationHandler`
/// in AppKitBackend.swift has the details). A sheet is an `NSCustomSheet`, a
/// window of its own, so it takes Back the same way with its own handler,
/// and its parent ignores Back while the sheet is attached. Bare extensions:
/// the conformances come from `FullAppBackend`.
///
/// macOS 上的 `BackendFeatures.BackNavigation` 與 `SheetBackNavigation`:Command-[、滑鼠返回鍵與觸控板的「在頁面之間滑動」,
/// 由視窗本身接下(細節見 AppKitBackend.swift 的 `NSCustomWindow.backNavigationHandler`)。sheet 是 `NSCustomSheet`,本身就是
/// 視窗，因此以同樣方式、用它自己的 handler 接下返回；sheet 掛著時，它的父視窗忽略返回。不帶 conformance 的 extension:
/// conformance 來自 `FullAppBackend`。
extension AppKitBackend {
    public func setBackNavigationHandler(
        ofWindow window: Window,
        to action: (@MainActor () -> Bool)?
    ) {
        window.backNavigationHandler = action
    }

    public func setBackNavigationHandler(
        ofSheet sheet: Sheet,
        to action: (@MainActor () -> Bool)?
    ) {
        sheet.backNavigationHandler = action
    }
}
