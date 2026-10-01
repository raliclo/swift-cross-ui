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
        guard view.getParent() != nil else { return nil }

        // Positions are read from what SwiftCrossUI SET, not from where Android
        // last laid the view out. `setPosition` writes a CustomContainer
        // LayoutParams and Android applies it on its NEXT layout pass, so
        // `getLeft()`/`getTop()` asked during the update that placed a view
        // still say 0 -- P63 read "global: x=0 y=0" on every run (2026-10-01).
        // The pending LayoutParams are the position SwiftCrossUI computed;
        // `getLeft()`/`getTop()` are used only for views it did not place
        // (the activity's own decor). Pixels, scaled back to points at the end,
        // and a scrolling parent's offset is subtracted so that `.global`
        // follows the content as it scrolls.
        // 位置讀自 SwiftCrossUI **設定**的值，而不是 Android 上一次排版的結果。`setPosition` 寫入的是
        // CustomContainer 的 LayoutParams,Android 要到**下一次**排版才套用，所以在放置某 view 的那次
        // 更新中詢問 `getLeft()`/`getTop()`,得到的仍是 0——P63 每次都讀到 "global: x=0 y=0"
        // (2026-10-01)。待套用的 LayoutParams 就是 SwiftCrossUI 算出的位置;`getLeft()`/`getTop()`
        // 只用於它沒有放置的 view(activity 自身的 decor)。單位是像素，最後換回點;捲動中父節點的位移
        // 會被扣除，好讓 `.global` 隨內容捲動。
        var x: Int32 = 0
        var y: Int32 = 0
        var current: AndroidKit.View? = view
        var hops = 0
        while let node = current, hops < 64 {
            if let params = node.getLayoutParams()?.as(CustomContainer.LayoutParams.self) {
                x += params.getX()
                y += params.getY()
            } else {
                x += node.getLeft()
                y += node.getTop()
            }
            current = node.getParent()?.as(View.self)
            if let parent = current {
                x -= parent.getScrollX()
                y -= parent.getScrollY()
            }
            hops += 1
        }
        let density = view.getResources().getDisplayMetrics().density
        return SIMD2(
            Int((Float(x) / density).rounded()),
            Int((Float(y) / density).rounded())
        )
    }
}
