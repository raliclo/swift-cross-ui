package dev.swiftcrossui.androidbackend.datepickers

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Typeface
import android.view.MotionEvent
import android.view.View
import java.text.DateFormatSymbols
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.YearMonth
import java.util.Locale

/**
 * One month drawn as UIDatePicker's inline calendar, to the measurements taken from
 * UIKitBackend on an iPhone 17 Pro Max simulator (iOS 27, P41, 2026-10-10), in points = dp:
 *
 *   320 x 324. Title "August 2025" semibold 17 from x 12, centred on y 34, a small tinted
 *   chevron after it; previous / next chevrons centred on x 259 and 304.5. Weekday
 *   initials (SUN...) semibold 13 in secondary label grey, centred on y 76.5. Days regular
 *   20, columns 45.43 apart from x 22.7, rows 38 apart from y 104. The selected day is a
 *   38-wide disc in the label colour with the number semibold in the background colour.
 *   Tint (0, 136, 255).
 *
 * The framework's DatePicker was Material's: a coloured header, 40 dp rows, a purple-grey
 * disc, and no height at all when measured without one.
 *
 * 把一個月畫成 UIDatePicker 的 inline 月曆，尺寸取自 iPhone 17 Pro Max 模擬器上的 UIKitBackend
 * (iOS 27,P41,2026-10-10),單位 pt = dp:320 x 324;標題半粗體 17、自 x 12 起、中心 y 34,後接一個
 * 小的 tint 色箭頭；上／下個月箭頭中心在 x 259 與 304.5;星期縮寫半粗體 13、次要標籤灰、中心 y 76.5;
 * 日期常規 20,欄距 45.43(自 x 22.7)、列距 38(自 y 104);選中的日期是直徑 38、標籤色的圓，數字半粗體、
 * 背景色。框架的 DatePicker 是 Material 的樣子，而且不給高度時量出來完全沒有高度。
 */
class InlineCalendarView(context: Context) : View(context) {
    var onChange: ((LocalDate) -> Unit)? = null

    var selected: LocalDate = LocalDate.now()
        set(value) {
            field = value
            shown = YearMonth.from(value)
            invalidate()
        }

    var minDate: LocalDate = LocalDate.MIN
    var maxDate: LocalDate = LocalDate.MAX

    var firstDayOfWeek: DayOfWeek = DayOfWeek.SUNDAY
        set(value) {
            field = value
            invalidate()
        }

    var locale: Locale = Locale.getDefault()
        set(value) {
            field = value
            invalidate()
        }

    /** The label colour; the disc's number takes its opposite. 標籤色；圓內數字取其相反色。 */
    var foreground: Int = Color.BLACK
        set(value) {
            field = value
            invalidate()
        }

    private var shown: YearMonth = YearMonth.from(selected)
    private val density = resources.displayMetrics.density
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val semibold = Typeface.create(Typeface.DEFAULT, 600, false)
    private val tint = Color.rgb(0, 136, 255)

    private fun dp(value: Float) = value * density

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        setMeasuredDimension(Math.round(dp(320f)), Math.round(dp(324f)))
    }

    private fun isLight(color: Int) =
        (Color.red(color) * 299 + Color.green(color) * 587 + Color.blue(color) * 114) / 1000 > 127

    private fun leadingBlanks(): Int {
        val first = shown.atDay(1).dayOfWeek.value
        return (first - firstDayOfWeek.value + 7) % 7
    }

    private fun chevron(canvas: Canvas, centreX: Float, centreY: Float, height: Float, right: Boolean) {
        val half = height / 2
        val reach = height * 0.29f * (if (right) 1 else -1)
        val path = Path()
        path.moveTo(centreX - reach, centreY - half)
        path.lineTo(centreX + reach, centreY)
        path.lineTo(centreX - reach, centreY + half)
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = height * 0.17f
        paint.strokeCap = Paint.Cap.ROUND
        paint.strokeJoin = Paint.Join.ROUND
        paint.color = tint
        canvas.drawPath(path, paint)
        paint.style = Paint.Style.FILL
    }

    private fun centredBaseline(centreY: Float) = centreY - (paint.descent() + paint.ascent()) / 2

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val months = DateFormatSymbols(locale).months
        val title = "${months[shown.monthValue - 1]} ${shown.year}"
        paint.typeface = semibold
        paint.textSize = dp(17f)
        paint.textAlign = Paint.Align.LEFT
        paint.color = foreground
        paint.alpha = if (isEnabled) 255 else 77
        canvas.drawText(title, dp(12f), centredBaseline(dp(34f)), paint)
        val titleEnd = dp(12f) + paint.measureText(title)
        chevron(canvas, titleEnd + dp(11f), dp(34f), dp(12f), true)
        chevron(canvas, dp(259f), dp(34f), dp(17f), false)
        chevron(canvas, dp(304.5f), dp(34f), dp(17f), true)

        val weekdays = DateFormatSymbols(locale).shortWeekdays
        paint.typeface = semibold
        paint.textSize = dp(13f)
        paint.textAlign = Paint.Align.CENTER
        // secondaryLabel: (60, 60, 67) at 60%, or (235, 235, 245) at 60% on dark.
        paint.color =
            if (isLight(foreground)) Color.argb(153, 235, 235, 245) else Color.argb(153, 60, 60, 67)
        for (column in 0 until 7) {
            val day = (firstDayOfWeek.value - 1 + column) % 7 + 1
            // DayOfWeek 1 = Monday; DateFormatSymbols 1 = Sunday.
            val name = weekdays[day % 7 + 1].uppercase(locale)
            canvas.drawText(name, dp(22.7f + 45.43f * column), centredBaseline(dp(76.5f)), paint)
        }

        val blanks = leadingBlanks()
        for (day in 1..shown.lengthOfMonth()) {
            val cell = blanks + day - 1
            val x = dp(22.7f + 45.43f * (cell % 7))
            val y = dp(104f + 38f * (cell / 7))
            val date = shown.atDay(day)
            val isSelected = date == selected
            val inRange = !date.isBefore(minDate) && !date.isAfter(maxDate)
            if (isSelected) {
                paint.color = foreground
                paint.alpha = if (isEnabled) 255 else 77
                canvas.drawCircle(x, y, dp(19f), paint)
                paint.color = if (isLight(foreground)) Color.BLACK else Color.WHITE
                paint.typeface = semibold
            } else {
                paint.color = foreground
                paint.alpha = if (isEnabled && inRange) 255 else 77
                paint.typeface = Typeface.DEFAULT
            }
            paint.textSize = dp(20f)
            canvas.drawText(day.toString(), x, centredBaseline(y), paint)
        }
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (!isEnabled) return false
        if (event.actionMasked == MotionEvent.ACTION_DOWN) return true
        if (event.actionMasked != MotionEvent.ACTION_UP) return true
        val x = event.x / density
        val y = event.y / density
        if (y < 56f) {
            if (x >= 282f) {
                shown = shown.plusMonths(1)
                invalidate()
            } else if (x >= 236f) {
                shown = shown.minusMonths(1)
                invalidate()
            }
            return true
        }
        if (y < 85f) return true
        val column = (x / 45.43f).toInt().coerceIn(0, 6)
        val row = ((y - 85f) / 38f).toInt()
        val day = row * 7 + column - leadingBlanks() + 1
        if (day < 1 || day > shown.lengthOfMonth()) return true
        val date = shown.atDay(day)
        if (date.isBefore(minDate) || date.isAfter(maxDate) || date == selected) return true
        selected = date
        onChange?.invoke(date)
        return true
    }
}
