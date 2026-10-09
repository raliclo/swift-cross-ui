import Foundation
import ImageFormats
import Testing

@testable import SwiftCrossUI

/// `marker-start`, `marker-mid`, `marker-end` (2026-10-10).
/// `marker-start`、`marker-mid`、`marker-end`(2026-10-10)。
@Suite("SVG markers")
struct SVGMarkerTests {
    func svg(_ width: Int, _ height: Int, _ body: String) -> String {
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(width)\" height=\"\(height)\">\(body)</svg>"
    }

    func document(_ width: Int, _ height: Int, _ body: String) throws -> SVGDocument {
        try SVGDocument(string: svg(width, height, body))
    }

    func render(_ width: Int, _ height: Int, _ body: String) throws -> ImageFormats.Image<RGBA> {
        try document(width, height, body).rasterize(
            width: width, height: height, showsUnsupportedMarkers: false)
    }

    func pixel(_ image: ImageFormats.Image<RGBA>, _ x: Int, _ y: Int) -> [Int] {
        let index = (y * image.width + x) * 4
        return image.bytes[index..<(index + 4)].map(Int.init)
    }

    let red = [255, 0, 0, 255]

    /// A 4x4 red square centred on its vertex, in user units.
    /// 以頂點為中心、使用者單位的 4x4 紅色方塊。
    let dot =
        #"<marker id="m" markerUnits="userSpaceOnUse" markerWidth="4" markerHeight="4" refX="2" refY="2"><rect width="4" height="4" fill="red"/></marker>"#

    /// A 6x2 red bar from its vertex along the marker's +x, for orientation.
    /// 從頂點沿標記 +x 方向的 6x2 紅色長條，用來看方向。
    func bar(_ orient: String) -> String {
        #"<marker id="b" markerUnits="userSpaceOnUse" markerWidth="6" markerHeight="2" refY="1" orient="\#(orient)"><rect width="6" height="2" fill="red"/></marker>"#
    }

    @Test("Vertices and their directions, curves by their end tangents")
    func vertices() {
        let (path, _) = SVGPathDataParser.parse("M0 0 L10 0 C10 5 5 10 0 10 Z")
        let vertices = SVGBuilder.markerVertices(of: path)
        #expect(vertices.map(\.point) == [SVGPoint(0, 0), SVGPoint(10, 0), SVGPoint(0, 10), SVGPoint(0, 0)])
        #expect(vertices[1].outgoing == SVGPoint(0, 5))  // toward the first control point
        #expect(vertices[2].incoming == SVGPoint(-5, 0))  // from the second control point
        // Closed: the start is entered along the closing segment, the closing vertex
        // leaves along the first. / 閉合：起點沿閉合段進入，閉合頂點沿第一段離開。
        #expect(vertices[0].incoming == SVGPoint(0, -10))
        #expect(vertices[3].outgoing == SVGPoint(10, 0))
    }

    @Test("start and end markers sit on the first and last vertex, even with no fill or stroke")
    func startAndEnd() throws {
        let image = try render(
            30, 10,
            #"\#(dot)<path d="M5 5 L15 5 L25 5" fill="none" marker-start="url(#m)" marker-end="url(#m)"/>"#)
        #expect(pixel(image, 5, 5) == red)
        #expect(pixel(image, 25, 5) == red)
        #expect(pixel(image, 15, 5)[3] == 0)  // no marker-mid
    }

    @Test("marker-mid goes on every vertex but the first and last")
    func mid() throws {
        let image = try render(
            30, 10,
            #"\#(dot)<polyline points="5,5 15,5 25,5" fill="none" marker-mid="url(#m)"/>"#)
        #expect(pixel(image, 15, 5) == red)
        #expect(pixel(image, 5, 5)[3] == 0)
        #expect(pixel(image, 25, 5)[3] == 0)
    }

    @Test("markerUnits strokeWidth scales the marker by the stroke width")
    func strokeWidthUnits() throws {
        let image = try render(
            20, 20,
            #"<marker id="m" markerWidth="3" markerHeight="3"><rect width="3" height="3" fill="red"/></marker><line x1="2" y1="2" x2="2" y2="2.001" stroke="none" stroke-width="2" marker-start="url(#m)"/>"#)
        #expect(pixel(image, 6, 6) == red)  // 3 x 2 = 6 units from the vertex
        #expect(pixel(image, 9, 9)[3] == 0)
    }

    @Test("orient auto turns the marker along the path; 0 leaves it")
    func orientAuto() throws {
        let auto = try render(
            20, 30, #"\#(bar("auto"))<path d="M10 0 L10 20" fill="none" marker-end="url(#b)"/>"#)
        #expect(pixel(auto, 10, 23) == red)  // pointing down / 朝下
        #expect(pixel(auto, 14, 20)[3] == 0)
        let fixed = try render(
            20, 30, #"\#(bar("0"))<path d="M10 0 L10 20" fill="none" marker-end="url(#b)"/>"#)
        #expect(pixel(fixed, 14, 20) == red)  // pointing right / 朝右
    }

    @Test("auto-start-reverse turns the start marker around")
    func autoStartReverse() throws {
        let image = try render(
            40, 20,
            #"\#(bar("auto-start-reverse"))<path d="M10 10 L30 10" fill="none" marker-start="url(#b)" marker-end="url(#b)"/>"#)
        #expect(pixel(image, 7, 10) == red)  // start points back / 起點朝後
        #expect(pixel(image, 13, 10)[3] == 0)
        #expect(pixel(image, 33, 10) == red)  // end points forward / 終點朝前
    }

    @Test("overflow hidden clips the marker to its viewport; visible does not")
    func overflow() throws {
        func image(_ overflow: String) throws -> ImageFormats.Image<RGBA> {
            try render(
                20, 10,
                #"<marker id="m" markerUnits="userSpaceOnUse" markerWidth="4" markerHeight="4" overflow="\#(overflow)"><rect width="10" height="4" fill="red"/></marker><path d="M2 2 L2.001 2" fill="none" marker-start="url(#m)"/>"#)
        }
        #expect(pixel(try image("hidden"), 4, 3) == red)
        #expect(pixel(try image("hidden"), 9, 3)[3] == 0)
        #expect(pixel(try image("visible"), 9, 3) == red)
    }

    @Test("A viewBox scales the content; refX is in viewBox units")
    func viewBox() throws {
        let image = try render(
            20, 20,
            #"<marker id="m" markerUnits="userSpaceOnUse" markerWidth="8" markerHeight="8" viewBox="0 0 1 1" refX="0.5" refY="0.5"><rect width="1" height="1" fill="red"/></marker><path d="M10 10 L10.001 10" fill="none" marker-start="url(#m)"/>"#)
        #expect(pixel(image, 7, 7) == red)
        #expect(pixel(image, 13, 13) == red)
        #expect(pixel(image, 4, 10)[3] == 0)
    }

    @Test("Working markers are not reported; a broken reference is")
    func diagnostics() throws {
        let clean = try document(
            30, 10, #"\#(dot)<path d="M5 5 L25 5" stroke="black" marker-end="url(#m)"/>"#)
        #expect(clean.diagnostics.isEmpty)
        let broken = try document(
            30, 10, #"<path d="M5 5 L25 5" stroke="black" marker-end="url(#none)"/>"#)
        #expect(broken.diagnostics.map(\.description).contains { $0.contains("marker url(#none)") })
    }
}
