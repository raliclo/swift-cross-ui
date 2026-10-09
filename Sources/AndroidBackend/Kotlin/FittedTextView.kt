package dev.swiftcrossui.androidbackend

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
}
