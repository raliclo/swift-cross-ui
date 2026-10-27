@_spi(Backends) import SwiftCrossUI
import DebugFeatures
import WinUI

extension WinUIBackend {
    /// Scrolls a container so that one of its descendants is visible.
    ///
    /// `startBringIntoView(_:)` with a `BringIntoViewOptions` is the platform's
    /// own answer and it takes both cases: no anchor is plain "make it visible",
    /// and an anchor becomes a vertical/horizontal alignment ratio, which is the
    /// same thing SwiftUI's `UnitPoint` says.
    ///
    /// `animationDesired` is `false`, and its polarity is worth
    /// stating because the WinUI spelling elsewhere is inverted:
    /// `changeView(_:_:_:_:)`'s fourth argument is `disableAnimation`. Reading
    /// one and writing the other is how a scroll ends up animating exactly when
    /// it was asked not to.
    ///
    /// `startBringIntoView(_:)` throws in the Swift/WinRT bindings, so the call
    /// needs `try`; without it WinUIBackend does not compile (found
    /// 2026-09-09). A comment saying "unverified" had hidden that: it was read
    /// as "written but not exercised at runtime" when nothing had compiled the
    /// file.
    ///
    /// 捲動某個容器,使它的某個子孫可見。
    ///
    /// `startBringIntoView(_:)` 搭配 `BringIntoViewOptions` 是該平台自己的答案,而且它兩種情況都吃:
    /// 沒有 anchor 就是單純的「讓它可見」,而給定 anchor 則轉換為垂直/水平的對齊比例,那與 SwiftUI 的
    /// `UnitPoint` 說的是同一件事。
    ///
    /// `animationDesired` 設為 `false`,而它的極性值得寫出來,因為 WinUI 在別處的寫法是
    /// 反的:`changeView(_:_:_:_:)` 的第四個引數是 `disableAnimation`。讀其中一個、寫另一個,正是
    /// 一次捲動「恰好在被要求不要動畫時動畫起來」的成因。
    ///
    /// `startBringIntoView(_:)` 在 Swift/WinRT 綁定中會 throw,因此呼叫需要 `try`;少了它 WinUIBackend 根本
    /// 無法編譯(2026-09-09 發現)。先前一句「未經驗證」掩蓋了這件事：它被讀成「已寫出但尚未在執行期演練」,
    /// 而事實上根本沒有東西編譯過這個檔案。
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
        // NOT `try?`. A programmatic scroll that silently fails to happen and a
        // scroll that worked are the same picture, and telling those two apart
        // is the whole reason ScrollViewReader got a log line on the GTK side.
        // `try!` is wrong the other way -- it takes the app down for a scroll.
        // So: catch, carry on, and say so.
        //
        // The diagnostic needs `DebugFeatures`, as GtkBackend's does (task #48,
        // "diagnostics reach UIKit and WinUI"). Other files in this backend
        // still have bare `try?` calls, for example Alerts, AngularGradient and
        // ButtonPressState.
        //
        // **不是 `try?`。** 一次「靜默地沒有發生」的程式化捲動，與一次成功的捲動，在畫面上是同一張圖；
        // 而分辨這兩者，正是 ScrollViewReader 在 GTK 那一側被加上一行 log 的全部理由。`try!` 則錯在
        // 另一個方向——它會為了一次捲動而拖垮整個 app。因此：捕捉、繼續執行、並且說出來。
        //
        // 這個診斷需要 `DebugFeatures`,與 GtkBackend 相同(任務 #48,「診斷要送進 UIKit 與 WinUI」)。本 backend
        // 其他檔案仍有裸露的 `try?`,例如 Alerts、AngularGradient 與 ButtonPressState。
        do {
            try child.startBringIntoView(options)
        } catch {
            DebugFeatures.log(
                "WinUIBackend.scrollContainer: startBringIntoView failed -- \(error). "
                    + "The view did NOT scroll; do not read the unchanged picture as a no-op."
            )
        }
    }
}
