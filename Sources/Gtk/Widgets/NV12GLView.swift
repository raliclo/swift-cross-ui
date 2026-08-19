import CGtk
import GtkCHelpers

/// A `GtkGLArea` that draws NV12 video frames, converting them to RGB on the
/// GPU.
///
/// The reason this exists is transport rather than drawing. Handing frames to
/// GTK as `GdkMemoryTexture` requires RGBA, and RGBA at 1080p60 needs 475 MB/s
/// through a decoder pipe that measures between 247 and 416 MB/s, which caps
/// playback at 30-43 fps however fast the decoder is -- hardware decode made no
/// difference at all. NV12 carries the same picture in 12 bits per pixel
/// instead of 32, needing 178 MB/s, but there is no memory-texture format for
/// it and converting on the CPU would return the saving. So the two planes go
/// to the GPU untouched and a fragment shader does the conversion.
///
/// Ownership note: the renderer holds GL objects, which are only valid while
/// this widget's context is current. It is created before realize and its GL
/// side is set up on the first render, because a widget has no context when it
/// is constructed.
public class NV12GLView: GLArea {
    // A var set after `self.init`, not a `let` set in a designated init.
    // GLArea's `init()` is a convenience initialiser, so it cannot be
    // overridden; the pattern the other hand-written widgets use is a
    // convenience init that delegates to the pointer-taking one, and that runs
    // after all stored properties already have values.
    // 這是在 `self.init` 之後設定的 var，而非在 designated init 中設定的 let。GLArea 的
    // `init()` 是 convenience initializer，無法被 override；其他手寫 widget 採用的模式是
    // 由 convenience init 委派給接受指標的那一個，而該流程執行時所有儲存屬性都已具備初值。
    private var renderer: OpaquePointer?
    private var didRealize = false

    /// Set when the shader fails to compile or link. Worth surfacing rather
    /// than leaving the area blank: a blank GL area and a working one that has
    /// received no frame look identical.
    public private(set) var shaderError: String?

    public convenience init() {
        self.init(gtk_gl_area_new())
        // `SCUINV12Renderer` is an opaque struct in C, so Swift imports every
        // reference to it as `OpaquePointer` rather than
        // `UnsafeMutablePointer<SCUINV12Renderer>` -- the type name itself is
        // never visible from Swift. Wrapping or converting the pointer here
        // fails to typecheck for that reason, not because the pointer is wrong.
        // `SCUINV12Renderer` 在 C 中是 opaque struct，因此 Swift 會把對它的所有參照匯入為
        // `OpaquePointer`，而非 `UnsafeMutablePointer<SCUINV12Renderer>`——該型別名稱本身
        // 從 Swift 完全不可見。此處若對指標再做包裝或轉換會無法通過型別檢查，原因在此，
        // 而非指標本身有誤。
        renderer = scui_nv12_renderer_new()

        render = { [weak self] area, _ in
            guard let self else { return }
            self.drawFrame(area)
        }
    }

    deinit {
        scui_nv12_renderer_free(renderer)
    }

    /// Hands one NV12 frame over. `y` is `width * height` bytes and `uv` is
    /// `width * height / 2` bytes of interleaved Cb/Cr, the layout ffmpeg
    /// writes for `-pix_fmt nv12`.
    ///
    /// The upload happens inside the render pass rather than here, because a
    /// GL call without a current context is undefined and the decode thread has
    /// none. The frame is copied so the caller may reuse its buffer.
    public func setFrame(y: [UInt8], uv: [UInt8], width: Int, height: Int) {
        pendingFrame = (y, uv, width, height)
        queueRender()
    }

    private var pendingFrame: (y: [UInt8], uv: [UInt8], width: Int, height: Int)?

    private func drawFrame(_ area: GLArea) {
        guard let handle = renderer else { return }

        if !didRealize {
            didRealize = true
            if scui_nv12_renderer_realize(handle) == 0 {
                shaderError = scui_nv12_renderer_error(handle).map { String(cString: $0) }
                    ?? "unknown shader failure"
                return
            }
        }
        guard shaderError == nil else { return }

        if let frame = pendingFrame {
            pendingFrame = nil
            frame.y.withUnsafeBufferPointer { yBuffer in
                frame.uv.withUnsafeBufferPointer { uvBuffer in
                    scui_nv12_renderer_upload(
                        handle,
                        yBuffer.baseAddress,
                        uvBuffer.baseAddress,
                        Int32(frame.width),
                        Int32(frame.height)
                    )
                }
            }
        }

        // No size passed and no viewport set here. GtkGLArea has already bound
        // its framebuffer and viewport; computing one from
        // `gtk_widget_get_width` times the scale factor gave a different number
        // and drew the frame into the right quarter of the area with the rest
        // black -- which reads as a decode fault rather than a viewport one.
        // 此處不傳尺寸、也不設定 viewport。GtkGLArea 已綁定其 framebuffer 與 viewport；若以
        // `gtk_widget_get_width` 乘上 scale factor 自行計算，會得到不同的數值，導致畫面被繪入
        // 區域右側四分之一、其餘全黑——而該現象看起來像解碼缺陷，而非 viewport 問題。
        scui_nv12_renderer_render(handle)
    }

    public func queueRender() {
        gtk_gl_area_queue_render(castedPointer())
    }
}
