import CoreImage
import UIKit

@_spi(Backends) import SwiftCrossUI

/// Compositing effects, rendered through Core Image because iOS will not
/// composite them.
///
/// The first version of this file was AppKitBackend's implementation with
/// `alpha` substituted for `alphaValue`: build a `[CIFilter]` and assign it to
/// `view.layer.filters`. That is the documented route on macOS and it does
/// nothing on iOS -- `CALayer.filters` exists in the headers on both platforms
/// and only the AppKit compositor reads it.
///
/// **That was measured twice rather than looked up.** P39 draws the same
/// angular gradient nine times and applies one effect to each, so a cell
/// identical to the control means the effect did nothing. On the iPhone 16
/// simulator, 2026-09-02: `opacity 0.35` was visibly faded and `blur 3`,
/// `saturation 2.5`, `brightness 0.4`, `grayscale 1` and `hueRotation 120` were
/// pixel-identical to the control. One of seven.
///
/// So the effects are applied to a rendering of the subtree instead:
///
/// 1. `CALayer.render(in:)` draws the live child into a bitmap.
/// 2. The `CIFilter` chain runs over that bitmap.
/// 3. The result becomes the contents of a layer laid over the child, and the
///    child is masked out.
///
/// **What this costs, stated plainly:** the visible pixels are a rendering
/// taken at a moment, not the live subtree. It is refreshed whenever the
/// container lays out -- which is every time SwiftCrossUI's view graph writes
/// a size or a position, so a state change inside a filtered container does
/// reach the screen -- but an animation running inside one, driven by Core
/// Animation rather than by the view graph, would be frozen at whatever frame
/// the last layout caught. `opacity` on its own does not take this path.
///
/// **The child stays interactive.** It is hidden with an empty `CALayer` mask
/// rather than with `alpha` or `isHidden`, because `UIView.hitTest` skips a
/// view whose alpha is at or below 0.01, and `alpha` and `isHidden` are both
/// stored on the layer -- there is no way to set them for drawing only. A mask
/// layer with no content is transparent everywhere, so the child draws nothing
/// and hit testing does not know the difference.
///
/// 合成效果，透過 Core Image 算繪，因為 iOS 不會為我們合成它們。
///
/// 本檔的第一版是 AppKitBackend 的實作，僅把 `alphaValue` 換成 `alpha`：建構一個 `[CIFilter]`
/// 並指派給 `view.layer.filters`。那在 macOS 上是有文件依據的做法，而在 iOS 上什麼都不會發生
/// ——`CALayer.filters` 在兩個平台的標頭檔中都存在，但只有 AppKit 的合成器會讀取它。
///
/// **這是量出來的，量了兩次，不是查來的。** P39 把同一張角度漸層畫了九次，每一格套用一種效果，
/// 因此某一格與對照格完全相同，就代表該效果沒有作用。2026-09-02 於 iPhone 16 模擬器上：
/// `opacity 0.35` 明顯變淡，而 `blur 3`、`saturation 2.5`、`brightness 0.4`、`grayscale 1`
/// 與 `hueRotation 120` 與對照格逐像素相同。七項中只有一項有效。
///
/// 因此改為把效果套用在「子樹的算繪結果」上：
///
/// 1. `CALayer.render(in:)` 把活的子元件畫進一張點陣圖。
/// 2. `CIFilter` 鏈在該點陣圖上執行。
/// 3. 結果成為一個覆蓋在子元件之上的 layer 的內容，而子元件被遮蔽。
///
/// **這麼做的代價，明說如下：** 看得見的像素是「某一刻的算繪結果」，而非活的子樹。它會在容器每次
/// 排版時重新產生——而那是 SwiftCrossUI 的 view graph 每次寫入尺寸或位置時都會發生的事，因此被
/// 過濾的容器內部若有狀態變更，確實會反映到畫面上——但若容器內有一個由 Core Animation 而非
/// view graph 驅動的動畫，它會凍結在最後一次排版所捕捉到的那一格。`opacity` 單獨使用時不走這條路。
///
/// **子元件仍可互動。** 它是以一個空的 `CALayer` mask 來隱藏，而非使用 `alpha` 或 `isHidden`，
/// 因為 `UIView.hitTest` 會跳過 alpha 小於等於 0.01 的 view，而 `alpha` 與 `isHidden` 兩者都
/// 儲存在 layer 上——沒有辦法只為「繪製」而設定它們。一個沒有內容的 mask layer 處處透明，因此
/// 子元件不會畫出任何東西，而 hit testing 察覺不到差別。
final class VisualEffectWidget: BaseViewWidget {
    /// One context for the whole backend. `CIContext` is expensive to build and
    /// safe to share, and a container per effect would pay for a GPU context
    /// per filtered view.
    /// 整個 backend 共用一個 context。`CIContext` 建構昂貴且可安全共用；若每個效果各建一個，
    /// 就等於每個被過濾的 view 都付出一個 GPU context 的代價。
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// A bare `CALayer`, not a `UIImageView`.
    ///
    /// Setting `UIImageView.image` invalidates the view's intrinsic content
    /// size, which marks the superview as needing layout, which runs this
    /// widget's `layoutSubviews`, which sets the image again. That is a loop
    /// with nothing to stop it. `CALayer.contents` invalidates nothing, and a
    /// layer cannot take a touch meant for the child underneath it either.
    ///
    /// 一個裸的 `CALayer`，而非 `UIImageView`。
    ///
    /// 設定 `UIImageView.image` 會使該 view 的 intrinsic content size 失效，進而把其 superview
    /// 標記為需要重新排版，於是本 widget 的 `layoutSubviews` 會執行，然後又設定一次 image。那是一個
    /// 沒有任何東西能終止的迴圈。`CALayer.contents` 不會使任何東西失效，而且 layer 也不會取走原本
    /// 要給其下方子元件的觸控。
    private let output = CALayer()

    /// An empty layer, reused. It has no content and no background, so every
    /// pixel of it is transparent, and a layer masked by it draws nothing.
    /// 一個空的 layer，重複使用。它沒有內容也沒有背景，因此每一個像素都是透明的；被它遮蔽的
    /// layer 不會畫出任何東西。
    private let hidingMask = CALayer()

    private var blurRadius: Double = 0
    private var colorFilters: [CIFilter] = []

    private var hasImageEffects: Bool { blurRadius != 0 || !colorFilters.isEmpty }

    override init() {
        super.init()

        output.contentsGravity = .resize
        output.contentsScale = UIScreen.main.scale
        layer.addSublayer(output)
    }

    func setEffect(_ effect: VisualEffect) {
        // Opacity through the view's alpha, which composites the subtree as one
        // group -- what SwiftUI's .opacity does, and the reason AppKit uses
        // alphaValue and GtkBackend gtk_widget_set_opacity rather than a
        // per-layer opacity that fades each descendant separately. It is also
        // the one effect iOS does composite, so it stays off the image path and
        // stays live.
        // 不透明度使用 view 的 alpha，它會把子樹當成一個群組來合成——那正是 SwiftUI 的 .opacity
        // 的行為，也是 AppKit 使用 alphaValue、GtkBackend 使用 gtk_widget_set_opacity，而非使用
        // 「讓每個後代各自淡出」的 per-layer 不透明度的理由。它同時也是 iOS 唯一真的會合成的效果，
        // 因此它不走影像那條路，也因而保持活的。
        alpha = CGFloat(effect.opacity)

        blurRadius = effect.blurRadius
        colorFilters = []

        // Saturation, brightness and contrast in one CIColorControls, which
        // takes all three and applies them in the order Core Image documents.
        // Its identity values are the same as VisualEffect's, so an untouched
        // field costs nothing.
        // 飽和度、亮度與對比合併於單一 CIColorControls，它同時接受三者並依 Core Image 所記載的
        // 順序套用。其單位值與 VisualEffect 的相同，因此未被更動的欄位不產生任何代價。
        if effect.saturation != 1 || effect.brightness != 0 || effect.contrast != 1 {
            if let controls = CIFilter(name: "CIColorControls") {
                controls.setValue(effect.saturation, forKey: "inputSaturation")
                controls.setValue(effect.brightness, forKey: "inputBrightness")
                controls.setValue(effect.contrast, forKey: "inputContrast")
                colorFilters.append(controls)
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
                colorFilters.append(monochrome)
            }
        }

        // Radians. `Angle` reports degrees, and the mismatch produces an effect
        // roughly 57 times too strong, which looks like the filter being wrong.
        // 弧度。`Angle` 回報的是度數，兩者不匹配會產生大約 57 倍過強的效果，看起來像是 filter 寫錯了。
        if effect.hueRotation != .zero {
            if let hue = CIFilter(name: "CIHueAdjust") {
                hue.setValue(effect.hueRotation.radians, forKey: "inputAngle")
                colorFilters.append(hue)
            }
        }

        refresh()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        refresh()
    }

    private func refresh() {
        guard hasImageEffects else {
            // Back to the live child. Reached when a modifier's values animate
            // down to identity, and cheap enough to do unconditionally.
            // 回到活的子元件。當某個 modifier 的值變動至單位值時會走到這裡，而且無條件執行也夠便宜。
            childHost?.layer.mask = nil
            output.contents = nil
            return
        }

        guard let child = childHost, bounds.width > 0, bounds.height > 0 else { return }

        // Laid out before it is drawn. Our `layoutSubviews` can run before the
        // child's, and rendering first would capture the previous pass.
        // 先排版再繪製。我們的 `layoutSubviews` 可能早於子元件的執行，先算繪會捕捉到上一輪的結果。
        child.layer.mask = nil
        child.layoutIfNeeded()

        let image = filtered(child)

        child.layer.mask = hidingMask

        // Frame and depth set here rather than once at init. A sublayer added
        // in `init` sits below the child's layer, because the child's view is
        // added afterwards and appends its layer above; re-adding moves this
        // one back to the end, which is the only way to keep it on top without
        // tracking the child's index.
        // frame 與層序在此設定，而非在 init 中一次設定。在 `init` 中加入的 sublayer 會位於子元件的
        // layer 之下，因為子元件的 view 是之後才加入、其 layer 被附加在上方；重新 add 會把這一個
        // 移回最後，而那是「不必追蹤子元件索引」就能讓它保持在最上層的唯一方式。
        output.frame = bounds
        layer.addSublayer(output)
        output.contents = image
    }

    /// The child's own view. `childWidgets` holds widgets and the image view is
    /// a plain subview, so this is the one place the two have to be told apart.
    /// 子元件自身的 view。`childWidgets` 存放的是 widget，而那個 image view 是一個普通的 subview，
    /// 因此這裡是唯一需要區分兩者的地方。
    private var childHost: UIView? { childWidgets.first?.view }

    private func filtered(_ child: UIView) -> CGImage? {
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return nil }

        let renderer = UIGraphicsImageRenderer(size: size)
        let source = renderer.image { context in
            child.layer.render(in: context.cgContext)
        }

        guard var image = CIImage(image: source) else { return nil }
        let extent = image.extent

        // Clamped before the blur and cropped after it. A Gaussian blur reads
        // outside its input, so without the clamp the edges fade into
        // transparency -- a blurred cell would be ringed in white against the
        // page -- and its output extent grows, so without the crop the image
        // view is handed something larger than the slot and scales it down.
        // 模糊之前先 clamp、之後再 crop。高斯模糊會讀取輸入之外的區域；少了 clamp，邊緣會淡入
        // 透明——被模糊的格子在頁面上會鑲一圈白邊——而它的輸出範圍會變大，少了 crop，image view
        // 拿到的就是比插槽更大的東西，並會把它縮小。
        if blurRadius != 0, let blur = CIFilter(name: "CIGaussianBlur") {
            blur.setValue(image.clampedToExtent(), forKey: kCIInputImageKey)
            blur.setValue(blurRadius, forKey: "inputRadius")
            if let output = blur.outputImage {
                image = output.cropped(to: extent)
            }
        }

        for filter in colorFilters {
            filter.setValue(image, forKey: kCIInputImageKey)
            guard let output = filter.outputImage else { continue }
            image = output
        }

        return Self.context.createCGImage(image, from: extent)
    }
}

extension UIKitBackend: BackendFeatures.VisualEffects {
    public func createVisualEffectContainer(wrapping child: Widget) -> Widget {
        let container = VisualEffectWidget()
        insert(child, into: container, at: 0)

        // All four edges, as on AppKit and Android. The modifier sizes the
        // container it is handed and nothing sizes what is inside it, so
        // without this the child resolves to zero by zero and the cell renders
        // empty -- which reads as the effect erasing its content.
        // 四個邊都釘住，與 AppKit、Android 相同。modifier 只設定它所拿到的容器的尺寸，沒有任何東西
        // 為其內部的元件設定尺寸；少了這一步，子元件會解析為 0x0，該格會算繪為空白——那讀起來像是
        // 效果抹除了自己的內容。
        let childView = child.view!
        childView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            childView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            childView.topAnchor.constraint(equalTo: container.topAnchor),
            childView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            childView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    public func setVisualEffect(_ effect: VisualEffect, ofWidget widget: Widget) {
        (widget as! VisualEffectWidget).setEffect(effect)
    }
}
