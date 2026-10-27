import AndroidKit
import SwiftJava

@_spi(Backends) import SwiftCrossUI

/// `allowsHitTesting` on Android.
///
/// Without this conformance the modifier's `@CastBackend` expands to
/// `fatalError`: P10 died at launch with "'AndroidBackend' does not implement
/// 'BackendFeatures.HitTesting'".
///
/// The work is in `HitTesting.kt`; that file explains why refusing a touch and
/// consuming one are different, and why P10 can tell them apart.
///
/// Android 上的 `allowsHitTesting`。
///
/// 少了此 conformance,該 modifier 的 `@CastBackend` 會展開為 `fatalError`:P10 曾在啟動時死於
/// 「'AndroidBackend' does not implement 'BackendFeatures.HitTesting'」。
///
/// 實作位於 `HitTesting.kt`；該檔說明了「拒收觸控」與「吃掉觸控」為何不同，以及 P10 為何分辨得出來。
extension AndroidBackend: BackendFeatures.HitTesting {
    public func setHitTesting(of widget: Widget, to allowsHitTesting: Bool) {
        helpers.setHitTesting(widget, allowsHitTesting)
    }
}
