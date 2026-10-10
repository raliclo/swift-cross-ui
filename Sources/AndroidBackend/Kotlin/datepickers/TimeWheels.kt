package dev.swiftcrossui.androidbackend.datepickers

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.icu.text.DateTimePatternGenerator
import android.icu.util.ULocale
import android.widget.FrameLayout
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.temporal.ChronoUnit
import java.util.Date
import java.util.Locale

/**
 * UIDatePicker's time wheels, and its date-and-time wheel when [showsDay] is set, to
 * measurements from UIKitBackend in 22 regions (P90, 2026-10-10), in points = dp. 320 x 216
 * over the same 301 x 34 bar as [DateWheels].
 *
 * What the columns hold comes from the region, as UIKit's do:
 *
 * - Hours are 1-12 or 0-23, padded or not, as the region's time pattern has them (9 in
 *   en_US, es_ES and ja_JP; 09 in en_GB and de_DE).
 * - The period column is AM/PM, or the region's day periods where it writes those
 *   (凌晨 清晨 上午 中午 下午 晚上 in zh_TW; रात सुबह दोपहर शाम in hi_IN). It stands before
 *   the hours where the pattern puts it first (zh_TW, ko_KR, hi_IN).
 * - The day column of the date-and-time wheel is the region's weekday, month and day
 *   without commas ("Sun Aug 24", "So. 24. Aug.", "8月24日 週日").
 *
 * Where they sit is measured, not derived. A time alone has three layouts: hours ending at
 * x 97.6, minutes on 155.3, period on 217 (en_US); period on 102.3, hours ending at 171.6,
 * minutes on 229.3 (period first); hours ending at 131, minutes on 192.3 (24-hour). The
 * date-and-time wheel differs region by region and is in [placements]; a region not in it
 * takes the layout of en_US, zh_TW or en_GB by its kind.
 *
 * UIDatePicker 的時間滾輪；設了 [showsDay] 時是它的「日期＋時間」滾輪。尺寸取自 UIKitBackend 在 22 個地區的量測
 * (P90,2026-10-10),單位 pt = dp。320 x 216,選取列與 [DateWheels] 相同(301 x 34)。
 *
 * 欄位的內容來自地區，與 UIKit 相同：小時是 1-12 或 0-23、補零與否依該地區的時間樣式(en_US、es_ES、ja_JP 是 9;en_GB、
 * de_DE 是 09);時段欄是 AM/PM,或該地區寫的日間時段(zh_TW 是 凌晨 清晨 上午 中午 下午 晚上;hi_IN 是 रात सुबह दोपहर शाम),
 * 樣式把它寫在前面時就排在小時之前(zh_TW、ko_KR、hi_IN);「日期＋時間」滾輪的日那一欄是該地區的星期、月、日，去掉逗號。
 *
 * 位置是量出來的，不是推導的。只有時間時有三種排法(en_US、時段在前、24 小時制);「日期＋時間」滾輪每個地區都不同，放在
 * [placements] 裡，不在表中的地區依其種類採用 en_US、zh_TW 或 en_GB 的排法。
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
    private var periodFirst = false
    private var hourDigits = 1
    private var current = LocalDateTime.now()

    /** The period each hour of the day belongs to, as an index into the period column. */
    private var periodOfHour = IntArray(24) { if (it < 12) 0 else 1 }

    /**
     * The date-and-time wheel as measured on UIKit: where the day text ends (or, negative,
     * where it starts), where the hours end, the middle of the minutes, and the middle of
     * the period column (0 without one).
     * UIKit 上量到的「日期＋時間」滾輪：日的文字結束於何處(負數表示開始於何處)、小時結束於何處、分的中心、時段欄的中心(沒有則為 0)。
     */
    private val placements =
        mapOf(
            "en_US" to floatArrayOf(138.3f, 179.6f, 227.3f, 282f),
            "en_GB" to floatArrayOf(163.6f, 205.6f, 257.3f, 0f),
            "de_DE" to floatArrayOf(162.6f, 208.6f, 260.3f, 0f),
            "fr_FR" to floatArrayOf(167.6f, 211.6f, 263.3f, 0f),
            "es_ES" to floatArrayOf(163f, 207.6f, 258.3f, 0f),
            "it_IT" to floatArrayOf(163f, 207.6f, 259.3f, 0f),
            "nl_NL" to floatArrayOf(157f, 196.6f, 248.3f, 0f),
            "sv_SE" to floatArrayOf(162.6f, 208.6f, 260.3f, 0f),
            "fi_FI" to floatArrayOf(143.3f, 191.6f, 242.3f, 0f),
            "pl_PL" to floatArrayOf(161.6f, 211f, 263.1f, 0f),
            "hu_HU" to floatArrayOf(-55.3f, 212.6f, 263.3f, 0f),
            "ru_RU" to floatArrayOf(143.3f, 208.6f, 260.3f, 0f),
            "tr_TR" to floatArrayOf(158.3f, 206.6f, 258.3f, 0f),
            "pt_BR" to floatArrayOf(185f, 224.6f, 276.3f, 0f),
            "zh_TW" to floatArrayOf(152.3f, 255.6f, 300.6f, 192.3f),
            "zh_CN" to floatArrayOf(177.3f, 216.6f, 268.3f, 0f),
            "ja_JP" to floatArrayOf(167f, 206.6f, 257.3f, 0f),
            "ko_KR" to floatArrayOf(137f, 237f, 284f, 174.5f),
            "th_TH" to floatArrayOf(173f, 220f, 271f, 0f),
            "hi_IN" to floatArrayOf(126f, 241.6f, 289.3f, 179.6f),
            "he_IL" to floatArrayOf(165f, 218.6f, 269.3f, 0f),
            "ar_SA" to floatArrayOf(177.6f, 212.6f, 251.3f, 299.3f),
        )

    var showsDay = false
        set(value) {
            if (field == value) return
            field = value
            arrange()
        }

    var locale: Locale = Locale.getDefault()
        set(value) {
            field = value
            fill()
            arrange()
            fillDays(current.toLocalDate())
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
        hour.wraps = true
        minute.wraps = true
        for (column in listOf(day, hour, minute, period)) {
            addView(column)
        }
        day.onChange = { read(false) }
        hour.onChange = { read(false) }
        minute.onChange = { read(false) }
        period.onChange = { read(true) }
        fill()
        arrange()
        show(current)
    }

    private fun number(value: Int, digits: Int) = String.format(locale, "%0${digits}d", value)

    private fun fill() {
        val generator = DateTimePatternGenerator.getInstance(locale)
        // `C` asks for the region's preferred hour with the day periods it writes
        // (B); an ICU without it throws, and `j` is the same question without them.
        // It also throws ArrayIndexOutOfBounds for regions it has no hour list for
        // (sv_SE, fi_FI and ru_RU on API 36), which took the app down (2026-10-10).
        // `C` 問的是該地區偏好的小時寫法，連同它所寫的日間時段(B);沒有它的 ICU 會丟例外,`j` 是不含時段的同一個問題。
        val pattern =
            try {
                generator.getBestPattern("Cm")
            } catch (_: RuntimeException) {
                generator.getBestPattern("jm")
            }
        val bare = pattern.replace(Regex("'[^']*'"), "")
        is24Hour = bare.any { it == 'H' || it == 'k' }
        hourDigits = if (bare.contains("HH") || bare.contains("hh") || bare.contains("kk")) 2 else 1
        val periodLetter = bare.firstOrNull { it == 'a' || it == 'b' || it == 'B' }
        periodFirst =
            periodLetter != null && bare.indexOf(periodLetter) < bare.indexOfFirst { it == 'h' || it == 'K' }

        hour.items =
            if (is24Hour) (0..23).map { number(it, hourDigits) }
            else listOf(12, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11).map { number(it, hourDigits) }
        minute.items = (0..59).map { number(it, 2) }

        // The period of every hour, and the column as those in the order the day meets
        // them. With `a` that is AM and PM; with `B` it is the region's day periods.
        // 每個小時所屬的時段，以及依一天中出現順序排列的欄位內容。用 `a` 時是 AM 與 PM;用 `B` 時是該地區的日間時段。
        val names =
            android.icu.text.SimpleDateFormat(
                if (periodLetter == 'B') "B" else "a", ULocale.forLocale(locale),
            )
        names.timeZone = android.icu.util.TimeZone.getTimeZone("UTC")
        val perHour = (0..23).map { names.format(Date(it * 3_600_000L + 1_800_000L)) }
        val ordered = perHour.distinct()
        period.items = ordered
        periodOfHour = IntArray(24) { ordered.indexOf(perHour[it]) }
    }

    private fun place(column: WheelColumn, left: Float, right: Float, anchor: Float, align: Paint.Align) {
        column.visibility = VISIBLE
        column.align = align
        column.anchor = anchor - left
        column.layoutParams =
            LayoutParams(Math.round((right - left) * density), Math.round(216 * density)).apply {
                leftMargin = Math.round(left * density)
            }
    }

    private fun arrange() {
        day.visibility = GONE
        period.visibility = GONE
        if (!showsDay) {
            when {
                is24Hour -> {
                    place(hour, 80f, 155f, 131f, Paint.Align.RIGHT)
                    place(minute, 155f, 240f, 192.3f, Paint.Align.CENTER)
                }
                periodFirst -> {
                    place(period, 50f, 140f, 102.3f, Paint.Align.CENTER)
                    place(hour, 140f, 195f, 171.6f, Paint.Align.RIGHT)
                    place(minute, 195f, 270f, 229.3f, Paint.Align.CENTER)
                }
                else -> {
                    // Arabic hours end 8 further right on UIKit (٩ ends at 104).
                    // 阿拉伯文的小時在 UIKit 上結束於更右邊 8 處(٩ 結束於 104)。
                    val hourEnd = if (locale.language == "ar") 106f else 97.6f
                    place(hour, 40f, 120f, hourEnd, Paint.Align.RIGHT)
                    place(minute, 120f, 186f, 155.3f, Paint.Align.CENTER)
                    place(period, 186f, 260f, 217f, Paint.Align.CENTER)
                }
            }
            requestLayout()
            return
        }
        val measured =
            placements["${locale.language}_${locale.country}"]
                ?: when {
                    is24Hour -> placements["en_GB"]!!
                    periodFirst -> placements["zh_TW"]!!
                    else -> placements["en_US"]!!
                }
        val hourEnd = measured[1]
        val minuteMiddle = measured[2]
        val periodMiddle = if (is24Hour) 0f else measured[3]
        val hourStart = hourEnd - 34f
        val minuteStart = hourEnd + (minuteMiddle - 13f - hourEnd) / 2
        if (periodMiddle > 0f && periodMiddle < hourEnd) {
            // day | period | hours | minutes
            val periodStart = periodMiddle - 28f
            if (measured[0] < 0f) {
                place(day, 0f, periodStart, -measured[0], Paint.Align.LEFT)
            } else {
                place(day, 0f, periodStart, measured[0], Paint.Align.RIGHT)
            }
            place(period, periodStart, hourStart, periodMiddle, Paint.Align.CENTER)
            place(hour, hourStart, minuteStart, hourEnd, Paint.Align.RIGHT)
            place(minute, minuteStart, 320f, minuteMiddle, Paint.Align.CENTER)
        } else {
            if (measured[0] < 0f) {
                place(day, 0f, hourStart, -measured[0], Paint.Align.LEFT)
            } else {
                place(day, 0f, hourStart, measured[0], Paint.Align.RIGHT)
            }
            place(hour, hourStart, minuteStart, hourEnd, Paint.Align.RIGHT)
            if (periodMiddle > 0f) {
                val periodStart = minuteMiddle + (periodMiddle - minuteMiddle) / 2
                place(minute, minuteStart, periodStart, minuteMiddle, Paint.Align.CENTER)
                place(period, periodStart, 320f, periodMiddle, Paint.Align.CENTER)
            } else {
                place(minute, minuteStart, 320f, minuteMiddle, Paint.Align.CENTER)
            }
        }
        requestLayout()
    }

    private fun fillDays(around: LocalDate) {
        val from = around.minusYears(3).let { if (it.isBefore(minDate)) minDate else it }
        val to = around.plusYears(3).let { if (it.isAfter(maxDate)) maxDate else it }
        firstDay = from
        // Weekday, month and day in the region's order, without the comma UIKit also
        // leaves out: "Sun Aug 24" in en_US, "Sun 24 Aug" in en_GB.
        // 星期、月、日依地區的順序，並去掉 UIKit 同樣省略的逗號:en_US 是「Sun Aug 24」,en_GB 是「Sun 24 Aug」。
        val pattern =
            DateTimePatternGenerator.getInstance(locale)
                .getBestPattern("EEEMMMd")
                .replace(",", "")
                .replace("،", "")
                // The weekday stands apart and bare, as UIKit writes it: 8月24日 日 where
                // the pattern is M月d日(EEE), 8月24日 周日 where it is M月d日EEE.
                // 星期獨立而不加括號，與 UIKit 的寫法相同：樣式是 M月d日(EEE) 時寫成 8月24日 日，是 M月d日EEE 時寫成 8月24日 周日。
                .replace("(", " ")
                .replace(")", "")
                .replace(Regex("(?<=[^\\sEc])(?=[Ec])"), " ")
                .replace(Regex(" +"), " ")
                .trim()
                .let {
                    // Hebrew and Arabic have the weekday after the date on UIKit (24 באוג׳ יום א׳,
                    // ٢٤ أغسطس أحد), where the pattern has it first. By language: it is what was measured.
                    // 希伯來文在 UIKit 上把星期放在日期之後(24 באוג׳ יום א׳),樣式卻把它放在前面。依語言決定：這是量到的結果。
                    val weekday = Regex("^[Ec]+ ").find(it)
                    if (locale.language in setOf("he", "iw", "ar") && weekday != null) {
                        it.substring(weekday.value.length) + " " + weekday.value.trim()
                    } else {
                        it
                    }
                }
        // ICU's formatter for ICU's pattern: java.time rejects letters these patterns use
        // (ccc in ru_RU and fi_FI), and the wheel took the process down with it.
        // 用 ICU 的格式器處理 ICU 的樣式:java.time 不接受這些樣式會用到的字母(ru_RU、fi_FI 的 ccc),滾輪曾因此讓整個行程當掉。
        val format = android.icu.text.SimpleDateFormat(pattern, ULocale.forLocale(locale))
        format.timeZone = android.icu.util.TimeZone.getTimeZone("UTC")
        // Capitalised where the region capitalises a list item (Dom. 24 de ago. in pt_BR).
        // 該地區會把清單項目大寫時就大寫(pt_BR 是 Dom. 24 de ago.)。
        format.setContext(android.icu.text.DisplayContext.CAPITALIZATION_FOR_UI_LIST_OR_MENU)
        // Thai weekdays as UIKit abbreviates them (อาทิตย์, พฤหัส), which are not the
        // abbreviations Android's data has (อา., พฤ.).
        // 泰文的星期用 UIKit 的縮寫(อาทิตย์、พฤหัส),那不是 Android 資料裡的縮寫(อา.、พฤ.)。
        if (locale.language == "th") {
            val names = arrayOf("", "อาทิตย์", "จันทร์", "อังคาร", "พุธ", "พฤหัส", "ศุกร์", "เสาร์")
            val symbols = format.dateFormatSymbols
            symbols.setWeekdays(
                names, android.icu.text.DateFormatSymbols.FORMAT,
                android.icu.text.DateFormatSymbols.ABBREVIATED,
            )
            symbols.setWeekdays(
                names, android.icu.text.DateFormatSymbols.STANDALONE,
                android.icu.text.DateFormatSymbols.ABBREVIATED,
            )
            format.dateFormatSymbols = symbols
        }
        // Arabic weekdays without the article, as UIKit writes them (أحد, not الأحد).
        // 阿拉伯文的星期不帶冠詞，與 UIKit 的寫法相同(أحد,不是 الأحد)。
        if (locale.language == "ar") {
            val symbols = format.dateFormatSymbols
            for (context in listOf(
                android.icu.text.DateFormatSymbols.FORMAT, android.icu.text.DateFormatSymbols.STANDALONE,
            )) {
                val names =
                    symbols.getWeekdays(context, android.icu.text.DateFormatSymbols.ABBREVIATED)
                        .map { it.removePrefix("ال") }
                        .toTypedArray()
                symbols.setWeekdays(names, context, android.icu.text.DateFormatSymbols.ABBREVIATED)
            }
            format.dateFormatSymbols = symbols
        }
        val today = LocalDate.now()
        val count = ChronoUnit.DAYS.between(from, to).toInt().coerceAtLeast(0)
        day.items =
            (0..count).map {
                val date = from.plusDays(it.toLong())
                if (date == today) "Today" else format.format(Date(date.toEpochDay() * 86_400_000L + 43_200_000L))
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
        period.index = periodOfHour[shown.hour]
    }

    /**
     * The value the wheels now show. The hour wheel says which hour of twelve; the period
     * says which half of the day. When the period wheel was the one turned and no hour of
     * that name has this number (中午 with 9), the hour whose period is nearest to the one
     * asked for is taken and the period wheel settles on it.
     * 滾輪現在顯示的值。小時滾輪說的是十二個小時中的哪一個，時段說的是一天的哪一半。轉的是時段滾輪、而那個時段裡沒有這個數字的
     * 小時(「中午」配 9)時，取時段最接近所要求者的那個小時，時段滾輪再停到它上面。
     */
    private fun read(periodTurned: Boolean) {
        val hours =
            if (is24Hour) {
                hour.index
            } else {
                val morning = hour.index
                val evening = hour.index + 12
                val wanted = period.index
                when {
                    periodOfHour[morning] == wanted -> morning
                    periodOfHour[evening] == wanted -> evening
                    !periodTurned -> if (current.hour < 12) morning else evening
                    Math.abs(periodOfHour[evening] - wanted) <= Math.abs(periodOfHour[morning] - wanted) -> evening
                    else -> morning
                }
            }
        val date = if (showsDay) firstDay.plusDays(day.index.toLong()) else current.toLocalDate()
        current = LocalDateTime.of(date, LocalTime.of(hours, minute.index, current.second))
        if (period.index != periodOfHour[hours]) {
            period.index = periodOfHour[hours]
        }
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
