@_spi(Backends) import SwiftCrossUI
import AndroidKit
import SwiftJava

/// Compositing effects, as one `RenderEffect` over the subtree.
///
/// The work is in Kotlin, in `VisualEffectContainer.kt`, and not because Swift
/// could not do it: building a `ColorMatrix` needs five composed 4x5 matrices
/// and a hue rotation with hand-written luminance coefficients, and every one
/// of those crossing the JNI boundary as a separate call would be five
/// round-trips to assemble one value that is then thrown away and rebuilt on
/// the next update. One call carrying seven floats crosses once.
///
/// 合成效果，實作為套用於整個子樹的單一 `RenderEffect`。
///
/// 實作位於 Kotlin 的 `VisualEffectContainer.kt`，原因並非 Swift 做不到：建構一個 `ColorMatrix`
/// 需要五個組合而成的 4x5 矩陣，以及一個帶有手寫亮度係數的色相旋轉；若每一個都各自跨越 JNI 邊界，
/// 就會是五次往返，只為組出一個在下次更新時即被丟棄重建的值。一次呼叫帶著七個 float，只跨越一次。
@JavaClass(
    "dev.swiftcrossui.androidbackend.VisualEffectContainer",
    extends: AndroidKit.ViewGroup.self
)
class VisualEffectContainer: AndroidKit.ViewGroup {
    @JavaMethod
    @_nonoverride convenience init(
        _ activity: AndroidKit.Activity!,
        environment: JNIEnvironment? = nil
    )

    @JavaMethod
    func setVisualEffect(
        _ opacity: Float,
        _ blurRadius: Float,
        _ saturation: Float,
        _ brightness: Float,
        _ contrast: Float,
        _ grayscale: Float,
        _ hueRotationDegrees: Float
    )
}

extension AndroidBackend: BackendFeatures.VisualEffects {
    public func createVisualEffectContainer(wrapping child: Widget) -> Widget {
        let container = VisualEffectContainer(Self.activity, environment: Self.env)
        container.addView(child)
        return container.as(AndroidKit.View.self)!
    }

    public func setVisualEffect(_ effect: VisualEffect, ofWidget widget: Widget) {
        guard let container = widget.as(VisualEffectContainer.self) else { return }

        // The blur radius is scaled by display density; the rest are ratios and
        // are not.
        //
        // `blurRadius` is in points, and `RenderEffect.createBlurEffect` takes
        // pixels -- the same conversion `setSize` and `setCornerRadius` already
        // do in this backend. Saturation, brightness, contrast, grayscale and
        // hue have no length in them, so scaling any of those would be a
        // density-dependent colour, which is the kind of bug that only shows up
        // on one device.
        //
        // 只有模糊半徑需要乘上顯示密度，其餘皆為比值，不需要。
        //
        // `blurRadius` 的單位是點，而 `RenderEffect.createBlurEffect` 接受的是像素——這與本 backend
        // 中 `setSize` 與 `setCornerRadius` 已在做的是同一種換算。飽和度、亮度、對比、灰階與色相
        // 都不含長度量綱，因此對其中任何一個做縮放，都會造成「隨密度而變的顏色」——那正是只會在某一種
        // 裝置上才顯現的那類缺陷。
        let density = widget.getResources().getDisplayMetrics().density

        container.setVisualEffect(
            Float(effect.opacity),
            Float(effect.blurRadius) * density,
            Float(effect.saturation),
            Float(effect.brightness),
            Float(effect.contrast),
            Float(effect.grayscale),
            Float(effect.hueRotation.degrees)
        )
    }
}
