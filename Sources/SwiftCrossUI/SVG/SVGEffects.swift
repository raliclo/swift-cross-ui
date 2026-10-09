import Foundation

// `clip-path` and `mask` (2026-10-10). Both are drawn by the core rasteriser,
// so every backend has them: the element's nodes go into a layer of their own,
// the layer is multiplied pixel by pixel by the clip's coverage and the mask's
// value, and the result is composited at the element's opacity -- the order
// SVG gives (opacity, clip and mask all act on the element as a whole).
//
// `clip-path` 與 `mask`(2026-10-10)。兩者都由核心點陣化器繪製，因此每個 backend 都有：元素的節點畫進
// 自己的圖層，圖層逐像素乘上裁切的覆蓋率與遮罩的值，再以元素的不透明度合成——這是 SVG 規定的順序
// (不透明度、裁切與遮罩都作用在整個元素上)。

/// What acts on a layer as a whole. / 作用在整個圖層上的東西。
struct SVGLayerEffects: Sendable {
    var opacity: Double
    /// Drawn as opaque white; their coverage is where the layer shows. `nil`
    /// for no clip; empty clips everything away.
    /// 以不透明白色繪製；其覆蓋率就是圖層顯示之處。`nil` 表示不裁切；空陣列則全部裁掉。
    var clip: [SVGRenderNode]?
    var mask: SVGMaskLayer?
    /// Run on the layer first, before the clip and the mask (see SVGFilters.swift).
    /// 最先在圖層上執行，在裁切與遮罩之前(見 SVGFilters.swift)。
    var filter: SVGFilter? = nil
}

/// A `<mask>`, ready to draw. / 準備好可繪製的 `<mask>`。
struct SVGMaskLayer: Sendable {
    /// The mask's content, drawn like any other nodes.
    /// 遮罩的內容，與其他節點一樣繪製。
    var nodes: [SVGRenderNode]
    /// `mask-type: luminance` (the default) rather than `alpha`.
    /// `mask-type: luminance`(預設)而非 `alpha`。
    var luminance: Bool
    /// The mask region, root viewBox space; outside it the mask is 0. Empty
    /// when the region is empty, which hides the element.
    /// 遮罩區域，根 viewBox 空間；區域外遮罩為 0。區域為空時為空陣列，元素因此不顯示。
    var region: [SVGPoint]
}

extension SVGBuilder {
    /// How a shape inside a <clipPath> is filled: its coverage is all that is read.
    /// <clipPath> 內的形狀以此填充：只讀取它的覆蓋率。
    static let clipWhite = SVGColor(red: 1, green: 1, blue: 1)

    /// The element a `url(#id)` reference names, if any.
    /// `url(#id)` 參照所指的元素(若有)。
    func element(referencedBy reference: String) -> SVGXMLElement? {
        let value = reference.trimmingCharacters(in: .whitespaces)
        guard value.hasPrefix("url("), let close = value.firstIndex(of: ")") else { return nil }
        var inner = value[value.index(value.startIndex, offsetBy: 4)..<close]
            .trimmingCharacters(in: .whitespaces)
        inner = inner.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        guard inner.hasPrefix("#") else { return nil }
        return elementsByID[String(inner.dropFirst())]
    }

    /// The object bounding box of `nodes` in the user space `transform` maps
    /// to root viewBox space: fill geometry only, strokes excluded, as SVG
    /// defines it. `nil` when nothing has geometry.
    /// `nodes` 在 `transform` 所對應之使用者空間中的物件外框：只算填充幾何、不含描邊，與 SVG 的定義相同。
    /// 沒有任何幾何時為 `nil`。
    static func objectBounds(of nodes: [SVGRenderNode], in transform: SVGTransform) -> SVGRect? {
        guard let inverse = transform.inverted() else { return nil }
        var minX = Double.infinity, minY = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity
        func include(_ root: SVGPoint) {
            let p = inverse.apply(root)
            minX = min(minX, p.x)
            minY = min(minY, p.y)
            maxX = max(maxX, p.x)
            maxY = max(maxY, p.y)
        }
        func visit(_ node: SVGRenderNode) {
            switch node {
                case .shape(let shape):
                    for line in shape.path.flattened(tolerance: 0.01) {
                        line.points.forEach { include(shape.transform.apply($0)) }
                    }
                case .group(_, let children), .layer(_, let children):
                    children.forEach(visit)
                case .text(let text):
                    text.corners.forEach(include)
                case .marker:
                    break
            }
        }
        nodes.forEach(visit)
        guard minX.isFinite, maxX >= minX, maxY >= minY else { return nil }
        return SVGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// The nodes of the `<clipPath>` that `reference` names, for an element
    /// drawing `nodes` in the user space `transform`; `nil` (reported) when the
    /// reference is broken or circular.
    /// `reference` 所指 `<clipPath>` 的節點，供在使用者空間 `transform` 中繪製 `nodes` 的元素使用；
    /// 參照失效或循環時為 `nil`(並回報)。
    func clipNodes(
        _ reference: String, for element: SVGXMLElement, transform: SVGTransform,
        nodes: [SVGRenderNode]
    ) -> [SVGRenderNode]? {
        guard let target = self.element(referencedBy: reference), target.localName == "clipPath"
        else {
            report(.invalidValue, element, "clip-path \(reference) does not name a <clipPath> (drawn unclipped)")
            return nil
        }
        let identity = ObjectIdentifier(target)
        guard !effectStack.contains(identity) else {
            report(.invalidValue, element, "clip-path \(reference) refers to itself (drawn unclipped)")
            return nil
        }
        effectStack.append(identity)
        defer { effectStack.removeLast() }

        let clipStyle = computeStyle(target, parent: Style())
        var content = transform
        if target[attribute: "clipPathUnits"] == "objectBoundingBox" {
            // No box (nothing drawn, or zero size) clips everything away.
            // 沒有外框(什麼都沒畫，或大小為零)時全部裁掉。
            guard let box = Self.objectBounds(of: nodes, in: transform), box.width > 0,
                box.height > 0
            else { return [] }
            content = content.concatenating(.translate(box.x, box.y))
                .concatenating(.scale(box.width, box.height))
        }
        guard let own = elementTransform(target, style: clipStyle) else { return [] }
        content = content.concatenating(own)

        // Only shapes, text and use count; their fill, stroke and opacity do
        // not -- `clipping` makes `build` draw each one as opaque white with
        // its `clip-rule`.
        // 只有形狀、文字與 use 算數；它們的填色、描邊與不透明度不算——`clipping` 讓 `build` 把每一個都畫成
        // 帶 `clip-rule` 的不透明白色。
        let saved = clipping
        clipping = true
        defer { clipping = saved }
        var out: [SVGRenderNode] = []
        for child in target.children where isSVGElement(child) {
            let name = child.localName
            if Self.shapeNames.contains(name) || name == "text" || name == "use" {
                out += build(child, parent: clipStyle, transform: content)
            } else if !["title", "desc", "metadata"].contains(name) {
                report(.unsupportedElement, child, "<\(name)> inside <clipPath> has no effect")
            }
        }
        // A clip-path on the <clipPath> itself intersects the two.
        // <clipPath> 本身的 clip-path 讓兩者取交集。
        if let nested = clipStyle.clipPath, !out.isEmpty,
            let inner = clipNodes(nested, for: target, transform: transform, nodes: nodes)
        {
            out = [.layer(SVGLayerEffects(opacity: 1, clip: inner, mask: nil), children: out)]
        }
        return out
    }

    /// The `<mask>` that `reference` names, for an element drawing `nodes` in
    /// the user space `transform`; `nil` (reported) when the reference is
    /// broken or circular.
    /// `reference` 所指的 `<mask>`,供在使用者空間 `transform` 中繪製 `nodes` 的元素使用；參照失效或
    /// 循環時為 `nil`(並回報)。
    func maskLayer(
        _ reference: String, for element: SVGXMLElement, transform: SVGTransform,
        nodes: [SVGRenderNode]
    ) -> SVGMaskLayer? {
        guard let target = self.element(referencedBy: reference), target.localName == "mask" else {
            report(.invalidValue, element, "mask \(reference) does not name a <mask> (drawn unmasked)")
            return nil
        }
        let identity = ObjectIdentifier(target)
        guard !effectStack.contains(identity) else {
            report(.invalidValue, element, "mask \(reference) refers to itself (drawn unmasked)")
            return nil
        }
        effectStack.append(identity)
        defer { effectStack.removeLast() }

        let maskStyle = computeStyle(target, parent: Style())
        let luminance = !maskStyle.maskAlpha
        let box = Self.objectBounds(of: nodes, in: transform)
        let hidden = SVGMaskLayer(nodes: [], luminance: luminance, region: [])

        // The region: x, y, width, height, -10% -10% 120% 120% by default.
        // 區域：x、y、width、height,預設 -10% -10% 120% 120%。
        let region: SVGRect
        if target[attribute: "maskUnits"] == "userSpaceOnUse" {
            func value(_ name: String, _ fallback: String, _ axis: Axis) -> Double {
                length(target[attribute: name] ?? fallback, axis: axis) ?? 0
            }
            region = SVGRect(
                x: value("x", "-10%", .x), y: value("y", "-10%", .y),
                width: value("width", "120%", .x), height: value("height", "120%", .y))
        } else {
            guard let box, box.width > 0, box.height > 0 else { return hidden }
            func fraction(_ name: String, _ fallback: Double) -> Double {
                guard let text = target[attribute: name]?.trimmingCharacters(in: .whitespaces)
                else { return fallback }
                if text.hasSuffix("%") { return (Double(text.dropLast()) ?? fallback * 100) / 100 }
                return Double(text) ?? fallback
            }
            region = SVGRect(
                x: box.x + fraction("x", -0.1) * box.width,
                y: box.y + fraction("y", -0.1) * box.height,
                width: fraction("width", 1.2) * box.width,
                height: fraction("height", 1.2) * box.height)
        }
        guard region.width > 0, region.height > 0 else { return hidden }

        var content = transform
        if target[attribute: "maskContentUnits"] == "objectBoundingBox" {
            guard let box, box.width > 0, box.height > 0 else { return hidden }
            content = content.concatenating(.translate(box.x, box.y))
                .concatenating(.scale(box.width, box.height))
        }
        let saved = clipping
        clipping = false
        defer { clipping = saved }
        let maskNodes = buildChildren(of: target, style: maskStyle, transform: content)
        let corners = [
            SVGPoint(region.x, region.y), SVGPoint(region.x + region.width, region.y),
            SVGPoint(region.x + region.width, region.y + region.height),
            SVGPoint(region.x, region.y + region.height),
        ].map(transform.apply)
        return SVGMaskLayer(nodes: maskNodes, luminance: luminance, region: corners)
    }
}
