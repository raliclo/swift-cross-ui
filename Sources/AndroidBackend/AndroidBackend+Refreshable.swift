import AndroidKit
import AndroidView
@_spi(Backends) import SwiftCrossUI
import SwiftJava

/// A refresh affordance for this backend's `ScrollContainer`.
///
/// **Not `SwipeRefreshLayout`, and that was checked rather than assumed.** The
/// androidx class is the conventional answer and it is not on AndroidKit's
/// classpath -- no `SwipeRefresh*` source exists in the checkout, and this
/// backend has already had one runtime `ClassNotFoundException` from a class
/// that looked present at compile time (see `AndroidBackend+Toolbar.swift`).
/// Reaching for it again would compile, build an APK, and die on launch.
///
/// `ScrollContainer` extends `FrameLayout`, so a button added to it floats
/// above the scrolling content at the top-left without disturbing the layout of
/// what it covers. That is the same shape AppKitBackend uses, for the same
/// reason: an affordance that can actually be pressed beats a gesture that
/// reports success on a platform where it never fires.
///
/// 給本 backend 的 `ScrollContainer` 使用的重新整理操作方式。
///
/// **不是 `SwipeRefreshLayout`,而這是查過的、不是假設的。** 那個 androidx 類別是慣例上的答案,而它
/// 不在 AndroidKit 的 classpath 上——checkout 中不存在任何 `SwipeRefresh*` 原始碼——而本 backend 已經
/// 因為一個「編譯期看起來存在」的類別吃過一次執行期的 `ClassNotFoundException`
/// (見 `AndroidBackend+Toolbar.swift`)。再伸手去拿它,結果會是:編譯過、APK 建起來、一啟動就死。
///
/// `ScrollContainer` 繼承自 `FrameLayout`,因此加進去的按鈕會浮在捲動內容之上、位於左上角,而不會
/// 擾亂它所覆蓋之物的版面。那與 AppKitBackend 採用的形狀相同,理由也相同:一個真的按得下去的操作
/// 方式,勝過一個「在它從不觸發的平台上仍回報成功」的手勢。
extension AndroidBackend {
    public func setRefreshHandler(
        ofScrollContainer scrollView: Widget,
        to handler: (@MainActor @Sendable () -> Void)?
    ) {
        guard let container = scrollView.as(ScrollContainer.self) else { return }

        let existing = Self.refreshButtons[container.javaHolder.object!.hashValue]

        guard let handler else {
            if let existing {
                container.removeView(existing)
                Self.refreshButtons[container.javaHolder.object!.hashValue] = nil
            }
            return
        }

        // The listener is replaced on an existing button rather than the button
        // being rebuilt. `updateScrollContainer` runs on every state change,
        // including the ones the refresh action itself causes, and a button
        // removed and re-added on each of those flickers.
        // 在既有按鈕上替換 listener,而不是重建那顆按鈕。`updateScrollContainer` 在每一次狀態改變時
        // 都會執行——包括那些由 refresh 動作本身所引起的——而一顆在每次都被移除再加回去的按鈕會閃爍。
        let button = existing ?? {
            let button = AndroidKit.Button(Self.activity, environment: Self.env)
            button.setText(Self.charSequence(from: "Refresh"))
            button.setAllCaps(false)
            container.addView(button)
            Self.refreshButtons[container.javaHolder.object!.hashValue] = button
            return button
        }()

        button.setOnClickListener(
            ViewOnClickListener(action: { handler() }, environment: Self.env)
                .as(AndroidView.View.OnClickListener.self)
        )
    }

    /// Keyed by the container's Java identity, because a `Widget` here is a
    /// handle rather than an object with storage of its own.
    /// 以容器的 Java 身分為索引鍵,因為此處的 `Widget` 是一個握把,而不是一個自帶儲存空間的物件。
    nonisolated(unsafe) static var refreshButtons: [Int: AndroidKit.Button] = [:]
}
