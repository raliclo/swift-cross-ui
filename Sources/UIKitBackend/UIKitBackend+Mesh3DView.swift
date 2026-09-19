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
