// Which alpha GDK reads from updateImageView's bytes. GtkBackend hands them
// over unpremultiplied, unlike AppKit, UIKit, Android and WinUI (ImagePixels),
// because a GdkPixbuf with alpha is straight RGBA by contract; this pins it.
// GDK 從 updateImageView 的位元組讀到哪一種 alpha。GtkBackend 不預乘就交出，與經 ImagePixels 的
// AppKit、UIKit、Android、WinUI 不同，因為帶 alpha 的 GdkPixbuf 依規格就是未預乘 RGBA;此測試把它釘住。
#if canImport(GtkBackend)
    import CGtk
    import Testing
    @testable import GtkBackend

    @Suite("GtkBackend image alpha")
    struct GtkImageAlphaTests {
        /// Straight (200, 0, 0, 128) must come back premultiplied as
        /// (100, 0, 0, 128), i.e. (227, 127, 127) over white. Read as already
        /// premultiplied it would stay 200 and give (255, 127, 127) -- the AppKit
        /// defect 6aaab744 fixed.
        /// 未預乘的 (200, 0, 0, 128) 必須讀回為預乘的 (100, 0, 0, 128),即白底上的 (227, 127, 127)。
        /// 若被當成已預乘，它會維持 200、得到 (255, 127, 127)——即 6aaab744 修掉的 AppKit 缺陷。
        @Test("updateImageView's texture reads RGBA as straight alpha")
        @MainActor func straightAlpha() {
            let texture = GtkBackend.texture(fromStraightRGBA: [200, 0, 0, 128], width: 1, height: 1)
            defer { g_object_unref(UnsafeMutableRawPointer(texture)) }
            var pixel = [UInt8](repeating: 0, count: 4)
            pixel.withUnsafeMutableBufferPointer { buffer in
                gdk_texture_download(texture, buffer.baseAddress, 4)
            }
            // gdk_texture_download writes CAIRO_FORMAT_ARGB32: premultiplied,
            // native-endian, so B G R A in memory on every host this runs on.
            // gdk_texture_download 寫出 CAIRO_FORMAT_ARGB32:預乘、原生位元組序，在此執行的主機上記憶體中為 B G R A。
            let (blue, green, red, alpha) = (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]), Int(pixel[3]))
            #expect(alpha == 128)
            #expect(abs(red - 100) <= 1)
            #expect(green == 0 && blue == 0)
            let overWhite = { (premultiplied: Int) in premultiplied + (255 * (255 - alpha) + 127) / 255 }
            #expect(abs(overWhite(red) - 227) <= 1)
            #expect(abs(overWhite(green) - 127) <= 1)
        }
    }
#endif
