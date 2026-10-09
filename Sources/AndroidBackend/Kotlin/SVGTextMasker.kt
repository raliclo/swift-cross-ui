package dev.swiftcrossui.androidbackend

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Typeface
import java.nio.ByteBuffer

/// SVG `<text>` through Android's own text engine: one run, as coverage, in a
/// canvas-sized mask (see SwiftCrossUI's SVGTextMaskRequest). Android substitutes
/// system fonts for characters the chosen typeface lacks, so Chinese still draws.
///
/// 經由 Android 自己的文字引擎繪製 SVG `<text>`:一段文字，以覆蓋率的形式，畫進與畫布同大的遮罩(見
/// SwiftCrossUI 的 SVGTextMaskRequest)。Android 會為所選字體缺少的字元替換系統字型，因此中文仍會畫出來。
class SVGTextMasker {
    /// `anchor`: 0 start, 1 middle, 2 end. `strokeWidth` < 0 fills the glyphs.
    /// Returns `width * height` coverage bytes, top row first.
    /// `anchor`:0 start、1 middle、2 end。`strokeWidth` < 0 表示填滿字形。回傳 `width * height` 個覆蓋率
    /// 位元組，最上面一列在前。
    fun mask(
        text: String, families: String, size: Double, bold: Boolean, italic: Boolean, anchor: Int,
        a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double,
        width: Int, height: Int, strokeWidth: Double,
    ): ByteArray {
        val out = ByteArray(width * height)
        if (width <= 0 || height <= 0 || text.isEmpty() || size <= 0) return out
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ALPHA_8)
        val canvas = Canvas(bitmap)
        val matrix = Matrix()
        matrix.setValues(
            floatArrayOf(
                a.toFloat(), c.toFloat(), tx.toFloat(),
                b.toFloat(), d.toFloat(), ty.toFloat(),
                0f, 0f, 1f,
            )
        )
        canvas.concat(matrix)
        val style = when {
            bold && italic -> Typeface.BOLD_ITALIC
            bold -> Typeface.BOLD
            italic -> Typeface.ITALIC
            else -> Typeface.NORMAL
        }
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface = typeface(families, style)
            textSize = size.toFloat()
            textAlign = when (anchor) {
                1 -> Paint.Align.CENTER
                2 -> Paint.Align.RIGHT
                else -> Paint.Align.LEFT
            }
            color = Color.WHITE
            if (strokeWidth >= 0) {
                this.style = Paint.Style.STROKE
                this.strokeWidth = strokeWidth.toFloat()
            } else {
                this.style = Paint.Style.FILL
            }
        }
        // The baseline runs along y = 0 in text space, the anchor at x = 0.
        // 文字空間中基線沿 y = 0、錨點在 x = 0。
        canvas.drawText(text, 0f, 0f, paint)
        // ALPHA_8 rows may be padded; copy row by row.
        // ALPHA_8 的列可能有填充位元組；逐列複製。
        val rowBytes = bitmap.rowBytes
        val buffer = ByteBuffer.allocate(rowBytes * height)
        bitmap.copyPixelsToBuffer(buffer)
        val source = buffer.array()
        for (row in 0 until height) {
            System.arraycopy(source, row * rowBytes, out, row * width, width)
        }
        bitmap.recycle()
        return out
    }

    /// The first family in the list: CSS generics mapped to Android's, any other
    /// name passed to Typeface.create, which falls back to the default face.
    /// 清單中的第一個家族：CSS 通用名稱對應到 Android 的，其他名稱交給 Typeface.create(找不到時退回預設字體)。
    private fun typeface(families: String, style: Int): Typeface {
        val name = families.split(',').map { it.trim() }.firstOrNull { it.isNotEmpty() }
        val generic = when (name?.lowercase()) {
            null -> Typeface.DEFAULT
            "serif" -> Typeface.SERIF
            "sans-serif", "system-ui" -> Typeface.SANS_SERIF
            "monospace" -> Typeface.MONOSPACE
            else -> null
        }
        return if (generic != null) Typeface.create(generic, style) else Typeface.create(name, style)
    }
}
