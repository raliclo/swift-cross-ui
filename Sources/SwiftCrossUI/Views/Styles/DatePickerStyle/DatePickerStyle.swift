import Foundation

/// A type that specifies the appearance and interaction of all date pickers
/// within a view hierarchy.
///
/// Shaped after ``PickerStyle``, which is shaped after SwiftUI. The point of
/// the protocol, rather than an enum of the built-in cases, is that a style can
/// be written outside this module: `struct MyStyle: DatePickerStyle` compiles
/// against SwiftUI and until 2026-08-27 did not compile here.
///
/// A style that maps onto a widget the backend already has should also conform
/// to ``_BuiltinDatePickerStyle``, which supplies ``makeView(selection:range:components:environment:)``
/// and the support check for free. The four built-in styles do exactly that.
@MainActor
public protocol DatePickerStyle: Sendable {
    associatedtype Body: View

    /// The method used to render ``DatePicker``.
    /// - Parameters:
    ///   - selection: A binding to the currently-selected date.
    ///   - range: The range of dates to offer. A hint rather than a guarantee;
    ///     backends are not required to enforce it.
    ///   - components: Which parts of the date and time to show.
    ///   - environment: The environment the date picker is being rendered in.
    func makeView(
        selection: Binding<Date>,
        range: ClosedRange<Date>,
        components: DatePickerComponents,
        environment: EnvironmentValues
    ) -> Body

    /// Whether this style can be drawn by a given backend.
    ///
    /// The default implementation returns `true`, because a style written
    /// outside this module draws itself out of ordinary views and so needs
    /// nothing in particular from the backend.
    /// - Parameter backend: The backend being queried for support.
    func isSupported<Backend: BaseAppBackend>(backend: Backend) -> Bool
}

extension DatePickerStyle {
    public func isSupported<Backend: BaseAppBackend>(backend: Backend) -> Bool {
        // Custom date picker styles are supported on all platforms by default.
        true
    }
}
