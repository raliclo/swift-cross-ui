extension BackendFeatures {
    /// Backend methods for popovers: a transient panel of arbitrary view
    /// content, anchored to a widget.
    ///
    /// These are used by ``View/popover(isPresented:attachmentEdge:onDismiss:content:)``.
    ///
    /// **Why this is not ``BackendFeatures/PopoverMenus``, which was expected to
    /// cover it.** That protocol's `showPopoverMenu(_:at:relativeTo:closeHandler:)`
    /// takes a `Menu`, and a `Menu` is built from a ``ResolvedMenu`` -- a list of
    /// labels, toggles, separators and submenus. It cannot carry a `Widget`, so
    /// it cannot show a `Slider`, a `TextField`, or anything else a caller
    /// writes in a `@ViewBuilder`. The two protocols also disagree on who owns
    /// dismissal: a menu closes itself when an item is chosen, whereas a popover
    /// stays up until the binding says otherwise. Only two backends conform to
    /// `PopoverMenus` at all (GtkBackend and AppKitBackend); the other three use
    /// ``BackendFeatures/AttachedMenus``, and a popover is not a thing you can
    /// attach to a button.
    ///
    /// **On the relationship to ``BackendFeatures/Sheets``.** A popover is not a
    /// small sheet. A sheet is modal, centred on or filling its window, and
    /// knows nothing about the widget that produced it; a popover is
    /// light-dismiss, positioned against an anchor, and usually draws a beak
    /// pointing at it. The anchor is the requirement `Sheets` has no parameter
    /// for, and adding one there would change every existing conformance.
    ///
    /// Backends outside the five shipped ones need not conform. The modifier
    /// warns once and renders its anchor unmodified rather than aborting -- see
    /// its documentation for why that is the right answer *there* and the wrong
    /// answer for GtkBackend, WinUIBackend, AppKitBackend, UIKitBackend and
    /// AndroidBackend, all five of which implement this protocol.
    ///
    /// popover 的 backend 方法：一塊錨定在某個 widget 上、承載任意 view 內容的短暫面板。
    ///
    /// 由 ``View/popover(isPresented:attachmentEdge:onDismiss:content:)`` 使用。
    ///
    /// **為何這不是原本預期能涵蓋它的 ``BackendFeatures/PopoverMenus``。** 該 protocol 的
    /// `showPopoverMenu(_:at:relativeTo:closeHandler:)` 接受的是 `Menu`，而 `Menu` 由
    /// ``ResolvedMenu`` 建構——一串標籤、開關、分隔線與子選單。它無法承載 `Widget`，因此無法顯示
    /// `Slider`、`TextField`，或呼叫端寫在 `@ViewBuilder` 裡的任何其他東西。兩個 protocol 對
    /// 「由誰決定關閉」的看法也不同：選單在項目被選取時自行關閉，而 popover 會一直停留，直到
    /// binding 另有指示。此外，實際 conform `PopoverMenus` 的只有兩個 backend（GtkBackend 與
    /// AppKitBackend）；其餘三個使用 ``BackendFeatures/AttachedMenus``，而 popover 並不是可以
    /// 「附加在按鈕上」的東西。
    ///
    /// **關於它與 ``BackendFeatures/Sheets`` 的關係。** popover 並不是小一號的 sheet。sheet 是
    /// 模態的、置中於或填滿其視窗，且對產生它的 widget 一無所知；popover 則是點擊外部即關閉、
    /// 相對於錨點定位，且通常會畫出一個指向錨點的尖角。錨點正是 `Sheets` 沒有對應參數的那項要求，
    /// 而在那裡新增一個參數會改動每一份既有的 conformance。
    ///
    /// 五個已發布 backend 以外的 backend 不需要 conform。該 modifier 會警告一次並原樣繪製其錨點，
    /// 而非中止行程——關於為何那在**該處**是正確答案、而對 GtkBackend、WinUIBackend、AppKitBackend、
    /// UIKitBackend 與 AndroidBackend 是錯誤答案（這五者皆已實作本 protocol），見該 modifier 的文件。
    @MainActor
    public protocol Popovers<Popover>: Core {
        /// The underlying popover type. Can be a wrapper or subclass.
        associatedtype Popover

        /// Creates a popover object (without showing it).
        ///
        /// - Parameter content: The content of the popover.
        /// - Returns: A popover containing `content`.
        func createPopover(content: Widget) -> Popover

        /// Updates the appearance and behaviour of a popover.
        ///
        /// Called whenever the content's layout or the environment changes, and
        /// always at least once before ``showPopover(_:relativeTo:window:)``.
        ///
        /// - Parameters:
        ///   - popover: The popover to update.
        ///   - environment: The environment the popover is presented in. This is
        ///     the *outer* environment, not that of the popover's content.
        ///   - size: The size the popover's content wants to be, in points.
        ///   - attachmentEdge: The edge of the anchor widget that the popover
        ///     should prefer to appear from. A backend is free to flip this when
        ///     the requested side would put the popover off-screen; that is what
        ///     every platform's own positioner does, and fighting it would push
        ///     the popover out of view rather than keep a promise.
        ///   - backgroundColor: The background color for the popover, or `nil`
        ///     for the platform default. The platform default is strongly
        ///     preferred here -- popovers are one of the few surfaces that are
        ///     translucent and vibrant by default on macOS and Windows.
        ///   - onDismiss: An action to perform when the popover is dismissed by
        ///     the user (by clicking away, or pressing escape). Must *not* be
        ///     called for a dismissal caused by ``dismissPopover(_:)``.
        func updatePopover(
            _ popover: Popover,
            environment: EnvironmentValues,
            size: SIMD2<Int>,
            attachmentEdge: Edge,
            backgroundColor: Color.Resolved?,
            onDismiss: @escaping () -> Void
        )

        /// Shows a popover anchored to a widget.
        ///
        /// This method must only be called once for any given popover.
        ///
        /// - Parameters:
        ///   - popover: The popover to show.
        ///   - widget: The widget to anchor the popover to.
        ///   - window: The window the anchor is in. Needed by backends whose
        ///     popup primitive is attached to a root or a scene rather than to
        ///     the anchor itself.
        func showPopover(_ popover: Popover, relativeTo widget: Widget, window: Window)

        /// Dismisses a popover programmatically.
        ///
        /// Used by ``View/popover(isPresented:attachmentEdge:onDismiss:content:)``
        /// when the binding goes to `false`. Must not trigger the `onDismiss`
        /// handler given to ``updatePopover(_:environment:size:attachmentEdge:backgroundColor:onDismiss:)``,
        /// which is for user-driven dismissals only -- the same split as
        /// ``Sheets/dismissSheet(_:window:parentSheet:)``.
        ///
        /// - Parameter popover: The popover to dismiss.
        func dismissPopover(_ popover: Popover)
    }
}
