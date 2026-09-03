package dev.swiftcrossui.androidbackend

import android.app.Activity
import android.util.AttributeSet
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup

class CustomContainer(val activity: Activity) : ViewGroup(activity) {
    init {
    // Android is the only one of these backends that clips a child to its
    // parent by default. `UIView.clipsToBounds` is false, an `NSView` does not
    // clip, and GTK draws outside an allocation; `ViewGroup.clipChildren` is
    // true. So a view the layout system deliberately moved outside its cell --
    // an offset, a rotation, a scale -- was drawn correctly and then cut at the
    // cell edge, on Android and nowhere else.
    //
    // Measured 2026-09-03 on P40: the offset tile translated to exactly the
    // right place and lost 106 pixels on its right and 53 at its bottom; the
    // rotated and sheared tiles both stopped at x 675, which is the right edge
    // of their pre-transform frames. P40's own header says the overflow and the
    // overlap are the correct behaviour.
    //
    // Nothing here relies on this clipping. `BackendFeatures.Clipping` is not
    // implemented on Android at all, and `CornerRadiusContainer` clips with
    // `canvas.clipPath` inside its own draw rather than through this flag.
    //
    // Android 是這些 backend 之中唯一「預設會把子元件裁切到父元件範圍內」的。
    // `UIView.clipsToBounds` 為 false，`NSView` 不裁切，GTK 會畫到 allocation 之外；而
    // `ViewGroup.clipChildren` 為 true。因此一個被版面系統刻意移到其格位之外的 view——offset、
    // 旋轉、縮放——會被正確地繪製，然後在格位邊緣被切掉；只在 Android 上如此，其他平台都不會。
    //
    // 2026-09-03 於 P40 上實測：offset 磚被平移到完全正確的位置，然後右側失去 106 像素、底部失去
    // 53 像素；旋轉與傾斜的磚都止於 x 675，那正是它們變換前方框的右緣。P40 自己的表頭寫明，溢出
    // 與重疊才是正確的行為。
    //
    // 此處沒有任何東西依賴這個裁切。`BackendFeatures.Clipping` 在 Android 上根本沒有實作，而
    // `CornerRadiusContainer` 是在它自己的 draw 之中以 `canvas.clipPath` 裁切的，不經由這個旗標。
        clipChildren = false
        clipToPadding = false
    }

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

    // Android orders siblings by Z first and by child index second. SwiftCrossUI
    // orders them by index alone: a ZStack's later child covers its earlier one,
    // and that is the whole of what a ZStack promises. When a native widget
    // carries a theme elevation, the two orderings disagree and Android's wins.
    //
    // Measured 2026-09-03 on P10, whose ZStack is `Button` then an opaque
    // `Color.orange`. The tree was built correctly -- Button at index 0, the
    // orange's container at index 1 -- and the button still drew on top, because
    // the platform button style gives it `elevation=5.25` (2dp at density 2.625)
    // against the orange's 0. On iOS and macOS the button is invisible, which is
    // what P10's own comment says it is for; on Android it was legible through
    // an opaque rectangle.
    //
    // Only when they disagree. A container whose Z values already rise with the
    // index is left alone, which is nearly all of them -- a button usually sits
    // alone in its wrapper, and its shadow is a real part of how Android looks.
    // The flattening is applied where a later sibling is being covered by an
    // earlier one, and there a shadow cast through the thing on top would be
    // wrong anyway.
    //
    // Android 先依 Z、再依子元件索引來排序同層元件。SwiftCrossUI 只依索引排序：ZStack 中較晚的
    // 子元件覆蓋較早的，而那就是 ZStack 所承諾的全部。當一個原生 widget 帶有來自主題的 elevation
    // 時，兩種排序就會衝突，而勝出的是 Android 的。
    //
    // 2026-09-03 於 P10 上實測，其 ZStack 為一個 `Button` 之後接一個不透明的 `Color.orange`。
    // 該樹是正確建構的——Button 在索引 0、橘色的容器在索引 1——而按鈕依然畫在上面，因為平台的按鈕
    // 樣式給了它 `elevation=5.25`（density 2.625 下的 2dp），而橘色是 0。在 iOS 與 macOS 上那顆
    // 按鈕是看不見的，那正是 P10 自己的註解所說的用途；在 Android 上它卻透過一個不透明矩形清晰可讀。
    //
    // 僅在兩者衝突時才處理。Z 值本來就隨索引遞增的容器完全不受影響，而那幾乎是全部——一顆按鈕通常
    // 獨自位於它自己的外層中，而它的陰影是 Android 外觀真實的一部分。此處的壓平只施加於「較晚的
    // 同層元件正被較早的蓋住」之處，而在那裡，一道穿過上方物件投下的陰影本來就是錯的。
    private fun enforceDeclarationOrder() {
        if (childCount < 2) {
            return
        }

        var highest = 0f
        var disagrees = false
        for (i in 0..<childCount) {
            val z = getChildAt(i).z
            if (z < highest) {
                disagrees = true
                break
            }
            if (z > highest) {
                highest = z
            }
        }

        if (!disagrees) {
            return
        }

        // The state-list animator first, and that ordering is not incidental.
        // Cancelling translationZ alone was measured to do nothing: the
        // animator owns that property on a platform button and puts its own
        // value back, so the tree still read `Button z=5.25` after a pass that
        // had just set it to zero. Clearing the animator, then the two
        // properties, is what holds.
        //
        // 先處理 state-list animator，而這個順序不是偶然的。實測顯示，只取消 translationZ 什麼也
        // 做不到：在平台按鈕上，那個屬性是由該 animator 所擁有的，它會把自己的值放回去，因此在一次
        // 剛把它設為零的處理之後，樹狀結構讀到的仍是 `Button z=5.25`。先清除 animator、再清除那兩個
        // 屬性，才站得住。
        for (i in 0..<childCount) {
            val child = getChildAt(i)
            child.stateListAnimator = null
            child.translationZ = 0f
            child.elevation = 0f
        }
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

    // Checked here rather than in onLayout, because at layout time the value
    // this has to correct does not exist yet. A platform button gets its
    // elevation from the state-list animator, which runs when the view's
    // drawable state is first set -- after layout, before the first draw. The
    // first version of this fix ran in onLayout, saw every child at z=0, found
    // nothing to correct and left the button on top; the tree dump afterwards
    // still read `Button z=5.25 tz=0.0`, which is what a check that ran too
    // early looks like.
    //
    // Converges in one extra frame: the correcting pass invalidates, the next
    // pass finds the orders agree and changes nothing.
    //
    // 在此處檢查而非在 onLayout 中，因為在版面計算的時點，這個機制所要修正的那個值根本還不存在。
    // 平台按鈕的 elevation 來自 state-list animator，而它是在該 view 的 drawable state 首次被設定時
    // 執行的——晚於版面、早於首次繪製。本修正的第一版是在 onLayout 中執行的，它看到的每個子元件都是
    // z=0，因而認定沒有東西需要修正，於是按鈕依然在上面；事後的樹狀 dump 仍讀作
    // `Button z=5.25 tz=0.0`，而那正是「一個執行得太早的檢查」的模樣。
    //
    // 一個額外的影格即收斂：進行修正的那一輪會觸發 invalidate，而下一輪會發現兩種排序已一致，
    // 因此不做任何改變。
    override protected fun dispatchDraw(canvas: android.graphics.Canvas) {
        enforceDeclarationOrder()
        super.dispatchDraw(canvas)
    }
}
