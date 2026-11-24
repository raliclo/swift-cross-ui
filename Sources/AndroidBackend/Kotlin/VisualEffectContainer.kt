package dev.swiftcrossui.androidbackend

import android.app.Activity
import android.graphics.BlendMode
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.Paint
import android.graphics.RenderEffect
import android.graphics.RuntimeShader
import android.graphics.Shader
import android.graphics.Xfermode
import android.os.Build
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout

// Compositing effects, as one RenderEffect over the subtree.
//
// RenderEffect is API 31, which is why minSDK was raised from 28 -- see
// testapp/androidContainer/Bundler.android.toml. It is the only public way to blur or
// colour-adjust a live View subtree; everything else on Android either
// rasterises the view yourself or applies to a single drawable.
//
// 合成效果，實作為套用於整個子樹的單一 RenderEffect。
//
// RenderEffect 屬於 API 31，這正是 minSDK 由 28 調升的原因——見
// testapp/androidContainer/Bundler.android.toml。它是公開 API 中唯一能對一棵活的 View 子樹進行模糊或色彩
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
        invert: Boolean,
        blendMode: Int,
        shadowRed: Float,
        shadowGreen: Float,
        shadowBlue: Float,
        shadowAlpha: Float,
        shadowX: Float,
        shadowY: Float,
        shadowRadius: Float,
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
        // Before the early return below, which compares the filters only.
        // 在下方只比較濾鏡的提前返回之前。
        applyBlendMode(blendMode)

        // The direct path sets the effect every frame while opacity animates
        // (EffectAnimation.swift). When nothing but the opacity changed, the
        // RenderEffect already set still holds, so it is not rebuilt.
        // 直接路徑在 opacity 動畫期間每幀都設定效果(EffectAnimation.swift)。除了 opacity 什麼都沒變時，
        // 已設定的 RenderEffect 仍然適用，因此不重建。
        val filters = floatArrayOf(
            blurRadius, saturation, brightness, contrast, grayscale, hueRotationDegrees, if (invert) 1f else 0f,
            shadowRed, shadowGreen, shadowBlue, shadowAlpha, shadowX, shadowY, shadowRadius,
        )
        if (filters.contentEquals(lastFilters)) {
            return
        }
        lastFilters = filters

        // Grayscale through a shader when the platform has one (API 33), so it
        // is the grey AppKitBackend draws: CIColorMonochrome tinted 0.5 grey in
        // Core Image's linear working space, which maps luminance through an
        // overlay and comes out darker than saturation 0 -- AppKit's grey is
        // the reference (P39, 2026-10-16). A ColorMatrix is linear in the sRGB
        // values and cannot draw that curve, so on API 31 and 32 grayscale
        // stays the desaturation in the matrix below, the same grey as
        // saturation 0. Hue rotation then has to come after the shader, as on
        // AppKit, so it moves to a matrix of its own.
        //
        // 平台有 shader 時(API 33)以 shader 繪製灰階，使它成為 AppKitBackend 畫出的那種灰：在 Core Image
        // 線性工作空間中以 0.5 灰上色的 CIColorMonochrome,會把亮度經過 overlay 映射，比 saturation 0
        // 更暗——以 AppKit 為準(P39,2026-10-16)。ColorMatrix 對 sRGB 數值是線性的，畫不出
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

        // colorInvert() after every other colour adjustment, as on AppKit: 255 minus
        // each of red, green and blue on unpremultiplied colour; alpha is kept.
        // colorInvert() 在其他所有色彩調整之後(同 AppKit):在未預乘的顏色上，紅綠藍各自變為 255 減原值;alpha 不變。
        if (invert) {
            val inversion =
                RenderEffect.createColorFilterEffect(
                    ColorMatrixColorFilter(
                        ColorMatrix(
                            floatArrayOf(
                                -1f, 0f, 0f, 0f, 255f,
                                0f, -1f, 0f, 0f, 255f,
                                0f, 0f, -1f, 0f, 255f,
                                0f, 0f, 0f, 1f, 0f,
                            )
                        )
                    )
                )
            colourEffect =
                if (colourEffect == null) inversion
                else RenderEffect.createChainEffect(inversion, colourEffect)
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

        val content =
            when {
                blurEffect != null && colourEffect != null ->
                    RenderEffect.createChainEffect(colourEffect, blurEffect)
                blurEffect != null -> blurEffect
                else -> colourEffect
            }
        setRenderEffect(
            withShadow(content, shadowRed, shadowGreen, shadowBlue, shadowAlpha, shadowX, shadowY, shadowRadius)
        )
    }

    /// The blend mode ordinal applied last; 0 (normal) before the first.
    /// 上次套用的混合模式序號;第一次之前為 0(normal)。
    private var blendModeOrdinal = 0

    // blendMode(_:) as a hardware layer whose paint carries the blend mode: the
    // container, effects and all, is drawn into its own layer, and the layer is
    // composited onto what the parent has drawn behind it with the paint's mode --
    // View.setLayerPaint's documented use of the paint's blend mode. Normal removes
    // the layer.
    //
    // plusDarker has no android.graphics.BlendMode. On API 36 it is a
    // RuntimeXfermode with PLUS_DARKER_BLENDER's formula, made by reflection because this
    // module compiles against API 35. Below API 36 Android has no public way to
    // compute it, and it is drawn as MULTIPLY, the nearest mode that only darkens:
    // the same where either colour is black or white, lighter than plusDarker in
    // between.
    //
    // blendMode(_:) 以一個 hardware layer 實作，其 paint 帶有混合模式：容器(連同效果)畫進它自己的 layer,
    // 該 layer 再以 paint 的模式合成到父容器在其後方已畫好的內容上——即 View.setLayerPaint 文件所述 paint 混合模式的
    // 用途。normal 會移除該 layer。
    //
    // plusDarker 沒有對應的 android.graphics.BlendMode。在 API 36 上它是使用 PLUS_DARKER_BLENDER 公式的 RuntimeXfermode,因為本模組
    // 以 API 35 編譯，所以經由 reflection 建立。API 36 以下 Android 沒有公開的方式算出它，因此畫成 MULTIPLY——
    // 只會變暗的模式中最接近的一個：任一方為黑或白時兩者相同，介於其間時比 plusDarker 亮。
    private fun applyBlendMode(ordinal: Int) {
        if (ordinal == blendModeOrdinal) {
            return
        }
        blendModeOrdinal = ordinal
        if (ordinal <= 0 || ordinal >= BLEND_MODES.size) {
            setLayerType(View.LAYER_TYPE_NONE, null)
            return
        }
        val paint = Paint()
        val mode = BLEND_MODES[ordinal]
        if (mode != null) {
            paint.blendMode = mode
        } else if (ordinal == PLUS_DARKER) {
            val runtime =
                if (Build.VERSION.SDK_INT >= 36) {
                    try {
                        Class.forName("android.graphics.RuntimeXfermode")
                            .getConstructor(String::class.java)
                            .newInstance(PLUS_DARKER_BLENDER) as Xfermode
                    } catch (error: ReflectiveOperationException) {
                        null
                    }
                } else null
            if (runtime != null) {
                paint.xfermode = runtime
            } else {
                paint.blendMode = BlendMode.MULTIPLY
            }
        }
        setLayerType(View.LAYER_TYPE_HARDWARE, paint)
    }

    // shadow(color:radius:x:y:) in pixels, kept for onAttachedToWindow. / 以像素表示的
    // shadow(color:radius:x:y:),供 onAttachedToWindow 使用。
    private var hasShadow = false

    // The content with a drop shadow beneath it: the content tinted to the shadow colour
    // through its alpha, blurred, offset, and the content blended over it. The shadow is
    // cast by the content as the other effects leave it. An alpha of 0 returns the
    // content unchanged.
    // 下方帶有投影的內容：把內容依其透明度染成陰影色、模糊、位移，再把內容疊在上面。陰影由套用其他效果
    // 之後的內容投出。alpha 為 0 時原樣回傳內容。
    private fun withShadow(
        content: RenderEffect?,
        red: Float,
        green: Float,
        blue: Float,
        alpha: Float,
        dx: Float,
        dy: Float,
        radius: Float,
    ): RenderEffect? {
        hasShadow = alpha > 0f
        if (!hasShadow) {
            return content
        }
        allowShadowOutsideBounds()
        val tint =
            ColorMatrixColorFilter(
                ColorMatrix(
                    floatArrayOf(
                        0f, 0f, 0f, 0f, red * 255f,
                        0f, 0f, 0f, 0f, green * 255f,
                        0f, 0f, 0f, 0f, blue * 255f,
                        0f, 0f, 0f, alpha, 0f,
                    )
                )
            )
        var shadow =
            if (content == null) RenderEffect.createColorFilterEffect(tint)
            else RenderEffect.createColorFilterEffect(tint, content)
        if (radius > 0f) {
            shadow = RenderEffect.createBlurEffect(radius, radius, shadow, Shader.TileMode.DECAL)
        }
        shadow = RenderEffect.createOffsetEffect(dx, dy, shadow)
        val top = content ?: RenderEffect.createOffsetEffect(0f, 0f)
        return RenderEffect.createBlendModeEffect(shadow, top, BlendMode.SRC_OVER)
    }

    // A parent clips its children to their bounds by default, which would cut the shadow
    // off where it leaves this view, so the parent is told not to. / 父容器預設會把子 view 裁到
    // 其範圍內，陰影離開此 view 的部分會被切掉，因此告訴父容器不要裁切。
    private fun allowShadowOutsideBounds() {
        (parent as? ViewGroup)?.clipChildren = false
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (hasShadow) {
            allowShadowOutsideBounds()
        }
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
        // SwiftCrossUI's BlendMode cases in declaration order (the ordinal Swift
        // passes) as Android's BlendMode; null for normal, which needs no layer, and
        // for plusDarker, which Android has no BlendMode for (see applyBlendMode).
        // SwiftCrossUI BlendMode 依宣告順序(即 Swift 傳入的序號)對應的 Android BlendMode;normal 不需要
        // layer、plusDarker 在 Android 沒有對應的 BlendMode(見 applyBlendMode),兩者為 null。
        private val BLEND_MODES =
            arrayOf(
                null,
                BlendMode.MULTIPLY,
                BlendMode.SCREEN,
                BlendMode.OVERLAY,
                BlendMode.DARKEN,
                BlendMode.LIGHTEN,
                BlendMode.COLOR_DODGE,
                BlendMode.COLOR_BURN,
                BlendMode.SOFT_LIGHT,
                BlendMode.HARD_LIGHT,
                BlendMode.DIFFERENCE,
                BlendMode.EXCLUSION,
                BlendMode.HUE,
                BlendMode.SATURATION,
                BlendMode.COLOR,
                BlendMode.LUMINOSITY,
                BlendMode.SRC_ATOP,
                BlendMode.DST_OVER,
                BlendMode.DST_OUT,
                null,
                BlendMode.PLUS,
            )
        private const val PLUS_DARKER = 19

        // plusDarker on premultiplied colour: max(0, S + D - Sa Da) per channel, alpha
        // Sa + Da - Sa Da. Where D is opaque this is max(0, S + D - Sa), Core
        // Graphics' max(0, 1 - ((1 - D) + (1 - S))) for S over white -- what
        // GtkBackend draws -- and a transparent S leaves D as it is.
        // 預乘色彩上的 plusDarker:每個通道 max(0, S + D - Sa Da),alpha 為 Sa + Da - Sa Da。D 不透明時即
        // max(0, S + D - Sa),也就是 S 疊在白色上時 Core Graphics 的 max(0, 1 - ((1 - D) + (1 - S)))
        // ——GtkBackend 畫的就是這個——而透明的 S 讓 D 維持原樣。
        private const val PLUS_DARKER_BLENDER =
            """
            half4 main(half4 src, half4 dst) {
                half both = src.a * dst.a;
                return half4(max(half3(0.0), src.rgb + dst.rgb - half3(both)), src.a + dst.a - both);
            }
            """

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
