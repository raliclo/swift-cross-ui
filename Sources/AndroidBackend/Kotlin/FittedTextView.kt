package dev.swiftcrossui.androidbackend

import android.os.Build
import android.app.Activity
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
        // Every line the same height whatever script it holds, as the size is
        // measured (lines x line height) and as UIKit lays them out. A line of
        // CJK text otherwise takes its fallback font's taller metrics: P37's
        // three Chinese lines pushed the last one half out of the view
        // (2026-10-10).
        // 不論是哪種文字，每一行都一樣高，與尺寸的量法(行數 x 行高)以及 UIKit 的排法相同。否則一行中日韓文字會採用
        // 後備字型較高的度量:P37 的三行中文把最後一行推出 view 一半(2026-10-10)。
        if (Build.VERSION.SDK_INT >= 28) {
            isFallbackLineSpacing = false
        }
    }

    // Every line is one line height, as `size(of:whenDisplayedIn:)` measures
    // it, so the lines that fit are the height divided by the line height.
    // maxLines is only assigned when it changes, because assigning it requests
    // another layout.
    // 每一行都是一個行高，與 `size(of:whenDisplayedIn:)` 的量法相同，所以放得下的行數就是高度除以行高。maxLines
    // 只在改變時才指派，因為指派它會要求再排一次版。
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        if (MeasureSpec.getMode(heightMeasureSpec) != MeasureSpec.UNSPECIFIED && lineHeight > 0) {
            val available = MeasureSpec.getSize(heightMeasureSpec) - compoundPaddingTop - compoundPaddingBottom
            // Two pixels of slack: the height arrives rounded to whole dp.
            // 兩個像素的餘裕：高度是以整數 dp 取整後送來的。
            val fitting = maxOf(1, (available + 2) / lineHeight)
            if (fitting != maxLines) {
                maxLines = fitting
            }
        }
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
    }

    // The widest wrapped line with the padding, in pixels; 0 with no layout.
    // A wrapped TextView measures as wide as it was offered, where UIKit's
    // boundingRect gives the widest line: `size(of:whenDisplayedIn:)` asks here.
    // 換行後最寬的一行加上 padding,單位像素；沒有 layout 時為 0。換行的 TextView 量出來與給它的寬度一樣寬,
    // 而 UIKit 的 boundingRect 給的是最寬的一行:`size(of:whenDisplayedIn:)` 來這裡問。
    fun widestLineWidth(): Int {
        val current = layout ?: return 0
        var widest = 0f
        for (line in 0 until current.lineCount) {
            widest = maxOf(widest, current.getLineMax(line))
        }
        return Math.ceil(widest.toDouble()).toInt() + compoundPaddingLeft + compoundPaddingRight
    }
}
