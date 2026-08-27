/// The toggle shapes a backend can be asked for directly.
///
/// The third of these, after ``BackendPickerStyle`` and
/// ``BackendDatePickerStyle``, and it came from the tidiest of the three
/// starting points: `ToggleStyle` was already a struct with static members and
/// a nested `@_spi(Backends) enum Style`, so the split between "what an
/// application writes" and "what a backend implements" was drawn before the
/// protocol existed. Only the protocol was missing, and with it the ability to
/// write a style of one's own.
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
