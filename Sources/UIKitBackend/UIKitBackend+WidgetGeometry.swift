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
        guard let view = widget.view, view.window != nil else { return nil }
        let inWindow = view.convert(CGPoint.zero, to: nil)
        return SIMD2(Int(inWindow.x.rounded()), Int(inWindow.y.rounded()))
    }
}
