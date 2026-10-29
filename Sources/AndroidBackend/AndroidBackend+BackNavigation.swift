import AndroidKit
import SwiftJava

@_spi(Backends) import SwiftCrossUI

/// `BackendFeatures.BackNavigation` on Android: the system Back key and the
/// back gesture pop the innermost `NavigationStack` that has anything pushed.
/// The callback and its place among the activity's other Back handling are in
/// Kotlin (`Kotlin/BackNavigation.kt`).
///
/// While no stack can pop, SwiftCrossUI removes the handler and Back is left
/// exactly as it was before this feature: it finishes a window after the
/// first, sends the first to the background, or meets the `closable` blocker
/// of `AndroidBackend+WindowBehaviors.swift`. While a stack can pop, Back pops
/// it first, and the blocker applies again once every stack is at its root.
/// Sheets are dialogs with their own Back and are not affected.
///
/// Android 上的 `BackendFeatures.BackNavigation`:系統返回鍵與返回手勢彈出推入了內容的最內層 `NavigationStack`。callback
/// 及其在 activity 其他返回處理之間的位置在 Kotlin 中(`Kotlin/BackNavigation.kt`)。
///
/// 沒有堆疊可彈出時,SwiftCrossUI 會移除 handler,返回維持此 feature 之前的原樣：結束第一個之後的視窗、把第一個送到背景，
/// 或遇上 `AndroidBackend+WindowBehaviors.swift` 的 `closable` 攔截。有堆疊可彈出時，返回先彈出它；每個堆疊都回到根層後，
/// 攔截再次生效。sheet 是有自己返回處理的 dialog,不受影響。
extension AndroidBackend: BackendFeatures.BackNavigation {
    public func setBackNavigationHandler(
        ofWindow window: Window,
        to action: (@MainActor () -> Bool)?
    ) {
        guard let navigation = try? JavaClass<ScuiBackNavigation>() else {
            log("ScuiBackNavigation is missing from the APK; Back does not pop NavigationStack")
            return
        }
        let callback = action.map { action in
            SwiftAction(environment: Self.env) {
                if !action() {
                    navigation.notHandled()
                }
            }
        }
        if let token = window.token {
            navigation.setForToken(token, callback)
        } else {
            navigation.setForActivity(Self.activity, callback)
        }
    }
}
/// `BackendFeatures.SheetBackNavigation` on Android: a sheet is a Material bottom
/// sheet dialog with its own `OnBackPressedDispatcher`, and the callback goes
/// there (`Kotlin/CustomSheet.kt`). The activity never sees Back while the
/// dialog is in front, so the window's stacks are out of reach; with no stack
/// in the sheet able to pop, Back cancels the sheet only if it is dismissable,
/// as it did before.
///
/// Android 上的 `BackendFeatures.SheetBackNavigation`:sheet 是有自己 `OnBackPressedDispatcher` 的 Material bottom sheet
/// dialog,callback 掛在那裡(`Kotlin/CustomSheet.kt`)。dialog 在前景時 activity 收不到返回，因此視窗的堆疊碰不到；sheet
/// 中沒有可彈出的堆疊時，返回只在 sheet 可關閉時取消它，與以往相同。
extension AndroidBackend: BackendFeatures.SheetBackNavigation {
    public func setBackNavigationHandler(
        ofSheet sheet: Sheet,
        to action: (@MainActor () -> Bool)?
    ) {
        let navigation = try? JavaClass<ScuiBackNavigation>()
        sheet.setBackNavigationAction(
            action.map { action in
                SwiftAction(environment: Self.env) {
                    if !action() {
                        navigation?.notHandled()
                    }
                }
            }
        )
    }
}


/// See Kotlin/BackNavigation.kt. 見 Kotlin/BackNavigation.kt。
@JavaClass("dev.swiftcrossui.androidbackend.ScuiBackNavigation")
class ScuiBackNavigation: JavaObject {}

extension JavaClass<ScuiBackNavigation> {
    @JavaStaticMethod
    func setForActivity(_ activity: Activity?, _ action: SwiftAction?)

    @JavaStaticMethod
    func setForToken(_ token: String, _ action: SwiftAction?)

    @JavaStaticMethod
    func notHandled()
}
