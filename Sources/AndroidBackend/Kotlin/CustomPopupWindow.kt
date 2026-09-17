package dev.swiftcrossui.androidbackend

import android.app.Activity
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorFilter
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.drawable.Drawable
import android.util.TypedValue
import android.view.View
import android.widget.PopupWindow

/// A `PopupWindow` that remembers which side of its anchor it was asked for,
/// draws a tail pointing at that anchor, and moves to the other side when the
/// panel does not fit.
///
/// **Three things live here that `PopupWindow` does not have.**
///
/// 1. **The preference.** #109 sets a side on the popover object before the
///    popover is shown, and `PopupWindow` -- unlike `GtkPopover.position` or
///    `Flyout.placement` -- has no property for a placement at all: the side is
///    decided by the arguments to `showAsDropDown`, which are spent at
///    presentation time.
/// 2. **The tail.** A `PopupWindow` is a plain window with a background
///    drawable, and Android draws no arrow on one. GTK, AppKit and UIKit all
///    draw one, and it is the thing that says WHICH control a panel belongs to
///    when two are open near each other. So it is drawn here.
/// 3. **The fit.** `showAsDropDown` shifts a popup that does not fit, which is
///    not the same as moving it to the other side of the anchor: a panel taller
///    than the room below gets pushed up until it clears the screen edge, which
///    can leave it covering the very control it was opened from. UIKit was
///    aligned on 2026-09-17 to measure the room and ask for the opposite side
///    instead; this does the same measurement so the two answer alike.
///
/// 一個會記住「它被要求出現在錨點哪一側」、會畫出指向該錨點的尾巴、並在面板放不下時改到另一側的
/// `PopupWindow`。
///
/// **此處有三樣 `PopupWindow` 沒有的東西。**
///
/// 1. **那個偏好。** #109 是在 popover 被顯示之前把某一側設在該物件上的,而 `PopupWindow`
///    ——不同於 `GtkPopover.position` 或 `Flyout.placement`——根本沒有任何表示位置的屬性:
///    那一側是由 `showAsDropDown` 的引數決定的,而那些引數要到呈現時才花掉。
/// 2. **那條尾巴。** 一個 `PopupWindow` 就是一扇帶背景 drawable 的普通視窗,而 Android 不會在上面
///    畫任何箭頭。GTK、AppKit 與 UIKit 三者都會畫,而當兩塊面板同時開在附近時,正是它說出「這一塊
///    屬於哪一個控制項」。因此在此處畫出來。
/// 3. **那個「放得下嗎」。** `showAsDropDown` 會把放不下的 popup **推**進畫面內,那與「把它移到錨點的
///    另一側」並不是同一件事:一塊比下方空間更高的面板會被往上推到離開螢幕邊緣為止,而那可能讓它蓋住
///    當初開啟它的那個控制項。UIKit 已於 2026-09-17 對齊為「量出空間、改要求相反的一側」;此處做同一個
///    量測,使兩者答得一樣。
class CustomPopupWindow(private val activity: Activity) : PopupWindow(activity) {
    companion object {
        const val EDGE_PLATFORM = 0
        const val EDGE_TOP = 1
        const val EDGE_BOTTOM = 2
        const val EDGE_LEADING = 3
        const val EDGE_TRAILING = 4
    }

    var preferredEdge: Int = EDGE_PLATFORM

    private var panelColor: Int = Color.WHITE
    private var hasPanelColor: Boolean = false

    /// The panel's own colour, so the tail is the same colour as the panel.
    /// 面板自己的顏色,好讓尾巴與面板同色。
    fun setPanelColor(color: Int, has: Boolean) {
        panelColor = color
        hasPanelColor = has
    }

    /// The side the panel will actually be placed on.
    ///
    /// The requested side when the panel fits there, the opposite side when it
    /// does not and the opposite one has room, and the requested side when
    /// neither does -- at which point the platform's own shifting is the floor,
    /// exactly as UIKit's shrinking is on the other one.
    ///
    /// 面板實際會被放置的那一側。
    ///
    /// 放得下時就是被要求的那一側;放不下、而相反那一側放得下時,就是相反那一側;兩側都放不下時仍是被
    /// 要求的那一側——那時平台自己的推移就是底線,正如另一邊 UIKit 的縮小也是底線。
    fun resolveEdge(anchor: View, requested: Int, arrowPx: Int): Int {
        if (requested == EDGE_PLATFORM) return EDGE_PLATFORM

        val location = IntArray(2)
        anchor.getLocationOnScreen(location)
        val root = anchor.rootView
        val insets = root.rootWindowInsets
        val top = insets?.systemWindowInsetTop ?: 0
        val bottom = insets?.systemWindowInsetBottom ?: 0

        val neededHeight = height + arrowPx
        val neededWidth = width + arrowPx
        val roomAbove = location[1] - top
        val roomBelow = root.height - bottom - (location[1] + anchor.height)
        val roomLeading = location[0]
        val roomTrailing = root.width - (location[0] + anchor.width)

        return when (requested) {
            EDGE_TOP ->
                if (roomAbove < neededHeight && roomBelow >= neededHeight) EDGE_BOTTOM else EDGE_TOP
            EDGE_BOTTOM ->
                if (roomBelow < neededHeight && roomAbove >= neededHeight) EDGE_TOP else EDGE_BOTTOM
            EDGE_LEADING ->
                if (roomLeading < neededWidth && roomTrailing >= neededWidth) EDGE_TRAILING
                else EDGE_LEADING
            else ->
                if (roomTrailing < neededWidth && roomLeading >= neededWidth) EDGE_LEADING
                else EDGE_TRAILING
        }
    }

    /// Puts the tail on the side facing the anchor and makes room for it.
    ///
    /// The popup grows by the tail's height on that axis, so the panel itself
    /// keeps the size the framework measured: a tail drawn inside the panel
    /// would eat a line of its content.
    ///
    /// 把尾巴放在面向錨點的那一側,並為它騰出空間。
    ///
    /// 這個 popup 會在該軸上長出「尾巴的高度」,好讓面板本身維持框架量出來的尺寸:畫在面板**之內**的
    /// 尾巴,會吃掉它一行內容。
    fun applyArrow(edge: Int, arrowPx: Int, anchorWidthPx: Int, anchorHeightPx: Int) {
        if (edge == EDGE_PLATFORM || arrowPx <= 0) {
            setBackgroundDrawable(null)
            return
        }

        val corner = dp(12f)
        val horizontal = edge == EDGE_LEADING || edge == EDGE_TRAILING
        val panelWidth = width
        val panelHeight = height

        // Along the tail's own side, pointing at the middle of the anchor.
        // `showAsDropDown` aligns the popup's leading edge with the anchor's, so
        // the anchor's middle is half its width into the panel -- clamped so the
        // tail never runs into a rounded corner.
        // 沿著尾巴自己那一側,指向錨點的中央。`showAsDropDown` 會把 popup 的前緣對齊錨點的前緣,
        // 因此錨點的中央落在面板內「它自己寬度的一半」處——並加以夾住,使尾巴永遠不會撞進圓角裡。
        val along =
            if (horizontal) (anchorHeightPx / 2).coerceIn(corner + arrowPx, panelHeight - corner - arrowPx)
            else (anchorWidthPx / 2).coerceIn(corner + arrowPx, panelWidth - corner - arrowPx)

        setBackgroundDrawable(
            PopoverBackground(edge, if (hasPanelColor) panelColor else themeBackground(), arrowPx, corner.toFloat(), along)
        )

        if (horizontal) {
            width = panelWidth + arrowPx
        } else {
            height = panelHeight + arrowPx
        }
    }

    private fun dp(value: Float): Int =
        TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            value,
            activity.resources.displayMetrics,
        ).toInt()

    private fun themeBackground(): Int {
        val value = TypedValue()
        val found =
            activity.theme.resolveAttribute(android.R.attr.colorBackground, value, true)
        return if (found) value.data else Color.WHITE
    }

    /// The panel and its tail, drawn as one shape.
    ///
    /// `getPadding` is what keeps the content off the tail: `PopupWindow` insets
    /// its content view by the background's padding, so reporting the tail's
    /// height on its own side is what reserves the strip it is drawn in.
    ///
    /// 面板與它的尾巴,畫成同一個形狀。
    ///
    /// 讓內容不會壓到尾巴的是 `getPadding`:`PopupWindow` 會依背景的 padding 內縮它的 content view,
    /// 因此在尾巴自己那一側回報它的高度,正是為它所在的那一條預留空間的方式。
    private class PopoverBackground(
        private val edge: Int,
        private val color: Int,
        private val arrow: Int,
        private val corner: Float,
        private val along: Int,
    ) : Drawable() {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
            color = this@PopoverBackground.color
        }

        override fun getPadding(padding: Rect): Boolean {
            when (edge) {
                EDGE_TOP -> padding.set(0, 0, 0, arrow)
                EDGE_BOTTOM -> padding.set(0, arrow, 0, 0)
                EDGE_LEADING -> padding.set(0, 0, arrow, 0)
                else -> padding.set(arrow, 0, 0, 0)
            }
            return true
        }

        override fun draw(canvas: Canvas) {
            val b = bounds
            val body = RectF(
                (b.left + if (edge == EDGE_TRAILING) arrow else 0).toFloat(),
                (b.top + if (edge == EDGE_BOTTOM) arrow else 0).toFloat(),
                (b.right - if (edge == EDGE_LEADING) arrow else 0).toFloat(),
                (b.bottom - if (edge == EDGE_TOP) arrow else 0).toFloat(),
            )
            canvas.drawRoundRect(body, corner, corner, paint)

            val tail = Path()
            when (edge) {
                EDGE_TOP -> {
                    tail.moveTo(b.left + along - arrow.toFloat(), body.bottom)
                    tail.lineTo(b.left + along + arrow.toFloat(), body.bottom)
                    tail.lineTo(b.left + along.toFloat(), body.bottom + arrow)
                }
                EDGE_BOTTOM -> {
                    tail.moveTo(b.left + along - arrow.toFloat(), body.top)
                    tail.lineTo(b.left + along + arrow.toFloat(), body.top)
                    tail.lineTo(b.left + along.toFloat(), body.top - arrow)
                }
                EDGE_LEADING -> {
                    tail.moveTo(body.right, b.top + along - arrow.toFloat())
                    tail.lineTo(body.right, b.top + along + arrow.toFloat())
                    tail.lineTo(body.right + arrow, b.top + along.toFloat())
                }
                else -> {
                    tail.moveTo(body.left, b.top + along - arrow.toFloat())
                    tail.lineTo(body.left, b.top + along + arrow.toFloat())
                    tail.lineTo(body.left - arrow, b.top + along.toFloat())
                }
            }
            tail.close()
            canvas.drawPath(tail, paint)
        }

        override fun setAlpha(alpha: Int) {
            paint.alpha = alpha
        }

        override fun setColorFilter(colorFilter: ColorFilter?) {
            paint.colorFilter = colorFilter
        }

        @Deprecated("Deprecated in Java", ReplaceWith("PixelFormat.TRANSLUCENT"))
        override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
    }
}
