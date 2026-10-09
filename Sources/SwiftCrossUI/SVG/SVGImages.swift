import Foundation
import ImageFormats

// `<image>` with a `data:` URI (2026-10-10): PNG, JPEG and the other raster
// formats ImageFormats decodes. The picture becomes a paint, and the element a
// rectangle filled with it -- the viewport, or the placed picture where that
// is smaller -- so its edges are antialiased like any other shape's.
// File references and pictures that are SVGs: see SVGImageFiles.swift.
//
// 帶 `data:` URI 的 `<image>`(2026-10-10):PNG、JPEG 以及 ImageFormats 能解碼的其他點陣格式。圖片成為
// 一種塗料，元素則是以它填充的矩形——視窗，或在較小時為放置後的圖片——因此邊緣與其他形狀一樣有抗鋸齒。
// 檔案參照與內容為 SVG 的圖片見 SVGImageFiles.swift。

/// A decoded picture and where its pixels go.
/// 解碼後的圖片，以及其像素的位置。
struct SVGRasterImage: Sendable {
    let width: Int
    let height: Int
    /// Premultiplied RGBA, top row first. / 預乘 RGBA,最上面一列在前。
    let pixels: [Float]
    /// Picture pixels (0...width, 0...height) to the element's user space.
    /// 圖片像素(0...width、0...height)到元素的使用者空間。
    let transform: SVGTransform

    init(_ image: ImageFormats.Image<RGBA>, transform: SVGTransform) {
        width = image.width
        height = image.height
        var pixels = [Float](repeating: 0, count: image.width * image.height * 4)
        let bytes = image.bytes
        for pixel in 0..<(image.width * image.height) {
            let index = pixel * 4
            let alpha = Float(bytes[index + 3]) / 255
            pixels[index] = Float(bytes[index]) / 255 * alpha
            pixels[index + 1] = Float(bytes[index + 1]) / 255 * alpha
            pixels[index + 2] = Float(bytes[index + 2]) / 255 * alpha
            pixels[index + 3] = alpha
        }
        self.pixels = pixels
        self.transform = transform
    }

    /// From pixels already premultiplied, e.g. a filtered layer.
    /// 從已預乘的像素建立，例如濾鏡處理後的圖層。
    init(width: Int, height: Int, premultiplied pixels: [Float], transform: SVGTransform) {
        self.width = width
        self.height = height
        self.pixels = pixels
        self.transform = transform
    }

    /// Bilinear, edges clamped. / 雙線性，邊緣夾住。
    func color(at point: SVGPoint) -> SVGPremultiplied {
        let u = min(max(point.x - 0.5, 0), Double(width - 1))
        let v = min(max(point.y - 0.5, 0), Double(height - 1))
        let x0 = Int(u)
        let y0 = Int(v)
        let x1 = min(x0 + 1, width - 1)
        let y1 = min(y0 + 1, height - 1)
        let fx = Float(u - Double(x0))
        let fy = Float(v - Double(y0))
        let i00 = (y0 * width + x0) * 4
        let i10 = (y0 * width + x1) * 4
        let i01 = (y1 * width + x0) * 4
        let i11 = (y1 * width + x1) * 4
        func channel(_ c: Int) -> Float {
            let top = pixels[i00 + c] + (pixels[i10 + c] - pixels[i00 + c]) * fx
            let bottom = pixels[i01 + c] + (pixels[i11 + c] - pixels[i01 + c]) * fx
            return top + (bottom - top) * fy
        }
        return SVGPremultiplied(red: channel(0), green: channel(1), blue: channel(2), alpha: channel(3))
    }
}

extension SVGBuilder {
    /// The bytes of a `data:` URI, or nil when `href` is not one or is malformed.
    /// `data:` URI 的位元組；`href` 不是 data URI 或格式錯誤時為 nil。
    static func dataURIBytes(_ href: String) -> [UInt8]? {
        let text = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.lowercased().hasPrefix("data:"), let comma = text.firstIndex(of: ",") else {
            return nil
        }
        let header = text[text.index(text.startIndex, offsetBy: 5)..<comma].lowercased()
        let payload = String(text[text.index(after: comma)...])
        if header.hasSuffix(";base64") {
            let compact = payload.filter { !$0.isWhitespace }
            return Data(base64Encoded: compact, options: .ignoreUnknownCharacters).map {
                [UInt8]($0)
            }
        }
        return (payload.removingPercentEncoding ?? payload).utf8.map { $0 }
    }

    /// The nodes of an `<image>`: a raster picture or an SVG, from a `data:`
    /// URI or a file beside the document; `.failure` says why it is not drawn.
    /// `<image>` 的節點：點陣圖片或 SVG,來自 `data:` URI 或文件旁的檔案；`.failure` 說明不繪製的原因。
    func imageNodes(_ element: SVGXMLElement, style: Style, transform: SVGTransform)
        -> Result<[SVGRenderNode], SVGImageProblem>
    {
        guard let href = element[attribute: "href"] ?? element[attribute: "xlink:href"] else {
            return .failure(SVGImageProblem("it has no href"))
        }
        let bytes: [UInt8]
        var source: URL? = nil
        if let data = Self.dataURIBytes(href) {
            bytes = data
        } else {
            switch fileBytes(href) {
                case .success(let found):
                    bytes = found.bytes
                    source = found.url
                case .failure(let problem):
                    return .failure(problem)
            }
        }
        if SVGDocument.looksLikeSVG(bytes) {
            return svgImageNodes(
                bytes, source: source, element: element, style: style, transform: transform)
        }
        guard let picture = try? ImageFormats.Image<RGBA>.load(from: bytes),
            picture.width > 0, picture.height > 0
        else { return .failure(SVGImageProblem("the picture cannot be decoded")) }
        guard style.visible else { return .success([]) }

        // width/height absent or auto: the picture's own size (SVG 2).
        // 沒有 width/height 或為 auto:圖片本身的大小(SVG 2)。
        func size(_ name: String, _ axis: Axis, intrinsic: Int) -> Double {
            guard let text = element[attribute: name], text != "auto" else {
                return Double(intrinsic)
            }
            return length(text, axis: axis) ?? Double(intrinsic)
        }
        let x = element[attribute: "x"].flatMap { length($0, axis: .x) } ?? 0
        let y = element[attribute: "y"].flatMap { length($0, axis: .y) } ?? 0
        let width = size("width", .x, intrinsic: picture.width)
        let height = size("height", .y, intrinsic: picture.height)
        guard width > 0, height > 0 else { return .success([]) }

        let placement = SVGTransform.translate(x, y).concatenating(
            parseAspect(element).transform(
                from: SVGViewBox(
                    x: 0, y: 0, width: Double(picture.width), height: Double(picture.height)),
                toWidth: width, height: height))
        // The drawn rectangle: the placed picture within the viewport (slice
        // overflows the viewport and is cut to it; meet leaves a margin).
        // 畫出的矩形：視窗內放置後的圖片(slice 會超出視窗而被裁到視窗；meet 則留下邊距)。
        let a = placement.apply(SVGPoint(0, 0))
        let b = placement.apply(SVGPoint(Double(picture.width), Double(picture.height)))
        let left = max(min(a.x, b.x), x)
        let right = min(max(a.x, b.x), x + width)
        let top = max(min(a.y, b.y), y)
        let bottom = min(max(a.y, b.y), y + height)
        guard right > left, bottom > top else { return .success([]) }
        var path = SVGPath()
        path.segments = [
            .move(SVGPoint(left, top)), .line(SVGPoint(right, top)),
            .line(SVGPoint(right, bottom)), .line(SVGPoint(left, bottom)), .close,
        ]
        let shape = SVGShape(
            path: path, transform: transform,
            fill: .image(SVGRasterImage(picture, transform: placement)), fillRule: .nonzero,
            stroke: nil, strokeWidth: 0, lineCap: .butt, lineJoin: .miter, miterLimit: 4,
            dashes: nil, dashOffset: 0)
        return .success([.shape(shape)])
    }
}
