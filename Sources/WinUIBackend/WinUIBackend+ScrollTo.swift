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
    /// `animationDesired` is set from the flag being FALSE, which is worth
    /// stating because the WinUI spelling elsewhere is inverted:
    /// `changeView(_:_:_:_:)`'s fourth argument is `disableAnimation`. Reading
    /// one and writing the other is how a scroll ends up animating exactly when
    /// it was asked not to.
    ///
    /// ~~**UNVERIFIED.** WinUIBackend builds and runs on the Windows machine.~~
    /// **IT DID NOT BUILD.** `startBringIntoView(_:)` throws in the Swift/WinRT
    /// bindings, and the call here was written without `try`, so WinUIBackend
    /// -- one of the five shipped backends -- would not compile at all. Found
    /// 2026-09-09 on the Windows machine, the first time anything tried to
    /// build this file, by a `swift build` for an unrelated change.
    ///
    /// The comment above is why it went unnoticed: "unverified" was read as
    /// "written but not exercised at runtime", when in fact nothing had
    /// established it was even syntactically complete. **Compiling is the
    /// cheapest half of verification and it had not been done**, on a file
    /// whose own header says which machine can do it.
    ///
    /// ~~**未經驗證。** WinUIBackend 是在 Windows 機器上建置與執行的。~~
    /// **它根本建不起來。** `startBringIntoView(_:)` 在 Swift/WinRT 綁定中會 throw，而此處的呼叫
    /// 未加 `try`，因此 WinUIBackend——五個已發布 backend 之一——完全無法編譯。2026-09-09 在
    /// Windows 機器上發現，那是第一次有東西嘗試建置此檔，起因是一次為了無關改動而執行的
    /// `swift build`。
    ///
    /// 上面那句註解正是它沒被注意到的原因：「未經驗證」被讀成了「已寫出但尚未在執行期演練」，
    /// 而事實是**根本沒有任何東西確認過它在語法上是完整的**。**編譯是驗證中最便宜的那一半，而它
    /// 沒有被做過**——在一個自己的標頭就寫明「哪台機器做得到」的檔案上。
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
        // NOT `try?`. A programmatic scroll that silently fails to happen and a
        // scroll that worked are the same picture, and telling those two apart
        // is the whole reason ScrollViewReader got a log line on the GTK side.
        // `try!` is wrong the other way -- it takes the app down for a scroll.
        // So: catch, carry on, and say so.
        //
        // The diagnostic needs `DebugFeatures`, which WinUIBackend did not
        // depend on until now. GtkBackend already did. That is task #48
        // ("diagnostics reach UIKit and WinUI") advancing by one file rather
        // than being done -- the rest of this backend still has bare `try?`
        // calls, in Alerts, AngularGradient, Button and ButtonPressState.
        //
        // **不是 `try?`。** 一次「靜默地沒有發生」的程式化捲動，與一次成功的捲動，在畫面上是同一張圖；
        // 而分辨這兩者，正是 ScrollViewReader 在 GTK 那一側被加上一行 log 的全部理由。`try!` 則錯在
        // 另一個方向——它會為了一次捲動而拖垮整個 app。因此：捕捉、繼續執行、並且說出來。
        //
        // 這個診斷需要 `DebugFeatures`，而 WinUIBackend 在此之前並未依賴它，GtkBackend 則早已依賴。
        // 這是任務 #48（「診斷要送進 UIKit 與 WinUI」）**前進了一個檔案**，而不是完成——本 backend
        // 其餘各處仍有裸露的 `try?`，散布於 Alerts、AngularGradient、Button 與 ButtonPressState。
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
