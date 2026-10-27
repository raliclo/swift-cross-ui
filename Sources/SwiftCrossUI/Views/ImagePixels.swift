/// Pixel conversions shared by backends.
///
/// AppKit (`CGImageAlphaInfo.premultipliedLast`), UIKit (`CIImage` `.RGBA8`),
/// Android (`Bitmap.copyPixelsFromBuffer`) and WinUI (`WriteableBitmap`) all
/// read their pixels as premultiplied, while `ImageFormats` decodes straight
/// bytes. GTK (`GdkPixbuf`) reads straight alpha (by its contract, and measured
/// on macOS with GTK 4.24.1: GtkImageAlphaTests). Handed straight bytes, the
/// four premultiplied readers draw a half-transparent pixel too bright --
/// measured on AppKit: straight (200, 0, 0, 128) drawn over white gave
/// (255, 127, 127), where (227, 127, 127) is correct; CIImage (`.RGBA8`, tried
/// on macOS) gave the same. Android's copyPixelsFromBuffer is documented to
/// copy unchanged into a premultiplied bitmap; it was not measured separately.
/// Translucent pixels are common since SVG rasterisation.
///
/// 各 backend 共用的像素轉換。AppKit、UIKit、Android 與 WinUI 都把像素當成預乘 alpha 讀取，而
/// `ImageFormats` 解碼出的是未預乘位元組；GTK(`GdkPixbuf`)讀的是未預乘(依其規格，並於 macOS 的
/// GTK 4.24.1 實測，見 GtkImageAlphaTests)。拿到未預乘位元組時，那四個以預乘讀取者會把半透明像素畫得偏亮——
/// AppKit 實測：未預乘的 (200, 0, 0, 128) 畫在白色上得到 (255, 127, 127),正確值為 (227, 127, 127)。
/// 自 SVG 點陣化之後，半透明像素變得常見。
@_spi(Backends) public enum ImagePixels {
    /// Straight RGBA to premultiplied RGBA. Returns the input untouched when
    /// every pixel is opaque, which is the common case for photos.
    ///
    /// 未預乘 RGBA 轉為預乘 RGBA。每個像素都不透明時(照片的常見情形)原樣回傳。
    public static func premultiplied(_ rgba: [UInt8]) -> [UInt8] {
        var index = 3
        while index < rgba.count {
            if rgba[index] != 255 { break }
            index += 4
        }
        if index >= rgba.count { return rgba }

        var result = rgba
        result.withUnsafeMutableBufferPointer { pixels in
            var alphaIndex = 3
            while alphaIndex < pixels.count {
                let alpha = UInt32(pixels[alphaIndex])
                if alpha == 0 {
                    pixels[alphaIndex - 3] = 0
                    pixels[alphaIndex - 2] = 0
                    pixels[alphaIndex - 1] = 0
                } else if alpha != 255 {
                    for channel in (alphaIndex - 3)..<alphaIndex {
                        // Rounded division by 255.
                        // 以四捨五入除以 255。
                        let product = UInt32(pixels[channel]) * alpha + 128
                        pixels[channel] = UInt8((product + (product >> 8)) >> 8)
                    }
                }
                alphaIndex += 4
            }
        }
        return result
    }
}
