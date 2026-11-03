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

    /// The value last assigned to a `@State` whose tween is still running, or
    /// `nil` when none is. Read inside `withAnimation`; see
    /// `StateImpl.wrappedValue`.
    /// 補間仍在進行之 `@State` 最後被賦予的值;沒有補間時為 `nil`。在 `withAnimation` 內讀取;見
    /// `StateImpl.wrappedValue`。
    var animationTarget: Any?

    var value: V

    init(_ value: V) {
        self.value = value
    }
}
