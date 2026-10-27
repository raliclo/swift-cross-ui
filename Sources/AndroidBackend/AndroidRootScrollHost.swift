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
/// same content and the same screens.
///
/// A window that went blank after a widening state change was traced to
/// `WindowReference.update`, not to a missing host (`bugs/bug-Android.md`,
/// 2026-09-03); the host is kept for the reason UIKitBackend has it.
///
/// 讓「比視窗大的內容」有地方可去。
///
/// UIKitBackend 會把每個視窗的根子元件放進一個捲動視圖，因為本樹中的測試 app 是以桌面寬度繪製的，
/// 而手機顯示不下——碰不到的內容就是測不到的內容。Android 有同樣的內容、同樣的螢幕。
///
/// 「內容變寬的狀態變更後視窗變空白」的成因最後查明在 `WindowReference.update`,而不是缺少這個宿主
/// (`bugs/bug-Android.md`,2026-09-03);本機制因與 UIKitBackend 相同的理由而保留。
enum AndroidRootScrollHost {
    /// Wraps `content` so that it can be larger than the window in either
    /// direction, and offers the two ways of looking at it.
    ///
    /// The construction lives in `RootScrollHost.kt`. Adding the content with
    /// `MATCH_PARENT` in both axes pins a scroll view's child to exactly the
    /// viewport and leaves nothing to scroll (measured 2026-09-05: both scroll
    /// views reported `scrollable=false` on P35, P39, P41 and P43). What makes
    /// it scrollable is measuring the laid-out subtree -- reading `x`, `y`,
    /// `width` and `height` off every descendant and taking the union including
    /// the negative half -- and then re-laying out around it. That is a
    /// `ViewGroup` with its own `onMeasure` and `onLayout`, and a draggable
    /// control on top of it, none of which is expressible as a call sequence
    /// from here.
    ///
    /// 包裹 `content`，使它在任一方向上都可以大於視窗，並提供觀看它的兩種方式。
    ///
    /// 實際的構造位於 `RootScrollHost.kt`。以兩軸皆 `MATCH_PARENT` 加入內容,會把捲動視圖的子元件釘死在
    /// 視口大小上,於是沒有任何東西可捲(2026-09-05 實測:P35、P39、P41、P43 上兩層捲動視圖都回報
    /// `scrollable=false`)。讓它能捲動的做法是「量測已排版的子樹」——讀取每一個後代的 `x`、`y`、`width`、
    /// `height` 並取其聯集(含負的那一半)——然後圍繞該結果重新排版。那需要一個具備自身 `onMeasure` 與
    /// `onLayout` 的 `ViewGroup`,其上再加一個可拖曳的控制項,而這些都無法以「從此處發出的一串呼叫」來表達。
    static func wrap(
        _ content: AndroidView.View,
        activity: Activity,
        environment: JNIEnvironment?,
        showModeControl: Bool,
        onHost: (RootScrollHost) -> Void = { _ in }
    ) -> AndroidView.View {
        let host = RootScrollHost(
            activity.as(AndroidContent.Context.self),
            environment: environment
        )
        host.host(content)
        onHost(host)
        if showModeControl {
            host.installModeButton(activity)
        }
        return host.as(AndroidView.View.self)!
    }
}
