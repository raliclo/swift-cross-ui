import AndroidKit
import SwiftJava

@_spi(Backends) import SwiftCrossUI

/// `clipped()` on Android.
///
/// Before this file AndroidBackend did not conform, and the modifier goes
/// through `@CastBackend`, which expands to `fatalError`. Nothing in this tree
/// had noticed, because no test app used `clipped()` on Android; P44 was
/// written alongside this file so that something does.
///
/// **Conforming is not the same as implementing here either.** The protocol's
/// default `createClippedContainer()` returns an ordinary container, so a
/// backend can conform, stop crashing, and clip nothing -- the shape this
/// repository's rules exist to prevent, and one this particular protocol makes
/// especially easy to reach by accident.
///
/// The pairing with `CustomContainer`'s `clipChildren = false` is deliberate
/// and the two have to be read together. Android clips a child to its parent by
/// default and the other backends do not, so the default was turned off to stop
/// transformed views being cut (see P40 and bug-Android.md); this turns it back
/// on for exactly the container that was asked to clip. Same arrangement as
/// UIKitBackend, where `clipsToBounds` is false on a `UIView` and true on a
/// clipped container.
///
/// Android 上的 `clipped()`。
///
/// 在本檔存在之前，AndroidBackend 並未實作此 conformance，而該 modifier 走的是 `@CastBackend`
/// ——它會展開為 `fatalError`。本樹中沒有任何東西察覺到這件事，因為沒有任何測試 app 在 Android 上
/// 使用過 `clipped()`；P44 是與本檔一同撰寫的，好讓「有東西」用到它。
///
/// **在此處，「符合 conformance」同樣不等於「實作」。** 該 protocol 的預設 `createClippedContainer()`
/// 回傳的是一個普通容器，因此一個 backend 可以符合 conformance、不再崩潰，然後什麼都不裁切
/// ——那正是本倉庫的規則所要防止的形狀，而這個特定的 protocol 使人格外容易在無意間走到那裡。
///
/// 與 `CustomContainer` 的 `clipChildren = false` 成對，這是刻意的，兩者必須一起讀。Android 預設會
/// 把子元件裁切到父元件範圍內，而其他 backend 不會，因此該預設被關掉，以免被變換過的 view 遭到裁切
/// （見 P40 與 bug-Android.md）；而此處為「確實被要求裁切的那一個容器」把它重新開啟。與
/// UIKitBackend 的安排相同：`UIView` 上的 `clipsToBounds` 為 false，而在 clipped container 上為 true。
extension AndroidBackend: BackendFeatures.Clipping {
    public func createClippedContainer() -> Widget {
        let container = createContainer()
        let clipped = container.as(CustomContainer.self)!
        clipped.setClipChildren(true)
        clipped.setClipToPadding(true)
        return container
    }
}
