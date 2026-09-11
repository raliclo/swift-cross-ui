package dev.swiftcrossui.androidbackend.lists

import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.StateListDrawable
import android.view.View
import android.view.ViewGroup
import android.widget.BaseAdapter
import android.widget.ListView

// All the existing concrete adapters require an XML resource ID.
class CustomListAdapter : BaseAdapter() {
    companion object {
        /**
         * The highlight a selected row wears.
         *
         * `AbsListView` calls `setActivated(true)` on a checked row's view when that view is not
         * `Checkable`, and these views are plain containers, so the flag arrived and nothing drew
         * it: a row selected from code measured pure white, while the same row selected by a tap
         * measured 237 -- a tap is the ListView's own selector and takes a different path.
         *
         * The same 0x32a1a1a1 the selector uses, so a row selected from code and a row under the
         * finger look alike rather than merely both looking selected.
         *
         * Applied as the foreground, not the background. A row's background belongs to whatever
         * `.background()` the app put there, and taking it would make selection and styling the
         * same property. The colour is translucent by design: a wash over the row, not a fill.
         *
         * 一個被選取的列所穿戴的高亮。
         *
         * 當某列的 view 並非 `Checkable` 時，`AbsListView` 會對它呼叫 `setActivated(true)`；而這些 view
         * 是普通容器，因此那個旗標抵達了、卻沒有任何東西把它畫出來：以程式選取的列量得純白， 而同一列以點擊選取則量得 237——點擊走的是 ListView 自己的
         * selector，那是另一條路徑。
         *
         * 採用與 selector 相同的 0x32a1a1a1，使「以程式選取的列」與「手指底下的列」看起來一樣， 而不只是兩者都看起來「像被選取了」。
         *
         * 施加於 foreground 而非 background。一列的 background 屬於 app 以 `.background()` 放在
         * 那裡的東西，佔用它會讓「選取」與「樣式」變成同一個屬性。這個顏色刻意是半透明的：它是 覆蓋在該列之上的一層薄色，不是填充。
         */
        private fun selectionOverlay(): StateListDrawable {
            val drawable = StateListDrawable()
            drawable.addState(intArrayOf(android.R.attr.state_activated), ColorDrawable(0x32a1a1a1))
            drawable.addState(intArrayOf(), ColorDrawable(Color.TRANSPARENT))
            return drawable
        }
    }

    private var views = arrayOf<View>()
    private var heights = intArrayOf()

    /**
     * Non-zero when rows come from Swift one at a time.
     *
     * The id, rather than a callback object, because the way back into Swift here is a JNI native
     * method and a native method has no captured state -- it gets its arguments and nothing else.
     * `MainRunLoopTickler` uses the same `external fun` contract; this one just carries which list
     * is asking.
     *
     * 非零時，代表列是由 Swift 一次交出一列的。
     *
     * 使用一個 id 而非一個 callback 物件，因為此處回到 Swift 的路徑是一個 JNI native method，而 native method
     * 沒有被捕捉的狀態——它只拿得到它的引數，沒有別的。`MainRunLoopTickler` 用的是 同一套 `external fun` 契約;這一個只是多帶著「是哪一份清單在問」。
     */
    private var lazyId = 0
    private var lazyCount = 0
    private var estimatedHeight = 0

    fun setLazy(id: Int, count: Int, estimatedHeight: Int) {
        lazyId = id
        lazyCount = count
        this.estimatedHeight = estimatedHeight
        // The eager arrays are cleared, not left behind: two answers to the same
        // question would be resolved by whichever branch is read first.
        // eager 的那兩個陣列被清空而不是留著:同一個問題的兩個答案，會由「先被讀到的那個分支」決定。
        views = arrayOf()
        heights = intArrayOf()
        notifyDataSetChanged()
    }

    /** Asks Swift to build one row. Returns null when the index is out of range. */
    /** 請 Swift 建出某一列。索引超出範圍時回傳 null。 */
    external fun swiftViewForRow(id: Int, position: Int): View?

    /** The height Swift reported for a row it has already built, or 0. */
    /** Swift 為某一列所回報的高度(該列必須已經被建立過)，否則為 0。 */
    external fun swiftKnownHeightForRow(id: Int, position: Int): Int

    var isEnabled = true

    fun setViews(newViews: Array<View>, newHeights: IntArray) {
        require(newViews.size == newHeights.size)
        views = newViews
        heights = newHeights
        notifyDataSetChanged()
    }

    override fun areAllItemsEnabled() = isEnabled

    override fun isEnabled(position: Int) = isEnabled

    override fun getCount() = if (lazyId != 0) lazyCount else views.size

    override fun getItem(position: Int): Any? = if (lazyId != 0) position else views[position]

    override fun getItemId(position: Int) = position.toLong()

    override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
        val view =
            if (lazyId != 0) {
                swiftViewForRow(lazyId, position) ?: View(parent.context)
            } else {
                views[position]
            }

        // A drawable per row rather than one shared: a StateListDrawable keeps
        // its own current state, so sharing one would make every row show the
        // state of whichever row was configured last.
        // 每一列各自一個 drawable，而非共用一個：StateListDrawable 會保有它自己的當前狀態，因此
        // 共用會使每一列都顯示「最後被設定的那一列」的狀態。
        if (view.foreground == null) {
            view.foreground = selectionOverlay()
        }

        val height =
            if (lazyId != 0) {
                // The real height if this row has been built, the estimate if it has not.
                // A row is always built by the line above before this runs, so the known
                // height is the normal case and the estimate is the fallback for a row
                // Swift declined to build.
                // 若該列已被建立則用真實高度，未建立則用估計值。在此行執行之前，上方那一行一定已經
                // 把該列建出來了，因此「已知高度」才是常態，而估計值是「Swift 拒絕建立該列」時的退路。
                val known = swiftKnownHeightForRow(lazyId, position)
                (if (known > 0) known else estimatedHeight) - (parent as ListView).dividerHeight
            } else {
                heights[position] - (parent as ListView).dividerHeight
            }

        view.layoutParams =
            if (convertView === view) {
                // Reuse the existing layoutParams when applicable in case it's a subclass of
                // ViewGroup.LayoutParams
                val lp = convertView.layoutParams
                lp.height = height
                lp.width = parent.width
                lp
            } else {
                ViewGroup.LayoutParams(parent.width, height)
            }

        return view
    }
}
