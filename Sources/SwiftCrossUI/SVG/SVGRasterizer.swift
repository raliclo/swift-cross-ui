import Foundation

/// `fill-rule`.
public enum SVGFillRule: String, Sendable {
    case nonzero, evenodd
}

/// An anti-aliased scanline polygon filler and a premultiplied RGBA canvas.
///
/// Coverage: each pixel row is sampled on `subsamples` horizontal lines. On
/// each line the crossings of the polygon edges are found, sorted, and walked
/// with the fill rule, so both nonzero and evenodd are exact per line; the
/// inside spans are added with fractional ends, so horizontal anti-aliasing
/// is exact and vertical anti-aliasing has `subsamples` levels. Full-pixel
/// runs go through a difference array so a wide fill costs one addition per
/// span rather than one per pixel.
///
/// 一個抗鋸齒的掃描線多邊形填充器，以及一張預乘 RGBA 畫布。
///
/// 覆蓋率：每一列像素在 `subsamples` 條水平線上取樣。每條線上找出多邊形各邊的交點、排序，並依
/// 填充規則走過，因此 nonzero 與 evenodd 在每一條線上都是精確的；內部區段以帶小數的端點累加，
/// 所以水平方向的抗鋸齒是精確的，垂直方向則有 `subsamples` 個層級。整像素的區段經由差分陣列
/// 累加，因此寬的填充每個區段只花一次加法，而不是每個像素一次。
struct SVGCanvas {
    let width: Int
    let height: Int
    /// Premultiplied RGBA, row-major, top row first.
    /// 預乘 RGBA,逐列排列，最上面一列在前。
    var pixels: [Float]

    static let subsamples = 16

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        pixels = [Float](repeating: 0, count: width * height * 4)
    }

    /// Fills `polygons` (device pixels, implicitly closed) with `color`.
    /// 以 `color` 填充 `polygons`(裝置像素，隱含封閉)。
    mutating func fill(_ polygons: [[SVGPoint]], rule: SVGFillRule, color: SVGColor) {
        guard color.alpha > 0, width > 0, height > 0 else { return }
        let coverage = Self.coverage(of: polygons, rule: rule, width: width, height: height)
        guard let coverage else { return }
        let alpha = Float(color.alpha)
        let red = Float(color.red) * alpha
        let green = Float(color.green) * alpha
        let blue = Float(color.blue) * alpha
        for row in coverage.rowRange {
            let rowOffset = (row - coverage.rowRange.lowerBound) * coverage.columns
            for column in 0..<coverage.columns {
                let amount = min(coverage.values[rowOffset + column], 1)
                if amount <= 0 { continue }
                let index = (row * width + coverage.firstColumn + column) * 4
                let inverse = 1 - alpha * amount
                pixels[index] = red * amount + pixels[index] * inverse
                pixels[index + 1] = green * amount + pixels[index + 1] * inverse
                pixels[index + 2] = blue * amount + pixels[index + 2] * inverse
                pixels[index + 3] = alpha * amount + pixels[index + 3] * inverse
            }
        }
    }

    /// Fills `polygons` with a colour per pixel: a solid colour or a gradient.
    /// 以逐像素的顏色(單色或漸層)填充 `polygons`。
    mutating func fill(_ polygons: [[SVGPoint]], rule: SVGFillRule, shader: SVGShader) {
        guard width > 0, height > 0,
            let coverage = Self.coverage(of: polygons, rule: rule, width: width, height: height)
        else { return }
        for row in coverage.rowRange {
            let rowOffset = (row - coverage.rowRange.lowerBound) * coverage.columns
            for column in 0..<coverage.columns {
                let amount = min(coverage.values[rowOffset + column], 1)
                if amount <= 0 { continue }
                let x = coverage.firstColumn + column
                blend(shader.color(x: x, y: row), amount: amount, at: (row * width + x) * 4)
            }
        }
    }

    /// Fills through `mask` (one coverage byte per pixel) with a colour per pixel.
    /// 經 `mask`(每像素一個覆蓋率位元組)以逐像素的顏色填充。
    mutating func fill(mask: [UInt8], shader: SVGShader) {
        guard mask.count == width * height else { return }
        for pixel in 0..<(width * height) where mask[pixel] > 0 {
            blend(
                shader.color(x: pixel % width, y: pixel / width), amount: Float(mask[pixel]) / 255,
                at: pixel * 4)
        }
    }

    /// Source-over of a premultiplied colour at `amount` coverage.
    /// 以 `amount` 覆蓋率對預乘顏色做 source-over。
    private mutating func blend(_ color: SVGPremultiplied, amount: Float, at index: Int) {
        guard color.alpha > 0 else { return }
        let inverse = 1 - color.alpha * amount
        pixels[index] = color.red * amount + pixels[index] * inverse
        pixels[index + 1] = color.green * amount + pixels[index + 1] * inverse
        pixels[index + 2] = color.blue * amount + pixels[index + 2] * inverse
        pixels[index + 3] = color.alpha * amount + pixels[index + 3] * inverse
    }

    /// Fills with `color` through `mask`: one coverage byte per pixel, top row
    /// first, as a backend's text renderer returns it. A mask of the wrong size
    /// draws nothing.
    /// 以 `color` 經 `mask` 填充：每像素一個覆蓋率位元組、最上面一列在前，即 backend 文字繪製器回傳的
    /// 格式。尺寸不符的遮罩不會畫出任何東西。
    mutating func fill(mask: [UInt8], color: SVGColor) {
        guard color.alpha > 0, mask.count == width * height else { return }
        let alpha = Float(color.alpha)
        let red = Float(color.red) * alpha
        let green = Float(color.green) * alpha
        let blue = Float(color.blue) * alpha
        for pixel in 0..<(width * height) where mask[pixel] > 0 {
            let amount = Float(mask[pixel]) / 255
            let index = pixel * 4
            let inverse = 1 - alpha * amount
            pixels[index] = red * amount + pixels[index] * inverse
            pixels[index + 1] = green * amount + pixels[index + 1] * inverse
            pixels[index + 2] = blue * amount + pixels[index + 2] * inverse
            pixels[index + 3] = alpha * amount + pixels[index + 3] * inverse
        }
    }

    /// Each pixel's alpha, the coverage a clip is read as.
    /// 每個像素的 alpha,裁切讀取的覆蓋率。
    func alphaValues() -> [Float] {
        (0..<(width * height)).map { pixels[$0 * 4 + 3] }
    }

    /// Each pixel's luminance times its alpha, what a luminance mask reads:
    /// the colours are premultiplied, so the product is the plain weighted
    /// sum (sRGB coefficients, as browsers apply them by default).
    /// 每個像素的亮度乘以其 alpha,也就是亮度遮罩讀取的值：顏色是預乘的，所以乘積就是加權和
    /// (sRGB 係數，與瀏覽器的預設相同)。
    func luminanceValues() -> [Float] {
        (0..<(width * height)).map {
            let index = $0 * 4
            return min(
                0.2125 * pixels[index] + 0.7154 * pixels[index + 1] + 0.0721 * pixels[index + 2],
                1)
        }
    }

    /// Scales every pixel (all four premultiplied channels) by `factors`.
    /// 以 `factors` 縮放每個像素(全部四個預乘通道)。
    mutating func multiply(by factors: [Float]) {
        for pixel in 0..<min(width * height, factors.count) {
            let factor = factors[pixel]
            if factor >= 1 { continue }
            let index = pixel * 4
            pixels[index] *= factor
            pixels[index + 1] *= factor
            pixels[index + 2] *= factor
            pixels[index + 3] *= factor
        }
    }

    /// Composites `layer` over this canvas at `opacity` (group opacity).
    /// 以 `opacity`(群組不透明度)把 `layer` 合成到此畫布上。
    mutating func composite(_ layer: SVGCanvas, opacity: Double) {
        let factor = Float(opacity)
        for pixel in 0..<(width * height) {
            let index = pixel * 4
            let sourceAlpha = layer.pixels[index + 3] * factor
            if sourceAlpha <= 0 { continue }
            let inverse = 1 - sourceAlpha
            pixels[index] = layer.pixels[index] * factor + pixels[index] * inverse
            pixels[index + 1] = layer.pixels[index + 1] * factor + pixels[index + 1] * inverse
            pixels[index + 2] = layer.pixels[index + 2] * factor + pixels[index + 2] * inverse
            pixels[index + 3] = sourceAlpha + pixels[index + 3] * inverse
        }
    }

    /// Straight-alpha RGBA bytes, the format `ImageFormats.Image<RGBA>` and
    /// every backend's `updateImageView` take.
    ///
    /// 未預乘的 RGBA 位元組——`ImageFormats.Image<RGBA>` 與每個 backend 的 `updateImageView`
    /// 所接受的格式。
    func straightRGBABytes() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for pixel in 0..<(width * height) {
            let index = pixel * 4
            let alpha = min(max(pixels[index + 3], 0), 1)
            if alpha <= 0 { continue }
            func byte(_ value: Float) -> UInt8 {
                UInt8(min(max(value / alpha, 0), 1) * 255 + 0.5)
            }
            bytes[index] = byte(pixels[index])
            bytes[index + 1] = byte(pixels[index + 1])
            bytes[index + 2] = byte(pixels[index + 2])
            bytes[index + 3] = UInt8(alpha * 255 + 0.5)
        }
        return bytes
    }

    // MARK: Coverage / 覆蓋率

    struct Coverage {
        var rowRange: Range<Int>
        var firstColumn: Int
        var columns: Int
        /// Per pixel, row-major over the bounding box; may exceed 1 slightly.
        /// 依包圍盒逐列排列的每像素值；可能略大於 1。
        var values: [Float]
    }

    private struct Edge {
        var x0: Double, y0: Double, x1: Double, y1: Double
        var direction: Int
        var slope: Double
    }

    static func coverage(
        of polygons: [[SVGPoint]], rule: SVGFillRule, width: Int, height: Int
    ) -> Coverage? {
        var edges: [Edge] = []
        var minX = Double.infinity, maxX = -Double.infinity
        var minY = Double.infinity, maxY = -Double.infinity
        for polygon in polygons where polygon.count >= 3 {
            for index in polygon.indices {
                let a = polygon[index]
                let b = polygon[(index + 1) % polygon.count]
                guard a.x.isFinite, a.y.isFinite, b.x.isFinite, b.y.isFinite else { continue }
                minX = min(minX, a.x)
                maxX = max(maxX, a.x)
                minY = min(minY, a.y)
                maxY = max(maxY, a.y)
                if a.y == b.y { continue }
                if a.y < b.y {
                    edges.append(
                        Edge(x0: a.x, y0: a.y, x1: b.x, y1: b.y, direction: 1,
                            slope: (b.x - a.x) / (b.y - a.y)))
                } else {
                    edges.append(
                        Edge(x0: b.x, y0: b.y, x1: a.x, y1: a.y, direction: -1,
                            slope: (a.x - b.x) / (a.y - b.y)))
                }
            }
        }
        guard !edges.isEmpty else { return nil }
        let firstRow = max(0, Int(minY.rounded(.down)))
        let endRow = min(height, Int(maxY.rounded(.up)))
        let firstColumn = max(0, Int(minX.rounded(.down)))
        let endColumn = min(width, Int(maxX.rounded(.up)))
        guard firstRow < endRow, firstColumn < endColumn else { return nil }
        let columns = endColumn - firstColumn
        let rows = endRow - firstRow

        edges.sort { $0.y0 < $1.y0 }
        var values = [Float](repeating: 0, count: rows * columns)
        // Partial-pixel contributions and full-run differences for one row.
        // 一列之中的部分像素貢獻與整段差分。
        var partial = [Float](repeating: 0, count: columns + 1)
        var runs = [Float](repeating: 0, count: columns + 1)
        var active: [Int] = []
        var nextEdge = 0
        var crossings: [(x: Double, direction: Int)] = []
        let weight = 1 / Float(subsamples)
        let left = Double(firstColumn)
        let right = Double(endColumn)

        for row in firstRow..<endRow {
            for index in 0...columns {
                partial[index] = 0
                runs[index] = 0
            }
            var touched = false
            for sample in 0..<subsamples {
                let y = Double(row) + (Double(sample) + 0.5) / Double(subsamples)
                while nextEdge < edges.count && edges[nextEdge].y0 <= y {
                    active.append(nextEdge)
                    nextEdge += 1
                }
                active.removeAll { edges[$0].y1 <= y }
                crossings.removeAll(keepingCapacity: true)
                for index in active where edges[index].y0 <= y {
                    let edge = edges[index]
                    crossings.append((edge.x0 + (y - edge.y0) * edge.slope, edge.direction))
                }
                if crossings.count < 2 { continue }
                crossings.sort { $0.x < $1.x }
                var winding = 0
                for index in 0..<(crossings.count - 1) {
                    winding += crossings[index].direction
                    let inside = rule == .nonzero ? winding != 0 : winding % 2 != 0
                    if !inside { continue }
                    let start = max(crossings[index].x, left)
                    let end = min(crossings[index + 1].x, right)
                    if end <= start { continue }
                    touched = true
                    let a = start - left
                    let b = end - left
                    let ia = Int(a)
                    let ib = Int(b)
                    if ia == ib {
                        partial[ia] += Float(b - a) * weight
                    } else {
                        partial[ia] += Float(Double(ia + 1) - a) * weight
                        if ib < columns {
                            partial[ib] += Float(b - Double(ib)) * weight
                        }
                        if ia + 1 < ib {
                            runs[ia + 1] += weight
                            runs[ib] -= weight
                        }
                    }
                }
            }
            if !touched { continue }
            var run: Float = 0
            let rowOffset = (row - firstRow) * columns
            for column in 0..<columns {
                run += runs[column]
                values[rowOffset + column] = partial[column] + run
            }
        }
        return Coverage(
            rowRange: firstRow..<endRow, firstColumn: firstColumn, columns: columns, values: values)
    }
}
