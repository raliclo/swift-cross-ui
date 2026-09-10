package dev.swiftcrossui.androidbackend

import android.app.Activity
import com.google.android.material.slider.Slider

class CustomSlider(activity: Activity) : Slider(activity) {
    var action: SwiftAction? = null

    // Two actions rather than one carrying a Bool.
    //
    // `SwiftAction` calls back with no arguments, and adding a Bool-carrying
    // variant would mean a new JNI bridge type for a value with two states.
    // Material's Slider reports the two edges separately anyway --
    // `onStartTrackingTouch` and `onStopTrackingTouch` -- so the shape here
    // matches the shape of what the platform reports.
    //
    // 使用兩個 action，而不是一個帶 Bool 的。
    //
    // `SwiftAction` 的回呼不帶參數，而為了一個只有兩種狀態的值去新增一個「帶 Bool」的變體，
    // 等於為它新增一個 JNI 橋接型別。反正 Material 的 Slider 本來就分別回報那兩個邊界
    // ——`onStartTrackingTouch` 與 `onStopTrackingTouch`——因此此處的形狀與平台回報的形狀一致。
    var editingBeganAction: SwiftAction? = null
    var editingEndedAction: SwiftAction? = null

    private var places = 7

    init {
        addOnChangeListener { _, _, fromUser ->
            if (fromUser) {
                action?.call()
            }
        }

        addOnSliderTouchListener(object : Slider.OnSliderTouchListener {
            override fun onStartTrackingTouch(slider: Slider) {
                editingBeganAction?.call()
            }

            override fun onStopTrackingTouch(slider: Slider) {
                editingEndedAction?.call()
            }
        })

        isTickVisible = false

        setLabelFormatter { String.format("%.${places}f", it.toDouble()) }
    }

    fun setBounds(min: Float, max: Float, places: Int) {
        this.places = places
        valueFrom = min
        valueTo = max
    }
}
