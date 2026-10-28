/// A type that specifies the appearance and interaction of all toggles within a
/// view hierarchy.
///
/// Shaped after ``PickerStyle`` and ``DatePickerStyle``. A style that maps onto
/// a control the backend already has should also conform to
/// ``_BuiltinToggleStyle``, which supplies both requirements; the three built-in
/// styles do.
///
/// A ``Toggle`` with a string label is drawn by
/// ``makeView(label:isOn:environment:)``; one with a view label by
/// ``makeView(label:labelText:isOn:environment:)``, whose default hands the
/// label's text to the string form, so a style written against strings keeps
/// working for both. A style that wants to draw the view label itself
/// implements the second requirement too.
///
/// 以字串為標籤的 ``Toggle`` 由 ``makeView(label:isOn:environment:)`` 繪製；以 view 為標籤的則由
/// ``makeView(label:labelText:isOn:environment:)`` 繪製，其預設實作把標籤的文字交給字串形式，因此以字串撰寫的
/// style 對兩者都繼續有效。想自己繪製 view 標籤的 style 也實作第二個要求即可。
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

    /// The method used to render a ``Toggle`` whose label is a view.
    ///
    /// The default implementation draws
    /// ``makeView(label:isOn:environment:)`` with `labelText`.
    /// - Parameters:
    ///   - label: The view to show on or beside the toggle.
    ///   - labelText: The text found in `label`, joined by spaces.
    ///   - isOn: A binding to whether the toggle is currently on.
    ///   - environment: The environment the toggle is being rendered in.
    ///
    /// 用來繪製「標籤為 view 的 ``Toggle``」的方法。預設實作以 `labelText` 繪製 ``makeView(label:isOn:environment:)``。
    func makeView(
        label: AnyView,
        labelText: String,
        isOn: Binding<Bool>,
        environment: EnvironmentValues
    ) -> AnyView

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

    public func makeView(
        label: AnyView,
        labelText: String,
        isOn: Binding<Bool>,
        environment: EnvironmentValues
    ) -> AnyView {
        AnyView(makeView(label: labelText, isOn: isOn, environment: environment))
    }
}
