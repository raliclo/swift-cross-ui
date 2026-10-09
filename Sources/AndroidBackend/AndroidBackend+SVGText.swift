import AndroidKit
@_spi(Backends) import SwiftCrossUI
import SwiftJava

/// The Swift side of `SVGTextMasker.kt`.
/// `SVGTextMasker.kt` 的 Swift 側。
@JavaClass("dev.swiftcrossui.androidbackend.SVGTextMasker")
class AndroidSVGTextMasker: JavaObject {
    @JavaMethod
    @_nonoverride convenience init(environment: JNIEnvironment? = nil)

    @JavaMethod
    func mask(
        _ text: String, _ families: String, _ size: Double, _ bold: Bool, _ italic: Bool,
        _ anchor: Int32, _ a: Double, _ b: Double, _ c: Double, _ d: Double, _ tx: Double,
        _ ty: Double, _ width: Int32, _ height: Int32, _ strokeWidth: Double
    ) -> [Int8]
}

/// SVG `<text>` through Android's text engine; see `SVGTextMasker.kt`.
/// 經由 Android 的文字引擎繪製 SVG `<text>`;見 `SVGTextMasker.kt`。
extension AndroidBackend: BackendFeatures.SVGText {
    /// One Java object for the process: building one costs a class lookup.
    /// 整個程序共用一個 Java 物件：每建立一個都要花一次類別查找。
    @MainActor static var svgTextMasker: AndroidSVGTextMasker?

    public func svgTextMask(_ request: SVGTextMaskRequest) -> [UInt8]? {
        let masker = Self.svgTextMasker ?? AndroidSVGTextMasker(environment: Self.env)
        Self.svgTextMasker = masker
        let run = request.run
        let t = request.transform
        let anchor: Int32 =
            switch run.anchor {
                case .start: 0
                case .middle: 1
                case .end: 2
            }
        let bytes = masker.mask(
            run.text, run.fontFamilies.joined(separator: ","), run.fontSize, run.isBold,
            run.isItalic, anchor, t.a, t.b, t.c, t.d, t.tx, t.ty, Int32(request.width),
            Int32(request.height), request.strokeWidth ?? -1)
        guard bytes.count == request.width * request.height else { return nil }
        return bytes.map { UInt8(bitPattern: $0) }
    }
}
