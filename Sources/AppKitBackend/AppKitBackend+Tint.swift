import AppKit
import CoreImage

@_spi(Backends) import SwiftCrossUI

/// `tint(_:)` on AppKit: a colour matrix on the control's own layer that moves
/// the system accent to the tint and leaves every neutral colour where it is.
///
/// NSSwitch, a checked NSButton checkbox and NSProgressIndicator take no colour
/// of their own: they draw `controlAccentColor`, and AppKit has no per-view
/// accent. NSSlider's `trackFillColor` and NSSegmentedControl's
/// `selectedSegmentBezelColor` exist, but one mechanism for every control keeps
/// the five alike. What these controls draw is the accent, neutrals (white
/// knob, grey track, text) and anti-aliased blends of the two, so a pixel's
/// distance from the grey axis along the accent's own direction says how much
/// accent it holds. The matrix
///
///     M = I + (T - A) dᵀ / |d|²,   d = A - mean(A)·(1, 1, 1)
///
/// sends A to T, sends every grey (dᵀg = 0) to itself, and sends a blend
/// a·A + (1 - a)·g to a·T + (1 - a)·g -- linear, so `CIColorMatrix` computes it.
/// It runs on sRGB-encoded values, as AppKit blends edges, between the same
/// encode and decode that colorInvert() uses here. A chromatic colour that is
/// not the accent moves as well, which is why only controls that draw nothing
/// of the app's go through it. With the Graphite accent the controls draw grey,
/// there is no direction to follow (d is 0), and they stay as AppKit draws
/// them for that setting.
///
/// AppKit 上的 `tint(_:)`:控制項自身 layer 上的一個色彩矩陣，把系統強調色移到 tint,所有中性色維持不動。
///
/// NSSwitch、勾選的 NSButton 核取方塊與 NSProgressIndicator 沒有自己的顏色屬性：它們畫的是
/// `controlAccentColor`,而 AppKit 沒有逐 view 的強調色。NSSlider 的 `trackFillColor` 與 NSSegmentedControl 的
/// `selectedSegmentBezelColor` 雖然存在，但所有控制項用同一個機制，五種才會一致。這些控制項畫的是強調色、中性色
/// (白色滑塊、灰色軌道、文字)以及兩者反鋸齒的混色，因此一個像素沿著強調色自身方向偏離灰軸的距離，就說明它含有多少強調色。
/// 上面的矩陣把 A 送到 T、把每個灰色(dᵀg = 0)送到自己，並把混色 a·A + (1 - a)·g 送到 a·T + (1 - a)·g——它是線性的，
/// 所以 `CIColorMatrix` 算得出來。它在 sRGB 編碼後的數值上執行(AppKit 就是在那裡混合邊緣),前後是此處 colorInvert()
/// 所用的同一組編碼與解碼。不是強調色的彩色也會跟著移動，所以只有不畫 app 任何內容的控制項才經過它。強調色是 Graphite 時控制項畫成灰色，
/// 沒有方向可循(d 為 0),它們維持 AppKit 在該設定下的畫法。
extension AppKitBackend {
    /// Applies the environment's tint to a control that draws the accent.
    /// 把 environment 的 tint 套到一個以強調色繪製的控制項上。
    func applyTint(of environment: EnvironmentValues, to control: NSView) {
        guard let tint = environment.tint else {
            // Only a control this put on the Core Image path is taken off it,
            // so an untinted control is never touched. 只把這裡放上 Core Image 路徑的控制項移下來，
            // 未加 tint 的控制項完全不碰。
            if control.layer?.filters != nil {
                control.layer?.filters = nil
                control.layerUsesCoreImageFilters = false
            }
            return
        }
        let target = tint.resolve(in: environment)
        var accent = SIMD3<Double>(0, 0.478, 1)
        control.effectiveAppearance.performAsCurrentDrawingAppearance {
            if let srgb = NSColor.controlAccentColor.usingColorSpace(.sRGB) {
                accent = SIMD3(
                    Double(srgb.redComponent),
                    Double(srgb.greenComponent),
                    Double(srgb.blueComponent)
                )
            }
        }
        // A translucent tint lands part of the way from the accent.
        // 半透明的 tint 只從強調色移動一部分。
        let opacity = Double(target.opacity)
        let tinted =
            accent
            + opacity
            * (SIMD3(Double(target.red), Double(target.green), Double(target.blue)) - accent)
        let mean = (accent.x + accent.y + accent.z) / 3
        let direction = accent - SIMD3(repeating: mean)
        let lengthSquared = (direction * direction).sum()
        guard lengthSquared > 1e-4,
            let encode = CIFilter(name: "CILinearToSRGBToneCurve"),
            let matrix = CIFilter(name: "CIColorMatrix"),
            let decode = CIFilter(name: "CISRGBToneCurveToLinear")
        else {
            control.layer?.filters = nil
            control.layerUsesCoreImageFilters = false
            return
        }
        let shift = (tinted - accent) / lengthSquared
        func row(_ index: Int) -> CIVector {
            var values = shift[index] * direction
            values[index] += 1
            return CIVector(x: values.x, y: values.y, z: values.z, w: 0)
        }
        matrix.setValue(row(0), forKey: "inputRVector")
        matrix.setValue(row(1), forKey: "inputGVector")
        matrix.setValue(row(2), forKey: "inputBVector")
        matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBiasVector")
        // Both flags, as in AppKitBackend+VisualEffects.swift: without
        // `layerUsesCoreImageFilters` AppKit ignores `layer.filters`.
        // 兩個旗標都要，與 AppKitBackend+VisualEffects.swift 相同：少了 `layerUsesCoreImageFilters`,
        // AppKit 會忽略 `layer.filters`。
        control.wantsLayer = true
        control.layerUsesCoreImageFilters = true
        control.layer?.filters = [encode, matrix, decode]
    }
}
