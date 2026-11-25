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
        /// Input other than a press is limited the same way: while the pointer
        /// is in the frame but outside `region`, hover, cursor and drop targets
        /// treat it as not over the widget, and a press that arrives with no
        /// move before it is decided by where it lands.
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
        /// 不是按壓的輸入也受同樣的限制：指標位於 frame 之內、`region` 之外時，懸停、游標與拖放目標都視它
        /// 為不在該 widget 上；沒有先移動就抵達的按壓，也必須依它落下的位置判斷。
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

    /// Gives a pointer-input target the content shape of the view it wraps.
    ///
    /// Every modifier that wraps its content in a widget of its own to receive
    /// pointer input -- taps, long presses, drags, magnify and rotate, context
    /// menus, hover, continuous hover, cursors, scrolling and drops -- calls
    /// this after committing the content, so that
    /// `.contentShape(Circle()).onLongPressGesture { ... }` is hit only inside
    /// the circle even where the backend puts that wrapper beside or over the
    /// content. The shape travels up as ``PreferenceValues/contentShape`` and is
    /// resolved again in the wrapper's own size, with every geometric effect it
    /// passed through applied; `nil` keeps the whole frame, and clears a shape
    /// a previous update set.
    ///
    /// Some backends attach the input controller to the content's own widget
    /// instead of a wrapper (GtkBackend), so `widget` and `content` are the same
    /// object. When that content is a geometric-effect container, the
    /// container's own transform is applied by its parent and its coordinates
    /// are the untransformed ones, so the outermost effect is left out
    /// (``ContentShape/region(in:outermostEffectApplied:)``).
    ///
    /// 讓一個指標輸入目標沿用其所包裝之 view 的 content shape。
    ///
    /// 每個為了接收指標輸入而把內容包進自己 widget 的 modifier——點按、長按、拖曳、縮放與旋轉、
    /// context menu、懸停、連續懸停、游標、捲動與拖放——都在 commit 內容之後呼叫此方法，讓
    /// `.contentShape(Circle()).onLongPressGesture { ... }` 即使在 backend 把該包裝層放在內容旁邊
    /// 或上方時，也只在圓內被命中。形狀以 ``PreferenceValues/contentShape`` 向上傳遞，並在包裝層自己
    /// 的尺寸中重新解析，途經的每個幾何效果都會套用;`nil` 保留整個 frame,並清除先前更新所設的形狀。
    ///
    /// 有些 backend 把輸入控制器直接加在內容自己的 widget 上，而不是包裝層(GtkBackend),因此
    /// `widget` 與 `content` 是同一個物件。當該內容是幾何效果容器時，容器自身的 transform 由其父元件
    /// 套用，其座標是未經變換的座標，因此最外層的效果不予套用
    /// (``ContentShape/region(in:outermostEffectApplied:)``)。
    @MainActor
    func adoptContentShape(of committed: ViewLayoutResult, for widget: Widget, wrapping content: Widget) {
        let isContentItself = (widget as AnyObject) === (content as AnyObject)
        setContentShapeIfSupported(
            of: widget,
            to: committed.preferences.contentShape?.region(
                in: committed.size,
                outermostEffectApplied: !isContentItself
            )
        )
    }
}
