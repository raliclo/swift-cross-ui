import Foundation

/// A built-in date picker style backed by a backend-supported date input.
///
/// The counterpart of ``_BuiltinPickerStyle``. Conforming supplies both of
/// ``DatePickerStyle``'s requirements: the view is the backend's own widget,
/// and support is whether the backend listed this shape in
/// `supportedDatePickerStyles`.
public protocol _BuiltinDatePickerStyle {
    @MainActor
    func _asBackendDatePickerStyle<Backend: BaseAppBackend>(backend: Backend)
        -> BackendDatePickerStyle
}

extension DatePickerStyle where Self: _BuiltinDatePickerStyle {
    public func makeView(
        selection: Binding<Date>,
        range: ClosedRange<Date>,
        components: DatePickerComponents,
        environment: EnvironmentValues
    ) -> _BuiltinDatePickerImplementation {
        _BuiltinDatePickerImplementation(
            style: _asBackendDatePickerStyle(backend: environment.backend),
            selection: selection,
            range: range,
            components: components
        )
    }

    public func isSupported<Backend: BaseAppBackend>(backend: Backend) -> Bool {
        // The cast is needed and `_BuiltinPickerStyle`'s equivalent is not,
        // because `supportedPickerStyles` is on `Core` while date pickers are
        // an opt-in feature. `EnvironmentValues` does the same cast for the
        // same reason.
        //
        // A backend without the feature supports nothing. `.automatic` is not
        // an exception: there is no date picker to be automatic about, and
        // `DatePicker` aborts at its `@CastBackend` before a style matters.
        //
        // 此處需要 cast、而 `_BuiltinPickerStyle` 的對應版本不需要，因為 `supportedPickerStyles`
        // 位於 `Core` 上，而日期選擇器是選用功能。`EnvironmentValues` 基於同樣的理由做了同樣的
        // cast。
        //
        // 未具備此功能的 backend 不支援任何 style，`.automatic` 也不例外：根本沒有日期選擇器可以
        // 「自動」，而 `DatePicker` 會在其 `@CastBackend` 處先行中止，輪不到 style 起作用。
        // Not shadowing `backend` with the cast result: the existential does
        // not satisfy `BaseAppBackend`, which is a composition of every feature
        // protocol, so `_asBackendDatePickerStyle` must still receive the
        // generic parameter. Shadowing it asked the compiler for twenty
        // conformances at once.
        // 不用 cast 的結果去遮蔽 `backend`：該 existential 並不滿足 `BaseAppBackend`——後者是所有
        // feature protocol 的組合——因此 `_asBackendDatePickerStyle` 仍必須收到原本的泛型參數。
        // 遮蔽它會讓編譯器一口氣要求二十個 conformance。
        guard let datePickers = backend as? any BackendFeatures.DatePickers else {
            return false
        }
        return datePickers.supportedDatePickerStyles.contains(
            _asBackendDatePickerStyle(backend: backend)
        )
    }
}
