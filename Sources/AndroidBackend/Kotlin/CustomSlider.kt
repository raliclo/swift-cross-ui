package dev.swiftcrossui.androidbackend

import android.app.Activity
import android.view.MotionEvent
import android.view.ViewConfiguration
import com.google.android.material.slider.Slider
import kotlin.math.abs

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

    private var downX = 0f
    private var downY = 0f
    private var handedBack = false

    /// **Claims the gesture from the scrolling ancestor, or the slider never
    /// moves at all.**
    ///
    /// Measured on 2026-09-17, emulator-5554, with
    /// `actions/android/P11-drag-the-first-slider.csv`: press on the first
    /// thumb, drag 160 points right. Before this, the readout still said
    /// `minimum 20`, `uiautomator` put the thumb at 319..445 against a track
    /// starting at 368 -- the very start, unmoved -- and the PAGE had scrolled
    /// right instead. The root is a `HorizontalScrollView`; it takes any
    /// gesture that travels one touch slop horizontally, which is the same 8dp
    /// theft that was taking pinch and rotate from
    /// `ContinuousGestureContainer` the same day.
    ///
    /// Material's `BaseSlider` does call `requestDisallowInterceptTouchEvent`
    /// itself, and it was not enough: its own call comes after it decides the
    /// drag is horizontal, by which time a horizontally scrolling parent has
    /// already taken it. That is the difference between reading the library and
    /// driving it.
    ///
    /// **Handed back when the drag turns out to be vertical**, so a list that
    /// scrolls under a slider still scrolls when the finger starts on one. That
    /// is why this is not an unconditional disallow on ACTION_DOWN.
    ///
    /// **從會捲動的祖先手中把手勢要回來,否則這個滑桿根本不會動。**
    ///
    /// 2026-09-17 於 emulator-5554 以 `actions/android/P11-drag-the-first-slider.csv` 實測:
    /// 按在第一個滑塊上,向右拖 160 點。在此修正之前,讀數仍是 `minimum 20`,`uiautomator` 給出滑塊
    /// 位於 319..445、而軌道起於 368——也就是最起點、完全沒動——而**整頁**反而向右捲了。根部是一個
    /// `HorizontalScrollView`;任何水平移動達一個 touch slop 的手勢它都會拿走,而那正是同一天把縮放與
    /// 旋轉從 `ContinuousGestureContainer` 手中拿走的那個 8dp 奪取。
    ///
    /// Material 的 `BaseSlider` 確實會自己呼叫 `requestDisallowInterceptTouchEvent`,而那不夠:
    /// 它那次呼叫發生在它判定這是一次水平拖曳**之後**,而那時水平捲動的父節點已經把手勢拿走了。
    /// 這就是「讀那個函式庫」與「驅動它」之間的差別。
    ///
    /// **當這次拖曳最後看起來是垂直的,就把手勢還回去**,如此「滑桿底下會捲動的清單」在手指起於滑桿上
    /// 時仍然捲得動。這正是此處不在 ACTION_DOWN 無條件 disallow 的理由。
    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downX = event.x
                downY = event.y
                handedBack = false
                parent?.requestDisallowInterceptTouchEvent(true)
            }

            MotionEvent.ACTION_MOVE ->
                if (!handedBack) {
                    val slop = ViewConfiguration.get(context).scaledTouchSlop
                    val dx = abs(event.x - downX)
                    val dy = abs(event.y - downY)
                    if (dy > dx && dy > slop) {
                        handedBack = true
                        parent?.requestDisallowInterceptTouchEvent(false)
                    }
                }
        }
        return super.onTouchEvent(event)
    }

    fun setBounds(min: Float, max: Float, places: Int) {
        this.places = places
        valueFrom = min
        valueTo = max
    }
}
