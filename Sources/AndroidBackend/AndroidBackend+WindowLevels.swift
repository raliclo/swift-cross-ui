import AndroidKit
import SwiftJava

@_spi(Backends) import SwiftCrossUI

/// `windowLevel(_:)` on Android.
///
/// `WindowLevel.floating` is defined as "above every other window, including
/// other applications', and staying there without needing focus". On Android
/// that is `TYPE_APPLICATION_OVERLAY`, and getting there took four experiments,
/// three of which failed. `OverlayService.kt` records them; the short version is
/// that the window was never the hard part and the app's *process state* was.
///
/// **Two things gate it, and both are the platform's price rather than a choice
/// made here.** `SYSTEM_ALERT_WINDOW` is granted by the user in Settings, so
/// `supportedWindowLevels` is computed rather than constant -- a list claiming
/// `.floating` on a device where the user said no would be a promise this
/// backend cannot keep. And the window has to be owned by a foreground service,
/// which means an app that floats shows a notification.
///
/// **One limit, measured and not ours.** A screen that sets
/// `HIDE_NON_SYSTEM_OVERLAY_WINDOWS` on its window hides every non-system
/// overlay while it is in front; Settings does, which is why testing against it
/// produced three misleading runs. Verified 2026-09-04 by reading the flag off
/// Settings' own window in `dumpsys window windows`, and by watching the same
/// overlay stay visible over an ordinary app. It applies to every app on the
/// platform and cannot be opted out of.
///
/// Android 上的 `windowLevel(_:)`。
///
/// `WindowLevel.floating` 的定義是「位於所有其他視窗之上——包含其他應用程式的——並且無需取得焦點
/// 即可停留在那裡」。在 Android 上那就是 `TYPE_APPLICATION_OVERLAY`，而走到這一步用了四次實驗，
/// 其中三次失敗。`OverlayService.kt` 記錄了它們；簡短的版本是：難的從來不是那個視窗，而是該 app
/// 的**行程狀態**。
///
/// **有兩件事管制它，而兩者都是平台的定價，不是此處所做的選擇。** `SYSTEM_ALERT_WINDOW` 由使用者
/// 在「設定」中授予，因此 `supportedWindowLevels` 是計算出來的、而非常數——在使用者拒絕的裝置上仍
/// 宣稱 `.floating`，會是這個 backend 兌現不了的承諾。而該視窗必須由一個 foreground service 持有，
/// 這意味著一支會浮動的 app 會顯示一則通知。
///
/// **一項限制，是量出來的，而且不屬於我們。** 任何在自己視窗上設定
/// `HIDE_NON_SYSTEM_OVERLAY_WINDOWS` 的畫面，在它位於前景時會隱藏所有非系統的 overlay；「設定」
/// 就是這樣的畫面，而那正是以它作為測試對象時產生三次誤導性結果的原因。2026-09-04 驗證方式：從
/// `dumpsys window windows` 中讀出「設定」自身視窗上的該旗標，並觀察同一個 overlay 在一支普通 app
/// 之上維持可見。它適用於平台上的每一支 app，且無法選擇退出。
extension AndroidBackend: BackendFeatures.WindowLevels {
    public nonisolated var supportedWindowLevels: [WindowLevel] {
        // Read from the lock rather than asked of the platform, because this is
        // `nonisolated` and the permission check needs the activity. Computed
        // in `init()` for the reason `resolveDeviceClass` is: `EnvironmentValues`
        // captures it once, before `computeRootEnvironment` runs.
        //
        // 從那個 lock 讀取，而不是去問平台，因為這是 `nonisolated` 的，而權限檢查需要 activity。
        // 它在 `init()` 中計算，理由與 `resolveDeviceClass` 相同：`EnvironmentValues` 只擷取一次，
        // 而那早於 `computeRootEnvironment` 執行。
        _supportedWindowLevels.withLock { copy $0 }
    }

    public func setLevel(ofWindow window: Window, to level: WindowLevel) {
        let floating = level == .floating
        let applied = helpers.setWindowFloating(Self.activity, floating)

        if floating && !applied {
            // Only reachable if the permission was revoked between `init` and
            // here, since `supportedWindowLevels` would not have offered
            // `.floating` otherwise and SwiftCrossUI substitutes `.normal` for
            // a level a backend does not list.
            //
            // 只有在權限於 `init` 與此處之間被撤銷時才可能走到；否則 `supportedWindowLevels` 不會
            // 提供 `.floating`，而 SwiftCrossUI 會把 backend 未列出的層級替換為 `.normal`。
            log(
                "windowLevel(.floating) could not be applied: the overlay "
                    + "permission is no longer held. The window stays at its "
                    + "normal level."
            )
        }
    }
}
