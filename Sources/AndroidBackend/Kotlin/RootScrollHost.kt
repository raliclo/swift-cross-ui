package dev.swiftcrossui.androidbackend

import android.app.Activity
import android.content.Context
import android.graphics.Rect
import android.util.Log
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.ScrollView

/**
 * The two ways to look at content that does not fit the phone, and the control
 * that switches between them.
 *
 * This is UIKitBackend's `RootScrollHost` on Android. It was missing here, and
 * the absence did not look like an absence: the previous version wrapped the
 * content in a `HorizontalScrollView` around a `ScrollView` and added it with
 * `MATCH_PARENT` in both axes, so the content was pinned to exactly the
 * viewport and there was never anything to scroll. Both scroll views reported
 * `scrollable=false` on every app measured -- P35, P39, P41, P43 -- and a
 * 900-pixel swipe on P35 moved zero pixels. A scroll view that cannot scroll is
 * indistinguishable from no scroll view at all, which is why this went
 * unnoticed for three days.
 *
 * **actualView** lays the content out at its natural size and lets you reach the
 * overflow by scrolling. **rwdView** scales it down until the width fits. The
 * names are UIKitBackend's, deliberately: the same control on two platforms
 * should not need two vocabularies.
 *
 * **rwdView is a scale, not a re-layout.** A real responsive layout would
 * propose a narrower width and let every container lay itself out again; that
 * belongs to the shared layout system and would touch all five backends. This
 * applies a transform to a finished layout, and the button says `rwdView`
 * rather than `responsive` for the same reason.
 *
 * 兩種觀看「塞不進手機的內容」的方式，以及在兩者之間切換的控制項。
 *
 * 這是 UIKitBackend 的 `RootScrollHost` 在 Android 上的對應物。此處原本沒有它，而那個缺席看起來
 * 並不像缺席：先前的版本把內容包進「`HorizontalScrollView` 包 `ScrollView`」，並以兩軸皆
 * `MATCH_PARENT` 加入，於是內容被釘死在視口大小上，永遠沒有任何東西可捲。所量測的每一支 app
 * ——P35、P39、P41、P43——兩層捲動視圖都回報 `scrollable=false`，而在 P35 上滑動 900 像素，畫面
 * 一個像素也沒有改變。一個捲不動的捲動視圖，與根本沒有捲動視圖是分辨不出來的，這正是它被忽略了
 * 三天的原因。
 *
 * **actualView** 讓內容以自然尺寸排版，並以捲動觸及溢出的部分。**rwdView** 則將其縮小直到寬度
 * 塞得下。名稱刻意沿用 UIKitBackend 的：同一個控制項在兩個平台上不應該需要兩套詞彙。
 *
 * **rwdView 是縮放，不是重新排版。** 真正的響應式版面會重新提出一個較窄的寬度、讓每個容器重新
 * 排版，那屬於共用版面系統的工作，會同時影響五個 backend。此處是對「已完成的版面」施加變換——
 * 這也是該按鈕標示為 `rwdView` 而非 `responsive` 的理由。
 */
class RootScrollHost(context: Context) : FrameLayout(context) {
    companion object {
        const val MODE_ACTUAL_VIEW = 0
        const val MODE_RWD_VIEW = 1

        fun titleFor(mode: Int): String =
            if (mode == MODE_RWD_VIEW) "rwdView" else "actualView"

        /**
         * The full bounding box of a view and its descendants, negative
         * coordinates included.
         *
         * The negative half is the point. `CustomContainer.onLayout` places
         * each child at the `x` and `y` SwiftCrossUI assigned it, and a view
         * wider than its container is centred, so half of the overflow is at
         * negative x. A version that took the largest `x + width` would report
         * the container's own width and find nothing to scroll to -- which is
         * exactly what UIKitBackend measured on P10 before its own version was
         * corrected.
         *
         * `x` and `y` rather than `left` and `top`, because
         * `AndroidBackend+GeometricEffects` moves views with `translationX` and
         * `translationY` and only `x`/`y` include that.
         *
         * 一個 view 及其所有後代的完整外接矩形，包含負座標。
         *
         * 負的那一半正是重點。`CustomContainer.onLayout` 會把每個子元件放在 SwiftCrossUI 指派給它的
         * `x` 與 `y` 上，而比容器寬的 view 是置中的，因此有一半的溢出位於負 x。若某個版本取的是最大的
         * `x + width`，它回報的就會是容器自身的寬度，並且找不到任何可捲之處——那正是 UIKitBackend 在
         * 修正它自己的版本之前，於 P10 上量到的結果。
         *
         * 使用 `x`/`y` 而非 `left`/`top`，因為 `AndroidBackend+GeometricEffects` 是以
         * `translationX` 與 `translationY` 移動 view 的，而只有 `x`/`y` 會計入那個位移。
         */
        fun contentBounds(view: View, into: Rect) {
            into.set(0, 0, view.width, view.height)
            if (view !is ViewGroup) return
            val child = Rect()
            for (i in 0..<view.childCount) {
                val subview = view.getChildAt(i)
                if (subview.visibility == View.GONE) continue
                contentBounds(subview, child)
                child.offset(subview.x.toInt(), subview.y.toInt())
                into.union(child)
            }
        }
    }

    private val stage = Stage(context)
    private val vertical = ScrollView(context)
    private val horizontal = HorizontalScrollView(context)
    private var button: ViewModeButton? = null

    init {
        // `fillViewport` on both, or content smaller than the screen is laid
        // out at its own size and floats at the top left instead of filling the
        // window, which would change every existing Android screenshot for the
        // apps that do fit.
        //
        // The layout params are the part the previous version had wrong.
        // `WRAP_CONTENT` on the scrolling axis is what allows a child to be
        // larger than its scroll view; `MATCH_PARENT` forbids exactly the case
        // a scroll view exists for. `fillViewport` already covers "smaller than
        // the viewport", so nothing is lost by wrapping.
        //
        // 兩者都設定 `fillViewport`，否則比螢幕小的內容會以它自己的尺寸排版並浮在左上角，而不是
        // 填滿視窗；那會改變所有「本來就塞得下」的 app 的既有截圖。
        //
        // layout params 正是先前版本弄錯的地方。在捲動軸上使用 `WRAP_CONTENT`，才允許子元件大於它的
        // 捲動視圖；`MATCH_PARENT` 恰恰禁止了「捲動視圖之所以存在」的那個情況。而 `fillViewport`
        // 已經涵蓋了「比視口小」的情形，因此改用 wrap 不會失去任何東西。
        horizontal.isFillViewport = true
        vertical.isFillViewport = true
        vertical.addView(
            stage,
            ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ),
        )
        horizontal.addView(
            vertical,
            ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
        addView(
            horizontal,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT),
        )
    }

    private var positioned = false

    fun host(view: View) {
        stage.host(view)
        positioned = false
    }

    // Scrolled to the content's own origin once, after the first layout.
    //
    // The shift `Stage` applies makes the leftmost pixel reachable, and that is
    // the whole reason it exists; it also means scroll position zero shows the
    // empty margin to the left of the content rather than the content. On P3
    // that put the "Small" button at 1140..1371 on a 1080-wide screen, and
    // every action file measured before this existed -- 46 of them, with
    // coordinates like P3's `click 328,399` carrying a "VERIFIED 2026-09-03"
    // note -- suddenly pressed nothing. Fifteen apps reported an action file
    // that replayed and changed no pixel.
    //
    // Re-measuring 46 files was the alternative. This is better because the
    // default view is the one the layout describes and the overflow stays
    // reachable in both directions: scroll left for what is left of the origin,
    // right for what is past the viewport.
    //
    // Once, not on every layout, or a scroll the user makes would be undone on
    // the next pass.
    //
    // 在第一次版面計算之後,捲到內容自身的原點一次。
    //
    // `Stage` 所施加的位移讓最左邊的像素得以觸及,而那正是它存在的全部理由;但它同時也意味著
    // 「捲動位置為零」顯示的是內容左側的空白邊界,而不是內容本身。在 P3 上,那把 "Small" 按鈕推到了
    // 一個 1080 寬的螢幕上的 1140..1371;而所有在此機制存在之前量測的動作檔——共 46 份,座標如 P3 的
    // `click 328,399`,並帶有「VERIFIED 2026-09-03」的備註——突然全都按不到任何東西。有十五支 app
    // 回報「動作檔重放了,而且沒有改變任何一個像素」。
    //
    // 另一個選項是重新量測那 46 份檔案。此做法更好,因為預設畫面就是版面所描述的那一個,而溢出在兩個
    // 方向上都仍可觸及:向左捲可看原點左側的部分,向右捲可看超出視口的部分。
    //
    // 只做一次,而不是每次版面計算都做,否則使用者自己捲動的結果會在下一輪被撤銷。
    override protected fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        super.onLayout(changed, l, t, r, b)
        if (positioned) return
        val origin = stage.originOffset
        if (origin.x == 0 && origin.y == 0 && stage.width == 0) return
        positioned = true
        post {
            horizontal.scrollTo(origin.x, 0)
            vertical.scrollTo(0, origin.y)
        }
    }

    fun getModeIndex(): Int = stage.mode

    fun setModeIndex(mode: Int) {
        stage.mode = mode
        button?.setModeIndex(mode)
    }

    /**
     * Adds the floating control.
     *
     * Called only when `DebugFeatures.allowsRootScrollControl` is true; the
     * decision is Swift's, because that flag is Swift's. A shipped application
     * does not float a control over its own content -- that is the difference
     * between a test affordance and a feature.
     *
     * Top left by default, and draggable from there. It sits over the content
     * wherever it starts, so the default is a choice about which corner is
     * least likely to matter rather than one that avoids the problem.
     *
     * 加入那個浮動控制項。
     *
     * 僅在 `DebugFeatures.allowsRootScrollControl` 為真時呼叫；該判斷屬於 Swift 那一側，因為那個
     * 旗標是 Swift 的。已出貨的應用程式不會在自己的內容之上浮著一個控制項——那正是「測試用輔助」與
     * 「產品功能」之間的分別。
     *
     * 預設位於左上角，並可自該處拖曳。無論從哪裡開始，它都會蓋在內容之上；因此這個預設值是「選一個
     * 最不可能造成妨礙的角落」，而不是一個能迴避該問題的位置。
     */
    fun installModeButton(activity: Activity) {
        if (button != null) return
        val density = resources.displayMetrics.density
        val margin = (8 * density).toInt()

        // Below the status bar, not under it.
        //
        // The first version used an 8dp margin from the top of the window and
        // the button was unreachable: `dumpsys window` reports
        // `statusBars frame=[0,0][1080,128]` on this device and the button
        // occupied y 21..147, so 107 of its 126 pixels were beneath a window
        // that belongs to SystemUI and takes the touches in its own area.
        // `adb shell input tap` at the centre did nothing at all -- no log, no
        // mode change -- and a tap 54 pixels lower, on the sliver that cleared
        // the bar, worked first time. A control that is visible and not
        // touchable is the worst of the three states it could be in.
        //
        // From API 35 an app draws into the insets, which is why this is needed
        // now and was not before; `getSafeAreaTopInset` returns 0 below that,
        // where the system keeps the content view clear of the bars itself.
        // Asked of `AndroidBackendHelpers` rather than computed here, so that
        // the inset this positions against is the same one `size(ofWindow:)`
        // reports. It answers in points.
        //
        // 放在狀態列之下，而不是壓在它底下。
        //
        // 第一版使用「距視窗頂端 8dp」的邊距，結果按鈕根本按不到：本裝置上 `dumpsys window` 回報
        // `statusBars frame=[0,0][1080,128]`，而按鈕佔據 y 21..147，因此它 126 個像素中有 107 個
        // 位於一個屬於 SystemUI 的視窗底下，而該視窗會接走其範圍內的觸控。以 `adb shell input tap`
        // 點擊其中心毫無反應——沒有日誌、也沒有模式變更——而往下 54 像素、點在剛好露出狀態列之外的
        // 那一條窄縫上，第一次就成功。一個「看得見卻按不到」的控制項，是三種可能狀態中最糟的一種。
        //
        // 自 API 35 起 app 會繪製進 inset 區域，這正是現在需要這段處理、而先前不需要的原因；在該版本
        // 以下 `getSafeAreaTopInset` 回傳 0，因為系統會自行讓 content view 避開系統列。此處向
        // `AndroidBackendHelpers` 詢問而非自行計算，如此「本控制項所依據的 inset」與
        // `size(ofWindow:)` 所回報的是同一個。它以「點」為單位作答。
        val helpers = AndroidBackendHelpers()
        val topInset = (helpers.getSafeAreaTopInset(activity) * density).toInt()
        val leftInset = (helpers.getSafeAreaLeftInset(activity) * density).toInt()

        val made = ViewModeButton(context, stage.mode) { mode -> stage.mode = mode }
        val params = LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT)
        params.leftMargin = leftInset + margin
        params.topMargin = topInset + margin
        addView(made, params)
        button = made
    }
}

/**
 * The view the content actually sits in, sized to the content rather than to
 * the window.
 *
 * Separate from `RootScrollHost` because a `ScrollView` measures its one child
 * and then scrolls it; the child has to report the size of the *content*, and
 * the content's own root reports the size of the *window* -- SwiftCrossUI gives
 * it `MATCH_PARENT` so that `size(ofWindow:)` and the layout agree. This view
 * sits between them and reports the union.
 *
 * 內容實際所在的那個 view，其尺寸取自內容而非視窗。
 *
 * 之所以與 `RootScrollHost` 分開，是因為 `ScrollView` 會量測它唯一的子元件然後捲動它；那個子元件
 * 必須回報**內容**的尺寸，而內容自己的根回報的是**視窗**的尺寸——SwiftCrossUI 給了它
 * `MATCH_PARENT`，好讓 `size(ofWindow:)` 與版面一致。本 view 位於兩者之間，回報兩者的聯集。
 */
private class Stage(context: Context) : ViewGroup(context) {
    private var content: View? = null
    private val box = Rect()
    private var scale = 1f
    private var lastLoggedState = ""

    /// Where the content's own (0,0) sits inside this view, in pixels.
    ///
    /// The host scrolls here once so the first frame shows what the app laid
    /// out, rather than the empty margin to its left.
    ///
    /// 內容自身的 (0,0) 落在本 view 內的位置,以像素計。
    ///
    /// 宿主會捲到此處一次,好讓第一個畫面顯示 app 實際排出來的東西,而不是它左側的空白邊界。
    val originOffset: android.graphics.Point
        get() = android.graphics.Point((-box.left * scale).toInt(), (-box.top * scale).toInt())

    var mode: Int = RootScrollHost.MODE_ACTUAL_VIEW
        set(value) {
            if (field == value) return
            field = value
            requestLayout()
            invalidate()
        }

    fun host(view: View) {
        removeAllViews()
        content = view
        addView(view)
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val child = content
        if (child == null) {
            setMeasuredDimension(0, 0)
            return
        }

        // The viewport, taken from the spec size even though the mode is
        // UNSPECIFIED. Both scroll views hand their child an UNSPECIFIED spec
        // on the axis they scroll -- that is how a child gets to be bigger than
        // its parent -- but they leave the size in place, and the content's
        // root is MATCH_PARENT and needs a real number to resolve against.
        //
        // 視口尺寸，取自 spec 的 size，即使其 mode 是 UNSPECIFIED。兩個捲動視圖在它們所捲動的那個軸上
        // 都會給子元件一個 UNSPECIFIED 的 spec——子元件之所以能大於其父容器，正是靠這個——但它們仍會
        // 保留 size 值；而內容的根是 MATCH_PARENT，需要一個實際的數字才能解析。
        val viewportWidth = MeasureSpec.getSize(widthMeasureSpec)
        val viewportHeight = MeasureSpec.getSize(heightMeasureSpec)
        child.measure(
            MeasureSpec.makeMeasureSpec(viewportWidth, MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(viewportHeight, MeasureSpec.EXACTLY),
        )

        // Laid out before it is measured, which is the wrong way round only in
        // name. `contentBounds` reads `x`, `y`, `width` and `height`, and those
        // are set by layout, not by measure -- so a first pass has to place the
        // children before the union can be taken. `child.layout` here does not
        // fight `onLayout` below: it places the subtree at the same size
        // `onLayout` will, and `onLayout` then only moves the root.
        //
        // 在量測之前先排版，這件事只有名稱上是反的。`contentBounds` 讀的是 `x`、`y`、`width` 與
        // `height`，而那些是由版面而非量測設定的——因此必須先有一次把子元件放好的過程，才能取聯集。
        // 此處的 `child.layout` 不會與下方的 `onLayout` 打架：它以 `onLayout` 將採用的相同尺寸放置
        // 整棵子樹，而 `onLayout` 之後只移動根。
        child.layout(0, 0, child.measuredWidth, child.measuredHeight)
        RootScrollHost.contentBounds(child, box)

        scale =
            if (mode == RootScrollHost.MODE_RWD_VIEW && box.width() > viewportWidth &&
                viewportWidth > 0
            ) {
                viewportWidth.toFloat() / box.width().toFloat()
            } else {
                1f
            }

        setMeasuredDimension(
            (box.width() * scale).toInt(),
            (box.height() * scale).toInt(),
        )
        // Logged when it changes, not on every measure pass. `onMeasure` runs
        // several times per layout -- fillViewport alone causes a second pass --
        // and a line per pass buries whatever else the app is saying. What this
        // reports is the one thing that cannot be seen from a screenshot: how
        // much content there is outside the viewport, and on which side.
        //
        // 在它改變時記錄，而不是每一次量測都記錄。`onMeasure` 在一次版面計算中會執行數次——光是
        // fillViewport 就會造成第二次——而每一次都記一行會把 app 想說的其他話全部淹沒。這一行所回報的
        // 正是螢幕截圖看不出來的那件事：視口之外還有多少內容，以及在哪一側。
        val state = "$box $scale $mode"
        if (state != lastLoggedState) {
            lastLoggedState = state
            Log.d(
                "swift",
                "[rootscroll] viewport=${viewportWidth}x${viewportHeight} " +
                    "box=(${box.left},${box.top})-(${box.right},${box.bottom}) " +
                    "scale=$scale mode=${RootScrollHost.titleFor(mode)}",
            )
        }
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        val child = content ?: return

        // Scale about the top left, not the centre.
        //
        // A view's default pivot is its centre, so scaling moves the frame as
        // well as resizing it and the offset below would be applied to a box
        // that had already shifted. UIKitBackend has the same problem and
        // solves it by setting the origin after the transform; a pivot is the
        // Android way to say the same thing once.
        //
        // 縮放以左上角為基準，而非中心。
        //
        // view 的預設 pivot 是它的中心，因此縮放會同時改變尺寸與位置，於是下方的偏移會被套用在一個
        // 早已位移過的矩形上。UIKitBackend 面對同樣的問題，其解法是在 transform 之後再設定原點；
        // 在 Android 上，pivot 是把同一件事一次講清楚的方式。
        child.pivotX = 0f
        child.pivotY = 0f
        child.scaleX = scale
        child.scaleY = scale

        // Shifted so the leftmost and topmost content sits at the origin.
        // Without this the overflow to the left is unreachable however large
        // the measured size is: a scroll view's scroll range starts at zero.
        //
        // 平移，使最左與最上的內容落在原點。少了這一步，無論量到的尺寸多大，左側的溢出都無法觸及：
        // 捲動視圖的捲動範圍是從零開始的。
        child.layout(0, 0, child.measuredWidth, child.measuredHeight)
        child.translationX = -box.left * scale
        child.translationY = -box.top * scale
    }
}

/**
 * The floating control that switches between the two, draggable so it can be
 * moved off whatever it is covering.
 *
 * 在兩者之間切換的浮動控制項，可拖曳，以便從它所遮蓋的東西上移開。
 */
private class ViewModeButton(
    context: Context,
    initial: Int,
    private val onToggle: (Int) -> Unit,
) : Button(context) {
    private var mode = initial
    private var downX = 0f
    private var downY = 0f
    private var dragged = false
    private val slop: Float

    init {
        text = RootScrollHost.titleFor(initial)
        isAllCaps = false
        textSize = 12f
        val density = resources.displayMetrics.density
        val padding = (10 * density).toInt()
        setPadding(padding, padding / 2, padding, padding / 2)
        elevation = 8 * density
        slop = 4 * density
    }

    fun setModeIndex(newMode: Int) {
        mode = newMode
        text = RootScrollHost.titleFor(newMode)
    }

    // Touch handled here rather than with an OnClickListener plus an
    // OnTouchListener. A drag on Android starts as a press, so the two would
    // race: the click fires on the up event whether or not the finger moved,
    // and every attempt to reposition the button would also toggle the mode.
    // The slop test is what separates them -- a press that never travels
    // further than four density-independent pixels is a tap.
    //
    // 觸控在此處處理，而不是用 OnClickListener 加 OnTouchListener 的組合。在 Android 上，拖曳一開始
    // 就是一次按下，因此兩者會互搶：無論手指有沒有移動，click 都會在抬起事件時觸發，於是每一次想
    // 重新擺放按鈕的操作也都會順帶切換模式。slop 判斷正是把兩者分開的東西——一次按下若移動距離從未
    // 超過四個密度無關像素，那就是一次點擊。
    override fun onTouchEvent(event: MotionEvent): Boolean {
        val parent = parent as? ViewGroup ?: return super.onTouchEvent(event)
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downX = event.rawX
                downY = event.rawY
                dragged = false
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                val dx = event.rawX - downX
                val dy = event.rawY - downY
                if (!dragged && kotlin.math.hypot(dx, dy) < slop) return true
                dragged = true
                // Clamped to the parent. A button dragged past the edge cannot
                // be dragged back, and it is the only way to change the mode.
                // 夾在父容器範圍內。被拖出邊界的按鈕就拖不回來了，而它是改變模式的唯一途徑。
                translationX = (translationX + dx)
                    .coerceIn(0f, (parent.width - width - left).toFloat().coerceAtLeast(0f))
                translationY = (translationY + dy)
                    .coerceIn(0f, (parent.height - height - top).toFloat().coerceAtLeast(0f))
                downX = event.rawX
                downY = event.rawY
                return true
            }
            MotionEvent.ACTION_UP -> {
                if (!dragged) {
                    mode =
                        if (mode == RootScrollHost.MODE_ACTUAL_VIEW) {
                            RootScrollHost.MODE_RWD_VIEW
                        } else {
                            RootScrollHost.MODE_ACTUAL_VIEW
                        }
                    text = RootScrollHost.titleFor(mode)
                    Log.d("swift", "root view mode -> ${RootScrollHost.titleFor(mode)}")
                    onToggle(mode)
                }
                return true
            }
        }
        return super.onTouchEvent(event)
    }
}
