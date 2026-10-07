extension BackendFeatures {
    public typealias Buttons = StringLabelButtons & ViewLabelButtons

    /// Backend methods for simple buttons.
    ///
    /// These are used by ``Toggle`` and ``Menu``.
    @MainActor
    public protocol StringLabelButtons: Core {
        /// Creates a labelled button with an action triggered on click/tap.
        ///
        /// Used by controls in button style like ``Menu``, ``Toggle`` or more constrained result builders.
        ///
        /// - Returns: A button.
        func createSimpleButton() -> Widget

        /// Sets a button's label and action.
        ///
        /// - Parameters:
        ///   - button: The button to update.
        ///   - label: The button's label.
        ///   - environment: The current environment.
        ///   - action: The action to perform when the button is clicked/tapped.
        ///     This replaces any existing actions.
        func updateSimpleButton(
            _ button: Widget,
            label: String,
            environment: EnvironmentValues,
            action: @escaping () -> Void
        )
    }

    /// Backend methods for more complex buttons supporting an arbitrary ``View`` as label.
    ///
    /// These are used by ``Button``.
    @MainActor
    public protocol ViewLabelButtons: Core {
        /// Creates a button that uses `widget` as its label with an action triggered on click/tap.
        ///
        /// Predominantly used by ``Button``.
        ///
        /// - Parameters:
        ///   - widget: The widget the button should use as label.
        ///
        /// - Returns: A button.
        func createButton(wrapping widget: Widget) -> Widget

        /// Sets a button's action and updates the rendered style based on the environment.
        ///
        /// - Parameters:
        ///   - button: The button to update.
        ///   - environment: The current environment.
        ///   - action: The action to perform when the button is clicked/tapped.
        ///     This replaces any existing actions.
        func updateButton(
            _ button: Widget,
            environment: EnvironmentValues,
            action: @escaping () -> Void
        )

        /// Buttons are set to label size + padding by SwiftCrossUI.
        /// Backends may choose different amounts of padding for different button styles.
        ///
        /// A padding of (0, 0) is recommended for all styles without a system defined background.
        ///
        /// - Parameters:
        ///   - environment: The current environment.
        ///
        /// - Returns: A vector containing the **total** spacing horizontally and vertically.
        func buttonPadding(in environment: EnvironmentValues) -> SIMD2<Int>

        /// The default button style that the backend desires.
        ///
        /// - Returns: The default ``PrimitiveButtonStyle``.
        ///
        /// Only ever a built-in style. A custom ``ButtonStyle`` belongs to an
        /// application, so a backend has nothing to say about it and is never
        /// asked; see ``EnvironmentValues/customButtonStyle``.
        ///
        /// 只會是內建樣式。自訂的 ``ButtonStyle`` 屬於應用程式，backend 對它無話可說，也永遠不會被
        /// 問到；見 ``EnvironmentValues/customButtonStyle``。
        func defaultButtonStyle() -> PrimitiveButtonStyle

        /// Modifies the environment for the body of a button label.
        ///
        /// Backends may implement their own to align with the platform's conventions more closely.
        /// The default implementation applies SwiftUI-like behavior.
        ///
        /// - Returns: The modified environment.
        func computeButtonLabelEnvironment(
            from environment: EnvironmentValues
        ) -> EnvironmentValues

        /// The colour a ``ButtonRole/destructive`` button's label takes when the
        /// application has named none, or `nil` to leave the label alone.
        ///
        /// Each platform marks a destructive button its own way, and on AppKit,
        /// UIKit and Android that way is the label's colour: the system red on
        /// the first two, the theme's `colorError` on Android. The label is a
        /// SwiftCrossUI view rather than the native control's title, so the
        /// colour has to reach it through the environment -- `updateButton`
        /// alone cannot recolour it. A backend whose platform styles the control
        /// itself (GTK's `destructive-action` class, which the label inherits)
        /// returns `nil` and does that in `updateButton`. An application colour
        /// always wins, as a `.foregroundColor` does on any other button.
        ///
        /// ``ButtonRole/destructive`` 按鈕的標籤在應用程式沒有指定顏色時所用的顏色;回傳 `nil` 則不動標籤。
        /// 各平台以自己的方式標示危險按鈕，在 AppKit、UIKit 與 Android 上那方式就是標籤的顏色：前兩者是系統紅，
        /// Android 是主題的 `colorError`。標籤是 SwiftCrossUI 的 view 而非原生控制項的 title,所以顏色必須經由
        /// environment 送到它——單靠 `updateButton` 改不了它的顏色。平台自己替控制項上樣式的 backend(GTK 的
        /// `destructive-action` class,標籤會繼承)回傳 `nil`,在 `updateButton` 裡處理。應用程式指定的顏色永遠優先。
        func destructiveButtonLabelColor(in environment: EnvironmentValues) -> Color?
    }
}

// MARK: - Default Implementations
extension BackendFeatures.ViewLabelButtons {
    public func computeButtonLabelEnvironment(
        from environment: EnvironmentValues
    ) -> EnvironmentValues {
        var labelEnvironment = environment

        let buttonStyle = environment.resolvedButtonStyle.kind
        let deviceClass = environment.backend.deviceClass

        if
            !environment.isEnabled, buttonStyle == .bordered,
            deviceClass == .desktop || deviceClass == .tv
        {
            labelEnvironment = labelEnvironment.with(
                \.foregroundColor,
                environment.suggestedForegroundColor.opacity(0.3) // SwiftUI uses tertiary afaict.
            )
        }

        // The disabled opacities and defaults are based on discoveries in SwiftUI.

        // Set the default foregroundColor for the label unless overridden.
        // Uses the same colors as SwiftUI.
        if
            buttonStyle == .borderless,
            deviceClass == .desktop
        {
            // Approximately equivalent to Color.secondary in SwiftUI.
            let opacity = environment.colorScheme == .dark ? 0.7 : 0.5
            labelEnvironment = labelEnvironment.with(
                \.foregroundColor,
                environment.foregroundColor ?? environment.suggestedForegroundColor.opacity(opacity)
            )
        }

        return labelEnvironment
    }
}

extension BackendFeatures.ViewLabelButtons {
    /// `nil`: the backend styles a destructive button some other way, or not
    /// through its label's colour.
    public func destructiveButtonLabelColor(in environment: EnvironmentValues) -> Color? {
        nil
    }
}
