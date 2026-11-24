/// How a view's rendered pixels combine with what is drawn behind it, as SwiftUI's
/// `BlendMode`. Set with ``View/blendMode(_:)``.
///
/// In the formulas below, S is the view's colour (the source) and D the colour
/// already drawn behind it (the destination), each channel from 0 to 1. The
/// separable modes work on each of red, green and blue on its own; hue, saturation,
/// color and luminosity mix whole colours. Where S is transparent the destination
/// shows through unchanged, so a blend only changes what the view covers.
///
/// "Behind" is what the platform's compositor has drawn before the view: the views
/// behind it in the same window. See each backend's `setVisualEffect(_:ofWidget:)`
/// for how it reaches those pixels, and for the modes a platform draws another way.
///
/// view 繪製出的像素如何與它後方已畫好的內容結合，即 SwiftUI 的 `BlendMode`。以 ``View/blendMode(_:)``
/// 設定。
///
/// 下列公式中，S 是 view 的顏色(來源),D 是它後方已畫好的顏色(目的地),每個通道介於 0 與 1。可分離的模式
/// 對紅、綠、藍各自獨立運算;hue、saturation、color 與 luminosity 則混合整個顏色。S 透明之處目的地原樣
/// 透出，因此混合只改變 view 所覆蓋的地方。
///
/// 「後方」是平台合成器在該 view 之前已畫好的內容：同一視窗中位於其後方的 view。各 backend 如何取得那些像素，
/// 以及某平台以其他方式畫出的模式，見各 backend 的 `setVisualEffect(_:ofWidget:)`。
public enum BlendMode: Hashable, Sendable, CaseIterable {
    /// S drawn over D: no blending. / S 畫在 D 之上：不混合。
    case normal
    /// S × D: never lighter than either. / S × D:不會比任一方亮。
    case multiply
    /// 1 − (1 − S)(1 − D): never darker than either. / 1 − (1 − S)(1 − D):不會比任一方暗。
    case screen
    /// Multiply where D is dark, screen where D is light. / D 暗處做 multiply,亮處做 screen。
    case overlay
    /// min(S, D). / min(S, D)。
    case darken
    /// max(S, D). / max(S, D)。
    case lighten
    /// D ÷ (1 − S): brightens D towards S. / D ÷ (1 − S):把 D 往 S 提亮。
    case colorDodge
    /// 1 − (1 − D) ÷ S: darkens D towards S. / 1 − (1 − D) ÷ S:把 D 往 S 壓暗。
    case colorBurn
    /// Darkens or lightens D by S, softly. / 依 S 柔和地壓暗或提亮 D。
    case softLight
    /// Multiply where S is dark, screen where S is light. / S 暗處做 multiply,亮處做 screen。
    case hardLight
    /// |S − D|. / |S − D|。
    case difference
    /// S + D − 2SD: difference with less contrast. / S + D − 2SD:對比較低的 difference。
    case exclusion
    /// S's hue with D's saturation and luminosity. / S 的色相，配上 D 的飽和度與亮度。
    case hue
    /// S's saturation with D's hue and luminosity. / S 的飽和度，配上 D 的色相與亮度。
    case saturation
    /// S's hue and saturation with D's luminosity. / S 的色相與飽和度，配上 D 的亮度。
    case color
    /// S's luminosity with D's hue and saturation. / S 的亮度，配上 D 的色相與飽和度。
    case luminosity
    /// S drawn only where D is, over D: D's alpha is kept.
    /// S 只畫在 D 存在之處、疊在 D 上:D 的 alpha 不變。
    case sourceAtop
    /// D drawn over S: the view shows only where D is transparent.
    /// D 畫在 S 之上:view 只在 D 透明之處看得見。
    case destinationOver
    /// D erased where S is opaque; S itself is not drawn.
    /// S 不透明之處的 D 被擦除;S 本身不畫出。
    case destinationOut
    /// max(0, S + D − 1): a sum that darkens. / max(0, S + D − 1):會變暗的相加。
    case plusDarker
    /// min(1, S + D): a sum that lightens. / min(1, S + D):會變亮的相加。
    case plusLighter
}
