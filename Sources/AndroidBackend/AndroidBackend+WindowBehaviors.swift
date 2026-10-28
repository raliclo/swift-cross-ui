import AndroidKit
import SwiftJava

@_spi(Backends) import SwiftCrossUI

/// `windowDismissBehavior`, `preferredWindowMinimizeBehavior` and
/// `windowResizeBehavior` on Android. The work is in Kotlin
/// (`Kotlin/WindowBehaviors.kt`); this file records what each behaviour maps to
/// and what was measured on the API 36 emulator (api36b, Android 16).
///
/// **closable.** An Android window has no close button; the user closes it
/// with Back -- the key, or the back gesture. A window that is not closable
/// has an enabled `OnBackPressedCallback` that consumes Back, so the activity
/// is neither finished (a window after the first) nor sent to the background
/// (the first, a launcher activity, which Android 12 and later move to the
/// back rather than finish). AndroidBackend had no Back handling of its own
/// before this, and `NavigationStack` is not driven by Back on Android, so
/// nothing else is displaced. Sheets and popovers are separate windows with
/// their own Back handling and still close. Measured with
/// `testapp/test_support/p113_back_android.zsh`: the Back key and an edge-swipe
/// back gesture left P113's first window and its second window in front; with
/// "closable" on, Back closed the second and sent the first to the background.
///
/// **minimizable.** Home cannot be intercepted: an activity hears about it
/// only afterwards, through `onUserLeaveHint`. What Android does offer is lock
/// task mode. Without device-owner status, `startLockTask()` is screen
/// pinning, measured on the emulator: the system showed "App is pinned" with
/// "No thanks" and "Got it"; before confirming, Home sent the app to the
/// background (`onUserLeaveHint`, `onStop`); after "Got it",
/// `mLockTaskModeState=PINNED` and Home left the app as the top resumed
/// activity. So a window that is not minimizable asks to be pinned, and the
/// user decides; the system's own unpin gesture stays available. Set back to
/// minimizable, the window calls `stopLockTask()`: measured
/// `mLockTaskModeState=NONE`, and Home then brought up the launcher.
///
/// **resizable.** Resizability is the manifest attribute
/// `android:resizeableActivity`. Measured with freeform windowing enabled
/// (`settings put global enable_freeform_support 1`): an activity declaring
/// it false, started with `am start --windowingMode 5`, opened full screen
/// (task `nonResizable`, `mode=fullscreen`), and `am task resize` on it logged
/// "resizeTask not allowed"; the same activity without the attribute opened
/// free-form and `am task resize` moved it to the requested bounds. No API
/// changes the attribute at runtime: the API 36 `android.jar` has, on
/// `Activity`, `ActivityOptions`, `Window` and `ActivityManager.AppTask`, only
/// `requestFullscreenMode`, `setLaunchBounds`/`getLaunchBounds` and
/// `setResizingCaptionDrawable`, and `WindowManager`'s resizeability property
/// (`PROPERTY_COMPAT_ALLOW_RESIZEABLE_ACTIVITY_OVERRIDES`) is a manifest
/// opt-in to device-maker overrides. So:
///
/// - a window after the first that is not resizable when it opens starts as
///   `ScuiFixedSizeWindowActivity`, declared non-resizable in the manifest;
/// - any window that is not resizable -- the first, whose activity is the
///   app's launcher activity, and a later window whose behaviour changes after
///   it opened -- leaves a free-form window with
///   `Activity.requestFullscreenMode` (API 34), now and whenever it enters
///   multi-window mode again, as the system does with a non-resizable activity.
///   Measured: requested from a free-form launch, the task went from
///   `mode=freeform` to `mode=fullscreen`, both at launch and when P113 was
///   started resizable (`--p113-resizable`) in a free-form window and then
///   switched to non-resizable there. P113's second window opened as
///   `ScuiFixedSizeWindowActivity` with `RESIZE_MODE_UNRESIZEABLE`, and
///   `am task resize` on its task logged "resizeTask not allowed".
///
/// On API 31-33 (`min_sdk` is 31) `requestFullscreenMode` does not exist; there
/// the first window, and a later one changed after it opened, are left where
/// they are and a warning is logged. Only API 36 was measured.
///
/// Android 上的 `windowDismissBehavior`、`preferredWindowMinimizeBehavior` 與 `windowResizeBehavior`。
/// 實作在 Kotlin(`Kotlin/WindowBehaviors.kt`);本檔記錄每項行為對應到什麼，以及在 API 36 emulator
/// (api36b,Android 16)上量到什麼。
///
/// **closable。** Android 視窗沒有關閉鈕；使用者以返回——按鍵或返回手勢——關閉它。不可關閉的視窗有一個
/// 啟用中的 `OnBackPressedCallback` 吃掉返回，因此 activity 既不會被結束(第一個之後的視窗),也不會被送到背景
/// (第一個視窗是 launcher activity,Android 12 以後會把它移到背景而非結束)。在此之前 AndroidBackend 沒有自己的返回
/// 處理，而 Android 上的 `NavigationStack` 也不由返回驅動，所以沒有其他東西被擠掉。sheet 與 popover 是有自己返回
/// 處理的獨立視窗，仍然會關閉。以 `testapp/test_support/p113_back_android.zsh` 實測：返回鍵與邊緣滑動的返回手勢都讓 P113 的
/// 第一個與第二個視窗留在前景;「closable」打開後，返回關閉了第二個視窗，並把第一個送到背景。
///
/// **minimizable。** Home 無法攔截:activity 只能在事後經由 `onUserLeaveHint` 得知。Android 提供的是 lock task
/// 模式。沒有 device owner 身分時,`startLockTask()` 就是螢幕固定，在 emulator 上實測：系統顯示「App is pinned」與
/// 「No thanks」「Got it」;確認之前按 Home 會把 app 送到背景(`onUserLeaveHint`、`onStop`);按「Got it」之後,
/// `mLockTaskModeState=PINNED`,按 Home 後 app 仍是最上層的 resumed activity。所以不可最小化的視窗會要求被固定，由使用者
/// 決定；系統自己的取消固定手勢仍然可用。改回可最小化時，視窗呼叫 `stopLockTask()`:實測 `mLockTaskModeState=NONE`,之後按 Home
/// 會出現 launcher。
///
/// **resizable。** 可縮放性是 manifest 屬性 `android:resizeableActivity`。在啟用 freeform 視窗
/// (`settings put global enable_freeform_support 1`)下實測：宣告為 false 的 activity 以
/// `am start --windowingMode 5` 啟動時開成全螢幕(工作為 `nonResizable`、`mode=fullscreen`),對它執行
/// `am task resize` 會記錄「resizeTask not allowed」;同一個 activity 不加此屬性時開成自由視窗,`am task resize`
/// 把它移到要求的範圍。沒有任何 API 能在執行期改變這個屬性:API 36 的 `android.jar` 中,`Activity`、`ActivityOptions`、
/// `Window` 與 `ActivityManager.AppTask` 上只有 `requestFullscreenMode`、`setLaunchBounds`/`getLaunchBounds` 與
/// `setResizingCaptionDrawable`,而 `WindowManager` 的可縮放性屬性(`PROPERTY_COMPAT_ALLOW_RESIZEABLE_ACTIVITY_OVERRIDES`)
/// 是 manifest 中允許裝置廠商覆寫的選項。因此：
///
/// - 開啟時就不可縮放的後續視窗，以 manifest 中宣告為不可縮放的 `ScuiFixedSizeWindowActivity` 啟動；
/// - 任何不可縮放的視窗——第一個(其 activity 是 app 的 launcher activity),以及開啟後才改變行為的後續視窗——
///   以 `Activity.requestFullscreenMode`(API 34)離開自由視窗，當下以及之後每次再進入多視窗模式時皆然，與系統對
///   不可縮放 activity 的處理相同。實測：從自由視窗啟動後提出要求，工作由 `mode=freeform` 變為 `mode=fullscreen`;P113 以可縮放
///   (`--p113-resizable`)在自由視窗中啟動、再於該處改為不可縮放時亦然。P113 的第二個視窗以 `ScuiFixedSizeWindowActivity`、
///   `RESIZE_MODE_UNRESIZEABLE` 開啟，對其工作執行 `am task resize` 會記錄「resizeTask not allowed」。
///
/// API 31-33(`min_sdk` 為 31)沒有 `requestFullscreenMode`;在那裡第一個視窗，以及開啟後才改變的後續視窗，會維持原處並記錄警告。
/// 只量測過 API 36。
extension AndroidBackend: BackendFeatures.WindowBehaviors {
    public func setBehaviors(
        ofWindow window: Window,
        closable: Bool,
        minimizable: Bool,
        resizable: Bool
    ) {
        guard let behaviors = try? JavaClass<ScuiWindowBehaviors>() else {
            log("ScuiWindowBehaviors is missing from the APK; window behaviours not applied")
            return
        }
        if let token = window.token {
            behaviors.setForToken(token, closable, minimizable, resizable)
        } else {
            behaviors.setForActivity(Self.activity, closable, minimizable, resizable)
        }
    }
}

/// See Kotlin/WindowBehaviors.kt. 見 Kotlin/WindowBehaviors.kt。
@JavaClass("dev.swiftcrossui.androidbackend.ScuiWindowBehaviors")
class ScuiWindowBehaviors: JavaObject {}

extension JavaClass<ScuiWindowBehaviors> {
    @JavaStaticMethod
    func setForActivity(_ activity: Activity?, _ closable: Bool, _ minimizable: Bool, _ resizable: Bool)

    @JavaStaticMethod
    func setForToken(_ token: String, _ closable: Bool, _ minimizable: Bool, _ resizable: Bool)
}
