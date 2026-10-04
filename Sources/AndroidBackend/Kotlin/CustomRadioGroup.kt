package dev.swiftcrossui.androidbackend

import android.app.Activity
import android.graphics.Typeface
import android.util.TypedValue
import android.widget.RadioButton
import android.widget.RadioGroup

class CustomRadioGroup(activity: Activity) : RadioGroup(activity) {
    companion object {
        /**
         * How a disabled option is dimmed. `setTextColor` with a plain colour
         * replaces RadioButton's own colour state list, so a disabled group's
         * labels stayed full black while iOS dims them (P74, 2026-10-04).
         * CustomSegmentedGroup dims the same way.
         * 停用選項的淡化方式。`setTextColor` 傳入單一顏色會取代 RadioButton 自己的顏色狀態清單，所以停用的
         * 群組標籤一直是全黑，而 iOS 會淡化(P74,2026-10-04)。CustomSegmentedGroup 以同樣方式淡化。
         */
        const val DISABLED_ALPHA = 0.4f
    }

    fun getSelectedOption() = getCheckedRadioButtonId()

    fun update(
        onChange: SwiftAction,
        options: Array<String>,
        isEnabled: Boolean,
        color: Int,
        fontSize: Float,
        lineHeight: Int,
        typeface: Typeface,
    ) {
        val optionCount = childCount
        if (optionCount < options.size) {
            for (i in 0..<childCount) {
                val button = getChildAt(i) as RadioButton
                button.text = options[i]
                button.setEnabled(isEnabled)
                button.alpha = if (isEnabled) 1f else DISABLED_ALPHA
                button.setTextColor(color)
                button.setTextSize(TypedValue.COMPLEX_UNIT_SP, fontSize)
                button.lineHeight = lineHeight
                button.typeface = typeface
            }

            for (i in optionCount..<options.size) {
                val button = RadioButton(context)
                button.text = options[i]
                button.id = i
                button.setEnabled(isEnabled)
                button.alpha = if (isEnabled) 1f else DISABLED_ALPHA
                button.setTextColor(color)
                button.setTextSize(TypedValue.COMPLEX_UNIT_SP, fontSize)
                button.lineHeight = lineHeight
                button.typeface = typeface
                addView(button)
            }
        } else {
            for (i in 0..<options.size) {
                val button = getChildAt(i) as RadioButton
                button.text = options[i]
                button.setEnabled(isEnabled)
                button.alpha = if (isEnabled) 1f else DISABLED_ALPHA
                button.setTextColor(color)
                button.setTextSize(TypedValue.COMPLEX_UNIT_SP, fontSize)
                button.lineHeight = lineHeight
                button.typeface = typeface
            }

            for (i in (options.size..<optionCount).reversed()) {
                removeViewAt(i)
            }
        }

        setOnCheckedChangeListener { _, _ -> onChange.call() }
    }

    fun selectOption(index: Int) {
        val oldIndex = getCheckedRadioButtonId()
        if (oldIndex == index) return

        if (oldIndex >= 0) {
            val oldButton = getChildAt(oldIndex) as RadioButton
            oldButton.isChecked = false
        }

        if (index >= 0) {
            val newButton = getChildAt(index) as RadioButton
            newButton.isChecked = true
        }
    }
}
