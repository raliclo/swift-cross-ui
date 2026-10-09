package dev.swiftcrossui.androidbackend

import android.R
import android.app.Activity
import android.graphics.Canvas
import android.graphics.ColorFilter
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.Drawable
import android.util.TypedValue
import android.view.View
import android.view.ViewGroup
import android.widget.AdapterView
import android.widget.ArrayAdapter
import android.widget.Spinner
import android.widget.TextView

// `.menu`, the default picker style, drawn as UIKitBackend's UIButtonPicker is:
// the selected option in the label colour followed by an up/down chevron, no
// background and no minimum size, opening the option list on a tap. The
// framework Spinner's underlined box with its 48 dp minimum height made P17's
// picker 90 x 48 where iOS's is about 30 x 22 (2026-10-10).
//
// `.menu`,即預設的 picker 樣式，畫成 UIKitBackend 的 UIButtonPicker 那樣：以標籤色顯示選取的選項，後面接一個
// 上下雙箭頭，沒有背景也沒有最小尺寸，點一下打開選項清單。框架 Spinner 帶底線的方框與 48 dp 最小高度，讓 P17 的
// picker 量出 90 x 48,而 iOS 的約 30 x 22(2026-10-10)。
class CustomSpinner(activity: Activity) : Spinner(activity, Spinner.MODE_DROPDOWN) {
    // I'm not 100% sure why, but without this (and the check in onItemSelected),
    // update() was being spammed, making it impossible for the user to select anything.
    private var oldSelectedPosition = AdapterView.INVALID_POSITION

    private var labelColor = 0
    private var labelSize = 17f
    private var labelLineHeight = 0
    private var labelTypeface: Typeface = Typeface.DEFAULT

    init {
        background = null
        setPadding(0, 0, 0, 0)
        minimumHeight = 0
        minimumWidth = 0
    }

    fun update(
        onChange: SwiftAction,
        options: Array<String>,
        isEnabled: Boolean,
        color: Int,
        fontSize: Float,
        lineHeight: Int,
        typeface: Typeface,
    ) {
        labelColor = color
        labelSize = fontSize
        labelLineHeight = lineHeight
        labelTypeface = typeface
        setAdapter(LabelAdapter(options))

        setOnItemSelectedListener(
            object : AdapterView.OnItemSelectedListener {
                override fun onItemSelected(
                    parent: AdapterView<*>,
                    view: View?,
                    position: Int,
                    id: Long,
                ) {
                    if (position != oldSelectedPosition) {
                        onChange.call()
                    }
                    oldSelectedPosition = position
                }

                override fun onNothingSelected(parent: AdapterView<*>) {
                    onItemSelected(
                        parent,
                        null,
                        AdapterView.INVALID_POSITION,
                        AdapterView.INVALID_ROW_ID,
                    )
                }
            }
        )

        setEnabled(isEnabled)
    }

    fun selectOption(index: Int) {
        setSelection(index)
        oldSelectedPosition = index
    }

    // The closed picker's face: the label and the chevrons. The open list keeps
    // the framework's rows. 收合時的外觀：標籤與箭頭。展開的清單保留框架的列。
    private inner class LabelAdapter(options: Array<String>) :
        ArrayAdapter<String>(context, R.layout.simple_list_item_1, options) {
        override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
            val label = (convertView as? TextView) ?: TextView(context)
            label.text = getItem(position)
            label.setPadding(0, 0, 0, 0)
            label.includeFontPadding = false
            label.setTextColor(labelColor)
            label.setTextSize(TypedValue.COMPLEX_UNIT_SP, labelSize)
            if (labelLineHeight > 0) label.lineHeight = labelLineHeight
            label.typeface = labelTypeface
            label.maxLines = 1
            val density = context.resources.displayMetrics.density
            label.compoundDrawablePadding = (2 * density).toInt()
            label.setCompoundDrawablesRelative(null, null, Chevrons(labelColor, labelSize * density), null)
            return label
        }
    }

    // SF Symbols' chevron.up.chevron.down at the label's size: two chevrons
    // stacked, stroked in the label colour. The box is the image UIButton lays
    // out, wider and taller than the strokes: iOS's picker with "S" selected
    // measures 27 x 22 (P17, --debug), and this box makes the Android one the
    // same; drawn only to the glyph it was 21 x 20, so a readout laid over it
    // truncated to "p..." where iOS shows "pi...".
    // SF Symbols 的 chevron.up.chevron.down,大小隨標籤：上下疊放的兩個箭頭，以標籤色描邊。外框是 UIButton
    // 排版用的圖片框，比線條寬也比線條高:iOS 選了 "S" 的 picker 量出 27 x 22(P17,--debug),這個外框讓
    // Android 的一樣大;只框到線條時是 21 x 20,疊在上面的讀數被截成 "p...",而 iOS 顯示 "pi..."。
    private class Chevrons(color: Int, private val textSize: Float) : Drawable() {
        private val width = (textSize * 0.86f).toInt()
        private val height = (textSize * 1.28f).toInt()
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
            style = Paint.Style.STROKE
            strokeWidth = textSize * 0.09f
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }

        init {
            setBounds(0, 0, width, height)
        }

        override fun draw(canvas: Canvas) {
            val b = bounds
            val glyphWidth = textSize * 0.55f
            val glyphHeight = textSize * 0.8f
            val left = b.exactCenterX() - glyphWidth / 2
            val right = b.exactCenterX() + glyphWidth / 2
            val mid = b.exactCenterX()
            val top = b.exactCenterY() - glyphHeight / 2
            val bottom = b.exactCenterY() + glyphHeight / 2
            val arm = glyphWidth * 0.5f
            val path = Path()
            path.moveTo(left, top + arm)
            path.lineTo(mid, top)
            path.lineTo(right, top + arm)
            path.moveTo(left, bottom - arm)
            path.lineTo(mid, bottom)
            path.lineTo(right, bottom - arm)
            canvas.drawPath(path, paint)
        }

        override fun getIntrinsicWidth() = width

        override fun getIntrinsicHeight() = height

        override fun setAlpha(alpha: Int) {
            paint.alpha = alpha
        }

        override fun setColorFilter(colorFilter: ColorFilter?) {
            paint.colorFilter = colorFilter
        }

        @Deprecated("Deprecated in Java")
        override fun getOpacity() = PixelFormat.TRANSLUCENT
    }
}
