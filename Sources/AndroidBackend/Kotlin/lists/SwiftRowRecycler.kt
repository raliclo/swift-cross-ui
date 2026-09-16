package dev.swiftcrossui.androidbackend.lists

import android.view.View
import android.widget.AbsListView
import dev.swiftcrossui.androidbackend.SwiftAction

/**
 * Reports the moment a row's view is scrapped, for
 * `BackendFeatures.LazyListRowLifetimes`.
 *
 * **`RecyclerListener`, not `getView`'s `convertView`.** The reuse of a scrapped view as
 * `convertView` also says a row let go of its content, and that hook is already wired -- but it
 * only fires when the view comes BACK. Views scrapped at the end of a scroll may never be reused,
 * so the last screenful of nodes would be held until something else displaced them, which is a
 * leak whose size depends on where the user stopped scrolling. `onMovedToScrapHeap` fires when the
 * view leaves, which is the question the protocol asks.
 *
 * **The position is looked up rather than carried.** A `View` scrapped by `AbsListView` arrives
 * with nothing attached saying which row it had been showing; `CustomListAdapter` records that as
 * it hands each view out, and answers -1 when this view is no longer the one holding that position
 * -- see `releasePosition`.
 *
 * `SwiftAction` carries no arguments, so the position is read back through
 * `lastReleasedPosition`. Same arrangement as `ListItemSelectedListener.selectedPosition` and
 * `TableContainer.tappedRow`.
 *
 * 回報「某一列的 view 被丟進 scrap heap」的那一刻,供 `BackendFeatures.LazyListRowLifetimes` 使用。
 *
 * **用 `RecyclerListener`,不是 `getView` 的 `convertView`。** 一個被丟棄的 view 以 `convertView`
 * 身分再度被使用,同樣說明了「某一列放開了它的內容」,而那個掛鉤本來就接好了——但它只在那個 view
 * **回來**時才觸發。在一次捲動結束時被丟棄的 view 可能永遠不會再被使用,於是最後一屏的節點會一直被
 * 持有、直到有別的東西把它們擠掉——那是一個「大小取決於使用者在哪裡停下捲動」的洩漏。
 * `onMovedToScrapHeap` 在該 view **離開**時觸發,而那正是這個協定所問的問題。
 *
 * **那個位置是被查出來的,不是被帶過來的。** 一個被 `AbsListView` 丟棄的 `View` 抵達時,身上沒有
 * 任何東西說明它先前在顯示哪一列;`CustomListAdapter` 會在交出每一個 view 時記下這件事,並在
 * 「這個 view 已不再是持有該位置的那一個」時回答 -1——見 `releasePosition`。
 *
 * `SwiftAction` 不帶任何引數,因此那個位置是透過 `lastReleasedPosition` 讀回去的。與
 * `ListItemSelectedListener.selectedPosition` 及 `TableContainer.tappedRow` 是同一種安排。
 */
class SwiftRowRecycler(private val adapter: CustomListAdapter) : AbsListView.RecyclerListener {
    var action: SwiftAction? = null

    var lastReleasedPosition = -1
        private set

    override fun onMovedToScrapHeap(view: View) {
        val position = adapter.releasePosition(view)
        if (position < 0) return
        lastReleasedPosition = position
        action?.call()
    }
}
