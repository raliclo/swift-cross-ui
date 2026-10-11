package dev.swiftcrossui.androidbackend

import android.app.Activity
import android.widget.NumberPicker

class CustomNumberPicker(activity: Activity) : NumberPicker(activity) {
    init {
        minValue = 0
    }

    // A NumberPicker asks for 64 x 180 dp; UIKit's wheel (UIPickerView) is 320 x 216 pt, and
    // the same Picker took a fifth of the width on Android that it took on iOS (P74,
    // 2026-10-12). The wheel asks for UIKit's size and still yields to a smaller offer.
    // NumberPicker 要的是 64 x 180 dp;UIKit 的滾輪(UIPickerView)是 320 x 216 pt,同一個 Picker 在 Android 上只有 iOS
    // 五分之一寬(P74,2026-10-12)。滾輪改要 UIKit 的尺寸，給得比較小時仍然讓步。
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
        val density = resources.displayMetrics.density
        fun resolve(want: Int, spec: Int): Int =
            when (MeasureSpec.getMode(spec)) {
                MeasureSpec.EXACTLY -> MeasureSpec.getSize(spec)
                MeasureSpec.AT_MOST -> minOf(want, MeasureSpec.getSize(spec))
                else -> want
            }
        setMeasuredDimension(
            resolve((320 * density).toInt(), widthMeasureSpec),
            resolve((216 * density).toInt(), heightMeasureSpec),
        )
    }

    fun update(onChange: SwiftAction, options: Array<String>, isEnabled: Boolean) {
        maxValue = options.size
        displayedValues = arrayOf("") + options

        setOnValueChangedListener { _, _, _ -> onChange.call() }

        setEnabled(isEnabled)
    }
}
