import AndroidApp
import AndroidContent
import AndroidView
import AndroidWidget
import Foundation
import SwiftJava

@_spi(Backends) import SwiftCrossUI

/// Somewhere for content larger than the window to go.
///
/// UIKitBackend hosts every window's root child in a scroll view, because the
/// test apps in this tree are drawn at desktop widths and a phone cannot show
/// them -- content you cannot reach is content you cannot test. Android has the
/// same content and the same screens, and it had no such host: the root
/// container went straight into `setContentView`.
///
/// **On Android the symptom is worse than unreachable content.** Measured on
/// the emulator 2026-09-02 and 2026-09-03: a state change that makes the
/// content need more width empties the whole window. Nine presses of P12's
/// "Increment counter" left the page intact at 378953 non-white pixels and the
/// tenth, where the number needs a second digit, took it to 0. Pressing a tab
/// button or anything with a longer status line did the same.
/// `adb shell input tap` did it too, so it was never the action-file machinery.
///
/// **This is a well-motivated experiment and not a diagnosis.** The cause of
/// the blanking has not been established. What is established is that
/// `setSize(ofWindow:)` warns and does nothing here, that the app logs
/// "Attempted to set size of Android window" as it happens, and that a scroll
/// view is the one parent whose job is to accept a child larger than itself. If
/// the window is failing because the layout asked for a size it cannot have,
/// this gives the layout somewhere to put the overflow instead. If the blanking
/// survives, the cause is elsewhere and this is still worth having for the
/// reason UIKitBackend has it.
///
/// 讓「比視窗大的內容」有地方可去。
///
/// UIKitBackend 會把每個視窗的根子元件放進一個捲動視圖，因為本樹中的測試 app 是以桌面寬度繪製的，
/// 而手機顯示不下——碰不到的內容就是測不到的內容。Android 有同樣的內容、同樣的螢幕，卻沒有這樣的
/// 宿主：根容器是直接進入 `setContentView` 的。
///
/// **在 Android 上，症狀比「內容碰不到」更糟。** 2026-09-02 與 2026-09-03 於 emulator 上實測：
/// 一個「讓內容需要更多寬度」的狀態變更會清空整個視窗。按 P12 的「Increment counter」九次，頁面
/// 完好、非白像素 378953；第十次——數字需要第二位數時——降為 0。按分頁按鈕、或按任何會讓狀態文字
/// 變長的東西，結果相同。`adb shell input tap` 也一樣，因此這從來就不是動作檔機制的問題。
///
/// **這是一個有充分動機的實驗，而不是一個診斷。** 清空的成因尚未確立。已確立的是：
/// `setSize(ofWindow:)` 在此處只會警告、不做任何事；該 app 會在事發時記錄
/// 「Attempted to set size of Android window」；而捲動視圖正是「以接受比自己更大的子元件為職責」
/// 的那種父容器。若該視窗是因為「版面要求了一個它不可能取得的尺寸」而失敗，這就給了版面一個安放
/// 溢出的地方。若清空依然發生，則成因在別處——而本機制仍然值得保留，理由與 UIKitBackend 相同。
enum AndroidRootScrollHost {
    /// Wraps `content` so that it can be larger than the window in either
    /// direction.
    ///
    /// A `HorizontalScrollView` around a `ScrollView` is how Android is scrolled
    /// in two directions; neither does both. The outer one is horizontal
    /// because that is the axis this tree's content overflows on -- desktop
    /// widths on a phone -- so a horizontal drag is the one that reaches the
    /// gesture first.
    ///
    /// `fillViewport` on both, or a child smaller than the screen is laid out at
    /// its own size and floats at the top left instead of filling the window,
    /// which would change every existing Android screenshot for the apps that
    /// do fit.
    ///
    /// 包裹 `content`，使它在任一方向上都可以大於視窗。
    ///
    /// 「`HorizontalScrollView` 包住 `ScrollView`」是 Android 達成雙向捲動的方式；兩者都不會自己
    /// 做兩個方向。外層採用水平，因為那正是本樹內容溢出的軸向——手機上的桌面寬度——因此水平拖曳會
    /// 先接到手勢。
    ///
    /// 兩者都設定 `fillViewport`，否則比螢幕小的子元件會以它自己的尺寸排版並浮在左上角，而不是填滿
    /// 視窗；那會改變所有「本來就塞得下」的 app 的既有截圖。
    static func wrap(
        _ content: AndroidView.View,
        activity: Activity,
        environment: JNIEnvironment?
    ) -> AndroidView.View {
        let matchParent = try! JavaClass<ViewGroup.LayoutParams>().MATCH_PARENT

        let vertical = AndroidWidget.ScrollView(activity, environment: environment)
        vertical.setFillViewport(true)
        vertical.addView(
            content,
            ViewGroup.LayoutParams(matchParent, matchParent, environment: environment)
        )

        let horizontal = AndroidWidget.HorizontalScrollView(activity, environment: environment)
        horizontal.setFillViewport(true)
        horizontal.addView(
            vertical.as(AndroidView.View.self)!,
            ViewGroup.LayoutParams(matchParent, matchParent, environment: environment)
        )

        return horizontal.as(AndroidView.View.self)!
    }
}
