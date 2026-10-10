package dev.swiftcrossui.androidbackend.datepickers

import android.content.Context
import java.time.LocalDateTime
import java.util.Locale

/**
 * The `.wheel` date picker style on Android, drawn to UIDatePicker's measurements.
 *
 * A date alone is [DateWheels]; a time alone is [TimeWheels]; a date and a time together
 * are [TimeWheels] with its day column, because that is one wheel on UIKit -- "Sun Aug 24"
 * beside the hours -- and not the date wheels next to the time wheels.
 *
 * Until 2026-10-10 both were the platform's Holo spinners, chosen so that this repository
 * would not own month lengths and leap years. Those now come from `java.time`, and what
 * the Holo pickers drew -- three flat rows between blue rules, abbreviated months, a month
 * calendar beside them -- was not the wheel the other backends show (P41).
 *
 * Android 上的 `.wheel` 日期選擇器樣式，依 UIDatePicker 的尺寸繪製。
 *
 * 只有日期時是 [DateWheels];只有時間時是 [TimeWheels];日期與時間都有時是帶「日」欄的 [TimeWheels],因為在 UIKit 上
 * 那是一個滾輪(「Sun Aug 24」在小時旁邊),而不是日期滾輪旁邊再放時間滾輪。
 *
 * 2026-10-10 之前兩者都是平台的 Holo 滾輪，當時的理由是不讓本倉庫自己負責月份天數與閏年。那些現在來自 `java.time`,
 * 而 Holo 畫出來的——兩條藍線之間三列平的、縮寫月份、旁邊還有一個月曆——並不是其他 backend 顯示的那種滾輪(P41)。
 */
class WheelDatePicker(context: Context) : AbstractDatePicker(context) {
    private var locale: Locale? = null

    protected override val dateView = DateWheels(context)
    protected override val timeView = TimeWheels(context)

    protected override var currentValue = LocalDateTime.now()

    init {
        dateView.onChange = {
            currentValue = LocalDateTime.of(dateView.value, currentValue.toLocalTime())
            settle()
        }

        timeView.onChange = {
            currentValue = timeView.value
            settle()
        }

        addView(dateView)
        addView(timeView)
        setLocale(Locale.getDefault())
    }

    /** Back inside the range when the wheels were let go outside it. 滾輪停在範圍外時，拉回範圍內。 */
    private fun settle() {
        val kept = value
        if (kept.toLocalDate() != dateView.value) {
            dateView.value = kept.toLocalDate()
        }
        if (kept != timeView.value) {
            timeView.value = kept
        }
        action?.call()
    }

    override fun setComponents(components: Int) {
        super.setComponents(components)
        val hasDate = components and COMPONENT_DATE != 0
        val hasTime = components and COMPONENT_TIME != 0
        timeView.showsDay = hasDate && hasTime
        dateView.visibility = if (hasDate && !hasTime) VISIBLE else GONE
    }

    override fun setLocale(locale: Locale) {
        if (locale == this.locale) return
        this.locale = locale
        dateView.locale = locale
        timeView.locale = locale
    }

    protected override fun applyRange(min: LocalDateTime, max: LocalDateTime) {
        dateView.setRange(min.toLocalDate(), max.toLocalDate())
        timeView.setRange(min.toLocalDate(), max.toLocalDate())
    }

    protected override fun applyDate(value: LocalDateTime) {
        if (dateView.value != value.toLocalDate()) {
            dateView.value = value.toLocalDate()
        }
        if (timeView.value != value) {
            timeView.value = value
        }
    }

    override fun setForegroundColor(color: Int) {
        dateView.foreground = color
        timeView.foreground = color
    }
}
