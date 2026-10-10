package dev.swiftcrossui.androidbackend.datepickers

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.widget.LinearLayout
import java.text.DateFormatSymbols
import java.time.LocalDate
import java.time.YearMonth
import java.util.Locale

/**
 * UIDatePicker's date wheels: month, day and year columns over one selection bar, to
 * measurements from UIKitBackend (P41, 2026-10-10), in points = dp. 320 x 216; the bar
 * 301 x 34 across the middle, (118, 118, 128) at 8%, fully rounded; month names left
 * aligned at x 27, days centred on x 180, years on x 256.5.
 *
 * UIDatePicker 的日期滾輪：月、日、年三欄共用一條選取列，尺寸取自 UIKitBackend(P41,2026-10-10),單位 pt = dp。
 * 320 x 216;選取列 301 x 34 橫過中央、(118, 118, 128) 8%、兩端全圓；月份名稱靠左於 x 27,日置中於 x 180,
 * 年置中於 x 256.5。
 */
class DateWheels(context: Context) : LinearLayout(context) {
    var onChange: (() -> Unit)? = null

    private val month = WheelColumn(context)
    private val day = WheelColumn(context)
    private val year = WheelColumn(context)
    private val density = resources.displayMetrics.density
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private var firstYear = 1
    private var lastYear = 9999

    var locale: Locale = Locale.getDefault()
        set(value) {
            field = value
            month.items = DateFormatSymbols(value).months.take(12)
            arrange()
        }

    var foreground: Int = Color.BLACK
        set(value) {
            field = value
            month.foreground = value
            day.foreground = value
            year.foreground = value
            invalidate()
        }

    var value: LocalDate
        get() {
            val shownYear = firstYear + year.index
            val shownMonth = YearMonth.of(shownYear, month.index + 1)
            return shownMonth.atDay((day.index + 1).coerceAtMost(shownMonth.lengthOfMonth()))
        }
        set(newValue) {
            year.index = (newValue.year - firstYear).coerceIn(0, lastYear - firstYear)
            month.index = newValue.monthValue - 1
            day.items = (1..newValue.lengthOfMonth()).map { it.toString() }
            day.index = newValue.dayOfMonth - 1
        }

    // Day before month where the locale writes it so, as UIKit orders its wheels:
    // en_GB is "24 | August | 2025" with the day centred on x 42.2 and the month from
    // x 90.3; en_US is "August | 24 | 2025". The year stays centred on 256.5.
    // (A year-first locale is laid out month, day, year: not measured on UIKit.)
    // 地區把日寫在月之前時，日那一欄也排在前面，與 UIKit 排滾輪的順序相同:en_GB 是「24 | August | 2025」,日置中於 x 42.2、
    // 月自 x 90.3 起;en_US 是「August | 24 | 2025」。年維持置中於 256.5。(年在最前的地區仍排成月、日、年:未在 UIKit 上量過。)
    private fun arrange() {
        val pattern =
            android.icu.text.DateTimePatternGenerator.getInstance(locale).getBestPattern("yMMMMd")
        val dayFirst = pattern.indexOf('d') in 0 until pattern.indexOf('M').coerceAtLeast(0)
        val height = Math.round(216 * density)
        removeAllViews()
        if (dayFirst) {
            day.anchor = 33.2f
            month.anchor = 21.3f
            addView(day, LayoutParams(Math.round(60 * density), height))
            addView(month, LayoutParams(Math.round(136 * density), height))
        } else {
            month.anchor = 18f
            day.anchor = 25f
            addView(month, LayoutParams(Math.round(146 * density), height))
            addView(day, LayoutParams(Math.round(50 * density), height))
        }
        year.anchor = 51.5f
        addView(year, LayoutParams(Math.round(103 * density), height))
    }

    init {
        orientation = HORIZONTAL
        setWillNotDraw(false)
        setPadding(Math.round(9 * density), 0, 0, 0)
        month.align = Paint.Align.LEFT
        month.wraps = true
        day.wraps = true
        month.items = DateFormatSymbols(locale).months.take(12)
        year.items = (firstYear..lastYear).map { it.toString() }
        arrange()
        val changed: (Int) -> Unit = {
            // The day column follows the month's length. 日那一欄跟著該月的天數。
            val current = value
            day.items = (1..current.lengthOfMonth()).map { it.toString() }
            day.index = current.dayOfMonth - 1
            onChange?.invoke()
        }
        month.onChange = changed
        day.onChange = changed
        year.onChange = changed
        value = LocalDate.now()
    }

    fun setRange(min: LocalDate, max: LocalDate) {
        val current = value
        firstYear = min.year.coerceIn(1, 9999)
        lastYear = max.year.coerceIn(firstYear, 9999)
        year.items = (firstYear..lastYear).map { it.toString() }
        value = current
    }

    override fun setEnabled(enabled: Boolean) {
        super.setEnabled(enabled)
        month.isEnabled = enabled
        day.isEnabled = enabled
        year.isEnabled = enabled
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
