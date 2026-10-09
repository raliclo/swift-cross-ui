import Foundation
import ImageFormats

/// Something in an SVG file that this renderer did not draw as written.
///
/// Nothing the renderer skips is skipped silently: every element, attribute
/// or value it cannot honour becomes one of these, and in the rasterised
/// image the place it would have been is outlined in magenta (with a magenta
/// flag in the top-left corner whenever the list is not empty). Identical
/// reports are merged and counted.
///
/// SVG 檔案中本算繪器沒有照原樣畫出的東西。
///
/// 算繪器略過的任何東西都不會被靜默略過：每一個它無法遵循的元素、屬性或值都會成為一筆這樣的紀錄，
/// 而在點陣化的影像中，它原本所在的位置會以洋紅色框出(只要清單不是空的，左上角還會有一個洋紅色
/// 旗標)。相同的紀錄會合併並計數。
public struct SVGDiagnostic: Sendable, Hashable, CustomStringConvertible {
    public enum Kind: String, Sendable, Hashable {
        /// An element this renderer does not draw, e.g. visible `<text>`, `<image>`.
        /// 本算繪器不繪製的元素，例如可見的 `<text>`、`<image>`。
        case unsupportedElement
        /// Visible `<text>`: drawn by the backend's text renderer
        /// (``BackendFeatures/SVGText``), outlined in magenta where there is none.
        /// 可見的 `<text>`:由 backend 的文字繪製器(``BackendFeatures/SVGText``)繪製，沒有時以洋紅色框出。
        case textNeedsRenderer
        /// An attribute or property it does not apply, e.g. `clip-path`, `filter`.
        /// 本算繪器不套用的屬性，例如 `clip-path`、`filter`。
        case unsupportedAttribute
        /// A supported property with a value it cannot use, e.g. a gradient paint.
        /// 受支援的屬性，但其值無法使用，例如漸層塗料。
        case unsupportedValue
        /// Something malformed: bad path data, an unknown colour, a broken reference.
        /// 格式錯誤：路徑資料錯誤、未知顏色、斷掉的參照。
        case invalidValue
    }

    public var kind: Kind
    /// The element it was found on, without namespace prefix.
    /// 發現它的元素，不含命名空間前綴。
    public var element: String
    public var detail: String
    /// How many times this exact report occurred.
    /// 這筆完全相同的紀錄出現的次數。
    public var count: Int

    public var description: String {
        let times = count > 1 ? " (x\(count))" : ""
        return "\(kind.rawValue) <\(element)>: \(detail)\(times)"
    }
}

/// A parsed SVG document that can be rasterised at any size.
///
/// Pure Swift: the same parser and rasteriser run on every backend, so an SVG
/// looks the same on AppKit, UIKit, GTK, WinUI and Android -- no backend's
/// own SVG support is involved. ``Image`` uses it for `.svg` files and
/// re-rasterises at the size the image is displayed at.
///
/// Supported: `svg` (`width`/`height` in any CSS unit, `viewBox`,
/// `preserveAspectRatio`), `g`, `a`, `use`, `switch`, `path` (every command,
/// relative and absolute), `rect` (with `rx`/`ry`), `circle`, `ellipse`,
/// `line`, `polyline`, `polygon`; `fill`, `stroke`, `stroke-width`, `opacity`
/// (as a group), `fill-opacity`, `stroke-opacity`, `fill-rule`,
/// `stroke-linecap`, `stroke-linejoin`, `stroke-miterlimit`,
/// `stroke-dasharray`, `stroke-dashoffset`, `color`/`currentColor`,
/// `display`, `visibility`; `transform` (`matrix`, `translate`, `scale`,
/// `rotate`, `skewX`, `skewY`); colour keywords, `#rgb[a]`, `#rrggbb[aa]`,
/// `rgb[a]()`, `hsl[a]()`; the `style` attribute and `<style>` sheets with
/// simple selectors. Everything else is listed in ``diagnostics``.
///
/// 一份已解析、可以任意尺寸點陣化的 SVG 文件。
///
/// 純 Swift:同一套解析器與點陣化器在每一個 backend 上執行，因此一張 SVG 在 AppKit、UIKit、GTK、
/// WinUI 與 Android 上看起來都一樣——不牽涉任何 backend 自己的 SVG 支援。``Image`` 以它處理 `.svg`
/// 檔，並以影像實際顯示的尺寸重新點陣化。支援項目見上方英文清單；其餘一律列在 ``diagnostics`` 中。
public struct SVGDocument: Sendable, Equatable {
    final class Storage: Sendable {
        let nodes: [SVGRenderNode]
        let width: Double
        let height: Double
        let viewBox: SVGViewBox?
        let aspect: SVGAspectRatio
        let diagnostics: [SVGDiagnostic]

        init(
            nodes: [SVGRenderNode], width: Double, height: Double, viewBox: SVGViewBox?,
            aspect: SVGAspectRatio, diagnostics: [SVGDiagnostic]
        ) {
            self.nodes = nodes
            self.width = width
            self.height = height
            self.viewBox = viewBox
            self.aspect = aspect
            self.diagnostics = diagnostics
        }
    }

    let storage: Storage

    /// The document's own width in CSS pixels (96 per inch), from its `width`
    /// attribute, else its `viewBox`, else 300.
    /// 文件自身的寬度，以 CSS 像素(每英吋 96)計：取自 `width` 屬性，否則取自 `viewBox`,否則為 300。
    public var width: Double { storage.width }
    /// The document's own height in CSS pixels; see ``width``.
    /// 文件自身的高度，以 CSS 像素計；見 ``width``。
    public var height: Double { storage.height }
    /// Everything this renderer did not draw as written. Empty for a fully
    /// supported file.
    /// 本算繪器沒有照原樣畫出的一切。完全受支援的檔案為空。
    public var diagnostics: [SVGDiagnostic] { storage.diagnostics }

    public static func == (lhs: SVGDocument, rhs: SVGDocument) -> Bool {
        lhs.storage === rhs.storage
    }

    /// Parses SVG source. Throws ``SVGParseError`` when the XML is malformed
    /// or the root element is not `<svg>`; anything less serious ends up in
    /// ``diagnostics`` instead.
    ///
    /// 解析 SVG 原始碼。XML 格式錯誤或根元素不是 `<svg>` 時拋出 ``SVGParseError``;不那麼嚴重的
    /// 問題則記入 ``diagnostics``。
    public init(data: [UInt8]) throws {
        let root = try SVGXMLReader.parse(data)
        guard root.localName == "svg" else {
            throw SVGParseError(offset: 0, message: "the root element is <\(root.name)>, not <svg>")
        }
        storage = SVGBuilder.build(root: root)
    }

    public init(string: String) throws {
        try self.init(data: Array(string.utf8))
    }

    /// Reads a local file. Remote URLs are refused, as in ``Image``.
    /// 讀取本機檔案。遠端 URL 會被拒絕，與 ``Image`` 相同。
    public init(contentsOf url: URL) throws {
        guard url.isFileURL else {
            throw SVGParseError(offset: 0, message: "only file URLs are read: \(url)")
        }
        try self.init(data: Array(try Data(contentsOf: url)))
    }

    init(storage: Storage) {
        self.storage = storage
    }

    /// A document that draws only the unsupported-content marker, for a file
    /// that could not be parsed at all. ``Image`` shows this rather than
    /// nothing, so a broken file is visible.
    ///
    /// 只畫出「不支援內容」標記的文件，用於完全無法解析的檔案。``Image`` 顯示它而不是什麼都不顯示，
    /// 讓壞掉的檔案看得見。
    static func unreadable(_ error: Error) -> SVGDocument {
        let size = 24.0
        let marker = SVGRenderNode.marker([
            SVGPoint(0, 0), SVGPoint(size, 0), SVGPoint(size, size), SVGPoint(0, size),
        ])
        return SVGDocument(
            storage: Storage(
                nodes: [marker], width: size, height: size, viewBox: nil,
                aspect: SVGAspectRatio(),
                diagnostics: [
                    SVGDiagnostic(
                        kind: .invalidValue, element: "svg", detail: "\(error)", count: 1)
                ]))
    }

    /// Whether `bytes` look like SVG source (and not, say, a PNG).
    /// `bytes` 看起來是否為 SVG 原始碼(而不是，例如，PNG)。
    public static func looksLikeSVG(_ bytes: [UInt8]) -> Bool {
        let head = bytes.prefix(4096)
        guard let text = String(bytes: head, encoding: .utf8)
            ?? String(bytes: head.dropLast(3), encoding: .utf8)
        else { return false }
        let trimmed = text.drop(while: { $0.isWhitespace || $0 == "\u{FEFF}" })
        if trimmed.hasPrefix("<svg") { return true }
        guard trimmed.hasPrefix("<?xml") || trimmed.hasPrefix("<!") else { return false }
        return trimmed.contains("<svg")
    }

    /// Rasterises the document into `width` x `height` pixels, honouring its
    /// `preserveAspectRatio` (by default centred and scaled to fit). The
    /// result has straight alpha and a transparent background.
    ///
    /// - Parameter showsUnsupportedMarkers: Draw the magenta outlines and
    ///   corner flag for ``diagnostics``. ``Image`` always passes `true`.
    /// - Parameter textMasker: Draws `<text>` (see ``SVGTextMaskRequest``);
    ///   ``Image`` passes the backend's when it has ``BackendFeatures/SVGText``.
    ///   Without one, text is outlined like anything else not drawn.
    ///
    /// 把文件點陣化成 `width` x `height` 像素，遵循其 `preserveAspectRatio`(預設為置中並等比縮放
    /// 至容納)。結果為未預乘 alpha、背景透明。`showsUnsupportedMarkers`:為 ``diagnostics`` 畫出
    /// 洋紅色外框與角落旗標；``Image`` 一律傳 `true`。
    public func rasterize(
        width: Int, height: Int, showsUnsupportedMarkers: Bool = true,
        textMasker: SVGTextMasker? = nil
    ) -> ImageFormats.Image<RGBA> {
        let pixelWidth = max(0, width)
        let pixelHeight = max(0, height)
        var canvas = SVGCanvas(width: pixelWidth, height: pixelHeight)
        if pixelWidth > 0 && pixelHeight > 0 {
            let box =
                storage.viewBox
                ?? SVGViewBox(x: 0, y: 0, width: storage.width, height: storage.height)
            let viewport = storage.aspect.transform(
                from: box, toWidth: Double(pixelWidth), height: Double(pixelHeight))
            var markers: [[SVGPoint]] = []
            SVGRenderer.render(
                storage.nodes, into: &canvas, viewport: viewport, markers: &markers,
                textMasker: textMasker)
            // Drawn text is not a gap; anything else listed, or any text left undrawn, is.
            // 已畫出的文字不算缺漏；其他被列出的項目，或任何沒畫出的文字，才算。
            let undrawn =
                !markers.isEmpty || storage.diagnostics.contains { $0.kind != .textNeedsRenderer }
            if showsUnsupportedMarkers && undrawn {
                SVGRenderer.drawMarkers(markers, into: &canvas)
            }
        }
        return ImageFormats.Image<RGBA>(
            width: pixelWidth, height: pixelHeight, bytes: canvas.straightRGBABytes())
    }
}

// MARK: - Render tree / 算繪樹

struct SVGViewBox: Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

/// `preserveAspectRatio`.
struct SVGAspectRatio: Equatable, Sendable {
    /// -1, 0, 1 for min, mid, max; `nil` alignment means `none`.
    /// -1、0、1 分別為 min、mid、max;`nil` 表示 `none`。
    var alignX: Int? = 0
    var alignY: Int? = 0
    var slice = false

    static func parse(_ text: String?) -> SVGAspectRatio? {
        guard let text else { return SVGAspectRatio() }
        var words = text.split(separator: " ").map(String.init)
        if words.first == "defer" { words.removeFirst() }
        guard let align = words.first else { return nil }
        var result = SVGAspectRatio()
        if words.count > 1 {
            switch words[1] {
                case "meet": result.slice = false
                case "slice": result.slice = true
                default: return nil
            }
        }
        if align == "none" {
            result.alignX = nil
            result.alignY = nil
            return result
        }
        let table = ["Min": -1, "Mid": 0, "Max": 1]
        guard align.count == 8, align.hasPrefix("x"),
            let x = table[String(align.dropFirst().prefix(3))],
            align.dropFirst(4).hasPrefix("Y"),
            let y = table[String(align.suffix(3))]
        else { return nil }
        result.alignX = x
        result.alignY = y
        return result
    }

    func transform(from box: SVGViewBox, toWidth width: Double, height: Double) -> SVGTransform {
        guard box.width > 0, box.height > 0 else { return .identity }
        var scaleX = width / box.width
        var scaleY = height / box.height
        guard let alignX, let alignY else {
            return SVGTransform.scale(scaleX, scaleY).concatenating(.translate(-box.x, -box.y))
        }
        let scale = slice ? max(scaleX, scaleY) : min(scaleX, scaleY)
        scaleX = scale
        scaleY = scale
        let freeX = width - box.width * scale
        let freeY = height - box.height * scale
        let offsetX = freeX * Double(alignX + 1) / 2
        let offsetY = freeY * Double(alignY + 1) / 2
        return SVGTransform.translate(offsetX, offsetY)
            .concatenating(.scale(scaleX, scaleY))
            .concatenating(.translate(-box.x, -box.y))
    }
}

struct SVGShape: Sendable {
    var path: SVGPath
    /// From the shape's user space to the root viewBox space.
    /// 從形狀的使用者空間到根 viewBox 空間。
    var transform: SVGTransform
    /// Fill colour with `fill-opacity` already applied; `nil` for none.
    /// 已套用 `fill-opacity` 的填充色；`nil` 表示無。
    var fill: SVGPaintValue?
    var fillRule: SVGFillRule
    var stroke: SVGPaintValue?
    var strokeWidth: Double
    var lineCap: SVGLineCap
    var lineJoin: SVGLineJoin
    var miterLimit: Double
    var dashes: [Double]?
    var dashOffset: Double
}

indirect enum SVGRenderNode: Sendable {
    case shape(SVGShape)
    /// Children drawn into their own layer, then composited at `opacity`.
    /// 子節點畫進自己的圖層，再以 `opacity` 合成。
    case group(opacity: Double, children: [SVGRenderNode])
    /// Where something unsupported would have been drawn: four corners in
    /// root viewBox space.
    /// 某個不支援之物原本會被畫出的位置：根 viewBox 空間中的四個角。
    case marker([SVGPoint])
    /// A `<text>` run, drawn by the backend's text renderer when there is one.
    /// 一段 `<text>`,有 backend 文字繪製器時由它繪製。
    case text(SVGTextNode)
}

// MARK: - Rendering / 算繪

enum SVGRenderer {
    /// Curves are flattened to within this many device pixels. Chords lie
    /// inside a curve, so the error is always a loss of area: at 0.1 a
    /// 15 px circle lost 0.6% (702.6 of 706.9 px), which the coverage tests
    /// caught; at 0.025 the loss is about a quarter of that.
    /// 曲線平坦化到與真實曲線相距不超過這麼多裝置像素。弦位於曲線內側，所以誤差一律是面積的損失：
    /// 在 0.1 時半徑 15 px 的圓少了 0.6%(706.9 中的 702.6 px),被覆蓋率測試抓到；0.025 時約為其四分之一。
    static let tolerance = 0.025

    static func render(
        _ nodes: [SVGRenderNode], into canvas: inout SVGCanvas, viewport: SVGTransform,
        markers: inout [[SVGPoint]], textMasker: SVGTextMasker? = nil
    ) {
        for node in nodes {
            switch node {
                case .shape(let shape):
                    draw(shape, into: &canvas, viewport: viewport)
                case .group(let opacity, let children):
                    var layer = SVGCanvas(width: canvas.width, height: canvas.height)
                    render(
                        children, into: &layer, viewport: viewport, markers: &markers,
                        textMasker: textMasker)
                    canvas.composite(layer, opacity: opacity)
                case .text(let node):
                    drawText(
                        node, into: &canvas, viewport: viewport, textMasker: textMasker,
                        markers: &markers)
                case .marker(let corners):
                    markers.append(corners.map { viewport.apply($0) })
            }
        }
    }

    /// Draws `node` through the backend's text mask (fill, then stroke), or
    /// records its outline when there is no text renderer or it drew nothing.
    /// 經 backend 的文字遮罩繪製 `node`(先填色、再描邊);沒有文字繪製器或它什麼都沒畫時，記錄其外框。
    static func drawText(
        _ node: SVGTextNode, into canvas: inout SVGCanvas, viewport: SVGTransform,
        textMasker: SVGTextMasker?, markers: inout [[SVGPoint]]
    ) {
        let device = viewport.concatenating(node.transform)
        guard let textMasker, device.isInvertible else {
            markers.append(node.corners.map { viewport.apply($0) })
            return
        }
        let transform = SVGTextTransform(
            a: device.a, b: device.b, c: device.c, d: device.d, tx: device.e, ty: device.f)
        let size = canvas.width * canvas.height
        var drew = false
        if let fill = node.fill,
            let mask = textMasker(
                SVGTextMaskRequest(
                    run: node.run, transform: transform, width: canvas.width,
                    height: canvas.height)),
            mask.count == size
        {
            if let shader = fill.shader(device: device) { canvas.fill(mask: mask, shader: shader) }
            drew = true
        }
        if let stroke = node.stroke, node.strokeWidth > 0,
            let mask = textMasker(
                SVGTextMaskRequest(
                    run: node.run, transform: transform, width: canvas.width,
                    height: canvas.height, strokeWidth: node.strokeWidth)),
            mask.count == size
        {
            if let shader = stroke.shader(device: device) { canvas.fill(mask: mask, shader: shader) }
            drew = true
        }
        if !drew {
            markers.append(node.corners.map { viewport.apply($0) })
        }
    }

    static func draw(_ shape: SVGShape, into canvas: inout SVGCanvas, viewport: SVGTransform) {
        let device = viewport.concatenating(shape.transform)
        guard device.isInvertible else { return }
        let userTolerance = tolerance / device.maximumScale
        let polylines = shape.path.flattened(tolerance: userTolerance)

        if let fill = shape.fill {
            let polygons = polylines.map { $0.points.map(device.apply) }
            if let shader = fill.shader(device: device) {
                canvas.fill(polygons, rule: shape.fillRule, shader: shader)
            }
        }
        if let stroke = shape.stroke, shape.strokeWidth > 0 {
            var lines = polylines
            if let dashes = shape.dashes {
                lines = SVGStroker.dash(lines, pattern: dashes, offset: shape.dashOffset)
            }
            let stroker = SVGStroker(
                halfWidth: shape.strokeWidth / 2, cap: shape.lineCap, join: shape.lineJoin,
                miterLimit: shape.miterLimit, tolerance: userTolerance)
            let polygons = stroker.stroke(lines).map { $0.map(device.apply) }
            if let shader = stroke.shader(device: device) {
                canvas.fill(polygons, rule: .nonzero, shader: shader)
            }
        }
    }

    /// Magenta outline and cross over each unsupported element, plus a flag
    /// in the top-left corner so a diagnostic with no position is seen too.
    ///
    /// 在每一個不支援的元素上畫洋紅色外框與叉，並在左上角畫一個旗標，讓沒有位置的診斷也看得見。
    static func drawMarkers(_ markers: [[SVGPoint]], into canvas: inout SVGCanvas) {
        let color = SVGColor.unsupportedMarker
        let stroker = SVGStroker(
            halfWidth: 1, cap: .butt, join: .miter, miterLimit: 4, tolerance: tolerance)
        for corners in markers where corners.count == 4 {
            let outline = SVGPolyline(points: corners, closed: true)
            let cross1 = SVGPolyline(points: [corners[0], corners[2]], closed: false)
            let cross2 = SVGPolyline(points: [corners[1], corners[3]], closed: false)
            canvas.fill(stroker.stroke([outline, cross1, cross2]), rule: .nonzero, color: color)
        }
        let flag = max(6, Double(min(canvas.width, canvas.height)) * 0.06)
        canvas.fill(
            [[SVGPoint(0, 0), SVGPoint(flag, 0), SVGPoint(0, flag)]], rule: .nonzero, color: color)
    }
}
