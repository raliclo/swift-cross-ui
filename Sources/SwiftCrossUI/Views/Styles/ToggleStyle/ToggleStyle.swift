/// A type that specifies the appearance and interaction of all toggles within a
/// view hierarchy.
///
/// Shaped after ``PickerStyle`` and ``DatePickerStyle``. A style that maps onto
/// a control the backend already has should also conform to
/// ``_BuiltinToggleStyle``, which supplies both requirements; the three built-in
/// styles do.
///
/// The label is a `String` rather than a view, which is not this protocol's
/// choice: ``Toggle`` takes one, as ``Button`` does. SwiftUI hands a style its
/// label as a view, and matching that needs arbitrary labels on the control
/// first -- `Button` carries a `_buttonWidth` workaround whose comment says as
/// much.
///
/// 標籤是 `String` 而非 view，這並非本 protocol 的選擇：``Toggle`` 收到的就是字串，``Button``
/// 亦然。SwiftUI 交給 style 的標籤是一個 view，要與之對齊，得先讓這些控制項支援任意標籤——
/// `Button` 上那個 `_buttonWidth` 暫解的註解正說明了這件事。
@MainActor
public protocol ToggleStyle: Sendable {
    associatedtype Body: View

    /// The method used to render ``Toggle``.
    /// - Parameters:
    ///   - label: The text to show on or beside the toggle.
    ///   - isOn: A binding to whether the toggle is currently on.
    ///   - environment: The environment the toggle is being rendered in.
    func makeView(
        label: String,
        isOn: Binding<Bool>,
        environment: EnvironmentValues
    ) -> Body

    /// Whether this style can be drawn by a given backend.
    ///
    /// The default implementation returns `true`, because a style written
    /// outside this module draws itself out of ordinary views.
    /// - Parameter backend: The backend being queried for support.
    func isSupported<Backend: BaseAppBackend>(backend: Backend) -> Bool
}

extension ToggleStyle {
    public func isSupported<Backend: BaseAppBackend>(backend: Backend) -> Bool {
        // Custom toggle styles are supported on all platforms by default.
        true
    }
}
