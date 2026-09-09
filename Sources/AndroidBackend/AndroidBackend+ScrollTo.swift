import AndroidKit
import AndroidView
@_spi(Backends) import SwiftCrossUI
import SwiftJava

extension AndroidBackend {
    /// Scrolls a container so that one of its descendants is visible.
    ///
    /// **Through a Kotlin method, not from Swift.** `ScrollContainer`'s two
    /// scroll views are `private val` and conditionally attached
    /// (`isVerticalScrollViewAdded` / `isHorizontalScrollViewAdded`), so Swift
    /// cannot reach the object that has to move. `scrollToChild` is added on the
    /// Kotlin side and does nothing when the axis it would scroll is not
    /// mounted -- a no-op is right there, because a container with no vertical
    /// scroll view has no vertical position to take.
    ///
    /// That is a limit on adding VIEWS to this container, not on adding methods.
    /// The `getChildAt(0)` assumption recorded in `AndroidBackend+Refreshable.swift`
    /// is about the former.
    ///
    /// 捲動某個容器,使它的某個子孫可見。
    ///
    /// **透過 Kotlin method,而不是從 Swift。** `ScrollContainer` 的兩個捲動視圖是 `private val`,
    /// 且是條件性掛載的(`isVerticalScrollViewAdded` / `isHorizontalScrollViewAdded`),因此 Swift
    /// 碰不到那個必須移動的物件。`scrollToChild` 加在 Kotlin 那一側,並在「它要捲的那個軸沒有被掛載」
    /// 時什麼都不做——在那裡 no-op 是正確的,因為一個沒有垂直捲動視圖的容器,並沒有垂直位置可取。
    ///
    /// 那是對「往這個容器**加 view**」的限制,不是對「加 method」的限制。記錄在
    /// `AndroidBackend+Refreshable.swift` 中的 `getChildAt(0)` 假設講的是前者。
    public func scrollContainer(
        _ scrollView: Widget,
        to child: Widget,
        anchor: UnitPoint?
    ) {
        guard let container = scrollView.as(ScrollContainer.self) else { return }
        // `-1` for "no anchor", because a Kotlin `Float?` across JNI costs a
        // boxed object for a value that has exactly one absent case. Named on
        // both sides rather than left as a magic number at one end.
        // 以 `-1` 表示「沒有 anchor」,因為跨 JNI 的 Kotlin `Float?` 會為一個「只有一種缺席情況」的值
        // 付出一個 boxed 物件的代價。兩側都具名,而不是只在一端留下一個魔術數字。
        container.scrollToChild(
            child,
            anchor.map { Float($0.x) } ?? -1,
            anchor.map { Float($0.y) } ?? -1
        )
    }
}

extension ScrollContainer {
    @JavaMethod
    func scrollToChild(_ child: AndroidView.View?, _ anchorX: Float, _ anchorY: Float)
}
