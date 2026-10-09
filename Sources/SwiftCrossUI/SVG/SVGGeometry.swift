import Foundation

// Geometry for the SVG renderer: points, affine transforms, path data and
// curve flattening. Everything is `Double`; pixels are only reached in
// `SVGRasterizer`.
//
// SVG 算繪器的幾何：點、仿射轉換、路徑資料與曲線平坦化。一律使用 `Double`;只有到了
// `SVGRasterizer` 才變成像素。

/// A point in some SVG coordinate system.
/// 某個 SVG 座標系中的一點。
struct SVGPoint: Equatable, Sendable {
    var x: Double
    var y: Double

    init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    static func + (a: SVGPoint, b: SVGPoint) -> SVGPoint { SVGPoint(a.x + b.x, a.y + b.y) }
    static func - (a: SVGPoint, b: SVGPoint) -> SVGPoint { SVGPoint(a.x - b.x, a.y - b.y) }
    static func * (a: SVGPoint, s: Double) -> SVGPoint { SVGPoint(a.x * s, a.y * s) }

    var length: Double { (x * x + y * y).squareRoot() }

    func distance(to other: SVGPoint) -> Double { (self - other).length }
}

/// The SVG affine matrix `[a c e; b d f; 0 0 1]`.
/// SVG 仿射矩陣 `[a c e; b d f; 0 0 1]`。
struct SVGTransform: Equatable, Sendable {
    var a = 1.0, b = 0.0, c = 0.0, d = 1.0, e = 0.0, f = 0.0

    static let identity = SVGTransform()

    static func translate(_ x: Double, _ y: Double) -> SVGTransform {
        SVGTransform(a: 1, b: 0, c: 0, d: 1, e: x, f: y)
    }

    static func scale(_ x: Double, _ y: Double) -> SVGTransform {
        SVGTransform(a: x, b: 0, c: 0, d: y, e: 0, f: 0)
    }

    static func rotate(degrees: Double) -> SVGTransform {
        let radians = degrees * Double.pi / 180
        let cosine = cos(radians)
        let sine = sin(radians)
        return SVGTransform(a: cosine, b: sine, c: -sine, d: cosine, e: 0, f: 0)
    }

    /// `self` applied after `other`: a point goes through `other` first.
    /// 先套用 `other` 再套用 `self`。
    func concatenating(_ other: SVGTransform) -> SVGTransform {
        SVGTransform(
            a: a * other.a + c * other.b,
            b: b * other.a + d * other.b,
            c: a * other.c + c * other.d,
            d: b * other.c + d * other.d,
            e: a * other.e + c * other.f + e,
            f: b * other.e + d * other.f + f
        )
    }

    func apply(_ point: SVGPoint) -> SVGPoint {
        SVGPoint(a * point.x + c * point.y + e, b * point.x + d * point.y + f)
    }

    /// How far one user unit can stretch under this transform at most: the
    /// larger singular value. Used to pick flattening tolerances.
    ///
    /// 一個使用者單位在此轉換下最多被拉長多少：較大的奇異值。用來選擇平坦化容差。
    var maximumScale: Double {
        let p = a * a + b * b
        let q = c * c + d * d
        let r = a * c + b * d
        let mean = (p + q) / 2
        let deviation = (((p - q) / 2) * ((p - q) / 2) + r * r).squareRoot()
        return (mean + deviation).squareRoot()
    }

    var isInvertible: Bool { abs(a * d - b * c) > 1e-12 }
}

/// One drawing command after path data has been normalised: absolute
/// coordinates, no shorthand, arcs already turned into cubics.
///
/// 路徑資料正規化後的一個繪圖命令：絕對座標、沒有簡寫，弧已轉為三次曲線。
enum SVGSegment: Equatable, Sendable {
    case move(SVGPoint)
    case line(SVGPoint)
    case quad(SVGPoint, SVGPoint)
    case cubic(SVGPoint, SVGPoint, SVGPoint)
    case close
}

/// A flattened subpath.
/// 平坦化後的一條子路徑。
struct SVGPolyline: Sendable {
    var points: [SVGPoint]
    var closed: Bool
}

struct SVGPath: Sendable {
    var segments: [SVGSegment] = []

    var isEmpty: Bool { segments.isEmpty }

    /// Turns curves into line segments no further than `tolerance` (in the
    /// path's own units) from the curve.
    ///
    /// 把曲線轉為直線段，與曲線的距離不超過 `tolerance`(以路徑自身的單位計)。
    func flattened(tolerance: Double) -> [SVGPolyline] {
        var result: [SVGPolyline] = []
        var current: [SVGPoint] = []
        var start = SVGPoint(0, 0)
        var point = SVGPoint(0, 0)

        func finish(closed: Bool) {
            if !current.isEmpty {
                result.append(SVGPolyline(points: current, closed: closed))
            }
            current = []
        }

        for segment in segments {
            switch segment {
                case .move(let p):
                    finish(closed: false)
                    start = p
                    point = p
                    current = [p]
                case .line(let p):
                    if current.isEmpty { current = [point] }
                    current.append(p)
                    point = p
                case .quad(let c1, let p):
                    if current.isEmpty { current = [point] }
                    let dd = (point - c1 * 2 + p).length
                    let count = Self.subdivisions(dd * 0.25, tolerance: tolerance)
                    for step in 1...count {
                        let t = Double(step) / Double(count)
                        let u = 1 - t
                        current.append(point * (u * u) + c1 * (2 * u * t) + p * (t * t))
                    }
                    point = p
                case .cubic(let c1, let c2, let p):
                    if current.isEmpty { current = [point] }
                    let dd = max(
                        (point - c1 * 2 + c2).length,
                        (c1 - c2 * 2 + p).length
                    )
                    let count = Self.subdivisions(dd * 0.75, tolerance: tolerance)
                    for step in 1...count {
                        let t = Double(step) / Double(count)
                        let u = 1 - t
                        current.append(
                            point * (u * u * u) + c1 * (3 * u * u * t) + c2 * (3 * u * t * t)
                                + p * (t * t * t)
                        )
                    }
                    point = p
                case .close:
                    finish(closed: true)
                    point = start
            }
        }
        finish(closed: false)
        return result
    }

    /// `n` with `bound / n² <= tolerance`, kept between 1 and 4096.
    /// 使 `bound / n² <= tolerance` 的 `n`,限制在 1 到 4096 之間。
    private static func subdivisions(_ bound: Double, tolerance: Double) -> Int {
        guard bound > 0, tolerance > 0, bound.isFinite else { return 1 }
        let count = (bound / tolerance).squareRoot().rounded(.up)
        return Int(min(max(count, 1), 4096))
    }

    // MARK: Shapes / 基本形狀

    static func rectangle(x: Double, y: Double, width: Double, height: Double, rx: Double, ry: Double)
        -> SVGPath
    {
        var path = SVGPath()
        if rx <= 0 || ry <= 0 {
            path.segments = [
                .move(SVGPoint(x, y)), .line(SVGPoint(x + width, y)),
                .line(SVGPoint(x + width, y + height)), .line(SVGPoint(x, y + height)), .close,
            ]
            return path
        }
        let k = 0.5522847498307936  // 4/3 (sqrt 2 - 1)
        let kx = rx * k
        let ky = ry * k
        let right = x + width
        let bottom = y + height
        path.segments = [
            .move(SVGPoint(x + rx, y)),
            .line(SVGPoint(right - rx, y)),
            .cubic(SVGPoint(right - rx + kx, y), SVGPoint(right, y + ry - ky), SVGPoint(right, y + ry)),
            .line(SVGPoint(right, bottom - ry)),
            .cubic(
                SVGPoint(right, bottom - ry + ky), SVGPoint(right - rx + kx, bottom),
                SVGPoint(right - rx, bottom)),
            .line(SVGPoint(x + rx, bottom)),
            .cubic(SVGPoint(x + rx - kx, bottom), SVGPoint(x, bottom - ry + ky), SVGPoint(x, bottom - ry)),
            .line(SVGPoint(x, y + ry)),
            .cubic(SVGPoint(x, y + ry - ky), SVGPoint(x + rx - kx, y), SVGPoint(x + rx, y)),
            .close,
        ]
        return path
    }

    static func ellipse(cx: Double, cy: Double, rx: Double, ry: Double) -> SVGPath {
        let k = 0.5522847498307936
        let kx = rx * k
        let ky = ry * k
        var path = SVGPath()
        path.segments = [
            .move(SVGPoint(cx + rx, cy)),
            .cubic(SVGPoint(cx + rx, cy + ky), SVGPoint(cx + kx, cy + ry), SVGPoint(cx, cy + ry)),
            .cubic(SVGPoint(cx - kx, cy + ry), SVGPoint(cx - rx, cy + ky), SVGPoint(cx - rx, cy)),
            .cubic(SVGPoint(cx - rx, cy - ky), SVGPoint(cx - kx, cy - ry), SVGPoint(cx, cy - ry)),
            .cubic(SVGPoint(cx + kx, cy - ry), SVGPoint(cx + rx, cy - ky), SVGPoint(cx + rx, cy)),
            .close,
        ]
        return path
    }

    // MARK: Arcs / 弧

    /// Appends the SVG elliptical arc from `from` to `to` as cubics, per the
    /// endpoint-to-centre conversion in SVG 1.1 appendix F.6.
    ///
    /// 依 SVG 1.1 附錄 F.6 的端點轉中心換算，把從 `from` 到 `to` 的橢圓弧以三次曲線附加上去。
    mutating func appendArc(
        from: SVGPoint, to: SVGPoint, rx rxIn: Double, ry ryIn: Double,
        rotation: Double, largeArc: Bool, sweep: Bool
    ) {
        if from == to { return }
        var rx = abs(rxIn)
        var ry = abs(ryIn)
        if rx == 0 || ry == 0 {
            segments.append(.line(to))
            return
        }
        let phi = rotation * Double.pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)
        let dx = (from.x - to.x) / 2
        let dy = (from.y - to.y) / 2
        let x1 = cosPhi * dx + sinPhi * dy
        let y1 = -sinPhi * dx + cosPhi * dy

        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 {
            let root = lambda.squareRoot()
            rx *= root
            ry *= root
        }
        let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var coefficient = (max(numerator, 0) / denominator).squareRoot()
        if largeArc == sweep { coefficient = -coefficient }
        let cxPrime = coefficient * rx * y1 / ry
        let cyPrime = -coefficient * ry * x1 / rx
        let cx = cosPhi * cxPrime - sinPhi * cyPrime + (from.x + to.x) / 2
        let cy = sinPhi * cxPrime + cosPhi * cyPrime + (from.y + to.y) / 2

        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            let value = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
            return value
        }
        let theta1 = angle(1, 0, (x1 - cxPrime) / rx, (y1 - cyPrime) / ry)
        var delta = angle(
            (x1 - cxPrime) / rx, (y1 - cyPrime) / ry,
            (-x1 - cxPrime) / rx, (-y1 - cyPrime) / ry)
        if !sweep && delta > 0 { delta -= 2 * Double.pi }
        if sweep && delta < 0 { delta += 2 * Double.pi }

        let pieces = max(1, Int((abs(delta) / (Double.pi / 2)).rounded(.up)))
        let step = delta / Double(pieces)
        let alpha = 4.0 / 3.0 * tan(step / 4)

        func pointAt(_ theta: Double) -> SVGPoint {
            let x = rx * cos(theta)
            let y = ry * sin(theta)
            return SVGPoint(cosPhi * x - sinPhi * y + cx, sinPhi * x + cosPhi * y + cy)
        }
        func derivativeAt(_ theta: Double) -> SVGPoint {
            let x = -rx * sin(theta)
            let y = ry * cos(theta)
            return SVGPoint(cosPhi * x - sinPhi * y, sinPhi * x + cosPhi * y)
        }

        var theta = theta1
        var start = from
        for piece in 0..<pieces {
            let next = theta + step
            let end = piece == pieces - 1 ? to : pointAt(next)
            let c1 = start + derivativeAt(theta) * alpha
            let c2 = end - derivativeAt(next) * alpha
            segments.append(.cubic(c1, c2, end))
            theta = next
            start = end
        }
    }
}

// MARK: - Number lists / 數字串列

/// Reads SVG numbers out of path data, `points` and transform arguments.
/// 從路徑資料、`points` 與轉換參數中讀出 SVG 數字。
struct SVGNumberScanner {
    let bytes: [UInt8]
    var index = 0

    init(_ string: String) {
        bytes = Array(string.utf8)
    }

    var isAtEnd: Bool { index >= bytes.count }

    static func isSeparator(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D || byte == UInt8(ascii: ",")
    }

    mutating func skipSeparators() {
        while index < bytes.count, Self.isSeparator(bytes[index]) {
            index += 1
        }
    }

    func peek() -> UInt8? {
        index < bytes.count ? bytes[index] : nil
    }

    /// Whether a number starts at the current position (after separators).
    /// 目前位置(略過分隔符之後)是否為一個數字的開頭。
    mutating func atNumber() -> Bool {
        skipSeparators()
        guard let byte = peek() else { return false }
        return (byte >= 0x30 && byte <= 0x39) || byte == UInt8(ascii: "-")
            || byte == UInt8(ascii: "+") || byte == UInt8(ascii: ".")
    }

    /// One number, accepting the compressed forms `1.5.5` and `-1-2`.
    /// 一個數字，接受 `1.5.5` 與 `-1-2` 這類壓縮寫法。
    mutating func number() -> Double? {
        skipSeparators()
        let start = index
        if let byte = peek(), byte == UInt8(ascii: "-") || byte == UInt8(ascii: "+") {
            index += 1
        }
        var digits = 0
        while let byte = peek(), byte >= 0x30 && byte <= 0x39 {
            index += 1
            digits += 1
        }
        if peek() == UInt8(ascii: ".") {
            index += 1
            while let byte = peek(), byte >= 0x30 && byte <= 0x39 {
                index += 1
                digits += 1
            }
        }
        guard digits > 0 else {
            index = start
            return nil
        }
        if let byte = peek(), byte == UInt8(ascii: "e") || byte == UInt8(ascii: "E") {
            let mark = index
            index += 1
            if let sign = peek(), sign == UInt8(ascii: "-") || sign == UInt8(ascii: "+") {
                index += 1
            }
            var exponentDigits = 0
            while let byte = peek(), byte >= 0x30 && byte <= 0x39 {
                index += 1
                exponentDigits += 1
            }
            if exponentDigits == 0 { index = mark }
        }
        return Double(String(decoding: bytes[start..<index], as: UTF8.self))
    }

    /// An arc flag: a single `0` or `1`, which may run into the next number.
    /// 弧的旗標：單一個 `0` 或 `1`,可能與下一個數字相連。
    mutating func flag() -> Bool? {
        skipSeparators()
        guard let byte = peek() else { return nil }
        if byte == UInt8(ascii: "0") {
            index += 1
            return false
        }
        if byte == UInt8(ascii: "1") {
            index += 1
            return true
        }
        return nil
    }

    static func numbers(in string: String) -> [Double]? {
        var scanner = SVGNumberScanner(string)
        var values: [Double] = []
        while true {
            scanner.skipSeparators()
            if scanner.isAtEnd { return values }
            guard let value = scanner.number() else { return nil }
            values.append(value)
        }
    }
}

// MARK: - Path data / 路徑資料

enum SVGPathDataParser {
    /// Parses `d`. On an error the path up to that point is kept, which is
    /// what the SVG specification asks for, and the error is returned too.
    ///
    /// 解析 `d`。遇到錯誤時保留到該處為止的路徑(這是 SVG 規格的要求),同時回傳該錯誤。
    static func parse(_ data: String) -> (path: SVGPath, error: String?) {
        var scanner = SVGNumberScanner(data)
        var path = SVGPath()
        var current = SVGPoint(0, 0)
        var subpathStart = SVGPoint(0, 0)
        var lastCubicControl: SVGPoint? = nil
        var lastQuadControl: SVGPoint? = nil
        var command: UInt8? = nil
        var needsMoveAfterClose = false

        func ensureStarted() {
            if needsMoveAfterClose {
                path.segments.append(.move(current))
                needsMoveAfterClose = false
            }
        }

        while true {
            scanner.skipSeparators()
            if scanner.isAtEnd { break }
            let byte = scanner.peek()!
            let isLetter =
                (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z"))
                || (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z"))
            if isLetter {
                command = byte
                scanner.index += 1
                if byte == UInt8(ascii: "Z") || byte == UInt8(ascii: "z") {
                    if !path.segments.isEmpty {
                        path.segments.append(.close)
                    }
                    current = subpathStart
                    needsMoveAfterClose = true
                    lastCubicControl = nil
                    lastQuadControl = nil
                    continue
                }
            } else if command == nil {
                return (path, "path data does not start with a command")
            }
            guard let active = command else { break }
            if active == UInt8(ascii: "Z") || active == UInt8(ascii: "z") {
                return (path, "numbers after Z")
            }
            let relative = active >= UInt8(ascii: "a")
            let base = relative ? current : SVGPoint(0, 0)

            func point() -> SVGPoint? {
                guard let x = scanner.number(), let y = scanner.number() else { return nil }
                return SVGPoint(base.x + x, base.y + y)
            }

            switch active | 0x20 {  // lowercase
                case UInt8(ascii: "m"):
                    guard let p = point() else { return (path, "bad moveto") }
                    path.segments.append(.move(p))
                    needsMoveAfterClose = false
                    current = p
                    subpathStart = p
                    // Further pairs are implicit linetos.
                    // 後續的座標對是隱含的 lineto。
                    command = relative ? UInt8(ascii: "l") : UInt8(ascii: "L")
                    lastCubicControl = nil
                    lastQuadControl = nil
                case UInt8(ascii: "l"):
                    guard let p = point() else { return (path, "bad lineto") }
                    ensureStarted()
                    path.segments.append(.line(p))
                    current = p
                    lastCubicControl = nil
                    lastQuadControl = nil
                case UInt8(ascii: "h"):
                    guard let x = scanner.number() else { return (path, "bad horizontal lineto") }
                    ensureStarted()
                    let p = SVGPoint(relative ? current.x + x : x, current.y)
                    path.segments.append(.line(p))
                    current = p
                    lastCubicControl = nil
                    lastQuadControl = nil
                case UInt8(ascii: "v"):
                    guard let y = scanner.number() else { return (path, "bad vertical lineto") }
                    ensureStarted()
                    let p = SVGPoint(current.x, relative ? current.y + y : y)
                    path.segments.append(.line(p))
                    current = p
                    lastCubicControl = nil
                    lastQuadControl = nil
                case UInt8(ascii: "c"):
                    guard let c1 = point(), let c2 = point(), let p = point() else {
                        return (path, "bad curveto")
                    }
                    ensureStarted()
                    path.segments.append(.cubic(c1, c2, p))
                    current = p
                    lastCubicControl = c2
                    lastQuadControl = nil
                case UInt8(ascii: "s"):
                    guard let c2 = point(), let p = point() else {
                        return (path, "bad smooth curveto")
                    }
                    ensureStarted()
                    let c1 = lastCubicControl.map { current * 2 - $0 } ?? current
                    path.segments.append(.cubic(c1, c2, p))
                    current = p
                    lastCubicControl = c2
                    lastQuadControl = nil
                case UInt8(ascii: "q"):
                    guard let c1 = point(), let p = point() else {
                        return (path, "bad quadratic curveto")
                    }
                    ensureStarted()
                    path.segments.append(.quad(c1, p))
                    current = p
                    lastQuadControl = c1
                    lastCubicControl = nil
                case UInt8(ascii: "t"):
                    guard let p = point() else { return (path, "bad smooth quadratic curveto") }
                    ensureStarted()
                    let c1 = lastQuadControl.map { current * 2 - $0 } ?? current
                    path.segments.append(.quad(c1, p))
                    current = p
                    lastQuadControl = c1
                    lastCubicControl = nil
                case UInt8(ascii: "a"):
                    guard let rx = scanner.number(), let ry = scanner.number(),
                        let rotation = scanner.number(), let large = scanner.flag(),
                        let sweep = scanner.flag(), let p = point()
                    else {
                        return (path, "bad elliptical arc")
                    }
                    ensureStarted()
                    path.appendArc(
                        from: current, to: p, rx: rx, ry: ry, rotation: rotation,
                        largeArc: large, sweep: sweep)
                    current = p
                    lastCubicControl = nil
                    lastQuadControl = nil
                default:
                    return (path, "unknown path command '\(Character(Unicode.Scalar(active)))'")
            }
        }
        return (path, nil)
    }
}

// MARK: - Transform lists / 轉換串列

enum SVGTransformParser {
    /// Parses a `transform` attribute. `nil` means it could not be read; the
    /// caller reports that and uses the identity.
    ///
    /// 解析 `transform` 屬性。`nil` 表示無法讀取；呼叫端會回報並改用單位矩陣。
    static func parse(_ string: String) -> SVGTransform? {
        var result = SVGTransform.identity
        var rest = Substring(string)
        while true {
            rest = rest.drop(while: { $0.isWhitespace || $0 == "," })
            if rest.isEmpty { return result }
            guard let open = rest.firstIndex(of: "("),
                let close = rest[open...].firstIndex(of: ")")
            else { return nil }
            let name = rest[..<open].trimmingCharacters(in: .whitespaces)
            guard let values = SVGNumberScanner.numbers(in: String(rest[rest.index(after: open)..<close]))
            else { return nil }
            let next: SVGTransform
            switch (name, values.count) {
                case ("matrix", 6):
                    next = SVGTransform(
                        a: values[0], b: values[1], c: values[2], d: values[3], e: values[4],
                        f: values[5])
                case ("translate", 1):
                    next = .translate(values[0], 0)
                case ("translate", 2):
                    next = .translate(values[0], values[1])
                case ("scale", 1):
                    next = .scale(values[0], values[0])
                case ("scale", 2):
                    next = .scale(values[0], values[1])
                case ("rotate", 1):
                    next = .rotate(degrees: values[0])
                case ("rotate", 3):
                    next = SVGTransform.translate(values[1], values[2])
                        .concatenating(.rotate(degrees: values[0]))
                        .concatenating(.translate(-values[1], -values[2]))
                case ("skewX", 1):
                    next = SVGTransform(a: 1, b: 0, c: tan(values[0] * Double.pi / 180), d: 1, e: 0, f: 0)
                case ("skewY", 1):
                    next = SVGTransform(a: 1, b: tan(values[0] * Double.pi / 180), c: 0, d: 1, e: 0, f: 0)
                default:
                    return nil
            }
            result = result.concatenating(next)
            rest = rest[rest.index(after: close)...]
        }
    }
}
