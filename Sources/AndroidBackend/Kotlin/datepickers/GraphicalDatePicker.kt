package dev.swiftcrossui.androidbackend.datepickers

import android.content.Context
import android.icu.util.Calendar
import android.view.Gravity
import android.widget.DatePicker
import androidx.fragment.app.FragmentActivity
import java.time.LocalDateTime
import java.time.temporal.ChronoUnit
import java.util.Locale

class GraphicalDatePicker(context: Context) : AbstractDatePicker(context) {
    protected override val dateView = DatePicker(context)
    // The time is the field the compact style uses, not a TimePicker: UIKit's
    // inline picker shows the time as that same field, and with only a time
    // asked for it is the whole picker. The clock face measured a fraction of
    // its size and P41's .hourAndMinute cell was a dark rectangle (2026-10-10).
    // 時間用的是 compact 樣式的那個欄位，不是 TimePicker:UIKit 的 inline picker 也是用同一個欄位顯示時間，
    // 只要求時間時它就是整個 picker。鐘面量出來只有實際的一小部分,P41 的 .hourAndMinute 格子是一塊深色方塊(2026-10-10)。
    protected override val timeView = TimeButton(context as FragmentActivity)

    protected override var currentValue = LocalDateTime.now()

    private var locale = Locale.getDefault()

    init {
        dateView.setOnDateChangedListener { _, year, month, day ->
            if (isApplyingDate) {
                return@setOnDateChangedListener
            }
            currentValue = currentValue.withYear(year).withMonth(month + 1).withDayOfMonth(day)

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
        // The month alone, 320 wide as UIDatePicker's inline calendar and 340 high: six weeks of the
        // framework's 40 dp rows under its heading (at 304 the sixth week scrolled out of sight).
        // Left to measure itself with no size offered, the calendar came out with
        // no area and P41's .graphical cell was empty; the coloured header above
        // the month has no counterpart on iOS (2026-10-10).
        // 只有月份，寬 320(UIDatePicker inline 月曆的寬度)、高 340(標題下六週、每週 40 dp)。不給尺寸讓它自己量，月曆量出來沒有面積,P41 的
        // .graphical 格子是空的；月份上方的彩色標頭在 iOS 上沒有對應物(2026-10-10)。
        val density = resources.displayMetrics.density
        val header = android.content.res.Resources.getSystem()
            .getIdentifier("date_picker_header", "id", "android")
        if (header != 0) {
            dateView.findViewById<android.view.View>(header)?.visibility = GONE
        }
        addView(
            dateView,
            LayoutParams(Math.round(320 * density), Math.round(340 * density)),
        )
        addView(
            timeView,
            LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
                gravity = Gravity.END
            },
        )
    }

    protected override fun applyRange(min: LocalDateTime, max: LocalDateTime) {
        dateView.minDate = Constants.EPOCH.until(min, ChronoUnit.MILLIS)
        dateView.maxDate = Constants.EPOCH.until(max, ChronoUnit.MILLIS)

        adjustTimeForBounds()
    }

    protected override fun applyDate(value: LocalDateTime) {
        isApplyingDate = true
        dateView.updateDate(value.year, value.monthValue - 1, value.dayOfMonth)
        timeView.value = value.toLocalTime()
        isApplyingDate = false
    }

    private fun adjustTimeForBounds() {
        timeView.value = value.toLocalTime()
    }

    override fun setLocale(locale: Locale) {
        if (locale == this.locale) return
        this.locale = locale
        dateView.firstDayOfWeek = Calendar.getInstance(locale).firstDayOfWeek
        timeView.setLocale(locale)
    }
}
