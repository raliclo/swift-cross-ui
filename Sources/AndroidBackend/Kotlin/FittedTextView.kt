package dev.swiftcrossui.androidbackend

import android.app.Activity
import android.text.StaticLayout
import android.text.TextUtils
import android.widget.TextView

// A Text that shows only the lines its frame has room for and ends the last
// one with an ellipsis, as UILabel does. SwiftCrossUI gives a Text a height
// from `size(of:whenDisplayedIn:)`, which -- like UIKit's boundingRect with
// truncatesLastVisibleLine -- counts only the whole lines that fit the
// proposal. A plain TextView laid out in that frame drew every line anyway and
// clipped the bottom ones mid-glyph (P17's "subject" and "picker" readouts,
// 2026-10-10). Here the line count follows the height the view is laid out at.
//
// 只顯示外框放得下的行數、最後一行以刪節號結尾的 Text,與 UILabel 相同。SwiftCrossUI 依
// `size(of:whenDisplayedIn:)` 給 Text 高度，而它——與 UIKit 帶 truncatesLastVisibleLine 的 boundingRect 一樣——
// 只計算提議尺寸裡放得下的整行。單純的 TextView 排在那個外框裡仍會畫出每一行，把下面幾行從字形中間裁掉
// (P17 的 "subject" 與 "picker" 讀數,2026-10-10)。此處行數跟著 view 實際排版的高度走。
class FittedTextView(activity: Activity) : TextView(activity) {
    init {
        ellipsize = TextUtils.TruncateAt.END
    }

    // Counted on a separate StaticLayout of the whole text, so the answer does
    // not depend on the maxLines already set, and from each line's real bottom:
    // the last line carries no line spacing, so two lines are shorter than two
    // getLineHeight()s, and dividing by it dropped a line that fitted (P17's
    // "picker: 90 x" lost its "48"). maxLines is only assigned when it changes,
    // because assigning it requests another layout.
    // 在另一個涵蓋整段文字的 StaticLayout 上計算，結果因此不受目前已設定的 maxLines 影響;並以每一行實際的底部
    // 計算：最後一行不帶行距，所以兩行比兩個 getLineHeight() 矮，用它去除就少算了一行放得下的行(P17 的
    // "picker: 90 x" 少了 "48")。maxLines 只在改變時才指派，因為指派它會要求再排一次版。
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val heightMode = MeasureSpec.getMode(heightMeasureSpec)
        val widthMode = MeasureSpec.getMode(widthMeasureSpec)
        if (heightMode != MeasureSpec.UNSPECIFIED && widthMode != MeasureSpec.UNSPECIFIED) {
            val width = MeasureSpec.getSize(widthMeasureSpec) - compoundPaddingLeft - compoundPaddingRight
            val available = MeasureSpec.getSize(heightMeasureSpec) - compoundPaddingTop - compoundPaddingBottom
            val content = text ?: ""
            var fitting = Int.MAX_VALUE
            if (width > 0 && content.isNotEmpty()) {
                val full = StaticLayout.Builder.obtain(content, 0, content.length, paint, width)
                    .setLineSpacing(lineSpacingExtra, lineSpacingMultiplier)
                    .setIncludePad(includeFontPadding)
                    .setBreakStrategy(breakStrategy)
                    .setHyphenationFrequency(hyphenationFrequency)
                    .build()
                if (full.height > available + 2) {
                    val descent = paint.fontMetricsInt.descent
                    var count = 1
                    while (count < full.lineCount && full.getLineBaseline(count) + descent <= available + 2) {
                        count += 1
                    }
                    fitting = count
                }
            }
            if (fitting != maxLines) {
                maxLines = fitting
            }
        }
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
    }
}
