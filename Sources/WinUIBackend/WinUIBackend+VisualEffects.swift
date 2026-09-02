import CWinRT
import Foundation
import Mutex
@_spi(Backends) import SwiftCrossUI
@_spi(WinRTInternal) import UWP
@_spi(WinRTInternal) import WinAppSDK
import WinSDK
@_spi(WinRTInternal) import WinUI
@preconcurrency import WindowsFoundation

private let visualEffectChildren = Mutex<[UInt: WinUIVisualEffectChild]>([:])
private let visualEffectStates = Mutex<[UInt: WinUIVisualEffectState]>([:])
private let win2DActivation = Mutex<Win2DActivationState>(Win2DActivationState())

private struct Win2DActivationState {
    var attempted = false
    var activated = false
    var handle: HANDLE?
    var cookie: ULONG_PTR = 0
}

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

        guard ensureWin2DActivationContext(),
              let child = visualEffectChildren.withLock({ $0[key] })?.widget
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
            let graph = try Win2DEffectGraph(effect: effect)
            guard let effectFactory = try compositor.createEffectFactory(graph.rootEffect),
                  let effectBrush = try effectFactory.createBrush()
            else {
                throw WinUIVisualEffectError.emptyEffectGraph
            }
            try effectBrush.setSourceParameter("source", sourceBrush)
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

private extension VisualEffect {
    var needsOnlyOpacity: Bool {
        blurRadius == 0
            && saturation == 1
            && brightness == 0
            && contrast == 1
            && grayscale == 0
            && hueRotation == .zero
    }

    /// The non-default components, for a diagnostic that names the effect.
    ///
    /// The log used to carry only the widget key, which is a pointer value: it
    /// proved that two of P39's nine cells failed but not which two, and the
    /// answer had to be inferred from the order the cells happened to lay out
    /// in. A failure that cannot say what it was given costs a whole run to
    /// re-derive.
    /// 列出非預設的成分，使診斷能指名是哪一個效果。
    ///
    /// 這份記錄過去只帶著 widget key，而那是一個指標值：它足以證明 P39 九格中有兩格失敗，
    /// 卻無法指出是哪兩格，只能從各格恰好的版面順序去推斷。一個說不出自己收到什麼的失敗，
    /// 要花掉一整輪執行才能重新推導出來。
    var debugSummary: String {
        var parts: [String] = []
        if blurRadius != 0 { parts.append("blur \(blurRadius)") }
        if saturation != 1 { parts.append("saturation \(saturation)") }
        if brightness != 0 { parts.append("brightness \(brightness)") }
        if contrast != 1 { parts.append("contrast \(contrast)") }
        if grayscale != 0 { parts.append("grayscale \(grayscale)") }
        if hueRotation != .zero { parts.append("hueRotation \(hueRotation.degrees)") }
        return parts.isEmpty ? "identity" : parts.joined(separator: ", ")
    }
}

private struct Win2DEffectGraph {
    let rootEffect: UWP.AnyIGraphicsEffect
    let effectObjects: [Any]

    init(effect: VisualEffect) throws {
        let sourceParameter = WinAppSDK.CompositionEffectSourceParameter("source")
        guard let sourceParameterWrapper =
            __ABI_Windows_Graphics_Effects.IGraphicsEffectSourceWrapper(sourceParameter)
        else {
            throw WinUIVisualEffectError.emptyEffectGraph
        }
        var currentSource: UnsafeMutablePointer<
            __x_ABI_CWindows_CGraphics_CEffects_CIGraphicsEffectSource
        >?
        var currentRoot: UWP.AnyIGraphicsEffect?
        var objects: [Any] = [sourceParameterWrapper]
        try sourceParameterWrapper.toABI { sourceParameterABI in
            currentSource = sourceParameterABI
        }

        func append(_ object: WindowsFoundation.IInspectable) throws {
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

        if effect.blurRadius != 0 {
            let blur = try Win2DGpuEffect(
                "Microsoft.Graphics.Canvas.Effects.GaussianBlurEffect",
                iid: .gaussianBlurEffect,
                as: __x_ABI_CMicrosoft_CGraphics_CCanvas_CEffects_CIGaussianBlurEffect.self
            )
            try CHECKED(blur.pointer.pointee.lpVtbl.pointee.put_BlurAmount(
                blur.pointer,
                FLOAT(effect.blurRadius)
            ))
            try CHECKED(blur.pointer.pointee.lpVtbl.pointee.put_Source(blur.pointer, currentSource))
            try append(blur.object)
        }

        if effect.saturation != 1 {
            // A colour matrix, not SaturationEffect, because that effect cannot
            // express oversaturation: it wraps D2D's saturation, whose property
            // range stops at 1, so P39's "saturation 2.5" cell was rejected with
            // 0x80070057 E_INVALIDARG while "saturation 0" worked. Measured
            // 2026-09-02: 7 effects attempted, 6 applied, that one failed.
            //
            // The matrix also removes a semantic dependency. SwiftCrossUI means
            // 1 by "unchanged", and whether Win2D's scale agreed was never
            // tested -- P39 exercises 0 and 2.5 but nothing between, so a wrong
            // midpoint would have gone unseen. Written out, the meaning is
            // whatever these coefficients say and matches SwiftCrossUI by
            // construction at every value.
            //
            // 使用色彩矩陣而非 SaturationEffect，因為後者無法表達過飽和：它包的是 D2D 的
            // saturation，其屬性值域止於 1，因此 P39 的「saturation 2.5」一格被以
            // 0x80070057 E_INVALIDARG 拒絕，而「saturation 0」則正常。2026-09-02 實測：
            // 嘗試 7 個效果，6 個成功，失敗的就是那一個。
            //
            // 改用矩陣也移除了一項語意依賴。SwiftCrossUI 以 1 表示「不變」，而 Win2D 的
            // 刻度是否與之一致從未被測過——P39 只驗了 0 與 2.5，中間沒有任何一點，因此
            // 中段若對應錯誤也不會被看見。明寫出來之後，其語意就是這些係數所述，並在每一個
            // 值上都依構造與 SwiftCrossUI 一致。
            //
            // out = s * in + (1 - s) * luma(in), with Rec. 709 weights.
            // out = s * in + (1 - s) * luma(in)，採用 Rec. 709 權重。
            let s = FLOAT(effect.saturation)
            let inverse = 1 - s
            let lumaR = FLOAT(0.2126)
            let lumaG = FLOAT(0.7152)
            let lumaB = FLOAT(0.0722)
            let saturation = try Win2DGpuEffect(
                "Microsoft.Graphics.Canvas.Effects.ColorMatrixEffect",
                iid: .colorMatrixEffect,
                as: __x_ABI_CMicrosoft_CGraphics_CCanvas_CEffects_CIColorMatrixEffect.self
            )
            try CHECKED(saturation.pointer.pointee.lpVtbl.pointee.put_ColorMatrix(
                saturation.pointer,
                __x_ABI_CMicrosoft_CGraphics_CCanvas_CEffects_CMatrix5x4(
                    M11: s + inverse * lumaR, M12: inverse * lumaR,
                    M13: inverse * lumaR, M14: 0,

                    M21: inverse * lumaG, M22: s + inverse * lumaG,
                    M23: inverse * lumaG, M24: 0,

                    M31: inverse * lumaB, M32: inverse * lumaB,
                    M33: s + inverse * lumaB, M34: 0,

                    M41: 0, M42: 0, M43: 0, M44: 1,
                    M51: 0, M52: 0, M53: 0, M54: 0
                )
            ))
            // Oversaturation drives channels past 1, and without clamping those
            // wrap rather than saturate, which shows as the wrong hue in the
            // brightest areas instead of as a flat highlight.
            // 過飽和會使色版超過 1，未經箝制時它們會繞回而非飽和，於是在最亮的區域呈現為
            // 錯誤的色相，而不是一片平坦的高光。
            try CHECKED(saturation.pointer.pointee.lpVtbl.pointee.put_ClampOutput(
                saturation.pointer,
                1
            ))
            try CHECKED(saturation.pointer.pointee.lpVtbl.pointee.put_Source(
                saturation.pointer,
                currentSource
            ))
            try append(saturation.object)
        }

        if effect.brightness != 0 {
            let colorMatrix = try Win2DGpuEffect(
                "Microsoft.Graphics.Canvas.Effects.ColorMatrixEffect",
                iid: .colorMatrixEffect,
                as: __x_ABI_CMicrosoft_CGraphics_CCanvas_CEffects_CIColorMatrixEffect.self
            )
            let amount = FLOAT(min(max(effect.brightness, -0.99), 0.99))
            try CHECKED(colorMatrix.pointer.pointee.lpVtbl.pointee.put_ColorMatrix(
                colorMatrix.pointer,
                __x_ABI_CMicrosoft_CGraphics_CCanvas_CEffects_CMatrix5x4(
                    M11: 1, M12: 0, M13: 0, M14: 0,
                    M21: 0, M22: 1, M23: 0, M24: 0,
                    M31: 0, M32: 0, M33: 1, M34: 0,
                    M41: 0, M42: 0, M43: 0, M44: 1,
                    M51: amount, M52: amount, M53: amount, M54: 0
                )
            ))
            try CHECKED(colorMatrix.pointer.pointee.lpVtbl.pointee.put_ClampOutput(
                colorMatrix.pointer,
                1
            ))
            try CHECKED(colorMatrix.pointer.pointee.lpVtbl.pointee.put_Source(
                colorMatrix.pointer,
                currentSource
            ))
            try append(colorMatrix.object)
        }

        if effect.contrast != 1 {
            let contrast = try Win2DGpuEffect(
                "Microsoft.Graphics.Canvas.Effects.ContrastEffect",
                iid: .contrastEffect,
                as: __x_ABI_CMicrosoft_CGraphics_CCanvas_CEffects_CIContrastEffect.self
            )
            try CHECKED(contrast.pointer.pointee.lpVtbl.pointee.put_Contrast(
                contrast.pointer,
                FLOAT(min(max(effect.contrast - 1, -1), 1))
            ))
            try CHECKED(contrast.pointer.pointee.lpVtbl.pointee.put_Source(
                contrast.pointer,
                currentSource
            ))
            try append(contrast.object)
        }

        if effect.grayscale != 0 {
            let grayscale = try Win2DGpuEffect(
                "Microsoft.Graphics.Canvas.Effects.GrayscaleEffect",
                iid: .grayscaleEffect,
                as: __x_ABI_CMicrosoft_CGraphics_CCanvas_CEffects_CIGrayscaleEffect.self
            )
            try CHECKED(grayscale.pointer.pointee.lpVtbl.pointee.put_Source(
                grayscale.pointer,
                currentSource
            ))
            try append(grayscale.object)
        }

        if effect.hueRotation != .zero {
            let hueRotation = try Win2DGpuEffect(
                "Microsoft.Graphics.Canvas.Effects.HueRotationEffect",
                iid: .hueRotationEffect,
                as: __x_ABI_CMicrosoft_CGraphics_CCanvas_CEffects_CIHueRotationEffect.self
            )
            try CHECKED(hueRotation.pointer.pointee.lpVtbl.pointee.put_Angle(
                hueRotation.pointer,
                FLOAT(effect.hueRotation.radians)
            ))
            try CHECKED(hueRotation.pointer.pointee.lpVtbl.pointee.put_Source(
                hueRotation.pointer,
                currentSource
            ))
            try append(hueRotation.object)
        }

        guard let currentRoot else {
            throw WinUIVisualEffectError.emptyEffectGraph
        }
        rootEffect = currentRoot
        effectObjects = objects
    }
}

private struct Win2DGpuEffect<Interface> {
    let object: WindowsFoundation.IInspectable
    let pointer: UnsafeMutablePointer<Interface>

    init(_ className: String, iid: WindowsFoundation.IID, as interface: Interface.Type) throws {
        object = try RoActivateInstance(HString(className))

        var iid = iid
        var raw: UnsafeMutableRawPointer?
        try object.QueryInterface(&iid, &raw)
        guard let raw else {
            throw WinUIVisualEffectError.missingWin2DInterface(className)
        }
        pointer = raw.bindMemory(to: Interface.self, capacity: 1)
    }
}

private extension WindowsFoundation.IID {
    static let colorMatrixEffect = WindowsFoundation.IID(
        Data1: 0xe6ae54c4,
        Data2: 0x883d,
        Data3: 0x588e,
        Data4: (0xb4, 0x51, 0xe9, 0xeb, 0xe3, 0x83, 0x04, 0x37)
    )
    static let contrastEffect = WindowsFoundation.IID(
        Data1: 0xda8a2b9f,
        Data2: 0x594e,
        Data3: 0x560a,
        Data4: (0x9e, 0xaa, 0x1f, 0x91, 0x24, 0x08, 0xfe, 0x79)
    )
    static let gaussianBlurEffect = WindowsFoundation.IID(
        Data1: 0xa82ec394,
        Data2: 0x6734,
        Data3: 0x5830,
        Data4: (0x91, 0x23, 0x2c, 0x82, 0xb2, 0x7d, 0xd3, 0xc0)
    )
    static let grayscaleEffect = WindowsFoundation.IID(
        Data1: 0x78e13b83,
        Data2: 0x0638,
        Data3: 0x53f8,
        Data4: (0xb0, 0xb3, 0x5b, 0x0b, 0x32, 0x0a, 0x9a, 0xd2)
    )
    static let hueRotationEffect = WindowsFoundation.IID(
        Data1: 0xc172ebf2,
        Data2: 0xe35f,
        Data3: 0x58ae,
        Data4: (0xad, 0x2c, 0x56, 0x1e, 0xce, 0xaf, 0x26, 0x94)
    )
    /// Unused since saturation moved to a colour matrix on 2026-09-02, and kept
    /// deliberately: SaturationEffect is still the right effect for a
    /// 0-to-1 saturation, and re-deriving a Win2D IID by hand is the expensive
    /// part of adding one back. What it cannot do is oversaturate, which is the
    /// only reason it is not in use.
    /// 自 2026-09-02 飽和度改用色彩矩陣後即無使用者，此處刻意保留：對 0 至 1 的飽和度而言
    /// SaturationEffect 仍是正確的效果，而重新手工推導一個 Win2D IID 正是要加回它時最花成本
    /// 的部分。它做不到的只有過飽和，而那也是它目前未被使用的唯一原因。
    static let saturationEffect = WindowsFoundation.IID(
        Data1: 0xf85a5ed7,
        Data2: 0x7212,
        Data3: 0x57a6,
        Data4: (0xb3, 0x57, 0x61, 0x03, 0x89, 0x61, 0xc5, 0x8d)
    )
}

private enum WinUIVisualEffectError: Swift.Error {
    case emptyEffectGraph
    case missingWin2DInterface(String)
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
/// without it a Win2D effect that cannot be built renders as an ordinary view,
/// which is indistinguishable from the effect being unsupported.
///
/// 當 `SCUI_DEBUG_VISUAL_EFFECTS=1` 時，於執行檔旁的 `winui-visual-effects-debug.log`
/// 附加一行。
///
/// 本檔其餘的除錯鷹架被移除時保留了它，因為兩者並非同一回事。那些鷹架會畫出替身畫面——洋紅色
/// 方塊、未經處理的來源——用以回答「究竟有沒有任何東西送上螢幕」，而那個問題已經有答案了。
/// 這一個記錄的是失敗；少了它，一個建不起來的 Win2D 效果會呈現為一般畫面，與「該效果未受支援」
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

private func ensureWin2DActivationContext() -> Bool {
    win2DActivation.withLock { state in
        if state.attempted {
            return state.activated
        }
        state.attempted = true

        guard let executable = CommandLine.arguments.first else {
            return false
        }

        let directory = URL(fileURLWithPath: executable).deletingLastPathComponent()
        let dllURL = directory.appendingPathComponent("Microsoft.Graphics.Canvas.dll")
        guard FileManager.default.fileExists(atPath: dllURL.path) else {
            return false
        }

        let manifestURL = directory.appendingPathComponent("SwiftCrossUI.Win2D.manifest")
        if (try? String(contentsOf: manifestURL, encoding: .utf8)) != win2DManifest {
            do {
                try win2DManifest.write(to: manifestURL, atomically: true, encoding: .utf8)
            } catch {
                return false
            }
        }

        do {
            try manifestURL.path.withCString(encodedAs: UTF16.self) { manifestPath in
                var context = ACTCTXW(
                    cbSize: ULONG(MemoryLayout<ACTCTXW>.size),
                    dwFlags: 0,
                    lpSource: manifestPath,
                    wProcessorArchitecture: 0,
                    wLangId: 0,
                    lpAssemblyDirectory: nil,
                    lpResourceName: nil,
                    lpApplicationName: nil,
                    hModule: nil
                )
                let handle = CreateActCtxW(&context)
                guard handle != INVALID_HANDLE_VALUE else {
                    throw WinUIVisualEffectError.emptyEffectGraph
                }
                var cookie: ULONG_PTR = 0
                guard ActivateActCtx(handle, &cookie) else {
                    throw WinUIVisualEffectError.emptyEffectGraph
                }
                state.handle = handle
                state.cookie = cookie
                state.activated = true
            }
        } catch {
            state.activated = false
        }

        return state.activated
    }
}

private let win2DManifest = """
<?xml version="1.0" encoding="utf-8"?>
<assembly
  manifestVersion="1.0"
  xmlns="urn:schemas-microsoft-com:asm.v1"
  xmlns:winrt="urn:schemas-microsoft-com:winrt.v1">
  <assemblyIdentity
    version="1.0.0.0"
    name="SwiftCrossUI.WinUI.VisualEffects"/>
  <file name="Microsoft.Graphics.Canvas.dll">
    <winrt:activatableClass
      name="Microsoft.Graphics.Canvas.Effects.BrightnessEffect"
      threadingModel="both"/>
    <winrt:activatableClass
      name="Microsoft.Graphics.Canvas.Effects.ColorMatrixEffect"
      threadingModel="both"/>
    <winrt:activatableClass
      name="Microsoft.Graphics.Canvas.Effects.ContrastEffect"
      threadingModel="both"/>
    <winrt:activatableClass
      name="Microsoft.Graphics.Canvas.Effects.GaussianBlurEffect"
      threadingModel="both"/>
    <winrt:activatableClass
      name="Microsoft.Graphics.Canvas.Effects.GrayscaleEffect"
      threadingModel="both"/>
    <winrt:activatableClass
      name="Microsoft.Graphics.Canvas.Effects.HueRotationEffect"
      threadingModel="both"/>
    <winrt:activatableClass
      name="Microsoft.Graphics.Canvas.Effects.SaturationEffect"
      threadingModel="both"/>
  </file>
</assembly>
"""
