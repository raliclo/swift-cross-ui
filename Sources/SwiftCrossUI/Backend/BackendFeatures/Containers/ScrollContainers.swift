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
        /// Scrolls a container so that one of its descendants is visible.
        ///
        /// - Parameters:
        ///   - scrollView: A scroll container from ``createScrollContainer(for:)``.
        ///   - child: A widget somewhere inside it. A widget that is NOT inside
        ///     it must be ignored rather than scrolled to -- an id that names a
        ///     view in a different scroll view is a mistake in the application,
        ///     and moving the wrong container hides it.
        ///   - anchor: Where in the viewport to put the child, or `nil` for the
        ///     shortest scroll that makes it visible. `nil` is what SwiftUI's
        ///     `scrollTo(_:anchor:)` means by a nil anchor, and it is the case
        ///     every platform here has a native call for.
        ///
        /// **Expressed as "reach this widget" rather than "go to this offset",
        /// and that was a constraint rather than a preference.** GTK's
        /// `gtk_viewport_scroll_to` is 4.12 and this package builds against
        /// < 4.10, so GTK cannot be handed a child and told to reach it by the
        /// toolkit -- but `gtk_widget_compute_point` has been there since 4.0,
        /// so it can compute the offset itself. Every other backend has a
        /// native scroll-to-descendant call. Asking each backend for the offset
        /// instead would mean the framework computing a position it does not
        /// have: a view's origin inside its scroll content is known to the
        /// layout system and published nowhere.
        ///
        /// 捲動某個容器,使它的某個子孫可見。
        ///
        /// - Parameters:
        ///   - scrollView: 由 ``createScrollContainer(for:)`` 產生的 scroll container。
        ///   - child: 位於它內部某處的一個 widget。**不**在它內部的 widget 必須被忽略而非被捲向——
        ///     一個指向「另一個捲動視圖中的 view」的 id 是應用程式的錯誤,而移動錯誤的容器會把它藏起來。
        ///   - anchor: 要把該子元件放在視口的什麼位置,或傳 `nil` 表示「讓它可見的最短捲動」。
        ///     `nil` 正是 SwiftUI 的 `scrollTo(_:anchor:)` 對 nil anchor 的定義,而那也是此處每一個
        ///     平台都有原生呼叫可用的情況。
        ///
        /// **表述為「抵達這個 widget」而非「前往這個位移」,而那是一項約束、不是偏好。** GTK 的
        /// `gtk_viewport_scroll_to` 需要 4.12,而本套件建置於 < 4.10 之上,因此無法把一個子元件交給
        /// GTK 並要求 toolkit 抵達它——但 `gtk_widget_compute_point` 自 4.0 就存在,所以它可以自己算出
        /// 那個位移。其餘每一個 backend 都有原生的「捲到某個子孫」呼叫。反過來要求每個 backend 接受
        /// 位移,則意味著框架必須算出一個它並不擁有的位置:一個 view 在其捲動內容中的原點,layout system
        /// 知道,但沒有發布到任何地方。
        func scrollContainer(
            _ scrollView: Widget,
            to child: Widget,
            anchor: UnitPoint?
        )

        func setRefreshHandler(
            ofScrollContainer scrollView: Widget,
            to handler: (@MainActor @Sendable () -> Void)?
        )
    }
}
