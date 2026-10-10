package dev.swiftcrossui.androidbackend.datepickers

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.view.MotionEvent
import android.view.VelocityTracker
import android.view.View
import android.view.animation.DecelerateInterpolator
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin

/**
 * One column of UIDatePicker's wheel, to measurements from UIKitBackend (P41, 2026-10-10):
 * rows on a cylinder of radius 100 at 18.2 degrees apart -- so 31, 59 and 78 from the
 * middle -- seven showing in 216; the middle row 23 in the label colour, the others 20.5
 * in grey (164, fading to 204 at the third). The framework's NumberPicker shows three
 * flat rows between two blue rules.
 *
 * UIDatePicker 滾輪的一欄，尺寸取自 UIKitBackend(P41,2026-10-10):列排在半徑 100 的圓柱上、相隔 18.2 度
 * (距中央 31、59、78),216 內顯示七列；中央列 23、標籤色，其餘 20.5、灰色(164,第三列淡到 204)。
 * 框架的 NumberPicker 是兩條藍線之間三列平的。
 */
class WheelColumn(context: Context) : View(context) {
    var items: List<String> = emptyList()
        set(value) {
            field = value
            if (index > value.size - 1) index = (value.size - 1).coerceAtLeast(0)
            invalidate()
        }

    var index: Int = 0
        set(value) {
            field = value
            if (!dragging && animator == null) position = value.toFloat()
            invalidate()
        }

    var onChange: ((Int) -> Unit)? = null
    var align: Paint.Align = Paint.Align.CENTER

    /** Where the text is anchored, in dp from the column's left. 文字的錨點，距欄左緣的 dp。 */
    var anchor: Float = 0f
    var foreground: Int = Color.BLACK
        set(value) {
            field = value
            invalidate()
        }

    private var position = 0f
    private var dragging = false
    private var lastY = 0f
    private var animator: ValueAnimator? = null
    private var tracker: VelocityTracker? = null
    private val density = resources.displayMetrics.density
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val step = Math.toRadians(18.2)
    private val radius = 100f

    private fun isLight(color: Int) =
        (Color.red(color) * 299 + Color.green(color) * 587 + Color.blue(color) * 114) / 1000 > 127

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (items.isEmpty()) return
        val centreY = height / 2f
        val nearest = position.roundToInt()
        paint.typeface = Typeface.DEFAULT
        paint.textAlign = align
        val light = isLight(foreground)
        for (row in nearest - 4..nearest + 4) {
            if (row < 0 || row >= items.size) continue
            val distance = row - position
            val angle = distance * step
            if (abs(angle) > Math.toRadians(62.0)) continue
            val near = abs(distance).coerceAtMost(1f)
            val far = ((abs(distance) - 2f).coerceIn(0f, 1f))
            // Label colour in the middle; 164 grey beside it, 204 at the third row
            // (on dark: their complements).
            val grey = (164 + 40 * far).roundToInt().let { if (light) 255 - it else it }
            val red = Color.red(foreground) + ((grey - Color.red(foreground)) * near).roundToInt()
            val green = Color.green(foreground) + ((grey - Color.green(foreground)) * near).roundToInt()
            val blue = Color.blue(foreground) + ((grey - Color.blue(foreground)) * near).roundToInt()
            paint.color = Color.rgb(red, green, blue)
            paint.alpha = if (isEnabled) 255 else 77
            paint.textSize = (23f - 2.5f * near) * density
            canvas.save()
            canvas.translate(anchor * density, centreY + (radius * sin(angle)).toFloat() * density)
            canvas.scale(1f, cos(angle).toFloat())
            canvas.drawText(items[row], 0f, -(paint.descent() + paint.ascent()) / 2, paint)
            canvas.restore()
        }
    }

    private fun settle(target: Int) {
        val end = target.coerceIn(0, (items.size - 1).coerceAtLeast(0))
        animator?.cancel()
        val animation = ValueAnimator.ofFloat(position, end.toFloat())
        animation.duration = (120 + 60 * abs(end - position)).toLong().coerceAtMost(900)
        animation.interpolator = DecelerateInterpolator(1.6f)
        animation.addUpdateListener {
            position = it.animatedValue as Float
            invalidate()
        }
        animation.addListener(
            object : android.animation.AnimatorListenerAdapter() {
                override fun onAnimationEnd(ended: android.animation.Animator) {
                    if (animator !== animation) return
                    animator = null
                    position = end.toFloat()
                    if (end != index) {
                        index = end
                        onChange?.invoke(end)
                    }
                    invalidate()
                }
            },
        )
        animator = animation
        animation.start()
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (!isEnabled || items.isEmpty()) return false
        val rowHeight = 31.3f * density
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                animator?.let {
                    animator = null
                    it.cancel()
                }
                dragging = true
                lastY = event.y
                tracker = VelocityTracker.obtain().also { it.addMovement(event) }
                parent?.requestDisallowInterceptTouchEvent(true)
            }
            MotionEvent.ACTION_MOVE -> {
                tracker?.addMovement(event)
                position =
                    (position - (event.y - lastY) / rowHeight)
                        .coerceIn(-0.4f, items.size - 0.6f)
                lastY = event.y
                invalidate()
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                dragging = false
                val moved = tracker
                moved?.addMovement(event)
                moved?.computeCurrentVelocity(1000)
                val velocity = moved?.yVelocity ?: 0f
                moved?.recycle()
                tracker = null
                // A fifth of a second of the release speed, in rows.
                settle((position - velocity * 0.2f / rowHeight).roundToInt())
            }
        }
        return true
    }
}
