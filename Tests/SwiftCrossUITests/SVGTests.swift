import Foundation
import ImageFormats
import Testing

@_spi(Backends) @testable import SwiftCrossUI

/// The pure-Swift SVG renderer behind `Image` for `.svg` files (2026-10-09).
///
/// Two layers. Unit tests pin geometry to pixel coverage -- a known shape must
/// cover a known area, with the right pixels partly covered -- so each part
/// (fill rules, transforms, arcs, strokes, dashes, colours, CSS) is checked on
/// its own. Golden tests compare whole KiCad exports and a feature sheet with
/// what macOS's CoreSVG draws (`Scripts/svg_golden.zsh`).
///
/// 支撐 `Image` 處理 `.svg` 檔的純 Swift SVG 算繪器(2026-10-09)。
///
/// 兩層。單元測試把幾何釘在像素覆蓋率上——已知形狀必須覆蓋已知面積，且正確的像素被部分覆蓋——因此
/// 每一部分(填充規則、轉換、弧、描邊、虛線、顏色、CSS)各自受檢。黃金測試把整份 KiCad 匯出檔與
/// 功能表，和 macOS 的 CoreSVG 所畫的結果比較(`Scripts/svg_golden.zsh`)。
@Suite("SVG rendering")
struct SVGTests {
    // MARK: Helpers / 輔助

    private func render(_ source: String, width: Int, height: Int) throws -> ImageFormats.Image<RGBA> {
        try SVGDocument(string: source).rasterize(width: width, height: height)
    }

    /// Alpha of every pixel, 0...1.
    private func alphas(_ image: ImageFormats.Image<RGBA>) -> [Double] {
        stride(from: 3, to: image.bytes.count, by: 4).map { Double(image.bytes[$0]) / 255 }
    }

    private func alpha(_ image: ImageFormats.Image<RGBA>, _ x: Int, _ y: Int) -> Double {
        Double(image.bytes[(y * image.width + x) * 4 + 3]) / 255
    }

    private func pixel(_ image: ImageFormats.Image<RGBA>, _ x: Int, _ y: Int) -> [Int] {
        let index = (y * image.width + x) * 4
        return (0..<4).map { Int(image.bytes[index + $0]) }
    }

    /// Covered area in pixels.
    private func area(_ image: ImageFormats.Image<RGBA>) -> Double {
        alphas(image).reduce(0, +)
    }

    private func svg(_ width: Int, _ height: Int, _ body: String) -> String {
        """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(width)" height="\(height)" \
        viewBox="0 0 \(width) \(height)">\(body)</svg>
        """
    }

    // MARK: Coverage / 覆蓋率

    @Test("A rectangle covers its area, with fractional edges")
    func rectangleCoverage() throws {
        let image = try render(
            svg(10, 10, #"<rect x="2.25" y="3.5" width="4" height="2" fill="black"/>"#),
            width: 10, height: 10)
        #expect(abs(area(image) - 8) < 0.05)
        #expect(abs(alpha(image, 2, 4) - 0.75) < 0.01)  // left edge, x 2.25..3
        #expect(abs(alpha(image, 4, 3) - 0.5) < 0.04)  // top edge, y 3.5..4
        #expect(alpha(image, 4, 4) == 1)
        #expect(abs(alpha(image, 6, 3) - 0.125) < 0.04)  // corner: 0.25 x 0.5
        #expect(alpha(image, 7, 4) == 0)
    }

    @Test("nonzero fills a same-direction inner square; evenodd leaves a hole")
    func fillRules() throws {
        let rings = "M1 1 h8 v8 h-8 Z M3 3 h4 v4 h-4 Z"
        let nonzero = try render(
            svg(10, 10, #"<path d="\#(rings)" fill-rule="nonzero"/>"#), width: 10, height: 10)
        let evenodd = try render(
            svg(10, 10, #"<path d="\#(rings)" fill-rule="evenodd"/>"#), width: 10, height: 10)
        #expect(alpha(nonzero, 5, 5) == 1)
        #expect(alpha(evenodd, 5, 5) == 0)
        #expect(abs(area(nonzero) - 64) < 0.1)
        #expect(abs(area(evenodd) - 48) < 0.1)
        // An opposite-direction inner square is a hole under nonzero too.
        // 反方向的內方形在 nonzero 下也是洞。
        let reversed = try render(
            svg(10, 10, #"<path d="M1 1 h8 v8 h-8 Z M3 3 v4 h4 v-4 Z"/>"#), width: 10, height: 10)
        #expect(alpha(reversed, 5, 5) == 0)
    }

    @Test("A self-intersecting star: evenodd leaves the centre empty, nonzero fills it")
    func starFillRules() throws {
        let points = "50,5 79,95 2,40 98,40 21,95"
        let evenodd = try render(
            svg(100, 100, #"<polygon points="\#(points)" fill-rule="evenodd"/>"#), width: 100, height: 100)
        let nonzero = try render(
            svg(100, 100, #"<polygon points="\#(points)"/>"#), width: 100, height: 100)
        #expect(alpha(evenodd, 50, 55) == 0)
        #expect(alpha(nonzero, 50, 55) == 1)
    }

    // MARK: Transforms / 轉換

    @Test("Transform lists apply right to left")
    func transformParsing() throws {
        let t = try #require(SVGTransformParser.parse("translate(10 0) scale(2)"))
        #expect(t.apply(SVGPoint(1, 1)) == SVGPoint(12, 2))
        let r = try #require(SVGTransformParser.parse("rotate(90, 5, 5)"))
        let p = r.apply(SVGPoint(10, 5))
        #expect(abs(p.x - 5) < 1e-9 && abs(p.y - 10) < 1e-9)
        let skew = try #require(SVGTransformParser.parse("skewX(45)"))
        let q = skew.apply(SVGPoint(0, 2))
        #expect(abs(q.x - 2) < 1e-9 && q.y == 2)
        let m = try #require(SVGTransformParser.parse("matrix(1,2,3,4,5,6)"))
        #expect(m.apply(SVGPoint(1, 1)) == SVGPoint(9, 12))
        #expect(SVGTransformParser.parse("rotate(1 2)") == nil)
    }

    @Test("A rotated, scaled rectangle lands on the transformed pixels")
    func transformedRectangle() throws {
        // A 2x4 rect rotated 90 degrees about the origin then moved: it becomes 4 wide, 2 high.
        let image = try render(
            svg(10, 10, #"<rect width="2" height="4" transform="translate(6 1) rotate(90)"/>"#),
            width: 10, height: 10)
        #expect(abs(area(image) - 8) < 0.05)
        #expect(alpha(image, 3, 1) == 1)  // x 2..6, y 1..3
        #expect(alpha(image, 3, 4) == 0)
        let scaled = try render(
            svg(10, 10, #"<g transform="scale(2 0.5)"><rect width="2" height="8"/></g>"#),
            width: 10, height: 10)
        #expect(abs(area(scaled) - 16) < 0.05)
        #expect(alpha(scaled, 3, 3) == 1)
        #expect(alpha(scaled, 3, 5) == 0)
    }

    @Test("viewBox and mm units: 160mm x 100mm is 604.7 x 377.95 CSS px")
    func unitsAndViewBox() throws {
        let document = try SVGDocument(
            string: #"<svg xmlns="http://www.w3.org/2000/svg" width="160mm" height="100mm" viewBox="0 0 16 10"><rect x="8" width="8" height="5"/></svg>"#
        )
        #expect(abs(document.width - 160 * 96 / 25.4) < 1e-9)
        #expect(abs(document.height - 100 * 96 / 25.4) < 1e-9)
        let image = document.rasterize(width: 32, height: 20)
        #expect(abs(area(image) - 16 * 10) < 0.1)
        #expect(alpha(image, 20, 5) == 1)
        #expect(alpha(image, 10, 5) == 0)
    }

    @Test("preserveAspectRatio meets and centres by default, stretches with none")
    func aspectRatio() throws {
        let body = #"<rect width="10" height="10"/>"#
        let meet = try render(svg(10, 10, body), width: 20, height: 10)
        #expect(alpha(meet, 2, 5) == 0)  // letterboxed: x 5..15
        #expect(alpha(meet, 10, 5) == 1)
        let none = try render(
            #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10" preserveAspectRatio="none">\#(body)</svg>"#,
            width: 20, height: 10)
        #expect(abs(area(none) - 200) < 0.1)
    }

    // MARK: Path data and arcs / 路徑資料與弧

    @Test("Compressed numbers, implicit linetos and relative commands")
    func pathDataSyntax() throws {
        let (path, error) = SVGPathDataParser.parse("M0,0L10-5.5.5.5l1e1 0h-1v1z m1 1 2 2")
        #expect(error == nil)
        #expect(path.segments[1] == .line(SVGPoint(10, -5.5)))
        #expect(path.segments[2] == .line(SVGPoint(0.5, 0.5)))  // ".5.5" is two numbers
        #expect(path.segments[3] == .line(SVGPoint(10.5, 0.5)))
        #expect(path.segments[5] == .line(SVGPoint(9.5, 1.5)))
        #expect(path.segments[6] == .close)
        // After z the current point is the subpath start (0,0); m is relative to it.
        #expect(path.segments[7] == .move(SVGPoint(1, 1)))
        #expect(path.segments[8] == .line(SVGPoint(3, 3)))
        let (_, bad) = SVGPathDataParser.parse("M0 0 L10")
        #expect(bad != nil)
    }

    @Test("S and T reflect the previous control point")
    func smoothCurves() throws {
        let (path, _) = SVGPathDataParser.parse("M0 0 C1 1 2 1 3 0 S5 -1 6 0 Q7 1 8 0 T10 0")
        #expect(path.segments[2] == .cubic(SVGPoint(4, -1), SVGPoint(5, -1), SVGPoint(6, 0)))
        #expect(path.segments[4] == .quad(SVGPoint(9, -1), SVGPoint(10, 0)))
    }

    @Test("Arcs: a half disc has half a circle's area, flags may run together")
    func arcs() throws {
        // Upper half disc of radius 20 centred at (25, 25).
        let half = try render(
            svg(50, 50, #"<path d="M5 25 A20 20 0 0 1 45 25 Z"/>"#), width: 50, height: 50)
        #expect(abs(area(half) - Double.pi * 400 / 2) < 2)
        #expect(alpha(half, 25, 10) == 1)
        #expect(alpha(half, 25, 35) == 0)
        // Same arc, compressed flags, the other sweep: the lower half.
        let lower = try render(
            svg(50, 50, #"<path d="M5 25a20 20 0 0040 0z"/>"#), width: 50, height: 50)
        #expect(alpha(lower, 25, 35) == 1)
        #expect(alpha(lower, 25, 10) == 0)
        // Radii too small are scaled up (F.6.6): still a half disc of radius 20.
        let small = try render(
            svg(50, 50, #"<path d="M5 25 A1 1 0 0 1 45 25 Z"/>"#), width: 50, height: 50)
        #expect(abs(area(small) - Double.pi * 400 / 2) < 2)
        // The large-arc flag picks the long way round.
        // From the bottom to the right of the circle about (25, 25): three quarters plus the
        // triangle the closing chord adds.
        let large = try render(
            svg(50, 50, #"<path d="M25 45 A20 20 0 1 1 45 25 Z"/>"#), width: 50, height: 50)
        #expect(abs(area(large) - (Double.pi * 400 * 0.75 + 200)) < 3)
    }

    @Test("Circles, ellipses and rounded rectangles")
    func basicShapes() throws {
        let circle = try render(svg(40, 40, #"<circle cx="20" cy="20" r="15"/>"#), width: 40, height: 40)
        #expect(abs(area(circle) - Double.pi * 225) < 2)
        let ellipse = try render(
            svg(40, 40, #"<ellipse cx="20" cy="20" rx="15" ry="5"/>"#), width: 40, height: 40)
        #expect(abs(area(ellipse) - Double.pi * 75) < 1)
        // rx alone sets ry too; the corners lose (4 - pi) r^2.
        let rounded = try render(
            svg(40, 40, #"<rect x="5" y="5" width="30" height="20" rx="5"/>"#), width: 40, height: 40)
        #expect(abs(area(rounded) - (600 - (4 - Double.pi) * 25)) < 1)
        #expect(alpha(rounded, 5, 5) == 0)
    }

    // MARK: Strokes / 描邊

    @Test("Caps: butt adds nothing, square adds a half-width box, round a half disc at each end")
    func lineCaps() throws {
        func strokeArea(_ cap: String) throws -> Double {
            try area(
                render(
                    svg(40, 20, #"<line x1="10" y1="10" x2="30" y2="10" stroke="black" stroke-width="4" stroke-linecap="\#(cap)"/>"#),
                    width: 40, height: 20))
        }
        #expect(abs(try strokeArea("butt") - 80) < 0.2)
        #expect(abs(try strokeArea("square") - 96) < 0.2)
        #expect(abs(try strokeArea("round") - (80 + Double.pi * 4)) < 0.3)
    }

    @Test("Joins: a right-angle miter fills the corner square; bevel cuts it in half")
    func lineJoins() throws {
        func joinArea(_ join: String) throws -> Double {
            try area(
                render(
                    svg(40, 40, #"<polyline points="10,30 10,10 30,10" fill="none" stroke="black" stroke-width="4" stroke-linejoin="\#(join)"/>"#),
                    width: 40, height: 40))
        }
        // Two 20x4 rectangles overlap in a 2x2 square; the outer corner adds 2x2 (miter), half (bevel),
        // a quarter disc (round).
        let base = 80 + 80 - 4.0
        #expect(abs(try joinArea("miter") - (base + 4)) < 0.3)
        #expect(abs(try joinArea("bevel") - (base + 2)) < 0.3)
        #expect(abs(try joinArea("round") - (base + Double.pi)) < 0.3)
        // A sharp turn beyond stroke-miterlimit falls back to bevel.
        // 超過 stroke-miterlimit 的銳角改為斜切。
        let sharp = #"<polyline points="5,35 20,5 35,35" fill="none" stroke="black" stroke-width="4" stroke-linejoin="miter" stroke-miterlimit="\#("LIMIT")"/>"#
        let limited = try area(render(svg(40, 40, sharp.replacingOccurrences(of: "LIMIT", with: "1")), width: 40, height: 40))
        let mitered = try area(render(svg(40, 40, sharp.replacingOccurrences(of: "LIMIT", with: "10")), width: 40, height: 40))
        #expect(mitered > limited + 2)
    }

    @Test("A translucent stroke's own overlaps count once")
    func strokeUnion() throws {
        let image = try render(
            svg(40, 40, #"<polyline points="10,30 10,10 30,10" fill="none" stroke="black" stroke-opacity="0.5" stroke-width="4" stroke-linejoin="round"/>"#),
            width: 40, height: 40)
        #expect(abs(alpha(image, 10, 10) - 0.5) < 0.01)  // the joint, covered by three polygons
    }

    @Test("Dashes split the line; the offset shifts the pattern")
    func dashes() throws {
        let line = #"<line x1="0" y1="5" x2="20" y2="5" stroke="black" stroke-width="2" stroke-dasharray="DASH" stroke-dashoffset="OFFSET"/>"#
        func draw(_ dash: String, _ offset: String) throws -> ImageFormats.Image<RGBA> {
            try render(
                svg(20, 10, line.replacingOccurrences(of: "DASH", with: dash)
                    .replacingOccurrences(of: "OFFSET", with: offset)),
                width: 20, height: 10)
        }
        let plain = try draw("4 4", "0")
        #expect(abs(area(plain) - 24) < 0.2)  // 0-4, 8-12, 16-20
        #expect(alpha(plain, 2, 5) == 1)
        #expect(alpha(plain, 6, 5) == 0)
        let shifted = try draw("4 4", "2")
        #expect(alpha(shifted, 0, 5) == 1)  // 0-2 then 6-10 ...
        #expect(alpha(shifted, 4, 5) == 0)
        // An odd list repeats: "3" is "3 3".
        let odd = try draw("3", "0")
        #expect(abs(area(odd) - 2 * (3 + 3 + 3 + 2)) < 0.2)  // 0-3, 6-9, 12-15, 18-20
    }

    // MARK: Paint and opacity / 塗料與不透明度

    @Test("Colour syntaxes")
    func colours() throws {
        #expect(SVGColor.parse("#f80") == SVGColor(red: 1, green: 136.0 / 255, blue: 0))
        #expect(SVGColor.parse("#FF880080")?.alpha == 128.0 / 255)
        #expect(SVGColor.parse("rgb(255, 0, 0)") == SVGColor(red: 1, green: 0, blue: 0))
        #expect(SVGColor.parse("rgb(100% 50% 0% / 25%)") == SVGColor(red: 1, green: 0.5, blue: 0, alpha: 0.25))
        #expect(SVGColor.parse("darkslateblue") == SVGColor(red: 72.0 / 255, green: 61.0 / 255, blue: 139.0 / 255))
        let hsl = try #require(SVGColor.parse("hsl(120, 100%, 25%)"))
        #expect(abs(hsl.red) < 1e-9 && abs(hsl.green - 0.5) < 1e-9 && abs(hsl.blue) < 1e-9)
        #expect(SVGColor.parse("#12345") == nil)
        #expect(SVGColor.parse("notacolour") == nil)
    }

    @Test("Group opacity composites the group once; fill-opacity applies per shape")
    func groupOpacity() throws {
        let group = try render(
            svg(10, 10, #"<g opacity="0.5"><rect width="6" height="10"/><rect x="4" width="6" height="10"/></g>"#),
            width: 10, height: 10)
        #expect(abs(alpha(group, 5, 5) - 0.5) < 0.01)
        let each = try render(
            svg(10, 10, #"<rect width="6" height="10" fill-opacity="0.5"/><rect x="4" width="6" height="10" fill-opacity="0.5"/>"#),
            width: 10, height: 10)
        #expect(abs(alpha(each, 5, 5) - 0.75) < 0.01)
    }

    @Test("Translucent output is straight alpha")
    func straightAlpha() throws {
        let image = try render(
            svg(4, 4, ##"<rect width="4" height="4" fill="#c83434" fill-opacity="0.5"/>"##), width: 4, height: 4)
        #expect(pixel(image, 1, 1) == [200, 52, 52, 128])
    }

    @Test("CSS: type, class, compound and id selectors; style attribute wins")
    func styleSheets() throws {
        let source = svg(
            40, 10,
            #"""
            <style>
              rect { fill: blue }
              .red { fill: #ff0000 }
              rect.green { fill: lime }
              #last { fill: yellow }
            </style>
            <rect x="0" width="10" height="10"/>
            <rect x="10" width="10" height="10" class="red" fill="black"/>
            <rect x="20" width="10" height="10" class="red green"/>
            <rect x="30" width="10" height="10" id="last" class="green" style="fill: white"/>
            """#)
        let image = try render(source, width: 40, height: 10)
        #expect(pixel(image, 5, 5) == [0, 0, 255, 255])
        #expect(pixel(image, 15, 5) == [255, 0, 0, 255])  // CSS beats the presentation attribute
        #expect(pixel(image, 25, 5) == [0, 255, 0, 255])
        #expect(pixel(image, 35, 5) == [255, 255, 255, 255])
    }

    @Test("currentColor, inheritance and use")
    func currentColorAndUse() throws {
        let image = try render(
            svg(20, 10,
                ##"<defs><rect id="r" width="10" height="10"/></defs><g color="#0000ff" fill="currentColor"><use href="#r"/><use xlink:href="#r" x="10" style="color: lime"/></g>"##),
            width: 20, height: 10)
        #expect(pixel(image, 5, 5) == [0, 0, 255, 255])
        #expect(pixel(image, 15, 5) == [0, 255, 0, 255])
    }

    @Test("display none and visibility hidden draw nothing and report nothing")
    func hidden() throws {
        let document = try SVGDocument(
            string: svg(10, 10, #"<rect width="10" height="10" display="none"/><rect width="10" height="10" visibility="hidden"/>"#))
        #expect(area(document.rasterize(width: 10, height: 10)) == 0)
        #expect(document.diagnostics.isEmpty)
    }

    // MARK: Diagnostics / 診斷

    @Test("Everything unsupported is listed, and outlined in magenta")
    func diagnosticsAreReported() throws {
        let document = try SVGDocument(contentsOf: fixture("unsupported.svg"))
        let details = document.diagnostics.map(\.description)
        #expect(details.contains { $0.contains("linearGradient") && !$0.contains("fallback") })
        #expect(details.contains { $0.contains("linearGradient") && $0.contains("fallback colour used") })
        #expect(details.contains { $0.contains("clip-path") })
        #expect(details.contains { $0.contains("filter") })
        #expect(details.contains { $0.contains("text 'Hello SVG'") })
        #expect(details.contains { $0.contains("<image>") })
        #expect(!details.contains { $0.contains("hidden") })  // opacity="0" text is not a gap
        #expect(document.diagnostics.count == 6)

        let image = document.rasterize(width: 320, height: 200)
        #expect(pixel(image, 1, 1) == [255, 0, 255, 255])  // corner flag
        #expect(pixel(image, 120, 30) == [255, 0, 255, 255])  // gradient without fallback
        #expect(pixel(image, 10, 175) == [255, 0, 255, 255])  // <image> outline, left edge
        let clean = document.rasterize(width: 320, height: 200, showsUnsupportedMarkers: false)
        #expect(pixel(clean, 1, 1)[3] == 0)
    }

    @Test("KiCad exports need nothing unsupported: their text is invisible plus stroked paths")
    func kicadHasNoDiagnostics() throws {
        for name in ["softpcb_microstrip", "softpcb_spiral", "softpcb_meander"] {
            let document = try SVGDocument(contentsOf: fixture("\(name).svg"))
            #expect(document.diagnostics.isEmpty, "\(name): \(document.diagnostics)")
            #expect(abs(document.width - 79.9846 * 96 / 25.4) < 0.01)
        }
    }

    @Test("Malformed files throw instead of drawing half a picture")
    func malformed() {
        #expect(throws: SVGParseError.self) { try SVGDocument(string: "<svg><g></svg>") }
        #expect(throws: SVGParseError.self) { try SVGDocument(string: "<html></html>") }
        #expect(throws: SVGParseError.self) { try SVGDocument(string: "<svg width='1") }
        #expect(SVGDocument.unreadable(SVGParseError(offset: 0, message: "x")).diagnostics.count == 1)
    }

    @Test("Sniffing: SVG text yes, PNG no")
    func sniffing() {
        #expect(SVGDocument.looksLikeSVG(Array("<?xml version='1.0'?>\n<!-- x -->\n<svg/>".utf8)))
        #expect(SVGDocument.looksLikeSVG(Array("  <svg xmlns='http://www.w3.org/2000/svg'/>".utf8)))
        #expect(!SVGDocument.looksLikeSVG([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
        #expect(!SVGDocument.looksLikeSVG(Array("<?xml version='1.0'?><html/>".utf8)))
    }

    @Test("Premultiplying for backends that read premultiplied pixels")
    func premultiply() {
        #expect(ImagePixels.premultiplied([200, 0, 0, 128]) == [100, 0, 0, 128])
        #expect(ImagePixels.premultiplied([9, 9, 9, 0, 255, 255, 255, 255]) == [0, 0, 0, 0, 255, 255, 255, 255])
        let opaque: [UInt8] = [1, 2, 3, 255]
        #expect(ImagePixels.premultiplied(opaque) == opaque)
    }

    // MARK: Golden images / 黃金影像

    private func fixture(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("SVGFixtures").appendingPathComponent(name)
    }

    /// Per-pixel comparison in premultiplied space (so that colour under
    /// zero alpha does not count), on 0...255.
    struct Difference {
        var maximum: Double
        var mean: Double
        /// Fraction of pixels whose largest channel difference exceeds 16.
        var over16: Double
    }

    static func difference(_ a: ImageFormats.Image<RGBA>, _ b: ImageFormats.Image<RGBA>) -> Difference {
        precondition(a.width == b.width && a.height == b.height)
        var maximum = 0.0
        var total = 0.0
        var over = 0
        for pixel in 0..<(a.width * a.height) {
            let index = pixel * 4
            let alphaA = Double(a.bytes[index + 3]) / 255
            let alphaB = Double(b.bytes[index + 3]) / 255
            var largest = 0.0
            for channel in 0..<4 {
                let va = channel == 3 ? alphaA * 255 : Double(a.bytes[index + channel]) * alphaA
                let vb = channel == 3 ? alphaB * 255 : Double(b.bytes[index + channel]) * alphaB
                let d = abs(va - vb)
                largest = max(largest, d)
                total += d
            }
            maximum = max(maximum, largest)
            if largest > 16 { over += 1 }
        }
        let pixels = Double(a.width * a.height)
        return Difference(maximum: maximum, mean: total / (pixels * 4), over16: Double(over) / pixels)
    }

    /// Tolerance against CoreSVG, measured 2026-10-09 before it was written
    /// down (curve tolerance 0.025 px): the KiCad exports gave maximum 14,
    /// mean 0.06-0.07, no pixel over 16; the feature sheet maximum 64, mean
    /// 0.11, 0.05% of pixels over 16. The differences are anti-aliasing policy
    /// at edges (CoreGraphics snaps thin strokes to the pixel grid; this
    /// renderer does not), not geometry: a wrong shape or colour moves whole
    /// areas and fails all three bounds.
    ///
    /// 對 CoreSVG 的容差，於寫下之前實測(2026-10-09,曲線容差 0.025 px):KiCad 匯出檔最大 14、
    /// 平均 0.06-0.07、沒有像素超過 16;功能表最大 64、平均 0.11、超過 16 的像素 0.05%。差異來自
    /// 邊緣的抗鋸齒策略(CoreGraphics 會把細描邊對齊像素格，本算繪器不會),不是幾何：形狀或顏色錯誤
    /// 會移動整片區域，三項界限都會失敗。
    static let goldenMaximum = 96.0
    static let goldenMean = 0.5
    static let goldenOver16 = 0.005

    @Test(
        "Golden: matches CoreSVG within tolerance",
        arguments: ["softpcb_microstrip", "softpcb_spiral", "softpcb_meander", "features"])
    func golden(name: String) throws {
        let document = try SVGDocument(contentsOf: fixture("\(name).svg"))
        #expect(document.diagnostics.isEmpty, "\(document.diagnostics)")
        let bytes = Array(try Data(contentsOf: fixture("\(name).reference.png")))
        let reference = try ImageFormats.Image<RGBA>.load(from: bytes, usingFileExtension: "png")
        let rendered = document.rasterize(width: reference.width, height: reference.height)
        let d = Self.difference(rendered, reference)
        #expect(d.maximum <= Self.goldenMaximum, "\(name): maximum \(d.maximum)")
        #expect(d.mean <= Self.goldenMean, "\(name): mean \(d.mean)")
        #expect(d.over16 <= Self.goldenOver16, "\(name): \(d.over16 * 100)% over 16")
    }
}
