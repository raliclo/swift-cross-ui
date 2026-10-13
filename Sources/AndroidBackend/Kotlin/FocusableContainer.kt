package dev.swiftcrossui.androidbackend

import android.app.Activity
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout

/**
 * `.focusable()` on Android: a container that can hold the focus.
 *
 * A view is not focusable by default here, and in touch mode it also needs
 * `isFocusableInTouchMode` or `requestFocus()` fails. Both follow [focusableNow].
 *
 * **A touch focuses it and is not taken.** `dispatchTouchEvent` sees every touch
 * on its way to the children; the down asks for the focus and the event goes on
 * as it would have.
 *
 * Tab needs nothing here: an unhandled Tab reaches the view root, which runs its
 * own focus search, and `KeyEventContainer` reports a key without consuming it.
 *
 * Android 上的 `.focusable()`:一個能持有焦點的容器。view 在這裡預設不可聚焦，在 touch mode 下還需要
 * `isFocusableInTouchMode`,否則 `requestFocus()` 會失敗;兩者都跟著 [focusableNow]。觸碰會讓它取得焦點
 * 但不被拿走:`dispatchTouchEvent` 看得到每個前往子 view 的觸碰，按下時要求焦點，事件照原樣往下走。
 * Tab 在這裡不需要處理:沒被處理的 Tab 會到 view root,由它自己搜尋焦點;`KeyEventContainer` 只回報、不消耗。
 */
class FocusableContainer(activity: Activity) : FrameLayout(activity) {
    var focusableNow = true
        set(value) {
            field = value
            isFocusable = value
            isFocusableInTouchMode = value
            if (!value && isFocused) clearFocus()
        }

    init {
        isFocusable = true
        isFocusableInTouchMode = true
        descendantFocusability = FOCUS_BEFORE_DESCENDANTS
    }

    override fun generateDefaultLayoutParams() =
        FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
            Gravity.FILL,
        )

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        if (event.actionMasked == MotionEvent.ACTION_DOWN && focusableNow && !isFocused) {
            requestFocus()
        }
        return super.dispatchTouchEvent(event)
    }

    companion object {
        /** Whether [view] holds a focusable container somewhere below it. [view] 底下是否有可聚焦的容器。 */
        @JvmStatic
        fun isHeldBy(view: View): Boolean {
            if (view !is ViewGroup) return false
            for (i in 0 until view.childCount) {
                val child = view.getChildAt(i)
                if (child is FocusableContainer || isHeldBy(child)) return true
            }
            return false
        }
    }
}
