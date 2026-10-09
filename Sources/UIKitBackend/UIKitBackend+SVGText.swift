@_spi(Backends) import SwiftCrossUI

/// SVG `<text>` through Core Text; see `SVGCoreTextMasker`.
/// 經由 Core Text 繪製 SVG `<text>`;見 `SVGCoreTextMasker`。
extension UIKitBackend: BackendFeatures.SVGText {
    public func svgTextMask(_ request: SVGTextMaskRequest) -> [UInt8]? {
        SVGCoreTextMasker.mask(request)
    }
}
