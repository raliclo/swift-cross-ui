import Foundation
import ImageFormats
import Testing

@testable import SwiftCrossUI

/// `filter`, the common subset (2026-10-10). / `filter` 常用子集(2026-10-10)。
@Suite("SVG filters")
struct SVGFilterTests {
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

    func close(_ a: [Int], _ b: [Int], within tolerance: Int = 3) -> Bool {
        zip(a, b).allSatisfy { abs($0 - $1) <= tolerance }
    }

    /// A filter over the whole drawing, so the region never gets in the way.
    /// 涵蓋整張圖的濾鏡，讓區域不會干擾。
    func filter(_ primitives: String, _ extra: String = "") -> String {
        #"<filter id="f" filterUnits="userSpaceOnUse" x="0" y="0" width="100" height="100"\#(extra)>\#(primitives)</filter>"#
    }

    @Test("feOffset moves the picture by dx, dy")
    func offset() throws {
        let image = try render(
            30, 10,
            filter(#"<feOffset dx="10"/>"#) + #"<rect width="10" height="10" fill="red" filter="url(#f)"/>"#)
        #expect(pixel(image, 15, 5) == [255, 0, 0, 255])
        #expect(pixel(image, 5, 5)[3] == 0)
    }

    @Test("feFlood fills the filter region, by default 10% beyond the box")
    func floodRegion() throws {
        let image = try render(
            40, 10,
            #"<filter id="f"><feFlood flood-color="lime"/></filter><rect x="10" width="20" height="10" fill="red" filter="url(#f)"/>"#)
        #expect(pixel(image, 9, 5) == [0, 255, 0, 255])  // x 8 to 32 / x 從 8 到 32
        #expect(pixel(image, 5, 5)[3] == 0)
        #expect(pixel(image, 35, 5)[3] == 0)
    }

    @Test("feGaussianBlur spreads the edge and keeps the middle")
    func blur() throws {
        let image = try render(
            30, 30,
            filter(#"<feGaussianBlur stdDeviation="2"/>"#)
                + #"<rect x="10" y="10" width="10" height="10" fill="red" filter="url(#f)"/>"#)
        #expect(pixel(image, 15, 15)[3] > 225)
        #expect((80...180).contains(pixel(image, 10, 15)[3]))  // the edge, about half / 邊緣約一半
        #expect(pixel(image, 7, 15)[3] > 0)  // spread outside / 擴散到外面
        #expect(pixel(image, 1, 15)[3] == 0)
    }

    @Test("feColorMatrix saturate 0 greys red: in linearRGB by default, sRGB on request")
    func colorSpaces() throws {
        let body = #"<rect width="10" height="10" fill="red" filter="url(#f)"/>"#
        let primitive = #"<feColorMatrix type="saturate" values="0"/>"#
        let linear = try render(10, 10, filter(primitive) + body)
        let srgb = try render(
            10, 10, filter(primitive, #" color-interpolation-filters="sRGB""#) + body)
        // linear 0.213 -> sRGB 127; sRGB 0.213 -> 54.
        #expect(close(pixel(linear, 5, 5), [127, 127, 127, 255]))
        #expect(close(pixel(srgb, 5, 5), [54, 54, 54, 255]))
    }

    @Test("feColorMatrix matrix and luminanceToAlpha")
    func matrices() throws {
        let swap = try render(
            10, 10,
            filter(#"<feColorMatrix values="0 0 1 0 0  0 1 0 0 0  1 0 0 0 0  0 0 0 1 0"/>"#)
                + #"<rect width="10" height="10" fill="red" filter="url(#f)"/>"#)
        #expect(pixel(swap, 5, 5) == [0, 0, 255, 255])
        let luminance = try render(
            10, 10,
            filter(#"<feColorMatrix type="luminanceToAlpha"/>"#)
                + #"<rect width="10" height="10" fill="white" filter="url(#f)"/>"#)
        #expect(pixel(luminance, 5, 5)[3] == 255)
        #expect(pixel(luminance, 5, 5)[0] == 0)
    }

    @Test("feComposite in, and arithmetic")
    func composite() throws {
        let inside = try render(
            20, 10,
            filter(#"<feFlood flood-color="blue"/><feComposite in2="SourceGraphic" operator="in"/>"#)
                + #"<rect width="10" height="10" fill="red" filter="url(#f)"/>"#)
        #expect(pixel(inside, 5, 5) == [0, 0, 255, 255])
        #expect(pixel(inside, 15, 5)[3] == 0)
        let half = try render(
            10, 10,
            filter(#"<feComposite in="SourceGraphic" in2="SourceGraphic" operator="arithmetic" k2="0.5"/>"#, #" color-interpolation-filters="sRGB""#)
                + #"<rect width="10" height="10" fill="red" filter="url(#f)"/>"#)
        #expect(abs(pixel(half, 5, 5)[3] - 128) <= 1)
    }

    @Test("feMerge, result names and SourceAlpha")
    func merge() throws {
        let image = try render(
            30, 10,
            filter(
                #"<feOffset in="SourceAlpha" dx="10" result="moved"/><feMerge><feMergeNode in="moved"/><feMergeNode in="SourceGraphic"/></feMerge>"#)
                + #"<rect width="10" height="10" fill="red" filter="url(#f)"/>"#)
        #expect(pixel(image, 5, 5) == [255, 0, 0, 255])
        #expect(pixel(image, 15, 5) == [0, 0, 0, 255])  // the alpha copy is black / alpha 複本為黑
    }

    @Test("feBlend multiply with white leaves the colour")
    func blend() throws {
        let image = try render(
            10, 10,
            filter(#"<feFlood flood-color="white" result="w"/><feBlend in="SourceGraphic" in2="w" mode="multiply"/>"#)
                + #"<rect width="10" height="10" fill="red" filter="url(#f)"/>"#)
        #expect(pixel(image, 5, 5) == [255, 0, 0, 255])
    }

    @Test("feDropShadow puts a shadow under the picture")
    func dropShadow() throws {
        let image = try render(
            30, 30,
            filter(#"<feDropShadow dx="6" dy="6" stdDeviation="0" flood-color="black"/>"#)
                + #"<rect x="5" y="5" width="10" height="10" fill="red" filter="url(#f)"/>"#)
        #expect(pixel(image, 8, 8) == [255, 0, 0, 255])
        #expect(pixel(image, 18, 18) == [0, 0, 0, 255])
        #expect(pixel(image, 25, 25)[3] == 0)
    }

    @Test("feComponentTransfer: a linear green function turns red to yellow")
    func componentTransfer() throws {
        let image = try render(
            10, 10,
            filter(#"<feComponentTransfer><feFuncG type="linear" slope="0" intercept="1"/></feComponentTransfer>"#)
                + #"<rect width="10" height="10" fill="red" filter="url(#f)"/>"#)
        #expect(pixel(image, 5, 5) == [255, 255, 0, 255])
    }

    @Test("A primitive subregion limits that primitive")
    func subregion() throws {
        let image = try render(
            20, 10,
            filter(#"<feFlood flood-color="blue" width="5"/>"#)
                + #"<rect width="20" height="10" fill="red" filter="url(#f)"/>"#)
        #expect(pixel(image, 2, 5) == [0, 0, 255, 255])
        #expect(pixel(image, 10, 5)[3] == 0)
    }

    @Test("A filter outside the subset draws unfiltered and is reported; an empty one hides the element")
    func unsupportedAndEmpty() throws {
        let unsupported = try document(
            10, 10,
            #"<filter id="f"><feTurbulence baseFrequency="0.1"/></filter><rect width="10" height="10" fill="red" filter="url(#f)"/>"#)
        #expect(unsupported.diagnostics.map(\.description).contains { $0.contains("<feTurbulence>") })
        let drawn = unsupported.rasterize(width: 10, height: 10, showsUnsupportedMarkers: false)
        #expect(pixel(drawn, 5, 5) == [255, 0, 0, 255])
        let empty = try render(
            10, 10, #"<filter id="f"/><rect width="10" height="10" fill="red" filter="url(#f)"/>"#)
        #expect(pixel(empty, 5, 5)[3] == 0)
    }

    @Test("A working filter is not reported")
    func clean() throws {
        let document = try document(
            10, 10,
            #"<filter id="f"><feGaussianBlur stdDeviation="1"/></filter><rect width="10" height="10" fill="red" filter="url(#f)"/>"#)
        #expect(document.diagnostics.isEmpty)
    }
}
