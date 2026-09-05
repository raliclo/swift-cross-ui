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
    /// direction, and offers the two ways of looking at it.
    ///
    /// The construction lives in `RootScrollHost.kt`. It was written here in
    /// Swift first, and the version that lived here was wrong in a way this
    /// file's own comment could not see: it added the content with
    /// `MATCH_PARENT` in both axes, which pins a scroll view's child to exactly
    /// the viewport and leaves nothing to scroll. Measured on 2026-09-05, both
    /// scroll views reported `scrollable=false` on P35, P39, P41 and P43, and a
    /// 900-pixel swipe on P35 moved zero pixels.
    ///
    /// Moved to Kotlin rather than fixed in place, because what actually closes
    /// the gap is measuring the laid-out subtree -- reading `x`, `y`, `width`
    /// and `height` off every descendant and taking the union including the
    /// negative half -- and then re-laying out around it. That is a `ViewGroup`
    /// with its own `onMeasure` and `onLayout`, and a draggable control on top
    /// of it, none of which is expressible as a call sequence from here.
    ///
    /// 包裹 `content`，使它在任一方向上都可以大於視窗，並提供觀看它的兩種方式。
    ///
    /// 實際的構造位於 `RootScrollHost.kt`。它原本是以 Swift 寫在此處的，而那個版本錯在一個「本檔
    /// 自己的註解看不見」的地方：它以兩軸皆 `MATCH_PARENT` 加入內容，而那會把捲動視圖的子元件釘死在
    /// 視口大小上，於是沒有任何東西可捲。2026-09-05 實測：P35、P39、P41、P43 上兩層捲動視圖都回報
    /// `scrollable=false`，而在 P35 上滑動 900 像素，畫面一個像素也沒有改變。
    ///
    /// 之所以搬到 Kotlin 而不是就地修正，是因為真正填補這個缺口的做法是「量測已排版的子樹」——讀取
    /// 每一個後代的 `x`、`y`、`width`、`height` 並取其聯集（含負的那一半）——然後圍繞該結果重新排版。
    /// 那需要一個具備自身 `onMeasure` 與 `onLayout` 的 `ViewGroup`，其上再加一個可拖曳的控制項，
    /// 而這些都無法以「從此處發出的一串呼叫」來表達。
    static func wrap(
        _ content: AndroidView.View,
        activity: Activity,
        environment: JNIEnvironment?,
        showModeControl: Bool
    ) -> AndroidView.View {
        let host = RootScrollHost(
            activity.as(AndroidContent.Context.self),
            environment: environment
        )
        host.host(content)
        if showModeControl {
            host.installModeButton(activity)
        }
        return host.as(AndroidView.View.self)!
    }
}
