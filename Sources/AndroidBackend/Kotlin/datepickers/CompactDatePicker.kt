package dev.swiftcrossui.androidbackend.datepickers

import androidx.fragment.app.FragmentActivity
import java.time.LocalDateTime

class CompactDatePicker(activity: FragmentActivity) : AbstractDatePicker(activity) {
    protected override val dateView = DateButton(activity)
    protected override val timeView = TimeButton(activity)

    init {
        val childAction: () -> Unit = {
            // Clamp to range before calling through to Swift
            timeView.value = value.toLocalTime()
            action?.call()
        }

        dateView.action = childAction
        timeView.action = childAction

        addView(dateView)
        addView(timeView)
    }

    protected override var currentValue: LocalDateTime
        get() = LocalDateTime.of(dateView.value, timeView.value)
        set(newValue) {
            dateView.value = newValue.toLocalDate()
            timeView.value = newValue.toLocalTime()
        }

    // The two buttons already redraw themselves from a value they are given,
    // which is why `.compact` never showed the defect this overrides.
    // 這兩顆按鈕本來就會依所收到的值自行重繪，這正是 `.compact` 從未顯現此處所修正之缺陷的原因。
    protected override fun applyDate(value: LocalDateTime) {
        dateView.value = value.toLocalDate()
        timeView.value = value.toLocalTime()
    }

    protected override fun applyRange(min: LocalDateTime, max: LocalDateTime) {
        dateView.setRange(min, max)
        timeView.value = value.toLocalTime()
    }

    fun setForegroundColor(color: Int) {
        dateView.setTextColor(color)
        timeView.setTextColor(color)
    }
}
