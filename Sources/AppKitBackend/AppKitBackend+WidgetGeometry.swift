import AppKit
import SwiftCrossUI

extension AppKitBackend: BackendFeatures.WidgetGeometry {
    /// Asks AppKit, and flips the y axis on the way out.
    ///
    /// **`convert(_:to: nil)` gives WINDOW coordinates**, which is what
    /// ``SwiftCrossUI/CoordinateSpace/global`` means -- `nil` is the window, not
    /// the screen, and the screen would need `convertToScreen` on top of it.
    ///
    /// **AppKit's window origin is bottom-left and every coordinate in this
    /// package is top-left**, so the y is subtracted from the content height
    /// rather than returned as AppKit gives it. Without that flip a view near
    /// the top of a 700pt window reports y = 690, and 690 is a plausible number
    /// -- it is what a view near the BOTTOM would have -- so the error would
    /// read as a layout bug in the caller rather than as an axis that was never
    /// converted.
    ///
    /// 去問 AppKit，並在回傳的路上把 y 軸翻過來。
    ///
    /// **`convert(_:to: nil)` 給的是**視窗**座標**，那正是 ``SwiftCrossUI/CoordinateSpace/global``
    /// 的意思——`nil` 指的是視窗、不是螢幕，而螢幕還要再套一層 `convertToScreen`。
    ///
    /// **AppKit 的視窗原點在左下，而本套件中每一個座標的原點都在左上**，因此此處的 y 是「內容高度
    /// 減去它」，而不是 AppKit 給什麼就回什麼。少了這次翻轉，一個位於 700 點高視窗頂端附近的 view
    /// 會回報 y = 690——而 690 是一個**說得通**的數字，它正是一個位於**底部**附近的 view 會有的值，
    /// 於是這個錯誤讀起來會像是呼叫端的版面 bug，而不像一個從未被轉換過的軸。
    public func originInWindow(ofWidget widget: Widget) -> SIMD2<Int>? {
        guard let window = widget.window else { return nil }
        let inWindow = widget.convert(NSPoint.zero, to: nil)
        // The top edge of the widget, which in AppKit's flipped-up world is the
        // corner with the LARGER y unless the view itself is flipped.
        // 該 widget 的上緣;在 AppKit「y 向上」的世界裡，除非該 view 自身是 flipped，否則那是 y
        // 較**大**的那個角。
        let topInWindow = widget.isFlipped
            ? inWindow.y
            : inWindow.y + widget.bounds.height
        let contentHeight = window.contentLayoutRect.height
        return SIMD2(
            Int(inWindow.x.rounded()),
            Int((contentHeight - topInWindow).rounded())
        )
    }
}
