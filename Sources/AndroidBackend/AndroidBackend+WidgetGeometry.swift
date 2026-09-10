import AndroidKit
import SwiftCrossUI

extension AndroidBackend: BackendFeatures.WidgetGeometry {
    /// Walks up the view tree adding `getLeft()` and `getTop()`.
    ///
    /// **NOT `getLocationInWindow`, and the reason is a JNI one.** That method
    /// is bound as `getLocationInWindow(_ arg0: [Int32])` -- Java writes the
    /// answer INTO the array, and a Swift `[Int32]` passed to it is a value the
    /// bridge copies. Whether the copy is written back is exactly the kind of
    /// thing that returns two zeros without any error, and this machine cannot
    /// run Android to find out. `getLeft()` and `getTop()` return `Int32` by
    /// value, so there is nothing to be wrong about.
    ///
    /// The walk stops at the first parent that is not a `View`, which is the
    /// window's own decor -- so what this returns is a position in the WINDOW,
    /// which is what ``SwiftCrossUI/CoordinateSpace/global`` asks for.
    ///
    /// **未編譯於此(2026-09-10)。** 這台機器上的 Android SDK 模組是以 Swift 6.3.3 編出來的，
    /// 而編譯器是 6.4，因此 `compile.zsh -android` 在抵達本檔之前就失敗了。要查的是:
    /// `ViewParent.as(View.self)` 是否為有效的轉換(此處假設它是，因為 `AndroidBackend.swift:258`
    /// 以同樣的 `.as(_:)` 形式轉換 activity)。
    ///
    /// 沿著 view 樹往上走，累加 `getLeft()` 與 `getTop()`。
    ///
    /// **不用 `getLocationInWindow`，而理由是一個 JNI 的理由。** 那個方法被綁定為
    /// `getLocationInWindow(_ arg0: [Int32])`——Java 把答案**寫進**那個陣列，而傳給它的 Swift
    /// `[Int32]` 是一個會被橋接層複製的值。那份複製會不會被寫回，正是那種「回傳兩個零、而且不報任何
    /// 錯」的事情，而這台機器跑不了 Android 來查明它。`getLeft()` 與 `getTop()` 以值回傳 `Int32`，
    /// 沒有任何地方可以出錯。
    ///
    /// 這趟走訪止於第一個不是 `View` 的父節點，也就是視窗自身的 decor——因此它回傳的是一個位於
    /// **視窗**中的位置，那正是 ``SwiftCrossUI/CoordinateSpace/global`` 所要的。
    public func originInWindow(ofWidget widget: Widget) -> SIMD2<Int>? {
        // `Widget` IS the `View` here -- `AndroidBackend.swift:139` says
        // `typealias Widget = AndroidKit.View` -- so there is nothing to unwrap,
        // unlike the UIKit half where a `Widget` owns a view.
        // 此處 `Widget` **就是** `View`——`AndroidBackend.swift:139` 寫著
        // `typealias Widget = AndroidKit.View`——因此沒有東西需要解開，這與「`Widget` 持有一個 view」
        // 的 UIKit 那一半不同。
        let view = widget

        var x: Int32 = 0
        var y: Int32 = 0
        var current: AndroidKit.View? = view
        var hops = 0
        while let node = current, hops < 64 {
            x += node.getLeft()
            y += node.getTop()
            current = node.getParent()?.as(View.self)
            hops += 1
        }
        // A view that has never been attached reports zero for every hop, which
        // is indistinguishable from one at the corner. `getParent()` being nil
        // on the FIRST hop is the signal that it is not in a tree at all.
        // 一個從未被附加過的 view，每一跳都回報零——那與一個位於角落的 view 無從分辨。真正的訊號是
        // 「**第一跳**的 `getParent()` 就是 nil」，那代表它根本不在任何樹裡。
        guard view.getParent() != nil else { return nil }
        return SIMD2(Int(x), Int(y))
    }
}
