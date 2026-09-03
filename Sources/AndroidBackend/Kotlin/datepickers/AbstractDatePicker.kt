package dev.swiftcrossui.androidbackend.datepickers

import android.content.Context
import android.view.View
import android.widget.LinearLayout
import dev.swiftcrossui.androidbackend.SwiftAction
import java.time.LocalDateTime

abstract class AbstractDatePicker(context: Context) : LinearLayout(context) {
    companion object {
        const val COMPONENT_DATE = 0x1C
        const val COMPONENT_HOUR_MINUTE = 0x60
        const val COMPONENT_SECOND = 0x80
        const val COMPONENT_TIME = COMPONENT_HOUR_MINUTE or COMPONENT_SECOND
        const val COMPONENT_MASK = COMPONENT_DATE or COMPONENT_HOUR_MINUTE or COMPONENT_SECOND
    }

    var action: SwiftAction? = null

    protected abstract val dateView: View
    protected abstract val timeView: View

    private var minDate = LocalDateTime.MIN
    private var maxDate = LocalDateTime.MAX

    protected abstract var currentValue: LocalDateTime

    init {
        orientation = LinearLayout.HORIZONTAL
    }

    protected abstract fun applyRange(min: LocalDateTime, max: LocalDateTime)

    /**
     * Shows [value] in the subclass's two views.
     *
     * The setter below used to assign `currentValue` and stop there, so a date
     * picker never displayed the date it was bound to -- it displayed whichever
     * date its widgets were constructed with, which is today. `.compact` hid
     * this because a `DateButton` reads its own label from the value it is
     * given; `.graphical` and `.wheel` did not, and `.graphical` was
     * unreachable on a phone until 2026-09-03, so nothing had looked. P41 shows
     * it plainly: its wheel read Sep 03 2026 with "2025-08-23" printed
     * underneath.
     *
     * 把 [value] 顯示在子類別的兩個 view 上。
     *
     * 下方的 setter 過去只指派 `currentValue` 就結束了，因此日期選擇器從不顯示它所繫結的日期
     * ——它顯示的是「其 widget 建構時所帶的日期」，也就是今天。`.compact` 掩蓋了這一點，因為
     * `DateButton` 會依它所收到的值自行更新標籤；`.graphical` 與 `.wheel` 則不會，而 `.graphical`
     * 在 2026-09-03 之前在手機上根本無法抵達，因此從來沒有人看過。P41 把它清楚地顯示了出來：
     * 它的滾輪讀作 Sep 03 2026，而底下印著「2025-08-23」。
     */
    protected abstract fun applyDate(value: LocalDateTime)

    /**
     * True while [applyDate] is writing to the views.
     *
     * `DatePicker.updateDate` and `TimePicker.hour` both notify their change
     * listeners, and those listeners call back into Swift. Without this, showing
     * a value would report it as a user edit, and SwiftCrossUI would write it
     * back -- a loop that starts on the first frame.
     *
     * 當 [applyDate] 正在寫入這些 view 時為 true。
     *
     * `DatePicker.updateDate` 與 `TimePicker.hour` 都會通知它們的變更 listener，而那些 listener
     * 會回呼進 Swift。若沒有這個旗標，「顯示一個值」就會被回報為一次使用者編輯，而 SwiftCrossUI
     * 會把它寫回來——那是一個從第一個影格就開始的迴圈。
     */
    protected var isApplyingDate = false

    var value: LocalDateTime
        get() = currentValue.coerceIn(minDate, maxDate)
        set(newValue) {
            currentValue = newValue.coerceIn(minDate, maxDate)
            applyDate(currentValue)
        }

    fun setRange(min: LocalDateTime, max: LocalDateTime) {
        minDate = min
        maxDate = max
        applyRange(min, max)
        // The new bounds may have moved the value; `value`'s getter coerces and
        // the views do not know that.
        // 新的邊界可能已經移動了該值；`value` 的 getter 會做夾限，而那些 view 並不知道這件事。
        applyDate(value)
    }

    fun setComponents(components: Int) {
        require(components and COMPONENT_MASK == components)
        require(components != 0)

        dateView.visibility = if (components and COMPONENT_DATE != 0) View.VISIBLE else View.GONE
        timeView.visibility = if (components and COMPONENT_TIME != 0) View.VISIBLE else View.GONE
    }

    override fun setEnabled(enabled: Boolean) {
        dateView.isEnabled = enabled
        timeView.isEnabled = enabled
        super.setEnabled(enabled)
    }
}
