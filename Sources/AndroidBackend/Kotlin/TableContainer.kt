package dev.swiftcrossui.androidbackend

import android.app.Activity
import android.view.View
import android.view.ViewGroup

/**
 * `Table` on Android.
 *
 * Before this class `BackendFeatures.Tables` was unimplemented and the modifier
 * went through `@CastBackend`, which expands to `fatalError`. P23 and P26 did
 * not render a table badly -- they died at launch with
 * "'AndroidBackend' does not implement 'BackendFeatures.Tables'".
 *
 * A grid rather than a `TableLayout`. Android's `TableLayout` sizes its columns
 * from their contents, and the layout system above this has already decided
 * every cell's size and expects the columns to be equal -- which is what
 * UIKitBackend's `TableWidget` does, and taking the same rule means the two
 * phone platforms draw the same table. A `TableLayout` would produce a
 * different geometry from the same view tree, and a screenshot that could not
 * be read against the other one.
 *
 * Headers and cells are separate lists rather than one child list with the
 * first N treated as headers, because `setColumnLabels` and `setCells` are
 * separate calls that arrive in either order, and a single list would make each
 * one need to know what the other had most recently done.
 *
 * Android 上的 `Table`。
 *
 * 在本類別存在之前，`BackendFeatures.Tables` 是未實作的，而相關 modifier 走的是 `@CastBackend`
 * ——該 macro 會展開為 `fatalError`。P23 與 P26 並不是「表格畫得不好」，而是直接在啟動時死於
 * 「'AndroidBackend' does not implement 'BackendFeatures.Tables'」。
 *
 * 採用格線而非 `TableLayout`。Android 的 `TableLayout` 會依內容決定各欄寬度，而其上的版面系統早已
 * 決定了每一個 cell 的尺寸，並預期各欄等寬——那正是 UIKitBackend 的 `TableWidget` 所做的，而採用
 * 同一條規則意味著兩個手機平台會畫出同樣的表格。`TableLayout` 會從同一棵 view tree 產生不同的幾何，
 * 於是它的截圖無法與另一張對照著讀。
 *
 * header 與 cell 分成兩個清單，而不是「用單一子元件清單、把前 N 個當作 header」，因為
 * `setColumnLabels` 與 `setCells` 是兩個獨立的呼叫、抵達順序不定，而單一清單會使兩者都必須知道
 * 對方最近做了什麼。
 */
class TableContainer(val activity: Activity) : ViewGroup(activity) {
    private val headers = mutableListOf<View>()
    private val cells = mutableListOf<View>()
    private val rowHeights = mutableListOf<Int>()

    var headerHeight = 0

    fun clearHeaders() {
        headers.forEach { removeView(it) }
        headers.clear()
    }

    fun addHeader(view: View) {
        headers.add(view)
        addView(view)
    }

    // Removed from the view, not just dropped from the list. A cell whose
    // widget the view graph has replaced stays on screen otherwise, drawn over
    // its successor at whatever position it last had. Same note as
    // UIKitBackend's TableWidget, and for the same reason.
    //
    // 從 view 中移除，而不只是從清單中丟棄。否則，view graph 已替換掉其 widget 的 cell 仍會留在
    // 畫面上，以它最後所在的位置覆蓋在後繼者之上。與 UIKitBackend 的 TableWidget 是同一條說明，
    // 理由也相同。
    fun clearCells() {
        cells.forEach { removeView(it) }
        cells.clear()
        rowHeights.clear()
    }

    fun addCell(view: View) {
        cells.add(view)
        addView(view)
    }

    fun addRowHeight(height: Int) {
        rowHeights.add(height)
    }

    private fun columnWidth(width: Int): Int {
        return if (headers.isEmpty()) width else width / headers.size
    }

    override protected fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        // The same sentinel guard as CustomContainer.onMeasure: a negative
        // layoutParams width is MATCH_PARENT or WRAP_CONTENT, not a size.
        // 與 CustomContainer.onMeasure 相同的哨兵值防護：負的 layoutParams 寬度代表 MATCH_PARENT
        // 或 WRAP_CONTENT，而不是一個尺寸。
        val requestedWidth = layoutParams?.width ?: -1
        val requestedHeight = layoutParams?.height ?: -1
        val width =
            if (requestedWidth >= 0) requestedWidth
            else View.MeasureSpec.getSize(widthMeasureSpec)
        val height =
            if (requestedHeight >= 0) requestedHeight
            else View.MeasureSpec.getSize(heightMeasureSpec)
        setMeasuredDimension(width, height)

        val column = columnWidth(width)
        headers.forEach { measureAt(it, column, headerHeight) }
        for ((index, cell) in cells.withIndex()) {
            val row = if (headers.isEmpty()) 0 else index / headers.size
            measureAt(cell, column, rowHeights.getOrElse(row) { 0 })
        }
    }

    private fun measureAt(view: View, width: Int, height: Int) {
        val safeWidth = Math.max(0, width)
        val safeHeight = Math.max(0, height)
        view.layoutParams?.let {
            it.width = safeWidth
            it.height = safeHeight
        }
        view.measure(
            View.MeasureSpec.makeMeasureSpec(safeWidth, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(safeHeight, View.MeasureSpec.EXACTLY),
        )
    }

    override protected fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        val column = columnWidth(r - l)

        for ((index, header) in headers.withIndex()) {
            val x = index * column
            header.layout(x, 0, x + column, headerHeight)
        }

        if (headers.isEmpty()) {
            return
        }

        var y = headerHeight
        for (row in rowHeights.indices) {
            val rowHeight = rowHeights[row]
            for (col in 0..<headers.size) {
                val index = row * headers.size + col
                if (index >= cells.size) {
                    break
                }
                val x = col * column
                cells[index].layout(x, y, x + column, y + rowHeight)
            }
            y += rowHeight
        }
    }
}
