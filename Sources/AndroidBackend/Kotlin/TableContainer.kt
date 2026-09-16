package dev.swiftcrossui.androidbackend

import android.app.Activity
import android.graphics.Canvas
import android.graphics.Paint
import android.util.TypedValue
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup

/**
 * `Table` on Android.
 *
 * Before this class `BackendFeatures.Tables` was unimplemented and the modifier went through
 * `@CastBackend`, which expands to `fatalError`. P23 and P26 did not render a table badly -- they
 * died at launch with "'AndroidBackend' does not implement 'BackendFeatures.Tables'".
 *
 * A grid rather than a `TableLayout`. Android's `TableLayout` sizes its columns from their
 * contents, and the layout system above this has already decided every cell's size and expects the
 * columns to be equal -- which is what UIKitBackend's `TableWidget` does, and taking the same rule
 * means the two phone platforms draw the same table. A `TableLayout` would produce a different
 * geometry from the same view tree, and a screenshot that could not be read against the other one.
 *
 * Headers and cells are separate lists rather than one child list with the first N treated as
 * headers, because `setColumnLabels` and `setCells` are separate calls that arrive in either order,
 * and a single list would make each one need to know what the other had most recently done.
 *
 * Android 上的 `Table`。
 *
 * 在本類別存在之前，`BackendFeatures.Tables` 是未實作的，而相關 modifier 走的是 `@CastBackend` ——該 macro 會展開為
 * `fatalError`。P23 與 P26 並不是「表格畫得不好」，而是直接在啟動時死於 「'AndroidBackend' does not implement
 * 'BackendFeatures.Tables'」。
 *
 * 採用格線而非 `TableLayout`。Android 的 `TableLayout` 會依內容決定各欄寬度，而其上的版面系統早已 決定了每一個 cell 的尺寸，並預期各欄等寬——那正是
 * UIKitBackend 的 `TableWidget` 所做的，而採用 同一條規則意味著兩個手機平台會畫出同樣的表格。`TableLayout` 會從同一棵 view tree
 * 產生不同的幾何， 於是它的截圖無法與另一張對照著讀。
 *
 * header 與 cell 分成兩個清單，而不是「用單一子元件清單、把前 N 個當作 header」，因為 `setColumnLabels` 與 `setCells`
 * 是兩個獨立的呼叫、抵達順序不定，而單一清單會使兩者都必須知道 對方最近做了什麼。
 */
class TableContainer(val activity: Activity) : ViewGroup(activity) {
    private val headers = mutableListOf<View>()
    private val cells = mutableListOf<View>()
    private val rowHeights = mutableListOf<Int>()

    var headerHeight = 0

    // MARK: Row selection (#125)

    /**
     * The highlight, drawn rather than made into a child view.
     *
     * **The opposite choice from UIKitBackend's `TableWidget`, and for a platform reason rather
     * than a preference.** A `ViewGroup` draws itself in `onDraw` and its children afterwards in
     * `dispatchDraw`, so anything painted here is *already* behind every cell -- no ordering to
     * maintain, and nothing for `clearCells` to disturb. UIKit has no such split: a `UIView` that
     * draws in `draw(_:)` still has its subviews composited over it by a separate mechanism, so
     * there the band had to be a sibling sent to the back on every pass.
     *
     * `setWillNotDraw(false)` is required. A `ViewGroup` is assumed to draw nothing and its
     * `onDraw` is skipped entirely by default -- which fails as a silent no-op: the colour is
     * right, the rectangle is right, and nothing appears.
     *
     * 那道高亮，是**畫**出來的，而不是做成一個子 view。
     *
     * **與 UIKitBackend 的 `TableWidget` 相反的選擇，而理由來自平台，不是偏好。** 一個 `ViewGroup` 會先在 `onDraw`
     * 畫自己，之後才在 `dispatchDraw` 畫它的子元件——因此在此處畫下的任何東西，**本來就**在每一個 cell 之後：沒有順序要維護，
     * 也沒有東西會被 `clearCells` 弄亂。UIKit 沒有這個區分：一個在 `draw(_:)` 中作畫的 `UIView`，其 subview
     * 仍會由另一套機制合成在它之上，所以在那邊，色帶必須是一個「每一輪都被送到最底層的同層 view」。
     *
     * `setWillNotDraw(false)` 是必要的。一個 `ViewGroup` 被假定為什麼都不畫，其 `onDraw` 預設會被整個略過
     * ——而那會以一次無聲的空操作呈現：顏色是對的、矩形是對的，然後什麼也沒出現。
     */
    private val selectionPaint = Paint()

    /**
     * -1 for "no row selected", because this crosses JNI.
     *
     * The Swift side of this protocol is `Int?`. There is no `Int?` in a Java signature, and a
     * boxed `Integer` would make every call site on both sides handle a null that only exists to
     * carry the same information -1 already carries. `AdapterView.INVALID_POSITION` is -1 for the
     * same reason, and the selectable list above already speaks it.
     *
     * -1 代表「沒有任何一列被選取」，因為這要穿過 JNI。
     *
     * 本協定在 Swift 那一側是 `Int?`。Java 簽章裡沒有 `Int?`，而一個裝箱的 `Integer` 會讓兩側每一個呼叫點都得處理一個 null
     * ——那個 null 存在的唯一目的，是攜帶 -1 早已攜帶的同一項資訊。 `AdapterView.INVALID_POSITION` 是 -1 也出於同一個理由，
     * 而上面那個可選取清單已經在講這套話了。
     */
    var selectedRow = -1
        set(value) {
            if (field == value) return
            field = value
            invalidate()
        }

    /**
     * The row a tap landed on, read back by the Swift closure `selectionAction` calls.
     *
     * `SwiftAction` carries no arguments -- it is a `() -> Void`. The value therefore has to be
     * somewhere the closure can reach, which is here. Same arrangement as
     * `ListItemSelectedListener.selectedPosition`.
     *
     * 一次點擊落在哪一列——由 `selectionAction` 所呼叫的那個 Swift closure 讀回去。
     *
     * `SwiftAction` 不帶任何引數,它是一個 `() -> Void`。因此那個值必須放在該 closure 到得了的地方,也就是這裡。
     * 與 `ListItemSelectedListener.selectedPosition` 是同一種安排。
     */
    var tappedRow = -1
        private set

    var selectionAction: SwiftAction? = null

    init {
        setWillNotDraw(false)
    }

    /**
     * Whether a tap is worth reporting, which is not the same as whether it hit a row.
     *
     * A tap on the header or below the last row reports -1: that is a deselection the user
     * performed, and on a touchscreen it is the only way to perform one. Returning early there
     * would leave a table whose selection can be set by hand and never cleared by hand.
     *
     * 一次點擊值不值得回報,與它有沒有打中某一列並不是同一件事。
     *
     * 點在表頭上、或點在最後一列下方,回報的是 -1:那是使用者做出的一次取消選取,而在觸控螢幕上,那是做出這件事的
     * 唯一方式。在那裡提早返回,會留下一個「可以用手設定選取、卻永遠無法用手清除」的表格。
     */
    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (selectionAction == null) return false
        when (event.action) {
            // Consumed at DOWN, or UP never arrives. Android sends the rest of a gesture to
            // whoever accepted its first event; declining the press and then expecting the
            // release is the shape that produces a table nothing can select.
            // 在 DOWN 時就消費掉,否則 UP 永遠不會抵達。Android 會把一個手勢的其餘部分送給「接受了它第一個事件」
            // 的那一方;拒絕了按下、卻期待收到放開,正是那種「什麼都選不動的表格」的形狀。
            MotionEvent.ACTION_DOWN -> return true
            MotionEvent.ACTION_UP -> {
                tappedRow = rowAt(event.y.toInt())
                selectionAction?.call()
                return true
            }
        }
        return false
    }

    private fun rowAt(y: Int): Int {
        if (y < headerHeight) return -1
        var top = headerHeight
        for (row in rowHeights.indices) {
            val bottom = top + rowHeights[row]
            if (y < bottom) return row
            top = bottom
        }
        return -1
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)

        val row = selectedRow
        if (row < 0 || row >= rowHeights.size) return

        var top = headerHeight
        for (index in 0..<row) {
            top += rowHeights[index]
        }

        selectionPaint.color = highlightColor()
        canvas.drawRect(
            0f,
            top.toFloat(),
            width.toFloat(),
            (top + rowHeights[row]).toFloat(),
            selectionPaint,
        )
    }

    /**
     * The theme's own highlight, with the selectable list's colour as the fallback.
     *
     * `colorControlHighlight` is what the platform paints under a pressed row, so a table that
     * uses it agrees with the rest of the device rather than with a constant chosen here. The
     * fallback is the value `createSelectableListView` arrived at by measurement on an Android 16
     * emulator -- so a theme that does not define the attribute still produces a table and a list
     * that highlight the same way.
     *
     * 主題自己的高亮色,而以那個可選取清單的顏色作為退路。
     *
     * `colorControlHighlight` 正是這個平台在一列被按下時所塗的顏色,因此採用它的表格,是與這台裝置的其餘部分一致,
     * 而不是與此處挑定的某個常數一致。退路值是 `createSelectableListView` 在 Android 16 模擬器上量出來的那一個
     * ——於是即使某個主題沒有定義該屬性,表格與清單仍會以同樣的方式高亮。
     */
    private fun highlightColor(): Int {
        val value = TypedValue()
        val resolved =
            context.theme.resolveAttribute(android.R.attr.colorControlHighlight, value, true)
        if (!resolved) return 0x32a1a1a1
        return if (value.resourceId != 0) {
            context.getColor(value.resourceId)
        } else {
            value.data
        }
    }

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
            if (requestedWidth >= 0) requestedWidth else View.MeasureSpec.getSize(widthMeasureSpec)
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
