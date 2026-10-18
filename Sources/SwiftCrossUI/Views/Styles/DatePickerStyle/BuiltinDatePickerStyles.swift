import Foundation

/// The four built-in date picker styles.
///
/// One file rather than four, unlike `PickerStyle`'s, because each is three
/// lines and the availability attributes are the only thing that differs
/// between them. They are worth reading side by side for that reason.
///
/// The `where Self == …` extensions are what make `.datePickerStyle(.compact)`
/// read the same as it did when these were enum cases. That is the whole point
/// of the shape: existing call sites do not change, and a call site that could
/// never have been written -- a style of the author's own -- becomes possible.

/// A date input that adapts to the current platform and context.
///
/// Supported by every backend, and the one anything unsupported falls back to.
public struct AutomaticDatePickerStyle: DatePickerStyle, _BuiltinDatePickerStyle {
    public nonisolated init() {}

    public func _asBackendDatePickerStyle<Backend: BaseAppBackend>(backend: Backend)
        -> BackendDatePickerStyle
    {
        .automatic
    }
}

extension DatePickerStyle where Self == AutomaticDatePickerStyle {
    /// A date input that adapts to the current platform and context.
    public static nonisolated var automatic: Self { Self() }
}

/// A date input that shows a calendar grid.
///
/// Supported by AppKitBackend, UIKitBackend, WinUIBackend and GtkBackend, and by
/// AndroidBackend on API levels that have the material date picker.
@available(iOS 14, macCatalyst 14, *)
public struct GraphicalDatePickerStyle: DatePickerStyle, _BuiltinDatePickerStyle {
    public nonisolated init() {}

    public func _asBackendDatePickerStyle<Backend: BaseAppBackend>(backend: Backend)
        -> BackendDatePickerStyle
    {
        .graphical
    }
}

@available(iOS 14, macCatalyst 14, *)
extension DatePickerStyle where Self == GraphicalDatePickerStyle {
    /// A date input that shows a calendar grid.
    public static nonisolated var graphical: Self { Self() }
}

/// A smaller date input. This may be a text field, or a button that opens a
/// calendar pop-up.
///
/// Supported by AppKitBackend, UIKitBackend, WinUIBackend, AndroidBackend and
/// GtkBackend. GtkBackend draws the second of those shapes: a `GtkMenuButton`
/// whose popover holds a `GtkCalendar`.
@available(iOS 13.4, macCatalyst 13.4, *)
public struct CompactDatePickerStyle: DatePickerStyle, _BuiltinDatePickerStyle {
    public nonisolated init() {}

    public func _asBackendDatePickerStyle<Backend: BaseAppBackend>(backend: Backend)
        -> BackendDatePickerStyle
    {
        .compact
    }
}

@available(iOS 13.4, macCatalyst 13.4, *)
extension DatePickerStyle where Self == CompactDatePickerStyle {
    /// A smaller date input. This may be a text field, or a button that opens a
    /// calendar pop-up.
    public static nonisolated var compact: Self { Self() }
}

/// A set of scrollable inputs that can be used to select a date.
///
/// Supported by every backend. UIKitBackend, WinUIBackend and AndroidBackend
/// (where its API level has the spinner) draw their own wheel; AppKitBackend
/// and GtkBackend, which have no wheel control, draw ``_SwiftWheelDatePicker``,
/// built from SwiftCrossUI views. Available on macOS, unlike SwiftUI's, for that
/// reason: the project's rule is that a feature works on every shipped backend
/// (P90 said "unavailable on macOS" until 2026-10-18).
///
/// 每個 backend 都支援。UIKitBackend、WinUIBackend 與 AndroidBackend(API 層級有 spinner 時)畫自己的滾輪;沒有滾輪控制項的
/// AppKitBackend 與 GtkBackend 畫 ``_SwiftWheelDatePicker``,以 SwiftCrossUI 的 view 組成。因此與 SwiftUI 不同，在 macOS 上
/// 也可用：本專案的規則是功能在每個已發布的 backend 上都要能用(P90 直到 2026-10-18 都顯示「macOS 上不可用」)。
@available(iOS 13.4, macCatalyst 13.4, *)
public struct WheelDatePickerStyle: DatePickerStyle {
    public nonisolated init() {}

    public func makeView(
        selection: Binding<Date>,
        range: ClosedRange<Date>,
        components: DatePickerComponents,
        environment: EnvironmentValues
    ) -> _WheelDatePickerImplementation {
        // No backend on macOS has a native date wheel, and the backend style
        // `.wheel` is unavailable there.
        // macOS 上沒有任何 backend 有原生的日期滾輪，而 backend 樣式 `.wheel` 在那裡不可用。
        #if os(macOS)
            let nativeWheel = false
        #else
            let datePickers = environment.backend as? any BackendFeatures.DatePickers
            let nativeWheel = datePickers?.supportedDatePickerStyles.contains(.wheel) ?? false
        #endif
        return _WheelDatePickerImplementation(
            selection: selection,
            range: range,
            components: components,
            nativeWheel: nativeWheel
        )
    }

    public func isSupported<Backend: BaseAppBackend>(backend: Backend) -> Bool {
        true
    }
}

@available(iOS 13.4, macCatalyst 13.4, *)
extension DatePickerStyle where Self == WheelDatePickerStyle {
    /// A set of scrollable inputs that can be used to select a date.
    public static nonisolated var wheel: Self { Self() }
}
