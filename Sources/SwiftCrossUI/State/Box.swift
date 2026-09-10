import Foundation

/// A simple wrapper used to implement internal mutability.
///
/// Mostly used by dynamic property wrappers (see ``DynamicProperty``).
final class Box<V> {
    /// Identifies this box to ``AnimationDriver``.
    ///
    /// On the box because the box is what survives a view being rebuilt; see
    /// `StateImpl.animationKey`.
    /// 放在 box 上，因為在 view 被重建時存活下來的正是 box;見 `StateImpl.animationKey`。
    let animationKey = UUID()

    var value: V

    init(_ value: V) {
        self.value = value
    }
}
