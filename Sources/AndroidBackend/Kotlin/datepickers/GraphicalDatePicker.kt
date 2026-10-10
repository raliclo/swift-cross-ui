package dev.swiftcrossui.androidbackend.datepickers

import android.content.Context
import android.icu.util.Calendar
import android.view.Gravity
import androidx.fragment.app.FragmentActivity
import java.time.DayOfWeek
import java.time.LocalDateTime
import java.util.Locale

class GraphicalDatePicker(context: Context) : AbstractDatePicker(context) {
    // The month as UIDatePicker's inline calendar draws it; see InlineCalendarView.
    // The framework's DatePicker measured with no height at all when none was
    // offered, so P41's .graphical cell was empty, and it is Material's calendar
    // where it does show (2026-10-10).
    // 月份依 UIDatePicker 的 inline 月曆繪製；見 InlineCalendarView。框架的 DatePicker 在不給高度時量出來完全沒有高度，
    // 所以 P41 的 .graphical 格子是空的；就算顯示出來，也是 Material 的月曆(2026-10-10)。
    protected override val dateView = InlineCalendarView(context)

    // The time is the field the compact style uses, not a TimePicker: UIKit's
    // inline picker shows the time as that same field, and with only a time
    // asked for it is the whole picker. The clock face measured a fraction of
    // its size and P41's .hourAndMinute cell was a dark rectangle (2026-10-10).
    // 時間用的是 compact 樣式的那個欄位，不是 TimePicker:UIKit 的 inline picker 也是用同一個欄位顯示時間，
    // 只要求時間時它就是整個 picker。鐘面量出來只有實際的一小部分,P41 的 .hourAndMinute 格子是一塊深色方塊(2026-10-10)。
    protected override val timeView = TimeButton(context as FragmentActivity)

    protected override var currentValue = LocalDateTime.now()

    private var locale: Locale? = null

    init {
        dateView.onChange = { date ->
            currentValue = LocalDateTime.of(date, currentValue.toLocalTime())

            adjustTimeForBounds()

            action?.call()
        }

        timeView.action = {
            val time = timeView.value
            currentValue = currentValue.withHour(time.hour).withMinute(time.minute)

            adjustTimeForBounds()

            action?.call()
        }

        // The calendar with the time under it at the trailing edge, as
        // UIDatePicker's inline style lays them out.
        // 月曆在上，時間在它下方靠後緣，與 UIDatePicker 的 inline 樣式排法相同。
        orientation = VERTICAL
        addView(dateView)
        addView(
            timeView,
            LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
                gravity = Gravity.END
                // 8.5 around the field, as UIKit's inline time has: P41's .hourAndMinute
                // cell is 51 high on iOS with the field 19 from its label, not 34 and 10.
                // 欄位四周留 8.5,與 UIKit 的 inline 時間相同:P41 的 .hourAndMinute 格子在 iOS 上高 51、欄位距標籤 19,
                // 而不是 34 與 10。
                val around = Math.round(8.5f * resources.displayMetrics.density)
                setMargins(around, around, around, around)
            },
        )
        setLocale(Locale.getDefault())
    }

    protected override fun applyRange(min: LocalDateTime, max: LocalDateTime) {
        dateView.minDate = min.toLocalDate()
        dateView.maxDate = max.toLocalDate()
        dateView.invalidate()

        adjustTimeForBounds()
    }

    protected override fun applyDate(value: LocalDateTime) {
        if (dateView.selected != value.toLocalDate()) {
            dateView.selected = value.toLocalDate()
        }
        timeView.value = value.toLocalTime()
    }

    private fun adjustTimeForBounds() {
        timeView.value = value.toLocalTime()
    }

    override fun setForegroundColor(color: Int) {
        dateView.foreground = color
        timeView.setTextColor(color)
    }

    override fun setLocale(locale: Locale) {
        if (locale == this.locale) return
        this.locale = locale
        dateView.locale = locale
        // ICU counts Sunday as 1; DayOfWeek counts Monday as 1.
        // ICU 的星期日是 1;DayOfWeek 的星期一是 1。
        dateView.firstDayOfWeek =
            DayOfWeek.of((Calendar.getInstance(locale).firstDayOfWeek + 5) % 7 + 1)
        timeView.setLocale(locale)
    }
}
