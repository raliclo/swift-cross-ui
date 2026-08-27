import Foundation

extension BackendFeatures {
    /// Backend methods for date pickers.
    ///
    /// These are used by ``DatePicker``.
    @MainActor
    public protocol DatePickers: Core {
        /// The supported date picker styles.
        ///
        /// Must include ``BackendDatePickerStyle/automatic``.
        nonisolated var supportedDatePickerStyles: [BackendDatePickerStyle] { get }

        func createDatePicker() -> Widget

        func updateDatePicker(
            _ datePicker: Widget,
            environment: EnvironmentValues,
            date: Date,
            range: ClosedRange<Date>,
            components: DatePickerComponents,
            onChange: @escaping (Date) -> Void
        )
    }
}
