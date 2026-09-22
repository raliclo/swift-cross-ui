package dev.swiftcrossui.androidbackend

import android.content.Context
import android.view.MotionEvent
import android.view.ViewConfiguration
import android.view.ViewGroup

/**
 * A scroll reported to the view rather than performed by a scroll container.
 *
 * **Two input paths, because Android has two and they are not the same event.** A mouse or an
 * external trackpad sends `ACTION_SCROLL` through `onGenericMotionEvent` with `AXIS_VSCROLL` in
 * notches; a finger sends an ordinary touch stream. `GestureDetector.onScroll` would cover the
 * second, and it is not used: it needs an `OnTouchListener` or a `dispatchTouchEvent` override to
 * be fed, and this backend has exactly one `OnTouchListener` slot per view which `ButtonPressState`
 * and `.onTapGesture(.secondary)` already contend for. A container of its own has no such
 * contention -- the same reasoning `ContinuousGestureContainer` was built on.
 *
 * **A one-finger drag, not two.** UIKitBackend made the same choice and wrote down why: the action
 * file runner drags with one finger, and a two-finger recogniser never fires under it. Android's
 * synthesiser spells `scroll` as a single-contact drag too (`AndroidSynthesiser.scroll`), so a
 * two-contact requirement here would make the verb undrivable on this platform.
 *
 * Values are read back through properties rather than passed to the callback, because `SwiftAction`
 * takes no arguments. `ContinuousGestureContainer` records the same constraint.
 *
 * 一次「回報給 view」而不是「由捲動容器自己執行」的捲動。
 *
 * **兩條輸入路徑,因為 Android 有兩條,而它們不是同一種事件。** 滑鼠或外接觸控板經由 `onGenericMotionEvent` 送出
 * `ACTION_SCROLL`,`AXIS_VSCROLL` 以「格」為單位;手指送的則是一般的 觸控事件串。`GestureDetector.onScroll`
 * 能涵蓋第二種,而此處沒有用它:它需要一個 `OnTouchListener` 或一個 `dispatchTouchEvent` 覆寫來餵給它,而本 backend 每個 view 只有一個
 * `OnTouchListener` 插槽, 那個插槽已經被 `ButtonPressState` 與 `.onTapGesture(.secondary)` 搶著用。自己的容器沒有這個爭用
 * ——與 `ContinuousGestureContainer` 當初的理由相同。
 *
 * **單指拖曳,不是雙指。** UIKitBackend 做了同樣的選擇並寫下了理由:動作檔的 runner 用一根手指拖曳, 而雙指 recogniser 在它之下永遠不會觸發。Android
 * 的 synthesiser 也把 `scroll` 寫成單一接觸點的拖曳
 * (`AndroidSynthesiser.scroll`),因此在此處要求兩個接觸點,會讓那個動作在這個平台上無法被驅動。
 *
 * 數值以屬性讀回,而不是傳給那個 callback,因為 `SwiftAction` 不帶引數;`ContinuousGestureContainer` 記載了同一項限制。
 */
class ScrollGestureContainer(context: Context) : ViewGroup(context) {
    var onChange: SwiftAction? = null
    var onEnd: SwiftAction? = null

    var deltaX = 0f
        private set

    var deltaY = 0f
        private set

    var travelX = 0f
        private set

    var travelY = 0f
        private set

    /** True for a finger, false for a notched wheel. */
    var isPrecise = true
        private set

    private var lastX = 0f
    private var lastY = 0f
    private var tracking = false

    /**
     * Pixels to points, because `ScrollGestureValue` is documented in points and a `MotionEvent` is
     * in pixels.
     *
     * AndroidBackend lays out in points multiplied by this same density -- P72's `.frame(width:
     * 340, height: 240)` measures 892 x 630 pixels at density 2.625 -- and `AndroidSynthesiser`
     * multiplies an action file's points by it on the way in. Reporting raw `event.x` would hand a
     * caller a number 2.625 times too large on this device and a different wrong number on the next
     * one, which is the kind of error that looks like an over-sensitive gesture rather than a unit
     * mistake.
     *
     * 像素換算成點,因為 `ScrollGestureValue` 是以點為單位載明的,而 `MotionEvent` 是像素。
     *
     * AndroidBackend 的排版就是「點乘上這同一個 density」——P72 的 `.frame(width: 340, height: 240)` 在 density
     * 2.625 下量到 892 x 630 像素——而 `AndroidSynthesiser` 在入口處把動作檔的點乘上它。 直接回報未經換算的
     * `event.x`,會在這台裝置上交給呼叫端一個大了 2.625 倍的數字,在下一台裝置上 則是另一個不同的錯數字;那種錯誤看起來像「手勢太敏感」,而不像一個單位錯誤。
     */
    private val density: Float
        get() = resources.displayMetrics.density

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        for (i in 0 until childCount) {
            getChildAt(i).layout(0, 0, r - l, b - t)
        }
    }

    override fun onMeasure(widthSpec: Int, heightSpec: Int) {
        measureChildren(widthSpec, heightSpec)
        setMeasuredDimension(resolveSize(0, widthSpec), resolveSize(0, heightSpec))
    }

    override fun onInterceptTouchEvent(event: MotionEvent) = true

    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                // A scrolling ancestor takes this gesture at eight dp of travel unless it is told
                // not to; `ContinuousGestureContainer` carries the measurement that found it.
                // 除非明講,否則一個會捲動的祖先會在八個 dp 的位移處奪走這個手勢;
                // 那次量測記在 `ContinuousGestureContainer`。
                parent?.requestDisallowInterceptTouchEvent(true)
                lastX = event.x
                lastY = event.y
                travelX = 0f
                travelY = 0f
                deltaX = 0f
                deltaY = 0f
                isPrecise = true
                tracking = true
            }

            MotionEvent.ACTION_MOVE -> {
                if (!tracking) return true
                // **The sign is the content's, not the finger's.** `ScrollGestureValue` defines
                // delta.y positive as moving FORWARD through the content, and dragging a finger
                // UP moves forward -- so the delta is last minus current, not current minus last.
                // **符號依循內容,不依循手指。** `ScrollGestureValue` 定義 delta.y 為正即「在內容中
                // 向前」,而把手指**往上**拖就是向前——因此差值是「上一個減目前」,不是反過來。
                deltaX = (lastX - event.x) / density
                deltaY = (lastY - event.y) / density
                lastX = event.x
                lastY = event.y
                travelX += deltaX
                travelY += deltaY
                onChange?.call()
            }

            MotionEvent.ACTION_UP,
            MotionEvent.ACTION_CANCEL -> {
                if (tracking) {
                    tracking = false
                    deltaX = 0f
                    deltaY = 0f
                    onEnd?.call()
                }
            }
        }
        return true
    }

    /**
     * The wheel. Each notch is a scroll of its own: a change and then an end.
     *
     * AppKitBackend reached the same shape for the same reason -- a wheel sends no phases, so a
     * target that only reset on a begin would accumulate one translation for the life of the view.
     *
     * 滾輪。每一格都是一次獨立的捲動:一次 change,然後一次 end。
     *
     * AppKitBackend 出於相同理由得到相同的形狀——滾輪不送 phase,因此一個「只在 begin 時重設」的 目標,會在整個 view 的生命期裡累積出單一個
     * translation。
     */
    override fun onGenericMotionEvent(event: MotionEvent): Boolean {
        if (event.actionMasked != MotionEvent.ACTION_SCROLL) {
            return super.onGenericMotionEvent(event)
        }
        if (onChange == null) return false

        val configuration = ViewConfiguration.get(context)
        // AXIS_VSCROLL is positive when the wheel turns away from the user, which moves content
        // BACKWARD, so it is negated to match the protocol. The scroll factors turn notches into
        // pixels and are the same numbers Android's own scroll views use.
        // AXIS_VSCROLL 在滾輪往遠離使用者的方向轉時為正,而那是在內容中**向後**移動,因此取負號以
        // 符合本協定。那兩個 scroll factor 把「格」換算成像素,與 Android 自家捲動視圖用的是同一組數字。
        deltaY =
            -event.getAxisValue(MotionEvent.AXIS_VSCROLL) *
                configuration.scaledVerticalScrollFactor / density
        deltaX =
            event.getAxisValue(MotionEvent.AXIS_HSCROLL) *
                configuration.scaledHorizontalScrollFactor / density
        travelX = deltaX
        travelY = deltaY
        isPrecise = false
        onChange?.call()

        deltaX = 0f
        deltaY = 0f
        onEnd?.call()
        return true
    }
}
