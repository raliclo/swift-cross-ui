/// A picker style that presents the options as a group of radio buttons.
///
/// Supported by every backend.
public struct RadioGroupPickerStyle: PickerStyle, _BuiltinPickerStyle {
    public nonisolated init() {}

    public func _asBackendPickerStyle<Backend: BaseAppBackend>(backend: Backend)
        -> BackendPickerStyle
    {
        .radioGroup
    }
}

extension PickerStyle where Self == RadioGroupPickerStyle {
    /// A picker style that presents the options as a group of radio buttons.
    ///
    /// Supported by every backend.
    public static nonisolated var radioGroup: Self { Self() }
}
