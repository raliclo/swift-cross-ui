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
         * `AbsListView` calls `setActivated(true)` on a checked row's view when
         * that view is not `Checkable`, and these views are plain containers, so
         * the flag arrived and nothing drew it: a row selected from code
         * measured pure white, while the same row selected by a tap measured 237
         * -- a tap is the ListView's own selector and takes a different path.
         *
         * The same 0x32a1a1a1 the selector uses, so a row selected from code and
         * a row under the finger look alike rather than merely both looking
         * selected.
         *
         * Applied as the foreground, not the background. A row's background
         * belongs to whatever `.background()` the app put there, and taking it
         * would make selection and styling the same property. The colour is
         * translucent by design: a wash over the row, not a fill.
         *
         * 一個被選取的列所穿戴的高亮。
         *
         * 當某列的 view 並非 `Checkable` 時，`AbsListView` 會對它呼叫 `setActivated(true)`；而這些
         * view 是普通容器，因此那個旗標抵達了、卻沒有任何東西把它畫出來：以程式選取的列量得純白，
         * 而同一列以點擊選取則量得 237——點擊走的是 ListView 自己的 selector，那是另一條路徑。
         *
         * 採用與 selector 相同的 0x32a1a1a1，使「以程式選取的列」與「手指底下的列」看起來一樣，
         * 而不只是兩者都看起來「像被選取了」。
         *
         * 施加於 foreground 而非 background。一列的 background 屬於 app 以 `.background()` 放在
         * 那裡的東西，佔用它會讓「選取」與「樣式」變成同一個屬性。這個顏色刻意是半透明的：它是
         * 覆蓋在該列之上的一層薄色，不是填充。
         */
        private fun selectionOverlay(): StateListDrawable {
            val drawable = StateListDrawable()
            drawable.addState(
                intArrayOf(android.R.attr.state_activated),
                ColorDrawable(0x32a1a1a1),
            )
            drawable.addState(intArrayOf(), ColorDrawable(Color.TRANSPARENT))
            return drawable
        }
    }

    private var views = arrayOf<View>()
    private var heights = intArrayOf()

    var isEnabled = true

    fun setViews(newViews: Array<View>, newHeights: IntArray) {
        require(newViews.size == newHeights.size)
        views = newViews
        heights = newHeights
        notifyDataSetChanged()
    }

    override fun areAllItemsEnabled() = isEnabled

    override fun isEnabled(position: Int) = isEnabled

    override fun getCount() = views.size

    override fun getItem(position: Int) = views[position]

    override fun getItemId(position: Int) = position.toLong()

    override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
        val view = views[position]

        // A drawable per row rather than one shared: a StateListDrawable keeps
        // its own current state, so sharing one would make every row show the
        // state of whichever row was configured last.
        // 每一列各自一個 drawable，而非共用一個：StateListDrawable 會保有它自己的當前狀態，因此
        // 共用會使每一列都顯示「最後被設定的那一列」的狀態。
        if (view.foreground == null) {
            view.foreground = selectionOverlay()
        }

        val height = heights[position] - (parent as ListView).dividerHeight

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
