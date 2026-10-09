import Foundation

// `marker-start`, `marker-mid` and `marker-end` (2026-10-10), built into
// ordinary nodes: each marker's content is built once per vertex in that
// vertex's coordinate system and drawn after the shape's fill and stroke, as
// SVG's paint order has it, inside the shape's opacity, clip and mask.
//
// `marker-start`、`marker-mid` 與 `marker-end`(2026-10-10),建構成一般節點：每個標記的內容在每個頂點的
// 座標系中各建構一次，並依 SVG 的繪製順序畫在形狀的填色與描邊之後，位於形狀的不透明度、裁切與遮罩之內。

extension SVGBuilder {
    /// The elements markers apply to. / 標記適用的元素。
    static let markableNames: Set<String> = ["path", "line", "polyline", "polygon"]

    /// A vertex of a path and the directions into and out of it; nil where
    /// there is no segment on that side, or it has no length.
    /// 路徑的一個頂點，以及進入與離開它的方向；該側沒有線段或線段長度為零時為 nil。
    struct MarkerVertex {
        var point: SVGPoint
        var incoming: SVGPoint?
        var outgoing: SVGPoint?
    }

    /// Every vertex markers go on, in order. A curve's direction at an end is
    /// its tangent there: toward the nearest control point that differs.
    /// 標記所在的每個頂點，依序排列。曲線在端點的方向是該處的切線：朝向第一個不重合的控制點。
    static func markerVertices(of path: SVGPath) -> [MarkerVertex] {
        func direction(_ from: SVGPoint, _ candidates: [SVGPoint]) -> SVGPoint? {
            for to in candidates {
                let d = SVGPoint(to.x - from.x, to.y - from.y)
                if abs(d.x) > 1e-12 || abs(d.y) > 1e-12 { return d }
            }
            return nil
        }
        func reversed(_ to: SVGPoint, _ candidates: [SVGPoint]) -> SVGPoint? {
            direction(to, candidates).map { SVGPoint(-$0.x, -$0.y) }
        }
        var vertices: [MarkerVertex] = []
        var current = SVGPoint(0, 0)
        var start = SVGPoint(0, 0)
        var startIndex = 0
        func leave(_ outgoing: SVGPoint?) {
            guard !vertices.isEmpty, vertices[vertices.count - 1].outgoing == nil else { return }
            vertices[vertices.count - 1].outgoing = outgoing
        }
        for segment in path.segments {
            switch segment {
                case .move(let p):
                    vertices.append(MarkerVertex(point: p))
                    current = p
                    start = p
                    startIndex = vertices.count - 1
                case .line(let p):
                    let d = direction(current, [p])
                    leave(d)
                    vertices.append(MarkerVertex(point: p, incoming: d))
                    current = p
                case .quad(let c, let p):
                    leave(direction(current, [c, p]))
                    vertices.append(MarkerVertex(point: p, incoming: reversed(p, [c, current])))
                    current = p
                case .cubic(let c1, let c2, let p):
                    leave(direction(current, [c1, c2, p]))
                    vertices.append(
                        MarkerVertex(point: p, incoming: reversed(p, [c2, c1, current])))
                    current = p
                case .close:
                    guard startIndex < vertices.count else { continue }
                    let d = direction(current, [start])
                    if d != nil {
                        leave(d)
                        vertices.append(MarkerVertex(point: start, incoming: d))
                    }
                    // The closing vertex leaves along the subpath's first segment,
                    // and the subpath's start is entered along the closing one.
                    // 閉合頂點沿子路徑第一段離開；子路徑起點沿閉合的那一段進入。
                    let first = vertices[startIndex].outgoing
                    let closing = vertices[vertices.count - 1].incoming
                    vertices[vertices.count - 1].outgoing = first
                    vertices[startIndex].incoming = closing
                    current = start
            }
        }
        return vertices
    }

    /// The angle `orient="auto"` gives a vertex, in degrees: the bisector of
    /// the directions in and out.
    /// `orient="auto"` 給一個頂點的角度(度):進出方向的角平分線。
    static func autoAngle(_ vertex: MarkerVertex) -> Double {
        func unit(_ d: SVGPoint) -> SVGPoint {
            let length = (d.x * d.x + d.y * d.y).squareRoot()
            return SVGPoint(d.x / length, d.y / length)
        }
        switch (vertex.incoming, vertex.outgoing) {
            case (let a?, let b?):
                let u = unit(a)
                let v = unit(b)
                let sum = SVGPoint(u.x + v.x, u.y + v.y)
                if abs(sum.x) < 1e-12 && abs(sum.y) < 1e-12 { return atan2(u.y, u.x) * 180 / .pi }
                return atan2(sum.y, sum.x) * 180 / .pi
            case (let a?, nil): return atan2(a.y, a.x) * 180 / .pi
            case (nil, let b?): return atan2(b.y, b.x) * 180 / .pi
            case (nil, nil): return 0
        }
    }

    /// The nodes of every marker on `path`, drawn by `element` in the user
    /// space `transform`.
    /// `element` 在使用者空間 `transform` 中繪製的 `path` 上所有標記的節點。
    func markerNodes(
        for element: SVGXMLElement, path: SVGPath, style: Style, transform: SVGTransform
    ) -> [SVGRenderNode] {
        let vertices = Self.markerVertices(of: path)
        guard !vertices.isEmpty else { return [] }
        var out: [SVGRenderNode] = []
        for (index, vertex) in vertices.enumerated() {
            let reference: String?
            let isStart = index == 0
            if isStart {
                reference = style.markerStart
            } else if index == vertices.count - 1 {
                reference = style.markerEnd
            } else {
                reference = style.markerMid
            }
            guard let reference else { continue }
            out += marker(
                reference, at: vertex, isStart: isStart, for: element, style: style,
                transform: transform)
        }
        return out
    }

    private func marker(
        _ reference: String, at vertex: MarkerVertex, isStart: Bool, for element: SVGXMLElement,
        style: Style, transform: SVGTransform
    ) -> [SVGRenderNode] {
        guard let target = self.element(referencedBy: reference), target.localName == "marker" else {
            report(.invalidValue, element, "marker \(reference) does not name a <marker>")
            return []
        }
        let identity = ObjectIdentifier(target)
        guard !effectStack.contains(identity) else {
            report(.invalidValue, element, "marker \(reference) refers to itself")
            return []
        }
        effectStack.append(identity)
        defer { effectStack.removeLast() }

        let markerStyle = computeStyle(target, parent: Style())
        func number(_ name: String, _ fallback: Double, _ axis: Axis) -> Double {
            target[attribute: name].flatMap { length($0, axis: axis) } ?? fallback
        }
        let width = number("markerWidth", 3, .x)
        let height = number("markerHeight", 3, .y)
        guard width > 0, height > 0 else { return [] }

        let angle: Double
        switch target[attribute: "orient"]?.trimmingCharacters(in: .whitespaces) {
            case "auto":
                angle = Self.autoAngle(vertex)
            case "auto-start-reverse":
                angle = Self.autoAngle(vertex) + (isStart ? 180 : 0)
            case let text?:
                let trimmed = text.hasSuffix("deg") ? String(text.dropLast(3)) : text
                angle = Double(trimmed) ?? 0
            case nil:
                angle = 0
        }
        var base = transform.concatenating(.translate(vertex.point.x, vertex.point.y))
            .concatenating(.rotate(degrees: angle))
        if target[attribute: "markerUnits"] != "userSpaceOnUse" {
            base = base.concatenating(.scale(style.strokeWidth, style.strokeWidth))
        }
        var viewBoxMap = SVGTransform.identity
        if target[attribute: "viewBox"] != nil {
            guard let viewBox = parseViewBox(target) else { return [] }
            viewBoxMap = parseAspect(target).transform(from: viewBox, toWidth: width, height: height)
        }
        let ref = viewBoxMap.apply(
            SVGPoint(number("refX", 0, .x), number("refY", 0, .y)))
        let viewport = base.concatenating(.translate(-ref.x, -ref.y))

        let saved = clipping
        clipping = false
        defer { clipping = saved }
        let nodes = buildChildren(
            of: target, style: markerStyle, transform: viewport.concatenating(viewBoxMap))
        guard !nodes.isEmpty else { return [] }
        // overflow hidden (the default) clips to the marker's viewport.
        // overflow 為 hidden(預設)時裁切到標記的視窗。
        let overflow = target[attribute: "overflow"] ?? target[attribute: "style"].flatMap { text in
            SVGCSS.declarations(text).first { $0.name == "overflow" }?.value
        }
        if overflow == "visible" || overflow == "auto" { return nodes }
        var box = SVGPath()
        box.segments = [
            .move(SVGPoint(0, 0)), .line(SVGPoint(width, 0)), .line(SVGPoint(width, height)),
            .line(SVGPoint(0, height)), .close,
        ]
        let clip = SVGShape(
            path: box, transform: viewport, fill: .color(Self.clipWhite), fillRule: .nonzero,
            stroke: nil, strokeWidth: 0, lineCap: .butt, lineJoin: .miter, miterLimit: 4,
            dashes: nil, dashOffset: 0)
        return [.layer(SVGLayerEffects(opacity: 1, clip: [.shape(clip)], mask: nil), children: nodes)]
    }
}
