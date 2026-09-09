@_spi(Backends) import SwiftCrossUI
import WinUI

extension WinUIBackend {
    /// Scrolls a container so that one of its descendants is visible.
    ///
    /// `startBringIntoView(_:)` with a `BringIntoViewOptions` is the platform's
    /// own answer and it takes both cases: no anchor is plain "make it visible",
    /// and an anchor becomes a vertical/horizontal alignment ratio, which is the
    /// same thing SwiftUI's `UnitPoint` says.
    ///
    /// `animationDesired` is set from the flag being FALSE, which is worth
    /// stating because the WinUI spelling elsewhere is inverted:
    /// `changeView(_:_:_:_:)`'s fourth argument is `disableAnimation`. Reading
    /// one and writing the other is how a scroll ends up animating exactly when
    /// it was asked not to.
    ///
    /// **UNVERIFIED.** WinUIBackend builds and runs on the Windows machine.
    ///
    /// 捲動某個容器,使它的某個子孫可見。
    ///
    /// `startBringIntoView(_:)` 搭配 `BringIntoViewOptions` 是該平台自己的答案,而且它兩種情況都吃:
    /// 沒有 anchor 就是單純的「讓它可見」,而給定 anchor 則轉換為垂直/水平的對齊比例,那與 SwiftUI 的
    /// `UnitPoint` 說的是同一件事。
    ///
    /// `animationDesired` 是由那個旗標的**否定**設定的,而這值得寫出來,因為 WinUI 在別處的寫法是
    /// 反的:`changeView(_:_:_:_:)` 的第四個引數是 `disableAnimation`。讀其中一個、寫另一個,正是
    /// 一次捲動「恰好在被要求不要動畫時動畫起來」的成因。
    ///
    /// **未經驗證。** WinUIBackend 是在 Windows 機器上建置與執行的。
    public func scrollContainer(
        _ scrollView: Widget,
        to child: Widget,
        anchor: UnitPoint?
    ) {
        let options = BringIntoViewOptions()
        options.animationDesired = false
        if let anchor {
            options.horizontalAlignmentRatio = Double(anchor.x)
            options.verticalAlignmentRatio = Double(anchor.y)
        }
        child.startBringIntoView(options)
    }
}
