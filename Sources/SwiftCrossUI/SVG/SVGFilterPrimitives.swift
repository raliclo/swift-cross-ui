import Foundation

// The rest of SVG 1.1's filter primitives (2026-10-10): feMorphology,
// feConvolveMatrix, feTile, feDisplacementMap, feTurbulence,
// feDiffuseLighting, feSpecularLighting and feImage. Each works on
// premultiplied pixels in the filter's pixel grid -- the device layer, or
// filter space for a rotated element (see SVGFilters.swift) -- and follows the
// formulas SVG 1.1 chapter 15 gives, feTurbulence its reference code.
//
// SVG 1.1 其餘的濾鏡 primitive(2026-10-10):feMorphology、feConvolveMatrix、feTile、
// feDisplacementMap、feTurbulence、feDiffuseLighting、feSpecularLighting 與 feImage。每一個都在濾鏡的
// 像素格上處理預乘像素——裝置圖層，或旋轉元素的濾鏡空間(見 SVGFilters.swift)——並依 SVG 1.1 第 15 章的
// 公式計算，feTurbulence 依其參考程式碼。

/// feConvolveMatrix's parameters. / feConvolveMatrix 的參數。
struct SVGConvolution: Sendable {
    var orderX: Int
    var orderY: Int
    var kernel: [Float]
    var divisor: Float
    var bias: Float
    var targetX: Int
    var targetY: Int
    /// "duplicate", "wrap" or "none". / "duplicate"、"wrap" 或 "none"。
    var edgeMode: String
    var preserveAlpha: Bool
}

/// feTurbulence's parameters, frequencies per user unit.
/// feTurbulence 的參數，頻率以每使用者單位計。
struct SVGTurbulence: Sendable {
    var frequencyX: Double
    var frequencyY: Double
    var octaves: Int
    var seed: Double
    var fractalNoise: Bool
    var stitch: Bool
}

/// A light source in the filtered element's user space.
/// 被濾鏡元素使用者空間中的光源。
enum SVGLight: Sendable {
    case distant(azimuth: Double, elevation: Double)
    case point(x: Double, y: Double, z: Double)
    case spot(
        x: Double, y: Double, z: Double, atX: Double, atY: Double, atZ: Double, exponent: Double,
        cone: Double?)
}

/// feDiffuseLighting or feSpecularLighting. / feDiffuseLighting 或 feSpecularLighting。
struct SVGLighting: Sendable {
    var specular: Bool
    var surfaceScale: Double
    /// kd or ks. / kd 或 ks。
    var constant: Double
    /// The specular exponent; unused for diffuse. / 鏡面指數；漫射不用。
    var exponent: Double
    var color: SVGColor
    var light: SVGLight
}

extension SVGFilterRenderer {
    // MARK: feMorphology

    /// Erode (minimum) or dilate (maximum) over a (2rx+1) x (2ry+1) box, per
    /// channel, radii in pixels. A zero radius in either direction passes the input through.
    /// 在 (2rx+1) x (2ry+1) 的方框內逐通道取最小(erode)或最大(dilate),半徑以像素計。任一方向半徑為零時原樣傳回輸入。
    static func morphology(
        _ pixels: [Float], width: Int, height: Int, dilate: Bool, rx: Int, ry: Int
    ) -> [Float] {
        guard rx > 0, ry > 0 else { return pixels }
        func pass(_ input: [Float], radius: Int, horizontal: Bool) -> [Float] {
            var out = input
            let lines = horizontal ? height : width
            let length = horizontal ? width : height
            for line in 0..<lines {
                for p in 0..<length {
                    for c in 0..<4 {
                        var best: Float = dilate ? 0 : 1
                        for q in max(0, p - radius)...min(length - 1, p + radius) {
                            let i = horizontal ? (line * width + q) * 4 : (q * width + line) * 4
                            best = dilate ? max(best, input[i + c]) : min(best, input[i + c])
                        }
                        let o = horizontal ? (line * width + p) * 4 : (p * width + line) * 4
                        out[o + c] = best
                    }
                }
            }
            return out
        }
        return pass(pass(pixels, radius: rx, horizontal: true), radius: ry, horizontal: false)
    }

    // MARK: feConvolveMatrix

    static func convolve(_ pixels: [Float], width: Int, height: Int, _ m: SVGConvolution) -> [Float] {
        var out = [Float](repeating: 0, count: pixels.count)
        func sample(_ x: Int, _ y: Int, _ c: Int) -> Float {
            var sx = x
            var sy = y
            switch m.edgeMode {
                case "wrap":
                    sx = ((x % width) + width) % width
                    sy = ((y % height) + height) % height
                case "none":
                    if x < 0 || y < 0 || x >= width || y >= height { return 0 }
                default:  // duplicate
                    sx = min(max(x, 0), width - 1)
                    sy = min(max(y, 0), height - 1)
            }
            let index = (sy * width + sx) * 4
            if m.preserveAlpha && c < 3 {
                let alpha = pixels[index + 3]
                return alpha > 0 ? pixels[index + c] / alpha : 0
            }
            return pixels[index + c]
        }
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                var result: [Float] = [0, 0, 0, 0]
                for c in 0..<(m.preserveAlpha ? 3 : 4) {
                    var sum: Float = 0
                    for i in 0..<m.orderY {
                        for j in 0..<m.orderX {
                            // SVG 1.1 15.13: the kernel is applied rotated by 180 degrees.
                            // SVG 1.1 15.13:核旋轉 180 度後套用。
                            let k = m.kernel[(m.orderY - i - 1) * m.orderX + (m.orderX - j - 1)]
                            sum += sample(x - m.targetX + j, y - m.targetY + i, c) * k
                        }
                    }
                    result[c] = sum / m.divisor + m.bias
                }
                if m.preserveAlpha {
                    let alpha = pixels[index + 3]
                    for c in 0..<3 { out[index + c] = min(max(result[c], 0), 1) * alpha }
                    out[index + 3] = alpha
                } else {
                    let alpha = min(max(result[3], 0), 1)
                    out[index + 3] = alpha
                    for c in 0..<3 { out[index + c] = min(max(result[c], 0), alpha) }
                }
            }
        }
        return out
    }

    // MARK: feTile

    /// Repeats the part of `pixels` inside `tile` (pixel rectangle) everywhere.
    /// 把 `pixels` 在 `tile`(像素矩形)內的部分重複到各處。
    static func tile(
        _ pixels: [Float], width: Int, height: Int,
        tile: (x: Int, y: Int, width: Int, height: Int)
    ) -> [Float] {
        guard tile.width > 0, tile.height > 0 else { return pixels }
        var out = [Float](repeating: 0, count: pixels.count)
        for y in 0..<height {
            let sy = tile.y + ((((y - tile.y) % tile.height) + tile.height) % tile.height)
            guard sy >= 0, sy < height else { continue }
            for x in 0..<width {
                let sx = tile.x + ((((x - tile.x) % tile.width) + tile.width) % tile.width)
                guard sx >= 0, sx < width else { continue }
                let to = (y * width + x) * 4
                let from = (sy * width + sx) * 4
                for c in 0..<4 { out[to + c] = pixels[from + c] }
            }
        }
        return out
    }

    // MARK: feDisplacementMap

    /// P'(x,y) = P(x + sx (XC - 0.5), y + sy (YC - 0.5)), the map's channels
    /// read straight; scales in pixels.
    /// P'(x,y) = P(x + sx (XC - 0.5), y + sy (YC - 0.5)),以未預乘的方式讀取對照圖的通道；縮放以像素計。
    static func displace(
        _ pixels: [Float], map: [Float], width: Int, height: Int, scaleX: Double, scaleY: Double,
        xChannel: Int, yChannel: Int
    ) -> [Float] {
        var out = [Float](repeating: 0, count: pixels.count)
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                let alpha = map[index + 3]
                func channel(_ c: Int) -> Double {
                    if c == 3 { return Double(alpha) }
                    return alpha > 0 ? Double(map[index + c] / alpha) : 0
                }
                let sx = Int((Double(x) + scaleX * (channel(xChannel) - 0.5)).rounded())
                let sy = Int((Double(y) + scaleY * (channel(yChannel) - 0.5)).rounded())
                guard sx >= 0, sy >= 0, sx < width, sy < height else { continue }
                let from = (sy * width + sx) * 4
                for c in 0..<4 { out[index + c] = pixels[from + c] }
            }
        }
        return out
    }

    // MARK: feTurbulence (SVG 1.1 15.24 reference code)

    struct PerlinLattice {
        static let size = 0x100
        static let mask = 0xff
        static let offset = 4096.0
        var selector = [Int](repeating: 0, count: 0x100 + 0x100 + 2)
        var gradient = [[Double]](repeating: [Double](repeating: 0, count: (0x100 + 0x100 + 2) * 2), count: 4)

        init(seed: Double) {
            let m = 2_147_483_647
            func random(_ seed: Int) -> Int {
                var result = 16807 * (seed % 127_773) - 2836 * (seed / 127_773)
                if result <= 0 { result += m }
                return result
            }
            var s = Int(seed.rounded(.toNearestOrEven))
            if s <= 0 { s = -(s % (m - 1)) + 1 }
            if s > m - 1 { s = m - 1 }
            let b = Self.size
            for k in 0..<4 {
                for i in 0..<b {
                    selector[i] = i
                    for j in 0..<2 {
                        s = random(s)
                        gradient[k][i * 2 + j] = Double((s % (b + b)) - b) / Double(b)
                    }
                    let length = (gradient[k][i * 2] * gradient[k][i * 2]
                        + gradient[k][i * 2 + 1] * gradient[k][i * 2 + 1]).squareRoot()
                    if length > 0 {
                        gradient[k][i * 2] /= length
                        gradient[k][i * 2 + 1] /= length
                    }
                }
            }
            var i = b
            while true {
                i -= 1
                if i == 0 { break }
                let k = selector[i]
                s = random(s)
                let j = s % b
                selector[i] = selector[j]
                selector[j] = k
            }
            for i in 0..<(b + 2) {
                selector[b + i] = selector[i]
                for k in 0..<4 {
                    gradient[k][(b + i) * 2] = gradient[k][i * 2]
                    gradient[k][(b + i) * 2 + 1] = gradient[k][i * 2 + 1]
                }
            }
        }

        struct Stitch {
            var width: Int
            var height: Int
            var wrapX: Int
            var wrapY: Int
        }

        func noise(_ channel: Int, _ x: Double, _ y: Double, _ stitch: Stitch?) -> Double {
            func sCurve(_ t: Double) -> Double { t * t * (3 - 2 * t) }
            func lerp(_ t: Double, _ a: Double, _ b: Double) -> Double { a + t * (b - a) }
            var t = x + Self.offset
            var bx0 = Int(t) & Self.mask
            var bx1 = (bx0 + 1) & Self.mask
            let rx0 = t - Double(Int(t))
            let rx1 = rx0 - 1
            t = y + Self.offset
            var by0 = Int(t) & Self.mask
            var by1 = (by0 + 1) & Self.mask
            let ry0 = t - Double(Int(t))
            let ry1 = ry0 - 1
            if let stitch {
                if bx0 >= stitch.wrapX { bx0 -= stitch.width }
                if bx1 >= stitch.wrapX { bx1 -= stitch.width }
                if by0 >= stitch.wrapY { by0 -= stitch.height }
                if by1 >= stitch.wrapY { by1 -= stitch.height }
            }
            bx0 &= Self.mask
            bx1 &= Self.mask
            by0 &= Self.mask
            by1 &= Self.mask
            let i = selector[bx0]
            let j = selector[bx1]
            let b00 = selector[i + by0]
            let b10 = selector[j + by0]
            let b01 = selector[i + by1]
            let b11 = selector[j + by1]
            let sx = sCurve(rx0)
            let sy = sCurve(ry0)
            let g = gradient[channel]
            var u = rx0 * g[b00 * 2] + ry0 * g[b00 * 2 + 1]
            var v = rx1 * g[b10 * 2] + ry0 * g[b10 * 2 + 1]
            let a = lerp(sx, u, v)
            u = rx0 * g[b01 * 2] + ry1 * g[b01 * 2 + 1]
            v = rx1 * g[b11 * 2] + ry1 * g[b11 * 2 + 1]
            let b = lerp(sx, u, v)
            return lerp(sy, a, b)
        }

        func turbulence(
            _ channel: Int, x: Double, y: Double, _ p: SVGTurbulence, tile: SVGRect
        ) -> Double {
            var fx = p.frequencyX
            var fy = p.frequencyY
            var stitch: Stitch?
            if p.stitch {
                if fx != 0 {
                    let low = (tile.width * fx).rounded(.down) / tile.width
                    let high = (tile.width * fx).rounded(.up) / tile.width
                    fx = (low > 0 && fx / low < high / fx) ? low : high
                }
                if fy != 0 {
                    let low = (tile.height * fy).rounded(.down) / tile.height
                    let high = (tile.height * fy).rounded(.up) / tile.height
                    fy = (low > 0 && fy / low < high / fy) ? low : high
                }
                let w = Int(tile.width * fx + 0.5)
                let h = Int(tile.height * fy + 0.5)
                stitch = Stitch(
                    width: w, height: h, wrapX: Int(tile.x * fx + Self.offset) + w,
                    wrapY: Int(tile.y * fy + Self.offset) + h)
            }
            var sum = 0.0
            var vx = x * fx
            var vy = y * fy
            var ratio = 1.0
            for _ in 0..<max(p.octaves, 0) {
                let n = noise(channel, vx, vy, stitch)
                sum += (p.fractalNoise ? n : abs(n)) / ratio
                vx *= 2
                vy *= 2
                ratio *= 2
                if var s = stitch {
                    s.width += s.width
                    s.wrapX = 2 * s.wrapX - Int(Self.offset)
                    s.height += s.height
                    s.wrapY = 2 * s.wrapY - Int(Self.offset)
                    stitch = s
                }
            }
            return sum
        }
    }

    /// Noise at each pixel centre, mapped back to user space by `toUser`.
    /// 每個像素中心的雜訊，經 `toUser` 映射回使用者空間。
    static func turbulence(
        _ p: SVGTurbulence, width: Int, height: Int, toUser: SVGTransform, tile: SVGRect
    ) -> [Float] {
        let lattice = PerlinLattice(seed: p.seed)
        var out = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let point = toUser.apply(SVGPoint(Double(x) + 0.5, Double(y) + 0.5))
                var v: [Float] = [0, 0, 0, 0]
                for c in 0..<4 {
                    let sum = lattice.turbulence(c, x: point.x, y: point.y, p, tile: tile)
                    let value = p.fractalNoise ? (sum + 1) / 2 : sum
                    v[c] = Float(min(max(value, 0), 1))
                }
                let index = (y * width + x) * 4
                out[index] = v[0] * v[3]
                out[index + 1] = v[1] * v[3]
                out[index + 2] = v[2] * v[3]
                out[index + 3] = v[3]
            }
        }
        return out
    }

    // MARK: Lighting (SVG 1.1 15.14, 15.22)

    /// The surface normal from the input's alpha with SVG's Sobel kernels,
    /// including its edge and corner forms.
    /// 以 SVG 的 Sobel 核(含邊緣與角落的形式)由輸入的 alpha 求表面法線。
    static func normal(
        _ alpha: (Int, Int) -> Double, x: Int, y: Int, width: Int, height: Int, scale: Double
    ) -> (Double, Double, Double) {
        // One axis at a time: the two columns (or rows) compared, how far apart
        // they are, and the weights of the three rows (or columns) across.
        // 一次一個軸：比較的兩欄(或兩列)、它們的間距，以及橫跨的三列(或三欄)的權重。
        func derivative(along horizontal: Bool) -> Double {
            let p = horizontal ? x : y
            let limit = horizontal ? width : height
            let q = horizontal ? y : x
            let qLimit = horizontal ? height : width
            guard limit > 1 else { return 0 }
            let (low, high, spread): (Int, Int, Double) =
                p == 0 ? (p, p + 1, 2) : p == limit - 1 ? (p - 1, p, 2) : (p - 1, p + 1, 1)
            var weights: [(Int, Double)] = []
            if q > 0 { weights.append((q - 1, 1)) }
            weights.append((q, 2))
            if q < qLimit - 1 { weights.append((q + 1, 1)) }
            let total = weights.reduce(0) { $0 + $1.1 }
            var sum = 0.0
            for (r, w) in weights {
                let a = horizontal ? alpha(high, r) - alpha(low, r) : alpha(r, high) - alpha(r, low)
                sum += w * a
            }
            return spread / total * sum
        }
        let nx = -scale * derivative(along: true)
        let ny = -scale * derivative(along: false)
        let length = (nx * nx + ny * ny + 1).squareRoot()
        return (nx / length, ny / length, 1 / length)
    }

    /// Lights the input's alpha as a height map. `toDevice` places the light
    /// (user space to pixels) and `zScale` turns user units of height into pixels.
    /// 把輸入的 alpha 當作高度圖打光。`toDevice` 決定光源位置(使用者空間到像素),`zScale` 把使用者單位
    /// 的高度換成像素。
    static func light(
        _ pixels: [Float], width: Int, height: Int, _ l: SVGLighting, linear: Bool,
        toDevice: SVGTransform, zScale: Double
    ) -> [Float] {
        func alpha(_ x: Int, _ y: Int) -> Double { Double(pixels[(y * width + x) * 4 + 3]) }
        let colour = [l.color.red, l.color.green, l.color.blue].map {
            linear ? Double(toLinear(Float($0))) : $0
        }
        func place(_ x: Double, _ y: Double, _ z: Double) -> (Double, Double, Double) {
            let p = toDevice.apply(SVGPoint(x, y))
            return (p.x, p.y, z * zScale)
        }
        var out = [Float](repeating: 0, count: pixels.count)
        for y in 0..<height {
            for x in 0..<width {
                let n = normal(
                    alpha, x: x, y: y, width: width, height: height, scale: l.surfaceScale)
                let surface = (Double(x), Double(y), l.surfaceScale * alpha(x, y))
                var lightVector: (Double, Double, Double)
                var c = colour
                switch l.light {
                    case .distant(let azimuth, let elevation):
                        let a = azimuth * .pi / 180
                        let e = elevation * .pi / 180
                        lightVector = (cos(a) * cos(e), sin(a) * cos(e), sin(e))
                    case .point(let lx, let ly, let lz):
                        let p = place(lx, ly, lz)
                        lightVector = (p.0 - surface.0, p.1 - surface.1, p.2 - surface.2)
                    case .spot(let lx, let ly, let lz, let ax, let ay, let az, let exponent, let cone):
                        let p = place(lx, ly, lz)
                        let at = place(ax, ay, az)
                        lightVector = (p.0 - surface.0, p.1 - surface.1, p.2 - surface.2)
                        let ll = (lightVector.0 * lightVector.0 + lightVector.1 * lightVector.1
                            + lightVector.2 * lightVector.2).squareRoot()
                        var s = (at.0 - p.0, at.1 - p.1, at.2 - p.2)
                        let sl = (s.0 * s.0 + s.1 * s.1 + s.2 * s.2).squareRoot()
                        if ll > 0 && sl > 0 {
                            s = (s.0 / sl, s.1 / sl, s.2 / sl)
                            let minusLDotS = -(lightVector.0 * s.0 + lightVector.1 * s.1
                                + lightVector.2 * s.2) / ll
                            if minusLDotS <= 0
                                || (cone.map { minusLDotS < cos($0 * .pi / 180) } ?? false)
                            {
                                c = [0, 0, 0]
                            } else {
                                let f = pow(minusLDotS, exponent)
                                c = c.map { $0 * f }
                            }
                        }
                }
                let length = (lightVector.0 * lightVector.0 + lightVector.1 * lightVector.1
                    + lightVector.2 * lightVector.2).squareRoot()
                if length > 0 {
                    lightVector = (
                        lightVector.0 / length, lightVector.1 / length, lightVector.2 / length
                    )
                }
                let index = (y * width + x) * 4
                if l.specular {
                    var h = (lightVector.0, lightVector.1, lightVector.2 + 1)
                    let hl = (h.0 * h.0 + h.1 * h.1 + h.2 * h.2).squareRoot()
                    if hl > 0 { h = (h.0 / hl, h.1 / hl, h.2 / hl) }
                    let nh = max(n.0 * h.0 + n.1 * h.1 + n.2 * h.2, 0)
                    let f = l.constant * pow(nh, l.exponent)
                    let rgb = c.map { Float(min(max($0 * f, 0), 1)) }
                    // Alpha is the largest channel, so the result is premultiplied as it stands.
                    // alpha 是最大的通道，因此結果本身就是預乘的。
                    out[index] = rgb[0]
                    out[index + 1] = rgb[1]
                    out[index + 2] = rgb[2]
                    out[index + 3] = rgb.max() ?? 0
                } else {
                    let nl = max(n.0 * lightVector.0 + n.1 * lightVector.1 + n.2 * lightVector.2, 0)
                    let f = l.constant * nl
                    for k in 0..<3 { out[index + k] = Float(min(max(c[k] * f, 0), 1)) }
                    out[index + 3] = 1
                }
            }
        }
        return out
    }
}
