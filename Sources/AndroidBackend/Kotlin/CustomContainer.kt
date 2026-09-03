package dev.swiftcrossui.androidbackend

import android.app.Activity
import android.util.AttributeSet
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup

class CustomContainer(val activity: Activity) : ViewGroup(activity) {
    class LayoutParams(width: Int, height: Int, var x: Int, var y: Int) :
        ViewGroup.LayoutParams(width, height) {}

    override fun checkLayoutParams(layoutParams: ViewGroup.LayoutParams?): Boolean {
        return layoutParams is LayoutParams
    }

    override fun generateDefaultLayoutParams(): ViewGroup.LayoutParams? {
        return LayoutParams(0, 0, 0, 0)
    }

    override fun generateLayoutParams(attrs: AttributeSet?): ViewGroup.LayoutParams? {
        return LayoutParams(0, 0, 0, 0)
    }

    override fun generateLayoutParams(
        layoutParams: ViewGroup.LayoutParams?
    ): ViewGroup.LayoutParams {
        return LayoutParams(layoutParams!!.width, layoutParams!!.height, 0, 0)
    }

    // MATCH_PARENT is -1 and WRAP_CONTENT is -2. They are sentinels in
    // layoutParams, not dimensions, and setMeasuredDimension takes a dimension.
    // Passing one straight through gives the view a negative size: measured on
    // the emulator, the root container reported `self=-1x-1` with a child of
    // 1078x2207, so the children were alive and correctly sized inside a parent
    // that had no size, and the window drew nothing.
    //
    // That is the blanking. Pressing anything that made the content need more
    // width emptied the page -- nine presses of P12's "Increment counter" left
    // it intact and the tenth, where the number needs a second digit, took the
    // non-white pixel count from 378953 to 0 -- because widening is what makes
    // SwiftCrossUI re-assign the root container MATCH_PARENT and re-measure.
    //
    // Resolved against the spec instead. A negative request means "as big as
    // the parent offered", which is what both sentinels mean here: this
    // container's children are given explicit sizes by the layout system, so
    // WRAP_CONTENT never has to mean "as big as my contents".
    //
    // MATCH_PARENT 是 -1，WRAP_CONTENT 是 -2。它們在 layoutParams 中是哨兵值，不是尺寸，而
    // setMeasuredDimension 接受的是尺寸。把哨兵值直接傳過去，會讓該 view 得到一個負的尺寸：
    // 於 emulator 上實測，根容器回報 `self=-1x-1`，而它的子元件是 1078x2207——也就是子元件活著
    // 且尺寸正確，卻位在一個沒有尺寸的父容器裡，於是整個視窗什麼都不畫。
    //
    // 那就是清空的成因。按下任何「讓內容需要更多寬度」的東西都會清空頁面——按 P12 的
    // 「Increment counter」九次頁面完好，第十次（數字需要第二位數時）把非白像素數從 378953 變成 0
    // ——因為「變寬」正是讓 SwiftCrossUI 重新把根容器指派為 MATCH_PARENT 並重新量測的原因。
    //
    // 改為依 spec 解析。負的請求值意味著「與父容器所提供的一樣大」，而在此處兩個哨兵值都是這個
    // 意思：本容器的子元件是由版面系統指派明確尺寸的，因此 WRAP_CONTENT 永遠不必表示「與我的內容
    // 一樣大」。
    private fun resolveDimension(requested: Int, spec: Int): Int {
        return if (requested >= 0) requested else View.MeasureSpec.getSize(spec)
    }

    override protected fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        setMeasuredDimension(
            resolveDimension(layoutParams.width, widthMeasureSpec),
            resolveDimension(layoutParams.height, heightMeasureSpec),
        )


        for (i in 0..<childCount) {
            val child = getChildAt(i)
            // If you're debugging this implementation and see a child with
            // strange layoutParams dimensions (such as 1073741822, or <= 0),
            // then it's likely that there is a widget that SwiftCrossUI
            // mistakenly hasn't assigned an explicit size via
            // AndroidBackend.setSize(of:to:). This often leads to views
            // within such a view not being visible at all.
            val layoutParams = child.layoutParams
            val widthSpec =
                View.MeasureSpec.makeMeasureSpec(layoutParams.width, View.MeasureSpec.EXACTLY)
            val heightSpec =
                View.MeasureSpec.makeMeasureSpec(layoutParams.height, View.MeasureSpec.EXACTLY)
            child.measure(widthSpec, heightSpec)
        }
    }

    // Refusing, not consuming. Returning false is what lets the ViewGroup above
    // carry on to the child underneath, which is the whole of what
    // `allowsHitTesting(false)` promises; see HitTesting.kt. Checked here rather
    // than on every descendant because this is the one call the entire subtree
    // has to pass through.
    //
    // 拒收，而非吃掉。回傳 false 正是讓上層 ViewGroup 繼續往下一個子元件走的原因，而那就是
    // `allowsHitTesting(false)` 所承諾的全部；見 HitTesting.kt。在此處檢查而非標記每一個後代，
    // 是因為這是整棵子樹都必須經過的那一個呼叫。
    override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
        if (HitTesting.isDisabled(this)) {
            return false
        }
        return super.dispatchTouchEvent(ev)
    }

    override protected fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        for (i in 0..<childCount) {
            val child = getChildAt(i)
            val layoutParams = child.layoutParams as LayoutParams
            child.layout(
                layoutParams.x,
                layoutParams.y,
                layoutParams.x + layoutParams.width,
                layoutParams.y + layoutParams.height,
            )
        }
    }
}
