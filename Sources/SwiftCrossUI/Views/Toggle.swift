/// A control for toggling between two values (usually representing on and off).
///
/// Depending on the value of ``EnvironmentValues/toggleStyle``, this control
/// can appear as a switch, a button, or a checkbox.
public struct Toggle: View {
    @Environment(\.self) var environment
    @Environment(\.toggleStyle) var toggleStyle

    /// The label to be shown on or beside the toggle.
    var label: String
    /// Whether the toggle is active or not.
    var active: Binding<Bool>

    @available(*, deprecated, renamed: "init(_:isOn:)")
    public init(_ label: String, active: Binding<Bool>) {
        self.init(label, isOn: active)
    }

    /// Creates a toggle that displays a custom label.
    ///
    /// - Parameters:
    ///   - label: The label to be shown on or beside the toggle.
    ///   - active: Whether the toggle is active or not.
    public init(_ label: String, isOn active: Binding<Bool>) {
        self.label = label
        self.active = active
    }

    public var body: some View {
        // Routed through the style, as `Picker` and `DatePicker` are. What used
        // to be here is now `_BuiltinToggleImplementation`, reached by the three
        // built-in styles; a style written outside this module draws whatever it
        // likes instead. `AnyView` because the style is existential and its
        // `Body` is not known here.
        //
        // 交由 style 繪製，與 `Picker`、`DatePicker` 相同。原本位於此處的內容現在是
        // `_BuiltinToggleImplementation`，由三個內建 style 取用；而在本模組之外撰寫的 style 則
        // 想畫什麼就畫什麼。使用 `AnyView`，因為此處的 style 是 existential，其 `Body` 型別在這裡
        // 無從得知。
        AnyView(
            toggleStyle.makeView(
                label: label,
                isOn: active,
                environment: environment
            )
        )
    }

    public var _asMenuItems: [MenuItem] {
        [.toggle(self)]
    }
}

// `ToggleStyle` used to be a struct here, with three static members and a
// nested `@_spi(Backends) enum Style`. It is now a protocol in
// Views/Styles/ToggleStyle/, and that nested enum lives on as
// `BackendToggleStyle` in Backend/.
// `ToggleStyle` 過去是此處的一個 struct，帶有三個 static 成員與一個巢狀的
// `@_spi(Backends) enum Style`。它現已成為 Views/Styles/ToggleStyle/ 中的 protocol，而那個巢狀
// enum 則以 `BackendToggleStyle` 之名存續於 Backend/ 之中。
