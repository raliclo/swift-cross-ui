package dev.swiftcrossui.androidbackend.lists

import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.StateListDrawable
import android.view.View
import android.view.ViewGroup
import android.widget.BaseAdapter
import android.widget.ListView
import dev.swiftcrossui.androidbackend.SwiftObject

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

    // `.listStyle(.sidebar)`: the selected row wears a pill inset from the
    // edges, as a Material navigation drawer's active indicator, instead of the
    // full-width grey. Set by AndroidBackendHelpers.setListSidebar. Which kind
    // each row's overlay is gets recorded, so a style change replaces it.
    // `.listStyle(.sidebar)`:被選取的列戴上內縮的膠囊，如 Material navigation drawer 的 active indicator,
    // 而非整列的灰色。由 AndroidBackendHelpers.setListSidebar 設定。記下每一列的 overlay 是哪一種，樣式改變時才換。
    private var sidebar = false
    private var pillColor = 0
    private var density = 1f
    private val overlayIsSidebar = java.util.WeakHashMap<View, Boolean>()

    fun setSidebarStyle(on: Boolean, color: Int, density: Float) {
        sidebar = on
        pillColor = color
        this.density = density
        notifyDataSetChanged()
    }

    // The background a row without one of its own is drawn on (0 = none); see
    // AndroidBackendHelpers.setListSidebar. Only rows this adapter painted are
    // repainted or cleared, so an app's own `.background()` on a row stays.
    // 沒有自己背景的列所畫的背景(0 = 無);見 AndroidBackendHelpers.setListSidebar。只重畫或清除本 adapter 畫過的列，
    // 所以 app 在列上的 `.background()` 不會被動到。
    private var rowBackground = 0
    private val paintedRows = java.util.WeakHashMap<View, Boolean>()

    fun setRowBackground(color: Int) {
        if (rowBackground == color) return
        rowBackground = color
        notifyDataSetChanged()
    }

    private fun paintRow(view: View) {
        val ours = paintedRows[view] == true
        if (view.background != null && !ours) return
        if (rowBackground == 0) {
            if (ours) view.background = null
            paintedRows.remove(view)
        } else {
            view.setBackgroundColor(rowBackground)
            paintedRows[view] = true
        }
    }

    private fun sidebarOverlay(): StateListDrawable {
        val pill = android.graphics.drawable.GradientDrawable()
        pill.cornerRadius = 28 * density
        pill.setColor(pillColor)
        val horizontal = (8 * density).toInt()
        val vertical = (2 * density).toInt()
        val drawable = StateListDrawable()
        drawable.addState(
            intArrayOf(android.R.attr.state_activated),
            android.graphics.drawable.InsetDrawable(pill, horizontal, vertical, horizontal, vertical)
        )
        drawable.addState(intArrayOf(), ColorDrawable(Color.TRANSPARENT))
        return drawable
    }

    private var views = arrayOf<View>()
    private var heights = intArrayOf()

    /**
     * Which row each handed-out view is showing, for `SwiftRowRecycler`.
     *
     * Two maps rather than one, because both questions get asked. `AbsListView` scraps a *view*
     * and gives no position, so the reverse direction answers "which row was this"; and a position
     * can be handed a NEW view while the old one is still on its way to the scrap heap, so the
     * forward direction answers "is this still the view for that row". Reporting a release for a
     * row that has already been rebuilt would drop a node the list is currently displaying, which
     * leaves a visible row that nothing updates afterwards.
     *
     * `IdentityHashMap` because `View` inherits `Object.equals`, but two distinct rows are two
     * distinct views and must never collapse into one key if a subclass ever overrides it.
     *
     * 每一個被交出去的 view 正在顯示哪一列——供 `SwiftRowRecycler` 使用。
     *
     * 用兩張表而不是一張,因為兩個問題都會被問到。`AbsListView` 丟棄的是一個 **view**、而且不給位置,
     * 因此反向那張回答「這個 view 先前是哪一列」;而一個位置可能在舊的 view 還在前往 scrap heap 的
     * 路上時,就已經被交付了一個**新的** view,因此正向那張回答「它是否仍是那一列的 view」。
     * 為一個**已經被重建**的列回報釋放,會丟掉一個清單當下正在顯示的節點,留下一個其後不再被任何東西
     * 更新的可見列。
     *
     * 使用 `IdentityHashMap`,因為 `View` 繼承的是 `Object.equals`;但兩個不同的列就是兩個不同的
     * view,萬一某個子類別覆寫了它,它們也絕不可以塌縮成同一把鍵。
     */
    private val positionForView = java.util.IdentityHashMap<View, Int>()
    private val viewForPosition = mutableMapOf<Int, View>()

    /**
     * The row this view had been showing, or -1 if it is no longer that row's view.
     *
     * 這個 view 先前在顯示的那一列;若它已不再是該列的 view 則為 -1。
     */
    fun releasePosition(view: View): Int {
        val position = positionForView.remove(view) ?: return -1
        if (viewForPosition[position] !== view) return -1
        viewForPosition.remove(position)
        return position
    }

    /**
     * Set when rows come from Swift one at a time: the Swift row source, boxed.
     *
     * Held here, by the adapter, rather than in a Swift table keyed by an id. The native methods
     * below are instance methods, so Swift reads the source back from the adapter that asks; the
     * source then lives exactly as long as this adapter, and two lists can never share one. A
     * table keyed by the adapter's Swift wrapper did neither: the wrapper is made per call, so
     * each update added an entry, and a freed wrapper's identity could be reused by another
     * list's.
     *
     * 列由 Swift 一次交出一列時設定：裝箱的 Swift 列來源。
     *
     * 由 adapter 在此持有，而不是放在一張以 id 為鍵的 Swift 表裡。下方的 native method 是實例方法，所以 Swift 從
     * 發問的那個 adapter 讀回來源；來源的壽命因此恰好等於這個 adapter,兩份清單也不可能共用一份。以 adapter 的
     * Swift 包裝物件為鍵的表兩者都做不到：包裝物件每次呼叫都新建，所以每次更新都多一筆，而被釋放的包裝物件的身分
     * 可能被另一份清單的重複使用。
     */
    private var lazyRows: SwiftObject? = null
    private var lazyCount = 0
    private var estimatedHeight = 0

    fun getLazyRows(): SwiftObject? = lazyRows

    fun setLazy(rows: SwiftObject, count: Int, estimatedHeight: Int) {
        lazyRows = rows
        lazyCount = count
        this.estimatedHeight = estimatedHeight
        // The eager arrays are cleared, not left behind: two answers to the same
        // question would be resolved by whichever branch is read first.
        // eager 的那兩個陣列被清空而不是留著:同一個問題的兩個答案，會由「先被讀到的那個分支」決定。
        views = arrayOf()
        heights = intArrayOf()
        notifyDataSetChanged()
    }

    /**
     * The row-release listener, kept so a later commit replaces its handler instead of
     * installing another. 列釋放的 listener,留著讓之後的 commit 替換它的 handler,而不是再裝一個。
     */
    var rowRecycler: SwiftRowRecycler? = null

    /** Asks Swift to build one row. Returns null when the index is out of range. */
    /** 請 Swift 建出某一列。索引超出範圍時回傳 null。 */
    external fun swiftViewForRow(position: Int): View?

    /** The height Swift reported for a row it has already built, or 0. */
    /** Swift 為某一列所回報的高度(該列必須已經被建立過)，否則為 0。 */
    external fun swiftKnownHeightForRow(position: Int): Int

    var isEnabled = true

    fun setViews(newViews: Array<View>, newHeights: IntArray) {
        require(newViews.size == newHeights.size)
        views = newViews
        heights = newHeights
        notifyDataSetChanged()
    }

    override fun areAllItemsEnabled() = isEnabled

    override fun isEnabled(position: Int) = isEnabled

    override fun getCount() = if (lazyRows != null) lazyCount else views.size

    override fun getItem(position: Int): Any? = if (lazyRows != null) position else views[position]

    override fun getItemId(position: Int) = position.toLong()

    override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
        val view =
            if (lazyRows != null) {
                swiftViewForRow(position) ?: View(parent.context)
            } else {
                views[position]
            }

        // A drawable per row rather than one shared: a StateListDrawable keeps
        // its own current state, so sharing one would make every row show the
        // state of whichever row was configured last.
        // 每一列各自一個 drawable，而非共用一個：StateListDrawable 會保有它自己的當前狀態，因此
        // 共用會使每一列都顯示「最後被設定的那一列」的狀態。
        paintRow(view)
        val ours = overlayIsSidebar[view]
        if (view.foreground == null || (ours != null && ours != sidebar)) {
            view.foreground = if (sidebar) sidebarOverlay() else selectionOverlay()
            overlayIsSidebar[view] = sidebar
        }

        // Recorded AFTER the view exists and before it is returned, so a scrap arriving later can
        // be turned back into a row index. Overwriting the forward entry is what makes a stale
        // scrap answer -1 in `releasePosition`.
        // 在該 view 已經存在、且尚未被回傳之前記下,好讓稍後抵達的一次 scrap 能被還原成一個列索引。
        // 覆寫正向那筆,正是讓一次過期的 scrap 在 `releasePosition` 中得到 -1 的東西。
        positionForView[view] = position
        viewForPosition[position] = view

        val height =
            if (lazyRows != null) {
                // The real height if this row has been built, the estimate if it has not.
                // A row is always built by the line above before this runs, so the known
                // height is the normal case and the estimate is the fallback for a row
                // Swift declined to build.
                // 若該列已被建立則用真實高度，未建立則用估計值。在此行執行之前，上方那一行一定已經
                // 把該列建出來了，因此「已知高度」才是常態，而估計值是「Swift 拒絕建立該列」時的退路。
                val known = swiftKnownHeightForRow(position)
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
