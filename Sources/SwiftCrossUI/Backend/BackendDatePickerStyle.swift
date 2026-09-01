/// The date input shapes a backend can be asked for directly.
///
/// The counterpart of ``BackendPickerStyle``, and it sits here for the same
/// reason: it is the vocabulary a backend implements, not the API an
/// application writes against. Applications use the ``DatePickerStyle``
/// protocol, and a built-in style resolves to one of these through
/// ``_BuiltinDatePickerStyle``.
///
/// This was `DatePickerStyle` itself until 2026-08-27, which made the two
/// things one thing and cost the ability to write a custom style at all --
/// `struct MyStyle: DatePickerStyle` compiles against SwiftUI and could not
/// compile here. Nothing in the API surface hinted at that, because the call
/// sites are identical either way: `.datePickerStyle(.compact)` reads the same
/// whether `.compact` is an enum case or a static on a protocol extension.
///
/// A backend advertises what it can draw in `supportedDatePickerStyles`, and
/// ``SwiftCrossUI/View/datePickerStyle(_:)`` substitutes ``automatic`` for
/// anything missing from that list, saying so once through the logger.
public enum BackendDatePickerStyle: Sendable, Hashable {
    /// A date input that adapts to the current platform and context.
    ///
    /// Supported by every backend, and the one anything unsupported falls back
    /// to.
    case automatic

    /// A date input that shows a calendar grid.
    ///
    /// Supported by AppKitBackend, UIKitBackend, WinUIBackend and GtkBackend,
    /// and by AndroidBackend on API levels that have the material date picker.
    @available(iOS 14, macCatalyst 14, *)
    case graphical

    /// A smaller date input. This may be a text field, or a button that opens a calendar pop-up.
    ///
    /// Supported by AppKitBackend, UIKitBackend, WinUIBackend, AndroidBackend
    /// and GtkBackend. GtkBackend draws the second of those shapes: a
    /// `GtkMenuButton` whose popover holds a `GtkCalendar`.
    @available(iOS 13.4, macCatalyst 13.4, *)
    case compact

    /// A set of scrollable inputs that can be used to select a date.
    ///
    /// Supported by UIKitBackend, WinUIBackend, and GtkBackend on hosts where
    /// this case exists -- see ``DateWheel``. Not by AppKitBackend or
    /// AndroidBackend.
    ///
    /// This said "Not by GtkBackend, which has no wheel widget of any kind"
    /// until f704f304 implemented it and left the sentence behind.
    @available(iOS 13.4, macCatalyst 13.4, *)
    @available(macOS, unavailable)
    case wheel
}
