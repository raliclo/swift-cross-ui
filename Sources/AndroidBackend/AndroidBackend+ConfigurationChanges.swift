import AndroidKit
import Foundation
@_spi(Backends) import SwiftCrossUI
import SwiftJava

/// Rotation, light/dark, density and font-scale changes, handled in place.
///
/// **Until 2026-10-06 every one of these restarted the app.** The manifest
/// declared no `configChanges`, so Android destroyed and recreated the activity
/// on each, and `setup()` ran the Swift app again inside the same process --
/// measured with P78 on the emulator: two URLs received, rotate, "received 0",
/// same PID. The three handlers this file now serves -- `setResizeHandler`,
/// `setRootEnvironmentChangeHandler`, `setWindowEnvironmentChangeHandler` --
/// were upstream's empty TODOs, which is why nothing could have noticed the
/// change without the restart.
///
/// The manifest (testapp/package_android.zsh) now declares the changes, so the
/// activity stays and `onConfigurationChanged` arrives through an
/// `ActivityListener`. The text-size cache is cleared first, because the font
/// scale is one of the things that changed.
///
/// 旋轉、深淺色、密度與字體縮放的變更，原地處理。**2026-10-06 之前，這些每一項都會讓 app 重新啟動。**
/// manifest 沒有宣告 `configChanges`,所以 Android 每次都銷毀並重建 activity,而 `setup()` 在同一個行程內
/// 再跑一次 Swift app——以 P78 在 emulator 上實測：收到兩個 URL、旋轉，變成「received 0」,PID 相同。本檔
/// 現在服務的三個處理器原本都是上游的空 TODO,所以除了重啟之外沒有任何東西能察覺變更。manifest 現已宣告
/// 這些變更，activity 會留下,`onConfigurationChanged` 經由 `ActivityListener` 抵達。先清掉文字大小快取，
/// 因為字體縮放也是變更的項目之一。
extension AndroidBackend {
    nonisolated(unsafe) static var resizeHandler: ((SIMD2<Int>) -> Void)?
    nonisolated(unsafe) static var rootEnvironmentChangeHandler: (@MainActor () -> Void)?
    nonisolated(unsafe) static var windowEnvironmentChangeHandler: (@MainActor () -> Void)?
    nonisolated(unsafe) static var didInstallConfigurationListener = false

    func installConfigurationListener() {
        guard !Self.didInstallConfigurationListener else { return }
        Self.didInstallConfigurationListener = true
        _ = ActivityListener(
            Self.activity.as(FragmentActivity.self)!,
            SwiftObject(ConfigurationListener(backend: self), environment: Self.env),
            environment: Self.env
        )
    }

    func configurationDidChange() {
        helpers.clearTextSizeCache()
        Self.rootEnvironmentChangeHandler?()
        Self.windowEnvironmentChangeHandler?()
        Self.resizeHandler?(size(ofWindow: Window()))
    }
}

/// Hands `onConfigurationChanged` to the backend.
/// 把 `onConfigurationChanged` 交給 backend。
///
/// `@unchecked Sendable` as `ActivityListener` is: it is only ever called on
/// the main thread, from the activity's callbacks.
/// `@unchecked Sendable`,與 `ActivityListener` 相同：它只會在主執行緒上、從 activity 的回呼被呼叫。
final class ConfigurationListener: ActivityDelegate, @unchecked Sendable {
    let backend: AndroidBackend

    init(backend: AndroidBackend) {
        self.backend = backend
    }

    func onConfigurationChanged(
        for activity: FragmentActivity,
        to configuration: AndroidKit.Configuration,
        env: JNIEnvironment?
    ) {
        MainActor.assumeIsolated {
            backend.configurationDidChange()
        }
    }
}
