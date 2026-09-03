package dev.swiftcrossui.androidbackend

import android.app.Activity
import android.view.View
import android.view.ViewGroup

/**
 * `NavigationSplitView` on Android.
 *
 * Before this class the four split-view entry points in `AndroidBackend` were
 * `fatalError`, so P16 did not render a split view badly -- it died at launch
 * with "createSplitView(leadingChild:trailingChild:) not implemented".
 *
 * Side by side, not a drawer. Android's own idiom for this on a phone is a
 * navigation drawer that slides over the content, and that is the wrong shape
 * here for the same reason it was on iPhone: the layout system asks
 * `sidebarWidth(ofSplitView:)` and hands the remainder to the trailing child,
 * which is a statement about two columns that exist at once. A drawer would
 * make that width a lie whenever it was closed, and the framework has nowhere
 * to say "the sidebar is currently zero wide because it is off screen".
 * `SlidingPaneLayout` was the other candidate and has the same problem: it
 * overlaps the panes below a width threshold, so the same app would report one
 * geometry and draw another.
 *
 * The 30% is `PhoneSplitWidget`'s fraction, which is
 * `UISplitViewController.preferredPrimaryColumnWidthFraction`'s default. Taking
 * the same number means the two phone platforms in this repository put the
 * divider in the same place, which is what makes their screenshots comparable
 * -- the point of a reference platform.
 *
 * Android 上的 `NavigationSplitView`。
 *
 * 在本類別存在之前，`AndroidBackend` 中四個 split view 進入點都是 `fatalError`，因此 P16 並不是
 * 「split view 畫得不好」，而是直接在啟動時死於
 * 「createSplitView(leadingChild:trailingChild:) not implemented」。
 *
 * 採並排，而非抽屜。Android 自己在手機上的慣用做法是一個覆蓋內容滑出的 navigation drawer，而它在
 * 此處是錯的形狀，理由與在 iPhone 上相同：版面系統會詢問 `sidebarWidth(ofSplitView:)` 並把其餘寬度
 * 交給 trailing child，那是一項「兩個欄位同時存在」的陳述。抽屜會讓那個寬度在關閉時成為謊言，而框架
 * 沒有任何地方可以表達「側欄目前寬度為零，因為它在畫面外」。另一個候選 `SlidingPaneLayout` 有同樣的
 * 問題：低於某個寬度閾值時它會讓兩個面板重疊，於是同一支 app 會回報一種幾何、卻畫出另一種。
 *
 * 那個 30% 是 `PhoneSplitWidget` 的比例，也就是
 * `UISplitViewController.preferredPrimaryColumnWidthFraction` 的預設值。採用同一個數字，意味著本
 * 倉庫中兩個手機平台會把分隔線放在同一個位置，而那正是使它們的截圖可以互相對照的原因——也就是基準
 * 平台的用意。
 */
class SplitContainer(val activity: Activity) : ViewGroup(activity) {
    companion object {
        private const val PREFERRED_FRACTION = 0.3f
    }

    private var leading: View? = null
    private var trailing: View? = null

    var minimumSidebarWidth = 0
    var maximumSidebarWidth = Int.MAX_VALUE
    var resizeHandler: SwiftAction? = null

    private var lastReportedWidth = -1
    private var lastReportedHeight = -1

    fun setChildren(leadingChild: View, trailingChild: View) {
        removeAllViews()
        leading = leadingChild
        trailing = trailingChild
        addView(leadingChild)
        addView(trailingChild)
    }

    fun setSidebarWidthBounds(minimum: Int, maximum: Int) {
        minimumSidebarWidth = minimum
        maximumSidebarWidth = maximum
        requestLayout()
    }

    /**
     * Asked for by the layout system before this view has ever been measured,
     * so it cannot be a stored value.
     *
     * `layoutParams.width` first because that is the size SwiftCrossUI assigned
     * and it is correct one pass earlier than `measuredWidth`. It is also where
     * MATCH_PARENT (-1) and WRAP_CONTENT (-2) turn up, and those are sentinels
     * rather than widths -- taking 30% of -1 is how a sidebar ends up nine
     * pixels wide. See the note in CustomContainer.onMeasure, which is the same
     * trap in the same layoutParams.
     *
     * 版面系統會在本 view 被量測之前就詢問它，因此它不能是一個已儲存的值。
     *
     * 優先採用 `layoutParams.width`，因為那是 SwiftCrossUI 所指派的尺寸，而且比 `measuredWidth`
     * 早一個回合就已正確。它同時也是 MATCH_PARENT（-1）與 WRAP_CONTENT（-2）出現的地方，而那些是
     * 哨兵值、不是寬度——對 -1 取 30%，正是側欄最後只有九個像素寬的成因。見 CustomContainer.onMeasure
     * 的說明，那是同一組 layoutParams 中的同一個陷阱。
     */
    fun resolvedSidebarWidth(): Int {
        val assigned = layoutParams?.width ?: -1
        val available = if (assigned > 0) assigned else measuredWidth
        if (available <= 0) {
            return minimumSidebarWidth
        }
        val preferred = Math.round(available * PREFERRED_FRACTION)
        return Math.max(minimumSidebarWidth, Math.min(maximumSidebarWidth, preferred))
    }

    override protected fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val requestedWidth = layoutParams?.width ?: -1
        val requestedHeight = layoutParams?.height ?: -1
        val width =
            if (requestedWidth >= 0) requestedWidth
            else View.MeasureSpec.getSize(widthMeasureSpec)
        val height =
            if (requestedHeight >= 0) requestedHeight
            else View.MeasureSpec.getSize(heightMeasureSpec)
        setMeasuredDimension(width, height)

        val sidebar = Math.min(resolvedSidebarWidth(), width)
        measureSplitChild(leading, sidebar, height)
        measureSplitChild(trailing, width - sidebar, height)

        // Posted, not called. A resize handler runs SwiftCrossUI's layout, which
        // writes layoutParams and calls requestLayout; doing that inside
        // onMeasure is laying out during a layout pass, which Android answers by
        // dropping the request. `post` puts it after this traversal finishes.
        //
        // Only on a change of size, so a steady state produces no calls at all.
        // A handler that fired every pass would re-enter layout every pass.
        //
        // 用 post，而不是直接呼叫。resize handler 會執行 SwiftCrossUI 的版面計算，而後者會寫入
        // layoutParams 並呼叫 requestLayout；在 onMeasure 之中做那件事，就是在版面回合之中要求版面
        // ——Android 對此的回應是丟棄該請求。`post` 會把它排在本次走訪結束之後。
        //
        // 僅在尺寸改變時觸發，因此穩定狀態不會產生任何呼叫。一個每回合都觸發的 handler，會導致每回合
        // 都重新進入版面計算。
        if (width != lastReportedWidth || height != lastReportedHeight) {
            lastReportedWidth = width
            lastReportedHeight = height
            resizeHandler?.let { handler -> post { handler.call() } }
        }
    }

    private fun measureSplitChild(child: View?, width: Int, height: Int) {
        if (child == null) {
            return
        }
        val safeWidth = Math.max(0, width)
        val safeHeight = Math.max(0, height)
        val params = child.layoutParams
        if (params != null) {
            params.width = safeWidth
            params.height = safeHeight
        }
        child.measure(
            View.MeasureSpec.makeMeasureSpec(safeWidth, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(safeHeight, View.MeasureSpec.EXACTLY),
        )
    }

    override protected fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        val height = b - t
        val sidebar = Math.min(resolvedSidebarWidth(), r - l)
        leading?.layout(0, 0, sidebar, height)
        trailing?.layout(sidebar, 0, r - l, height)
    }
}
