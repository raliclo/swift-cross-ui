import CGtk
import Foundation
import GtkCHelpers

/// A `GtkGLArea` that draws a Mesh3DView scene with `gtk_mesh3d_gl.c`.
///
/// Holds what the next frame needs -- geometry, per-mesh matrices and flags,
/// light, background -- and draws it in the area's `render` signal, where GTK
/// has made the context current and bound the framebuffer. Geometry is
/// uploaded only when it changed; the matrices are cheap and go every frame.
///
/// 用 `gtk_mesh3d_gl.c` 繪製 Mesh3DView 場景的 `GtkGLArea`。保存下一幀所需的一切——幾何、每個 mesh 的矩陣
/// 與旗標、光、背景——並在 area 的 `render` 信號中繪製；那時 GTK 已讓 context 成為 current 並綁好
/// framebuffer。幾何只在改變時上傳；矩陣很便宜，每幀都送。
public class Mesh3DGLView: GLArea {
    public struct Frame {
        public var modes: [Int32] = []
        public var starts: [Int32] = []
        public var counts: [Int32] = []
        public var pointSizes: [Float] = []
        public var flags: [Int32] = []
        public var mvps: [Float] = []
        public var normals: [Float] = []
        public var light: [Float] = [-0.4, -0.7, -0.6]
        public var background: [Float] = [0, 0, 0, 1]
        public var measuresRenderTime = false

        public init() {}
    }

    private var renderer: OpaquePointer?
    private var didRealize = false
    private var pendingGeometry: (vertices: [Float], indices: [UInt32])?

    public var frame = Frame()
    public private(set) var shaderError: String?
    public private(set) var rendererName = ""
    public private(set) var frameCount = 0
    public private(set) var renderMicros: Int?
    /// The framebuffer GTK last drew into, in device pixels.
    /// GTK 上一次繪製所用的 framebuffer,以裝置像素計。
    public private(set) var drawableSize = SIMD2<Int>(0, 0)
    public var onFrame: (() -> Void)?

    private var captureRequested = false
    private var captured: (width: Int, height: Int, rgba: [UInt8])?

    public convenience init() {
        self.init(gtk_gl_area_new())
        renderer = scui_mesh3d_renderer_new()
        hasDepthBuffer = true
        render = { [weak self] area, _ in
            guard let self else { return false }
            self.drawFrame()
            return true
        }
    }

    deinit {
        scui_mesh3d_renderer_free(renderer)
    }

    public func setGeometry(vertices: [Float], indices: [UInt32]) {
        pendingGeometry = (vertices, indices)
    }

    public func queueRender() {
        gtk_gl_area_queue_render(castedPointer())
    }

    /// Draws a frame now and returns its pixels, RGBA8, top row first, in
    /// device pixels -- what the Metal and GLES paths return. `nil` before the
    /// area is realised.
    /// 現在繪製一幀並回傳其像素：RGBA8、最上列在前、以裝置像素計——與 Metal、GLES 路徑回傳的相同。
    /// area 尚未 realize 時為 `nil`。
    public func snapshot() -> (width: Int, height: Int, rgba: [UInt8])? {
        guard gtk_widget_get_realized(widgetPointer) != 0 else { return nil }
        captureRequested = true
        captured = nil
        queueRender()
        // The render signal runs from the frame clock; drawing synchronously
        // is what gtk_widget_snapshot-free code can do instead: make the
        // context current and run the same frame here.
        // render 信號由 frame clock 驅動；此處改為同步繪製：讓 context 成為 current,在這裡跑同一幀。
        gtk_gl_area_make_current(castedPointer())
        gtk_gl_area_attach_buffers(castedPointer())
        drawFrame()
        captureRequested = false
        return captured
    }

    private func drawFrame() {
        guard let handle = renderer else { return }
        if !didRealize {
            didRealize = true
            if scui_mesh3d_renderer_realize(handle) == 0 {
                shaderError = scui_mesh3d_renderer_error(handle).map { String(cString: $0) }
                    ?? "unknown shader failure"
                return
            }
            rendererName = String(cString: scui_mesh3d_renderer_name(handle))
        }
        guard shaderError == nil else { return }

        if let geometry = pendingGeometry {
            pendingGeometry = nil
            geometry.vertices.withUnsafeBufferPointer { vertices in
                geometry.indices.withUnsafeBufferPointer { indices in
                    scui_mesh3d_renderer_set_geometry(
                        handle, vertices.baseAddress, Int32(vertices.count),
                        indices.baseAddress, Int32(indices.count)
                    )
                }
            }
        }

        let scale = Int(gtk_widget_get_scale_factor(widgetPointer))
        drawableSize = SIMD2(
            Int(gtk_widget_get_width(widgetPointer)) * scale,
            Int(gtk_widget_get_height(widgetPointer)) * scale
        )

        let frame = self.frame
        let meshCount = min(
            frame.modes.count, frame.starts.count, frame.counts.count, frame.pointSizes.count,
            frame.flags.count, frame.mvps.count / 16, frame.normals.count / 16
        )
        let micros = scui_mesh3d_renderer_render(
            handle, Int32(meshCount), frame.modes, frame.starts, frame.counts,
            frame.pointSizes, frame.flags, frame.mvps, frame.normals, frame.light,
            frame.background, frame.measuresRenderTime ? 1 : 0
        )
        renderMicros = micros >= 0 ? Int(micros) : nil
        frameCount += 1

        if captureRequested, drawableSize.x > 0, drawableSize.y > 0 {
            var rgba = [UInt8](repeating: 0, count: drawableSize.x * drawableSize.y * 4)
            rgba.withUnsafeMutableBufferPointer { buffer in
                scui_mesh3d_renderer_read_pixels(
                    Int32(drawableSize.x), Int32(drawableSize.y), buffer.baseAddress
                )
            }
            captured = (drawableSize.x, drawableSize.y, rgba)
        }

        onFrame?()
    }
}
