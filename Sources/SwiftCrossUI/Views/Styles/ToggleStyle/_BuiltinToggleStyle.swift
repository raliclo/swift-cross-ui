/// A built-in toggle style backed by a control the backend already has.
///
/// Each of the three lands on a different opt-in backend feature, so support is
/// asked per style rather than answered once for toggles as a whole: a backend
/// may have ``BackendFeatures/Switches`` and not ``BackendFeatures/Checkboxes``.
///
/// 三者各自落在不同的選用 backend 功能上，因此「是否支援」是逐一詢問，而非對「toggle」整體回答
/// 一次：某個 backend 可能有 ``BackendFeatures/Switches`` 卻沒有 ``BackendFeatures/Checkboxes``。
public protocol _BuiltinToggleStyle {
    @MainActor
    func _asBackendToggleStyle<Backend: BaseAppBackend>(backend: Backend) -> BackendToggleStyle
}

extension ToggleStyle where Self: _BuiltinToggleStyle {
    public func makeView(
        label: String,
        isOn: Binding<Bool>,
        environment: EnvironmentValues
    ) -> _BuiltinToggleImplementation {
        _BuiltinToggleImplementation(
            style: _asBackendToggleStyle(backend: environment.backend),
            label: label,
            isOn: isOn
        )
    }

    public func isSupported<Backend: BaseAppBackend>(backend: Backend) -> Bool {
        switch _asBackendToggleStyle(backend: backend) {
            case .switch:
                backend is any BackendFeatures.Switches
            case .button:
                backend is any BackendFeatures.ToggleButtons
            case .checkbox:
                backend is any BackendFeatures.Checkboxes
        }
    }
}
