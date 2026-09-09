package dev.swiftcrossui.androidbackend

import android.app.Activity
import android.view.Gravity
import android.graphics.Rect
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.ScrollView

class ScrollContainer(activity: Activity, child: View) : FrameLayout(activity) {
    init {
        child.layoutParams =
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
                Gravity.FILL,
            )

        addView(child)
    }

    private val verticalScrollView =
        ScrollView(activity).apply {
            layoutParams =
                FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    Gravity.FILL,
                )
        }

    private val horizontalScrollView =
        HorizontalScrollView(activity).apply {
            layoutParams =
                FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    Gravity.FILL,
                )
        }

    private var isVerticalScrollViewAdded = false
    private var isHorizontalScrollViewAdded = false

    fun updateScroll(vertical: Boolean, horizontal: Boolean) {
        if (isHorizontalScrollViewAdded && !horizontal) {
            val horizontalScrollViewChild = horizontalScrollView.getChildAt(0)
            val horizontalScrollViewParent = horizontalScrollView.parent as FrameLayout
            horizontalScrollView.removeView(horizontalScrollViewChild)
            horizontalScrollViewParent.removeView(horizontalScrollView)
            horizontalScrollViewParent.addView(horizontalScrollViewChild)
            isHorizontalScrollViewAdded = false
        }

        if (isVerticalScrollViewAdded && !vertical) {
            val verticalScrollViewChild = verticalScrollView.getChildAt(0)
            val verticalScrollViewParent = verticalScrollView.parent as FrameLayout
            verticalScrollView.removeView(verticalScrollViewChild)
            verticalScrollViewParent.removeView(verticalScrollView)
            verticalScrollViewParent.addView(verticalScrollViewChild)
            isVerticalScrollViewAdded = false
        }

        if (!isHorizontalScrollViewAdded && horizontal) {
            val ownChild = getChildAt(0)
            removeView(ownChild)
            horizontalScrollView.addView(ownChild)
            addView(horizontalScrollView)
            isHorizontalScrollViewAdded = true
        }

        if (!isVerticalScrollViewAdded && vertical) {
            val ownChild = getChildAt(0)
            removeView(ownChild)
            verticalScrollView.addView(ownChild)
            addView(verticalScrollView)
            isVerticalScrollViewAdded = true
        }
    }

    /**
     * Scrolls so that [child] is visible, optionally placing it at [anchorX] /
     * [anchorY] within the viewport. A negative anchor means "no anchor" --
     * take the shortest scroll that makes the child visible.
     *
     * A no-op on an axis whose scroll view is not mounted. `updateScroll` adds
     * and removes those views as the ScrollView's axes change, so a container
     * that is not scrolling vertically has no vertical position to move to, and
     * moving one that is not there would be a silent write to nothing.
     *
     * `requestRectangleOnScreen` rather than arithmetic for the anchorless
     * case: it is the platform's own "make this visible", it already knows
     * about padding and insets, and it takes the shortest path.
     *
     * 捲動使 [child] 可見,並可選擇性地把它放在視口中 [anchorX] / [anchorY] 的位置。
     * 負值的 anchor 代表「沒有 anchor」——採取讓該子元件可見的最短捲動。
     *
     * 對於「捲動視圖未被掛載」的那個軸,這是一個 no-op。`updateScroll` 會隨著 ScrollView 的軸向改變
     * 而加入或移除那些視圖,因此一個並未垂直捲動的容器,沒有垂直位置可移動;而去移動一個不存在的東西,
     * 會是一次寫進虛無的靜默寫入。
     *
     * 無 anchor 的情況使用 `requestRectangleOnScreen` 而非自行計算:那是該平台自己的「讓這個可見」,
     * 它已經知道 padding 與 inset 的存在,而且採取的是最短路徑。
     */
    fun scrollToChild(child: View, anchorX: Float, anchorY: Float) {
        val rect = Rect(0, 0, child.width, child.height)
        if (anchorX < 0f && anchorY < 0f) {
            child.requestRectangleOnScreen(rect, true)
            return
        }

        if (isVerticalScrollViewAdded && anchorY >= 0f) {
            val top = offsetWithin(child, verticalScrollView, vertical = true)
            val viewport = verticalScrollView.height
            verticalScrollView.scrollTo(
                verticalScrollView.scrollX,
                (top - (viewport - child.height) * anchorY).toInt().coerceAtLeast(0),
            )
        }

        if (isHorizontalScrollViewAdded && anchorX >= 0f) {
            val left = offsetWithin(child, horizontalScrollView, vertical = false)
            val viewport = horizontalScrollView.width
            horizontalScrollView.scrollTo(
                (left - (viewport - child.width) * anchorX).toInt().coerceAtLeast(0),
                horizontalScrollView.scrollY,
            )
        }
    }

    /**
     * The child's offset inside [ancestor], summed up the parent chain.
     *
     * Not `getLocationOnScreen`, whose answer moves with the window, the status
     * bar and any parent that is itself scrolled -- and this method is called
     * precisely when a parent IS scrolled, so those two differ by exactly the
     * amount being corrected for.
     *
     * 該子元件在 [ancestor] 之內的位移,沿著 parent 鏈累加而得。
     *
     * 不使用 `getLocationOnScreen`,它的答案會隨著視窗、狀態列、以及任何「本身正被捲動的 parent」
     * 而改變——而本方法被呼叫的時機,正是某個 parent **正在**被捲動的時候,因此兩者的差距恰好就是
     * 正要被修正掉的那個量。
     */
    private fun offsetWithin(child: View, ancestor: ViewGroup, vertical: Boolean): Int {
        var offset = 0
        var current: View = child
        while (current !== ancestor) {
            offset += if (vertical) current.top else current.left
            val parent = current.parent as? View ?: return offset
            current = parent
        }
        return offset
    }
}
