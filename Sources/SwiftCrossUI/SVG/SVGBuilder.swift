import Foundation

/// Walks the XML tree: resolves styles, transforms and references, and
/// produces the render tree plus the diagnostics list.
///
/// 走訪 XML 樹：解析樣式、轉換與參照，產生算繪樹與診斷清單。
final class SVGBuilder {
    enum Paint {
        case none
        case color(SVGColor)
        case currentColor
        /// A paint server (gradient, pattern) or broken reference; drawn with
        /// the fallback colour when there is one, else in the marker colour.
        /// 塗料伺服器(漸層、圖樣)或斷掉的參照；有後備顏色時以其繪製，否則以標記色繪製。
        case unsupported(String, fallback: SVGColor?)
        /// A gradient element; its fallback is used only if the reference breaks.
        /// 漸層元素；後備色只在參照失效時使用。
        case server(SVGXMLElement, fallback: SVGColor?)
    }

    struct Style {
        // Inherited. / 會繼承。
        var fill: Paint = .color(SVGColor(red: 0, green: 0, blue: 0))
        var fillOpacity = 1.0
        var fillRule = SVGFillRule.nonzero
        var clipRule = SVGFillRule.nonzero
        var stroke: Paint = .none
        var strokeOpacity = 1.0
        var strokeWidth = 1.0
        var lineCap = SVGLineCap.butt
        var lineJoin = SVGLineJoin.miter
        var miterLimit = 4.0
        var dashes: [Double]? = nil
        var dashOffset = 0.0
        var color = SVGColor(red: 0, green: 0, blue: 0)
        var visible = true
        var fontSize = 16.0
        var textAnchor = "start"
        var fontFamilies: [String] = []
        var fontBold = false
        var fontItalic = false
        var markerStart: String? = nil
        var markerMid: String? = nil
        var markerEnd: String? = nil
        // Not inherited. / 不繼承。
        var opacity = 1.0
        var displayed = true
        var transform: String? = nil
        var clipPath: String? = nil
        var mask: String? = nil
        var filter: String? = nil
        /// `mask-type: alpha` on a <mask>. / <mask> 上的 `mask-type: alpha`。
        var maskAlpha = false

        func resettingUninherited() -> Style {
            var copy = self
            copy.opacity = 1
            copy.displayed = true
            copy.transform = nil
            copy.clipPath = nil
            copy.mask = nil
            copy.filter = nil
            copy.maskAlpha = false
            return copy
        }
    }

    /// Properties read from presentation attributes and CSS.
    /// 從呈現屬性與 CSS 讀取的屬性。
    static let properties: Set<String> = [
        "fill", "fill-opacity", "fill-rule", "stroke", "stroke-opacity", "stroke-width",
        "stroke-linecap", "stroke-linejoin", "stroke-miterlimit", "stroke-dasharray",
        "stroke-dashoffset", "color", "visibility", "font-size", "text-anchor", "opacity",
        "font-family", "font-weight", "font-style",
        "display", "clip-path", "mask", "filter", "marker-start", "marker-mid", "marker-end",
        "marker", "clip-rule", "mask-type",
    ]

    /// Properties that change nothing this renderer draws, accepted without a
    /// report. Text properties are here because visible text is already
    /// reported as a whole.
    ///
    /// 不影響本算繪器所畫內容的屬性，接受而不回報。文字相關屬性也在此，因為可見文字本身已整體回報。
    static let ignoredProperties: Set<String> = [
        "font-variant", "font-stretch", "font",
        "letter-spacing", "word-spacing", "text-decoration", "dominant-baseline",
        "alignment-baseline", "baseline-shift", "writing-mode", "direction", "unicode-bidi",
        "white-space", "line-height", "text-rendering", "shape-rendering", "image-rendering",
        "color-rendering", "color-interpolation", "color-interpolation-filters",
        "color-profile", "pointer-events", "cursor", "overflow",
        "enable-background", "solid-color", "solid-opacity", "isolation", "stop-color",
        "stop-opacity", "flood-color", "flood-opacity", "lighting-color", "transform-origin",
        "font-feature-settings", "font-variation-settings", "text-align", "text-indent",
        "user-select", "inline-size",
    ]

    private var diagnostics: [SVGDiagnostic] = []
    private var diagnosticIndex: [String: Int] = [:]
    var elementsByID: [String: SVGXMLElement] = [:]
    private var rules: [SVGStyleRule] = []
    private var viewportWidth = 300.0
    private var viewportHeight = 150.0
    private var useStack: [ObjectIdentifier] = []
    /// True while building the content of a <clipPath>: geometry only, drawn opaque white.
    /// 建構 <clipPath> 內容時為真：只取幾何，以不透明白色繪製。
    var clipping = false
    /// The <clipPath> and <mask> elements being built, against cycles.
    /// 正在建構的 <clipPath> 與 <mask> 元素，用來防止循環。
    var effectStack: [ObjectIdentifier] = []

    static func build(root: SVGXMLElement) -> SVGDocument.Storage {
        let builder = SVGBuilder()
        return builder.run(root)
    }

    func report(_ kind: SVGDiagnostic.Kind, _ element: SVGXMLElement, _ detail: String) {
        let key = "\(kind.rawValue)|\(element.localName)|\(detail)"
        if let index = diagnosticIndex[key] {
            diagnostics[index].count += 1
        } else {
            diagnosticIndex[key] = diagnostics.count
            diagnostics.append(
                SVGDiagnostic(kind: kind, element: element.localName, detail: detail, count: 1))
        }
    }

    private func run(_ root: SVGXMLElement) -> SVGDocument.Storage {
        index(root)
        collectStyleSheets(root)

        let viewBox = parseViewBox(root)
        let aspect = parseAspect(root)
        // Percentages in the root's own width/height refer to a viewport we
        // do not have; they fall back to the viewBox, as browsers do for an
        // image with no container size.
        // 根元素自身 width/height 中的百分比所指的視埠並不存在；比照瀏覽器處理沒有容器尺寸的影像，
        // 改用 viewBox。
        let widthText = root[attribute: "width"]
        let heightText = root[attribute: "height"]
        var width = widthText.flatMap { absoluteLength($0, element: root) }
        var height = heightText.flatMap { absoluteLength($0, element: root) }
        if let viewBox {
            switch (width, height) {
                case (nil, nil):
                    width = viewBox.width
                    height = viewBox.height
                case (let w?, nil):
                    height = w * viewBox.height / viewBox.width
                case (nil, let h?):
                    width = h * viewBox.width / viewBox.height
                default:
                    break
            }
        }
        let finalWidth = max(width ?? 300, 0)
        let finalHeight = max(height ?? 150, 0)
        viewportWidth = viewBox?.width ?? finalWidth
        viewportHeight = viewBox?.height ?? finalHeight

        let style = computeStyle(root, parent: Style())
        var nodes: [SVGRenderNode] = []
        if style.displayed {
            nodes = buildChildren(of: root, style: style, transform: .identity)
            nodes = wrap(nodes, style: style, element: root, transform: .identity)
        }
        return SVGDocument.Storage(
            nodes: nodes, width: finalWidth, height: finalHeight, viewBox: viewBox,
            aspect: aspect, diagnostics: diagnostics)
    }

    private func index(_ element: SVGXMLElement) {
        if let id = element[attribute: "id"], elementsByID[id] == nil {
            elementsByID[id] = element
        }
        for child in element.children {
            index(child)
        }
    }

    private func collectStyleSheets(_ element: SVGXMLElement) {
        if element.localName == "style" && isSVGElement(element) {
            let type = element[attribute: "type"] ?? "text/css"
            if type.lowercased() != "text/css" && !type.isEmpty {
                report(.unsupportedValue, element, "style sheet type '\(type)'")
            } else {
                let parsed = SVGCSS.parseSheet(element.text, firstOrder: rules.count)
                rules += parsed.rules
                for problem in parsed.unsupported {
                    report(.unsupportedValue, element, "CSS \(problem) ignored")
                }
            }
        }
        for child in element.children {
            collectStyleSheets(child)
        }
    }

    func isSVGElement(_ element: SVGXMLElement) -> Bool {
        element.prefix == nil || element.prefix == "svg"
    }

    // MARK: Lengths / 長度

    enum Axis { case x, y, other }

    func length(_ text: String, axis: Axis, fontSize: Double = 16) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        var scanner = SVGNumberScanner(trimmed)
        guard let value = scanner.number() else { return nil }
        let unit = String(decoding: scanner.bytes[scanner.index...], as: UTF8.self)
            .trimmingCharacters(in: .whitespaces).lowercased()
        switch unit {
            case "", "px": return value
            case "mm": return value * 96 / 25.4
            case "cm": return value * 96 / 2.54
            case "in": return value * 96
            case "pt": return value * 96 / 72
            case "pc": return value * 16
            case "em": return value * fontSize
            case "ex": return value * fontSize / 2
            case "%":
                switch axis {
                    case .x: return value / 100 * viewportWidth
                    case .y: return value / 100 * viewportHeight
                    case .other:
                        let diagonal =
                            ((viewportWidth * viewportWidth + viewportHeight * viewportHeight) / 2)
                            .squareRoot()
                        return value / 100 * diagonal
                }
            default: return nil
        }
    }

    private func absoluteLength(_ text: String, element: SVGXMLElement) -> Double? {
        if text.trimmingCharacters(in: .whitespaces).hasSuffix("%") { return nil }
        guard let value = length(text, axis: .other) else {
            report(.invalidValue, element, "length '\(text)'")
            return nil
        }
        return value
    }

    private func attributeLength(
        _ element: SVGXMLElement, _ name: String, axis: Axis, style: Style, default value: Double = 0
    ) -> Double {
        guard let text = element[attribute: name] else { return value }
        guard let result = length(text, axis: axis, fontSize: style.fontSize) else {
            report(.invalidValue, element, "\(name)='\(text)'")
            return value
        }
        return result
    }

    func parseViewBox(_ element: SVGXMLElement) -> SVGViewBox? {
        guard let text = element[attribute: "viewBox"] else { return nil }
        guard let values = SVGNumberScanner.numbers(in: text), values.count == 4,
            values[2] > 0, values[3] > 0
        else {
            report(.invalidValue, element, "viewBox='\(text)'")
            return nil
        }
        return SVGViewBox(x: values[0], y: values[1], width: values[2], height: values[3])
    }

    func parseAspect(_ element: SVGXMLElement) -> SVGAspectRatio {
        let text = element[attribute: "preserveAspectRatio"]
        if let aspect = SVGAspectRatio.parse(text) { return aspect }
        report(.invalidValue, element, "preserveAspectRatio='\(text ?? "")'")
        return SVGAspectRatio()
    }

    // MARK: Style / 樣式

    func computeStyle(_ element: SVGXMLElement, parent: Style) -> Style {
        var style = parent.resettingUninherited()
        var declarations: [(name: String, value: String, fromCSS: Bool)] = []
        for attribute in element.attributes where Self.properties.contains(attribute.name) {
            declarations.append((attribute.name, attribute.value, false))
        }
        if !rules.isEmpty {
            let tag = element.localName
            let id = element[attribute: "id"]
            let classes = (element[attribute: "class"] ?? "").split(separator: " ").map(String.init)
            let matching = rules.filter {
                $0.selector.matches(tag: tag, id: id, classes: classes)
            }.sorted {
                let a = $0.selector.specificity
                let b = $1.selector.specificity
                if a != b { return a < b }
                return $0.order < $1.order
            }
            for rule in matching {
                for declaration in rule.declarations {
                    declarations.append((declaration.name, declaration.value, true))
                }
            }
        }
        if let inline = element[attribute: "style"] {
            for declaration in SVGCSS.declarations(inline) {
                declarations.append((declaration.name, declaration.value, true))
            }
        }
        for declaration in declarations {
            apply(
                declaration.name, declaration.value, fromCSS: declaration.fromCSS, to: &style,
                parent: parent, element: element)
        }
        return style
    }

    private func apply(
        _ name: String, _ rawValue: String, fromCSS: Bool, to style: inout Style, parent: Style,
        element: SVGXMLElement
    ) {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value == "inherit" {
            switch name {
                case "fill": style.fill = parent.fill
                case "stroke": style.stroke = parent.stroke
                case "opacity": style.opacity = parent.opacity
                case "display": style.displayed = parent.displayed
                default: break  // inherited properties already hold the parent's value
            }
            return
        }
        func number(_ text: String) -> Double? {
            var scanner = SVGNumberScanner(text)
            guard let result = scanner.number() else { return nil }
            scanner.skipSeparators()
            if scanner.peek() == UInt8(ascii: "%") { return result / 100 }
            return scanner.isAtEnd ? result : nil
        }
        func invalid() {
            report(.invalidValue, element, "\(name)='\(value)'")
        }
        switch name {
            case "fill":
                if let paint = parsePaint(value, element: element) { style.fill = paint } else { invalid() }
            case "stroke":
                if let paint = parsePaint(value, element: element) { style.stroke = paint } else { invalid() }
            case "fill-opacity":
                if let v = number(value) { style.fillOpacity = min(max(v, 0), 1) } else { invalid() }
            case "stroke-opacity":
                if let v = number(value) { style.strokeOpacity = min(max(v, 0), 1) } else { invalid() }
            case "opacity":
                if let v = number(value) { style.opacity = min(max(v, 0), 1) } else { invalid() }
            case "fill-rule":
                if let rule = SVGFillRule(rawValue: value) { style.fillRule = rule } else { invalid() }
            case "stroke-width":
                if let width = length(value, axis: .other, fontSize: style.fontSize), width >= 0 {
                    style.strokeWidth = width
                } else {
                    invalid()
                }
            case "stroke-linecap":
                if let cap = SVGLineCap(rawValue: value) { style.lineCap = cap } else { invalid() }
            case "stroke-linejoin":
                switch value {
                    case "miter", "miter-clip", "arcs": style.lineJoin = .miter
                    case "round": style.lineJoin = .round
                    case "bevel": style.lineJoin = .bevel
                    default: invalid()
                }
            case "stroke-miterlimit":
                if let v = number(value), v >= 1 { style.miterLimit = v } else { invalid() }
            case "stroke-dasharray":
                if value == "none" {
                    style.dashes = nil
                } else {
                    let parts = value.split(whereSeparator: { $0 == "," || $0 == " " })
                    let lengths = parts.map { length(String($0), axis: .other, fontSize: style.fontSize) }
                    if lengths.contains(where: { $0 == nil || $0! < 0 }) || lengths.isEmpty {
                        invalid()
                        style.dashes = nil
                    } else {
                        var pattern = lengths.map { $0! }
                        if pattern.count % 2 == 1 { pattern += pattern }
                        style.dashes = pattern.reduce(0, +) > 0 ? pattern : nil
                    }
                }
            case "stroke-dashoffset":
                if let v = length(value, axis: .other, fontSize: style.fontSize) {
                    style.dashOffset = v
                } else {
                    invalid()
                }
            case "color":
                if let color = SVGColor.parse(value) { style.color = color } else { invalid() }
            case "visibility":
                style.visible = value == "visible"
            case "display":
                style.displayed = value != "none"
            case "font-size":
                if let size = length(value, axis: .other, fontSize: parent.fontSize) {
                    style.fontSize = size
                }
            case "text-anchor":
                style.textAnchor = value
            case "font-family":
                style.fontFamilies = Self.fontFamilies(value)
            case "font-weight":
                switch value {
                    case "bold", "bolder": style.fontBold = true
                    case "normal", "lighter": style.fontBold = false
                    default:
                        if let weight = Double(value) { style.fontBold = weight >= 600 } else { invalid() }
                }
            case "font-style":
                style.fontItalic = value == "italic" || value == "oblique"
            case "clip-path":
                style.clipPath = value == "none" ? nil : value
            case "clip-rule":
                if let rule = SVGFillRule(rawValue: value) { style.clipRule = rule } else { invalid() }
            case "mask-type":
                switch value {
                    case "alpha": style.maskAlpha = true
                    case "luminance": style.maskAlpha = false
                    default: invalid()
                }
            case "mask":
                style.mask = value == "none" ? nil : value
            case "filter":
                style.filter = value == "none" ? nil : value
            case "marker-start":
                style.markerStart = value == "none" ? nil : value
            case "marker-mid":
                style.markerMid = value == "none" ? nil : value
            case "marker-end":
                style.markerEnd = value == "none" ? nil : value
            case "marker":
                let reference = value == "none" ? nil : value
                style.markerStart = reference
                style.markerMid = reference
                style.markerEnd = reference
            case "transform":
                style.transform = value
            default:
                if !fromCSS || name.hasPrefix("-") || Self.ignoredProperties.contains(name) {
                    return
                }
                switch (name, value) {
                    case ("paint-order", "normal"), ("mix-blend-mode", "normal"),
                        ("vector-effect", "none"):
                        return
                    default:
                        report(.unsupportedAttribute, element, "property '\(name): \(value)'")
                }
        }
    }

    private func parsePaint(_ text: String, element: SVGXMLElement) -> Paint? {
        let value = text.trimmingCharacters(in: .whitespaces)
        if value == "none" { return Paint.none }
        if value.lowercased() == "currentcolor" { return .currentColor }
        if value.hasPrefix("url(") {
            guard let close = value.firstIndex(of: ")") else { return nil }
            var reference = value[value.index(value.startIndex, offsetBy: 4)..<close]
                .trimmingCharacters(in: .whitespaces)
            reference = reference.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            let fallbackText = value[value.index(after: close)...].trimmingCharacters(in: .whitespaces)
            let fallback: SVGColor?
            if fallbackText.isEmpty || fallbackText == "none" {
                fallback = nil
            } else {
                fallback = SVGColor.parse(fallbackText)
            }
            let id = reference.hasPrefix("#") ? String(reference.dropFirst()) : reference
            if let target = elementsByID[id] {
                if Self.gradientNames.contains(target.localName) || target.localName == "pattern" {
                    return .server(target, fallback: fallback)
                }
                return .unsupported("paint server <\(target.localName)> (\(reference))", fallback: fallback)
            }
            return .unsupported("paint reference \(reference) does not exist", fallback: fallback)
        }
        return SVGColor.parse(value).map(Paint.color)
    }

    /// Resolves a paint to a colour with `opacity` applied, reporting
    /// anything it had to substitute.
    /// 把塗料解析成已套用 `opacity` 的顏色，並回報任何不得不替換的情形。
    private func resolve(
        _ paint: Paint, opacity: Double, style: Style, element: SVGXMLElement,
        box: @autoclosure () -> SVGRect? = nil
    )
        -> SVGPaintValue?
    {
        let color: SVGColor
        switch paint {
            case .none:
                return nil
            case .color(let value):
                color = value
            case .currentColor:
                color = style.color
            case .server(let target, _):
                guard opacity > 0 else { return nil }
                if target.localName == "pattern" {
                    guard let pattern = pattern(target, box: box()) else { return nil }
                    return .pattern(pattern, opacity: opacity)
                }
                guard let gradient = gradient(target, box: box(), style: style) else {
                    return nil
                }
                return .gradient(gradient, opacity: opacity)
            case .unsupported(let what, let fallback):
                report(.unsupportedValue, element, what + (fallback == nil ? "" : "; fallback colour used"))
                color = fallback ?? SVGColor.unsupportedMarker
        }
        let alpha = color.alpha * opacity
        return alpha > 0 ? .color(color.with(alpha: alpha)) : nil
    }

    // MARK: Tree / 樹

    func buildChildren(of element: SVGXMLElement, style: Style, transform: SVGTransform)
        -> [SVGRenderNode]
    {
        var nodes: [SVGRenderNode] = []
        for child in element.children {
            nodes += build(child, parent: style, transform: transform)
        }
        return nodes
    }

    /// Applies opacity, clip-path and mask, and reports the effects that are not applied.
    /// 套用不透明度、clip-path 與 mask,並回報未套用的效果。
    private func wrap(
        _ nodes: [SVGRenderNode], style: Style, element: SVGXMLElement, transform: SVGTransform
    ) -> [SVGRenderNode] {
        // Inside a <clipPath> only clip-path applies; opacity, mask and filter do not.
        // <clipPath> 之中只有 clip-path 有作用；不透明度、mask 與 filter 都沒有。
        let opacity = clipping ? 1 : style.opacity
        if nodes.isEmpty { return nodes }
        var filter: SVGFilter? = nil
        var unfiltered = false
        if let reference = style.filter, !clipping {
            switch filterEffect(reference, for: element, transform: transform, nodes: nodes) {
                case .success(let built?):
                    filter = built
                case .success(nil):
                    // An empty region, an empty box, or no primitives: not drawn (SVG 1.1 15.7).
                    // 區域為空、外框為空或沒有 primitive:不繪製(SVG 1.1 15.7)。
                    return []
                case .failure(let problem):
                    report(.unsupportedAttribute, element, "\(problem.detail) (drawn unfiltered)")
                    unfiltered = true
            }
        }
        var clip: [SVGRenderNode]? = nil
        var mask: SVGMaskLayer? = nil
        var broken = false
        if let reference = style.clipPath {
            clip = clipNodes(reference, for: element, transform: transform, nodes: nodes)
            broken = broken || clip == nil
        }
        if let reference = style.mask, !clipping {
            mask = maskLayer(reference, for: element, transform: transform, nodes: nodes)
            broken = broken || mask == nil
        }
        var result = nodes
        if clip != nil || mask != nil || filter != nil {
            result = [
                .layer(
                    SVGLayerEffects(opacity: opacity, clip: clip, mask: mask, filter: filter),
                    children: nodes)
            ]
        } else if opacity < 1 {
            result = [.group(opacity: opacity, children: nodes)]
        }
        if broken || unfiltered, let box = Self.boundingMarker(of: nodes) {
            result.append(box)
        }
        return result
    }

    /// A marker around everything `nodes` draw, in root viewBox space.
    /// 包住 `nodes` 所畫一切的標記，位於根 viewBox 空間。
    static func boundingMarker(of nodes: [SVGRenderNode]) -> SVGRenderNode? {
        var minX = Double.infinity, minY = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity
        func include(_ point: SVGPoint) {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }
        func visit(_ node: SVGRenderNode) {
            switch node {
                case .shape(let shape):
                    let margin = shape.stroke == nil ? 0 : shape.strokeWidth / 2
                    for segment in shape.path.segments {
                        let points: [SVGPoint]
                        switch segment {
                            case .move(let p), .line(let p): points = [p]
                            case .quad(let a, let p): points = [a, p]
                            case .cubic(let a, let b, let p): points = [a, b, p]
                            case .close: points = []
                        }
                        for p in points {
                            for dx in [-margin, margin] {
                                for dy in [-margin, margin] {
                                    include(shape.transform.apply(SVGPoint(p.x + dx, p.y + dy)))
                                }
                            }
                        }
                    }
                case .group(_, let children), .layer(_, let children):
                    children.forEach(visit)
                case .text(let node):
                    node.corners.forEach(include)
                case .marker(let corners):
                    corners.forEach(include)
            }
        }
        nodes.forEach(visit)
        guard minX.isFinite, maxX > minX || maxY > minY else { return nil }
        return .marker([
            SVGPoint(minX, minY), SVGPoint(maxX, minY), SVGPoint(maxX, maxY), SVGPoint(minX, maxY),
        ])
    }

    static let shapeNames: Set<String> = [
        "path", "rect", "circle", "ellipse", "line", "polyline", "polygon",
    ]

    /// Elements that never draw by themselves: definitions and metadata.
    /// 本身從不繪製的元素：定義與中繼資料。
    private static let nonRendering: Set<String> = [
        "defs", "symbol", "title", "desc", "metadata", "style", "clipPath", "mask", "marker",
        "pattern", "linearGradient", "radialGradient", "filter", "font", "font-face", "glyph",
        "missing-glyph", "view", "cursor", "color-profile",
    ]

    private static let animationNames: Set<String> = [
        "animate", "animateTransform", "animateMotion", "animateColor", "set",
    ]

    func elementTransform(_ element: SVGXMLElement, style: Style) -> SVGTransform? {
        let text = element[attribute: "transform"] ?? style.transform
        guard let text else { return .identity }
        if let transform = SVGTransformParser.parse(text) { return transform }
        report(.invalidValue, element, "transform='\(text)'")
        return nil
    }

    func build(_ element: SVGXMLElement, parent: Style, transform parentTransform: SVGTransform)
        -> [SVGRenderNode]
    {
        // Elements in other namespaces (sodipodi:, inkscape:) are editor
        // metadata, not drawing.
        // 其他命名空間的元素(sodipodi:、inkscape:)是編輯器的中繼資料，不是繪圖內容。
        guard isSVGElement(element) else { return [] }
        let name = element.localName
        if Self.nonRendering.contains(name) { return [] }
        if Self.animationNames.contains(name) {
            report(.unsupportedElement, element, "animation not run; the static image is drawn")
            return []
        }
        if name == "script" {
            report(.unsupportedElement, element, "script not run")
            return []
        }

        let style = computeStyle(element, parent: parent)
        guard style.displayed else { return [] }
        // An invalid transform disables rendering of the element (SVG 1.1 7.6).
        // 無效的轉換會使該元素不被算繪(SVG 1.1 7.6)。
        guard let local = elementTransform(element, style: style) else { return [] }
        let transform = parentTransform.concatenating(local)

        switch name {
            case "g", "a":
                let nodes = buildChildren(of: element, style: style, transform: transform)
                return wrap(nodes, style: style, element: element, transform: transform)
            case "switch":
                // Draws the first child that is something this renderer
                // draws; conditional attributes are not evaluated.
                // 畫出第一個本算繪器會畫的子元素；條件屬性不予評估。
                for child in element.children where isSVGElement(child) {
                    let childName = child.localName
                    if childName == "foreignObject" { continue }
                    if Self.shapeNames.contains(childName) || ["g", "a", "use", "svg", "text", "image"].contains(childName) {
                        let nodes = build(child, parent: style, transform: transform)
                        return wrap(nodes, style: style, element: element, transform: transform)
                    }
                }
                return []
            case "svg":
                return buildNestedSVG(element, style: style, transform: transform)
            case "use":
                return buildUse(element, style: style, transform: transform)
            case "text":
                return buildText(element, style: style, transform: transform)
            case "image", "foreignObject", "video", "audio", "canvas", "iframe":
                if name == "image", let nodes = imageNodes(element, style: style, transform: transform) {
                    return wrap(nodes, style: style, element: element, transform: transform)
                }
                report(
                    .unsupportedElement, element,
                    name == "image"
                        ? "<image> is not drawn: only data: URIs of raster pictures are"
                        : "<\(name)> is not drawn")
                let x = attributeLength(element, "x", axis: .x, style: style)
                let y = attributeLength(element, "y", axis: .y, style: style)
                let width = attributeLength(element, "width", axis: .x, style: style)
                let height = attributeLength(element, "height", axis: .y, style: style)
                if width > 0 && height > 0 {
                    return [marker(x: x, y: y, width: width, height: height, transform: transform)]
                }
                return []
            default:
                break
        }

        guard Self.shapeNames.contains(name) else {
            report(.unsupportedElement, element, "unknown element not drawn")
            return []
        }
        guard let path = shapePath(element, name: name, style: style) else { return [] }
        guard style.visible else { return [] }
        if clipping {
            // In a <clipPath> only the geometry counts, filled with `clip-rule`.
            // 在 <clipPath> 中只有幾何算數，以 `clip-rule` 填充。
            let shape = SVGShape(
                path: path, transform: transform, fill: .color(Self.clipWhite),
                fillRule: style.clipRule, stroke: nil, strokeWidth: 0, lineCap: .butt,
                lineJoin: .miter, miterLimit: 4, dashes: nil, dashOffset: 0)
            return wrap([.shape(shape)], style: style, element: element, transform: transform)
        }

        let fill =
            name == "line"
            ? nil
            : resolve(
                style.fill, opacity: style.fillOpacity, style: style, element: element,
                box: Self.bounds(of: path))
        let stroke = resolve(
            style.stroke, opacity: style.strokeOpacity, style: style, element: element,
            box: Self.bounds(of: path))
        // Markers come after the fill and stroke, inside the shape's opacity, clip and mask.
        // 標記畫在填色與描邊之後，位於形狀的不透明度、裁切與遮罩之內。
        let markers =
            Self.markableNames.contains(name)
            ? markerNodes(for: element, path: path, style: style, transform: transform) : []
        if fill == nil && stroke == nil {
            return wrap(markers, style: style, element: element, transform: transform)
        }
        let shape = SVGShape(
            path: path, transform: transform, fill: fill, fillRule: style.fillRule, stroke: stroke,
            strokeWidth: style.strokeWidth, lineCap: style.lineCap, lineJoin: style.lineJoin,
            miterLimit: style.miterLimit, dashes: style.dashes, dashOffset: style.dashOffset)
        var nodes: [SVGRenderNode] = [.shape(shape)] + markers
        // A substituted paint is outlined like any other unsupported item.
        // 被替換的塗料與其他不支援的項目一樣會被框出。
        if Self.isUnsupported(style.fill) && name != "line" || Self.isUnsupported(style.stroke),
            let box = Self.boundingMarker(of: nodes)
        {
            nodes.append(box)
        }
        return wrap(nodes, style: style, element: element, transform: transform)
    }

    private static func isUnsupported(_ paint: Paint) -> Bool {
        if case .unsupported = paint { return true }
        return false
    }

    private func marker(x: Double, y: Double, width: Double, height: Double, transform: SVGTransform)
        -> SVGRenderNode
    {
        .marker([
            transform.apply(SVGPoint(x, y)), transform.apply(SVGPoint(x + width, y)),
            transform.apply(SVGPoint(x + width, y + height)),
            transform.apply(SVGPoint(x, y + height)),
        ])
    }

    private func shapePath(_ element: SVGXMLElement, name: String, style: Style) -> SVGPath? {
        switch name {
            case "path":
                guard let data = element[attribute: "d"] else { return nil }
                let (path, error) = SVGPathDataParser.parse(data)
                if let error {
                    report(.invalidValue, element, "path data: \(error) (drawn up to the error)")
                }
                return path.isEmpty ? nil : path
            case "rect":
                let x = attributeLength(element, "x", axis: .x, style: style)
                let y = attributeLength(element, "y", axis: .y, style: style)
                let width = attributeLength(element, "width", axis: .x, style: style)
                let height = attributeLength(element, "height", axis: .y, style: style)
                guard width > 0, height > 0 else { return nil }
                let rxText = element[attribute: "rx"]
                let ryText = element[attribute: "ry"]
                var rx = rxText.map { _ in attributeLength(element, "rx", axis: .x, style: style) }
                var ry = ryText.map { _ in attributeLength(element, "ry", axis: .y, style: style) }
                if rx == nil { rx = ry }
                if ry == nil { ry = rx }
                let radiusX = min(max(rx ?? 0, 0), width / 2)
                let radiusY = min(max(ry ?? 0, 0), height / 2)
                return SVGPath.rectangle(
                    x: x, y: y, width: width, height: height, rx: radiusX, ry: radiusY)
            case "circle":
                let r = attributeLength(element, "r", axis: .other, style: style)
                guard r > 0 else { return nil }
                return SVGPath.ellipse(
                    cx: attributeLength(element, "cx", axis: .x, style: style),
                    cy: attributeLength(element, "cy", axis: .y, style: style), rx: r, ry: r)
            case "ellipse":
                let rx = attributeLength(element, "rx", axis: .x, style: style)
                let ry = attributeLength(element, "ry", axis: .y, style: style)
                guard rx > 0, ry > 0 else { return nil }
                return SVGPath.ellipse(
                    cx: attributeLength(element, "cx", axis: .x, style: style),
                    cy: attributeLength(element, "cy", axis: .y, style: style), rx: rx, ry: ry)
            case "line":
                var path = SVGPath()
                path.segments = [
                    .move(
                        SVGPoint(
                            attributeLength(element, "x1", axis: .x, style: style),
                            attributeLength(element, "y1", axis: .y, style: style))),
                    .line(
                        SVGPoint(
                            attributeLength(element, "x2", axis: .x, style: style),
                            attributeLength(element, "y2", axis: .y, style: style))),
                ]
                return path
            case "polyline", "polygon":
                guard let text = element[attribute: "points"] else { return nil }
                var scanner = SVGNumberScanner(text)
                var values: [Double] = []
                while scanner.atNumber(), let value = scanner.number() {
                    values.append(value)
                }
                scanner.skipSeparators()
                if !scanner.isAtEnd || values.count % 2 == 1 {
                    report(.invalidValue, element, "points list malformed (drawn up to the error)")
                }
                guard values.count >= 4 else { return nil }
                var path = SVGPath()
                for index in stride(from: 0, to: values.count - 1, by: 2) {
                    let point = SVGPoint(values[index], values[index + 1])
                    path.segments.append(index == 0 ? .move(point) : .line(point))
                }
                if name == "polygon" { path.segments.append(.close) }
                return path
            default:
                return nil
        }
    }

    private func buildNestedSVG(_ element: SVGXMLElement, style: Style, transform: SVGTransform)
        -> [SVGRenderNode]
    {
        let x = attributeLength(element, "x", axis: .x, style: style)
        let y = attributeLength(element, "y", axis: .y, style: style)
        let width = element[attribute: "width"] == nil
            ? viewportWidth : attributeLength(element, "width", axis: .x, style: style)
        let height = element[attribute: "height"] == nil
            ? viewportHeight : attributeLength(element, "height", axis: .y, style: style)
        guard width > 0, height > 0 else { return [] }
        var inner = transform.concatenating(.translate(x, y))
        if let viewBox = parseViewBox(element) {
            inner = inner.concatenating(
                parseAspect(element).transform(from: viewBox, toWidth: width, height: height))
        }
        report(.unsupportedAttribute, element, "nested <svg> viewport is not clipped")
        let nodes = buildChildren(of: element, style: style, transform: inner)
        return wrap(nodes, style: style, element: element, transform: transform)
    }

    private func buildUse(_ element: SVGXMLElement, style: Style, transform: SVGTransform)
        -> [SVGRenderNode]
    {
        guard let href = element[attribute: "href"] ?? element[attribute: "xlink:href"] else {
            return []
        }
        guard href.hasPrefix("#"), let target = elementsByID[String(href.dropFirst())] else {
            report(.invalidValue, element, "href '\(href)' does not name an element in this file")
            return []
        }
        let identity = ObjectIdentifier(target)
        if useStack.contains(identity) || useStack.count > 32 {
            report(.invalidValue, element, "href '\(href)' refers to itself")
            return []
        }
        useStack.append(identity)
        defer { useStack.removeLast() }

        let x = attributeLength(element, "x", axis: .x, style: style)
        let y = attributeLength(element, "y", axis: .y, style: style)
        let placed = transform.concatenating(.translate(x, y))
        let nodes: [SVGRenderNode]
        if target.localName == "symbol" {
            let symbolStyle = computeStyle(target, parent: style)
            var inner = placed
            if let viewBox = parseViewBox(target) {
                let width = element[attribute: "width"] == nil
                    ? viewBox.width : attributeLength(element, "width", axis: .x, style: style)
                let height = element[attribute: "height"] == nil
                    ? viewBox.height : attributeLength(element, "height", axis: .y, style: style)
                inner = inner.concatenating(
                    parseAspect(target).transform(from: viewBox, toWidth: width, height: height))
            }
            nodes = wrap(
                buildChildren(of: target, style: symbolStyle, transform: inner), style: symbolStyle,
                element: target, transform: inner)
        } else {
            nodes = build(target, parent: style, transform: placed)
        }
        return wrap(nodes, style: style, element: element, transform: transform)
    }

    /// Text is drawn by none of the backends' fonts here, because the result
    /// would differ per platform. Invisible text -- KiCad writes every label
    /// twice, once as `<text opacity="0">` for search and once as stroked
    /// paths -- draws nothing in any renderer and is not reported.
    ///
    /// 文字在此不以任何 backend 的字型繪製，因為結果會因平台而異。不可見的文字——KiCad 每個標籤都寫
    /// 兩次，一次是供搜尋用的 `<text opacity="0">`,一次是描邊路徑——在任何算繪器中都不會畫出東西，
    /// 因此不回報。
    private func buildText(_ element: SVGXMLElement, style: Style, transform: SVGTransform)
        -> [SVGRenderNode]
    {
        let content = Self.textContent(element).trimmingCharacters(in: .whitespacesAndNewlines)
        let fillVisible: Bool
        if case .none = style.fill { fillVisible = false } else { fillVisible = style.fillOpacity > 0 }
        let strokeVisible: Bool
        if case .none = style.stroke { strokeVisible = false } else { strokeVisible = style.strokeOpacity > 0 }
        // In a <clipPath> text clips whatever its fill, stroke and opacity.
        // 在 <clipPath> 中，文字不論填色、描邊與不透明度都會裁切。
        guard style.visible, clipping || (style.opacity > 0 && (fillVisible || strokeVisible)),
            !content.isEmpty
        else {
            return []
        }
        report(
            .textNeedsRenderer, element,
            "text '\(content.prefix(40))' is drawn only by a backend text renderer")
        let x = SVGNumberScanner.numbers(in: element[attribute: "x"] ?? "0")?.first ?? 0
        let y = SVGNumberScanner.numbers(in: element[attribute: "y"] ?? "0")?.first ?? 0
        let size = style.fontSize
        let width =
            element[attribute: "textLength"].flatMap { length($0, axis: .x, fontSize: size) }
            ?? Double(content.count) * size * 0.6
        let left: Double
        switch element[attribute: "text-anchor"] ?? style.textAnchor {
            case "middle": left = x - width / 2
            case "end": left = x - width
            default: left = x
        }
        let top = y - size * 0.8
        let corners = [
            SVGPoint(left, top), SVGPoint(left + width, top), SVGPoint(left + width, top + size),
            SVGPoint(left, top + size),
        ].map(transform.apply)
        let run = SVGTextRun(
            text: content.split(whereSeparator: \.isWhitespace).joined(separator: " "),
            fontFamilies: style.fontFamilies, fontSize: size, isBold: style.fontBold,
            isItalic: style.fontItalic,
            anchor: SVGTextAnchor(rawValue: element[attribute: "text-anchor"] ?? style.textAnchor)
                ?? .start)
        let textBox = SVGRect(x: left, y: top, width: width, height: size)
        var node = SVGTextNode(
            run: run, transform: transform.concatenating(.translate(x, y)),
            fill: Self.shifted(
                resolve(
                    style.fill, opacity: style.fillOpacity, style: style, element: element,
                    box: textBox), x: x, y: y),
            stroke: Self.shifted(
                resolve(
                    style.stroke, opacity: style.strokeOpacity, style: style, element: element,
                    box: textBox), x: x, y: y),
            strokeWidth: style.strokeWidth, corners: corners)
        if clipping {
            node.fill = .color(Self.clipWhite)
            node.stroke = nil
        }
        return wrap([.text(node)], style: style, element: element, transform: transform)
    }

    /// `font-family` as a list, quotes removed, empty names dropped.
    /// `font-family` 解析成清單，去除引號並略過空名稱。
    static func fontFamilies(_ value: String) -> [String] {
        value.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        }.filter { !$0.isEmpty }
    }

    private static func textContent(_ element: SVGXMLElement) -> String {
        var text = element.text
        for child in element.children {
            text += textContent(child)
        }
        return text
    }
}
