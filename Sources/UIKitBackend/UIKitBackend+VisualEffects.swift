import CoreImage
import UIKit

@_spi(Backends) import SwiftCrossUI

/// Compositing effects, as one `CIFilter` chain on the container's layer.
///
/// This is AppKitBackend's implementation with two differences: `alpha` rather
/// than `alphaValue`, and no `layerUsesCoreImageFilters` — that flag is AppKit's
/// and UIKit has no equivalent.
///
/// **Whether `CALayer.filters` composites on iOS is measured, not assumed.** I
/// declined to implement this once on the grounds that it does not, and that
/// decline was rejected. The way to settle it is to write the chain and look at
/// P39, whose nine cells each apply one effect to the same angular gradient and
/// are readable against the control at a glance. If a cell is identical to the
/// control, that effect did nothing.
///
/// 合成效果，實作為容器 layer 上的單一條 `CIFilter` 鏈。
///
/// 這就是 AppKitBackend 的實作，只有兩處不同：使用 `alpha` 而非 `alphaValue`，以及沒有
/// `layerUsesCoreImageFilters`——那個旗標屬於 AppKit，UIKit 沒有對應者。
///
/// **`CALayer.filters` 在 iOS 上是否參與合成，是量出來的，不是假設的。** 我曾以「它不參與」為由
/// 拒絕實作本項，而該拒絕未被接受。要定案的方式，就是把這條鏈寫出來，然後去看 P39——它的九個格子
/// 各對同一張角度漸層套用一種效果，與對照格並排即可一眼判讀。若某一格與對照格完全相同，該效果
/// 就是沒有作用。
extension UIKitBackend: BackendFeatures.VisualEffects {
    public func createVisualEffectContainer(wrapping child: Widget) -> Widget {
        let container = createContainer()
        insert(child, into: container, at: 0)

        // All four edges, as on AppKit and Android. The modifier sizes the
        // container it is handed and nothing sizes what is inside it, so
        // without this the child resolves to zero by zero and the cell renders
        // empty -- which reads as the effect erasing its content.
        // 四個邊都釘住，與 AppKit、Android 相同。modifier 只設定它所拿到的容器的尺寸，沒有任何東西
        // 為其內部的元件設定尺寸；少了這一步，子元件會解析為 0x0，該格會算繪為空白——那讀起來像是
        // 效果抹除了自己的內容。
        let childView = child.view!
        let containerView = container.view!
        childView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            childView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            childView.topAnchor.constraint(equalTo: containerView.topAnchor),
            childView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            childView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])
        return container
    }

    public func setVisualEffect(_ effect: VisualEffect, ofWidget widget: Widget) {
        let view = widget.view!

        // Opacity through the view's alpha, which composites the subtree as one
        // group -- what SwiftUI's .opacity does, and the reason AppKit uses
        // alphaValue and GtkBackend gtk_widget_set_opacity rather than a
        // per-layer opacity that fades each descendant separately.
        // 不透明度使用 view 的 alpha，它會把子樹當成一個群組來合成——那正是 SwiftUI 的 .opacity 的
        // 行為，也是 AppKit 使用 alphaValue、GtkBackend 使用 gtk_widget_set_opacity，而非使用
        // 「讓每個後代各自淡出」的 per-layer 不透明度的理由。
        view.alpha = CGFloat(effect.opacity)

        var filters: [CIFilter] = []

        // Blur first, so it reads the original pixels rather than recoloured
        // ones -- the order SwiftUI's .blur(radius:).saturation(0) produces by
        // nesting.
        // 模糊排在最前，使它讀到的是原始像素而非已重新上色的像素——那正是 SwiftUI 的
        // .blur(radius:).saturation(0) 透過巢狀所產生的順序。
        if effect.blurRadius != 0 {
            if let blur = CIFilter(name: "CIGaussianBlur") {
                blur.setValue(effect.blurRadius, forKey: "inputRadius")
                filters.append(blur)
            }
        }

        // Saturation, brightness and contrast in one CIColorControls, which
        // takes all three and applies them in the order Core Image documents.
        // Its identity values are the same as VisualEffect's, so an untouched
        // field costs nothing.
        // 飽和度、亮度與對比合併於單一 CIColorControls，它同時接受三者並依 Core Image 所記載的順序
        // 套用。其單位值與 VisualEffect 的相同，因此未被更動的欄位不產生任何代價。
        if effect.saturation != 1 || effect.brightness != 0 || effect.contrast != 1 {
            if let controls = CIFilter(name: "CIColorControls") {
                controls.setValue(effect.saturation, forKey: "inputSaturation")
                controls.setValue(effect.brightness, forKey: "inputBrightness")
                controls.setValue(effect.contrast, forKey: "inputContrast")
                filters.append(controls)
            }
        }

        // Grayscale separately from saturation, because SwiftUI's
        // .grayscale(_:) takes an amount and has to be able to land halfway.
        // 灰階與飽和度分開處理，因為 SwiftUI 的 .grayscale(_:) 接受一個程度值，必須能停在中途。
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

        // Radians. `Angle` reports degrees, and the mismatch produces an effect
        // roughly 57 times too strong, which looks like the filter being wrong.
        // 弧度。`Angle` 回報的是度數，兩者不匹配會產生大約 57 倍過強的效果，看起來像是 filter 寫錯了。
        if effect.hueRotation != .zero {
            if let hue = CIFilter(name: "CIHueAdjust") {
                hue.setValue(effect.hueRotation.radians, forKey: "inputAngle")
                filters.append(hue)
            }
        }

        // nil, not []. An empty array is still a chain and keeps the layer on
        // the Core Image path.
        // 使用 nil 而非 []。空陣列仍是一條鏈，會讓該 layer 留在 Core Image 的路徑上。
        view.layer.filters = filters.isEmpty ? nil : filters
    }
}
