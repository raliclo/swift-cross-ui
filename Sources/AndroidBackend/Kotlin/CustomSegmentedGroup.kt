package dev.swiftcrossui.androidbackend

import android.app.Activity
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.StateListDrawable
import android.util.TypedValue
import android.view.Gravity
import android.widget.RadioButton
import android.widget.RadioGroup

/**
 * `.segmented` on Android: one row of joined segments, the chosen one filled.
 *
 * Android has no platform segmented control (Material's button toggle group is a
 * library, not the platform), so this is a horizontal RadioGroup -- which already
 * gives single choice, keyboard and accessibility semantics -- with the radio
 * dots removed and each button drawn as a bordered segment. Until 2026-09-29 the
 * style was `fatalError("Unsupported picker style")`.
 *
 * `.segmented` 在 Android 上:一列相連的分段,選中的那一段填色。Android 平台本身沒有分段控制項(Material 的 button
 * toggle group 是函式庫,不是平台),所以這是一個水平的 RadioGroup——它本來就提供單選、鍵盤與無障礙語意——拿掉圓點、
 * 把每顆按鈕畫成有邊框的一段。2026-09-29 之前這個樣式是 `fatalError`。
 */
class CustomSegmentedGroup(activity: Activity) : RadioGroup(activity) {
    init {
        orientation = HORIZONTAL
    }

    fun getSelectedOption() = getCheckedRadioButtonId()

    private fun dp(value: Float): Int =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, value, resources.displayMetrics)
            .toInt()

    private fun segmentBackground(accent: Int): StateListDrawable {
        fun shape(fill: Int) = GradientDrawable().apply {
            setColor(fill)
            setStroke(dp(1f), accent)
            cornerRadius = dp(6f).toFloat()
        }
        val selectedFill = Color.argb(70, Color.red(accent), Color.green(accent), Color.blue(accent))
        return StateListDrawable().apply {
            addState(intArrayOf(android.R.attr.state_checked), shape(selectedFill))
            addState(intArrayOf(), shape(Color.TRANSPARENT))
        }
    }

    private fun style(
        button: RadioButton,
        text: String,
        isEnabled: Boolean,
        color: Int,
        fontSize: Float,
        lineHeight: Int,
        typeface: Typeface,
    ) {
        button.text = text
        button.setEnabled(isEnabled)
        button.setTextColor(color)
        button.setTextSize(TypedValue.COMPLEX_UNIT_SP, fontSize)
        button.lineHeight = lineHeight
        button.typeface = typeface
        button.buttonDrawable = null
        button.buttonTintList = ColorStateList.valueOf(Color.TRANSPARENT)
        button.gravity = Gravity.CENTER
        button.setPadding(dp(14f), dp(6f), dp(14f), dp(6f))
        button.background = segmentBackground(color)
        // Disabled segments are dimmed, as every Android control is.
        // 停用的分段變淡,和每個 Android 控制項一樣。
        button.alpha = if (isEnabled) 1f else 0.4f
    }

    fun update(
        onChange: SwiftAction,
        options: Array<String>,
        isEnabled: Boolean,
        color: Int,
        fontSize: Float,
        lineHeight: Int,
        typeface: Typeface,
    ) {
        setOnCheckedChangeListener(null)
        for (i in (options.size..<childCount).reversed()) {
            removeViewAt(i)
        }
        for (i in 0..<options.size) {
            val button = if (i < childCount) {
                getChildAt(i) as RadioButton
            } else {
                RadioButton(context).also {
                    it.id = i
                    addView(it)
                }
            }
            style(button, options[i], isEnabled, color, fontSize, lineHeight, typeface)
        }
        setOnCheckedChangeListener { _, _ -> onChange.call() }
    }

    fun selectOption(index: Int) {
        if (getCheckedRadioButtonId() == index) return
        if (index >= 0 && index < childCount) {
            check(index)
        } else {
            clearCheck()
        }
    }
}
