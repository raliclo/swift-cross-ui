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
            winUIVisualEffectDebug("missing Win2D activation or child for key \(key)")
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
            if ProcessInfo.processInfo.environment["SCUI_DEBUG_VISUAL_EFFECT_SOLID"] == "1" {
                guard let spriteVisual = try compositor.createSpriteVisual() else {
                    throw WinUIVisualEffectError.emptyEffectGraph
                }
                spriteVisual.brush = try compositor.createColorBrush(UWP.Color(
                    a: 192,
                    r: 255,
                    g: 0,
                    b: 255
                ))
                spriteVisual.relativeSizeAdjustment = WindowsFoundation.Vector2(x: 0, y: 0)
                spriteVisual.size = widget.actualVectorSize
                try WinUIElementCompositionPreview.setElementChildVisual(of: widget, to: spriteVisual)
                child.opacity = 0
                return
            } else if ProcessInfo.processInfo.environment["SCUI_DEBUG_VISUAL_EFFECT_SOURCE"] == "1" {
                guard let spriteVisual = try compositor.createSpriteVisual() else {
                    throw WinUIVisualEffectError.emptyEffectGraph
                }
                spriteVisual.brush = sourceBrush
                spriteVisual.relativeSizeAdjustment = WindowsFoundation.Vector2(x: 0, y: 0)
                spriteVisual.size = widget.actualVectorSize
                try WinUIElementCompositionPreview.setElementChildVisual(of: widget, to: spriteVisual)
                child.opacity = 0
                return
            } else {
                let graph = try Win2DEffectGraph(effect: effect)
                winUIVisualEffectDebug("created Win2D effect graph for key \(key)")
                guard let effectFactory = try compositor.createEffectFactory(graph.rootEffect),
                      let effectBrush = try effectFactory.createBrush()
                else {
                    throw WinUIVisualEffectError.emptyEffectGraph
                }
                winUIVisualEffectDebug("created effect brush for key \(key)")
                try effectBrush.setSourceParameter("source", sourceBrush)
                winUIVisualEffectDebug("set source parameter for key \(key)")
                guard let spriteVisual = try compositor.createSpriteVisual() else {
                    throw WinUIVisualEffectError.emptyEffectGraph
                }
                spriteVisual.brush = effectBrush
                spriteVisual.relativeSizeAdjustment = WindowsFoundation.Vector2(x: 0, y: 0)
                spriteVisual.size = widget.actualVectorSize
                spriteVisual.clip = try compositor.createInsetClip(0, 0, 0, 0)
                winUIVisualEffectDebug(
                    "sprite size \(spriteVisual.size.x)x\(spriteVisual.size.y), "
                        + "widget \(widget.actualWidth)x\(widget.actualHeight)"
                )
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
            }
        } catch {
            winUIVisualEffectDebug("effect failed for key \(key): \(error)")
            try? WinUIElementCompositionPreview.setElementChildVisual(of: widget, to: nil)
            visualEffectStates.withLock { states in
                states[key] = nil
            }
        }
    }
}

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

private extension VisualEffect {
    var needsOnlyOpacity: Bool {
        blurRadius == 0
            && saturation == 1
            && brightness == 0
            && contrast == 1
            && grayscale == 0
            && hueRotation == .zero
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
            let saturation = try Win2DGpuEffect(
                "Microsoft.Graphics.Canvas.Effects.SaturationEffect",
                iid: .saturationEffect,
                as: __x_ABI_CMicrosoft_CGraphics_CCanvas_CEffects_CISaturationEffect.self
            )
            try CHECKED(saturation.pointer.pointee.lpVtbl.pointee.put_Saturation(
                saturation.pointer,
                FLOAT(effect.saturation)
            ))
            try CHECKED(saturation.pointer.pointee.lpVtbl.pointee.put_Source(
                saturation.pointer,
                currentSource
            ))
            try append(saturation.object)
        }

        if effect.brightness != 0 {
            let brightness = try Win2DGpuEffect(
                "Microsoft.Graphics.Canvas.Effects.BrightnessEffect",
                iid: .brightnessEffect,
                as: __x_ABI_CMicrosoft_CGraphics_CCanvas_CEffects_CIBrightnessEffect.self
            )
            let amount = FLOAT(effect.brightness)
            try CHECKED(brightness.pointer.pointee.lpVtbl.pointee.put_BlackPoint(
                brightness.pointer,
                __x_ABI_CWindows_CFoundation_CNumerics_CVector2(X: -amount, Y: -amount)
            ))
            try CHECKED(brightness.pointer.pointee.lpVtbl.pointee.put_WhitePoint(
                brightness.pointer,
                __x_ABI_CWindows_CFoundation_CNumerics_CVector2(X: 1 - amount, Y: 1 - amount)
            ))
            try CHECKED(brightness.pointer.pointee.lpVtbl.pointee.put_Source(
                brightness.pointer,
                currentSource
            ))
            try append(brightness.object)
        }

        if effect.contrast != 1 {
            let contrast = try Win2DGpuEffect(
                "Microsoft.Graphics.Canvas.Effects.ContrastEffect",
                iid: .contrastEffect,
                as: __x_ABI_CMicrosoft_CGraphics_CCanvas_CEffects_CIContrastEffect.self
            )
            try CHECKED(contrast.pointer.pointee.lpVtbl.pointee.put_Contrast(
                contrast.pointer,
                FLOAT(effect.contrast)
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
    static let brightnessEffect = WindowsFoundation.IID(
        Data1: 0xbeced347,
        Data2: 0x025f,
        Data3: 0x5727,
        Data4: (0x8f, 0x7d, 0x49, 0x8d, 0x67, 0xdf, 0x55, 0x7e)
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
        if !FileManager.default.fileExists(atPath: manifestURL.path) {
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
