@_spi(Backends) import SwiftCrossUI
import AndroidKit
import SwiftJava

@JavaClass("java.nio.Buffer")
class JavaNioBuffer: JavaObject {
}

extension JavaClass where JavaClass_T == AndroidKit.ByteBuffer {
    @JavaStaticMethod
    func wrap(_ array: [UInt8]) -> AndroidKit.ByteBuffer?
}

extension AndroidKit.Bitmap {
    @JavaMethod
    func copyPixelsFromBuffer(_ src: JavaNioBuffer?)
}

extension AndroidKit.ImageView {
    @JavaMethod
    func setImageBitmap(_ bm: AndroidKit.Bitmap?)
}

// swiftlint:disable force_try

// implements BackendFeatures.Images
extension AndroidBackend {
    public var requiresImageUpdateOnScaleFactorChange: Bool { false }

    public func createImageView() -> Widget {
        let view = AndroidKit.ImageView(Self.activity, environment: Self.env)
        // Fill the frame the layout gave the image. The core already sized that frame (a
        // `.resizable()` image without `aspectRatio` is stretched), so the default FIT_CENTER
        // kept the bitmap's own aspect a second time: P95's 8x8 swatch, framed 60x24, was
        // drawn 24x24 in the middle of its frame on 2026-10-16 while AppKit filled it.
        // 填滿版面給這張圖的 frame。frame 的大小已由核心決定(沒有 `aspectRatio` 的 `.resizable()` 圖會被拉伸),
        // 預設的 FIT_CENTER 卻再保持一次 bitmap 自己的長寬比:2026-10-16 P95 的 8x8 色塊 frame 為 60x24,
        // 在 Android 上被畫成 frame 中央 24x24,AppKit 則填滿。
        view.setScaleType(try! JavaClass<AndroidKit.ImageView.ScaleType>().FIT_XY)
        return view
    }

    public func updateImageView(
        _ imageView: Widget,
        rgbaData: [UInt8],
        width: Int,
        height: Int,
        targetWidth: Int,
        targetHeight: Int,
        dataHasChanged: Bool,
        environment: EnvironmentValues
    ) {
        guard dataHasChanged else { return }

        let imageView = imageView.as(AndroidKit.ImageView.self)!

        let bitmap = try! JavaClass<AndroidKit.Bitmap>().createBitmap(
            Int32(width),
            Int32(height),
            try! JavaClass<AndroidKit.Bitmap.Config>().ARGB_8888,
            true
        )!

        // copyPixelsFromBuffer copies as is into a premultiplied bitmap. / 原樣複製進預乘的 bitmap。
        let buffer = try! JavaClass<AndroidKit.ByteBuffer>().wrap(ImagePixels.premultiplied(rgbaData))!

        bitmap.copyPixelsFromBuffer(buffer.as(JavaNioBuffer.self)!)

        imageView.setImageBitmap(bitmap)
    }
}
