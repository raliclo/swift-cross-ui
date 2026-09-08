/// A type that specifies the appearance and interaction of all text fields
/// within a view hierarchy.
///
/// ## This is deliberately not SwiftUI's `TextFieldStyle`
///
/// SwiftUI's `TextFieldStyle` is a **closed, empty** protocol: it declares no
/// requirements, and its documentation says conforming types are provided by
/// the framework. An application cannot usefully write
/// `struct MyStyle: TextFieldStyle` there -- there is nothing to implement, and
/// nothing would call it if there were.
///
/// This one is open, and shaped like ``ToggleStyle``, ``PickerStyle`` and
/// ``DatePickerStyle`` in this package: it has a ``makeView(placeholder:text:environment:)``
/// requirement, ``TextField`` routes through it, and a style written outside
/// this module renders. The four built-in styles cover SwiftUI's set by also
/// conforming to ``_BuiltinTextFieldStyle``, which supplies both requirements
/// from a single ``BackendTextFieldStyle`` value.
///
/// The reason to diverge is that a closed protocol is the one thing this
/// package's style tree does not do. Every other style here is open, for the
/// same reason recorded on ``DatePickerStyle``: `struct MyStyle: DatePickerStyle`
/// compiles against SwiftUI and, until it was opened, did not compile here.
/// `TextFieldStyle` is the inverse case -- it does not usefully compile against
/// SwiftUI either -- and matching that limitation would have been the only
/// place in the tree where an application is told "no".
///
/// ## 這刻意不是 SwiftUI 的 `TextFieldStyle`
///
/// SwiftUI 的 `TextFieldStyle` 是一個**封閉且空白**的 protocol：它沒有宣告任何需求，其文件說明遵循
/// 它的型別由框架提供。應用程式在那裡寫 `struct MyStyle: TextFieldStyle` 沒有任何意義——沒有東西可
/// 實作，就算有也沒有人會呼叫它。
///
/// 此處這個是開放的，形狀比照本套件中的 ``ToggleStyle``、``PickerStyle`` 與 ``DatePickerStyle``：
/// 它帶有 ``makeView(placeholder:text:environment:)`` 需求，``TextField`` 經由它繪製，而在本模組
/// 之外撰寫的 style 確實會被算繪。四個內建 style 藉由同時遵循 ``_BuiltinTextFieldStyle`` 來涵蓋
/// SwiftUI 的那一組，該 protocol 從單一個 ``BackendTextFieldStyle`` 值供應兩項需求。
///
/// 之所以要偏離，是因為「封閉的 protocol」正是本套件樣式樹唯一不做的事。此處其他每一個 style 都是
/// 開放的，理由記於 ``DatePickerStyle``：`struct MyStyle: DatePickerStyle` 在 SwiftUI 下可編譯，
/// 而在被開放之前，於此處不可編譯。`TextFieldStyle` 是相反的案例——它在 SwiftUI 下也不能有意義地被
/// 實作——若照抄該限制，這裡就會成為整棵樹中唯一對應用程式說「不行」的地方。
@MainActor
public protocol TextFieldStyle: Sendable {
    associatedtype Body: View

    /// The method used to render ``TextField``.
    ///
    /// - Parameters:
    ///   - placeholder: The label to show while the field is empty.
    ///   - text: A binding to the field's content.
    ///   - environment: The environment the text field is being rendered in.
    ///
    /// The placeholder is a `String` rather than a view for the reason recorded
    /// on ``ToggleStyle``: ``TextField``'s own initialiser takes one, and
    /// changing that is a separate piece of work.
    ///
    /// 佔位文字是 `String` 而非 view，理由記於 ``ToggleStyle``：``TextField`` 自身的建構式收到的
    /// 就是字串，要改變這一點是另一件獨立的工作。
    func makeView(
        placeholder: String,
        text: Binding<String>,
        environment: EnvironmentValues
    ) -> Body

    /// Whether this style can be drawn by a given backend.
    ///
    /// The default implementation returns `true`, because a style written
    /// outside this module draws itself out of ordinary views and so needs
    /// nothing in particular from the backend.
    ///
    /// The four built-in styles also answer `true`, and unlike
    /// ``PickerStyle``'s that is not a shortcut -- see
    /// ``_BuiltinTextFieldStyle`` for why there is no
    /// `supportedTextFieldStyles` list to consult.
    ///
    /// - Parameter backend: The backend being queried for support.
    func isSupported<Backend: BaseAppBackend>(backend: Backend) -> Bool
}

extension TextFieldStyle {
    public func isSupported<Backend: BaseAppBackend>(backend: Backend) -> Bool {
        // Custom text field styles are supported on all platforms by default.
        true
    }
}
