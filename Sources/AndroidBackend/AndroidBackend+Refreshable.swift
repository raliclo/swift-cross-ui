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
    /// The text on the button, and also how it is found again.
    ///
    /// The first version kept the buttons in a Swift dictionary keyed by
    /// `container.javaHolder.object!.hashValue`. That looks like an identity
    /// and is not one: the pointer is a JNI local reference and can differ
    /// between two calls about the same Java object, so the lookup missed, a
    /// new button was added on EVERY update, and the emulator went from
    /// "Pixel Launcher isn't responding" to "System UI isn't responding" while
    /// the app itself never crashed. Nothing in the Swift code failed; the view
    /// tree simply grew without bound.
    ///
    /// Scanning the container's children for this text is O(children) on a
    /// scroll container that holds one or two, and it asks the view hierarchy
    /// -- which is the thing that actually knows -- instead of a side table.
    ///
    /// 按鈕上的文字,同時也是「再次找到它」的方式。
    ///
    /// 第一版把那些按鈕放在一個 Swift 字典裡,以 `container.javaHolder.object!.hashValue` 為索引鍵。
    /// 那看起來像是一個身分,但它不是:該指標是一個 JNI local reference,對同一個 Java 物件的兩次呼叫
    /// 可能不同,因此查找落空、**每一次**更新都新增一顆按鈕,而模擬器就從「Pixel Launcher isn't
    /// responding」一路走到「System UI isn't responding」——而 app 本身從未當掉。Swift 這一側沒有任何
    /// 東西失敗;只是那棵 view 樹無上限地長大。
    ///
    /// 在容器的子 view 中掃描這段文字,對一個只有一兩個子項的 scroll container 而言是 O(children),
    /// 而且它問的是 view 階層——那才是真正知道答案的東西——而不是一張旁置的表。
    private static let refreshButtonText = "Refresh"

    public func setRefreshHandler(
        ofScrollContainer scrollView: Widget,
        to handler: (@MainActor @Sendable () -> Void)?
    ) {
        guard let container = scrollView.as(ScrollContainer.self) else { return }
        let existing = Self.refreshButton(in: container)

        guard let handler else {
            if let existing {
                container.removeView(existing)
            }
            return
        }

        // The listener is replaced on an existing button rather than the button
        // being rebuilt. `updateScrollContainer` runs on every state change,
        // including the ones the refresh action itself causes.
        // 在既有按鈕上替換 listener,而不是重建那顆按鈕。`updateScrollContainer` 在每一次狀態改變時
        // 都會執行——包括那些由 refresh 動作本身所引起的。
        let button = existing ?? {
            let button = AndroidKit.Button(Self.activity, environment: Self.env)
            button.setText(Self.charSequence(from: Self.refreshButtonText))
            button.setAllCaps(false)
            container.addView(button)
            return button
        }()

        button.setOnClickListener(
            ViewOnClickListener(action: { handler() }, environment: Self.env)
                .as(AndroidView.View.OnClickListener.self)
        )
    }

    private static func refreshButton(in container: ScrollContainer) -> AndroidKit.Button? {
        for index in 0..<container.getChildCount() {
            guard let child = container.getChildAt(index),
                let button = child.as(AndroidKit.Button.self),
                button.getText()?.toString() == refreshButtonText
            else { continue }
            return button
        }
        return nil
    }
}
