package dev.swiftcrossui.androidbackend.datepickers

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.widget.FrameLayout
import java.text.DateFormatSymbols
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale

/**
 * UIDatePicker's time wheels, and its date-and-time wheels when [showsDay] is set, to
 * measurements from UIKitBackend (P41's ".wheel time" and ".wheel date+time", 2026-10-10),
 * in points = dp. 320 x 216 over the same 301 x 34 bar as [DateWheels].
 *
 *   time:           hours right-aligned at x 96.5, minutes centred on 155, AM/PM on 216.7
 *   date and time:  "Sun Aug 24" right-aligned at 138.5, hours at 178.5, minutes centred
 *                   on 227, AM/PM on 281.7
 *
 * With a 24-hour locale there is no AM/PM column and the time alone is 09 centred on x 117.3 and 46 on x 192. The day column holds three years either
 * side of the value, inside the range, and is rebuilt around a value outside it.
 *
 * It replaces the Holo spinner TimePicker, which next to these wheels was three flat rows
 * between blue rules; and with both a date and a time the Holo pair stood side by side
 * where UIKit shows one wheel with the day as its first column.
 *
 * UIDatePicker 的時間滾輪；設了 [showsDay] 時是它的「日期＋時間」滾輪。尺寸取自 UIKitBackend(P41 的
 * 「.wheel time」與「.wheel date+time」,2026-10-10),單位 pt = dp。320 x 216,選取列與 [DateWheels] 相同(301 x 34)。
 * 時間：時靠右於 x 96.5、分置中於 155、AM/PM 置中於 216.7。日期＋時間:「Sun Aug 24」靠右於 138.5、時靠右於 178.5、
 * 分置中於 227、AM/PM 置中於 281.7。24 小時制的地區沒有 AM/PM 欄。日那一欄放值前後各三年(在範圍內),值超出時重建。
 * 它取代 Holo 的滾輪 TimePicker:後者是兩條藍線之間三列平的；同時要日期與時間時,Holo 是兩個並排,UIKit 則是一個滾輪、
 * 以「日」為第一欄。
 */
class TimeWheels(context: Context) : FrameLayout(context) {
    var onChange: (() -> Unit)? = null

    private val day = WheelColumn(context)
    private val hour = WheelColumn(context)
    private val minute = WheelColumn(context)
    private val period = WheelColumn(context)
    private val density = resources.displayMetrics.density
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private var firstDay = LocalDate.now()
    private var minDate = LocalDate.MIN
    private var maxDate = LocalDate.MAX
    private var is24Hour = false
    private var current = LocalDateTime.now()

    var showsDay = false
        set(value) {
            if (field == value) return
            field = value
            arrange()
        }

    var locale: Locale = Locale.getDefault()
        set(value) {
            field = value
            is24Hour = is24HourLocale(value)
            fill()
            arrange()
            show(current)
        }

    var foreground: Int = Color.BLACK
        set(value) {
            field = value
            for (column in listOf(day, hour, minute, period)) column.foreground = value
            invalidate()
        }

    var value: LocalDateTime
        get() = current
        set(newValue) {
            current = newValue
            show(newValue)
        }

    init {
        setWillNotDraw(false)
        hour.align = Paint.Align.RIGHT
        day.align = Paint.Align.RIGHT
        hour.wraps = true
        minute.wraps = true
        for (column in listOf(day, hour, minute, period)) {
            addView(column)
            column.onChange = { read() }
        }
        is24Hour = is24HourLocale(locale)
        fill()
        arrange()
        show(current)
    }

    private fun fill() {
        hour.items =
            if (is24Hour) (0..23).map { "%02d".format(it) }
            else listOf(12, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11).map { it.toString() }
        minute.items = (0..59).map { "%02d".format(it) }
        period.items = DateFormatSymbols(locale).amPmStrings.take(2)
    }

    private fun place(column: WheelColumn, left: Float, right: Float, anchor: Float) {
        column.visibility = VISIBLE
        column.anchor = anchor - left
        column.layoutParams =
            LayoutParams(Math.round((right - left) * density), Math.round(216 * density)).apply {
                leftMargin = Math.round(left * density)
            }
    }

    private fun arrange() {
        day.visibility = GONE
        period.visibility = GONE
        if (showsDay) {
            hour.align = Paint.Align.RIGHT
            place(day, 0f, 146f, 138.5f)
            place(hour, 146f, 190f, 178.5f)
            place(minute, 190f, 256f, 227f)
            if (!is24Hour) place(period, 256f, 320f, 281.7f)
        } else if (is24Hour) {
            // Two centred columns of two digits, as UIKit lays a 24-hour time out
            // (en_GB, 2026-10-10): 09 on x 117.3, 46 on x 192.
            // 兩欄置中的兩位數，與 UIKit 排 24 小時制時間的方式相同(en_GB,2026-10-10):09 在 x 117.3、46 在 x 192。
            hour.align = Paint.Align.CENTER
            place(hour, 80f, 155f, 117.3f)
            place(minute, 155f, 230f, 192f)
        } else {
            hour.align = Paint.Align.RIGHT
            place(hour, 40f, 106f, 96.5f)
            place(minute, 106f, 186f, 155f)
            if (!is24Hour) place(period, 186f, 260f, 216.7f)
        }
        requestLayout()
    }

    private fun fillDays(around: LocalDate) {
        val from = around.minusYears(3).let { if (it.isBefore(minDate)) minDate else it }
        val to = around.plusYears(3).let { if (it.isAfter(maxDate)) maxDate else it }
        firstDay = from
        val format = DateTimeFormatter.ofPattern("EEE MMM d", locale)
        val today = LocalDate.now()
        val count = ChronoUnit.DAYS.between(from, to).toInt().coerceAtLeast(0)
        day.items =
            (0..count).map {
                val date = from.plusDays(it.toLong())
                if (date == today) "Today" else date.format(format)
            }
    }

    private fun show(shown: LocalDateTime) {
        val offset = ChronoUnit.DAYS.between(firstDay, shown.toLocalDate())
        if (day.items.isEmpty() || offset < 0 || offset >= day.items.size) {
            fillDays(shown.toLocalDate())
        }
        day.index = ChronoUnit.DAYS.between(firstDay, shown.toLocalDate()).toInt()
        hour.index = if (is24Hour) shown.hour else shown.hour % 12
        minute.index = shown.minute
        period.index = if (shown.hour < 12) 0 else 1
    }

    private fun read() {
        val hours = if (is24Hour) hour.index else hour.index + 12 * period.index
        val date = if (showsDay) firstDay.plusDays(day.index.toLong()) else current.toLocalDate()
        current = LocalDateTime.of(date, LocalTime.of(hours, minute.index, current.second))
        onChange?.invoke()
    }

    fun setRange(min: LocalDate, max: LocalDate) {
        minDate = min
        maxDate = max
        fillDays(current.toLocalDate())
        show(current)
    }

    override fun setEnabled(enabled: Boolean) {
        super.setEnabled(enabled)
        for (column in listOf(day, hour, minute, period)) column.isEnabled = enabled
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(
            MeasureSpec.makeMeasureSpec(Math.round(320 * density), MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(Math.round(216 * density), MeasureSpec.EXACTLY),
        )
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val light =
            (Color.red(foreground) * 299 + Color.green(foreground) * 587 +
                Color.blue(foreground) * 114) / 1000 > 127
        paint.color = Color.argb(if (light) 46 else 20, 118, 118, 128)
        val middle = height / 2f
        canvas.drawRoundRect(
            9.3f * density, middle - 17 * density, 310.3f * density, middle + 17 * density,
            17 * density, 17 * density, paint,
        )
    }
}
