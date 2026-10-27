/// The toggle shapes a backend can be asked for directly.
///
/// Like ``BackendPickerStyle`` and ``BackendDatePickerStyle``, it is the
/// vocabulary a backend implements; ``ToggleStyle`` is the protocol an
/// application writes against, and what lets it write a style of its own.
///
/// Each case is served by its own opt-in backend feature --
/// ``BackendFeatures/Switches``, ``BackendFeatures/ToggleButtons`` and
/// ``BackendFeatures/Checkboxes`` -- which is why a backend can offer some and
/// not others.
public enum BackendToggleStyle: Sendable, Hashable {
    /// A toggle switch.
    case `switch`
    /// A toggle button. Generally looks like a regular button when off and an
    /// accented button when on.
    case button
    /// A checkbox.
    case checkbox
}
