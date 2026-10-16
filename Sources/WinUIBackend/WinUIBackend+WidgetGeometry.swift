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
        // Canvas positions take effect at the next layout pass, so a transform
        // read straight after a commit would be the last layout's -- the stale
        // read AppKitBackend measured on P100 (2026-10-17). Run the pass first,
        // as `setChild(ofWindow:to:)` does with `updateLayout`.
        // Canvas 的位置在下一次排版時才生效，所以 commit 之後立刻讀到的 transform 會是上一次排版的
        // ——正是 AppKitBackend 在 P100 上量到的過期讀數(2026-10-17)。先跑排版，與 `setChild(ofWindow:to:)`
        // 以 `updateLayout` 所做的相同。
        try? root.updateLayout()
        guard let transform = try? widget.transformToVisual(root) else { return nil }
        // `transformPoint` throws TOO. The version that arrived had `try?` on
        // `transformToVisual` and none here, which is the whole of the build
        // break this file caused on the Windows side (2026-09-10):
        //
        //     WinUIBackend+WidgetGeometry.swift:29:22: error: call can throw,
        //     but it is not marked with 'try'
        //
        // Both calls are absorbed the same way and for the same reason: each
        // fails when the elements are not in one visual tree, and "not placed
        // yet" is what nil means here.
        //
        // `transformPoint` **也會** throws。送到的版本在 `transformToVisual` 上加了 `try?`、
        // 此處卻沒有,而那正是本檔在 Windows 端造成的建置中斷的全部內容(2026-09-10)。
        // 兩個呼叫以同樣的方式、基於同樣的理由被吸收:兩者都在「元素不在同一棵 visual tree 中」
        // 時失敗,而此處的 nil 表達的正是「尚未被放置」。
        guard let origin = try? transform.transformPoint(.init(x: 0, y: 0)) else {
            return nil
        }
        return SIMD2(Int(origin.x.rounded()), Int(origin.y.rounded()))
    }
}
