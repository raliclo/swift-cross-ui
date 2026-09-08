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
    /// 按鈕上的文字,同時也是「再次找到它」的方式。
    ///
    /// 第一版把那些按鈕放在一個 Swift 字典裡,以 `container.javaHolder.object!.hashValue` 為索引鍵。
    /// 那看起來像是一個身分,但它不是:該指標是一個 JNI local reference,對同一個 Java 物件的兩次呼叫
    /// 可能不同,因此查找落空、**每一次**更新都新增一顆按鈕,而模擬器就從「Pixel Launcher isn't
    /// responding」一路走到「System UI isn't responding」——而 app 本身從未當掉。Swift 這一側沒有任何
    /// 東西失敗;只是那棵 view 樹無上限地長大。
    private static let refreshButtonText = "Refresh"

    /// The button goes in the window's root stack, not inside the scroll
    /// container.
    ///
    /// `ScrollContainer` is this backend's own Kotlin class and its
    /// `updateScroll` is written around `getChildAt(0)` -- it assumes exactly
    /// one child and moves that child in and out of a ScrollView as the axes
    /// change. A second child breaks that assumption. Measured on P54: with the
    /// button added to the container, the app rendered as a grey rectangle with
    /// "Refresh" in the middle and no content at all.
    ///
    /// The root stack is where `.toolbar` already puts its row, it is above the
    /// scrolling content, and adding to it disturbs nothing. The cost is that
    /// the affordance is per-window rather than per-scroll-view, which matters
    /// only for an app with two scroll views wanting different refresh actions
    /// -- and that app would also need two visible buttons to tell them apart,
    /// which is a design question rather than a missing capability.
    ///
    /// 這顆按鈕放在視窗的 root stack 中,而不是放進 scroll container 裡。
    ///
    /// `ScrollContainer` 是本 backend 自有的 Kotlin 類別,而它的 `updateScroll` 是圍繞著
    /// `getChildAt(0)` 寫成的——它假設自己恰好只有一個子項,並在軸向改變時把那個子項移進、移出一個
    /// ScrollView。多出第二個子項就會破壞那個假設。在 P54 上實測:把按鈕加進該容器後,這支 app 畫出來
    /// 是一塊灰色矩形、中央寫著「Refresh」,完全沒有內容。
    ///
    /// root stack 正是 `.toolbar` 已經擺放它那一列的地方,它位於捲動內容之上,而加入其中不會擾亂任何
    /// 東西。代價是這個操作方式屬於「每個視窗一個」而非「每個捲動視圖一個」,而那只有在一支 app 有
    /// 兩個捲動視圖、且各自想要不同的 refresh 動作時才有影響——而那樣的 app 也需要兩顆看得見的按鈕
    /// 才分得出來,那是一個設計問題,不是一項缺失的能力。
    public func setRefreshHandler(
        ofScrollContainer scrollView: Widget,
        to handler: (@MainActor @Sendable () -> Void)?
    ) {
        guard let stack = Self.rootStack else { return }
        let existing = Self.refreshButton(in: stack)

        guard let handler else {
            if let existing {
                stack.removeView(existing)
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
            // Inserted above the scroll host, with the LinearLayout's own
            // default params rather than params of our making. A vertical
            // LinearLayout generates MATCH_PARENT x WRAP_CONTENT for a child,
            // which is a full-width button one line tall -- the shape a bar
            // across the top of a screen has on this platform.
            //
            // 插入在 scroll host 之上,並使用 LinearLayout 自己的預設 params,而不是我們自製的。
            // 垂直的 LinearLayout 會為子項產生 MATCH_PARENT x WRAP_CONTENT,那是一顆佔滿寬度、
            // 一行高的按鈕——也就是這個平台上「橫跨畫面頂端的一條」所具有的形狀。
            stack.addView(button, stack.getChildCount() - 1)
            return button
        }()

        button.setOnClickListener(
            ViewOnClickListener(action: { handler() }, environment: Self.env)
                .as(AndroidView.View.OnClickListener.self)
        )
    }

    private static func refreshButton(in stack: AndroidKit.LinearLayout) -> AndroidKit.Button? {
        for index in 0..<stack.getChildCount() {
            guard let child = stack.getChildAt(index),
                let button = child.as(AndroidKit.Button.self),
                button.getText()?.toString() == refreshButtonText
            else { continue }
            return button
        }
        return nil
    }
}
