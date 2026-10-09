import Foundation

// `<image>` referring to a file, and `<image>` of an SVG (2026-10-10).
//
// A file is read only when the document itself came from a file, and only
// from that file's folder or below: an absolute path, a `../` that climbs out,
// or a network address is refused and reported. An SVG that draws pictures
// should not be a way to read whatever else is on the disk, and a picture
// from the network would make drawing wait on it.
//
// A referenced SVG is not turned into pixels: its nodes are placed into this
// document, moved and scaled into the image's viewport and clipped to it, so
// it stays vector at any size and its text still goes to the platform's text
// engine. What it cannot draw is reported against the `<image>`.
//
// 參照檔案的 `<image>`,以及內容為 SVG 的 `<image>`(2026-10-10)。
//
// 只有當文件本身來自檔案時才讀取檔案，而且只讀該檔案所在的資料夾及其子資料夾：絕對路徑、往外爬的 `../`
// 或網路位址都會被拒絕並回報。一張會畫圖片的 SVG 不應該成為讀取磁碟上其他東西的途徑；來自網路的圖片則會
// 讓繪製等待它。
//
// 被參照的 SVG 不會轉成像素：它的節點被放進本文件，平移與縮放到影像的視窗內並裁切到視窗，因此在任何尺寸下
// 都保持向量，其中的文字仍交給平台的文字引擎。它畫不出來的東西會記在這個 `<image>` 上。

/// Why an `<image>` is not drawn. / `<image>` 不繪製的原因。
struct SVGImageProblem: Error {
    let detail: String
    init(_ detail: String) { self.detail = detail }
}

extension SVGRenderNode {
    /// The same node with `transform` applied in front of all its geometry.
    /// 在所有幾何之前套用 `transform` 後的同一個節點。
    func transformed(by transform: SVGTransform) -> SVGRenderNode {
        switch self {
            case .shape(var shape):
                shape.transform = transform.concatenating(shape.transform)
                return .shape(shape)
            case .group(let opacity, let children):
                return .group(opacity: opacity, children: children.map { $0.transformed(by: transform) })
            case .layer(var effects, let children):
                effects.clip = effects.clip?.map { $0.transformed(by: transform) }
                if var mask = effects.mask {
                    mask.nodes = mask.nodes.map { $0.transformed(by: transform) }
                    mask.region = mask.region.map(transform.apply)
                    effects.mask = mask
                }
                if var filter = effects.filter {
                    filter.transform = transform.concatenating(filter.transform)
                    effects.filter = filter
                }
                return .layer(effects, children: children.map { $0.transformed(by: transform) })
            case .marker(let corners):
                return .marker(corners.map(transform.apply))
            case .text(var node):
                node.transform = transform.concatenating(node.transform)
                node.corners = node.corners.map(transform.apply)
                return .text(node)
        }
    }
}

extension SVGBuilder {
    /// Files read above this size are refused. / 超過此大小的檔案拒絕讀取。
    static let imageFileLimit = 64 * 1024 * 1024
    /// Images inside images, at most this deep. / 影像中的影像，最多這麼多層。
    static let imageNestingLimit = 8

    /// The bytes of the file `href` names, beside the document or below it.
    /// `href` 所指、位於文件旁或其下的檔案位元組。
    func fileBytes(_ href: String) -> Result<(bytes: [UInt8], url: URL), SVGImageProblem> {
        let text = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let base = baseURL, base.isFileURL else {
            return .failure(
                SVGImageProblem(
                    "only data: URIs are read when the document did not come from a file"))
        }
        let lowered = text.lowercased()
        if lowered.contains("://") && !lowered.hasPrefix("file:") {
            return .failure(SVGImageProblem("network address \(text) is not fetched"))
        }
        let folder = base.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
        let target: URL
        if let url = URL(string: text, relativeTo: base), url.scheme == nil || url.isFileURL {
            target = url.absoluteURL
        } else {
            target = URL(fileURLWithPath: text, relativeTo: folder).absoluteURL
        }
        let resolved = target.standardizedFileURL.resolvingSymlinksInPath()
        guard resolved.path.hasPrefix(folder.path + "/") else {
            return .failure(SVGImageProblem("\(text) is outside the document's folder"))
        }
        guard !imageChain.contains(resolved) else {
            return .failure(SVGImageProblem("\(text) refers to itself"))
        }
        let size =
            (try? FileManager.default.attributesOfItem(atPath: resolved.path)[.size] as? Int) ?? nil
        guard let size else { return .failure(SVGImageProblem("\(text) cannot be read")) }
        guard size <= Self.imageFileLimit else {
            return .failure(SVGImageProblem("\(text) is larger than 64 MB"))
        }
        guard let data = try? Data(contentsOf: resolved) else {
            return .failure(SVGImageProblem("\(text) cannot be read"))
        }
        return .success(([UInt8](data), resolved))
    }

    /// The nodes of an `<image>` showing an SVG: the referenced document's
    /// nodes placed into the viewport and clipped to it.
    /// 顯示 SVG 之 `<image>` 的節點：被參照文件的節點放進視窗並裁切到視窗。
    func svgImageNodes(
        _ bytes: [UInt8], source: URL?, element: SVGXMLElement, style: Style,
        transform: SVGTransform
    ) -> Result<[SVGRenderNode], SVGImageProblem> {
        guard imageChain.count < Self.imageNestingLimit else {
            return .failure(SVGImageProblem("images nested more than \(Self.imageNestingLimit) deep"))
        }
        guard let root = try? SVGXMLReader.parse(bytes), root.localName == "svg" else {
            return .failure(SVGImageProblem("the SVG it refers to cannot be parsed"))
        }
        let chain = imageChain + (source.map { [$0] } ?? [])
        let nested = Self.build(root: root, baseURL: source ?? baseURL, chain: chain)
        let label = source?.lastPathComponent ?? "data: SVG"
        for diagnostic in nested.diagnostics {
            for _ in 0..<max(diagnostic.count, 1) {
                report(diagnostic.kind, element, "in \(label): \(diagnostic.detail)")
            }
        }
        guard style.visible else { return .success([]) }

        func size(_ name: String, _ axis: Axis, intrinsic: Double) -> Double {
            guard let text = element[attribute: name], text != "auto" else { return intrinsic }
            return length(text, axis: axis) ?? intrinsic
        }
        let x = element[attribute: "x"].flatMap { length($0, axis: .x) } ?? 0
        let y = element[attribute: "y"].flatMap { length($0, axis: .y) } ?? 0
        let width = size("width", .x, intrinsic: nested.width)
        let height = size("height", .y, intrinsic: nested.height)
        let box = nested.viewBox ?? SVGViewBox(x: 0, y: 0, width: nested.width, height: nested.height)
        guard width > 0, height > 0, box.width > 0, box.height > 0 else { return .success([]) }

        // The <image>'s preserveAspectRatio places the picture, as for a raster one.
        // <image> 的 preserveAspectRatio 決定圖片位置，與點陣圖相同。
        let place = transform.concatenating(.translate(x, y)).concatenating(
            parseAspect(element).transform(from: box, toWidth: width, height: height))
        let nodes = nested.nodes.map { $0.transformed(by: place) }
        guard !nodes.isEmpty else { return .success([]) }
        var path = SVGPath()
        path.segments = [
            .move(SVGPoint(x, y)), .line(SVGPoint(x + width, y)),
            .line(SVGPoint(x + width, y + height)), .line(SVGPoint(x, y + height)), .close,
        ]
        let viewport = SVGShape(
            path: path, transform: transform, fill: .color(Self.clipWhite), fillRule: .nonzero,
            stroke: nil, strokeWidth: 0, lineCap: .butt, lineJoin: .miter, miterLimit: 4,
            dashes: nil, dashOffset: 0)
        return .success([
            .layer(SVGLayerEffects(opacity: 1, clip: [.shape(viewport)], mask: nil), children: nodes)
        ])
    }
}
