package dev.swiftcrossui.androidbackend

import android.app.Activity
import android.view.Gravity
import android.view.MotionEvent
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
}
