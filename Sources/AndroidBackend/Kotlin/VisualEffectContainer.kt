package dev.swiftcrossui.androidbackend

import android.app.Activity
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.RenderEffect
import android.graphics.RuntimeShader
import android.graphics.Shader
import android.os.Build
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
    /// The non-opacity values the current RenderEffect was built from; null before the first.
    /// 目前的 RenderEffect 所依據的、opacity 以外的數值;第一次之前為 null。
    private var lastFilters: FloatArray? = null

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

        // The direct path sets the effect every frame while opacity animates
        // (EffectAnimation.swift). When nothing but the opacity changed, the
        // RenderEffect already set still holds, so it is not rebuilt.
        // 直接路徑在 opacity 動畫期間每幀都設定效果(EffectAnimation.swift)。除了 opacity 什麼都沒變時，
        // 已設定的 RenderEffect 仍然適用，因此不重建。
        val filters = floatArrayOf(blurRadius, saturation, brightness, contrast, grayscale, hueRotationDegrees)
        if (filters.contentEquals(lastFilters)) {
            return
        }
        lastFilters = filters

        // Grayscale through a shader when the platform has one (API 33), so it
        // is the grey AppKitBackend draws: CIColorMonochrome tinted 0.5 grey in
        // Core Image's linear working space, which maps luminance through an
        // overlay and comes out darker than saturation 0 -- the user chose
        // AppKit's (P39, 2026-10-16). A ColorMatrix is linear in the sRGB
        // values and cannot draw that curve, so on API 31 and 32 grayscale
        // stays the desaturation in the matrix below, the same grey as
        // saturation 0. Hue rotation then has to come after the shader, as on
        // AppKit, so it moves to a matrix of its own.
        //
        // 平台有 shader 時(API 33)以 shader 繪製灰階，使它成為 AppKitBackend 畫出的那種灰：在 Core Image
        // 線性工作空間中以 0.5 灰上色的 CIColorMonochrome,會把亮度經過 overlay 映射，比 saturation 0
        // 更暗——使用者選擇以 AppKit 為準(P39,2026-10-16)。ColorMatrix 對 sRGB 數值是線性的，畫不出
        // 那條曲線，因此在 API 31 與 32 上灰階仍是下方矩陣中的去飽和，與 saturation 0 同一種灰。色相旋轉
        // 必須在 shader 之後(與 AppKit 相同),所以改用它自己的矩陣。
        val greyShader =
            if (grayscale != 0f && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
                RuntimeShader(GREY_SHADER).apply { setFloatUniform("amount", grayscale) }
            else null
        val matrix =
            if (greyShader == null)
                colourMatrix(saturation, brightness, contrast, grayscale, hueRotationDegrees)
            else colourMatrix(saturation, brightness, contrast, 0f, 0f)
        var colourEffect =
            if (matrix == null) null
            else RenderEffect.createColorFilterEffect(ColorMatrixColorFilter(matrix))
        if (greyShader != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val grey = RenderEffect.createRuntimeShaderEffect(greyShader, "content")
            colourEffect =
                if (colourEffect == null) grey
                else RenderEffect.createChainEffect(grey, colourEffect)
            if (hueRotationDegrees != 0f) {
                colourEffect =
                    RenderEffect.createChainEffect(
                        RenderEffect.createColorFilterEffect(
                            ColorMatrixColorFilter(hueRotationMatrix(hueRotationDegrees))
                        ),
                        colourEffect,
                    )
            }
        }

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
        if (
            saturation == 1f &&
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
                        contrast,
                        0f,
                        0f,
                        0f,
                        shift,
                        0f,
                        contrast,
                        0f,
                        0f,
                        shift,
                        0f,
                        0f,
                        contrast,
                        0f,
                        shift,
                        0f,
                        0f,
                        0f,
                        1f,
                        0f,
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
                        1f,
                        0f,
                        0f,
                        0f,
                        offset,
                        0f,
                        1f,
                        0f,
                        0f,
                        offset,
                        0f,
                        0f,
                        1f,
                        0f,
                        offset,
                        0f,
                        0f,
                        0f,
                        1f,
                        0f,
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
                0f,
                0f,
                lumR - cos * lumR + sin * 0.143f,
                lumG + cos * (1 - lumG) + sin * 0.140f,
                lumB - cos * lumB - sin * 0.283f,
                0f,
                0f,
                lumR - cos * lumR - sin * (1 - lumR),
                lumG - cos * lumG + sin * lumG,
                lumB + cos * (1 - lumB) + sin * lumB,
                0f,
                0f,
                0f,
                0f,
                0f,
                1f,
                0f,
            )
        )
    }

    companion object {
        // CIColorMonochrome as Core Image runs it in a linear working space:
        // decode sRGB, take luminance with its weights, overlay it against the
        // tint c (0.5 grey, linear 0.21404) -- 2Lc below 0.5, 1 - 2(1 - L)(1 - c)
        // above -- blend by `amount` in linear light, encode. Colours arrive
        // premultiplied, so the curve runs on the unpremultiplied values.
        //
        // 依 Core Image 在線性工作空間中的方式實作 CIColorMonochrome:解碼 sRGB,以其權重取亮度，
        // 對上色值 c(0.5 灰，線性 0.21404)做 overlay——0.5 以下為 2Lc,以上為 1 - 2(1 - L)(1 - c)——
        // 在線性光中依 `amount` 混合，再編碼。顏色是預乘過的，所以曲線作用於還原後的數值。
        private const val GREY_SHADER =
            """
            uniform shader content;
            uniform float amount;

            float decode(float v) {
                return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4);
            }

            float encode(float v) {
                return v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1.0 / 2.4) - 0.055;
            }

            half4 main(float2 position) {
                half4 colour = content.eval(position);
                if (colour.a == 0.0) {
                    return colour;
                }
                float3 rgb = float3(colour.rgb) / float(colour.a);
                float3 lin = float3(decode(rgb.r), decode(rgb.g), decode(rgb.b));
                float luminance = dot(lin, float3(0.2125, 0.7154, 0.0721));
                const float tint = 0.21404;
                float grey = luminance < 0.5
                    ? 2.0 * luminance * tint
                    : 1.0 - 2.0 * (1.0 - luminance) * (1.0 - tint);
                float3 mixed = mix(lin, float3(grey), amount);
                float3 result = float3(encode(mixed.r), encode(mixed.g), encode(mixed.b));
                return half4(half3(result * float(colour.a)), colour.a);
            }
            """
    }
}
