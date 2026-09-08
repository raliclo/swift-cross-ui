extension BackendFeatures {
    /// Backend methods for scroll containers.
    ///
    /// These are used by ``ScrollView`` and other views that require scrolling.
    @MainActor
    public protocol ScrollContainers: Core {
        /// Gets the layout width of a backend's scroll bars.
        ///
        /// Assumes that the width is the same for both vertical and horizontal
        /// scroll bars (where the width of a horizontal scroll bar is what pedants
        /// may call its height). If the backend uses overlay scroll bars then this
        /// width should be 0.
        ///
        /// This value may make sense to have as a computed property for some backends
        /// such as `AppKitBackend` where plugging in a mouse can cause the default
        /// scroll bar style to change. If something does cause this value to change,
        /// ensure that the configured root environment change handler gets called so
        /// that SwiftCrossUI can update the app's layout accordingly.
        var scrollBarWidth: Int { get }

        /// Creates a scrollable single-child container wrapping the given widget.
        ///
        /// - Parameter child: The widget to wrap in a scroll container.
        /// - Returns: A scroll container wrapping `child`.
        func createScrollContainer(for child: Widget) -> Widget

        /// Updates a scroll container with environment-specific values.
        ///
        /// This method is primarily used on iOS to apply environment changes
        /// that affect the scroll view’s behavior, such as keyboard dismissal mode.
        ///
        /// - Parameters:
        ///   - scrollView: The scroll container widget previously created by
        ///     ``createScrollContainer(for:)``.
        ///   - environment: The current ``EnvironmentValues`` to apply.
        ///   - bounceHorizontally: Whether the scroll view should 'bounce' horizontally.
        ///     Some backends ignore this, as it's not a universal concept.
        ///   - bounceVertically: Whether the scroll view should 'bounce' vertically.
        ///     Some backends ignore this, as it's not a universal concept.
        ///   - hasHorizontalScrollBar: Whether the scroll view has a horizontal
        ///     scroll bar.
        ///   - hasVerticalScrollBar: Whether the scroll view has a vertical scroll
        ///     bar.
        func updateScrollContainer(
            _ scrollView: Widget,
            environment: EnvironmentValues,
            bounceHorizontally: Bool,
            bounceVertically: Bool,
            hasHorizontalScrollBar: Bool,
            hasVerticalScrollBar: Bool
        )

        /// Sets the action a scroll container runs when the user pulls it down
        /// past its top, or removes it.
        ///
        /// `nil` must REMOVE the control, not merely stop calling the handler.
        /// A pull-to-refresh spinner that still appears and then does nothing
        /// is worse than no spinner: it tells the user the app is fetching
        /// something when nothing was asked for.
        ///
        /// Called on every update, so an implementation must be cheap when the
        /// handler has not changed. Rebuilding the control each time resets any
        /// refresh already in flight, which on a slow fetch cancels the very
        /// thing the user pulled for.
        ///
        /// A backend whose platform has no pull gesture -- a desktop toolkit
        /// driven by a mouse -- should give the container some other way to run
        /// the action rather than dropping it. Each backend's file says which
        /// way it chose.
        ///
        /// - Parameters:
        ///   - scrollView: A scroll container from ``createScrollContainer(for:)``.
        ///   - handler: The action, or `nil` to remove the control entirely.
        ///
        /// 設定 scroll container 在使用者將其自頂端往下拉時執行的動作,或移除該動作。
        ///
        /// 傳入 `nil` 必須**移除**該控制項,而不只是不再呼叫 handler。一個「仍會出現、然後什麼都不做」
        /// 的下拉重新整理轉圈,比沒有轉圈更糟:它告訴使用者這個 app 正在取得某樣東西,而其實沒有人
        /// 要求過任何東西。
        ///
        /// 每次更新都會被呼叫,因此當 handler 未改變時,實作必須是廉價的。每次都重建該控制項會重置
        /// 任何正在進行中的重新整理,而在一次緩慢的抓取上,那正好取消掉使用者所拉動的那件事。
        ///
        /// 若某個 backend 所在的平台沒有下拉手勢——例如以滑鼠驅動的桌面 toolkit——它應當為該容器
        /// 提供另一種執行該動作的方式,而不是把它丟掉。每個 backend 的檔案都會說明它選了哪一種。
        func setRefreshHandler(
            ofScrollContainer scrollView: Widget,
            to handler: (@MainActor @Sendable () -> Void)?
        )
    }
}
