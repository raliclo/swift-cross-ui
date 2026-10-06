import CGtk
import Foundation
import Gtk
@_spi(Backends) import SwiftCrossUI

/// `Mesh3DView` on GTK: a `Gtk.Mesh3DGLView` (GtkGLArea) drawing with core GL
/// 3.3. Until 2026-10-06 GtkBackend did not declare `Mesh3DViews`, so a
/// Mesh3DView drew nothing on Linux and on Windows under GTK.
///
/// The scene is packed the way AndroidBackend packs it -- nine floats per
/// vertex, one draw entry per mesh, triangle indices offset into the shared
/// vertex array -- except that indices are 32-bit unconditionally: core GL 3.3
/// has `GL_UNSIGNED_INT` everywhere, so the 16-bit fallback GLES 2 needs has no
/// reason to exist here. Depth range is OpenGL's, -1...1.
///
/// GTK 上的 `Mesh3DView`:一個以 core GL 3.3 繪製的 `Gtk.Mesh3DGLView`(GtkGLArea)。2026-10-06 之前
/// GtkBackend 沒有宣告 `Mesh3DViews`,所以 Mesh3DView 在 Linux 以及 Windows 的 GTK 下什麼都不畫。場景的打包
/// 方式與 AndroidBackend 相同——每個頂點九個 float、每個 mesh 一筆繪製項、三角形索引偏移到共用的頂點陣列——
/// 只是索引一律 32 位元:core GL 3.3 到處都有 `GL_UNSIGNED_INT`,GLES 2 需要的 16 位元退路在這裡沒有存在理由。
/// 深度範圍是 OpenGL 的 -1...1。
extension GtkBackend: BackendFeatures.Mesh3DViews {
    public func createMesh3DView() -> Widget {
        Mesh3DGLView()
    }

    public func updateMesh3DView(
        _ view: Widget,
        scene: Mesh3DScene,
        onFrame: @escaping @MainActor (Mesh3DFrameInfo) -> Void,
        environment: EnvironmentValues
    ) {
        let view = view as! Mesh3DGLView
        var vertices: [Float] = []
        var indices: [UInt32] = []
        var frame = Mesh3DGLView.Frame()
        vertices.reserveCapacity(scene.meshes.reduce(0) { $0 + $1.vertices.count } * 9)

        for mesh in scene.meshes {
            let base = vertices.count / 9
            for vertex in mesh.vertices {
                vertices.append(contentsOf: [
                    vertex.position.x, vertex.position.y, vertex.position.z,
                    vertex.normal.x, vertex.normal.y, vertex.normal.z,
                    vertex.colour.x, vertex.colour.y, vertex.colour.z,
                ])
            }
            let lit: Bool
            switch mesh.primitive {
                case .triangles:
                    let whole = mesh.indices.count - mesh.indices.count % 3
                    frame.modes.append(0)
                    frame.starts.append(Int32(indices.count))
                    frame.counts.append(Int32(whole))
                    frame.pointSizes.append(1)
                    for index in mesh.indices.prefix(whole) {
                        indices.append(UInt32(truncatingIfNeeded: Int(index) + base))
                    }
                    lit = mesh.lit
                case .lines:
                    frame.modes.append(1)
                    frame.starts.append(Int32(base))
                    frame.counts.append(Int32(mesh.vertices.count - mesh.vertices.count % 2))
                    frame.pointSizes.append(1)
                    lit = false
                case .points(let size):
                    frame.modes.append(2)
                    frame.starts.append(Int32(base))
                    frame.counts.append(Int32(mesh.vertices.count))
                    frame.pointSizes.append(max(size, 1))
                    lit = false
            }
            frame.flags.append((lit ? 1 : 0) | (mesh.depthTested ? 2 : 0))
        }

        let width = max(Float(gtk_widget_get_width(view.widgetPointer)), 1)
        let height = max(Float(gtk_widget_get_height(view.widgetPointer)), 1)
        let viewProjection = Mesh3DMatrix4.viewProjection(
            camera: scene.camera,
            aspect: width / height,
            depthRange: .minusOneToOne
        )
        for mesh in scene.meshes {
            frame.mvps.append(contentsOf: (viewProjection * .model(mesh.transform)).elements)
            frame.normals.append(contentsOf: Mesh3DMatrix4.rotation(mesh.transform.rotation).elements)
        }
        let light = scene.lightDirection
        frame.light = [light.x, light.y, light.z]
        let background = scene.background.resolve(in: environment)
        frame.background = [background.red, background.green, background.blue, background.opacity]
        frame.measuresRenderTime = scene.measuresRenderTime

        view.setGeometry(vertices: vertices, indices: indices)
        view.frame = frame
        view.onFrame = { [weak view] in
            guard let view else { return }
            onFrame(
                Mesh3DFrameInfo(
                    renderer: view.rendererName,
                    drawableSize: view.drawableSize,
                    frameCount: view.frameCount,
                    renderMicros: view.renderMicros
                )
            )
        }
        view.queueRender()
    }
}
