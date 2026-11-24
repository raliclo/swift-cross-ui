extension BackendFeatures {
    /// Backend methods for limiting where a widget can be hit to a shape.
    ///
    /// These are used by ``View/contentShape(_:eoFill:)``.
    ///
    /// 把 widget 可被點中的範圍限制在一個形狀之內的 backend 方法。供
    /// ``View/contentShape(_:eoFill:)`` 使用。
    @MainActor
    public protocol ContentShapes: Core {
        /// Limits where a widget and everything inside it can be hit.
        ///
        /// A pointer press, click or touch at a point of the widget's frame
        /// outside `region` must behave as if the widget were not there: it
        /// goes on to whatever is underneath, a sibling drawn below or the
        /// parent. Inside `region` the widget is hit as it would be without a
        /// shape. `nil` removes the limit.
        ///
        /// `region` is in the widget's own coordinates: origin at its top-left
        /// corner, y down, in the same units as ``Core/setSize(of:to:)``. It
        /// is called again after every commit of the view, with the region
        /// rebuilt for the size the widget was given.
        ///
        /// 限制一個 widget 及其內部一切可被點中的範圍。
        ///
        /// 在 widget 的 frame 之內、但位於 `region` 之外的一點上的按壓、點擊或觸控，必須表現得
        /// 如同該 widget 不存在：它繼續前往下方的東西——畫在下面的兄弟元件或父元件。在 `region`
        /// 之內，widget 的命中方式與沒有形狀時相同。`nil` 移除該限制。
        ///
        /// `region` 位於 widget 自身的座標系：原點在其左上角、y 向下，單位與
        /// ``Core/setSize(of:to:)`` 相同。每次該 view commit 之後都會再次呼叫，區域依 widget
        /// 所得到的尺寸重建。
        ///
        /// - Parameters:
        ///   - widget: The widget.
        ///   - region: Where it can be hit, or `nil` for its whole frame.
        func setContentShape(of widget: Widget, to region: HitRegion?)
    }
}

extension BackendFeatures.Core {
    /// Calls ``BackendFeatures/ContentShapes/setContentShape(of:to:)`` when
    /// this backend has it, and returns whether it did.
    ///
    /// For callers that apply a shape as a side effect of something else -- a
    /// tap gesture adopting its content's shape -- where a backend without
    /// the feature should simply keep its whole frame hittable.
    ///
    /// 若本 backend 具備 ``BackendFeatures/ContentShapes/setContentShape(of:to:)`` 就呼叫它，並
    /// 回傳是否呼叫了。給「套用形狀只是附帶作用」的呼叫端使用——例如點擊手勢沿用其內容的形狀——
    /// 在不具該功能的 backend 上，整個 frame 維持可被點中即可。
    @MainActor
    @discardableResult
    func setContentShapeIfSupported(of widget: Widget, to region: HitRegion?) -> Bool {
        func apply<B: BackendFeatures.ContentShapes>(_ backend: B) {
            backend.setContentShape(of: widget as! B.Widget, to: region)
        }
        guard let capable = self as? any BackendFeatures.ContentShapes else {
            return false
        }
        apply(capable)
        return true
    }
}
