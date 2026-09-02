package dev.swiftcrossui.androidbackend

import android.app.Activity
import android.graphics.Matrix
import android.view.Gravity
import android.view.ViewGroup
import android.widget.FrameLayout

// Geometric effects, as an animation matrix on the container.
//
// setAnimationMatrix rather than the scaleX / rotation / translationX family,
// because those cannot express a shear and SwiftUI's .transformEffect(_:) takes
// an arbitrary affine. Composing the named properties would also fix an order
// this backend does not get to choose: the transform arrives already composed
// and already resolved about its anchor.
//
// 幾何效果，實作為容器上的 animation matrix。
//
// 使用 setAnimationMatrix 而非 scaleX / rotation / translationX 那一族，因為後者無法表達推移
// (shear)，而 SwiftUI 的 .transformEffect(_:) 接受任意仿射變換。以具名屬性組合出結果，還會固定一個
// 本 backend 無權決定的順序：傳入的 transform 已經組合完成，也已針對其錨點解析完畢。
class GeometricEffectContainer(activity: Activity) : FrameLayout(activity) {

    private val matrix = Matrix()

    override fun generateDefaultLayoutParams() =
        FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
            Gravity.FILL,
        )

    // The six values of a 3x3 affine, in Android's own order.
    //
    // Matrix.setValues wants nine and the last row of an affine is always
    // (0, 0, 1), so only six cross the boundary. Android's MSCALE_X, MSKEW_X,
    // MTRANS_X, MSKEW_Y, MSCALE_Y, MTRANS_Y map to CoreGraphics'
    // (a, c, tx, b, d, ty) -- note the interleaving, which is the thing to get
    // wrong here. The caller passes them already in this order.
    //
    // 3x3 仿射矩陣的六個值，依 Android 自身的順序排列。
    //
    // Matrix.setValues 需要九個值，而仿射矩陣的最後一列恆為 (0, 0, 1)，因此只有六個需要跨越邊界。
    // Android 的 MSCALE_X、MSKEW_X、MTRANS_X、MSKEW_Y、MSCALE_Y、MTRANS_Y 對應 CoreGraphics 的
    // (a, c, tx, b, d, ty)——請注意其交錯順序，那正是此處容易寫錯的地方。呼叫端傳入時即已依此順序排列。
    fun setAffineTransform(
        scaleX: Float,
        skewX: Float,
        translateX: Float,
        skewY: Float,
        scaleY: Float,
        translateY: Float,
    ) {
        matrix.setValues(
            floatArrayOf(
                scaleX, skewX, translateX,
                skewY, scaleY, translateY,
                0f, 0f, 1f,
            )
        )
        animationMatrix = matrix

        // The parent has to redraw, not just this view. An animation matrix
        // moves pixels outside this container's own bounds -- that is what a
        // rotation or an offset does -- and only the parent's invalidate
        // repaints the area the view has left behind.
        // 需要重繪的是父容器，而非只有本 view。animation matrix 會把像素移動到本容器自身邊界之外
        // ——旋轉或位移正是如此——而唯有父容器的 invalidate 才會重繪該 view 所離開的那塊區域。
        (parent as? ViewGroup)?.invalidate()
    }

    fun clearAffineTransform() {
        animationMatrix = null
        (parent as? ViewGroup)?.invalidate()
    }
}
