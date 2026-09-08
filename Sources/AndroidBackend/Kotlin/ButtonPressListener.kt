package dev.swiftcrossui.androidbackend

import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration

/**
 * Reports whether a button is being held down, for `ButtonStyleConfiguration.isPressed`.
 *
 * **It never consumes an event.** `onTouch` always returns false, so `View.dispatchTouchEvent` goes
 * on to run `View.onTouchEvent` as if this listener were not there -- the click still fires, the
 * ripple still draws, and `View.isPressed` is still maintained by the view itself. That is the whole
 * reason a listener was acceptable here at all: a `View` has room for exactly one `OnTouchListener`,
 * so one that changed behaviour would be trading a working button for a highlight.
 *
 * **The abandon case is the point of the ACTION_MOVE branch.** A press that ends by dragging off the
 * button has to report false, or a `ButtonStyle` latches into its pressed appearance for good. The
 * bounds test is `View`'s own: `View.onTouchEvent` calls `pointInView(x, y, mTouchSlop)` and clears
 * its pressed state when that goes false, so matching it means this listener and the ripple stop and
 * start together instead of disagreeing at the edge by a few pixels.
 *
 * **ACTION_UP and ACTION_CANCEL report false unconditionally**, without the equality check the
 * ACTION_MOVE branch uses. SwiftCrossUI rebuilds this listener on every commit, and a press schedules
 * a re-render, so the listener that sees the release is routinely not the one that saw the press.
 * Edge-triggering the release against a `down` this instance never observed would drop it, and a
 * dropped release is the latch. The Swift side seeds `down` from `View.isPressed()` to close the
 * same gap for ACTION_MOVE, where an unconditional report would instead fire once per pointer sample.
 *
 * **Not handled, and shared with the other backends rather than specific to Android:** a view
 * disabled mid-press stops receiving touch events -- `dispatchTouchEvent` consults the listener only
 * while the view is enabled -- so the release is never seen. Android sets the view's own pressed
 * state to false there; this listener cannot observe that, and reports the release at the next touch
 * instead.
 *
 * 回報一顆按鈕是否正被按住，供 `ButtonStyleConfiguration.isPressed` 使用。
 *
 * **它從不消耗事件。** `onTouch` 一律回傳 false，因此 `View.dispatchTouchEvent` 會繼續執行
 * `View.onTouchEvent`，彷彿這個 listener 不存在——點擊照樣觸發、漣漪照樣繪製，而 `View.isPressed`
 * 仍由 view 自己維護。這正是「在此使用 listener 尚可接受」的全部理由：一個 `View` 恰好只有一個
 * `OnTouchListener` 的位置，因此一個會改變行為的 listener，等於拿一顆可用的按鈕去換一個高亮。
 *
 * **ACTION_MOVE 那一支的存在意義就是放棄的情況。** 一次以「拖離按鈕」結束的按壓必須回報 false，
 * 否則 `ButtonStyle` 會永遠卡在它按下的外觀上。此處的邊界判斷是 `View` 自己的那一個：
 * `View.onTouchEvent` 呼叫 `pointInView(x, y, mTouchSlop)`，並在它變為 false 時清除自身的按下狀態；
 * 與之一致，意味著這個 listener 與漣漪會一起停、一起起，而不會在邊緣處差了幾個像素而彼此不一致。
 *
 * **ACTION_UP 與 ACTION_CANCEL 會無條件回報 false**，不做 ACTION_MOVE 那一支所用的相等性檢查。
 * SwiftCrossUI 每次 commit 都會重建這個 listener，而一次按壓會排入一次重繪，因此「看到放開的那個
 * listener」通常並不是「看到按下的那一個」。若拿一個本實例從未觀察過的 `down` 去做邊緣觸發，就會把
 * 放開丟掉，而丟掉的放開就是卡住的成因。Swift 端以 `View.isPressed()` 為 `down` 設定初始值，替
 * ACTION_MOVE 補上同一個缺口——在那裡若改為無條件回報，則會依指標取樣頻率反覆觸發。
 *
 * **未處理、且與其他 backend 共通而非 Android 特有的一點：** 一個在按壓中途被停用的 view 會停止收到
 * 觸控事件——`dispatchTouchEvent` 只在 view 為 enabled 時才詢問 listener——因此那次放開永遠不會被看到。
 * Android 會在該處把 view 自身的按下狀態設為 false；本 listener 觀察不到這件事，只能在下一次觸控時
 * 才回報那次放開。
 */
class ButtonPressListener(
    private val pressedAction: SwiftAction?,
    private val releasedAction: SwiftAction?,
    initiallyDown: Boolean,
) : View.OnTouchListener {
    private var down = initiallyDown
    private var inside = initiallyDown

    override fun onTouch(v: View, event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                down = true
                inside = true
                pressedAction?.call()
            }

            MotionEvent.ACTION_MOVE -> {
                if (down) {
                    val nowInside = pointInView(v, event)
                    if (nowInside != inside) {
                        inside = nowInside
                        (if (nowInside) pressedAction else releasedAction)?.call()
                    }
                }
            }

            MotionEvent.ACTION_UP,
            MotionEvent.ACTION_CANCEL -> {
                down = false
                inside = false
                releasedAction?.call()
            }
        }

        return false
    }

    private fun pointInView(v: View, event: MotionEvent): Boolean {
        val slop = ViewConfiguration.get(v.context).scaledTouchSlop.toFloat()

        return event.x >= -slop &&
            event.y >= -slop &&
            event.x < v.width + slop &&
            event.y < v.height + slop
    }
}
