/// The launch behavior for a scene.
public enum SceneLaunchBehavior: Sendable {
    /// SwiftCrossUI decides, as SwiftUI does: the first window scene of the app
    /// is shown on launch and the others are not, unless some scene is marked
    /// ``presented`` -- then only the marked ones are.
    case automatic
    /// The scene will be shown on app launch.
    case presented
    /// The scene will not be shown on app launch.
    case suppressed
}
