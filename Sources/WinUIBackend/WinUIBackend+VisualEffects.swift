import CWinRT
import Foundation
import Mutex
@_spi(Backends) import SwiftCrossUI
@_spi(WinRTInternal) import UWP
@_spi(WinRTInternal) import WinAppSDK
import WinSDK
import WinUIInterop
@_spi(WinRTInternal) import WinUI
@_spi(WinRTInternal) @preconcurrency import WindowsFoundation

private let visualEffectChildren = Mutex<[UInt: WinUIVisualEffectChild]>([:])
/// The non-opacity part of the effect each widget's graph was last built for.
/// 每個 widget 的效果圖上次建立時，效果中 opacity 以外的部分。
private let visualEffectLastFilters = Mutex<[UInt: VisualEffect]>([:])
private let visualEffectStates = Mutex<[UInt: WinUIVisualEffectState]>([:])

/// The DropShadow behind one effect container: a host Canvas under the child (ZIndex
/// -1, after it in the children so the child keeps index 0), whose child visual casts
/// a shadow masked by a surface of the child's visual -- so the shadow follows the
/// child's alpha, not its frame.
/// 一個效果容器後方的 DropShadow:子元件下方的宿主 Canvas(ZIndex -1,排在子元件之後，讓子元件保有
/// index 0),其 child visual 以子元件 visual 的表面為遮罩投出陰影——因此陰影跟著子元件的透明度，而不是它的框。
private final class WinUIShadowState: @unchecked Sendable {
    let host: WinUI.Canvas
    let surface: WinAppSDK.CompositionVisualSurface
    let dropShadow: WinAppSDK.DropShadow
    let mask: WinAppSDK.CompositionSurfaceBrush
    let sprite: WinAppSDK.SpriteVisual

    init(
        host: WinUI.Canvas,
        surface: WinAppSDK.CompositionVisualSurface,
        dropShadow: WinAppSDK.DropShadow,
        mask: WinAppSDK.CompositionSurfaceBrush,
        sprite: WinAppSDK.SpriteVisual
    ) {
        self.host = host
        self.surface = surface
        self.dropShadow = dropShadow
        self.mask = mask
        self.sprite = sprite
    }

    /// Follows the container's size: the host, and the surface the mask is cut from.
    /// 跟隨容器的尺寸：宿主，以及遮罩所取自的表面。
    @MainActor func resize(to container: WinUI.FrameworkElement) {
        let width = max(0, container.width.isNaN ? container.actualWidth : container.width)
        let height = max(0, container.height.isNaN ? container.actualHeight : container.height)
        host.width = width
        host.height = height
        surface.sourceSize = WindowsFoundation.Vector2(x: Float(width), y: Float(height))
    }
}

private let visualEffectShadows = Mutex<[UInt: WinUIShadowState]>([:])

private struct WinUIVisualEffectChild: @unchecked Sendable {
    nonisolated(unsafe) let widget: WinUI.FrameworkElement
}

private final class WinUIVisualEffectState: @unchecked Sendable {
    var sourceSurface: WinAppSDK.CompositionVisualSurface
    var sourceBrush: WinAppSDK.CompositionSurfaceBrush
    var effectFactory: WinAppSDK.CompositionEffectFactory
    var effectBrush: WinAppSDK.CompositionEffectBrush
    var spriteVisual: WinAppSDK.SpriteVisual
    var effectObjects: [Any]

    init(
        sourceSurface: WinAppSDK.CompositionVisualSurface,
        sourceBrush: WinAppSDK.CompositionSurfaceBrush,
        effectFactory: WinAppSDK.CompositionEffectFactory,
        effectBrush: WinAppSDK.CompositionEffectBrush,
        spriteVisual: WinAppSDK.SpriteVisual,
        effectObjects: [Any]
    ) {
        self.sourceSurface = sourceSurface
        self.sourceBrush = sourceBrush
        self.effectFactory = effectFactory
        self.effectBrush = effectBrush
        self.spriteVisual = spriteVisual
        self.effectObjects = effectObjects
    }
}

extension WinUIBackend: BackendFeatures.VisualEffects {
    public func createVisualEffectContainer(wrapping child: Widget) -> Widget {
        let container = createContainer()
        insert(child, into: container, at: 0)
        visualEffectChildren.withLock { children in
            children[winUIVisualEffectKey(container)] = WinUIVisualEffectChild(widget: child)
        }
        return container
    }

    public func setVisualEffect(_ effect: VisualEffect, ofWidget widget: Widget) {
        widget.opacity = effect.opacity

        let key = winUIVisualEffectKey(widget)
        // shadow(color:radius:x:y:) is drawn by its own DropShadow beneath the child (see
        // applyShadow); the filter graph below never sees it. / shadow(color:radius:x:y:) 由它自己的
        // DropShadow 畫在子元件下方(見 applyShadow);下方的濾鏡圖不會看到它。
        applyShadow(effect.shadow, to: widget, key: key)
        var effect = effect
        effect.shadow = nil

        // The direct path sets the effect every frame while opacity animates
        // (EffectAnimation.swift). When only the opacity changed, the effect graph
        // built for the rest still holds: Opacity, set above, is all there is to do.
        // 直接路徑在 opacity 動畫期間每幀都設定效果(EffectAnimation.swift)。只有 opacity 改變時，為其餘
        // 部分建好的效果圖仍然適用：上面設好的 Opacity 就是全部要做的事。
        var filters = effect
        filters.opacity = 1
        let unchanged = visualEffectLastFilters.withLock { last in
            let same = !filters.needsOnlyOpacity && last[key] == filters
            last[key] = filters.needsOnlyOpacity ? nil : filters
            return same
        }
        if unchanged, visualEffectStates.withLock({ $0[key] != nil }) {
            return
        }
        if effect.needsOnlyOpacity {
            try? WinUIElementCompositionPreview.setElementChildVisual(of: widget, to: nil)
            visualEffectChildren.withLock { children in
                children[key]?.widget.opacity = 1
            }
            visualEffectStates.withLock { states in
                states[key] = nil
            }
            return
        }

        guard let child = visualEffectChildren.withLock({ $0[key] })?.widget
        else {
            return
        }

        do {
            guard let sourceVisual = try child.getVisualInternal(),
                  let compositor = sourceVisual.compositor
            else {
                throw WinUIVisualEffectError.emptyEffectGraph
            }
            guard let sourceSurface = try compositor.createVisualSurface() else {
                throw WinUIVisualEffectError.emptyEffectGraph
            }
            sourceSurface.sourceVisual = sourceVisual
            sourceSurface.sourceSize = widget.actualVectorSize

            guard let sourceBrush = try compositor.createSurfaceBrush(sourceSurface) else {
                throw WinUIVisualEffectError.emptyEffectGraph
            }
            let graph = try D2DEffectGraph(effect: effect)
            guard let effectFactory = try compositor.createEffectFactory(graph.rootEffect),
                  let effectBrush = try effectFactory.createBrush()
            else {
                throw WinUIVisualEffectError.emptyEffectGraph
            }
            try effectBrush.setSourceParameter("source", sourceBrush)
            // blendMode(_:)'s destination: what the compositor has drawn behind the
            // sprite. The child is at opacity 0 below, so it is not part of it.
            // blendMode(_:) 的目的地：合成器在 sprite 後方已畫好的內容。子元件在下方被設為 opacity 0,所以不在其中。
            if graph.usesBackdrop {
                guard let backdrop = try compositor.createBackdropBrush() else {
                    throw WinUIVisualEffectError.emptyEffectGraph
                }
                try effectBrush.setSourceParameter("backdrop", backdrop)
            }
            guard let spriteVisual = try compositor.createSpriteVisual() else {
                throw WinUIVisualEffectError.emptyEffectGraph
            }
            spriteVisual.brush = effectBrush
            spriteVisual.relativeSizeAdjustment = WindowsFoundation.Vector2(x: 0, y: 0)
            spriteVisual.size = widget.actualVectorSize
            spriteVisual.clip = try compositor.createInsetClip(0, 0, 0, 0)
            try WinUIElementCompositionPreview.setElementChildVisual(of: widget, to: spriteVisual)
            child.opacity = 0

            visualEffectStates.withLock { states in
                states[key] = WinUIVisualEffectState(
                    sourceSurface: sourceSurface,
                    sourceBrush: sourceBrush,
                    effectFactory: effectFactory,
                    effectBrush: effectBrush,
                    spriteVisual: spriteVisual,
                    effectObjects: graph.effectObjects
                )
            }
            // The denominator. Logging only failures cannot distinguish "one
            // effect failed" from "only one effect was ever attempted", and a
            // run cut short by a timeout produces the second while looking
            // exactly like the first.
            // 分母。只記錄失敗，就無法分辨「有一個效果失敗」與「總共只嘗試了一個效果」，
            // 而被逾時中斷的執行會產生後者，外觀卻與前者一模一樣。
            winUIVisualEffectDebug("effect applied [\(effect.debugSummary)]")
        } catch {
            // Never fail silently here. The recovery below removes the child
            // visual, so an effect that could not be built renders as an
            // untouched view -- which looks exactly like a backend that chose
            // not to apply the effect rather than one that tried and failed.
            // P39's whole design is comparing cells against a control, and that
            // comparison reads a failed cell as "this effect does nothing".
            // 此處絕不可安靜失敗。下方的復原會移除 child visual，因此一個建不起來的效果會
            // 呈現為未經處理的畫面——而那看起來就和「backend 選擇不套用此效果」一模一樣，
            // 而非「它試了但失敗」。P39 的整個設計就是拿各格與對照組相比，而那個比較會把
            // 失敗的一格讀成「這個效果沒有作用」。
            winUIVisualEffectDebug(
                "effect failed for key \(key) [\(effect.debugSummary)]: \(error)"
            )
            try? WinUIElementCompositionPreview.setElementChildVisual(of: widget, to: nil)
            visualEffectStates.withLock { states in
                states[key] = nil
            }
        }
    }
}

private extension SwiftCrossUI.BlendMode {
    /// The Direct2D node that draws this mode -- the effect kind, its mode property
    /// and the mode -- or nil for normal, which needs none.
    ///
    /// Blend's own modes cover multiply through luminosity; plusLighter is its
    /// LINEAR_DODGE, min(1, S + D), and plusDarker its LINEAR_BURN,
    /// max(0, S + D - 1). sourceAtop, destinationOver and destinationOut are
    /// Porter-Duff operators, drawn by Composite.
    ///
    /// One gap, stated precisely: the result is a sprite drawn over the backdrop it
    /// was computed from, and Composition cannot erase the visuals underneath it. So
    /// destinationOut, which erases the backdrop where the view is opaque, computes
    /// the erased backdrop and draws it over the untouched one -- the cell looks as
    /// if nothing were drawn there, instead of showing what lies behind the
    /// backdrop. Every other mode's result covers the backdrop where the view is and
    /// equals it elsewhere, so drawing it over the backdrop is exact wherever the
    /// backdrop is opaque.
    ///
    /// 畫出此模式的 Direct2D 節點——效果種類、其模式屬性與模式值——normal 不需要節點，為 nil。
    ///
    /// Blend 自身的模式涵蓋 multiply 到 luminosity;plusLighter 是它的 LINEAR_DODGE,即 min(1, S + D),plusDarker
    /// 是它的 LINEAR_BURN,即 max(0, S + D - 1)。sourceAtop、destinationOver 與 destinationOut 是 Porter-Duff
    /// 運算子，由 Composite 繪製。
    ///
    /// 唯一的缺口，明確說明如下：結果是一個畫在「用來計算它的背景」之上的 sprite,而 Composition 無法擦除其下方的
    /// visual。因此 destinationOut(在 view 不透明處擦除背景)算出了擦除後的背景，卻把它畫在未被改動的背景上——
    /// 該格看起來像什麼都沒畫，而不是露出背景後方的內容。其他每種模式的結果在 view 所在處覆蓋背景、其餘處等於背景，
    /// 因此只要背景不透明，畫在背景之上就完全精確。
    var direct2D: (kind: Int, property: Int, mode: Int)? {
        let blend = { (mode: Int) in (SCUI_EFFECT_BLEND, SCUI_D2DBLEND_MODE, mode) }
        let composite = { (mode: Int) in (SCUI_EFFECT_COMPOSITE, SCUI_D2DCOMPOSITE_MODE, mode) }
        switch self {
            case .normal: return nil
            case .multiply: return blend(SCUI_D2DBLEND_MULTIPLY)
            case .screen: return blend(SCUI_D2DBLEND_SCREEN)
            case .overlay: return blend(SCUI_D2DBLEND_OVERLAY)
            case .darken: return blend(SCUI_D2DBLEND_DARKEN)
            case .lighten: return blend(SCUI_D2DBLEND_LIGHTEN)
            case .colorDodge: return blend(SCUI_D2DBLEND_COLOR_DODGE)
            case .colorBurn: return blend(SCUI_D2DBLEND_COLOR_BURN)
            case .softLight: return blend(SCUI_D2DBLEND_SOFT_LIGHT)
            case .hardLight: return blend(SCUI_D2DBLEND_HARD_LIGHT)
            case .difference: return blend(SCUI_D2DBLEND_DIFFERENCE)
            case .exclusion: return blend(SCUI_D2DBLEND_EXCLUSION)
            case .hue: return blend(SCUI_D2DBLEND_HUE)
            case .saturation: return blend(SCUI_D2DBLEND_SATURATION)
            case .color: return blend(SCUI_D2DBLEND_COLOR)
            case .luminosity: return blend(SCUI_D2DBLEND_LUMINOSITY)
            case .sourceAtop: return composite(SCUI_D2DCOMPOSITE_SOURCE_ATOP)
            case .destinationOver: return composite(SCUI_D2DCOMPOSITE_DESTINATION_OVER)
            case .destinationOut: return composite(SCUI_D2DCOMPOSITE_DESTINATION_OUT)
            case .plusDarker: return blend(SCUI_D2DBLEND_LINEAR_BURN)
            case .plusLighter: return blend(SCUI_D2DBLEND_LINEAR_DODGE)
        }
    }
}

private extension VisualEffect {
    var needsOnlyOpacity: Bool {
        blurRadius == 0
            && saturation == 1
            && brightness == 0
            && contrast == 1
            && grayscale == 0
            && hueRotation == .zero
            && !colorInvert
            && blendMode == .normal
    }

    /// The non-default components, for a diagnostic that names the effect.
    ///
    /// The widget key alone is a pointer value: it can prove that two of
    /// P39's nine cells failed but not which two. A failure that cannot say
    /// what it was given costs a whole run to re-derive.
    /// 列出非預設的成分，使診斷能指名是哪一個效果。
    ///
    /// 只有 widget key 時，那是一個指標值：足以證明 P39 九格中有兩格失敗，卻無法指出是哪兩格。
    /// 一個說不出自己收到什麼的失敗，要花掉一整輪執行才能重新推導出來。
    var debugSummary: String {
        var parts: [String] = []
        if blurRadius != 0 { parts.append("blur \(blurRadius)") }
        if saturation != 1 { parts.append("saturation \(saturation)") }
        if brightness != 0 { parts.append("brightness \(brightness)") }
        if contrast != 1 { parts.append("contrast \(contrast)") }
        if grayscale != 0 { parts.append("grayscale \(grayscale)") }
        if hueRotation != .zero { parts.append("hueRotation \(hueRotation.degrees)") }
        if colorInvert { parts.append("colorInvert") }
        if blendMode != .normal { parts.append("blendMode \(blendMode)") }
        return parts.isEmpty ? "identity" : parts.joined(separator: ", ")
    }
}

private typealias D2DSource = UnsafeMutablePointer<
    __x_ABI_CWindows_CGraphics_CEffects_CIGraphicsEffectSource
>?

private struct D2DEffectGraph {
    let rootEffect: UWP.AnyIGraphicsEffect
    let effectObjects: [Any]
    /// Whether the graph has a "backdrop" source to bind (blendMode(_:)).
    /// 效果圖是否有需要繫結的 "backdrop" 來源(blendMode(_:))。
    let usesBackdrop: Bool

    init(effect: VisualEffect) throws {
        let sourceParameter = WinAppSDK.CompositionEffectSourceParameter("source")
        guard let sourceParameterWrapper =
            __ABI_Windows_Graphics_Effects.IGraphicsEffectSourceWrapper(sourceParameter)
        else {
            throw WinUIVisualEffectError.emptyEffectGraph
        }
        var currentSource: D2DSource = nil
        var currentRoot: UWP.AnyIGraphicsEffect?
        var objects: [Any] = [sourceParameterWrapper]
        try sourceParameterWrapper.toABI { sourceParameterABI in
            currentSource = sourceParameterABI
        }

        func append(_ node: D2DEffect) throws {
            let object = node.object
            let graphicsEffect: __ABI_Windows_Graphics_Effects.IGraphicsEffect =
                try object.QueryInterface()
            currentRoot = __IMPL_Windows_Graphics_Effects.IGraphicsEffectBridge.from(
                abi: RawPointer(graphicsEffect)
            )
            let graphicsEffectSource: __ABI_Windows_Graphics_Effects.IGraphicsEffectSource =
                try object.QueryInterface()
            let sourcePointer: UnsafeMutablePointer<
                __x_ABI_CWindows_CGraphics_CEffects_CIGraphicsEffectSource
            > = RawPointer(graphicsEffectSource)
            currentSource = sourcePointer
            objects.append(object)
        }

        // A Direct2D colour matrix, row-major 5x4 (the fifth row is added), in
        // premultiplied alpha mode: the effect un-premultiplies, applies the matrix and
        // premultiplies again, so alpha is kept and edges are not darkened.
        // Direct2D 的色彩矩陣，逐列的 5x4(第五列為加上的常數),採預乘 alpha 模式：效果先解除預乘、套用矩陣、
        // 再預乘回去，因此 alpha 不變，邊緣也不會變暗。
        func colorMatrix(_ matrix: [Float], clamp: Bool, from source: D2DSource) throws -> D2DSource {
            let node = try D2DEffect(SCUI_EFFECT_COLOR_MATRIX, sources: [source])
            try node.set(SCUI_COLORMATRIX_MATRIX, .singles(matrix))
            try node.set(SCUI_COLORMATRIX_ALPHA_MODE, .uint(SCUI_COLORMATRIX_ALPHA_PREMULTIPLIED))
            try node.set(SCUI_COLORMATRIX_CLAMP, .boolean(clamp))
            try append(node)
            return currentSource
        }

        if effect.blurRadius != 0 {
            let blur = try D2DEffect(SCUI_EFFECT_GAUSSIAN_BLUR, sources: [currentSource])
            try blur.set(SCUI_BLUR_DEVIATION, .single(Float(effect.blurRadius)))
            try blur.set(SCUI_BLUR_OPTIMIZATION, .uint(SCUI_BLUR_OPTIMIZATION_BALANCED))
            try blur.set(SCUI_BLUR_BORDER_MODE, .uint(SCUI_BLUR_BORDER_SOFT))
            try append(blur)
        }

        if effect.saturation != 1 {
            // A colour matrix, not Direct2D's saturation effect, because that effect
            // cannot express oversaturation: its property range stops at 1, so P39's
            // "saturation 2.5" cell was rejected with 0x80070057 E_INVALIDARG while
            // "saturation 0" worked. Measured 2026-09-02: 7 effects attempted, 6
            // applied, that one failed.
            //
            // The matrix also removes a semantic dependency. SwiftCrossUI means 1 by
            // "unchanged"; written out, the meaning is whatever these coefficients
            // say and matches SwiftCrossUI by construction at every value.
            //
            // 使用色彩矩陣而非 Direct2D 的 saturation 效果，因為後者無法表達過飽和：其屬性值域止於 1,
            // 因此 P39 的「saturation 2.5」一格被以 0x80070057 E_INVALIDARG 拒絕，而「saturation 0」
            // 則正常。2026-09-02 實測：嘗試 7 個效果，6 個成功，失敗的就是那一個。
            //
            // 改用矩陣也移除了一項語意依賴。SwiftCrossUI 以 1 表示「不變」;明寫出來之後，其語意就是這些
            // 係數所述，並在每一個值上都依構造與 SwiftCrossUI 一致。
            //
            // out = s * in + (1 - s) * luma(in), with Rec. 709 weights. Oversaturation
            // drives channels past 1, so the output is clamped.
            // out = s * in + (1 - s) * luma(in)，採用 Rec. 709 權重。過飽和會使色版超過 1,因此輸出要箝制。
            let s = Float(effect.saturation)
            let inverse = 1 - s
            let r = inverse * 0.2126
            let g = inverse * 0.7152
            let b = inverse * 0.0722
            _ = try colorMatrix(
                [
                    s + r, r, r, 0,
                    g, s + g, g, 0,
                    b, b, s + b, 0,
                    0, 0, 0, 1,
                    0, 0, 0, 0,
                ],
                clamp: true,
                from: currentSource
            )
        }

        if effect.brightness != 0 {
            let amount = Float(min(max(effect.brightness, -0.99), 0.99))
            _ = try colorMatrix(
                [
                    1, 0, 0, 0,
                    0, 1, 0, 0,
                    0, 0, 1, 0,
                    0, 0, 0, 1,
                    amount, amount, amount, 0,
                ],
                clamp: true,
                from: currentSource
            )
        }

        if effect.contrast != 1 {
            // SwiftUI's contrast is linear about mid grey, c' = (c - 0.5) * k + 0.5, done
            // here as a colour matrix like brightness above. Not Direct2D's contrast
            // effect: it is its own curve, and with `k - 1` P39's contrast 0.3 cell came
            // out nearly the control: (11, 160, 215) -> (16, 147, 200), where the formula
            // gives (93, 137, 154) and GtkBackend draws it washed out.
            // SwiftUI 的 contrast 以中灰為中心呈線性,c' = (c - 0.5) * k + 0.5,此處與上面的 brightness 一樣用
            // 顏色矩陣實作。不用 Direct2D 的 contrast 效果：它是自己的曲線，傳入 `k - 1` 時 P39 的 contrast 0.3
            // 那格幾乎等於對照格:(11, 160, 215) -> (16, 147, 200),公式給的是 (93, 137, 154),GtkBackend 畫出來
            // 也是褪色的。
            let k = Float(max(effect.contrast, 0))
            let offset = 0.5 * (1 - k)
            _ = try colorMatrix(
                [
                    k, 0, 0, 0,
                    0, k, 0, 0,
                    0, 0, k, 0,
                    0, 0, 0, 1,
                    offset, offset, offset, 0,
                ],
                clamp: true,
                from: currentSource
            )
        }

        if effect.grayscale != 0 {
            // AppKit's grey, the reference for P39, which GtkBackend, UIKitBackend and
            // AndroidBackend draw too: CIColorMonochrome tinted with 0.5 grey, in
            // linear light. Not Direct2D's grayscale effect: it is the sRGB-luma grey
            // (the same as saturation 0, lighter than AppKit's) and has no amount, so
            // grayscale(0.5) drew fully grey.
            //
            //   decode   sRGB to linear, (v + 0.055) / 1.055 then the power 2.4
            //   L        linear luminance with CIColorMonochrome's weights
            //   overlay  2cL below L = 0.5, 1 - 2(1 - L)(1 - c) above, with the
            //            tint c = 0.5 grey in linear light. That is
            //            2c * L + (1 - 2c) * max(0, 2L - 1): a weighted sum
            //            whose weights add to 1, so the arithmetic composite, which
            //            works on premultiplied colour, keeps alpha as it was.
            //   amount   below 1, the grey and the decoded original are mixed
            //            in linear light, as Core Image does
            //   encode   1.055 v^(1/2.4) - 0.055
            //
            // decode and encode drop sRGB's short linear segment near black,
            // as GtkBackend's curves do: at most 3 of 255 levels, below 15.
            //
            // AppKit 的灰，是 P39 的基準,GtkBackend、UIKitBackend 與 AndroidBackend 也都這樣畫：以 0.5 灰上色的
            // CIColorMonochrome,在線性光中進行。不用 Direct2D 的 grayscale 效果：那是 sRGB 亮度的灰(與
            // saturation 0 相同，比 AppKit 的亮),而且沒有強度，所以 grayscale(0.5) 畫成全灰。
            //
            //   decode   sRGB 轉線性:(v + 0.055) / 1.055，再取 2.4 次方
            //   L        線性亮度，權重同 CIColorMonochrome
            //   overlay  L < 0.5 時為 2cL，以上為 1 - 2(1 - L)(1 - c)，上色值 c 為線性光中的 0.5 灰。
            //            也就是 2c * L + (1 - 2c) * max(0, 2L - 1):權重和為 1 的加權和，因此在預乘
            //            色彩上運算的 arithmetic composite 會讓 alpha 維持原值。
            //   amount   小於 1 時，灰圖與解碼後的原圖在線性光中混合，與 Core Image 相同
            //   encode   1.055 v^(1/2.4) - 0.055
            //
            // decode 與 encode 都略去 sRGB 在黑色附近那一小段線性區，與 GtkBackend 的曲線相同：
            // 255 階中最多 3 階，且只在 15 以下。
            let tint = Float(0.214_041) // ((0.5 + 0.055) / 1.055)^2.4

            func weightedSum(
                _ first: D2DSource, _ firstAmount: Float,
                _ second: D2DSource, _ secondAmount: Float
            ) throws -> D2DSource {
                let node = try D2DEffect(SCUI_EFFECT_ARITHMETIC_COMPOSITE, sources: [first, second])
                // multiply, source 1, source 2, offset / 相乘、來源 1、來源 2、偏移
                try node.set(SCUI_ARITHMETIC_COEFFICIENTS, .singles([0, firstAmount, secondAmount, 0]))
                try node.set(SCUI_ARITHMETIC_CLAMP, .boolean(true))
                try append(node)
                return currentSource
            }

            // A fresh copy of everything upstream of the grey: the source and
            // the adjustments before it. Composition takes only a TREE --
            // reusing one decoded node for two branches failed with
            // "Non-tree shaped effect graph" (2026-10-19) -- so each branch
            // gets its own, built by the same code with grey and hue left out.
            // 灰色上游一切的全新副本：來源與它之前的調整。Composition 只接受**樹**——讓兩個分支共用同一個
            // 解碼節點時失敗,"Non-tree shaped effect graph"(2026-10-19)——因此每個分支各有一份，以同一段
            // 程式、去掉灰階與色相建成。
            func freshPrefix() throws -> D2DSource {
                var prefix = effect
                prefix.grayscale = 0
                prefix.hueRotation = .zero
                prefix.colorInvert = false
                prefix.blendMode = .normal
                if prefix.needsOnlyOpacity {
                    let parameter = WinAppSDK.CompositionEffectSourceParameter("source")
                    guard let wrapper =
                        __ABI_Windows_Graphics_Effects.IGraphicsEffectSourceWrapper(parameter)
                    else {
                        throw WinUIVisualEffectError.emptyEffectGraph
                    }
                    objects.append(wrapper)
                    var pointer: D2DSource = nil
                    try wrapper.toABI { pointer = $0 }
                    return pointer
                }
                let graph = try D2DEffectGraph(effect: prefix)
                objects.append(contentsOf: graph.effectObjects)
                guard let last = graph.effectObjects.last as? WindowsFoundation.IInspectable else {
                    throw WinUIVisualEffectError.emptyEffectGraph
                }
                let source: __ABI_Windows_Graphics_Effects.IGraphicsEffectSource =
                    try last.QueryInterface()
                let pointer: UnsafeMutablePointer<__x_ABI_CWindows_CGraphics_CEffects_CIGraphicsEffectSource> = RawPointer(source)
                return pointer
            }

            // Red, green and blue through `curve`; alpha left alone. A transfer
            // effect's properties come in one group per channel, red first.
            // 紅綠藍經過 `curve`;alpha 不變。transfer 效果的屬性每個通道一組，紅色在前。
            func linearTransfer(slope: Float, intercept: Float, from source: D2DSource) throws -> D2DSource {
                let node = try D2DEffect(SCUI_EFFECT_LINEAR_TRANSFER, sources: [source])
                for base in [SCUI_LINEAR_RED_INTERCEPT, SCUI_LINEAR_GREEN_INTERCEPT, SCUI_LINEAR_BLUE_INTERCEPT] {
                    try node.set(base, .single(intercept))
                    try node.set(base + 1, .single(slope))
                    try node.set(base + 2, .boolean(false))
                }
                try node.set(SCUI_LINEAR_ALPHA_INTERCEPT, .single(0))
                try node.set(SCUI_LINEAR_ALPHA_INTERCEPT + 1, .single(1))
                try node.set(SCUI_LINEAR_ALPHA_DISABLE, .boolean(true))
                try node.set(SCUI_LINEAR_CLAMP, .boolean(false))
                try append(node)
                return currentSource
            }

            func gammaTransfer(
                amplitude: Float, exponent: Float, offset: Float, clamp: Bool,
                from source: D2DSource
            ) throws -> D2DSource {
                let node = try D2DEffect(SCUI_EFFECT_GAMMA_TRANSFER, sources: [source])
                for base in [SCUI_GAMMA_RED_AMPLITUDE, SCUI_GAMMA_GREEN_AMPLITUDE, SCUI_GAMMA_BLUE_AMPLITUDE] {
                    try node.set(base, .single(amplitude))
                    try node.set(base + 1, .single(exponent))
                    try node.set(base + 2, .single(offset))
                    try node.set(base + 3, .boolean(false))
                }
                try node.set(SCUI_GAMMA_ALPHA_AMPLITUDE, .single(1))
                try node.set(SCUI_GAMMA_ALPHA_AMPLITUDE + 1, .single(1))
                try node.set(SCUI_GAMMA_ALPHA_AMPLITUDE + 2, .single(0))
                try node.set(SCUI_GAMMA_ALPHA_DISABLE, .boolean(true))
                try node.set(SCUI_GAMMA_CLAMP, .boolean(clamp))
                try append(node)
                return currentSource
            }

            func decode(from source: D2DSource) throws -> D2DSource {
                let shifted = try linearTransfer(
                    slope: Float(1 / 1.055), intercept: Float(0.055 / 1.055), from: source
                )
                return try gammaTransfer(
                    amplitude: 1, exponent: 2.4, offset: 0, clamp: false, from: shifted
                )
            }

            // Linear luminance in every channel, CIColorMonochrome's weights.
            // 每個通道都是線性亮度，權重同 CIColorMonochrome。
            func luminance(from source: D2DSource) throws -> D2DSource {
                try colorMatrix(
                    [
                        0.2125, 0.2125, 0.2125, 0,
                        0.7154, 0.7154, 0.7154, 0,
                        0.0721, 0.0721, 0.0721, 0,
                        0, 0, 0, 1,
                        0, 0, 0, 0,
                    ],
                    clamp: false,
                    from: source
                )
            }

            // L, and max(0, 2L - 1) from a second copy of L.
            // L,以及由第二份 L 算出的 max(0, 2L - 1)。
            let lower = try luminance(from: decode(from: currentSource))
            let upper = try colorMatrix(
                [
                    2, 0, 0, 0,
                    0, 2, 0, 0,
                    0, 0, 2, 0,
                    0, 0, 0, 1,
                    -1, -1, -1, 0,
                ],
                clamp: true,
                from: luminance(from: decode(from: freshPrefix()))
            )
            var grey = try weightedSum(lower, 2 * tint, upper, 1 - 2 * tint)

            let amount = Float(min(max(effect.grayscale, 0), 1))
            if amount < 1 {
                grey = try weightedSum(grey, amount, decode(from: freshPrefix()), 1 - amount)
            }

            _ = try gammaTransfer(
                amplitude: 1.055, exponent: Float(1 / 2.4), offset: -0.055, clamp: true, from: grey
            )
        }

        if effect.hueRotation != .zero {
            // Direct2D's angle is in degrees. / Direct2D 的角度單位是度。
            let hue = try D2DEffect(SCUI_EFFECT_HUE_ROTATION, sources: [currentSource])
            try hue.set(SCUI_HUE_ANGLE, .single(Float(effect.hueRotation.degrees)))
            try append(hue)
        }

        // colorInvert() after every other colour adjustment, as on AppKit: 1 minus each
        // of red, green and blue.
        // colorInvert() 在其他所有色彩調整之後(同 AppKit):紅綠藍各自變為 1 減原值。
        if effect.colorInvert {
            _ = try colorMatrix(
                [
                    -1, 0, 0, 0,
                    0, -1, 0, 0,
                    0, 0, -1, 0,
                    0, 0, 0, 1,
                    1, 1, 1, 0,
                ],
                clamp: true,
                from: currentSource
            )
        }

        // blendMode(_:) last, after every other effect, on what the effects produced:
        // a Direct2D Blend or Composite node whose destination (input 0) is the
        // "backdrop" parameter, which setVisualEffect binds to a CompositionBackdropBrush
        // -- the pixels the compositor has drawn behind this container's sprite -- and
        // whose source (input 1) is the view. See `BlendMode.direct2D` for the node
        // each mode uses.
        // blendMode(_:) 排在最後，在其他所有效果之後，作用於效果產出的結果:Direct2D 的 Blend 或 Composite 節點，
        // 其目的地(輸入 0)是 "backdrop" 參數——setVisualEffect 把它繫結到 CompositionBackdropBrush,也就是合成器在
        // 本容器 sprite 後方已畫好的像素——來源(輸入 1)則是 view。每種模式用哪個節點，見 `BlendMode.direct2D`。
        if let blend = effect.blendMode.direct2D {
            let backdropParameter = WinAppSDK.CompositionEffectSourceParameter("backdrop")
            guard let backdropWrapper =
                __ABI_Windows_Graphics_Effects.IGraphicsEffectSourceWrapper(backdropParameter)
            else {
                throw WinUIVisualEffectError.emptyEffectGraph
            }
            objects.append(backdropWrapper)
            var backdrop: D2DSource = nil
            try backdropWrapper.toABI { backdrop = $0 }
            let node = try D2DEffect(blend.kind, sources: [backdrop, currentSource])
            try node.set(blend.property, .uint(blend.mode))
            try append(node)
        }
        usesBackdrop = effect.blendMode.direct2D != nil

        guard let currentRoot else {
            throw WinUIVisualEffectError.emptyEffectGraph
        }
        rootEffect = currentRoot
        effectObjects = objects
    }
}

/// One Direct2D built-in effect as an IGraphicsEffect (WinUIInterop's
/// graphics_effect.cpp), so Composition compiles the graph with no Win2D.
/// 一個 Direct2D 內建效果，以 IGraphicsEffect 的形式提供(WinUIInterop 的 graphics_effect.cpp),
/// 讓 Composition 不經 Win2D 編譯效果圖。
private struct D2DEffect {
    let object: WindowsFoundation.IInspectable
    private let node: UnsafeMutableRawPointer

    init(_ kind: Int, sources: [D2DSource]) throws {
        guard let node = scui_effect_create(Int32(kind)) else {
            throw WinUIVisualEffectError.effectNotCreated(kind)
        }
        let unknown = node.assumingMemoryBound(to: C_IUnknown.self)
        // ComPtr takes a reference of its own; the one scui_effect_create returned is
        // then given back, so `object` owns the node.
        // ComPtr 自己取得一個參考；scui_effect_create 回傳的那個隨即歸還，因此由 `object` 擁有節點。
        object = WindowsFoundation.IInspectable(ComPtr(unknown))
        _ = unknown.pointee.lpVtbl.pointee.Release(unknown)
        self.node = node
        for (index, source) in sources.enumerated() {
            guard let source, scui_effect_set_source(node, UInt32(index), source) == 1 else {
                throw WinUIVisualEffectError.emptyEffectGraph
            }
        }
    }

    func set(_ index: Int, _ value: D2DPropertyValue) throws {
        let boxed = try value.make()
        guard scui_effect_set_property(node, UInt32(index), boxed.get()) == 1 else {
            throw WinUIVisualEffectError.propertyNotSet(index)
        }
    }
}

/// A Windows.Foundation.PropertyValue for an effect property, of the type Direct2D's
/// property expects: Single, a Single array (a matrix or a vector), UInt32 (an enum)
/// or Boolean.
/// 效果屬性用的 Windows.Foundation.PropertyValue,型別即 Direct2D 屬性所預期的:Single、Single 陣列
/// (矩陣或向量)、UInt32(列舉)或 Boolean。
private enum D2DPropertyValue {
    case single(Float)
    case singles([Float])
    case uint(Int)
    case boolean(Bool)

    nonisolated(unsafe) private static let statics: UnsafeMutablePointer<
        __x_ABI_CWindows_CFoundation_CIPropertyValueStatics
    >? = {
        guard let factory: WindowsFoundation.IInspectable =
            try? RoGetActivationFactory(HString("Windows.Foundation.PropertyValue"))
        else {
            return nil
        }
        // IPropertyValueStatics / IPropertyValueStatics 的 IID
        var iid = WindowsFoundation.IID(
            Data1: 0x629B_DBC8,
            Data2: 0xD932,
            Data3: 0x4FF4,
            Data4: (0x96, 0xB9, 0x8D, 0x96, 0xC5, 0xC1, 0xE8, 0x58)
        )
        var raw: UnsafeMutableRawPointer?
        try? factory.QueryInterface(&iid, &raw)
        return raw?.bindMemory(to: __x_ABI_CWindows_CFoundation_CIPropertyValueStatics.self, capacity: 1)
    }()

    func make() throws -> ComPtr<C_IInspectable> {
        guard let statics = Self.statics else {
            throw WinUIVisualEffectError.emptyEffectGraph
        }
        let table = statics.pointee.lpVtbl.pointee
        let (value) = try ComPtrs.initialize { (out: inout UnsafeMutablePointer<C_IInspectable>?) in
            switch self {
            case .single(let number):
                try CHECKED(table.CreateSingle(statics, number, &out))
            case .singles(let numbers):
                var numbers = numbers
                try numbers.withUnsafeMutableBufferPointer { buffer in
                    try CHECKED(table.CreateSingleArray(
                        statics, UInt32(buffer.count), buffer.baseAddress, &out
                    ))
                }
            case .uint(let number):
                try CHECKED(table.CreateUInt32(statics, UInt32(number), &out))
            case .boolean(let flag):
                try CHECKED(table.CreateBoolean(statics, flag ? 1 : 0, &out))
            }
        }
        guard let value else {
            throw WinUIVisualEffectError.emptyEffectGraph
        }
        return value
    }
}

private enum WinUIVisualEffectError: Swift.Error {
    case emptyEffectGraph
    case effectNotCreated(Int)
    case propertyNotSet(Int)
}

private enum WinUIElementCompositionPreview {
    static func setElementChildVisual(
        of element: WinUI.FrameworkElement,
        to visual: WinAppSDK.Visual?
    ) throws {
        let staticsInspectable: WindowsFoundation.IInspectable = try RoGetActivationFactory(HString(
            "Microsoft.UI.Xaml.Hosting.ElementCompositionPreview"
        ))
        var iidCount: ULONG = 0
        var iids: UnsafeMutablePointer<WindowsFoundation.IID>?
        try staticsInspectable.GetIids(&iidCount, &iids)
        guard let iids, iidCount > 0 else {
            throw WinUIVisualEffectError.emptyEffectGraph
        }
        defer { CoTaskMemFree(iids) }

        var iid = iids[0]
        var rawStatics: UnsafeMutableRawPointer?
        try staticsInspectable.QueryInterface(&iid, &rawStatics)
        guard let rawStatics else {
            throw WinUIVisualEffectError.emptyEffectGraph
        }
        let statics = rawStatics.bindMemory(
            to: __x_ABI_CMicrosoft_CUI_CXaml_CHosting_CIElementCompositionPreviewStatics.self,
            capacity: 1
        )
        defer { _ = statics.pointee.lpVtbl.pointee.Release(statics) }

        let uiElement: __ABI_Microsoft_UI_Xaml.IUIElement = try element.thisPtr.QueryInterface()
        try uiElement.perform(as: __x_ABI_CMicrosoft_CUI_CXaml_CIUIElement.self) { pElement in
            let rawVisual: UnsafeMutablePointer<
                __x_ABI_CMicrosoft_CUI_CComposition_CIVisual
            >? = RawPointer(visual)
            try CHECKED(statics.pointee.lpVtbl.pointee.SetElementChildVisual(
                statics,
                pElement,
                rawVisual
            ))
        }
    }
}

private extension WinUI.FrameworkElement {
    var actualVectorSize: WindowsFoundation.Vector2 {
        WindowsFoundation.Vector2(
            x: Float(max(0, actualWidth)),
            y: Float(max(0, actualHeight))
        )
    }
}

/// Appends a line to `winui-visual-effects-debug.log`, next to the executable,
/// when `SCUI_DEBUG_VISUAL_EFFECTS=1`.
///
/// Kept when the rest of this file's debug scaffolding was removed, because the
/// two are not the same thing. The scaffolding drew stand-in visuals -- a
/// magenta block, the unfiltered source -- to answer "does anything reach the
/// screen at all", and that question is settled. This writes down failures, and
/// without it an effect graph that cannot be built renders as an ordinary view,
/// which is indistinguishable from the effect being unsupported.
///
/// 當 `SCUI_DEBUG_VISUAL_EFFECTS=1` 時，於執行檔旁的 `winui-visual-effects-debug.log`
/// 附加一行。
///
/// 本檔其餘的除錯鷹架被移除時保留了它，因為兩者並非同一回事。那些鷹架會畫出替身畫面——洋紅色
/// 方塊、未經處理的來源——用以回答「究竟有沒有任何東西送上螢幕」，而那個問題已經有答案了。
/// 這一個記錄的是失敗；少了它，一個建不起來的效果圖會呈現為一般畫面，與「該效果未受支援」
/// 無從分辨。
private func winUIVisualEffectDebug(_ message: @autoclosure () -> String) {
    if ProcessInfo.processInfo.environment["SCUI_DEBUG_VISUAL_EFFECTS"] == "1" {
        guard let executable = CommandLine.arguments.first else {
            return
        }
        let directory = URL(fileURLWithPath: executable).deletingLastPathComponent()
        let url = directory.appendingPathComponent("winui-visual-effects-debug.log")
        let line = "[WinUIBackend.VisualEffects] \(message())\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url)
            {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}

private func winUIVisualEffectKey(_ widget: WinUI.FrameworkElement) -> UInt {
    let pointer: UnsafeMutablePointer<__x_ABI_CMicrosoft_CUI_CXaml_CIFrameworkElement>? =
        widget._getABI()
    return UInt(bitPattern: pointer)
}

extension WinUIBackend {
    /// shadow(color:radius:x:y:) for one effect container; `nil` makes the shadow
    /// transparent and keeps its host for the next one. The DropShadow's blurRadius is
    /// a CSS-style blur, twice the Gaussian spread SwiftUI's radius names, as on GTK.
    /// 一個效果容器的 shadow(color:radius:x:y:);`nil` 讓陰影變透明並保留其宿主供下次使用。DropShadow 的
    /// blurRadius 是 CSS 式的模糊，是 SwiftUI radius 所指高斯擴散的兩倍，與 GTK 相同。
    fileprivate func applyShadow(_ shadow: VisualEffect.Shadow?, to widget: Widget, key: UInt) {
        let existing = visualEffectShadows.withLock { $0[key] }
        guard let shadow else {
            existing?.dropShadow.opacity = 0
            return
        }
        let state: WinUIShadowState
        if let existing {
            state = existing
        } else {
            guard let container = widget as? Canvas,
                  let child = visualEffectChildren.withLock({ $0[key] })?.widget,
                  let sourceVisual = try? child.getVisualInternal(),
                  let compositor = sourceVisual.compositor,
                  let surface = try? compositor.createVisualSurface(),
                  let mask = try? compositor.createSurfaceBrush(surface),
                  let dropShadow = try? compositor.createDropShadow(),
                  let sprite = try? compositor.createSpriteVisual()
            else {
                winUIVisualEffectDebug("shadow could not be built for key \(key)")
                return
            }
            surface.sourceVisual = sourceVisual
            dropShadow.mask = mask
            sprite.relativeSizeAdjustment = WindowsFoundation.Vector2(x: 1, y: 1)
            sprite.shadow = dropShadow
            let host = Canvas()
            host.isHitTestVisible = false
            container.children.append(host)
            try? Canvas.setZIndex(host, -1)
            try? WinUIElementCompositionPreview.setElementChildVisual(of: host, to: sprite)
            state = WinUIShadowState(
                host: host, surface: surface, dropShadow: dropShadow, mask: mask, sprite: sprite
            )
            visualEffectShadows.withLock { $0[key] = state }
            container.sizeChanged.addHandler { [weak container] _, _ in
                MainActor.assumeIsolated {
                    guard let container, let state = visualEffectShadows.withLock({ $0[key] })
                    else { return }
                    state.resize(to: container)
                }
            }
        }
        state.resize(to: widget)
        state.dropShadow.color = shadow.color.uwpColor
        state.dropShadow.opacity = 1
        state.dropShadow.blurRadius = Float(2 * shadow.radius)
        state.dropShadow.offset = WindowsFoundation.Vector3(x: Float(shadow.x), y: Float(shadow.y), z: 0)
    }
}
