import SwiftCrossUI
import UIKit

extension UIKitBackend: BackendFeatures.WidgetGeometry {
    /// Asks UIKit, with no axis to flip.
    ///
    /// UIKit's origin is already top-leading, so unlike the AppKit half this is
    /// the conversion and nothing else. `convert(_:to: nil)` is documented as
    /// converting to the WINDOW, which is what
    /// ``SwiftCrossUI/CoordinateSpace/global`` means here.
    ///
    /// The `window` check is not a formality: a view is laid out before it is
    /// in a window, and `convert(_:to: nil)` on a view with no window returns
    /// coordinates in the topmost superview instead -- a number, with no error,
    /// measured from somewhere else.
    ///
    /// 去問 UIKit，沒有任何軸需要翻轉。
    ///
    /// UIKit 的原點本來就在左上，因此與 AppKit 那一半不同，此處就只有轉換、沒有別的。
    /// `convert(_:to: nil)` 的文件寫明它轉換到**視窗**，那正是此處
    /// ``SwiftCrossUI/CoordinateSpace/global`` 的意思。
    ///
    /// 檢查 `window` 不是形式:一個 view 會在進入視窗之前先被排版，而對一個沒有視窗的 view 呼叫
    /// `convert(_:to: nil)`，回傳的是它最上層 superview 中的座標——一個數字、沒有錯誤、量自別的地方。
    public func originInWindow(ofWidget widget: Widget) -> SIMD2<Int>? {
        guard let view = widget.view, let window = view.window else { return nil }
        // Widgets are placed by Auto Layout constraints (`updateLeftConstraint`
        // and friends), and a frame reflects a constraint only after a layout
        // pass. Asked from `commit`, or from the main-queue retry that follows
        // it, the pass has not run yet -- main-queue blocks run before Core
        // Animation's commit in the same run-loop turn -- so the frame was
        // still (0, 0) and P63 on iOS read global x=0 y=0 with its marker at
        // about (49, 583) points (2026-09-30). Resolving the constraints here
        // is what makes the answer the position the view will be drawn at.
        //
        // widget 由 Auto Layout 約束放置(`updateLeftConstraint` 等),而 frame 要經過一次版面
        // 計算才會反映約束。從 `commit` 或其後的主佇列重試來問時,那一次計算還沒跑——同一輪 run loop
        // 中,主佇列的區塊先於 Core Animation 的 commit 執行——所以 frame 仍是 (0, 0),而 iOS 上的
        // P63 讀到 global x=0 y=0,標記卻約在 (49, 583) 點(2026-09-30)。在此解算約束,答案才會是
        // 這個 view 實際被畫出的位置。
        window.layoutIfNeeded()
        let inWindow = view.convert(CGPoint.zero, to: nil)
        return SIMD2(Int(inWindow.x.rounded()), Int(inWindow.y.rounded()))
    }
}
