package dev.swiftcrossui.androidbackend

import android.view.View
import java.util.WeakHashMap

/**
 * Turning off pointer input for a view and everything inside it.
 *
 * UIKit has one property for this (`isUserInteractionEnabled`) and AppKit is
 * given one by `AppKitHitTestingContainer`. Android has neither: `setEnabled`
 * does not reach a ViewGroup's children, and there is no flag that means "this
 * subtree takes no touches".
 *
 * What Android does have is the dispatch rule this is built on. `ViewGroup`
 * walks its children topmost-first and calls `dispatchTouchEvent` on each; a
 * child that returns `false` is passed over and **the walk continues to the
 * child underneath**. So refusing is not the same as consuming, and refusing is
 * what `allowsHitTesting(false)` means: P10 places an opaque `Color.orange`
 * over a button and requires the press to reach the button. A view that
 * consumed the touch would leave that counter at zero and look like a pass.
 *
 * Two shapes, because a view can be either:
 *
 * - **A leaf** -- a Button, a Text. Clearing `clickable`, `longClickable` and
 *   `focusable` makes `View.onTouchEvent` return false, which is the refusal.
 * - **A subtree** -- a `CustomContainer`. It overrides `dispatchTouchEvent` and
 *   asks this object, so the whole subtree is skipped in one check rather than
 *   every descendant being walked and flagged.
 *
 * The previous flags are saved, because `allowsHitTesting` takes a Bool that is
 * usually bound to state and has to be reversible. Restoring a Button to
 * `clickable = true` is right; restoring a Text to it is not, and only the view
 * knows which it was. The map is weak: a view whose window has gone should not
 * be held alive by this.
 *
 * 讓一個 view 與其內部的一切都不接收指標輸入。
 *
 * UIKit 有一個對應的屬性（`isUserInteractionEnabled`），AppKit 則由
 * `AppKitHitTestingContainer` 提供一個。Android 兩者皆無：`setEnabled` 不會傳達到 ViewGroup 的
 * 子元件，而且沒有任何旗標表示「這棵子樹不接收觸控」。
 *
 * Android 確實具備的，是本機制所依據的那條分派規則。`ViewGroup` 由最上層往下走訪其子元件，對每一個
 * 呼叫 `dispatchTouchEvent`；回傳 `false` 的子元件會被略過，而**走訪會繼續往下一個子元件進行**。
 * 因此「拒收」與「吃掉」並不相同，而 `allowsHitTesting(false)` 的意思正是拒收：P10 把一個不透明的
 * `Color.orange` 蓋在按鈕上，並要求該次按壓抵達按鈕。一個把觸控吃掉的 view 會讓那個計數維持為零，
 * 而那看起來像是通過。
 *
 * 兩種形狀，因為一個 view 可能是其中任一種：
 *
 * - **葉節點**——Button、Text。清除 `clickable`、`longClickable` 與 `focusable` 會使
 *   `View.onTouchEvent` 回傳 false，那就是拒收。
 * - **子樹**——`CustomContainer`。它覆寫 `dispatchTouchEvent` 並詢問本物件，因此整棵子樹只需一次
 *   檢查即可略過，而不必走訪並標記每一個後代。
 *
 * 原有的旗標會被保存，因為 `allowsHitTesting` 接受的 Bool 通常繫結於狀態，必須是可逆的。把 Button
 * 還原為 `clickable = true` 是對的，把 Text 還原成那樣則不是——而只有該 view 自己知道它原本是哪一種。
 * 該 map 是弱參考的：一個視窗已消失的 view 不應被此處持有而無法回收。
 */
object HitTesting {
    private class Saved(
        val clickable: Boolean,
        val longClickable: Boolean,
        val focusable: Int,
    )

    private val disabled = WeakHashMap<View, Saved>()

    @JvmStatic
    fun setHitTesting(view: View, allowsHitTesting: Boolean) {
        if (allowsHitTesting) {
            val saved = disabled.remove(view) ?: return
            view.isClickable = saved.clickable
            view.isLongClickable = saved.longClickable
            view.focusable = saved.focusable
            return
        }

        // Guarded, so a second `false` does not save the already-cleared flags
        // as the values to restore -- which would turn a Button permanently
        // dead. SwiftCrossUI calls `commit` on every update, so the same view
        // is disabled again on every frame it stays disabled.
        //
        // 加上防護，使第二次 `false` 不會把「已被清除的旗標」存成待還原的值——那會讓一顆 Button
        // 永久失效。SwiftCrossUI 每次更新都會呼叫 `commit`，因此同一個 view 在其保持停用的每一格
        // 都會被再次停用。
        if (!disabled.containsKey(view)) {
            disabled[view] =
                Saved(view.isClickable, view.isLongClickable, view.focusable)
        }
        view.isClickable = false
        view.isLongClickable = false
        view.focusable = View.NOT_FOCUSABLE
    }

    @JvmStatic fun isDisabled(view: View): Boolean = disabled.containsKey(view)
}
