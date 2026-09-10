import SwiftCrossUI
import WinUI

extension WinUIBackend: BackendFeatures.WidgetGeometry {
    /// Asks WinUI for the transform from this element to the window's root.
    ///
    /// `transformToVisual(_:)` is SYNCHRONOUS and `throws` -- confirmed by the
    /// Windows side on 2026-09-10, which is what let this be a synchronous
    /// requirement at all. `try?` absorbs the throw: it fails when the two
    /// elements are not in the same visual tree, and "not placed yet" is exactly
    /// what this returns `nil` for.
    ///
    /// **NOT COMPILED HERE (2026-09-10).** This machine cannot build
    /// WinUIBackend. What to check: that `Self.rootElement(of:)` or whatever
    /// this backend uses to reach the window's content is spelled as below --
    /// the shape is right, the name may not be.
    ///
    /// 向 WinUI 詢問「從這個元素到視窗 root」的變換。
    ///
    /// `transformToVisual(_:)` 是**同步**的，而且會 `throws`——2026-09-10 由 Windows 端確認，而那正是
    /// 這個 requirement 得以是同步的原因。`try?` 吸收掉那個 throw:它會在兩個元素不在同一棵 visual
    /// tree 中時失敗，而「尚未被放置」正是此處回傳 `nil` 所要表達的。
    ///
    /// **此處未編譯(2026-09-10)。** 這台機器建不了 WinUIBackend。要查的是:用來取得視窗內容的那個
    /// 東西是否如下方所寫——形狀是對的，名字未必。
    public func originInWindow(ofWidget widget: Widget) -> SIMD2<Int>? {
        guard let root = widget.xamlRoot?.content else { return nil }
        guard let transform = try? widget.transformToVisual(root) else { return nil }
        let origin = transform.transformPoint(.init(x: 0, y: 0))
        return SIMD2(Int(origin.x.rounded()), Int(origin.y.rounded()))
    }
}
