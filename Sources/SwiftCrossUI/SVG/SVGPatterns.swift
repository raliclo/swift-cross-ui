import Foundation

// `<pattern>` paint (2026-10-10), in the core rasteriser like the gradients.
// The tile's content is built once per shape, in tile space; when the shape is
// drawn the tile is rendered at the device's resolution into a small canvas,
// and each pixel of the shape maps back into pattern space, wraps into the
// tile and samples it.
//
// `<pattern>` 塗料(2026-10-10),與漸層一樣在核心點陣化器中。圖塊內容為每個形狀在圖塊空間中建構一次；
// 繪製形狀時，圖塊以裝置解析度畫進一張小畫布，形狀的每個像素映射回圖樣空間、在圖塊內取模後取樣。

/// A `<pattern>`, resolved for one shape. / 為一個形狀解析好的 `<pattern>`。
struct SVGPattern: Sendable {
    /// The tile's content in tile space, the tile's top-left corner at the origin.
    /// 圖塊空間中的圖塊內容，圖塊左上角位於原點。
    var nodes: [SVGRenderNode]
    /// Where the tiles start and how large one is, in pattern space.
    /// 圖塊的起點與單一圖塊的大小，位於圖樣空間。
    var tile: SVGRect
    /// Pattern space to the shape's user space (`patternTransform`).
    /// 圖樣空間到形狀的使用者空間(`patternTransform`)。
    var transform: SVGTransform
}

/// One tile drawn at device resolution, sampled with wrap-around.
/// 以裝置解析度畫好的一個圖塊，取樣時循環。
struct SVGPatternTile {
    let canvas: SVGCanvas
    let tile: SVGRect
    /// Tile pixels per pattern unit. / 每個圖樣單位的圖塊像素數。
    let scaleX: Double
    let scaleY: Double

    func color(at point: SVGPoint) -> SVGPremultiplied {
        var u = (point.x - tile.x).truncatingRemainder(dividingBy: tile.width)
        if u < 0 { u += tile.width }
        var v = (point.y - tile.y).truncatingRemainder(dividingBy: tile.height)
        if v < 0 { v += tile.height }
        let column = min(max(Int(u * scaleX), 0), canvas.width - 1)
        let row = min(max(Int(v * scaleY), 0), canvas.height - 1)
        let index = (row * canvas.width + column) * 4
        return SVGPremultiplied(
            red: canvas.pixels[index], green: canvas.pixels[index + 1],
            blue: canvas.pixels[index + 2], alpha: canvas.pixels[index + 3])
    }

    /// At most this many pixels per tile: a pattern far finer than a pixel is
    /// drawn coarser rather than allocating without bound.
    /// 每個圖塊最多這麼多像素：遠比像素細的圖樣會畫得粗一些，而不是無上限地配置記憶體。
    static let pixelLimit = 4_000_000.0

    /// Renders `pattern`'s tile for drawing through `toPattern` (pattern space
    /// to device pixels); nil when there is nothing to draw.
    /// 為經 `toPattern`(圖樣空間到裝置像素)繪製而畫出 `pattern` 的圖塊；沒有東西可畫時為 nil。
    init?(_ pattern: SVGPattern, toDevice: SVGTransform) {
        guard !pattern.nodes.isEmpty, pattern.tile.width > 0, pattern.tile.height > 0 else {
            return nil
        }
        let scale = max(toDevice.maximumScale, 1e-6)
        var columns = max(1.0, (pattern.tile.width * scale).rounded(.up))
        var rows = max(1.0, (pattern.tile.height * scale).rounded(.up))
        if columns * rows > Self.pixelLimit {
            let shrink = (Self.pixelLimit / (columns * rows)).squareRoot()
            columns = max(1, (columns * shrink).rounded(.down))
            rows = max(1, (rows * shrink).rounded(.down))
        }
        var canvas = SVGCanvas(width: Int(columns), height: Int(rows))
        let scaleX = columns / pattern.tile.width
        let scaleY = rows / pattern.tile.height
        var ignored: [[SVGPoint]] = []
        SVGRenderer.render(
            pattern.nodes, into: &canvas, viewport: .scale(scaleX, scaleY), markers: &ignored)
        self.canvas = canvas
        self.tile = pattern.tile
        self.scaleX = scaleX
        self.scaleY = scaleY
    }
}

extension SVGBuilder {
    /// `element` and the patterns it inherits from through `href`, nearest first.
    /// `element` 以及它經由 `href` 繼承的圖樣，最近的在前。
    func patternChain(_ element: SVGXMLElement) -> [SVGXMLElement] {
        var chain = [element]
        var current = element
        while chain.count < 16, let next = referencedElement(current), next.localName == "pattern",
            !chain.contains(where: { $0 === next })
        {
            chain.append(next)
            current = next
        }
        return chain
    }

    /// The pattern `element` describes, for a shape whose user-space bounding
    /// box is `box`; nil paints nothing (an empty tile, no content, or an empty
    /// box under objectBoundingBox units).
    /// `element` 所描述的圖樣，供使用者空間外框為 `box` 的形狀使用；nil 表示不畫(圖塊為空、沒有內容，
    /// 或在 objectBoundingBox 單位下外框為空)。
    func pattern(_ element: SVGXMLElement, box: SVGRect?) -> SVGPattern? {
        let chain = patternChain(element)
        func attribute(_ name: String) -> String? {
            for link in chain {
                if let value = link[attribute: name] { return value }
            }
            return nil
        }
        let boxUnits = attribute("patternUnits") != "userSpaceOnUse"
        let tile: SVGRect
        if boxUnits {
            guard let box, box.width > 0, box.height > 0 else { return nil }
            func fraction(_ name: String) -> Double {
                guard let text = attribute(name)?.trimmingCharacters(in: .whitespaces) else {
                    return 0
                }
                if text.hasSuffix("%") { return (Double(text.dropLast()) ?? 0) / 100 }
                return Double(text) ?? 0
            }
            tile = SVGRect(
                x: box.x + fraction("x") * box.width, y: box.y + fraction("y") * box.height,
                width: fraction("width") * box.width, height: fraction("height") * box.height)
        } else {
            func value(_ name: String, _ axis: Axis) -> Double {
                attribute(name).flatMap { length($0, axis: axis) } ?? 0
            }
            tile = SVGRect(
                x: value("x", .x), y: value("y", .y), width: value("width", .x),
                height: value("height", .y))
        }
        guard tile.width > 0, tile.height > 0 else { return nil }

        // Content: viewBox first, then patternContentUnits.
        // 內容：先看 viewBox,再看 patternContentUnits。
        var content = SVGTransform.identity
        if let owner = chain.first(where: { $0[attribute: "viewBox"] != nil }) {
            guard let viewBox = parseViewBox(owner) else { return nil }
            content = parseAspect(owner).transform(
                from: viewBox, toWidth: tile.width, height: tile.height)
        } else if attribute("patternContentUnits") == "objectBoundingBox" {
            guard let box, box.width > 0, box.height > 0 else { return nil }
            content = .scale(box.width, box.height)
        }

        var transform = SVGTransform.identity
        if let text = attribute("patternTransform") {
            guard let parsed = SVGTransformParser.parse(text) else {
                report(.invalidValue, element, "patternTransform='\(text)'")
                return nil
            }
            transform = parsed
        }

        // The first pattern in the chain with children supplies them.
        // 鏈中第一個有子元素的圖樣提供內容。
        guard
            let owner = chain.first(where: { link in
                link.children.contains { isSVGElement($0) }
            })
        else { return nil }
        let identity = ObjectIdentifier(owner)
        guard !effectStack.contains(identity) else {
            report(.invalidValue, element, "pattern refers to itself")
            return nil
        }
        effectStack.append(identity)
        defer { effectStack.removeLast() }
        let saved = clipping
        clipping = false
        defer { clipping = saved }
        let style = computeStyle(owner, parent: Style())
        let nodes = buildChildren(of: owner, style: style, transform: content)
        guard !nodes.isEmpty else { return nil }
        return SVGPattern(nodes: nodes, tile: tile, transform: transform)
    }
}
