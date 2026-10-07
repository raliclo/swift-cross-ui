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
    /// The geometry last uploaded, re-sent after the context is recreated.
    /// 最後一次上傳的幾何，context 重建後重新送出。
    private var uploadedGeometry: (vertices: [Float], indices: [UInt32])?

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
        connectUnrealize()
        render = { [weak self] area, _ in
            guard let self else { return false }
            self.drawFrame()
            return true
        }
    }

    deinit {
        if unrealizeHandlerID != 0 {
            g_signal_handler_disconnect(UnsafeMutableRawPointer(widgetPointer), unrealizeHandlerID)
        }
        scui_mesh3d_renderer_free(renderer)
    }

    /// The GL objects belong to the area's context, and GTK destroys that context
    /// on unrealize -- removing the view and adding it back, or moving it to
    /// another window, gives it a new one. So the objects are deleted here,
    /// while the old context is still current (this handler runs before
    /// GtkGLArea's own), the renderer is marked unrealised, and the last
    /// geometry is queued again for the next context. Until 2026-10-07 the
    /// renderer kept the dead handles (review, Codex).
    /// GL 物件屬於 area 的 context,而 GTK 在 unrealize 時會銷毀它——移除再加回 view、或移到另一個視窗，都會拿到
    /// 新的 context。所以在這裡、舊 context 仍為 current 時(此處理器在 GtkGLArea 自己的之前執行)刪除物件，把
    /// renderer 標為未初始化，並把最後的幾何重新排入，給下一個 context。2026-10-07 之前 renderer 會沿用失效的
    /// handle(review,Codex)。
    private var unrealizeHandlerID: gulong = 0

    /// Connected with `g_signal_connect_data` and no AFTER flag, not through
    /// `addSignal`: that connects AFTER, and by then GtkGLArea's own unrealize
    /// has destroyed the context -- measured, "gtk_gl_area_make_current:
    /// assertion gtk_widget_get_realized failed". Connected once, in `init`,
    /// rather than in `registerSignals`, which runs again on every reparent.
    /// 以 `g_signal_connect_data` 且不帶 AFTER 連接，而不是經由 `addSignal`:後者以 AFTER 連接，那時 GtkGLArea
    /// 自己的 unrealize 已經銷毀了 context——實測出現「gtk_gl_area_make_current: assertion
    /// gtk_widget_get_realized failed」。只在 `init` 中連接一次，不放在每次換 parent 都會重跑的 `registerSignals`。
    private func connectUnrealize() {
        let handler: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void = {
            _, data in
            guard let data else { return }
            Unmanaged<Mesh3DGLView>.fromOpaque(data).takeUnretainedValue().releaseGL()
        }
        unrealizeHandlerID = g_signal_connect_data(
            UnsafeMutableRawPointer(widgetPointer),
            "unrealize",
            unsafeBitCast(handler, to: GCallback.self),
            Unmanaged.passUnretained(self).toOpaque(),
            nil,
            SHIM_G_CONNECT_DEFAULT
        )
    }

    private func releaseGL() {
        guard let handle = renderer, didRealize else { return }
        gtk_gl_area_make_current(castedPointer())
        if gtk_gl_area_get_error(castedPointer()) == nil {
            scui_mesh3d_renderer_release(handle)
        }
        didRealize = false
        shaderError = nil
        if pendingGeometry == nil {
            pendingGeometry = uploadedGeometry
        }
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
                // Said once, on stderr: the view otherwise stays blank with no
                // sign of why -- under WSLg a GLES context rejected the GL 3.3
                // shaders and nothing anywhere reported it (2026-10-07).
                // 在 stderr 說一次：否則 view 只是一片空白、看不出原因——WSLg 下 GLES context 拒絕了 GL 3.3
                // 的 shader,而任何地方都沒有回報(2026-10-07)。
                FileHandle.standardError.write(Data("Mesh3DGLView: \(shaderError ?? "")\n".utf8))
                return
            }
            rendererName = String(cString: scui_mesh3d_renderer_name(handle))
        }
        guard shaderError == nil else { return }

        if let geometry = pendingGeometry {
            pendingGeometry = nil
            uploadedGeometry = geometry
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
