import AppKit
import Metal
@_spi(Backends) import SwiftCrossUI
import SwiftCrossUIMetal

/// M10's first backend: the framework describes a scene, this draws it with
/// Metal.
///
/// **Nothing here is Metal code.** The renderer, the shaders and the camera
/// arithmetic are in `SwiftCrossUIMetal`, which UIKitBackend uses unchanged,
/// because `MTKView` is the same MetalKit class on both. This file is the
/// adapter: make one, hand it scenes, and answer the "is there a GPU at all"
/// question honestly.
///
/// M10 的第一個 backend:框架描述一個場景,這裡用 Metal 把它畫出來。
///
/// **此處沒有任何 Metal 程式碼。** renderer、著色器與相機運算都在 `SwiftCrossUIMetal` 裡,
/// 而 UIKitBackend 原封不動地使用同一份——因為 `MTKView` 在兩邊是 MetalKit 的同一個類別。
/// 本檔是轉接層:做一個出來、把場景交給它,並誠實回答「到底有沒有 GPU」這個問題。
extension AppKitBackend: BackendFeatures.Mesh3DViews {
    public func createMesh3DView() -> Widget {
        // `MTLCreateSystemDefaultDevice()` returns nil, and on macOS that is not
        // hypothetical: it is what a process gets with no window server session
        // -- an ssh login, or a binary run from a build machine's CI shell. Every
        // test app in this tree can be launched that way, so returning an empty
        // view and saying why beats a crash inside a `!` that only reproduces on
        // someone else's machine.
        //
        // `MTLCreateSystemDefaultDevice()` 會回傳 nil,而在 macOS 上那不是假設性的:一個沒有
        // window server session 的行程就會拿到 nil——透過 ssh 登入,或從建置機的 CI shell 執行的
        // 二進位檔。這棵樹裡的每一支測試 app 都可能那樣被啟動,因此「回傳一個空 view 並說明原因」
        // 勝過「在一個 `!` 裡崩潰,而且只在別人的機器上重現」。
        guard let device = MTLCreateSystemDefaultDevice() else {
            logger.warning(
                """
                render warning (the app keeps running and the view is still laid out): \
                this Mac reports no Metal device, so Mesh3DView draws an empty box of \
                the size the layout gave it. That is normal for a process with no \
                window server session -- an app started over ssh, or from a CI shell. \
                What to change: run it from a logged-in desktop session, or from \
                testapp/test_mac.zsh, which does.
                """
            )
            return NSView()
        }
        return Mesh3DMetalView(device: device)
    }

    public func updateMesh3DView(
        _ view: Widget,
        scene: Mesh3DScene,
        onFrame: @escaping @MainActor (Mesh3DFrameInfo) -> Void,
        environment: EnvironmentValues
    ) {
        // A plain NSView here is the no-device case above, not a programming
        // error, so this returns rather than casting with `as!`.
        // 此處若是一個普通的 NSView,那是上面那個「沒有裝置」的情況,不是程式錯誤,
        // 因此這裡直接返回,而不是用 `as!` 去轉。
        guard let view = view as? Mesh3DMetalView else { return }
        view.onFrame = onFrame
        view.setScene(scene, background: scene.background.resolve(in: environment))
    }
}
