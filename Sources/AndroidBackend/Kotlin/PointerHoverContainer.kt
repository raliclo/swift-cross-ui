package dev.swiftcrossui.androidbackend

import android.app.Activity
import android.view.Gravity
import android.view.MotionEvent
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.widget.FrameLayout

/**
 * `onContinuousHover(perform:)` on Android: where the pointer is, and the meta state, on every
 * hover sample.
 *
 * The same route as [HoverContainer] -- `dispatchHoverEvent` overridden, because a listener would
 * fall silent over any clickable child -- but level-reported rather than edge-triggered: every
 * `ACTION_HOVER_MOVE` is a new position, which is the point. The values are read back by the
 * Swift side through the getters, because `SwiftAction` takes no arguments
 * ([ContinuousGestureContainer] does the same). Positions are in points (pixels / density), the
 * unit SwiftCrossUI lays out in.
 *
 * Android 上的 `onContinuousHover(perform:)`:每個 hover 取樣時指標的位置與 meta 狀態。走與 [HoverContainer]
 * 相同的路——覆寫 `dispatchHoverEvent`,因為 listener 在任何可點擊的子元件上方會沉默——但每次都回報，而不是
 * 邊緣觸發：每個 `ACTION_HOVER_MOVE` 都是新位置，那正是重點。數值由 Swift 端經 getter 讀回，因為 `SwiftAction`
 * 不帶參數([ContinuousGestureContainer] 也是如此)。位置以點計(像素 / density),也就是 SwiftCrossUI
 * 排版的單位。
 */
class PointerHoverContainer(activity: Activity) : FrameLayout(activity) {
    var changeAction: SwiftAction? = null

    var inside = false
        private set
    var pointX = 0f
        private set
    var pointY = 0f
        private set
    var metaState = 0
        private set

    override fun generateDefaultLayoutParams() =
        FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
            Gravity.FILL,
        )

    override fun dispatchHoverEvent(event: MotionEvent): Boolean {
        val density = resources.displayMetrics.density
        when (event.actionMasked) {
            MotionEvent.ACTION_HOVER_ENTER, MotionEvent.ACTION_HOVER_MOVE -> {
                inside = true
                pointX = event.x / density
                pointY = event.y / density
                metaState = event.metaState
                changeAction?.call()
            }
            MotionEvent.ACTION_HOVER_EXIT -> {
                inside = false
                changeAction?.call()
            }
        }
        return super.dispatchHoverEvent(event) || inside
    }

    /**
     * A finger hovers by holding still for the system's long-press timeout
     * (`ViewConfiguration.getLongPressTimeout()`: 400 ms by default, longer when the user sets
     * the touch-and-hold delay in Accessibility); from then on, until it lifts, every move is
     * reported, and the lift ends it. This matches the iPhone's 0.5 s hold, the same
     * gesture on both phones. A mouse is left to `dispatchHoverEvent`, which already
     * reports it. The touch still goes to the children first; the hold only watches.
     *
     * 手指靜止按住系統的長按逾時(`ViewConfiguration.getLongPressTimeout()`:預設 400 毫秒，使用者在無障礙設定裡
     * 調整「觸控並按住的延遲」時會更長)即開始 hover;此後到放開為止，每次移動都回報，放開即結束。這與
     * iPhone 的 0.5 秒按住相對應，兩支手機上是同一個手勢。滑鼠交給 `dispatchHoverEvent`,它已經會回報。
     * 觸控仍先送到子元件;按住只是在旁觀察。
     */
    private var holding = false
    private var downX = 0f
    private var downY = 0f
    private val beginHold = Runnable {
        holding = true
        inside = true
        changeAction?.call()
    }

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        val handled = super.dispatchTouchEvent(event)
        if (changeAction == null || event.getToolType(0) == MotionEvent.TOOL_TYPE_MOUSE) {
            return handled
        }
        val density = resources.displayMetrics.density
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downX = event.x
                downY = event.y
                pointX = event.x / density
                pointY = event.y / density
                metaState = event.metaState
                postDelayed(beginHold, ViewConfiguration.getLongPressTimeout().toLong())
            }
            MotionEvent.ACTION_MOVE ->
                if (holding) {
                    pointX = event.x / density
                    pointY = event.y / density
                    metaState = event.metaState
                    changeAction?.call()
                } else if (Math.hypot((event.x - downX).toDouble(), (event.y - downY).toDouble()) >
                    ViewConfiguration.get(context).scaledTouchSlop
                ) {
                    removeCallbacks(beginHold)
                }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                removeCallbacks(beginHold)
                if (holding) {
                    holding = false
                    inside = false
                    changeAction?.call()
                }
            }
        }
        // Keep receiving the gesture even when no child took the down.
        // 即使沒有子元件接下 down,也要繼續收到這個手勢。
        return true
    }
}
