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
class ContinuousGestureContainer(context: Context, private val kind: Int) :
    ViewGroup(context) {

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
        setMeasuredDimension(
            resolveSize(0, widthSpec),
            resolveSize(0, heightSpec),
        )
    }

    override fun onInterceptTouchEvent(event: MotionEvent) = true

    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                startX = event.x
                startY = event.y
                currentX = event.x
                currentY = event.y
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
                        currentX = event.x
                        currentY = event.y
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
                        currentX = event.x
                        currentY = event.y
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
