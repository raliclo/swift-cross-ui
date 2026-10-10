package dev.swiftcrossui.androidbackend.datepickers

import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.util.TypedValue
import android.widget.Button
import java.text.DateFormat
import java.text.SimpleDateFormat
import java.time.LocalDateTime
import java.time.temporal.ChronoUnit
import java.util.Locale

// A Button drawn as UIDatePicker's compact field: a capsule of tertiarySystemFill
// (118, 118, 128 at 12%), 34 high, 17-point regular text, 12 of inset.
// The framework's raised grey button with bold text was what P41 showed.
// 把 Button 畫成 UIDatePicker 的 compact 欄位:tertiarySystemFill(118, 118, 128、12%)的膠囊、高 34、
// 17 點的常規字、內縮 12。P41 原本顯示的是框架的凸起灰色粗體按鈕。
fun styleAsPickerField(button: Button) {
    val density = button.resources.displayMetrics.density
    val fill = GradientDrawable()
    fill.cornerRadius = 17 * density
    fill.setColor(Color.argb(31, 118, 118, 128))
    button.background = fill
    button.stateListAnimator = null
    button.isAllCaps = false
    button.typeface = Typeface.DEFAULT
    button.letterSpacing = 0f
    button.setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
    button.minWidth = 0
    button.minimumWidth = 0
    button.minHeight = 0
    button.minimumHeight = 0
    val inset = Math.round(12 * density)
    button.setPadding(inset, 0, inset, 0)
    button.height = Math.round(34 * density)
}

object Constants {
    val EPOCH = LocalDateTime.of(1970, 1, 1, 0, 0)

    val defaultMinDate =
        try {
            EPOCH.until(LocalDateTime.MIN, ChronoUnit.MILLIS)
        } catch (_: ArithmeticException) {
            Long.MIN_VALUE
        }

    val defaultMaxDate =
        try {
            EPOCH.until(LocalDateTime.MAX, ChronoUnit.MILLIS)
        } catch (_: ArithmeticException) {
            Long.MAX_VALUE
        }
}

fun is24HourLocale(locale: Locale): Boolean {
    // Based on
    // https://cs.android.com/android/platform/superproject/+/android-latest-release:frameworks/base/core/java/android/text/format/DateFormat.java;drc=8b53f4656c9760da39d5b55b86dde5b311ed131d;l=214

    val natural = DateFormat.getTimeInstance(DateFormat.LONG, locale)
    if (natural !is SimpleDateFormat) return false

    var insideQuote = false
    for (c in natural.toPattern()) {
        if (c == '\'') {
            insideQuote = !insideQuote
        } else if (!insideQuote && c == 'H') {
            return true
        }
    }

    return false
}
