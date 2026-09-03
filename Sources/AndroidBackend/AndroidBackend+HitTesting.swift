import AndroidKit
import SwiftJava

@_spi(Backends) import SwiftCrossUI

/// `allowsHitTesting` on Android.
///
/// Before this file `AndroidBackend` was the only shipped backend without the
/// conformance, and the modifier goes through `@CastBackend`, which expands to
/// `fatalError`. P10 did not fail a check on Android -- it died at launch with
/// "'AndroidBackend' does not implement 'BackendFeatures.HitTesting'" and
/// ActivityManager gave up on it as having "crashed too many times". One
/// modifier took the whole app down, which is the outcome this repository's
/// rules exist to prevent.
///
/// The work is in `HitTesting.kt`; that file explains why refusing a touch and
/// consuming one are different, and why P10 can tell them apart.
///
/// Android 上的 `allowsHitTesting`。
///
/// 在本檔存在之前，`AndroidBackend` 是唯一未實作此 conformance 的已發布 backend，而該 modifier
/// 走的是 `@CastBackend`——它會展開為 `fatalError`。P10 在 Android 上並不是「某項檢查沒過」，而是
/// 直接在啟動時死於「'AndroidBackend' does not implement 'BackendFeatures.HitTesting'」，接著
/// ActivityManager 以「crashed too many times」放棄了它。一個 modifier 拖垮了整個 app，而那正是
/// 本倉庫的規則所要防止的結果。
///
/// 實作位於 `HitTesting.kt`；該檔說明了「拒收觸控」與「吃掉觸控」為何不同，以及 P10 為何分辨得出來。
extension AndroidBackend: BackendFeatures.HitTesting {
    public func setHitTesting(of widget: Widget, to allowsHitTesting: Bool) {
        helpers.setHitTesting(widget, allowsHitTesting)
    }
}
