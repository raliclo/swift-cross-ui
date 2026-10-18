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

        /// How the backend's own picker draws a time, when it matches one of
        /// ``ClockDatePickerStyle`` and ``RowsDatePickerStyle``: AppKit draws a
        /// clock face for `.graphical`, GtkBackend a row of spin buttons for
        /// every style. `nil`, the default, means neither, and the style is
        /// drawn in SwiftCrossUI views (P41, 2026-10-18).
        /// backend 自己的選擇器畫時間的方式，若符合 ``ClockDatePickerStyle`` 或 ``RowsDatePickerStyle`` 之一:
        /// AppKit 對 `.graphical` 畫鐘面,GtkBackend 對每種樣式畫一列 spin button。預設的 `nil` 表示兩者皆非，該樣式
        /// 以 SwiftCrossUI 的 view 畫出(P41,2026-10-18)。
        nonisolated var nativeTimePresentation: TimePickerPresentation? { get }
    }
}

/// The two ways a time is drawn: ``ClockDatePickerStyle`` and ``RowsDatePickerStyle``.
/// 時間的兩種畫法:``ClockDatePickerStyle`` 與 ``RowsDatePickerStyle``。
public enum TimePickerPresentation: Sendable, Hashable {
    /// An analogue clock face with hands. / 有指針的類比鐘面。
    case clock
    /// A row of hour, minute and second fields. / 一列時、分、秒欄位。
    case rows
}

extension BackendFeatures.DatePickers {
    public nonisolated var nativeTimePresentation: TimePickerPresentation? { nil }
}
