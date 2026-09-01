import AppKit
import CoreImage

@_spi(Backends) import SwiftCrossUI

/// Compositing effects, as one `CIFilter` chain on a layer-backed container.
///
/// The chain is rebuilt on every call rather than mutated, because
/// ``BackendFeatures/VisualEffects/setVisualEffect(_:ofWidget:)`` replaces the
/// container's whole effect. A backend that added to `layer.filters` would
/// compound the effect on every view update, which is the failure that
/// protocol's own documentation warns about.
///
/// 合成效果，實作為 layer-backed 容器上的單一條 `CIFilter` 鏈。
///
/// 每次呼叫都重建整條鏈，而非就地修改，因為
/// ``BackendFeatures/VisualEffects/setVisualEffect(_:ofWidget:)`` 取代的是該容器的完整效果。
/// 若 backend 改為往 `layer.filters` 累加，每次 view 更新都會讓效果不斷疊加——那正是該 protocol
/// 自己的文件所警告的失效模式。
extension AppKitBackend: BackendFeatures.VisualEffects {
    public func createVisualEffectContainer(wrapping child: Widget) -> Widget {
        let container = createContainer()
        insert(child, into: container, at: 0)
        // All four edges, so the child takes the container's size.
        //
        // Measured, after two wrong guesses. With no constraints at all the
        // cells were blank; with a left and top constraint they were still
        // blank, and the probe said why:
        //
        //     container=(0, 0, 200, 109)  child=(0, 109, 0, 0)  childConstraints=0
        //
        // The container is sized correctly and the child has no size at all.
        // ``VisualEffectModifier``'s commit sizes `widget`, which is this
        // container; nothing sizes what is inside it. That is invisible on
        // GtkBackend, where a container sizes its child for you, and it does not
        // arise in the ordinary case either, because there the layout system
        // owns both ends. A pass-through container inserted by a backend is the
        // one case with neither.
        //
        // Pinning all four edges makes the child follow the container, which is
        // what a pass-through means. It is safe here because the child arrives
        // with no size constraints of its own -- the probe above counted zero.
        //
        // 四個邊都釘住，讓子元件取得容器的尺寸。
        //
        // 這是量出來的，而且是在兩次猜錯之後。完全沒有約束時，各格是空白的；加上 left 與 top 約束
        // 之後仍然空白，而探測指出了原因（數值如上方英文所示）。
        //
        // 容器的尺寸是正確的，而子元件根本沒有尺寸。``VisualEffectModifier`` 的 commit 設定的是
        // `widget` 的尺寸，也就是這個容器；沒有任何東西為它內部的元件設定尺寸。這在 GtkBackend 上
        // 看不出來，因為那裡的容器會替你調整子元件的尺寸；在一般情況下也不會發生，因為版面系統同時
        // 掌握兩端。由 backend 插入的 pass-through 容器，正是兩者皆無的那個情況。
        //
        // 釘住四個邊會讓子元件跟隨容器，而那正是 pass-through 的意義。此處這麼做是安全的，因為子元件
        // 抵達時本身沒有任何尺寸約束——上述探測數到的是零。
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            child.topAnchor.constraint(equalTo: container.topAnchor),
            child.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            child.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        // Both flags, and both are required.
        //
        // `wantsLayer` gets a layer at all. `layerUsesCoreImageFilters` is the
        // one that is easy to miss: without it AppKit silently ignores
        // `layer.filters`, so every effect below would be built correctly,
        // assigned, and have no visible result -- which reads as the filters
        // being wrong rather than as being switched off.
        //
        // 兩個旗標缺一不可。
        //
        // `wantsLayer` 才會有 layer。`layerUsesCoreImageFilters` 則是容易漏掉的那一個：少了它，
        // AppKit 會靜默忽略 `layer.filters`，於是下方每一個效果都會被正確建立、正確指派，卻沒有
        // 任何可見結果——讀起來會像是 filter 寫錯了，而不是像它被關掉了。
        container.wantsLayer = true
        return container
    }

    public func setVisualEffect(_ effect: VisualEffect, ofWidget widget: Widget) {
        widget.wantsLayer = true

        // Opacity through `alphaValue`, not through a filter or `layer.opacity`.
        //
        // `alphaValue` composites the subtree as one group, so two half-opaque
        // siblings inside it do not show through each other -- which is what
        // SwiftUI's `.opacity` does, and what GtkBackend gets from
        // `gtk_widget_set_opacity` for the same reason. Per-layer opacity would
        // fade each descendant independently.
        //
        // 不透明度使用 `alphaValue`，而非 filter 或 `layer.opacity`。
        //
        // `alphaValue` 會把整個子樹當成一個群組來合成，因此其中兩個半透明的同層元件不會互相透出
        // ——那正是 SwiftUI 的 `.opacity` 的行為，也是 GtkBackend 基於同樣理由改用
        // `gtk_widget_set_opacity` 所得到的。逐 layer 的不透明度則會讓每個後代各自淡出。
        widget.alphaValue = CGFloat(effect.opacity)

        var filters: [CIFilter] = []

        // Blur first. It reads the pixels underneath it, so running it before
        // the colour adjustments blurs the original image rather than a
        // recoloured one -- the order SwiftUI's `.blur(radius:).saturation(0)`
        // produces by nesting.
        // 模糊排在最前。它讀取其下方的像素，因此在色彩調整之前執行，模糊到的是原始影像而非已被重新
        // 上色的影像——那正是 SwiftUI 的 `.blur(radius:).saturation(0)` 透過巢狀所產生的順序。
        if effect.blurRadius != 0 {
            if let blur = CIFilter(name: "CIGaussianBlur") {
                blur.setValue(effect.blurRadius, forKey: "inputRadius")
                filters.append(blur)
            }
        }

        // Saturation, brightness and contrast in one filter, because
        // `CIColorControls` is one filter that takes all three and applies them
        // in the order Core Image documents. Three separate filters would be
        // three passes with an order this file would have to choose.
        //
        // The defaults are the identity values Core Image uses -- saturation 1,
        // brightness 0, contrast 1 -- and they are the same as
        // ``VisualEffect``'s, so an untouched field costs nothing here.
        //
        // 飽和度、亮度與對比在同一個 filter 中處理，因為 `CIColorControls` 本身就是一個同時接受
        // 三者、並依 Core Image 所記載順序套用的 filter。拆成三個 filter 會變成三個 pass，而其
        // 順序將必須由本檔自行決定。
        //
        // 其預設值即 Core Image 的單位值——飽和度 1、亮度 0、對比 1——與 ``VisualEffect`` 的相同，
        // 因此未被更動的欄位在此不會產生任何代價。
        if effect.saturation != 1 || effect.brightness != 0 || effect.contrast != 1 {
            if let controls = CIFilter(name: "CIColorControls") {
                controls.setValue(effect.saturation, forKey: "inputSaturation")
                // Additive, and Core Image agrees. SwiftUI's `.brightness(_:)`
                // adds to each channel and so does `inputBrightness`, so this
                // passes straight through -- unlike CSS `filter: brightness()`,
                // which is multiplicative and centred on 1, and which
                // GtkBackend has to convert for.
                // 加法式，而 Core Image 的定義一致。SwiftUI 的 `.brightness(_:)` 是加到每個通道上，
                // `inputBrightness` 亦然，因此此處可直接傳遞——不同於 CSS 的
                // `filter: brightness()`，那是以 1 為中心的乘法，GtkBackend 必須為它做換算。
                controls.setValue(effect.brightness, forKey: "inputBrightness")
                controls.setValue(effect.contrast, forKey: "inputContrast")
                filters.append(controls)
            }
        }

        // Grayscale as a partial blend toward luminance, not as saturation 0.
        //
        // SwiftUI's `.grayscale(_:)` takes an amount, so it has to be able to
        // land halfway. Folding it into `inputSaturation` above would also make
        // it fight `.saturation(_:)` -- a view with both would get one value
        // where it asked for two effects.
        //
        // 灰階實作為「朝亮度方向的部分混合」，而非設定飽和度為 0。
        //
        // SwiftUI 的 `.grayscale(_:)` 接受一個程度值，因此它必須能停在中途。若把它折進上方的
        // `inputSaturation`，還會與 `.saturation(_:)` 互相打架——同時使用兩者的 view 會只得到一個
        // 數值，而它要求的是兩個效果。
        if effect.grayscale != 0 {
            if let monochrome = CIFilter(name: "CIColorMonochrome") {
                monochrome.setValue(
                    CIColor(red: 0.5, green: 0.5, blue: 0.5),
                    forKey: "inputColor"
                )
                monochrome.setValue(effect.grayscale, forKey: "inputIntensity")
                filters.append(monochrome)
            }
        }

        // Hue last, and in radians. `CIHueAdjust` takes an angle in radians
        // while ``Angle`` reports degrees, which is the kind of mismatch that
        // produces an effect roughly 57 times too strong and looks like the
        // filter being wrong.
        // 色相排在最後，且單位為弧度。`CIHueAdjust` 接受的角度單位是弧度，而 ``Angle`` 回報的是
        // 度數；這類不匹配會產生大約 57 倍過強的效果，看起來就像是 filter 寫錯了。
        if effect.hueRotation != .zero {
            if let hue = CIFilter(name: "CIHueAdjust") {
                hue.setValue(effect.hueRotation.radians, forKey: "inputAngle")
                filters.append(hue)
            }
        }

        // nil, not []. An empty array is still a filter chain and keeps the
        // layer on the Core Image path; nil takes it off.
        // 使用 nil 而非 []。空陣列仍然是一條 filter 鏈，會讓該 layer 留在 Core Image 的路徑上；
        // nil 才會讓它離開。
        // Core Image only when there is a filter to run.
        //
        // `layerUsesCoreImageFilters` was set unconditionally at first, and
        // every cell in P39 went blank -- including "none (control)", whose
        // effect is the identity. Putting a view on the Core Image path makes
        // AppKit render its subtree through that path whether or not any filter
        // is attached, and here that lost the subtree entirely. Setting it only
        // alongside a non-empty chain keeps the untouched case on the ordinary
        // drawing path, which is also what it should have been doing.
        //
        // 只有在確實有 filter 要執行時才啟用 Core Image。
        //
        // 起初 `layerUsesCoreImageFilters` 是無條件設定的，結果 P39 中每一格都變成空白——包括
        // 效果為單位值的「none (control)」。把一個 view 放上 Core Image 路徑，會讓 AppKit 無論是否
        // 附有任何 filter，都改由該路徑算繪其子樹；而在此處那使整個子樹消失。改為僅在鏈非空時一併
        // 設定，可讓未受影響的情況留在一般的繪製路徑上——那本來也就是它應有的行為。
        if filters.isEmpty {
            widget.layer?.filters = nil
            widget.layerUsesCoreImageFilters = false
        } else {
            widget.layerUsesCoreImageFilters = true
            widget.layer?.filters = filters
        }
    }
}
