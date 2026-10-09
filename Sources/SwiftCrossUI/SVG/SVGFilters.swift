import Foundation

// `filter` (2026-10-10): every SVG 1.1 filter primitive, run on the element's
// layer in device pixels before its clip, mask and opacity, as SVG orders them.
//
// Here: feGaussianBlur, feOffset, feDropShadow, feFlood, feColorMatrix (all
// four types), feComposite (all operators, arithmetic included), feMerge,
// feBlend (normal, multiply, screen, darken, lighten) and feComponentTransfer;
// in SVGFilterPrimitives.swift: feMorphology, feConvolveMatrix, feTile,
// feDisplacementMap, feTurbulence, feDiffuseLighting and feSpecularLighting
// with all three lights, and feImage. `in`, `in2` and `result`; SourceGraphic
// and SourceAlpha; BackgroundImage, BackgroundAlpha, FillPaint and StrokePaint
// as transparent, which is what browsers draw for them; the filter region and
// primitive subregions in either unit; color-interpolation-filters, linearRGB
// by default as SVG specifies. A filter holding an element SVG does not define
// is not applied at all and stays reported and outlined: a filter drawn
// half-way looks deliberate, and a reader cannot tell which half is missing.
//
// The filter runs along the element's own axes. Where its user space is only
// scaled and moved on screen, that is the device-pixel layer itself; where it
// is rotated or skewed, the element is drawn in filter space first and the
// result resampled back (`applyInFilterSpace`), so a blur of "4 0" blurs along
// the element's x axis however it is turned.
//
// `filter`(2026-10-10):SVG 1.1 的全部濾鏡 primitive,依 SVG 的順序在元素的裁切、遮罩與不透明度之前，
// 以裝置像素在元素的圖層上執行。
//
// 本檔：feGaussianBlur、feOffset、feDropShadow、feFlood、feColorMatrix(四種類型)、feComposite
// (所有運算子，含 arithmetic)、feMerge、feBlend(normal、multiply、screen、darken、lighten)與
// feComponentTransfer;SVGFilterPrimitives.swift:feMorphology、feConvolveMatrix、feTile、
// feDisplacementMap、feTurbulence、feDiffuseLighting 與 feSpecularLighting(三種光源)以及 feImage。
// `in`、`in2` 與 `result`;SourceGraphic 與 SourceAlpha;BackgroundImage、BackgroundAlpha、FillPaint 與
// StrokePaint 視為透明，這也是瀏覽器畫出的結果；兩種單位下的濾鏡區域與 primitive 子區域；
// color-interpolation-filters,依 SVG 規定預設為 linearRGB。含有 SVG 未定義之元素的濾鏡完全不套用，
// 並照舊回報與框出：只畫一半的濾鏡看起來像是刻意的，讀者分不出缺的是哪一半。
//
// 濾鏡沿元素自己的座標軸執行。使用者空間在螢幕上只有縮放與平移時，那就是裝置像素圖層本身；有旋轉或斜切時，
// 先把元素畫在濾鏡空間、再把結果重新取樣回來(`applyInFilterSpace`),因此 "4 0" 的模糊不論元素怎麼轉，
// 都沿元素的 x 軸。

/// A `<filter>`, resolved for one element. / 為一個元素解析好的 `<filter>`。
struct SVGFilter: Sendable {
    var primitives: [SVGFilterPrimitive]
    /// The filter region in the element's user space. / 元素使用者空間中的濾鏡區域。
    var region: SVGRect
    /// The element's user space to root viewBox space.
    /// 元素使用者空間到根 viewBox 空間。
    var transform: SVGTransform
}

/// A transfer function of feComponentTransfer, on 0...1.
/// feComponentTransfer 的傳遞函式，作用於 0...1。
enum SVGTransferFunction: Sendable {
    case table([Double])
    case discrete([Double])
    case linear(slope: Double, intercept: Double)
    case gamma(amplitude: Double, exponent: Double, offset: Double)

    func apply(_ value: Float) -> Float {
        let c = Double(value)
        switch self {
            case .table(let v):
                guard v.count > 1 else { return v.first.map(Float.init) ?? value }
                let n = Double(v.count - 1)
                let k = min(Int(c * n), v.count - 2)
                return Float(v[k] + (c - Double(k) / n) * n * (v[k + 1] - v[k]))
            case .discrete(let v):
                guard !v.isEmpty else { return value }
                return Float(v[min(Int(c * Double(v.count)), v.count - 1)])
            case .linear(let slope, let intercept):
                return Float(slope * c + intercept)
            case .gamma(let amplitude, let exponent, let offset):
                return Float(amplitude * pow(c, exponent) + offset)
        }
    }
}

/// One filter primitive. / 一個濾鏡 primitive。
struct SVGFilterPrimitive: Sendable {
    enum Kind: Sendable {
        /// Standard deviations in user units. / 使用者單位的標準差。
        case blur(Double, Double)
        case offset(Double, Double)
        /// Opacity already applied. / 已套用不透明度。
        case flood(SVGColor)
        /// 20 values, row-major, on straight colour. / 20 個值，逐列，作用於未預乘的顏色。
        case colorMatrix([Float])
        case luminanceToAlpha
        case composite(String, k: [Float])
        case merge([String?])
        case blend(String)
        case dropShadow(dx: Double, dy: Double, sx: Double, sy: Double, color: SVGColor)
        /// R, G, B, A; nil is identity. / R、G、B、A;nil 為恆等。
        case componentTransfer([SVGTransferFunction?])
        /// Radii in user units. / 半徑以使用者單位計。
        case morphology(dilate: Bool, rx: Double, ry: Double)
        case convolve(SVGConvolution)
        case tile
        /// Scales in user units; channels 0 to 3 for R, G, B, A. / 縮放以使用者單位計；通道 0 到 3 為 R、G、B、A。
        case displacement(scaleX: Double, scaleY: Double, x: Int, y: Int)
        /// `tile` is the primitive subregion, for stitchTiles. / `tile` 為 primitive 子區域，供 stitchTiles 使用。
        case turbulence(SVGTurbulence, tile: SVGRect)
        case lighting(SVGLighting)
        /// What feImage draws, in root space. / feImage 畫出的東西，位於根空間。
        case image([SVGRenderNode])
    }

    var kind: Kind
    /// `in` and `in2`; nil is the previous result (SourceGraphic for the first).
    /// `in` 與 `in2`;nil 為上一個結果(第一個為 SourceGraphic)。
    var inputs: [String?]
    var result: String?
    /// Works on linearRGB rather than sRGB values.
    /// 以 linearRGB 而非 sRGB 的值運算。
    var linear: Bool
    /// The primitive subregion in user space; nil is the whole filter region.
    /// 使用者空間中的 primitive 子區域；nil 為整個濾鏡區域。
    var subregion: SVGRect?
}

// MARK: - Building / 建構

extension SVGBuilder {
    static let filterPrimitiveNames: Set<String> = [
        "feGaussianBlur", "feOffset", "feDropShadow", "feFlood", "feColorMatrix", "feComposite",
        "feMerge", "feBlend", "feComponentTransfer", "feMorphology", "feConvolveMatrix", "feTile",
        "feDisplacementMap", "feTurbulence", "feDiffuseLighting", "feSpecularLighting", "feImage",
    ]

    /// The `<filter>` that `reference` names, for an element drawing `nodes`
    /// in the user space `transform`. `.failure` carries why it is not applied.
    /// `reference` 所指的 `<filter>`,供在使用者空間 `transform` 中繪製 `nodes` 的元素使用。
    /// `.failure` 帶著不套用的原因。
    func filterEffect(
        _ reference: String, for element: SVGXMLElement, transform: SVGTransform,
        nodes: [SVGRenderNode]
    ) -> Result<SVGFilter?, FilterProblem> {
        guard let target = self.element(referencedBy: reference), target.localName == "filter" else {
            return .failure(FilterProblem("filter \(reference) does not name a <filter>"))
        }
        // feImage can draw the very element being filtered; that must not recurse.
        // feImage 可以畫出正被套用濾鏡的那個元素；這不能無限遞迴。
        let identity = ObjectIdentifier(target)
        guard !effectStack.contains(identity) else {
            return .failure(FilterProblem("filter \(reference) refers to itself"))
        }
        effectStack.append(identity)
        defer { effectStack.removeLast() }
        let box = Self.objectBounds(of: nodes, in: transform)
        let boxUnits = target[attribute: "filterUnits"] != "userSpaceOnUse"
        let primitiveBox = target[attribute: "primitiveUnits"] == "objectBoundingBox"
        func fraction(_ text: String?, _ fallback: Double) -> Double {
            guard let text = text?.trimmingCharacters(in: .whitespaces) else { return fallback }
            if text.hasSuffix("%") { return (Double(text.dropLast()) ?? fallback * 100) / 100 }
            return Double(text) ?? fallback
        }
        let region: SVGRect
        if boxUnits {
            // An empty box under objectBoundingBox units: the element is not drawn.
            // objectBoundingBox 單位下外框為空：元素不繪製。
            guard let box, box.width > 0, box.height > 0 else { return .success(nil) }
            region = SVGRect(
                x: box.x + fraction(target[attribute: "x"], -0.1) * box.width,
                y: box.y + fraction(target[attribute: "y"], -0.1) * box.height,
                width: fraction(target[attribute: "width"], 1.2) * box.width,
                height: fraction(target[attribute: "height"], 1.2) * box.height)
        } else {
            func value(_ name: String, _ fallback: String, _ axis: Axis) -> Double {
                length(target[attribute: name] ?? fallback, axis: axis) ?? 0
            }
            region = SVGRect(
                x: value("x", "-10%", .x), y: value("y", "-10%", .y),
                width: value("width", "120%", .x), height: value("height", "120%", .y))
        }
        guard region.width > 0, region.height > 0 else { return .success(nil) }

        // Numbers in primitiveUnits: user units, or fractions of the box.
        // primitiveUnits 中的數字：使用者單位，或外框的比例。
        func scaled(_ value: Double, _ axis: Axis) -> Double? {
            guard primitiveBox else { return value }
            guard let box else { return nil }
            return value * (axis == .x ? box.width : box.height)
        }
        func numbers(_ text: String?) -> [Double] {
            text.flatMap { SVGNumberScanner.numbers(in: $0) } ?? []
        }
        let filterSpace = target[attribute: "color-interpolation-filters"]
        func color(_ primitive: SVGXMLElement, default fallback: SVGColor) -> SVGColor {
            let style = primitive[attribute: "style"].map(SVGCSS.declarations) ?? []
            func property(_ name: String) -> String? {
                style.last { $0.name == name }?.value ?? primitive[attribute: name]
            }
            var color = property("flood-color").flatMap(SVGColor.parse) ?? fallback
            let opacity = property("flood-opacity").flatMap { Double($0) } ?? 1
            color = color.with(alpha: color.alpha * min(max(opacity, 0), 1))
            return color
        }

        var primitives: [SVGFilterPrimitive] = []
        for child in target.children where isSVGElement(child) {
            let name = child.localName
            if ["title", "desc", "metadata"].contains(name) { continue }
            guard Self.filterPrimitiveNames.contains(name) else {
                return .failure(FilterProblem("<\(name)> in filter \(reference) is not drawn"))
            }
            let space = child[attribute: "color-interpolation-filters"] ?? filterSpace
            var kind: SVGFilterPrimitive.Kind
            switch name {
                case "feGaussianBlur":
                    let values = numbers(child[attribute: "stdDeviation"])
                    let sx = values.first ?? 0
                    let sy = values.count > 1 ? values[1] : sx
                    guard let x = scaled(sx, .x), let y = scaled(sy, .y) else { return .success(nil) }
                    kind = .blur(max(x, 0), max(y, 0))
                case "feOffset":
                    let dx = Double(child[attribute: "dx"] ?? "0") ?? 0
                    let dy = Double(child[attribute: "dy"] ?? "0") ?? 0
                    guard let x = scaled(dx, .x), let y = scaled(dy, .y) else { return .success(nil) }
                    kind = .offset(x, y)
                case "feDropShadow":
                    let values = numbers(child[attribute: "stdDeviation"] ?? "2")
                    let sx = values.first ?? 2
                    let sy = values.count > 1 ? values[1] : sx
                    let dx = Double(child[attribute: "dx"] ?? "2") ?? 2
                    let dy = Double(child[attribute: "dy"] ?? "2") ?? 2
                    guard let x = scaled(dx, .x), let y = scaled(dy, .y),
                        let bx = scaled(sx, .x), let by = scaled(sy, .y)
                    else { return .success(nil) }
                    kind = .dropShadow(
                        dx: x, dy: y, sx: max(bx, 0), sy: max(by, 0),
                        color: color(child, default: SVGColor(red: 0, green: 0, blue: 0)))
                case "feFlood":
                    kind = .flood(color(child, default: SVGColor(red: 0, green: 0, blue: 0)))
                case "feColorMatrix":
                    let values = numbers(child[attribute: "values"])
                    switch child[attribute: "type"] ?? "matrix" {
                        case "matrix":
                            kind = .colorMatrix(
                                values.count == 20 ? values.map(Float.init) : Self.identityMatrix)
                        case "saturate":
                            kind = .colorMatrix(Self.saturate(values.first ?? 1))
                        case "hueRotate":
                            kind = .colorMatrix(Self.hueRotate(values.first ?? 0))
                        case "luminanceToAlpha":
                            kind = .luminanceToAlpha
                        case let other:
                            return .failure(FilterProblem("feColorMatrix type '\(other)'"))
                    }
                case "feComposite":
                    let op = child[attribute: "operator"] ?? "over"
                    guard ["over", "in", "out", "atop", "xor", "arithmetic"].contains(op) else {
                        return .failure(FilterProblem("feComposite operator '\(op)'"))
                    }
                    let k = ["k1", "k2", "k3", "k4"].map { Float(child[attribute: $0] ?? "0") ?? 0 }
                    kind = .composite(op, k: k)
                case "feMerge":
                    kind = .merge(
                        child.children.filter { $0.localName == "feMergeNode" }.map {
                            $0[attribute: "in"]
                        })
                case "feBlend":
                    let mode = child[attribute: "mode"] ?? "normal"
                    guard ["normal", "multiply", "screen", "darken", "lighten"].contains(mode) else {
                        return .failure(FilterProblem("feBlend mode '\(mode)'"))
                    }
                    kind = .blend(mode)
                case "feMorphology":
                    let values = numbers(child[attribute: "radius"])
                    let rx = values.first ?? 0
                    let ry = values.count > 1 ? values[1] : rx
                    guard let x = scaled(rx, .x), let y = scaled(ry, .y) else { return .success(nil) }
                    kind = .morphology(dilate: child[attribute: "operator"] == "dilate", rx: x, ry: y)
                case "feConvolveMatrix":
                    let order = numbers(child[attribute: "order"] ?? "3").map { Int($0) }
                    let ox = order.first ?? 3
                    let oy = order.count > 1 ? order[1] : ox
                    let kernel = numbers(child[attribute: "kernelMatrix"]).map(Float.init)
                    guard ox > 0, oy > 0, kernel.count == ox * oy else {
                        return .failure(
                            FilterProblem("feConvolveMatrix needs \(max(ox, 0) * max(oy, 0)) kernel values"))
                    }
                    let sum = kernel.reduce(0, +)
                    var divisor = Float(child[attribute: "divisor"] ?? "") ?? sum
                    if divisor == 0 { divisor = 1 }
                    let tx = Int(child[attribute: "targetX"] ?? "") ?? ox / 2
                    let ty = Int(child[attribute: "targetY"] ?? "") ?? oy / 2
                    guard (0..<ox).contains(tx), (0..<oy).contains(ty) else {
                        return .failure(FilterProblem("feConvolveMatrix target outside the kernel"))
                    }
                    kind = .convolve(
                        SVGConvolution(
                            orderX: ox, orderY: oy, kernel: kernel, divisor: divisor,
                            bias: Float(child[attribute: "bias"] ?? "0") ?? 0, targetX: tx, targetY: ty,
                            edgeMode: child[attribute: "edgeMode"] ?? "duplicate",
                            preserveAlpha: child[attribute: "preserveAlpha"] == "true"))
                case "feTile":
                    kind = .tile
                case "feDisplacementMap":
                    let scale = Double(child[attribute: "scale"] ?? "0") ?? 0
                    guard let sx = scaled(scale, .x), let sy = scaled(scale, .y) else {
                        return .success(nil)
                    }
                    func channel(_ name: String) -> Int {
                        ["R": 0, "G": 1, "B": 2, "A": 3][child[attribute: name] ?? "A"] ?? 3
                    }
                    kind = .displacement(
                        scaleX: sx, scaleY: sy, x: channel("xChannelSelector"),
                        y: channel("yChannelSelector"))
                case "feTurbulence":
                    let values = numbers(child[attribute: "baseFrequency"])
                    var fx = values.first ?? 0
                    var fy = values.count > 1 ? values[1] : fx
                    if primitiveBox {
                        guard let box, box.width > 0, box.height > 0 else { return .success(nil) }
                        fx /= box.width
                        fy /= box.height
                    }
                    guard fx >= 0, fy >= 0 else {
                        return .failure(FilterProblem("feTurbulence with a negative baseFrequency"))
                    }
                    kind = .turbulence(
                        SVGTurbulence(
                            frequencyX: fx, frequencyY: fy,
                            octaves: Int(child[attribute: "numOctaves"] ?? "1") ?? 1,
                            seed: Double(child[attribute: "seed"] ?? "0") ?? 0,
                            fractalNoise: child[attribute: "type"] == "fractalNoise",
                            stitch: child[attribute: "stitchTiles"] == "stitch"),
                        tile: region)
                case "feDiffuseLighting", "feSpecularLighting":
                    let style = child[attribute: "style"].map(SVGCSS.declarations) ?? []
                    let colorText =
                        style.last { $0.name == "lighting-color" }?.value
                        ?? child[attribute: "lighting-color"]
                    let lightColor =
                        colorText.flatMap(SVGColor.parse) ?? SVGColor(red: 1, green: 1, blue: 1)
                    guard
                        let source = child.children.first(where: {
                            ["feDistantLight", "fePointLight", "feSpotLight"].contains($0.localName)
                        })
                    else { return .failure(FilterProblem("<\(name)> has no light source")) }
                    func value(_ name: String, _ fallback: Double = 0) -> Double {
                        Double(source[attribute: name] ?? "") ?? fallback
                    }
                    // Light positions in primitiveUnits; z of a box measured against its diagonal.
                    // 光源位置以 primitiveUnits 計；外框單位下的 z 以對角線衡量。
                    func position(_ px: String, _ py: String, _ pz: String) -> (Double, Double, Double)? {
                        let (x, y, z) = (value(px), value(py), value(pz))
                        guard primitiveBox else { return (x, y, z) }
                        guard let box else { return nil }
                        let diagonal = ((box.width * box.width + box.height * box.height) / 2).squareRoot()
                        return (box.x + x * box.width, box.y + y * box.height, z * diagonal)
                    }
                    let light: SVGLight
                    switch source.localName {
                        case "feDistantLight":
                            light = .distant(azimuth: value("azimuth"), elevation: value("elevation"))
                        case "fePointLight":
                            guard let p = position("x", "y", "z") else { return .success(nil) }
                            light = .point(x: p.0, y: p.1, z: p.2)
                        default:
                            guard let p = position("x", "y", "z"),
                                let at = position("pointsAtX", "pointsAtY", "pointsAtZ")
                            else { return .success(nil) }
                            light = .spot(
                                x: p.0, y: p.1, z: p.2, atX: at.0, atY: at.1, atZ: at.2,
                                exponent: value("specularExponent", 1),
                                cone: source[attribute: "limitingConeAngle"].flatMap { Double($0) })
                    }
                    let specular = name == "feSpecularLighting"
                    kind = .lighting(
                        SVGLighting(
                            specular: specular,
                            surfaceScale: Double(child[attribute: "surfaceScale"] ?? "1") ?? 1,
                            constant: Double(
                                child[attribute: specular ? "specularConstant" : "diffuseConstant"] ?? "1")
                                ?? 1,
                            exponent: Double(child[attribute: "specularExponent"] ?? "1") ?? 1,
                            color: lightColor, light: light))
                case "feImage":
                    // Filled in below, once the subregion is known. / 待子區域確定後於下方填入。
                    kind = .image([])
                default:  // feComponentTransfer
                    var functions: [SVGTransferFunction?] = [nil, nil, nil, nil]
                    for (index, funcName) in ["feFuncR", "feFuncG", "feFuncB", "feFuncA"].enumerated() {
                        guard let function = child.children.last(where: { $0.localName == funcName })
                        else { continue }
                        let table = numbers(function[attribute: "tableValues"])
                        func number(_ name: String, _ fallback: Double) -> Double {
                            Double(function[attribute: name] ?? "") ?? fallback
                        }
                        switch function[attribute: "type"] ?? "identity" {
                            case "table": functions[index] = .table(table)
                            case "discrete": functions[index] = .discrete(table)
                            case "linear":
                                functions[index] = .linear(
                                    slope: number("slope", 1), intercept: number("intercept", 0))
                            case "gamma":
                                functions[index] = .gamma(
                                    amplitude: number("amplitude", 1),
                                    exponent: number("exponent", 1), offset: number("offset", 0))
                            default: break
                        }
                    }
                    kind = .componentTransfer(functions)
            }
            // Primitive subregion: x, y, width, height in primitiveUnits.
            // primitive 子區域：primitiveUnits 中的 x、y、width、height。
            var subregion: SVGRect?
            if ["x", "y", "width", "height"].contains(where: { child[attribute: $0] != nil }) {
                var sub = region
                if primitiveBox {
                    guard let box else { return .success(nil) }
                    if let v = child[attribute: "x"] { sub.x = box.x + fraction(v, 0) * box.width }
                    if let v = child[attribute: "y"] { sub.y = box.y + fraction(v, 0) * box.height }
                    if let v = child[attribute: "width"] { sub.width = fraction(v, 0) * box.width }
                    if let v = child[attribute: "height"] { sub.height = fraction(v, 0) * box.height }
                } else {
                    if let v = child[attribute: "x"], let l = length(v, axis: .x) { sub.x = l }
                    if let v = child[attribute: "y"], let l = length(v, axis: .y) { sub.y = l }
                    if let v = child[attribute: "width"], let l = length(v, axis: .x) { sub.width = l }
                    if let v = child[attribute: "height"], let l = length(v, axis: .y) { sub.height = l }
                }
                subregion = sub
            }
            if case .turbulence(let noise, _) = kind {
                kind = .turbulence(noise, tile: subregion ?? region)
            }
            if name == "feImage" {
                let area = subregion ?? region
                guard let href = child[attribute: "href"] ?? child[attribute: "xlink:href"] else {
                    return .failure(FilterProblem("feImage has no href"))
                }
                if href.hasPrefix("#") {
                    // An element, drawn as `use` would draw it, in the filtered element's user space.
                    // 一個元素，以 `use` 的方式繪製，位於被濾鏡元素的使用者空間。
                    guard let shown = elementsByID[String(href.dropFirst())] else {
                        return .failure(FilterProblem("feImage \(href) does not name an element"))
                    }
                    kind = .image(build(shown, parent: Style(), transform: transform))
                } else {
                    // A picture, placed in the subregion as <image> would place it.
                    // 一張圖片，以 <image> 的方式放進子區域。
                    let stand = SVGXMLElement(
                        name: "image",
                        attributes: [
                            ("x", "\(area.x)"), ("y", "\(area.y)"), ("width", "\(area.width)"),
                            ("height", "\(area.height)"),
                            ("preserveAspectRatio", child[attribute: "preserveAspectRatio"] ?? "xMidYMid meet"),
                            ("href", href),
                        ])
                    switch imageNodes(stand, style: Style(), transform: transform) {
                        case .success(let nodes): kind = .image(nodes)
                        case .failure(let problem):
                            return .failure(FilterProblem("feImage: \(problem.detail)"))
                    }
                }
            }
            primitives.append(
                SVGFilterPrimitive(
                    kind: kind, inputs: [child[attribute: "in"], child[attribute: "in2"]],
                    result: child[attribute: "result"], linear: space != "sRGB",
                    subregion: subregion))
        }
        // No primitives: the element is not drawn (SVG 1.1 15.7.1).
        // 沒有 primitive:元素不繪製(SVG 1.1 15.7.1)。
        guard !primitives.isEmpty else { return .success(nil) }
        return .success(SVGFilter(primitives: primitives, region: region, transform: transform))
    }

    struct FilterProblem: Error {
        let detail: String
        init(_ detail: String) { self.detail = detail }
    }

    static let identityMatrix: [Float] = [
        1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0,
    ]

    static func saturate(_ s: Double) -> [Float] {
        let s = Float(s)
        return [
            0.213 + 0.787 * s, 0.715 - 0.715 * s, 0.072 - 0.072 * s, 0, 0,
            0.213 - 0.213 * s, 0.715 + 0.285 * s, 0.072 - 0.072 * s, 0, 0,
            0.213 - 0.213 * s, 0.715 - 0.715 * s, 0.072 + 0.928 * s, 0, 0,
            0, 0, 0, 1, 0,
        ]
    }

    static func hueRotate(_ degrees: Double) -> [Float] {
        let r = degrees * .pi / 180
        let c = Float(cos(r))
        let s = Float(sin(r))
        return [
            0.213 + c * 0.787 - s * 0.213, 0.715 - c * 0.715 - s * 0.715,
            0.072 - c * 0.072 + s * 0.928, 0, 0,
            0.213 - c * 0.213 + s * 0.143, 0.715 + c * 0.285 + s * 0.140,
            0.072 - c * 0.072 - s * 0.283, 0, 0,
            0.213 - c * 0.213 - s * 0.787, 0.715 - c * 0.715 + s * 0.715,
            0.072 + c * 0.928 + s * 0.072, 0, 0,
            0, 0, 0, 1, 0,
        ]
    }
}

// MARK: - Running / 執行

/// Runs a filter on a layer. / 在圖層上執行濾鏡。
enum SVGFilterRenderer {
    /// Premultiplied pixels and the colour space they are in.
    /// 預乘像素，以及它們所在的色彩空間。
    struct Buffer {
        var pixels: [Float]
        var linear: Bool
    }

    static func apply(_ filter: SVGFilter, to layer: SVGCanvas, viewport: SVGTransform) -> SVGCanvas {
        let width = layer.width
        let height = layer.height
        let device = viewport.concatenating(filter.transform)
        // Pixels per user unit along each axis. / 每個使用者單位沿各軸的像素數。
        let scaleX = (device.a * device.a + device.b * device.b).squareRoot()
        let scaleY = (device.c * device.c + device.d * device.d).squareRoot()
        func regionMask(_ rect: SVGRect) -> [Float] {
            var canvas = SVGCanvas(width: width, height: height)
            let corners = [
                SVGPoint(rect.x, rect.y), SVGPoint(rect.x + rect.width, rect.y),
                SVGPoint(rect.x + rect.width, rect.y + rect.height),
                SVGPoint(rect.x, rect.y + rect.height),
            ].map(device.apply)
            canvas.fill([corners], rule: .nonzero, color: SVGBuilder.clipWhite)
            return canvas.alphaValues()
        }
        let regionValues = regionMask(filter.region)
        func clipped(_ pixels: [Float], _ mask: [Float]) -> [Float] {
            var out = pixels
            for pixel in 0..<(width * height) where mask[pixel] < 1 {
                for c in 0..<4 { out[pixel * 4 + c] *= mask[pixel] }
            }
            return out
        }

        let source = Buffer(pixels: clipped(layer.pixels, regionValues), linear: false)
        var sourceAlpha = source.pixels
        for pixel in 0..<(width * height) {
            sourceAlpha[pixel * 4] = 0
            sourceAlpha[pixel * 4 + 1] = 0
            sourceAlpha[pixel * 4 + 2] = 0
        }
        var results: [String: Buffer] = [:]
        var previous = source
        // Each result's subregion, for feTile. / 每個結果的子區域，供 feTile 使用。
        var regions: [String: SVGRect] = [:]
        var previousRegion = filter.region
        func inputRegion(_ name: String?) -> SVGRect {
            switch name {
                case nil: return previousRegion
                case let named?: return regions[named] ?? filter.region
            }
        }

        func input(_ name: String?, linear: Bool) -> [Float] {
            let buffer: Buffer
            switch name {
                case nil: buffer = previous
                case "SourceGraphic"?: buffer = source
                case "SourceAlpha"?: buffer = Buffer(pixels: sourceAlpha, linear: linear)
                // Never drawn by browsers either: transparent, as they treat them.
                // 瀏覽器也從不繪製：與它們一樣視為透明。
                case "BackgroundImage"?, "BackgroundAlpha"?, "FillPaint"?, "StrokePaint"?:
                    buffer = Buffer(pixels: [Float](repeating: 0, count: width * height * 4), linear: linear)
                case let named?: buffer = results[named] ?? previous
            }
            return convert(buffer, toLinear: linear)
        }

        for primitive in filter.primitives {
            let linear = primitive.linear
            let a = input(primitive.inputs[0], linear: linear)
            var out: [Float]
            switch primitive.kind {
                case .blur(let sx, let sy):
                    out = blur(a, width: width, height: height, sx: sx * scaleX, sy: sy * scaleY)
                case .offset(let dx, let dy):
                    out = offset(
                        a, width: width, height: height, dx: device.a * dx + device.c * dy,
                        dy: device.b * dx + device.d * dy)
                case .flood(let color):
                    out = flood(color, linear: linear, count: width * height)
                case .colorMatrix(let m):
                    out = map(a) { r, g, b, alpha in
                        let v = [r, g, b, alpha]
                        return (0..<4).map { row in
                            m[row * 5] * v[0] + m[row * 5 + 1] * v[1] + m[row * 5 + 2] * v[2]
                                + m[row * 5 + 3] * v[3] + m[row * 5 + 4]
                        }
                    }
                case .luminanceToAlpha:
                    out = map(a) { r, g, b, _ in [0, 0, 0, 0.2125 * r + 0.7154 * g + 0.0721 * b] }
                case .morphology(let dilate, let rx, let ry):
                    out = morphology(
                        a, width: width, height: height, dilate: dilate,
                        rx: Int((rx * scaleX).rounded()), ry: Int((ry * scaleY).rounded()))
                case .convolve(let m):
                    out = convolve(a, width: width, height: height, m)
                case .tile:
                    let r = inputRegion(primitive.inputs[0])
                    let corners = [
                        SVGPoint(r.x, r.y), SVGPoint(r.x + r.width, r.y + r.height),
                    ].map(device.apply)
                    let x0 = Int(min(corners[0].x, corners[1].x).rounded())
                    let y0 = Int(min(corners[0].y, corners[1].y).rounded())
                    let x1 = Int(max(corners[0].x, corners[1].x).rounded())
                    let y1 = Int(max(corners[0].y, corners[1].y).rounded())
                    out = tile(
                        a, width: width, height: height, tile: (x0, y0, x1 - x0, y1 - y0))
                case .displacement(let sx, let sy, let xc, let yc):
                    let map = input(primitive.inputs[1], linear: linear)
                    out = displace(
                        a, map: map, width: width, height: height, scaleX: sx * scaleX,
                        scaleY: sy * scaleY, xChannel: xc, yChannel: yc)
                case .turbulence(let noise, let tileRect):
                    if let toUser = device.inverted() {
                        out = turbulence(
                            noise, width: width, height: height, toUser: toUser, tile: tileRect)
                    } else {
                        out = [Float](repeating: 0, count: width * height * 4)
                    }
                case .lighting(let l):
                    out = light(
                        a, width: width, height: height, l, linear: linear, toDevice: device,
                        zScale: (scaleX + scaleY) / 2)
                case .image(let nodes):
                    var picture = SVGCanvas(width: width, height: height)
                    var ignored: [[SVGPoint]] = []
                    SVGRenderer.render(nodes, into: &picture, viewport: viewport, markers: &ignored)
                    out = convert(Buffer(pixels: picture.pixels, linear: false), toLinear: linear)
                case .componentTransfer(let functions):
                    out = map(a) { r, g, b, alpha in
                        zip([r, g, b, alpha], functions).map { value, function in
                            function?.apply(value) ?? value
                        }
                    }
                case .composite(let op, let k):
                    let b = input(primitive.inputs[1], linear: linear)
                    out = composite(a, b, op: op, k: k)
                case .blend(let mode):
                    let b = input(primitive.inputs[1], linear: linear)
                    out = blend(a, b, mode: mode)
                case .merge(let names):
                    out = [Float](repeating: 0, count: width * height * 4)
                    for name in names {
                        out = composite(input(name, linear: linear), out, op: "over", k: [])
                    }
                case .dropShadow(let dx, let dy, let sx, let sy, let color):
                    var alpha = a
                    for pixel in 0..<(width * height) {
                        alpha[pixel * 4] = 0
                        alpha[pixel * 4 + 1] = 0
                        alpha[pixel * 4 + 2] = 0
                    }
                    let blurred = blur(alpha, width: width, height: height, sx: sx * scaleX, sy: sy * scaleY)
                    let moved = offset(
                        blurred, width: width, height: height, dx: device.a * dx + device.c * dy,
                        dy: device.b * dx + device.d * dy)
                    let shadow = composite(
                        flood(color, linear: linear, count: width * height), moved, op: "in", k: [])
                    out = composite(a, shadow, op: "over", k: [])
            }
            var mask = regionValues
            if let subregion = primitive.subregion {
                let sub = regionMask(subregion)
                for index in mask.indices { mask[index] *= sub[index] }
            }
            out = clipped(out, mask)
            previous = Buffer(pixels: out, linear: linear)
            previousRegion = primitive.subregion ?? filter.region
            if let name = primitive.result {
                results[name] = previous
                regions[name] = previousRegion
            }
        }
        var result = layer
        result.pixels = convert(previous, toLinear: false)
        return result
    }

    /// For an element whose user space is rotated or skewed on screen: the
    /// children drawn in filter space -- the user space's own axes, at device
    /// resolution -- filtered there, and resampled back to device pixels, so a
    /// blur or an offset follows the element's axes exactly. nil when the user
    /// space is axis-aligned on screen, where filtering the device-pixel layer
    /// directly is already exact and spares a resampling.
    ///
    /// 用於使用者空間在螢幕上旋轉或斜切的元素：子節點畫在濾鏡空間——使用者空間自己的座標軸、裝置解析度——
    /// 在那裡執行濾鏡，再重新取樣回裝置像素，因此模糊與位移精確地沿元素的座標軸。使用者空間在螢幕上沿座標軸
    /// 時為 nil:那時直接處理裝置像素圖層已經精確，也省掉一次重新取樣。
    static func applyInFilterSpace(
        _ filter: SVGFilter, children: [SVGRenderNode], width: Int, height: Int,
        viewport: SVGTransform, markers: inout [[SVGPoint]], textMasker: SVGTextMasker?
    ) -> SVGCanvas? {
        let device = viewport.concatenating(filter.transform)
        guard abs(device.b) > 1e-9 || abs(device.c) > 1e-9,
            let toUser = filter.transform.inverted()
        else { return nil }
        let region = filter.region
        let pixelsX = max((device.a * device.a + device.b * device.b).squareRoot(), 1e-6)
        let pixelsY = max((device.c * device.c + device.d * device.d).squareRoot(), 1e-6)
        var columns = max(1.0, (region.width * pixelsX).rounded(.up))
        var rows = max(1.0, (region.height * pixelsY).rounded(.up))
        if columns * rows > SVGPatternTile.pixelLimit {
            let shrink = (SVGPatternTile.pixelLimit / (columns * rows)).squareRoot()
            columns = max(1, (columns * shrink).rounded(.down))
            rows = max(1, (rows * shrink).rounded(.down))
        }
        let toFilter = SVGTransform.scale(columns / region.width, rows / region.height)
            .concatenating(.translate(-region.x, -region.y))
        guard let fromFilter = toFilter.inverted() else { return nil }
        let filterViewport = toFilter.concatenating(toUser)

        var local = SVGCanvas(width: Int(columns), height: Int(rows))
        var localMarkers: [[SVGPoint]] = []
        SVGRenderer.render(
            children, into: &local, viewport: filterViewport, markers: &localMarkers,
            textMasker: textMasker)
        // Markers come back in filter pixels; the caller keeps them in device pixels.
        // 標記以濾鏡像素回來；呼叫端以裝置像素保存。
        if let back = filterViewport.inverted() {
            markers += localMarkers.map { $0.map { viewport.apply(back.apply($0)) } }
        }
        let filtered = apply(filter, to: local, viewport: filterViewport)

        var path = SVGPath()
        path.segments = [
            .move(SVGPoint(region.x, region.y)), .line(SVGPoint(region.x + region.width, region.y)),
            .line(SVGPoint(region.x + region.width, region.y + region.height)),
            .line(SVGPoint(region.x, region.y + region.height)), .close,
        ]
        let picture = SVGRasterImage(
            width: local.width, height: local.height, premultiplied: filtered.pixels,
            transform: fromFilter)
        let shape = SVGShape(
            path: path, transform: filter.transform, fill: .image(picture), fillRule: .nonzero,
            stroke: nil, strokeWidth: 0, lineCap: .butt, lineJoin: .miter, miterLimit: 4,
            dashes: nil, dashOffset: 0)
        var out = SVGCanvas(width: width, height: height)
        SVGRenderer.draw(shape, into: &out, viewport: viewport)
        return out
    }

    // MARK: Colour space / 色彩空間

    static func toLinear(_ c: Float) -> Float {
        // Double: Android's C library has no Float pow overload. / Double:Android 的 C 函式庫沒有 Float 版的 pow。
        c <= 0.04045 ? c / 12.92 : Float(pow((Double(c) + 0.055) / 1.055, 2.4))
    }

    static func toSRGB(_ c: Float) -> Float {
        c <= 0.0031308 ? c * 12.92 : Float(1.055 * pow(Double(c), 1 / 2.4) - 0.055)
    }

    static func convert(_ buffer: Buffer, toLinear linear: Bool) -> [Float] {
        guard buffer.linear != linear else { return buffer.pixels }
        let f = linear ? toLinear : toSRGB
        var out = buffer.pixels
        for index in stride(from: 0, to: out.count, by: 4) {
            let alpha = out[index + 3]
            guard alpha > 0 else { continue }
            for c in 0..<3 { out[index + c] = f(min(max(out[index + c] / alpha, 0), 1)) * alpha }
        }
        return out
    }

    /// Applies `body` to straight colour and premultiplies the clamped result.
    /// 對未預乘的顏色套用 `body`,並把夾住後的結果預乘。
    static func map(_ pixels: [Float], _ body: (Float, Float, Float, Float) -> [Float]) -> [Float] {
        var out = pixels
        for index in stride(from: 0, to: out.count, by: 4) {
            let alpha = pixels[index + 3]
            let r = alpha > 0 ? pixels[index] / alpha : 0
            let g = alpha > 0 ? pixels[index + 1] / alpha : 0
            let b = alpha > 0 ? pixels[index + 2] / alpha : 0
            let v = body(r, g, b, alpha).map { min(max($0, 0), 1) }
            out[index] = v[0] * v[3]
            out[index + 1] = v[1] * v[3]
            out[index + 2] = v[2] * v[3]
            out[index + 3] = v[3]
        }
        return out
    }

    static func flood(_ color: SVGColor, linear: Bool, count: Int) -> [Float] {
        let alpha = Float(color.alpha)
        let channels = [color.red, color.green, color.blue].map { value -> Float in
            let c = Float(value)
            return (linear ? toLinear(c) : c) * alpha
        }
        var out = [Float](repeating: 0, count: count * 4)
        for pixel in 0..<count {
            out[pixel * 4] = channels[0]
            out[pixel * 4 + 1] = channels[1]
            out[pixel * 4 + 2] = channels[2]
            out[pixel * 4 + 3] = alpha
        }
        return out
    }

    // MARK: Primitives / primitive

    static func composite(_ a: [Float], _ b: [Float], op: String, k: [Float]) -> [Float] {
        var out = [Float](repeating: 0, count: a.count)
        for index in stride(from: 0, to: a.count, by: 4) {
            let aa = a[index + 3]
            let ba = b[index + 3]
            for c in 0..<4 {
                let x = a[index + c]
                let y = b[index + c]
                let value: Float
                switch op {
                    case "in": value = x * ba
                    case "out": value = x * (1 - ba)
                    case "atop": value = x * ba + y * (1 - aa)
                    case "xor": value = x * (1 - ba) + y * (1 - aa)
                    case "arithmetic": value = k[0] * x * y + k[1] * x + k[2] * y + k[3]
                    default: value = x + y * (1 - aa)  // over
                }
                out[index + c] = min(max(value, 0), 1)
            }
            // Arithmetic can leave colour above alpha; keep it premultiplied.
            // arithmetic 可能讓顏色超過 alpha;保持預乘。
            for c in 0..<3 { out[index + c] = min(out[index + c], out[index + 3]) }
        }
        return out
    }

    static func blend(_ a: [Float], _ b: [Float], mode: String) -> [Float] {
        var out = [Float](repeating: 0, count: a.count)
        for index in stride(from: 0, to: a.count, by: 4) {
            let qa = a[index + 3]
            let qb = b[index + 3]
            for c in 0..<3 {
                let ca = a[index + c]
                let cb = b[index + c]
                let value: Float
                switch mode {
                    case "multiply": value = (1 - qa) * cb + (1 - qb) * ca + ca * cb
                    case "screen": value = cb + ca - ca * cb
                    case "darken": value = min((1 - qa) * cb + ca, (1 - qb) * ca + cb)
                    case "lighten": value = max((1 - qa) * cb + ca, (1 - qb) * ca + cb)
                    default: value = (1 - qa) * cb + ca  // normal
                }
                out[index + c] = min(max(value, 0), 1)
            }
            out[index + 3] = 1 - (1 - qa) * (1 - qb)
        }
        return out
    }

    static func offset(_ pixels: [Float], width: Int, height: Int, dx: Double, dy: Double) -> [Float] {
        let ox = Int(dx.rounded())
        let oy = Int(dy.rounded())
        var out = [Float](repeating: 0, count: pixels.count)
        for y in 0..<height {
            let sy = y - oy
            guard sy >= 0, sy < height else { continue }
            for x in 0..<width {
                let sx = x - ox
                guard sx >= 0, sx < width else { continue }
                let to = (y * width + x) * 4
                let from = (sy * width + sx) * 4
                out[to] = pixels[from]
                out[to + 1] = pixels[from + 1]
                out[to + 2] = pixels[from + 2]
                out[to + 3] = pixels[from + 3]
            }
        }
        return out
    }

    /// Gaussian blur, standard deviations in device pixels: three box blurs
    /// from 2 pixels up (the approximation SVG gives), an exact kernel below.
    /// 高斯模糊，標準差以裝置像素計：2 像素以上用三次盒狀模糊(SVG 給出的近似),以下用精確的核。
    static func blur(_ pixels: [Float], width: Int, height: Int, sx: Double, sy: Double) -> [Float] {
        var out = pixels
        if sx > 0 { out = blurPass(out, width: width, height: height, sigma: sx, horizontal: true) }
        if sy > 0 { out = blurPass(out, width: width, height: height, sigma: sy, horizontal: false) }
        return out
    }

    private static func blurPass(
        _ pixels: [Float], width: Int, height: Int, sigma: Double, horizontal: Bool
    ) -> [Float] {
        let lines = horizontal ? height : width
        let length = horizontal ? width : height
        func index(_ line: Int, _ position: Int) -> Int {
            horizontal ? (line * width + position) * 4 : (position * width + line) * 4
        }
        var out = pixels
        var line = [Float](repeating: 0, count: length * 4)
        for l in 0..<lines {
            for p in 0..<length {
                let i = index(l, p)
                for c in 0..<4 { line[p * 4 + c] = pixels[i + c] }
            }
            let blurred: [Float]
            if sigma < 2 {
                blurred = gaussian(line, length: length, sigma: sigma)
            } else {
                let d = Int((sigma * 3 * (2 * Double.pi).squareRoot() / 4 + 0.5).rounded(.down))
                if d % 2 == 1 {
                    let r = d / 2
                    blurred = box(box(box(line, length: length, left: r, right: r), length: length, left: r, right: r), length: length, left: r, right: r)
                } else {
                    let r = d / 2
                    blurred = box(
                        box(box(line, length: length, left: r, right: r - 1), length: length, left: r - 1, right: r),
                        length: length, left: r, right: r)
                }
            }
            for p in 0..<length {
                let i = index(l, p)
                for c in 0..<4 { out[i + c] = blurred[p * 4 + c] }
            }
        }
        return out
    }

    /// A box average over [p - left, p + right], zero outside.
    /// 在 [p - left, p + right] 上的盒狀平均，範圍外為零。
    private static func box(_ line: [Float], length: Int, left: Int, right: Int) -> [Float] {
        let size = Float(left + right + 1)
        var out = [Float](repeating: 0, count: line.count)
        var sums: [Float] = [0, 0, 0, 0]
        for p in 0..<min(right, length) {
            for c in 0..<4 { sums[c] += line[p * 4 + c] }
        }
        for p in 0..<length {
            let entering = p + right
            if entering < length { for c in 0..<4 { sums[c] += line[entering * 4 + c] } }
            for c in 0..<4 { out[p * 4 + c] = sums[c] / size }
            let leaving = p - left
            if leaving >= 0 { for c in 0..<4 { sums[c] -= line[leaving * 4 + c] } }
        }
        return out
    }

    private static func gaussian(_ line: [Float], length: Int, sigma: Double) -> [Float] {
        let radius = max(1, Int((3 * sigma).rounded(.up)))
        var weights = (-radius...radius).map { Float(exp(-Double($0 * $0) / (2 * sigma * sigma))) }
        let total = weights.reduce(0, +)
        weights = weights.map { $0 / total }
        var out = [Float](repeating: 0, count: line.count)
        for p in 0..<length {
            for (k, weight) in weights.enumerated() {
                let q = p + k - radius
                guard q >= 0, q < length else { continue }
                for c in 0..<4 { out[p * 4 + c] += line[q * 4 + c] * weight }
            }
        }
        return out
    }
}
