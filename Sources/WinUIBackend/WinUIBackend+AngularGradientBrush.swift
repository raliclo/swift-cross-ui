import CWinRT
import Foundation
@_spi(Backends) import SwiftCrossUI
import UWP
@_spi(WinRTInternal) import WinAppSDK
import WinUI
import WinUIInterop
import WindowsFoundation

/// An AngularGradient as a XAML brush, for a Path's fill or stroke and a
/// TextBlock's foreground: what `ResolvedFillStyle.angularGradient` paints.
///
/// XAML has no conic brush, and swift-winui projects neither ImageBrush nor
/// LoadedImageSurface, so the conic is rasterised here, in the bounds' own
/// aspect so the angles are not stretched, and shown through a
/// CompositionSurfaceBrush on a CompositionDrawingSurface. The two interop
/// steps are in WinUIInterop/composition_surface.cpp. The brush stretches the
/// surface over the element it paints, which is the bounds the gradient's unit
/// centre is relative to, as on the other backends.
///
/// AngularGradient 作為 XAML brush,用於 Path 的填色或描邊與 TextBlock 的前景：也就是
/// `ResolvedFillStyle.angularGradient` 所塗繪的東西。XAML 沒有錐形 brush,swift-winui 也沒有投影 ImageBrush 或
/// LoadedImageSurface,因此錐形在此點陣化——以外框本身的長寬比，角度不會被拉伸——並經由 CompositionDrawingSurface 上的
/// CompositionSurfaceBrush 顯示。兩個 interop 步驟在 WinUIInterop/composition_surface.cpp。brush 把 surface 拉伸到它所
/// 塗繪的元素上，也就是漸層單位中心所相對的外框，與其他 backend 相同。
final class ConicGradientBrush: XamlCompositionBrushBase {
    private let width: Int
    private let height: Int
    private let pixels: [UInt8]

    /// - Parameters:
    ///   - stops: one turn from `startAngle`, as `ResolvedFillStyle.angularTurnStops` gives them.
    ///   - size: the painted bounds in DIPs; drawn at twice that, at most 1024 pixels a side.
    init(
        stops: [(location: Double, colour: SwiftCrossUI.Color.Resolved)],
        center: UnitPoint, startAngle: Angle, size: SIMD2<Double>
    ) {
        let density = 2.0
        let width = max(1, min(1024, Int((size.x * density).rounded(.up))))
        let height = max(1, min(1024, Int((size.y * density).rounded(.up))))
        self.width = width
        self.height = height
        self.pixels = Self.rasterise(
            stops: stops, center: center, startAngle: startAngle, width: width, height: height)
        super.init()
    }

    override func onConnected() throws {
        guard compositionBrush == nil,
            let compositor = WinUI.CompositionTarget.getCompositorForCurrentThread()
        else { return }
        let compositorABI: __ABI_Microsoft_UI_Composition.ICompositor =
            try compositor.thisPtr.QueryInterface()
        let deviceRaw = try compositorABI.perform(as: UInt8.self) { pointer in
            scui_composition_graphics_device(UnsafeMutableRawPointer(pointer))
        }
        guard let deviceRaw else {
            logger.warning("ConicGradientBrush: could not create a composition graphics device")
            return
        }
        let devicePointer = deviceRaw.assumingMemoryBound(
            to: __x_ABI_CMicrosoft_CUI_CComposition_CICompositionGraphicsDevice.self)
        // ComPtr takes its own reference; the one returned from C is ours to drop.
        // ComPtr 會自己取一個參考;C 回傳的那個由我們釋放。
        let device = WinAppSDK.CompositionGraphicsDevice.from(abi: ComPtr(devicePointer))
        _ = devicePointer.pointee.lpVtbl.pointee.Release(devicePointer)
        guard let device,
            let surface = try device.createDrawingSurface(
                WindowsFoundation.Size(width: Float(width), height: Float(height)),
                .b8g8r8a8uIntNormalized, .premultiplied)
        else { return }
        let surfaceABI: __ABI_Microsoft_UI_Composition.ICompositionDrawingSurface =
            try surface.thisPtr.QueryInterface()
        let drew = try surfaceABI.perform(as: UInt8.self) { pointer in
            pixels.withUnsafeBufferPointer { buffer in
                scui_drawing_surface_fill(
                    UnsafeMutableRawPointer(pointer), Int32(width), Int32(height), buffer.baseAddress)
            }
        }
        guard drew != 0 else {
            logger.warning("ConicGradientBrush: drawing into the composition surface failed")
            return
        }
        guard let brush = try compositor.createSurfaceBrush(surface) else { return }
        brush.stretch = WinAppSDK.CompositionStretch.fill
        compositionBrush = brush
    }

    override func onDisconnected() throws {
        compositionBrush = nil
    }

    /// Premultiplied BGRA, top row first. Angles from three o'clock, clockwise on
    /// screen (y down), the turn starting at `startAngle`; between two stops the
    /// colour is interpolated, past the last one it is the last colour.
    /// 預乘 BGRA,最上面一列在前。角度自三點鐘方向起、螢幕上順時針(y 朝下),一圈從 `startAngle` 開始；兩個色標之間
    /// 內插，最後一個之後是最後的顏色。
    static func rasterise(
        stops: [(location: Double, colour: SwiftCrossUI.Color.Resolved)],
        center: UnitPoint, startAngle: Angle, width: Int, height: Int
    ) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let first = stops.first, let last = stops.last else { return bytes }
        let cx = center.x * Double(width)
        let cy = center.y * Double(height)
        let start = startAngle.radians
        func colour(at turn: Double) -> SwiftCrossUI.Color.Resolved {
            if turn <= first.location { return first.colour }
            if turn >= last.location { return last.colour }
            for index in 1..<stops.count where turn <= stops[index].location {
                let a = stops[index - 1]
                let b = stops[index]
                let span = b.location - a.location
                let t = span > 0 ? (turn - a.location) / span : 1
                return SwiftCrossUI.Color.Resolved(
                    red: a.colour.red + (b.colour.red - a.colour.red) * Float(t),
                    green: a.colour.green + (b.colour.green - a.colour.green) * Float(t),
                    blue: a.colour.blue + (b.colour.blue - a.colour.blue) * Float(t),
                    opacity: a.colour.opacity + (b.colour.opacity - a.colour.opacity) * Float(t)
                )
            }
            return last.colour
        }
        for y in 0..<height {
            for x in 0..<width {
                var angle = atan2(Double(y) + 0.5 - cy, Double(x) + 0.5 - cx) - start
                angle = angle.truncatingRemainder(dividingBy: 2 * .pi)
                if angle < 0 { angle += 2 * .pi }
                let c = colour(at: angle / (2 * .pi))
                let alpha = max(0, min(1, Double(c.opacity)))
                let offset = (y * width + x) * 4
                bytes[offset] = UInt8((max(0, min(1, Double(c.blue))) * alpha * 255).rounded())
                bytes[offset + 1] = UInt8((max(0, min(1, Double(c.green))) * alpha * 255).rounded())
                bytes[offset + 2] = UInt8((max(0, min(1, Double(c.red))) * alpha * 255).rounded())
                bytes[offset + 3] = UInt8((alpha * 255).rounded())
            }
        }
        return bytes
    }
}

extension ResolvedFillStyle {
    /// Whether WinUIBackend needs the painted size to draw this style: the radii
    /// of a radial gradient are points, and a conic is rasterised at that size.
    /// WinUIBackend 是否需要塗繪尺寸才能畫這個樣式：放射漸層的半徑是點，錐形以該尺寸點陣化。
    var needsPaintedSize: Bool {
        switch self {
            case .radialGradient, .angularGradient: true
            case .color, .linearGradient: false
        }
    }
}
