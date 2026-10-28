package dev.swiftcrossui.androidbackend

import android.app.Activity
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.InsetDrawable
import android.graphics.drawable.StateListDrawable
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.FrameLayout
import android.widget.TextView

/// A button-style toggle whose label is a SwiftCrossUI view
/// (`Toggle(isOn:label:)` with `.toggleStyle(.button)`).
///
/// Drawn as `styleToggleButton` draws the string-label `ToggleButton`: clear
/// while off, the theme's `colorPrimary` filled behind the label while on, 6 dp
/// corners, the fill reaching 6 dp past the label at each side without taking
/// part in the layout, and 6 dp above and below. The label is the only child
/// and a click anywhere on the frame -- the label included -- flips the state
/// and calls `action`. TalkBack sees a toggle button named by the label's
/// texts, checkable, with its checked state.
///
/// 標籤為 SwiftCrossUI view 的按鈕樣式 toggle(`.toggleStyle(.button)` 的 `Toggle(isOn:label:)`)。
///
/// 畫法與 `styleToggleButton` 畫字串標籤 `ToggleButton` 相同：關時透明，開時在標籤後填滿主題的 `colorPrimary`,6 dp 圓角，
/// 填色在標籤左右各多出 6 dp 且不參與排版，上下各 6 dp。標籤是唯一的子 view,在框上任何位置(含標籤)點擊都會翻轉狀態並呼叫
/// `action`。TalkBack 看到的是一個以標籤文字命名、可勾選、帶勾選狀態的 toggle button。
class ViewLabelToggleButton(activity: Activity) : FrameLayout(activity) {
    var action: SwiftAction? = null
    private var on = false

    companion object {
        const val verticalPadding = 6
        const val fillOutset = 6
    }

    init {
        isClickable = true
        isFocusable = true
        val density = resources.displayMetrics.density
        val pad = (verticalPadding * density).toInt()
        setPadding(0, pad, 0, pad)

        val value = TypedValue()
        val primary =
            if (context.theme.resolveAttribute(android.R.attr.colorPrimary, value, true)) {
                if (value.resourceId != 0) context.getColor(value.resourceId) else value.data
            } else {
                Color.BLUE
            }
        val filled = GradientDrawable()
        filled.cornerRadius = 6 * density
        filled.setColor(primary)
        val outset = -(fillOutset * density).toInt()
        val states = StateListDrawable()
        states.addState(
            intArrayOf(android.R.attr.state_activated),
            InsetDrawable(filled, outset, 0, outset, 0),
        )
        states.addState(intArrayOf(), ColorDrawable(Color.TRANSPARENT))
        background = states

        setOnClickListener {
            if (isEnabled) {
                on = !on
                isActivated = on
                action?.call()
                sendAccessibilityEvent(AccessibilityEvent.TYPE_VIEW_CLICKED)
            }
        }
    }

    fun set(action: SwiftAction, isEnabled: Boolean) {
        this.action = action
        this.isEnabled = isEnabled
        refreshAccessibilityName()
    }

    fun setOn(value: Boolean) {
        on = value
        isActivated = value
    }

    fun isOn(): Boolean = on

    private fun refreshAccessibilityName() {
        val texts = mutableListOf<CharSequence>()
        collectText(this, texts)
        contentDescription = if (texts.isEmpty()) null else texts.joinToString(" ")
        for (index in 0 until childCount) {
            getChildAt(index).importantForAccessibility =
                View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        }
    }

    private fun collectText(view: View, into: MutableList<CharSequence>) {
        if (view is TextView) {
            val text = view.text
            if (!text.isNullOrEmpty()) {
                into.add(text)
                return
            }
        }
        if (view is ViewGroup) {
            for (index in 0 until view.childCount) {
                collectText(view.getChildAt(index), into)
            }
        }
    }

    override fun onInitializeAccessibilityNodeInfo(info: AccessibilityNodeInfo) {
        super.onInitializeAccessibilityNodeInfo(info)
        info.className = "android.widget.ToggleButton"
        info.isCheckable = true
        info.isChecked = on
    }

    override fun addView(child: View, index: Int, params: ViewGroup.LayoutParams) {
        val frameParams = params as? LayoutParams ?: LayoutParams(params)
        frameParams.gravity = Gravity.CENTER
        frameParams.width = ViewGroup.LayoutParams.WRAP_CONTENT
        frameParams.height = ViewGroup.LayoutParams.WRAP_CONTENT
        super.addView(child, index, frameParams)
    }
}
