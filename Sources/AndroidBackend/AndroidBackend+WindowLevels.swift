import AndroidKit
import SwiftJava

@_spi(Backends) import SwiftCrossUI

/// `windowLevel(_:)` on Android.
///
/// Before this file AndroidBackend did not conform to
/// `BackendFeatures.WindowLevels` at all, and a backend that does not conform
/// gets `[.automatic, .normal]` from `EnvironmentValues` anyway -- so the
/// visible behaviour is unchanged and what this adds is that the list is now
/// this backend's own statement rather than a fallback, and that `setLevel` is
/// a place where a level can be acted on.
///
/// **`.floating` is not offered, and that is a measured result rather than an
/// assumption.** Two APIs were tried on 2026-09-04, on the API 36 emulator with
/// SYSTEM_ALERT_WINDOW granted through `appops`:
///
/// - `Window.setType(TYPE_APPLICATION_OVERLAY)` on the activity's own window.
///   Compiles, runs, reports nothing, does nothing: Settings launched over P37
///   covered it completely and `dumpsys window` showed Settings focused. An
///   activity's window type is assigned when the activity is attached and is
///   not a property it can change afterwards.
/// - Detaching the content view and adding it to the `WindowManager` as a
///   `TYPE_APPLICATION_OVERLAY` window. This produces a real overlay --
///   `dumpsys window windows` listed `Sys2038:...p37` at #6 against Settings at
///   #9, `mViewVisibility=0`, `fillxfill`, appop SYSTEM_ALERT_WINDOW -- and it
///   draws nothing. Re-assigning MATCH_PARENT layout params and calling
///   `requestLayout()`/`invalidate()` after `addView` did not change that. The
///   window is in front and empty, which is worse than not floating.
///
/// So the remaining work is making SwiftCrossUI's tree render in a window that
/// is not the activity's, which is a real piece of work and not a missing call.
/// Recorded in bugs/bug-Android.md. What is *not* done here is claiming
/// `.floating` and hoping: a backend that lists a level it cannot deliver is
/// worse than one that lists two it can, because the app has no way to find out.
///
/// Android 上的 `windowLevel(_:)`。
///
/// 在本檔存在之前，AndroidBackend 根本沒有實作 `BackendFeatures.WindowLevels`，而一個未實作的
/// backend 本來就會從 `EnvironmentValues` 得到 `[.automatic, .normal]`——因此外顯行為並未改變；
/// 本檔所增加的是：這份清單現在是這個 backend 自己的陳述，而非一個後備值，且 `setLevel` 成為一個
/// 「可以對某個層級採取行動」的位置。
///
/// **不提供 `.floating`，而那是一個實測結果，不是一個假設。** 2026-09-04 於 API 36 emulator 上、
/// 並以 `appops` 授予 SYSTEM_ALERT_WINDOW 的情況下，嘗試過兩個 API：
///
/// - 在 activity 自己的視窗上呼叫 `Window.setType(TYPE_APPLICATION_OVERLAY)`。能編譯、能執行、
///   不回報任何東西，也什麼都不做：啟動於 P37 之上的「設定」把它完全覆蓋，而 `dumpsys window`
///   顯示焦點在「設定」。activity 的視窗型別是在 activity 被 attach 時指派的，並非它事後可以更改
///   的屬性。
/// - 把內容 view 分離，並以 `TYPE_APPLICATION_OVERLAY` 加入 `WindowManager`。這確實產生了一個真正
///   的 overlay——`dumpsys window windows` 把 `Sys2038:...p37` 列在 #6，而「設定」在 #9，
///   `mViewVisibility=0`、`fillxfill`、appop 為 SYSTEM_ALERT_WINDOW——而它什麼都不畫。在 `addView`
///   之後重新指派 MATCH_PARENT 的 layout params 並呼叫 `requestLayout()`/`invalidate()`，也沒有改變
///   這一點。該視窗在最前面而且是空的，那比「不浮動」更糟。
///
/// 因此剩下的工作，是讓 SwiftCrossUI 的樹在「不屬於 activity 的視窗」中完成繪製——那是一件實在的
/// 工作，不是少呼叫了某個方法。已記錄於 bugs/bug-Android.md。此處**沒有**做的事，是一邊宣稱
/// `.floating` 一邊期待它成立：一個列出自己無法兌現之層級的 backend，比一個只列出兩個做得到的更糟，
/// 因為 app 沒有任何辦法察覺。
extension AndroidBackend: BackendFeatures.WindowLevels {
    public nonisolated var supportedWindowLevels: [WindowLevel] {
        [.automatic, .normal]
    }

    public func setLevel(ofWindow window: Window, to level: WindowLevel) {
        // Only levels from `supportedWindowLevels` arrive here -- SwiftCrossUI
        // substitutes `.normal` for anything else and says so once -- and both
        // of the two mean "where an activity normally sits", which is where it
        // already is.
        //
        // 只有來自 `supportedWindowLevels` 的層級會抵達此處——SwiftCrossUI 會把其他層級替換為
        // `.normal` 並提示一次——而那兩個層級的意思都是「一個 activity 平常所在的位置」，
        // 而它已經在那裡了。
        _ = (window, level)
    }
}
