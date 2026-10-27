package dev.swiftcrossui.androidbackend

import android.R
import android.app.Activity
import android.content.Context
import android.graphics.Color
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.TextView
import android.widget.FrameLayout

class CustomButton(activity: Activity) : FrameLayout(activity) {
    var buttonStyle: Short = ButtonStyle.BORDERED
    var action: SwiftAction? = null

    private val density = resources.displayMetrics.density

    companion object {
        const val horizontalPadding = 11
        const val verticalPadding = 5

        const val borderedButtonStyle = ButtonStyle.BORDERED
        const val plainButtonStyle = ButtonStyle.PLAIN
        const val borderlessButtonStyle = ButtonStyle.BORDERLESS

        private val BORDERED_ATTR = R.attr.selectableItemBackground
        private val BORDERLESS_ATTR = R.attr.selectableItemBackgroundBorderless

        private fun getDrawable(context: Context, attrId: Int): Drawable? {
            val outValue = TypedValue()
            context.theme.resolveAttribute(attrId, outValue, true)
            return context.getDrawable(outValue.resourceId)
        }
    }

    object ButtonStyle {
        const val BORDERED: Short = 0
        const val PLAIN: Short = 1
        const val BORDERLESS: Short = 2
    }

    init {
        isClickable = true
        isFocusable = true

        setOnClickListener { view -> if (isEnabled) this.action?.call() }
    }

    fun set(action: SwiftAction, buttonStyle: Short, isEnabled: Boolean, isDarkMode: Boolean) {
        this.buttonStyle = buttonStyle
        this.action = action
        this.isEnabled = isEnabled

        updateButtonStyle(isDarkMode)
        refreshAccessibilityName()
    }

    /// Names this button for TalkBack, from the texts below it.
    ///
    /// A `FrameLayout` is not focusable by default, so the description alone
    /// would not be announced -- `isFocusable` is set with it. Both are needed
    /// and either alone is silent.
    ///
    /// 從這顆按鈕底下的文字，為 TalkBack 為它命名。
    ///
    /// 一個 `FrameLayout` 預設不可取得焦點，因此光有描述並不會被念出來——`isFocusable` 與它一起設定。
    /// 兩者都必要，缺任何一個都是靜默的。
    fun refreshAccessibilityName() {
        val name = joinedText(this)
        contentDescription = name
        isFocusable = name != null
    }

    /// **Every text in the label, in order, joined by spaces -- not just the
    /// first.**
    ///
    /// P67's second button is the case that needs it: a button labelled with
    /// two `Text`s would otherwise announce itself as "two", dropping "texts"
    /// from beside it on screen. The other backends agree -- GtkBackend read
    /// externally over AT-SPI names it `two texts`, SwiftUI's VoiceOver reads
    /// both texts, and WinUIBackend joins them. `.accessibilityLabel(_:)` still
    /// overrides it.
    ///
    /// **標籤裡的每一段文字,依序、以空白串接——不是只取第一段。**
    ///
    /// P67 的第二顆按鈕正是需要它的情況:一顆以兩個 `Text` 標示的按鈕,否則會把自己宣告為「two」,
    /// 丟掉畫面上就在旁邊的「texts」。其他 backend 都一致——經 AT-SPI 由外部讀到的 GtkBackend 命名為
    /// `two texts`、SwiftUI 的 VoiceOver 會唸出兩段、WinUIBackend 也串接。
    /// `.accessibilityLabel(_:)` 仍然覆蓋它。
    private fun joinedText(view: View): CharSequence? {
        val texts = mutableListOf<CharSequence>()
        collectText(view, texts)
        return if (texts.isEmpty()) null else texts.joinToString(" ")
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

    fun updateButtonStyle(isDarkMode: Boolean) {
        // Why 38% opacity was chosen:
        // https://m2.material.io/design/interaction/states.html#disabled
        alpha = if (isEnabled) 1.0f else 0.38f

        val borderedBackground by lazy {
            GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                setColor(getAdaptiveGray(isDarkMode))
                cornerRadius = 3f * resources.displayMetrics.density
            }
        }

        val convertedHorizontalPadding = (horizontalPadding * density).toInt()
        val convertedVerticalPadding = (verticalPadding * density).toInt()

        when (buttonStyle) {
            ButtonStyle.BORDERED -> {
                background = borderedBackground
                setPadding(
                    convertedHorizontalPadding,
                    convertedVerticalPadding,
                    convertedHorizontalPadding,
                    convertedVerticalPadding,
                )
            }
            ButtonStyle.PLAIN,
            ButtonStyle.BORDERLESS -> {
                background = null
                setPadding(0, 0, 0, 0)
            }
            else -> {
                background = borderedBackground
                setPadding(
                    convertedHorizontalPadding,
                    convertedVerticalPadding,
                    convertedHorizontalPadding,
                    convertedVerticalPadding,
                )
            }
        }

        val foregroundAttr =
            when (buttonStyle) {
                ButtonStyle.PLAIN,
                ButtonStyle.BORDERLESS -> BORDERLESS_ATTR
                else -> BORDERED_ATTR
            }

        // Sets or removes the press ripple effect.
        if (isEnabled) {
            foreground = getDrawable(context, foregroundAttr)
        } else {
            foreground = null
        }
    }

    override fun onInitializeAccessibilityNodeInfo(info: AccessibilityNodeInfo) {
        super.onInitializeAccessibilityNodeInfo(info)
        info.className = "android.widget.Button"
    }

    override fun addView(child: View, index: Int, params: ViewGroup.LayoutParams) {
        val frameParams = params as? LayoutParams ?: LayoutParams(params)

        frameParams.gravity = Gravity.CENTER
        frameParams.width = ViewGroup.LayoutParams.WRAP_CONTENT
        frameParams.height = ViewGroup.LayoutParams.WRAP_CONTENT

        super.addView(child, index, frameParams)
    }

    fun getAdaptiveGray(isDarkMode: Boolean): Int {
        return if (isDarkMode) Color.DKGRAY else Color.LTGRAY
    }
}
