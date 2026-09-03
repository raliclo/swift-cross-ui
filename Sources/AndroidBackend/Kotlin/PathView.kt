package dev.swiftcrossui.androidbackend

import android.app.Activity
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.view.View

/**
 * A path, and optionally a gradient clipped to it.
 *
 * The gradient is described in unit space -- 0 to 1 across the path's own
 * bounding box -- and resolved to pixels here, at draw time, because that is the
 * first moment the box is known. The alternative is Swift computing pixels from
 * a box it would have to ask for a frame earlier, and being wrong on the frame
 * the shape resizes.
 *
 * **Android's `RadialGradient` has no start radius**, and
 * `radialGradient(startRadius:endRadius:)` has one. That is not a reason to
 * degrade: the shader takes explicit stop positions, so a start radius is
 * expressible by remapping them. A stop at location *t* wants to sit at radius
 * `r0 + t*(r1 - r0)`, and the shader's own parameter is a fraction of `r1`, so
 * the position it needs is `(r0 + t*(r1 - r0)) / r1`. CLAMP then paints the
 * inner disc in the first colour, which is what a start radius means.
 *
 * 一條路徑，以及（可選的）一個被裁切到該路徑內的漸層。
 *
 * 漸層是以單位空間描述的——橫跨該路徑自身邊界框的 0 到 1——並在此處、於繪製時解析為像素，因為那是
 * 「邊界框已知」的第一個時刻。另一種做法是由 Swift 從一個必須提早一個影格去索取的邊界框計算像素，
 * 而那會在形狀改變尺寸的那一個影格上出錯。
 *
 * **Android 的 `RadialGradient` 沒有起始半徑**，而 `radialGradient(startRadius:endRadius:)` 有。
 * 那不構成降級的理由：該 shader 接受明確的 stop 位置，因此起始半徑可以用重新映射來表達。位於位置
 * *t* 的 stop 應當落在半徑 `r0 + t*(r1 - r0)` 處，而 shader 自身的參數是 `r1` 的分數，因此它所需要
 * 的位置是 `(r0 + t*(r1 - r0)) / r1`。CLAMP 接著會把內圈以第一個顏色填滿，而那正是起始半徑的意思。
 */
class PathView(activity: Activity) : View(activity) {
    private class GradientSpec {
        var isRadial = false
        var ax = 0f
        var ay = 0f
        var bx = 0f
        var by = 0f
        var startRadius = 0f
        var endRadius = 0f
        val colors = mutableListOf<Int>()
        val positions = mutableListOf<Float>()
    }

    private lateinit var path: Path
    private lateinit var fillPaint: Paint
    private lateinit var strokePaint: Paint

    private var fillGradient: GradientSpec? = null
    private var strokeGradient: GradientSpec? = null

    fun set(path: Path, fillPaint: Paint, strokePaint: Paint) {
        this.path = path
        this.fillPaint = fillPaint
        this.strokePaint = strokePaint
    }

    fun clearGradient(stroke: Boolean) {
        if (stroke) strokeGradient = null else fillGradient = null
        invalidate()
    }

    fun setGradient(
        stroke: Boolean,
        radial: Boolean,
        ax: Float,
        ay: Float,
        bx: Float,
        by: Float,
        startRadius: Float,
        endRadius: Float,
    ) {
        val spec = GradientSpec()
        spec.isRadial = radial
        spec.ax = ax
        spec.ay = ay
        spec.bx = bx
        spec.by = by
        spec.startRadius = startRadius
        spec.endRadius = endRadius
        if (stroke) strokeGradient = spec else fillGradient = spec
        invalidate()
    }

    fun addGradientStop(stroke: Boolean, color: Int, position: Float) {
        val spec = (if (stroke) strokeGradient else fillGradient) ?: return
        spec.colors.add(color)
        spec.positions.add(position)
        invalidate()
    }

    private fun shaderFor(spec: GradientSpec?): Shader? {
        if (spec == null || spec.colors.isEmpty()) {
            return null
        }

        val bounds = RectF()
        path.computeBounds(bounds, true)
        if (bounds.width() <= 0f || bounds.height() <= 0f) {
            // A zero-extent path leaves a gradient nowhere to run. The flat
            // colour already on the Paint keeps the shape visible, which is
            // what GtkBackend does with the same case.
            // 範圍為零的路徑會讓漸層無處延展。Paint 上既有的平面色可讓形狀保持可見，而 GtkBackend
            // 對同一個情況的處理方式也是如此。
            return null
        }

        // Android needs at least two. One stop is a solid colour and the Paint
        // already carries it, but returning null there would drop a legitimate
        // single-stop gradient's colour, so it is doubled instead.
        // Android 至少需要兩個。單一 stop 就是一個純色，而 Paint 本來就帶著它；但在該情況回傳 null
        // 會丟掉一個合法的單 stop 漸層的顏色，因此改為將它複製一份。
        val colors =
            if (spec.colors.size == 1) intArrayOf(spec.colors[0], spec.colors[0])
            else spec.colors.toIntArray()
        val positions =
            if (spec.positions.size == 1) floatArrayOf(0f, 1f)
            else spec.positions.toFloatArray()

        if (!spec.isRadial) {
            return LinearGradient(
                bounds.left + spec.ax * bounds.width(),
                bounds.top + spec.ay * bounds.height(),
                bounds.left + spec.bx * bounds.width(),
                bounds.top + spec.by * bounds.height(),
                colors,
                positions,
                Shader.TileMode.CLAMP,
            )
        }

        // Scaled by the shorter side, so a circle stays a circle in a path that
        // is not square. Same rule as GtkBackend and the two Apple backends.
        // 以較短的一邊縮放，使圓形在非正方形的路徑中仍是圓形。與 GtkBackend 及兩個 Apple backend
        // 的規則相同。
        val scale = Math.min(bounds.width(), bounds.height())
        val outer = spec.endRadius * scale
        if (outer <= 0f) {
            return null
        }
        val inner = spec.startRadius * scale
        val remapped = FloatArray(positions.size) {
            ((inner + positions[it] * (outer - inner)) / outer).coerceIn(0f, 1f)
        }

        return RadialGradient(
            bounds.left + spec.ax * bounds.width(),
            bounds.top + spec.ay * bounds.height(),
            outer,
            colors,
            remapped,
            Shader.TileMode.CLAMP,
        )
    }

    override fun onDraw(canvas: Canvas) {
        // Assigned on every draw rather than cached, because the shader is
        // built from the path's bounds and those change with the view.
        // 每次繪製都重新指派而非快取，因為該 shader 是由路徑的邊界框建構的，而邊界框會隨 view 改變。
        fillPaint.shader = shaderFor(fillGradient)
        canvas.drawPath(path, fillPaint)

        strokePaint.shader = shaderFor(strokeGradient)
        canvas.drawPath(path, strokePaint)
    }
}
