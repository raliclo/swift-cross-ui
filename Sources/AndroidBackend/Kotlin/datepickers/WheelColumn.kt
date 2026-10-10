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
import android.view.ViewConfiguration
import android.view.animation.DecelerateInterpolator
import kotlin.math.abs
import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin

/**
 * One column of UIDatePicker's wheel, to measurements from UIKitBackend (P41, 2026-10-10):
 * rows on a cylinder of radius 100 at 18.2 degrees apart -- so 31, 59 and 78 from the
 * middle -- seven showing in 216 and an eighth pair just entering; the middle row 23 in the
 * label colour, the others 20.5 in grey (164, then 204 at the third and 238 at the
 * fourth). A column that [wraps] goes round, as UIKit's months, days, hours and minutes
 * do. The framework's NumberPicker shows three flat rows between two blue rules.
 *
 * UIDatePicker 滾輪的一欄，尺寸取自 UIKitBackend(P41,2026-10-10):列排在半徑 100 的圓柱上、相隔 18.2 度
 * (距中央 31、59、78),216 內顯示七列，第八對剛要進來；中央列 23、標籤色，其餘 20.5、灰色(164,第三列 204、
 * 第四列 238)。[wraps] 的欄會循環，如同 UIKit 的月、日、時、分。框架的 NumberPicker 是兩條藍線之間三列平的。
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

    /** Whether the last row is followed by the first. 最後一列之後是否接第一列。 */
    var wraps = false

    var foreground: Int = Color.BLACK
        set(value) {
            field = value
            invalidate()
        }

    private var position = 0f
    private var dragging = false
    private var lastY = 0f
    private var downY = 0f
    private var travelled = 0f
    private var animator: ValueAnimator? = null
    private var tracker: VelocityTracker? = null
    private val density = resources.displayMetrics.density
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val step = Math.toRadians(18.2)
    private val radius = 100f

    private fun isLight(color: Int) =
        (Color.red(color) * 299 + Color.green(color) * 587 + Color.blue(color) * 114) / 1000 > 127

    private fun item(row: Int): String? {
        if (items.isEmpty()) return null
        if (wraps) return items[Math.floorMod(row, items.size)]
        return items.getOrNull(row)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (items.isEmpty()) return
        val centreY = height / 2f
        val nearest = position.roundToInt()
        paint.typeface = Typeface.DEFAULT
        paint.textAlign = align
        val light = isLight(foreground)
        val middle =
            if (light) {
                Color.rgb(
                    Color.red(foreground) * 9 / 10, Color.green(foreground) * 9 / 10,
                    Color.blue(foreground) * 9 / 10,
                )
            } else foreground
        for (row in nearest - 5..nearest + 5) {
            val text = item(row) ?: continue
            val distance = row - position
            val angle = distance * step
            if (abs(angle) > Math.toRadians(80.0)) continue
            val away = abs(distance)
            val near = away.coerceAtMost(1f)
            // Label colour in the middle; 164 grey beside it, 204 at the third row and
            // 238 at the fourth (on dark: their complements).
            val shade =
                164f + 40f * (away - 2f).coerceIn(0f, 1f) + 34f * (away - 3f).coerceIn(0f, 1f)
            // On dark the complement, less 2 as UIKit's measure (89 beside the middle), and the
            // middle row is the label colour at 90% (230). 深色時取補色再減 2(中央旁是 89),中央列是標籤色的 90%(230)。
            val grey = shade.roundToInt().let { if (light) 253 - it else it }
            val red = Color.red(middle) + ((grey - Color.red(middle)) * near).roundToInt()
            val green = Color.green(middle) + ((grey - Color.green(middle)) * near).roundToInt()
            val blue = Color.blue(middle) + ((grey - Color.blue(middle)) * near).roundToInt()
            paint.color = Color.rgb(red, green, blue)
            paint.alpha = if (isEnabled) 255 else 77
            paint.textSize = (23f - 2.5f * near) * density
            canvas.save()
            canvas.translate(anchor * density, centreY + (radius * sin(angle)).toFloat() * density)
            canvas.scale(1f, cos(angle).toFloat())
            canvas.drawText(text, 0f, -(paint.descent() + paint.ascent()) / 2, paint)
            canvas.restore()
        }
    }

    private fun settle(target: Int) {
        val last = (items.size - 1).coerceAtLeast(0)
        val end = if (wraps) target else target.coerceIn(0, last)
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
                    val landed = if (wraps) Math.floorMod(end, items.size.coerceAtLeast(1)) else end
                    position = landed.toFloat()
                    if (landed != index) {
                        index = landed
                        onChange?.invoke(landed)
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
                downY = event.y
                travelled = 0f
                tracker = VelocityTracker.obtain().also { it.addMovement(event) }
                parent?.requestDisallowInterceptTouchEvent(true)
            }
            MotionEvent.ACTION_MOVE -> {
                tracker?.addMovement(event)
                travelled += abs(event.y - lastY)
                position -= (event.y - lastY) / rowHeight
                if (!wraps) position = position.coerceIn(-0.4f, items.size - 0.6f)
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
                val slop = ViewConfiguration.get(context).scaledTouchSlop
                if (event.actionMasked == MotionEvent.ACTION_UP && travelled < slop) {
                    // A tap on a row brings that row to the middle, as UIKit's does.
                    // 點某一列會把那一列帶到中央，與 UIKit 相同。
                    val offset = ((downY - height / 2f) / density / radius).coerceIn(-0.98f, 0.98f)
                    settle((position + asin(offset.toDouble()) / step).roundToInt())
                } else {
                    // A fifth of a second of the release speed, in rows.
                    // 放開時速度的五分之一秒，以列計。
                    settle((position - velocity * 0.2f / rowHeight).roundToInt())
                }
            }
        }
        return true
    }
}
