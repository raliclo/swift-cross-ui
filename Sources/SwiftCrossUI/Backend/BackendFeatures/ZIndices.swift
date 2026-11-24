extension BackendFeatures {
    /// Backend methods for drawing a container's children in an order other
    /// than their index order.
    ///
    /// These are used by ``View/zIndex(_:)``.
    ///
    /// 讓容器的子元件以不同於索引順序的順序繪製的 backend 方法。供 ``View/zIndex(_:)`` 使用。
    @MainActor
    public protocol ZIndices: GenericContainers {
        /// Draws a container's children in the given order and hit-tests them
        /// in its reverse.
        ///
        /// The children keep their indices: `insert`, `swap`, `remove` and
        /// `setPosition` still address them by declaration order. Only what is
        /// drawn over what changes, and with it which child a click or touch
        /// reaches first.
        ///
        /// Called after every layout of a container whose children are ordered
        /// by ``View/zIndex(_:)``, and with `nil` after every other layout, so that
        /// children that lose their `zIndex` go back; keep `nil` cheap, it is the common case.
        ///
        /// 以給定順序繪製容器的子元件，並以相反順序做 hit test。子元件保留它們的索引:`insert`、`swap`、
        /// `remove` 與 `setPosition` 仍以宣告順序指稱它們。改變的只有誰畫在誰之上，以及點擊或觸控先到達哪
        /// 一個子元件。每次排版一個子元件以 ``View/zIndex(_:)`` 排序的容器之後都會呼叫，其餘每次排版之後則以
        /// `nil` 呼叫，讓失去 `zIndex` 的子元件回到原位;請讓 `nil` 保持便宜——那是常見情況。
        ///
        /// - Parameters:
        ///   - container: The container.
        ///   - order: Child indices from back to front, a permutation of
        ///     `0..<count`; `nil` for declaration order.
        func setDrawingOrder(ofChildrenIn container: Widget, to order: [Int]?)
    }
}
