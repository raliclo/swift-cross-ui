package dev.swiftcrossui.androidbackend

import android.content.Context
import android.view.MotionEvent
import android.view.ViewGroup
import kotlin.math.atan2
import kotlin.math.hypot

/// Recognises one of drag, magnify or rotate, and reports it to Swift.
///
/// **Rotation is done by hand because Android has no detector for it.** It ships
/// `GestureDetector` and `ScaleGestureDetector`, and nothing for rotation -- so
/// the two-finger angle is computed here. That absence is the reason
/// `BackendFeatures` declares three protocols rather than one: a backend can
/// have drag and magnify and lack rotate, and this one nearly did.
///
/// Values are read back through properties rather than passed to the callback,
/// because `SwiftAction` takes no arguments. `FrameClockCallback` and
/// `CustomSlider` both record the same constraint.
///
/// 辨識拖曳、縮放或旋轉三者之一，並把結果回報給 Swift。
///
/// **旋轉是手寫的，因為 Android 沒有對應的偵測器。** 它提供 `GestureDetector` 與
/// `ScaleGestureDetector`，而旋轉什麼都沒有——因此兩指之間的角度在此處計算。那個「缺席」正是
/// `BackendFeatures` 宣告三個協定而非一個的原因:一個 backend 可以有拖曳與縮放而沒有旋轉，而這一個
/// 差一點就是如此。
///
/// 數值以屬性讀回，而不是傳給那個 callback，因為 `SwiftAction` 不帶參數。`FrameClockCallback` 與
/// `CustomSlider` 都記載了同一項限制。
class ContinuousGestureContainer(context: Context, private val kind: Int) : ViewGroup(context) {

    companion object {
        const val KIND_DRAG = 0
        const val KIND_MAGNIFY = 1
        const val KIND_ROTATE = 2
    }

    var onChange: SwiftAction? = null
    var onEnd: SwiftAction? = null

    var startX = 0f
        private set

    var startY = 0f
        private set

    var currentX = 0f
        private set

    var currentY = 0f
        private set

    var magnification = 1f
        private set

    var radians = 0f
        private set

    private var initialSpan = 0f
    private var initialAngle = 0f
    private var tracking = false

    /**
     * Pixels to points, because `DragGestureValue` is documented in points and a `MotionEvent` is
     * in pixels.
     *
     * **This was missing until 2026-09-23 and nothing reported it.** AndroidBackend lays out in
     * points multiplied by this same density -- a `.frame(width: 340, height: 240)` measures 892 x
     * 630 pixels at density 2.625 -- and `AndroidSynthesiser` multiplies an action file's points by
     * it on the way in. Handing `event.x` over unscaled made every drag distance 2.625 times too
     * large on that device and a different wrong number on the next one, which reads as an
     * over-sensitive gesture rather than as a unit mistake. Found while writing
     * `ScrollGestureContainer`, which had the conversion from its first line.
     *
     * Only the drag needs it. A magnification is a ratio of two spans and a rotation is an angle;
     * both cancel the units out, which is why they were right all along.
     *
     * 像素換算成點,因為 `DragGestureValue` 是以點為單位載明的,而 `MotionEvent` 是像素。
     *
     * **在 2026-09-23 之前這件事是缺的,而沒有任何東西回報過它。** AndroidBackend 的排版就是 「點乘上這同一個 density」——`.frame(width:
     * 340, height: 240)` 在 density 2.625 下量到 892 x 630 像素——而 `AndroidSynthesiser` 在入口處把動作檔的點乘上它。把
     * `event.x` 未經換算 交出去,會讓那台裝置上每一段拖曳距離都大 2.625 倍,換一台就是另一個錯數字;那讀起來像 「手勢太敏感」,而不像一個單位錯誤。它是在寫
     * `ScrollGestureContainer` 時被發現的 ——那一支從第一行就有這個換算。
     *
     * 只有拖曳需要它。縮放是兩個 span 的比值、旋轉是一個角度,兩者都把單位約掉了 ——那正是它們一直都是對的原因。
     */
    private val density: Float
        get() = resources.displayMetrics.density

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        // The child fills this container, which is what every wrapping container
        // in this backend does.
        // 子節點填滿這個容器——本 backend 中每一個包裝用的容器都是這麼做的。
        for (i in 0 until childCount) {
            getChildAt(i).layout(0, 0, r - l, b - t)
        }
    }

    override fun onMeasure(widthSpec: Int, heightSpec: Int) {
        measureChildren(widthSpec, heightSpec)
        setMeasuredDimension(resolveSize(0, widthSpec), resolveSize(0, heightSpec))
    }

    override fun onInterceptTouchEvent(event: MotionEvent) = true

    /// **A scrolling ancestor steals this gesture at eight dp of travel, and
    /// the theft looks exactly like a gesture that stopped early.**
    ///
    /// Measured on 2026-09-17 with P65 and a synthesised two-contact stream, at
    /// 420 dpi where one touch slop is 8dp = 21 px. A pinch asked to double
    /// reported 1.194 and stopped: that is step 12 of 62, where the first
    /// contact has moved 20.3 px, and step 13 would have moved it 22.0. A
    /// rotation asked for 45 degrees reported 0.633 rad: step 25 of 31, where
    /// the same contact has moved 20.4 px horizontally, and step 26 crosses 21.
    /// Two different gestures, two different fractions, one threshold.
    ///
    /// What happens is that the root scroll view passes the slop, takes the
    /// gesture, and this view gets `ACTION_CANCEL` -- which it already reports
    /// as an end, so the app printed `magnify ENDED: 1.194` and every later
    /// move fell through the `tracking` guard in silence. Nothing was dropped
    /// and nothing failed; the gesture simply belonged to somebody else from
    /// there on, and that is as true of a finger as it is of a synthesiser.
    ///
    /// `requestDisallowInterceptTouchEvent` is the API for this: a child that
    /// owns a gesture says so, and the flag is cleared by the framework on the
    /// next `ACTION_DOWN`.
    ///
    /// **一個會捲動的祖先會在八個 dp 的位移處奪走這個手勢,而那次奪取看起來與「一個提早停止的手勢」
    /// 完全相同。**
    ///
    /// 2026-09-17 以 P65 與一段合成的雙接觸點事件串實測,420 dpi 之下一個 touch slop 是 8dp = 21 px。
    /// 一次要求放大兩倍的縮放停在 1.194:那是 62 步中的第 12 步,此時第一個接觸點移動了 20.3 px,
    /// 而第 13 步會是 22.0。一次要求 45 度的旋轉停在 0.633 rad:31 步中的第 25 步,同一個接觸點的
    /// 水平位移是 20.4 px,而第 26 步越過 21。兩個不同的手勢、兩個不同的比例、同一個門檻。
    ///
    /// 實際發生的是:根部的 scroll view 越過了 slop、接管了這個手勢,而本 view 收到 `ACTION_CANCEL`
    /// ——它本來就把那當成結束回報,所以 app 印出了 `magnify ENDED: 1.194`,其後每一個 move 都靜靜地
    /// 落在 `tracking` 的守衛之外。沒有東西被丟掉,也沒有東西失敗;那個手勢從那一刻起就屬於別人了,
    /// 而這件事對一根手指與對一個合成器同樣成立。
    ///
    /// `requestDisallowInterceptTouchEvent` 正是為此而存在的 API:一個擁有某個手勢的子節點把這件事
    /// 說出來,而該旗標會由框架在下一個 `ACTION_DOWN` 時清除。
    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                parent?.requestDisallowInterceptTouchEvent(true)
                startX = event.x / density
                startY = event.y / density
                currentX = event.x / density
                currentY = event.y / density
                tracking = kind == KIND_DRAG
            }

            MotionEvent.ACTION_POINTER_DOWN -> {
                if (kind != KIND_DRAG && event.pointerCount >= 2) {
                    initialSpan = span(event)
                    initialAngle = angle(event)
                    magnification = 1f
                    radians = 0f
                    tracking = initialSpan > 0
                }
            }

            MotionEvent.ACTION_MOVE -> {
                if (!tracking) return true
                when (kind) {
                    KIND_DRAG -> {
                        currentX = event.x / density
                        currentY = event.y / density
                    }

                    KIND_MAGNIFY ->
                        if (event.pointerCount >= 2 && initialSpan > 0) {
                            magnification = span(event) / initialSpan
                        }

                    KIND_ROTATE ->
                        if (event.pointerCount >= 2) {
                            // Android's y grows downward, so a positive change
                            // in atan2 is already clockwise -- no flip, unlike
                            // the AppKit side.
                            // Android 的 y 向下增加，因此 atan2 的正向改變本來就是順時針——不需要
                            // 翻轉，這與 AppKit 那一側不同。
                            radians = angle(event) - initialAngle
                        }
                }
                onChange?.call()
            }

            MotionEvent.ACTION_UP,
            MotionEvent.ACTION_CANCEL,
            MotionEvent.ACTION_POINTER_UP -> {
                if (tracking) {
                    if (kind == KIND_DRAG) {
                        currentX = event.x / density
                        currentY = event.y / density
                    }
                    tracking = false
                    onEnd?.call()
                }
            }
        }
        return true
    }

    private fun span(event: MotionEvent) =
        hypot(event.getX(1) - event.getX(0), event.getY(1) - event.getY(0))

    private fun angle(event: MotionEvent) =
        atan2(event.getY(1) - event.getY(0), event.getX(1) - event.getX(0))
}
