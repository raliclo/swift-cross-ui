package dev.swiftcrossui.androidbackend

import android.app.Activity
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.RenderEffect
import android.graphics.Shader
import android.view.Gravity
import android.view.ViewGroup
import android.widget.FrameLayout

// Compositing effects, as one RenderEffect over the subtree.
//
// RenderEffect is API 31, which is why minSDK was raised from 28 -- see
// androidContainer/Bundler.android.toml. It is the only public way to blur or
// colour-adjust a live View subtree; everything else on Android either
// rasterises the view yourself or applies to a single drawable.
//
// 合成效果，實作為套用於整個子樹的單一 RenderEffect。
//
// RenderEffect 屬於 API 31，這正是 minSDK 由 28 調升的原因——見
// androidContainer/Bundler.android.toml。它是公開 API 中唯一能對一棵活的 View 子樹進行模糊或色彩
// 調整的方式；Android 上其餘的做法，不是要自行把 view 光柵化，就是只能作用於單一 drawable。
class VisualEffectContainer(activity: Activity) : FrameLayout(activity) {

    // MATCH_PARENT, so the child takes this container's size.
    //
    // The same gap the AppKit and UIKit containers had: the modifier sizes the
    // container it is handed and nothing sizes what is inside it. Android
    // solves it here rather than at each insert, the way CornerRadiusContainer
    // already does.
    //
    // 使用 MATCH_PARENT，讓子元件取得本容器的尺寸。
    //
    // 這與 AppKit、UIKit 容器所遇到的是同一個缺口：modifier 只設定它所拿到的容器的尺寸，沒有任何
    // 東西為其內部的元件設定尺寸。Android 在此處解決它，而非在每一次 insert 時處理——與
    // CornerRadiusContainer 既有的做法相同。
    override fun generateDefaultLayoutParams() =
        FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
            Gravity.FILL,
        )

    // One call carrying every value, because the protocol replaces the whole
    // effect rather than accumulating. Seven separate setters would each have
    // to rebuild the chain from the other six's remembered state, which is the
    // same work with somewhere for the two to disagree.
    //
    // 一次呼叫帶入所有數值，因為該 protocol 是「取代整個效果」而非累加。若拆成七個 setter，每一個
    // 都必須依據其餘六個所記住的狀態重建整條鏈——那是同樣的工作量，卻多出一個讓兩者不一致的地方。
    fun setVisualEffect(
        opacity: Float,
        blurRadius: Float,
        saturation: Float,
        brightness: Float,
        contrast: Float,
        grayscale: Float,
        hueRotationDegrees: Float,
    ) {
        // Opacity through alpha, not through the colour matrix.
        //
        // View.setAlpha composites the subtree as a group, which is what
        // SwiftUI's .opacity does; a matrix alpha would fade each descendant
        // independently and two half-opaque siblings would show through each
        // other. AppKitBackend uses NSView.alphaValue for the same reason, and
        // GtkBackend gtk_widget_set_opacity.
        //
        // 不透明度使用 alpha，而非色彩矩陣。
        //
        // View.setAlpha 會把子樹當作一個群組來合成，那正是 SwiftUI 的 .opacity 的行為；若改用矩陣中
        // 的 alpha，每個後代會各自淡出，兩個半透明的同層元件會互相透出。AppKitBackend 基於同樣理由
        // 使用 NSView.alphaValue，GtkBackend 則使用 gtk_widget_set_opacity。
        alpha = opacity

        val matrix = colourMatrix(saturation, brightness, contrast, grayscale, hueRotationDegrees)
        val colourEffect =
            if (matrix == null) null
            else RenderEffect.createColorFilterEffect(ColorMatrixColorFilter(matrix))

        // Blur before colour, so the blur reads the original pixels rather than
        // recoloured ones -- the order SwiftUI's .blur(radius:).saturation(0)
        // produces by nesting. createChainEffect(outer, inner) runs inner
        // first, so the blur is the inner one.
        //
        // 模糊排在色彩之前，使模糊讀到的是原始像素而非已重新上色的像素——那正是 SwiftUI 的
        // .blur(radius:).saturation(0) 透過巢狀所產生的順序。createChainEffect(outer, inner) 會先
        // 執行 inner，因此模糊是 inner 的那一個。
        val blurEffect =
            if (blurRadius <= 0f) null
            else RenderEffect.createBlurEffect(blurRadius, blurRadius, Shader.TileMode.CLAMP)

        setRenderEffect(
            when {
                blurEffect != null && colourEffect != null ->
                    RenderEffect.createChainEffect(colourEffect, blurEffect)
                blurEffect != null -> blurEffect
                else -> colourEffect
            }
        )
    }

    // null when every input is its identity, so the common case attaches no
    // colour filter at all rather than an identity one.
    // 當每一個輸入都是單位值時回傳 null，使常見情況完全不附加色彩 filter，而非附加一個單位 filter。
    private fun colourMatrix(
        saturation: Float,
        brightness: Float,
        contrast: Float,
        grayscale: Float,
        hueRotationDegrees: Float,
    ): ColorMatrix? {
        if (saturation == 1f &&
            brightness == 0f &&
            contrast == 1f &&
            grayscale == 0f &&
            hueRotationDegrees == 0f
        ) {
            return null
        }

        val result = ColorMatrix()

        if (saturation != 1f) {
            result.postConcat(ColorMatrix().apply { setSaturation(saturation) })
        }

        // Grayscale is a partial desaturation and is kept separate from
        // saturation on purpose. SwiftUI's .grayscale(_:) takes an amount, so it
        // has to be able to land halfway, and folding it into setSaturation
        // would make a view asking for both get one value instead of two
        // effects. 1 - amount is the saturation that leaves `amount` of the way
        // to grey.
        //
        // 灰階是「部分去飽和」，刻意與 saturation 分開。SwiftUI 的 .grayscale(_:) 接受一個程度值，
        // 因此必須能停在中途；若把它折進 setSaturation，同時要求兩者的 view 會只得到一個數值，而非
        // 兩個效果。1 - amount 即是「朝灰色走了 amount 的比例」所對應的飽和度。
        if (grayscale != 0f) {
            result.postConcat(ColorMatrix().apply { setSaturation(1f - grayscale) })
        }

        // Contrast about mid-grey, which is what SwiftUI and CSS both mean by
        // it: scale each channel by `contrast` and shift so 0.5 stays put.
        // 對比以中灰為中心，那正是 SwiftUI 與 CSS 對它的共同定義：把每個通道乘以 contrast，
        // 並平移使 0.5 保持不動。
        if (contrast != 1f) {
            val shift = (0.5f - 0.5f * contrast) * 255f
            result.postConcat(
                ColorMatrix(
                    floatArrayOf(
                        contrast, 0f, 0f, 0f, shift,
                        0f, contrast, 0f, 0f, shift,
                        0f, 0f, contrast, 0f, shift,
                        0f, 0f, 0f, 1f, 0f,
                    )
                )
            )
        }

        // Additive, because SwiftUI's .brightness(_:) adds to each channel.
        // CSS filter: brightness() is multiplicative and centred on 1, which is
        // why GtkBackend converts and this does not.
        // 加法式，因為 SwiftUI 的 .brightness(_:) 是加到每個通道上。CSS 的 filter: brightness()
        // 是以 1 為中心的乘法，那正是 GtkBackend 需要換算、而此處不需要的原因。
        if (brightness != 0f) {
            val offset = brightness * 255f
            result.postConcat(
                ColorMatrix(
                    floatArrayOf(
                        1f, 0f, 0f, 0f, offset,
                        0f, 1f, 0f, 0f, offset,
                        0f, 0f, 1f, 0f, offset,
                        0f, 0f, 0f, 1f, 0f,
                    )
                )
            )
        }

        if (hueRotationDegrees != 0f) {
            result.postConcat(hueRotationMatrix(hueRotationDegrees))
        }

        return result
    }

    // The standard luminance-preserving hue rotation. ColorMatrix has no
    // built-in for it -- setRotate rotates one channel about an axis, which is
    // a different operation and is the easy thing to reach for by mistake.
    // 標準的、保留亮度的色相旋轉。ColorMatrix 沒有對應的內建方法——setRotate 旋轉的是單一通道繞某軸，
    // 那是不同的運算，也正是容易誤用的那一個。
    private fun hueRotationMatrix(degrees: Float): ColorMatrix {
        val radians = Math.toRadians(degrees.toDouble())
        val cos = Math.cos(radians).toFloat()
        val sin = Math.sin(radians).toFloat()
        val lumR = 0.213f
        val lumG = 0.715f
        val lumB = 0.072f
        return ColorMatrix(
            floatArrayOf(
                lumR + cos * (1 - lumR) - sin * lumR,
                lumG - cos * lumG - sin * lumG,
                lumB - cos * lumB + sin * (1 - lumB),
                0f, 0f,
                lumR - cos * lumR + sin * 0.143f,
                lumG + cos * (1 - lumG) + sin * 0.140f,
                lumB - cos * lumB - sin * 0.283f,
                0f, 0f,
                lumR - cos * lumR - sin * (1 - lumR),
                lumG - cos * lumG + sin * lumG,
                lumB + cos * (1 - lumB) + sin * lumB,
                0f, 0f,
                0f, 0f, 0f, 1f, 0f,
            )
        )
    }
}
