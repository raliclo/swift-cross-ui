import Foundation

/// A simple wrapper used to implement internal mutability.
///
/// Mostly used by dynamic property wrappers (see ``DynamicProperty``).
final class Box<V> {
    /// The tween state of the `@State` this box holds the storage of. A
    /// `var`, because a box made when the view is rebuilt adopts the previous
    /// box's; see `StateImpl.animationKey`.
    /// 這個 box 所持有之 `@State` 的補間狀態。是 `var`,因為 view 重建時建立的 box 會沿用前一個 box 的那一份;
    /// 見 `StateImpl.animationKey`。
    var animation = StateAnimation()

    /// Identifies this storage to ``AnimationDriver``. 向 ``AnimationDriver`` 標識這份儲存。
    var animationKey: UUID { animation.key }

    /// The value last assigned to a `@State` whose tween is still running, or
    /// `nil` when none is. Read inside `withAnimation`; see
    /// `StateImpl.wrappedValue`.
    /// 補間仍在進行之 `@State` 最後被賦予的值;沒有補間時為 `nil`。在 `withAnimation` 內讀取;見
    /// `StateImpl.wrappedValue`。
    var animationTarget: Any? {
        get { animation.target }
        set { animation.target = newValue }
    }

    var value: V

    init(_ value: V) {
        self.value = value
    }
}

/// A `@State`'s tween: the key it runs under and the value it is heading for.
/// A class, so the boxes a storage passes through share one rather than copies.
/// 一個 `@State` 的補間：它執行時所用的 key,以及它前往的值。是 class,讓 storage 經過的各個 box 共用同一份，而非複本。
final class StateAnimation {
    let key = UUID()
    var target: Any?
}
