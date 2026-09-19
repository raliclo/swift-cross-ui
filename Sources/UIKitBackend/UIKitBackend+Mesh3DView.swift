import Metal
@_spi(Backends) import SwiftCrossUI
import SwiftCrossUIMetal
import UIKit

/// M10's second backend, and the reason the renderer lives in its own target.
///
/// **Everything below the `WrapperWidget` is the same code AppKitBackend runs.**
/// `MTKView` is the same MetalKit class on both, so `Mesh3DMetalView`, the
/// shaders and the camera arithmetic are shared verbatim; what differs is only
/// the widget wrapper each backend needs. Popovers, accessibility names and
/// gesture placement each cost a week this month because two Apple backends had
/// been written twice and drifted -- this one is written once on purpose.
///
/// M10 的第二個 backend,也正是 renderer 自成一個 target 的理由。
///
/// **`WrapperWidget` 以下的每一行,都是 AppKitBackend 所執行的同一份程式碼。** `MTKView` 在兩邊是
/// MetalKit 的同一個類別,因此 `Mesh3DMetalView`、著色器與相機運算是逐字共用的;不同的只有各
/// backend 所需的那層 widget 包裝。本月 popover、無障礙名稱與手勢位置各花掉一週,正是因為兩個
/// Apple backend 被寫了兩次而後分歧——這一個是刻意只寫一次。
extension UIKitBackend: BackendFeatures.Mesh3DViews {
    public func createMesh3DView() -> Widget {
        // nil here is a simulator whose host has no usable Metal device, and on
        // iOS hardware it does not happen. AppKitBackend carries the same guard
        // with a longer note; the point of repeating it is that a backend which
        // force-unwraps is a backend that crashes in CI rather than on a desk.
        //
        // 此處為 nil 的情況,是「宿主沒有可用 Metal 裝置」的模擬器;在 iOS 實機上不會發生。
        // AppKitBackend 帶有同樣的防護與更長的說明;這裡重複它的意義在於:一個強制解包的 backend,
        // 就是一個「在 CI 上崩潰、而不是在桌前崩潰」的 backend。
        guard let device = MTLCreateSystemDefaultDevice() else {
            logger.warning(
                """
                render warning (the app keeps running and the view is still laid out): \
                this device reports no Metal device, so Mesh3DView draws an empty box of \
                the size the layout gave it. On iOS hardware that does not happen; a \
                simulator on a host without a usable GPU does. What to change: run it on \
                a device, or on a simulator whose host has one.
                """
            )
            return BaseViewWidget()
        }
        return WrapperWidget<Mesh3DMetalView>(child: Mesh3DMetalView(device: device))
    }

    public func updateMesh3DView(
        _ view: Widget,
        scene: Mesh3DScene,
        onFrame: @escaping @MainActor (Mesh3DFrameInfo) -> Void,
        environment: EnvironmentValues
    ) {
        // A bare `BaseViewWidget` is the no-device case above, not a programming
        // error, so this returns rather than casting with `as!`.
        // 一個光禿禿的 `BaseViewWidget` 是上面那個「沒有裝置」的情況,不是程式錯誤,
        // 因此這裡直接返回,而不是用 `as!` 去轉。
        guard let widget = view as? WrapperWidget<Mesh3DMetalView> else { return }
        widget.child.onFrame = onFrame
        widget.child.setScene(scene, background: scene.background.resolve(in: environment))
    }
}

/// Reading back what a widget drew (SoftPCB `plan.md` §10.7, gap 9).
///
/// **The same two paths as AppKit, and the same reason for the order.**
/// `UIGraphicsImageRenderer.image { view.layer.render(in:) }` walks the layer
/// tree with Core Graphics, which is right for a label and blank for an
/// `MTKView` -- Metal never touches that layer's contents. `drawHierarchy` does
/// capture Metal, and it captures whatever is on screen at the time including
/// anything in front of the view, so it answers a different question than "what
/// did this widget draw". The mesh view path is taken first.
///
/// 把一個 widget 畫出來的東西讀回來(SoftPCB `plan.md` §10.7 的第 9 項缺口)。
///
/// **與 AppKit 相同的兩條路徑,順序的理由也相同。**
/// `UIGraphicsImageRenderer.image { view.layer.render(in:) }` 是以 Core Graphics 走訪 layer 樹——那對
/// 一個標籤是對的,對一個 `MTKView` 則是空白:Metal 從來不碰那個 layer 的 contents。`drawHierarchy`
/// 確實抓得到 Metal,但它抓的是「當下螢幕上的樣子」,包含擋在那個 view 前面的任何東西——因此它回答的
/// 是與「這個 widget 畫了什麼」不同的問題。mesh view 的路徑排在前面。
extension UIKitBackend: BackendFeatures.WidgetSnapshots {
    public func snapshotWidget(_ widget: Widget) -> WidgetSnapshot? {
        if let wrapper = widget as? WrapperWidget<Mesh3DMetalView> {
            return wrapper.child.snapshot()
        }

        let view = widget.view!
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let scale = view.window?.screen.scale ?? UIScreen.main.scale
        let width = Int((bounds.width * scale).rounded())
        let height = Int((bounds.height * scale).rounded())
        guard width > 0, height > 0 else { return nil }

        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let ok = rgba.withUnsafeMutableBytes { raw -> Bool in
            guard
                let context = CGContext(
                    data: raw.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            else { return false }
            // UIKit's origin is top-left and Core Graphics' is bottom-left, so
            // the layer renders upside down into a raw context unless the
            // transform is applied. Leaving it out gives a snapshot that is
            // correct in every way except vertically mirrored -- which on a
            // symmetric view is invisible.
            // UIKit 的原點在左上、Core Graphics 的在左下,因此若不套用這個變換,layer 畫進一個裸 context
            // 時會上下顛倒。漏掉它,得到的快照在每一方面都正確,只是上下鏡像——而在一個上下對稱的 view 上,
            // 那是看不出來的。
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: scale, y: -scale)
            view.layer.render(in: context)
            return true
        }
        guard ok else { return nil }
        return WidgetSnapshot(width: width, height: height, rgbaData: rgba)
    }
}
