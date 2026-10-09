import Foundation
import ImageFormats
import Testing

@testable import SwiftCrossUI

/// `<pattern>` paint (2026-10-10). / `<pattern>` 塗料(2026-10-10)。
@Suite("SVG patterns")
struct SVGPatternTests {
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
    let blue = [0, 0, 255, 255]

    @Test("userSpaceOnUse tiles repeat across the shape")
    func userSpaceTiles() throws {
        let image = try render(
            20, 20,
            #"<pattern id="p" patternUnits="userSpaceOnUse" width="10" height="10"><rect width="5" height="5" fill="red"/><rect x="5" y="5" width="5" height="5" fill="blue"/></pattern><rect width="20" height="20" fill="url(#p)"/>"#)
        #expect(pixel(image, 2, 2) == red)
        #expect(pixel(image, 7, 7) == blue)
        #expect(pixel(image, 12, 12) == red)  // the next tile / 下一個圖塊
        #expect(pixel(image, 17, 2)[3] == 0)  // the empty quarter of the next tile / 下一個圖塊的空白四分之一
        #expect(pixel(image, 17, 7) == blue)
    }

    @Test("objectBoundingBox tiles start at the shape's box")
    func boundingBoxTiles() throws {
        let image = try render(
            40, 10,
            #"<pattern id="p" width="0.5" height="1"><rect width="5" height="10" fill="red"/></pattern><rect x="10" width="20" height="10" fill="url(#p)"/>"#)
        #expect(pixel(image, 12, 5) == red)
        #expect(pixel(image, 17, 5)[3] == 0)
        #expect(pixel(image, 22, 5) == red)
        #expect(pixel(image, 5, 5)[3] == 0)  // outside the shape / 形狀之外
    }

    @Test("patternContentUnits objectBoundingBox scales the content to the box")
    func boundingBoxContent() throws {
        let image = try render(
            20, 10,
            #"<pattern id="p" width="1" height="1" patternContentUnits="objectBoundingBox"><rect width="0.25" height="1" fill="red"/></pattern><rect width="20" height="10" fill="url(#p)"/>"#)
        #expect(pixel(image, 3, 5) == red)
        #expect(pixel(image, 8, 5)[3] == 0)
    }

    @Test("A viewBox maps the content onto the tile")
    func viewBox() throws {
        let image = try render(
            20, 10,
            #"<pattern id="p" patternUnits="userSpaceOnUse" width="10" height="10" viewBox="0 0 1 1"><rect width="0.5" height="1" fill="red"/></pattern><rect width="20" height="10" fill="url(#p)"/>"#)
        #expect(pixel(image, 3, 5) == red)
        #expect(pixel(image, 7, 5)[3] == 0)
        #expect(pixel(image, 13, 5) == red)
    }

    @Test("patternTransform moves the tiles")
    func patternTransform() throws {
        let image = try render(
            20, 10,
            #"<pattern id="p" patternUnits="userSpaceOnUse" width="10" height="10" patternTransform="translate(5 0)"><rect width="5" height="10" fill="red"/></pattern><rect width="20" height="10" fill="url(#p)"/>"#)
        #expect(pixel(image, 2, 5)[3] == 0)
        #expect(pixel(image, 7, 5) == red)
    }

    @Test("href: attributes and content come from the referenced pattern unless overridden")
    func inheritance() throws {
        let image = try render(
            20, 10,
            ##"<pattern id="a" patternUnits="userSpaceOnUse" width="10" height="10"><rect width="5" height="10" fill="red"/></pattern><pattern id="b" href="#a" width="20"/><rect width="20" height="10" fill="url(#b)"/>"##)
        #expect(pixel(image, 2, 5) == red)
        #expect(pixel(image, 12, 5)[3] == 0)  // width 20 overridden: no second tile at 10
    }

    @Test("fill-opacity applies on top of the tile")
    func opacity() throws {
        let image = try render(
            10, 10,
            #"<pattern id="p" patternUnits="userSpaceOnUse" width="10" height="10"><rect width="10" height="10" fill="red"/></pattern><rect width="10" height="10" fill="url(#p)" fill-opacity="0.5"/>"#)
        #expect(abs(pixel(image, 5, 5)[3] - 128) <= 1)
        #expect(pixel(image, 5, 5)[0] == 255)
    }

    @Test("An empty or zero-sized pattern paints nothing, and a working one is not reported")
    func emptyAndClean() throws {
        let empty = try render(
            10, 10,
            #"<pattern id="p" width="0" height="1"><rect width="10" height="10" fill="red"/></pattern><rect width="10" height="10" fill="url(#p)"/>"#)
        #expect(pixel(empty, 5, 5)[3] == 0)
        let clean = try document(
            10, 10,
            #"<pattern id="p" width="1" height="1"><rect width="10" height="10" fill="red"/></pattern><rect width="10" height="10" fill="url(#p)"/>"#)
        #expect(clean.diagnostics.isEmpty)
    }

    @Test("A pattern that paints with itself is reported, not followed forever")
    func selfReference() throws {
        let document = try document(
            10, 10,
            #"<pattern id="p" patternUnits="userSpaceOnUse" width="10" height="10"><rect width="10" height="10" fill="url(#p)"/></pattern><rect width="10" height="10" fill="url(#p)"/>"#)
        #expect(document.diagnostics.map(\.description).contains { $0.contains("refers to itself") })
    }
}
