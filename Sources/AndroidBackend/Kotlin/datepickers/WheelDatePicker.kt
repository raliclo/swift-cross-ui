package dev.swiftcrossui.androidbackend.datepickers

import android.content.Context
import android.text.format.DateFormat
import android.widget.DatePicker
import android.widget.TimePicker
import java.time.LocalDateTime
import java.time.temporal.ChronoUnit

/**
 * The `.wheel` date picker style on Android.
 *
 * Identical to [GraphicalDatePicker] except for the Context its two children are
 * built with, and that difference is the whole style: `DatePicker` and
 * `TimePicker` choose calendar or spinner from the theme they resolve against,
 * and the app's Material theme resolves to calendar.
 *
 * **`android:datePickerMode="spinner"` is not the only way to ask.** The
 * comment this class replaces said the style had to wait for swift-bundler to
 * support XML resources in libraries, because that attribute can only be set in
 * XML. It can only be *set* there; it can be *defaulted* by a theme, and
 * `Theme.Holo.Light` is a platform theme -- `android.R.style`, not an app
 * resource -- whose DatePicker and TimePicker defaults are the spinners. So the
 * style needs no resource of ours at all, only a `ContextThemeWrapper`.
 *
 * Holo is deprecated and still shipped; the wheels it draws are the platform's
 * own, not a reimplementation. Composing three `NumberPicker`s was the other
 * candidate and would have been this repository inventing a date picker --
 * including its month lengths, its leap years and its locale ordering.
 *
 * Android 上的 `.wheel` 日期選擇器樣式。
 *
 * 除了「用來建構其兩個子元件的 Context」之外，與 [GraphicalDatePicker] 完全相同，而那個差異就是
 * 這個樣式的全部：`DatePicker` 與 `TimePicker` 是從它們所解析的主題來決定要用日曆還是滾輪的，
 * 而 app 的 Material 主題解析出來的是日曆。
 *
 * **`android:datePickerMode="spinner"` 並不是唯一的詢問方式。** 本類別所取代的那則註解說，這個
 * 樣式必須等到 swift-bundler 支援函式庫中的 XML 資源，因為該屬性只能在 XML 中設定。它確實只能在
 * 那裡被**設定**，但它可以被主題**預設**——而 `Theme.Holo.Light` 是一個平台主題（位於
 * `android.R.style`，不是 app 的資源），其 DatePicker 與 TimePicker 的預設值正是滾輪。因此這個
 * 樣式完全不需要我們自己的任何資源，只需要一個 `ContextThemeWrapper`。
 *
 * Holo 已被標記為棄用，但仍然隨系統提供；它所繪製的滾輪是平台自己的，而非重新實作的版本。另一個
 * 候選做法是以三個 `NumberPicker` 組合出來，那等於由本倉庫自行發明一個日期選擇器——連同它的月份
 * 天數、閏年與地區順序。
 */
class WheelDatePicker(context: Context) : AbstractDatePicker(context) {
    // Declared before the two views, because they are built from it and Kotlin
    // initialises properties in declaration order.
    // 宣告在那兩個 view 之前，因為它們是以它建構的，而 Kotlin 依宣告順序初始化屬性。
    private val spinnerContext =
        android.view.ContextThemeWrapper(context, android.R.style.Theme_Holo_Light)

    protected override val dateView = DatePicker(spinnerContext)
    protected override val timeView = TimePicker(spinnerContext)

    protected override var currentValue = LocalDateTime.now()

    init {
        dateView.setOnDateChangedListener { _, year, month, day ->
            currentValue = currentValue.withYear(year).withMonth(month + 1).withDayOfMonth(day)

            adjustTimeForBounds()

            action?.call()
        }

        timeView.setIs24HourView(DateFormat.is24HourFormat(context))
        timeView.setOnTimeChangedListener { _, hour, minute ->
            currentValue = currentValue.withHour(hour).withMinute(minute)

            adjustTimeForBounds()

            action?.call()
        }

        addView(dateView)
        addView(timeView)
    }

    protected override fun applyRange(min: LocalDateTime, max: LocalDateTime) {
        dateView.minDate = Constants.EPOCH.until(min, ChronoUnit.MILLIS)
        dateView.maxDate = Constants.EPOCH.until(max, ChronoUnit.MILLIS)

        adjustTimeForBounds()
    }

    private fun adjustTimeForBounds() {
        val time = value
        timeView.hour = time.hour
        timeView.minute = time.minute
    }
}
