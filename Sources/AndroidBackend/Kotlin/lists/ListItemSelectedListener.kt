package dev.swiftcrossui.androidbackend.lists

import android.view.View
import android.widget.AdapterView
import dev.swiftcrossui.androidbackend.SwiftAction

/**
 * Both listeners, because on a touchscreen only one of them ever fires.
 *
 * `OnItemSelectedListener` is about the *focused* item -- the one a D-pad or a
 * trackball moved to. A ListView on a touchscreen is in touch mode, where there
 * is no focused item at all, so tapping a row fires `onItemClick` and never
 * `onItemSelected`. Registering only the selected listener is therefore an
 * option that is accepted and does nothing: P16's sidebar rows lit up under the
 * press, its `selection` binding never changed, and its detail pane read
 * "Select an area" no matter which row was pressed.
 *
 * 兩個 listener 都實作，因為在觸控螢幕上，兩者之中只有一個會被觸發。
 *
 * `OnItemSelectedListener` 講的是**取得焦點**的項目——也就是 D-pad 或軌跡球移動到的那一個。觸控
 * 螢幕上的 ListView 處於 touch mode，而該模式下根本沒有「取得焦點的項目」，因此點擊一列觸發的是
 * `onItemClick`，永遠不會是 `onItemSelected`。所以只註冊 selected listener 是一個「被接受卻什麼
 * 都不做」的選項：P16 的側欄各列在按壓下會亮起、它的 `selection` 繫結從未改變，而無論按下哪一列，
 * detail 窗格都讀作「Select an area」。
 */
class ListItemSelectedListener :
    AdapterView.OnItemSelectedListener, AdapterView.OnItemClickListener {
    var action: SwiftAction? = null

    var selectedPosition = AdapterView.INVALID_POSITION
        private set

    private var oldSelectedPosition = AdapterView.INVALID_POSITION

    override fun onNothingSelected(parent: AdapterView<*>) {
        onItemSelected(parent, null, AdapterView.INVALID_POSITION, AdapterView.INVALID_ROW_ID)
    }

    override fun onItemSelected(parent: AdapterView<*>, view: View?, position: Int, id: Long) {
        selectedPosition = position
        if (position != oldSelectedPosition) action?.call()
        oldSelectedPosition = position
    }

    override fun onItemClick(parent: AdapterView<*>, view: View?, position: Int, id: Long) {
        onItemSelected(parent, view, position, id)
    }
}
