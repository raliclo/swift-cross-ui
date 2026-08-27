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
/// Supported by UIKitBackend and WinUIBackend. Not by GtkBackend, which has no
/// wheel widget of any kind, nor by AppKitBackend or AndroidBackend.
@available(iOS 13.4, macCatalyst 13.4, *)
@available(macOS, unavailable)
public struct WheelDatePickerStyle: DatePickerStyle, _BuiltinDatePickerStyle {
    public nonisolated init() {}

    public func _asBackendDatePickerStyle<Backend: BaseAppBackend>(backend: Backend)
        -> BackendDatePickerStyle
    {
        .wheel
    }
}

@available(iOS 13.4, macCatalyst 13.4, *)
@available(macOS, unavailable)
extension DatePickerStyle where Self == WheelDatePickerStyle {
    /// A set of scrollable inputs that can be used to select a date.
    public static nonisolated var wheel: Self { Self() }
}
