package dev.swiftcrossui.androidbackend

import android.app.Activity
import android.view.Gravity
import android.view.MotionEvent
import android.view.ViewGroup
import android.widget.FrameLayout

/**
 * `onHover(perform:)` on Android.
 *
 * Android does have hover. It arrives as three `MotionEvent` actions -- `ACTION_HOVER_ENTER`,
 * `ACTION_HOVER_MOVE` and `ACTION_HOVER_EXIT` -- on a stream that is separate from the touch
 * stream, and it is produced by a mouse, by a stylus held within detection range, and by an
 * accessibility explore-by-touch pass. Those are the only three producers, and that is the honest
 * answer to "what happens on a phone with no mouse": nothing is delivered, so the closure is never
 * called. A pointer that is never over the view is not a missing feature, it is a pointer that is
 * not there. What is not acceptable, and what this file exists to remove, is the modifier taking
 * the process down.
 *
 * **Why a wrapper `ViewGroup` and not `View.setOnHoverListener`.** The listener would have been one
 * line of Swift, and it is bound (`AndroidKit/Sources/AndroidView/View.swift:187`). It is also
 * consulted only inside `View.dispatchHoverEvent`, which `ViewGroup` overrides: a `ViewGroup` walks
 * its children first and only falls through to `super.dispatchHoverEvent` -- and therefore to its
 * own listener -- when no child handled the event. `View.onHoverEvent` returns true for any view
 * that is clickable, long-clickable or context-clickable, which every `Button` is. So a listener on
 * a wrapper around a button would go quiet exactly where the pointer is, which is the failure that
 * looks like a working implementation. Overriding `dispatchHoverEvent` runs before that fork and is
 * not subject to it.
 *
 * `super.dispatchHoverEvent(event) || hovering` rather than plain `super`, so a container that is
 * hovered reports itself as having handled the event. The parent `ViewGroup` keeps its hovered
 * children in a list and synthesises the `ACTION_HOVER_EXIT` from it when the pointer leaves; a
 * child that always answers false is not reliably kept there, and the symptom of losing the exit is
 * a hover that turns on and never turns off.
 *
 * Two `SwiftAction`s rather than one plus an `isHovering()` getter, which is what `DropListener`
 * does for the drop-target hover next door. That shape needs the Swift closure to capture the
 * container so it can read the flag back, and the container holds the closure -- a reference cycle
 * across the JNI boundary, so the last one set after the final commit keeps its container alive for
 * good. One drop target is not worth the machinery to avoid it; `Examples/Sources/HoverExample`
 * puts 540 hover targets on screen at once.
 *
 * Not handled here, and shared with the other backends rather than specific to Android: a view
 * removed from the window while the pointer is inside it gets no exit, so its last reported state
 * stays `true`. `NSTrackingArea` behaves the same way in `AppKitBackend`.
 *
 * Android 上的 `onHover(perform:)`。
 *
 * Android 確實有 hover。它以三種 `MotionEvent` action 抵達——`ACTION_HOVER_ENTER`、 `ACTION_HOVER_MOVE` 與
 * `ACTION_HOVER_EXIT`——走的是與觸控事件分離的另一條串流，產生者為滑鼠、 位於偵測範圍內的觸控筆，以及無障礙的
 * explore-by-touch。產生者就只有這三種，而這也就是「一支沒有 滑鼠的手機會怎樣」的誠實答案：沒有任何事件被送出，因此該 closure 永遠不會被呼叫。一個從未位於 view
 * 之上的指標並不是缺失的功能，而是根本不存在的指標。不可接受的、也就是本檔要消除的，是這個 modifier 把整個行程拖垮。
 *
 * **為何使用外層 `ViewGroup` 而非 `View.setOnHoverListener`。** 用那個 listener 只需一行 Swift，
 * 而且它有繫結（`AndroidKit/Sources/AndroidView/View.swift:187`）。但它只會在 `View.dispatchHoverEvent` 之中被查詢，而
 * `ViewGroup` 覆寫了該方法：`ViewGroup` 會先走訪其子元件， 唯有在沒有任何子元件處理該事件時，才會落到
 * `super.dispatchHoverEvent`——也才會落到它自己的 listener。`View.onHoverEvent` 對任何 clickable、long-clickable 或
 * context-clickable 的 view 都回傳 true，而每一顆 `Button` 都是如此。因此，掛在按鈕外層上的 listener 會恰好在指標所在之處
 * 靜默無聲，而那正是「看起來像能運作」的那種失敗。覆寫 `dispatchHoverEvent` 執行於該分岔之前， 不受其影響。
 *
 * 使用 `super.dispatchHoverEvent(event) || hovering` 而非單純的 `super`，使一個正被懸停的容器回報 自己已處理該事件。父
 * `ViewGroup` 會把被懸停的子元件記錄成一份清單，並在指標離開時據以合成 `ACTION_HOVER_EXIT`；一個總是回答 false 的子元件不會被可靠地保留在那份清單中，而失去
 * exit 的症狀 就是「懸停打開之後再也關不掉」。
 *
 * 使用兩個 `SwiftAction` 而非「一個加上 `isHovering()` getter」——後者是隔壁 `DropListener` 為 drop target
 * 的懸停所採用的形狀。那個形狀需要 Swift closure 捕獲容器才能把旗標讀回來，而容器又持有 該 closure——這是一個跨越 JNI 邊界的參考循環，因此最後一次 commit
 * 所設定的那一個會讓它的容器永久 存活。一個 drop target 不值得為此加上規避機制；但 `Examples/Sources/HoverExample` 會同時在畫面上 放置 540 個
 * hover target。
 *
 * 此處未處理、且與其他 backend 共通而非 Android 特有的一點：一個在指標仍位於其內時就被移出視窗的 view 不會收到 exit，因此它最後回報的狀態會停留在
 * `true`。`AppKitBackend` 中的 `NSTrackingArea` 也是同樣的行為。
 */
class HoverContainer(activity: Activity) : FrameLayout(activity) {
    var enterAction: SwiftAction? = null
    var exitAction: SwiftAction? = null

    private var hovering = false

    // MATCH_PARENT, so the child takes this container's size. The modifier
    // sizes the container it is handed and nothing sizes what is inside it;
    // VisualEffectContainer and CornerRadiusContainer close the same gap in the
    // same place.
    //
    // 使用 MATCH_PARENT，讓子元件取得本容器的尺寸。modifier 只會為它所拿到的容器設定尺寸，沒有任何
    // 東西為其內部的元件設定尺寸；VisualEffectContainer 與 CornerRadiusContainer 也是在同一個位置
    // 填補同一個缺口。
    override fun generateDefaultLayoutParams() =
        FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
            Gravity.FILL,
        )

    // ACTION_HOVER_MOVE is treated as an enter as well as ACTION_HOVER_ENTER,
    // and that is not belt-and-braces. Hover is delivered on its own stream and
    // the touch stream interrupts it: pressing a mouse button sends
    // ACTION_HOVER_EXIT immediately before ACTION_DOWN, so a click reports
    // false and the pointer is still over the view when the moves resume. Only
    // ACTION_HOVER_ENTER after that would leave the state stuck at false for
    // the rest of the gesture.
    //
    // ACTION_HOVER_MOVE 與 ACTION_HOVER_ENTER 一樣被視為進入，而這並非多此一舉。hover 走的是它自己
    // 的串流，而觸控串流會中斷它：按下滑鼠按鍵會在 ACTION_DOWN 之前立即送出 ACTION_HOVER_EXIT，
    // 因此一次點擊會回報 false，而當 move 事件恢復時指標其實仍在該 view 之上。若此後只認
    // ACTION_HOVER_ENTER，狀態就會在該手勢的其餘期間卡在 false。
    override fun dispatchHoverEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_HOVER_ENTER,
            MotionEvent.ACTION_HOVER_MOVE -> setHovering(true)

            MotionEvent.ACTION_HOVER_EXIT -> setHovering(false)
        }

        return super.dispatchHoverEvent(event) || hovering
    }

    // Edge-triggered. SwiftCrossUI calls commit on every update, and a hover
    // that re-reported true on every ACTION_HOVER_MOVE would run the caller's
    // closure once per pointer sample.
    //
    // 邊緣觸發。SwiftCrossUI 每次更新都會呼叫 commit，而一個在每個 ACTION_HOVER_MOVE 上都重新回報
    // true 的懸停，會讓呼叫端的 closure 依指標取樣頻率反覆執行。
    private fun setHovering(newValue: Boolean) {
        if (newValue == hovering) {
            return
        }
        hovering = newValue
        (if (newValue) enterAction else exitAction)?.call()
    }
}
