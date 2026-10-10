package dev.swiftcrossui.androidbackend.datepickers

import android.content.Context
import android.text.format.DateFormat
import android.widget.TimePicker
import java.time.LocalDateTime
import java.util.Locale

/**
 * The `.wheel` date picker style on Android.
 *
 * The date is [DateWheels], drawn to UIDatePicker's measurements. Until 2026-10-10 it was the
 * platform's Holo spinner `DatePicker`, chosen so that this repository would not own month
 * lengths and leap years; those now come from `java.time` (`YearMonth.lengthOfMonth`), and
 * what the Holo picker drew -- three flat rows between blue rules, abbreviated months, a
 * month calendar beside them -- was not the wheel the other backends show (P41).
 *
 * The time is still the Holo spinner `TimePicker`: `Theme.Holo.Light` is a platform theme
 * whose pickers default to spinners, so a `ContextThemeWrapper` is all it needs.
 *
 * Android 上的 `.wheel` 日期選擇器樣式。
 *
 * 日期是 [DateWheels],依 UIDatePicker 的尺寸繪製。2026-10-10 之前用的是平台的 Holo 滾輪 `DatePicker`,當時的理由是
 * 不讓本倉庫自己負責月份天數與閏年；那些現在來自 `java.time`(`YearMonth.lengthOfMonth`),而 Holo 畫出來的——兩條藍線
 * 之間三列平的、縮寫月份、旁邊還有一個月曆——並不是其他 backend 顯示的那種滾輪(P41)。
 *
 * 時間仍是 Holo 滾輪 `TimePicker`:`Theme.Holo.Light` 是平台主題，其 picker 預設就是滾輪，所以只需要一個
 * `ContextThemeWrapper`。
 */
class WheelDatePicker(context: Context) : AbstractDatePicker(context) {
    // Declared before the two views, because they are built from it and Kotlin
    // initialises properties in declaration order.
    // 宣告在那兩個 view 之前，因為它們是以它建構的，而 Kotlin 依宣告順序初始化屬性。
    private var locale = Locale.getDefault()

    private val spinnerContext =
        android.view.ContextThemeWrapper(context, android.R.style.Theme_Holo_Light)

    protected override val dateView = DateWheels(context)
    protected override val timeView = TimePicker(spinnerContext)

    protected override var currentValue = LocalDateTime.now()

    init {
        dateView.onChange = {
            currentValue = LocalDateTime.of(dateView.value, currentValue.toLocalTime())

            adjustTimeForBounds()
            // Back inside the range when the wheels were let go outside it.
            // 滾輪停在範圍外時，拉回範圍內。
            val kept = value.toLocalDate()
            if (kept != dateView.value) {
                dateView.value = kept
            }

            action?.call()
        }

        timeView.setIs24HourView(DateFormat.is24HourFormat(context))
        timeView.setOnTimeChangedListener { _, hour, minute ->
            if (isApplyingDate) {
                return@setOnTimeChangedListener
            }
            currentValue = currentValue.withHour(hour).withMinute(minute)

            adjustTimeForBounds()

            action?.call()
        }

        // The time wheels stay the Holo TimePicker, 216 high as the date wheels.
        // 時間滾輪仍是 Holo 的 TimePicker,高 216,與日期滾輪相同。
        val wheelHeight = Math.round(216 * resources.displayMetrics.density)
        addView(dateView)
        addView(timeView, LayoutParams(LayoutParams.WRAP_CONTENT, wheelHeight))
    }

    /**
     * The same two lines GraphicalDatePicker uses, because the two hold the same
     * pair of views -- a DatePicker and a TimePicker -- and differ only in the
     * theme they are built against.
     *
     * Absent, this class was the one subclass of AbstractDatePicker that did not
     * implement the abstract member, and Kotlin refused to compile it. That
     * refusal took out `assembleDebug` for EVERY app: the failure is one class
     * in one file, and what it looks like from outside is that Android has no
     * APKs at all.
     *
     * 與 GraphicalDatePicker 所用的是同樣那兩行,因為兩者持有的是同一對 view——一個 DatePicker 與一個
     * TimePicker——差別只在它們是以哪個佈景主題建構的。
     *
     * 缺了它,本類別就是 AbstractDatePicker 底下唯一沒有實作那個抽象成員的子類別,而 Kotlin 拒絕編譯。
     * 該拒絕會讓**每一支** app 的 `assembleDebug` 一起垮掉:失敗的是一個檔案裡的一個類別,而從外面
     * 看起來的樣子,是 Android 根本產不出任何 APK。
     */
    override fun setLocale(locale: Locale) {
        if (locale == this.locale) return
        this.locale = locale
        dateView.locale = locale
        timeView.setIs24HourView(is24HourLocale(locale))
    }

    protected override fun applyRange(min: LocalDateTime, max: LocalDateTime) {
        dateView.setRange(min.toLocalDate(), max.toLocalDate())

        adjustTimeForBounds()
    }

    protected override fun applyDate(value: LocalDateTime) {
        isApplyingDate = true
        dateView.value = value.toLocalDate()
        timeView.hour = value.hour
        timeView.minute = value.minute
        isApplyingDate = false
    }

    private fun adjustTimeForBounds() {
        val time = value
        timeView.hour = time.hour
        timeView.minute = time.minute
    }

    override fun setForegroundColor(color: Int) {
        dateView.foreground = color
    }
}
