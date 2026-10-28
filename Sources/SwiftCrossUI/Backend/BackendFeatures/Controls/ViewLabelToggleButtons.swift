extension BackendFeatures {
    /// Backend methods for a button-style toggle whose label is an arbitrary
    /// view.
    ///
    /// ``Toggle`` with a view label (`Toggle(isOn:label:)`) in the
    /// ``ToggleStyle/button`` style draws the label *inside* the native toggle
    /// button, as SwiftUI does, so the backend has to host a child widget in
    /// it -- the same thing ``BackendFeatures/ViewLabelButtons`` asks of a
    /// plain button through `createButton(wrapping:)`. The switch and checkbox
    /// styles need nothing from here: they place the label beside an unlabelled
    /// control in the core, as SwiftUI does on macOS and iOS.
    ///
    /// **Separate from ``BackendFeatures/ToggleButtons``** so that a backend
    /// outside the five shipped ones still compiles; ``Toggle`` checks for this
    /// conformance and, on a backend without it, draws the label in a
    /// ``Button`` that flips the value. GtkBackend, WinUIBackend, AppKitBackend,
    /// UIKitBackend and AndroidBackend all conform.
    ///
    /// 標籤為任意 view 的按鈕樣式 toggle 所需的 backend 方法。
    ///
    /// 帶 view 標籤的 ``Toggle``(`Toggle(isOn:label:)`)在 ``ToggleStyle/button`` 樣式下，會像 SwiftUI 一樣把標籤畫在
    /// 原生 toggle 按鈕**裡面**,因此 backend 必須在其中容納一個子 widget——與 ``BackendFeatures/ViewLabelButtons``
    /// 透過 `createButton(wrapping:)` 對一般按鈕的要求相同。switch 與 checkbox 樣式不需要這裡的任何東西：它們在 core 中
    /// 把標籤放在一個無標籤控制項旁邊，與 SwiftUI 在 macOS 與 iOS 上的做法相同。
    ///
    /// **與 ``BackendFeatures/ToggleButtons`` 分開**,讓五個已發布 backend 以外的 backend 仍然能編譯;``Toggle`` 會檢查
    /// 這個 conformance,在沒有它的 backend 上，把標籤畫在一顆會翻轉值的 ``Button`` 裡。GtkBackend、WinUIBackend、
    /// AppKitBackend、UIKitBackend 與 AndroidBackend 全部都遵循。
    @MainActor
    public protocol ViewLabelToggleButtons: ToggleButtons {
        /// Creates a toggle button that shows `widget` as its label.
        ///
        /// Clicking anywhere on it, the label included, flips it and calls the
        /// handler installed by `updateToggle(_:environment:onChange:)`. Its
        /// accessibility name is the text of the label.
        ///
        /// 建立一個以 `widget` 為標籤的 toggle 按鈕。點擊其上任何位置(含標籤)都會翻轉它，並呼叫
        /// `updateToggle(_:environment:onChange:)` 所安裝的 handler。它的輔助使用名稱是標籤的文字。
        func createToggle(wrapping widget: Widget) -> Widget

        /// Sets a view-label toggle's change handler and enabled state.
        ///
        /// - Parameters:
        ///   - toggle: A widget returned by `createToggle(wrapping:)`.
        ///   - environment: The current environment.
        ///   - onChange: Called with the new state when the user flips the
        ///     toggle. Replaces any previous handler.
        ///
        /// 設定 view 標籤 toggle 的變更 handler 與啟用狀態。`onChange` 在使用者翻轉 toggle 時以新狀態呼叫，取代先前的 handler。
        func updateToggle(
            _ toggle: Widget,
            environment: EnvironmentValues,
            onChange: @escaping (Bool) -> Void
        )

        /// Sets the state of a toggle returned by `createToggle(wrapping:)`,
        /// without calling its change handler.
        ///
        /// 設定由 `createToggle(wrapping:)` 回傳之 toggle 的狀態，不呼叫其變更 handler。
        func setState(ofViewLabelToggle toggle: Widget, to state: Bool)

        /// The total horizontal and vertical space the toggle adds around its
        /// label. The core sizes the toggle to the label plus this.
        ///
        /// toggle 在標籤周圍所增加的水平與垂直空間總和。core 以「標籤加上它」決定 toggle 的大小。
        func toggleButtonPadding(in environment: EnvironmentValues) -> SIMD2<Int>

        /// The environment the label is laid out and drawn in, for a toggle that
        /// is on or off.
        ///
        /// A platform that fills an on toggle with the accent colour draws its
        /// title in a contrasting colour (white on WinUI, AndroidBackend's
        /// filled state); a view label is a SwiftCrossUI view, so that colour
        /// has to reach it through the environment. The default returns the
        /// environment unchanged.
        ///
        /// 標籤在 toggle 開或關時用來排版與繪製的 environment。以強調色填滿開啟中 toggle 的平台，會以對比色畫它的標題
        /// (WinUI 的白色、AndroidBackend 的填滿狀態);view 標籤是 SwiftCrossUI 的 view,所以那個顏色必須經由
        /// environment 送到它。預設實作原樣回傳 environment。
        func computeToggleLabelEnvironment(
            from environment: EnvironmentValues,
            isOn: Bool
        ) -> EnvironmentValues
    }
}

extension BackendFeatures.ViewLabelToggleButtons {
    public func computeToggleLabelEnvironment(
        from environment: EnvironmentValues,
        isOn: Bool
    ) -> EnvironmentValues {
        environment
    }
}
