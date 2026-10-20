extension BackendFeatures {
    /// Backend methods for sheets.
    ///
    /// These are used by ``View/sheet(isPresented:onDismiss:content:)``.
    @MainActor
    public protocol Sheets<Sheet>: Core {
        /// The underlying sheet type. Can be a wrapper or subclass.
        associatedtype Sheet

        /// Creates a sheet object (without showing it).
        ///
        /// Sheets contain view content. They prevent users from interacting with
        /// the parent window until dimissed and can optionally execute a callback
        /// on dismiss.
        ///
        /// - Parameter content: The content of the sheet.
        /// - Returns: A sheet containing `content`.
        func createSheet(content: Widget) -> Sheet

        /// Updates the content, appearance and behaviour of a sheet.
        ///
        /// - Parameters:
        ///   - sheet: The sheet to update.
        ///   - window: The root window that the sheet will be presented in. Used on
        ///     platforms such as tvOS to compute layout constraints.
        ///
        ///     The sheet shouldn't be attached to the window by `updateSheet`. That
        ///     is handled by ``presentSheet(_:window:parentSheet:)`` which is
        ///     guaranteed to be called exactly once (unlike `updateSheet` which
        ///     gets called whenever preferences or sizing change).
        ///   - environment: The environment that the sheet will be presented in.
        ///     This differs from the environment passed to the sheet's content.
        ///   - size: The size of the sheet.
        ///   - onDismiss: An action to perform when the sheet gets dismissed by
        ///     the user. Not triggered by programmatic dismissals, but _is_
        ///     triggered by the implicit dismissals of nested sheets when their
        ///     parent sheet is programmatically dismissed.
        ///   - cornerRadius: The radius of the sheet. If `nil`, the platform
        ///     default should be used. Not all backends can support this (e.g.
        ///     macOS doesn't support custom window corner radii).
        ///   - detents: An array of sizes that the sheet should snap to. This is
        ///     generally only a thing on mobile where sheets can be dragged up
        ///     and down.
        ///   - dragIndicatorVisibility: Whether the drag indicator should be shown.
        ///     Sheet drag indicators are generally only a thing on mobile, and
        ///     usually appear as a small horizontal bar at the top of the sheet.
        ///   - backgroundColor: The background color to use for the sheet. If
        ///     `nil`, the platform's default sheet background style should be used.
        ///   - interactiveDismissDisabled: Whether to disable user-driven sheet
        ///     dismissal. On mobile this disables swiping to dismiss a sheet, and
        ///     on desktop this usually disables dismissal shortcuts such as the
        ///     escape key and/or removes system-provided close/cancel buttons from
        ///     the sheet.
        func updateSheet(
            _ sheet: Sheet,
            window: Window,
            environment: EnvironmentValues,
            size: SIMD2<Int>,
            onDismiss: @escaping () -> Void,
            cornerRadius: Double?,
            detents: [PresentationDetent],
            dragIndicatorVisibility: Visibility,
            backgroundColor: Color.Resolved?,
            interactiveDismissDisabled: Bool
        )

        /// Makes the sheet cover its whole window, or returns it to the
        /// platform's own sheet shape. `fullScreenCover` asks for it; every other
        /// sheet passes `false`. Called before ``updateSheet`` and, on the first
        /// pass, before ``presentSheet``, so a backend whose presentation
        /// style is fixed at presentation time can set it then.
        ///
        /// A backend whose sheets are already as large as the size they are given
        /// has nothing to lift, and says so where it implements this; one whose
        /// platform caps a sheet -- a page sheet on iPad, Material's bottom sheet on
        /// a tablet -- lifts the cap.
        ///
        /// 讓 sheet 覆蓋整個視窗，或回到平台自己的 sheet 形狀。`fullScreenCover` 會要求它，其他 sheet 傳 `false`。在
        /// ``updateSheet`` 之前呼叫(第一輪也在 ``presentSheet`` 之前),好讓「呈現樣式在呈現時就固定」的 backend 能在那時設定。
        /// sheet 本來就和給它的尺寸一樣大的 backend 沒有限制可拿掉，並在實作處寫明;平台會限制 sheet 的 backend(iPad 的
        /// page sheet、平板上 Material 的 bottom sheet)要拿掉限制。
        func setPresentationFillsWindow(of sheet: Sheet, window: Window, _ fillsWindow: Bool)

        /// Presents a sheet as a modal on top of or within the given window.
        ///
        /// Sheets should disable interaction with all content below them until they
        /// get dismissed.
        ///
        /// `onDismiss` only gets called once the sheet has been closed.
        ///
        /// This method must only be called once for any given sheet.
        ///
        /// - Parameters:
        ///   - sheet: The sheet to present.
        ///   - window: The window to present the sheet on top of.
        ///   - parentSheet: The sheet that the current sheet was presented from,
        ///     if any.
        func presentSheet(
            _ sheet: Sheet,
            window: Window,
            parentSheet: Sheet?
        )

        /// Dismisses a sheet programmatically.
        ///
        /// Used by the ``View/sheet(isPresented:onDismiss:content:)`` modifier to
        /// close sheets.
        ///
        /// - Parameters:
        ///   - sheet: The sheet to dismiss.
        ///   - window: The window that the sheet was presented in.
        ///   - parentSheet: The sheet that presented the current sheet, if any.
        func dismissSheet(_ sheet: Sheet, window: Window, parentSheet: Sheet?)

        /// Get the size of a sheet.
        ///
        /// - Parameter sheet: The sheet to get the size of.
        /// - Returns: The sheet's size.
        func size(ofSheet sheet: Sheet) -> SIMD2<Int>
    }
}
