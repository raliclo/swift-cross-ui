/// Styles already reported as unsupported.
///
/// The modification closure below runs on every `computeLayout` and every
/// `commit`, so an ungated log would repeat several times a frame for as long
/// as the view exists. Written without a lock, as `_logger` is: this runs on
/// the main actor with the rest of the view tree.
///
/// Keyed by the backend style rather than by the style value, now that a style
/// is an existential and need not be `Hashable`. Nothing is lost: only a
/// built-in style can be unsupported, and a built-in style is exactly one of
/// these.
///
/// 以 backend style 而非 style 值作為鍵，因為 style 現在是 existential，不必然是 `Hashable`。
/// 這並未損失任何東西：只有內建的 style 才可能不被支援，而內建的 style 恰好就是這些之一。
private nonisolated(unsafe) var warnedDatePickerStyles: Set<BackendDatePickerStyle> = []

extension View {
    /// Sets the date picker style for views.
    ///
    /// - Parameter style: The date picker style to use.
    ///
    /// ## See Also
    ///
    /// - ``DatePickerStyle``
    public func datePickerStyle(_ style: any DatePickerStyle) -> some View {
        EnvironmentModifier(self) { environment in
            let resolved = (style as? any _BuiltinDatePickerStyle)?
                ._asBackendDatePickerStyle(backend: environment.backend)

            guard style.isSupported(backend: environment.backend) else {
                // `assertionFailure` alone is compiled out of a release build,
                // so a shipped app substituted `.automatic` and said nothing at
                // all: an author who asked for a compact field got a full
                // calendar grid, with no way to find out why (#38). The style
                // that is unsupported is a property of the backend, not of the
                // moment, so saying it once is saying it.
                //
                // `PickerStyleModifier` carried the same defect and now carries
                // the same fix; keep the two in step.
                //
                // `PickerStyleModifier` 曾有同一個缺陷，如今也套用了同一個修法；請讓兩者
                // 保持一致。
                if warnedDatePickerStyles.insert(resolved ?? .automatic).inserted {
                    logger.warning(
                        """
                        date picker style \(type(of: style)) is not supported by \
                        \(type(of: environment.backend)); using .automatic instead
                        """
                    )
                }
                assertionFailure("Unsupported date picker style: \(type(of: style))")
                return
                    environment
                    .with(\.datePickerStyle, .automatic)
                    .with(\.backendDatePickerStyle, .automatic)
            }

            return
                environment
                .with(\.datePickerStyle, style)
                .with(\.backendDatePickerStyle, resolved ?? .automatic)
        }
    }
}
