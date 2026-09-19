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

/// Reading back what a widget drew (SoftPCB `plan.md` §10.7, gap 9).
///
/// **Two paths, because AppKit has two kinds of widget here and only one of
/// them draws with the CPU.** `cacheDisplay` redraws a view through AppKit's own
/// drawing machinery, which is exactly right for a button or a label and says
/// nothing about an `MTKView`: Metal content does not go through `drawRect`, so
/// a cached image of one is the view's background. Checked before being written
/// down -- the mesh view path is taken first for that reason, and the generic
/// path is for everything else.
///
/// 把一個 widget 畫出來的東西讀回來(SoftPCB `plan.md` §10.7 的第 9 項缺口)。
///
/// **兩條路徑,因為此處 AppKit 有兩種 widget,而其中只有一種是用 CPU 畫的。** `cacheDisplay` 會透過
/// AppKit 自己的繪圖機制重畫一個 view——那對一顆按鈕或一個標籤完全正確,而對一個 `MTKView` 什麼也說不出來:
/// Metal 的內容不經過 `drawRect`,因此對它做 cache 得到的影像,是那個 view 的背景。這是查證過才寫下來的
/// ——mesh view 的路徑之所以排在前面,理由就在這裡;而通用路徑是給其餘所有東西用的。
extension AppKitBackend: BackendFeatures.WidgetSnapshots {
    public func snapshotWidget(_ widget: Widget) -> WidgetSnapshot? {
        if let mesh = widget as? Mesh3DMetalView {
            return mesh.snapshot()
        }

        let bounds = widget.bounds
        guard bounds.width > 0, bounds.height > 0,
              let rep = widget.bitmapImageRepForCachingDisplay(in: bounds)
        else { return nil }
        widget.cacheDisplay(in: bounds, to: rep)

        let width = rep.pixelsWide
        let height = rep.pixelsHigh
        guard width > 0, height > 0 else { return nil }

        // Converted through an explicit RGBA8 context rather than read out of
        // the representation directly. `NSBitmapImageRep`'s own layout depends
        // on the window's colour space and on whether AppKit chose a planar or
        // meshed arrangement, and `bitmapData` hands back whichever it picked
        // with no error and no hint.
        // 透過一個明確的 RGBA8 context 轉換,而不是直接從那個 representation 讀出來。`NSBitmapImageRep`
        // 自己的排列方式,取決於視窗的色彩空間、以及 AppKit 選擇了 planar 還是 meshed;而 `bitmapData`
        // 會把它挑中的那一種原樣交還,不報錯、也不給任何提示。
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
                ),
                let image = rep.cgImage
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { return nil }
        return WidgetSnapshot(width: width, height: height, rgbaData: rgba)
    }
}
