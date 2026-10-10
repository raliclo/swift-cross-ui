package dev.swiftcrossui.androidbackend.datepickers

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.icu.text.DateTimePatternGenerator
import android.widget.FrameLayout
import java.time.LocalDate
import java.time.YearMonth
import java.util.Locale

/**
 * UIDatePicker's date wheels: month, day and year columns over one selection bar, to
 * measurements from UIKitBackend (P41 and P90, 2026-10-10), in points = dp. 320 x 216; the
 * bar 301 x 34 across the middle, (118, 118, 128) at 8%, fully rounded.
 *
 * The columns follow the region, as UIKit's do. Their order is the order the region writes
 * a date in (the `yMMMMd` pattern): August | 24 | 2025 in en_US, 24 | August | 2025 in
 * en_GB, 2025年 | 8月 | 24日 in zh_TW. Their text is the region's pattern for that one field
 * (`d` is "24." in de_DE and "24日" in ja_JP; `y` is "2025." in hu_HU). They are laid out
 * as wide as their widest text plus padding and centred together on x 156.45: a month
 * name left-aligned 17.2 into its column with 7.8 after it, a number centred with 18.8
 * either side. That is what en_US, en_GB and it_IT measure (August from x 28, 24 on
 * x 180.5, 2025 on x 256.8 in en_US; Italian's shorter months move its day 3 right and
 * its year 4 left).
 *
 * UIDatePicker 的日期滾輪：月、日、年三欄共用一條選取列，尺寸取自 UIKitBackend(P41 與 P90,2026-10-10),單位 pt = dp。
 * 320 x 216;選取列 301 x 34 橫過中央、(118, 118, 128) 8%、兩端全圓。欄位跟著地區走，與 UIKit 相同：順序是該地區書寫日期的
 * 順序(`yMMMMd` 樣式):en_US 是 August | 24 | 2025,en_GB 是 24 | August | 2025,zh_TW 是 2025年 | 8月 | 24日;文字是
 * 該地區對那一個欄位的樣式(`d` 在 de_DE 是「24.」、在 ja_JP 是「24日」;`y` 在 hu_HU 是「2025.」)。每一欄的寬度是它最寬的文字加內距,
 * 三欄合起來以 x 156.45 為中心：月份名稱靠左、欄內前留 17.2 後留 7.8;數字置中、兩側各 18.8。這是 en_US、en_GB 與 it_IT 量到的
 * 結果(en_US:August 自 x 28、24 在 x 180.5、2025 在 x 256.8;義大利文的月份較短，日右移 3、年左移 4)。
 */
class DateWheels(context: Context) : FrameLayout(context) {
    var onChange: (() -> Unit)? = null

    private val month = WheelColumn(context)
    private val day = WheelColumn(context)
    private val year = WheelColumn(context)
    private val density = resources.displayMetrics.density
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private var firstYear = 1
    private var lastYear = 9999
    private var dayPattern = "d"
    private var yearPattern = "y"

    var locale: Locale = Locale.getDefault()
        set(value) {
            field = value
            val shown = this.value
            arrange()
            this.value = shown
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
            day.items = days(newValue.lengthOfMonth())
            day.index = newValue.dayOfMonth - 1
        }

    /** A one-field pattern with its number put in: "d日" and 24 give "24日". */
    private fun fill(pattern: String, letter: Char, number: Int): String {
        val text = StringBuilder()
        var written = false
        var quoted = false
        for (character in pattern) {
            when {
                character == '\'' -> quoted = !quoted
                !quoted && character == letter -> {
                    if (!written) text.append(String.format(locale, "%d", number))
                    written = true
                }
                else -> text.append(character)
            }
        }
        return text.toString()
    }

    private fun days(count: Int) = (1..count).map { fill(dayPattern, 'd', it) }

    /** The width UIKit's 23-point text takes: 13 a digit, and the rest as measured here. */
    private fun width(text: String): Float {
        paint.textSize = 23f
        val digits = text.count { it.isDigit() }
        val others = text.filterNot { it.isDigit() }
        // Arabic-Indic digits are narrower in UIKit's font: 10 each (٢٠٢٥ is 38 wide).
        // 阿拉伯-印度數字在 UIKit 的字型裡較窄：每個 10(٢٠٢٥ 寬 38)。
        val digit = if (text.any { it in '٠'..'٩' }) 10f else 13f
        return digit * digits + paint.measureText(others)
    }

    private fun arrange() {
        val generator = DateTimePatternGenerator.getInstance(locale)
        // Each field as the region's full date writes it: the letters of the field and
        // whatever is written straight after them. "d. MMMM y" makes the day "24." in
        // de_DE; "y年M月d日" makes "2025年", "8月" and "24日"; "MMMM d, y" makes "24", a
        // comma being left out as UIKit leaves it out. The month is in the form the
        // date uses (elokuuta in fi_FI, not elokuu).
        // 每個欄位都照該地區完整日期的寫法：欄位的字母，加上緊接在後面寫的東西。「d. MMMM y」讓 de_DE 的日成為「24.」;
        // 「y年M月d日」得到「2025年」「8月」「24日」;「MMMM d, y」得到「24」(逗號略去,UIKit 也略去)。月份用日期中的
        // 詞形(fi_FI 是 elokuuta,不是 elokuu)。
        val full = generator.getBestPattern("yMMMMd")
        val counts = HashMap<Char, Int>()
        val suffixes = HashMap<Char, String>()
        var index = 0
        while (index < full.length) {
            val letter = full[index]
            if (letter != 'y' && letter != 'M' && letter != 'L' && letter != 'd') {
                if (letter == '\'') {
                    index = full.indexOf('\'', index + 1).let { if (it < 0) full.length else it }
                }
                index += 1
                continue
            }
            var end = index
            while (end < full.length && full[end] == letter) end += 1
            val suffix = StringBuilder()
            var after = end
            var quoted = false
            while (after < full.length) {
                val character = full[after]
                if (character == '\'') {
                    quoted = !quoted
                } else if (!quoted && (character.isWhitespace() || character in "yMLdE,")) {
                    break
                } else {
                    suffix.append(character)
                }
                after += 1
            }
            val field = if (letter == 'L') 'M' else letter
            counts[field] = end - index
            suffixes[field] = suffix.toString()
            index = end
        }
        dayPattern = "d'${suffixes['d'] ?: ""}'"
        // An Arabic year carries its era, as UIKit writes it: ٢٠٢٥ م. The region's own
        // pattern for a date has no era in it, so this one is by language.
        // 阿拉伯文的年帶著紀元，與 UIKit 的寫法相同:٢٠٢٥ م。該地區自己的日期樣式裡沒有紀元，所以這一條是依語言決定的。
        val era =
            if (locale.language == "ar") {
                val names =
                    android.icu.text.SimpleDateFormat("G", android.icu.util.ULocale.forLocale(locale))
                " " + names.format(java.util.Date(1_000_000_000_000L))
            } else {
                ""
            }
        yearPattern = "y'${suffixes['y'] ?: ""}$era'"
        val monthLetters = counts['M'] ?: 4
        val monthSuffix = suffixes['M'] ?: ""
        month.items =
            if (monthLetters >= 3) {
                val names =
                    android.icu.text.SimpleDateFormat("MMMM", android.icu.util.ULocale.forLocale(locale))
                names.timeZone = android.icu.util.TimeZone.getTimeZone("UTC")
                // Capitalised where the region capitalises an item in a list (Августа in
                // ru_RU, agosto in pt_BR), as UIKit shows them.
                // 該地區會把清單項目大寫時就大寫(ru_RU 是 Августа,pt_BR 是 agosto),與 UIKit 顯示的相同。
                names.setContext(android.icu.text.DisplayContext.CAPITALIZATION_FOR_UI_LIST_OR_MENU)
                (1..12).map {
                    val noon = LocalDate.of(2001, it, 15).toEpochDay() * 86_400_000L + 43_200_000L
                    names.format(java.util.Date(noon)) + monthSuffix
                }
            } else {
                (1..12).map { String.format(locale, "%d", it) + monthSuffix }
            }
        year.items = (firstYear..lastYear).map { fill(yearPattern, 'y', it) }
        day.items = days(31)

        val order = full.replace('L', 'M')
        val columns =
            listOf('y' to year, 'M' to month, 'd' to day)
                .sortedBy { (letter, _) -> order.indexOf(letter).let { if (it < 0) 99 else it } }
        // Each column is its widest text and its padding; the three together are
        // centred on x 156.45, the middle of the selection bar less its inset.
        // 每一欄是它最寬的文字加上內距；三欄合起來以 x 156.45 為中心(選取列的中心扣掉其內縮)。
        class Placed(
            val column: WheelColumn, val isName: Boolean, val widest: Float, val isYear: Boolean,
            val isMonth: Boolean,
        )
        val placed =
            columns.map { (letter, column) ->
                val isName = letter == 'M' && month.items.none { name -> name.any { it.isDigit() } }
                val widest =
                    when (letter) {
                        'M' -> month.items.maxOf { width(it) }
                        'd' -> width(fill(dayPattern, 'd', 28))
                        else -> width(fill(yearPattern, 'y', 2028))
                    }
                Placed(column, isName, widest, letter == 'y', letter == 'M')
            }
        fun before(item: Placed) = if (item.isName) 17.2f else 18.8f
        // A year that is not the last column has the next one close behind it: 17
        // between 2025. and augusztus in hu_HU, 19 between 2025年 and 8月 in zh_TW,
        // where a day is followed at 36.
        // 不是最後一欄的年，下一欄緊跟在後:hu_HU 的 2025. 與 augusztus 之間是 17,zh_TW 的 2025年 與 8月 之間是 19;
        // 日的後面則隔 36。
        fun after(item: Placed) =
            when {
                item.isName -> 7.8f
                item.isYear && item !== placed.last() -> -3f
                // A month written as a number (8月) has the day 43 after it, not 50.
                item.isMonth -> 12f
                else -> 18.8f
            }
        val total = placed.sumOf { (before(it) + it.widest + after(it)).toDouble() }.toFloat()
        var x = 156.45f - total / 2
        for (item in placed) {
            item.column.align = if (item.isName) Paint.Align.LEFT else Paint.Align.CENTER
            item.column.anchor = if (item.isName) before(item) else before(item) + item.widest / 2
            val span = before(item) + item.widest + after(item)
            item.column.layoutParams =
                LayoutParams(Math.round(span * density), Math.round(216 * density)).apply {
                    leftMargin = Math.round(x * density)
                }
            x += span
        }
        requestLayout()
    }

    init {
        setWillNotDraw(false)
        month.wraps = true
        day.wraps = true
        addView(month)
        addView(day)
        addView(year)
        arrange()
        val changed: (Int) -> Unit = {
            // The day column follows the month's length. 日那一欄跟著該月的天數。
            val current = value
            day.items = days(current.lengthOfMonth())
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
        year.items = (firstYear..lastYear).map { fill(yearPattern, 'y', it) }
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
