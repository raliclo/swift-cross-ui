/// Styles already reported as unsupported.
///
/// The modification closure below runs on every `computeLayout` and every
/// `commit`, so an ungated log would repeat several times a frame for as long
/// as the view exists. Written without a lock, as `_logger` is: this runs on
/// the main actor with the rest of the view tree.
private nonisolated(unsafe) var warnedDatePickerStyles: Set<DatePickerStyle> = []

extension View {
    public func datePickerStyle(_ style: DatePickerStyle) -> some View {
        EnvironmentModifier(self) { environment in
            guard environment.supportedDatePickerStyles.contains(style) else {
                // `assertionFailure` alone is compiled out of a release build,
                // so a shipped app substituted `.automatic` and said nothing at
                // all: an author who asked for a compact field got a full
                // calendar grid, with no way to find out why (#38). The style
                // that is unsupported is a property of the backend, not of the
                // moment, so saying it once is saying it.
                if warnedDatePickerStyles.insert(style).inserted {
                    logger.warning(
                        """
                        date picker style \(style) is not supported by \
                        \(type(of: environment.backend)); using .automatic instead
                        """
                    )
                }
                assertionFailure("Unsupported date picker style: \(style)")
                return environment.with(\.datePickerStyle, .automatic)
            }
            return environment.with(\.datePickerStyle, style)
        }
    }
}
