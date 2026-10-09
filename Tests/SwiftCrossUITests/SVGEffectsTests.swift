import Foundation
import ImageFormats
import Testing

@testable import SwiftCrossUI

/// `clip-path` and `mask` (2026-10-10). / `clip-path` 與 `mask`(2026-10-10)。
@Suite("SVG clip-path and mask")
struct SVGEffectsTests {
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

    @Test("A clipPath keeps what lies inside it and nothing else")
    func clipRect() throws {
        let image = try render(
            20, 10,
            #"<clipPath id="c"><rect width="10" height="10"/></clipPath><rect width="20" height="10" fill="red" clip-path="url(#c)"/>"#)
        #expect(pixel(image, 5, 5) == red)
        #expect(pixel(image, 15, 5)[3] == 0)
    }

    @Test("In a clipPath only geometry counts: fill none, opacity 0 and strokes change nothing")
    func clipGeometryOnly() throws {
        let image = try render(
            20, 10,
            #"<clipPath id="c"><rect width="10" height="10" fill="none" opacity="0" stroke="red" stroke-width="8"/></clipPath><rect width="20" height="10" fill="red" clip-path="url(#c)"/>"#)
        #expect(pixel(image, 5, 5) == red)
        #expect(pixel(image, 12, 5)[3] == 0)  // a stroke would have reached x = 14
    }

    @Test("clip-rule evenodd cuts a hole where nonzero does not")
    func clipRule() throws {
        let rings = #"M0 0H20V20H0Z M5 5H15V15H5Z"#
        let evenodd = try render(
            20, 20,
            #"<clipPath id="c"><path d="\#(rings)" clip-rule="evenodd"/></clipPath><rect width="20" height="20" fill="red" clip-path="url(#c)"/>"#)
        let nonzero = try render(
            20, 20,
            #"<clipPath id="c"><path d="\#(rings)"/></clipPath><rect width="20" height="20" fill="red" clip-path="url(#c)"/>"#)
        #expect(pixel(evenodd, 2, 2) == red)
        #expect(pixel(evenodd, 10, 10)[3] == 0)
        #expect(pixel(nonzero, 10, 10) == red)
    }

    @Test("clipPathUnits objectBoundingBox measures in the clipped shape's box")
    func clipBoundingBox() throws {
        let image = try render(
            40, 10,
            #"<clipPath id="c" clipPathUnits="objectBoundingBox"><rect width="0.5" height="1"/></clipPath><rect x="10" width="20" height="10" fill="red" clip-path="url(#c)"/>"#)
        #expect(pixel(image, 15, 5) == red)
        #expect(pixel(image, 25, 5)[3] == 0)
    }

    @Test("The clip is in the user space of the element, transform included")
    func clipUserSpace() throws {
        let image = try render(
            40, 10,
            #"<clipPath id="c"><rect width="10" height="10"/></clipPath><g transform="translate(20 0)" clip-path="url(#c)"><rect x="-20" width="40" height="10" fill="red"/></g>"#)
        #expect(pixel(image, 25, 5) == red)
        #expect(pixel(image, 5, 5)[3] == 0)
        #expect(pixel(image, 35, 5)[3] == 0)
    }

    @Test("A clip-path on the clipPath intersects the two")
    func nestedClip() throws {
        let image = try render(
            30, 10,
            #"<clipPath id="a"><rect width="20" height="10"/></clipPath><clipPath id="b" clip-path="url(#a)"><rect x="10" width="20" height="10"/></clipPath><rect width="30" height="10" fill="red" clip-path="url(#b)"/>"#)
        #expect(pixel(image, 5, 5)[3] == 0)
        #expect(pixel(image, 15, 5) == red)
        #expect(pixel(image, 25, 5)[3] == 0)
    }

    @Test("Opacity and clip act on the element as a whole")
    func opacityAndClip() throws {
        let image = try render(
            20, 10,
            #"<clipPath id="c"><rect width="10" height="10"/></clipPath><rect width="20" height="10" fill="red" opacity="0.5" clip-path="url(#c)"/>"#)
        #expect(abs(pixel(image, 5, 5)[3] - 128) <= 1)
        #expect(pixel(image, 15, 5)[3] == 0)
    }

    @Test("A luminance mask: white shows, black hides, grey halves")
    func luminanceMask() throws {
        let image = try render(
            30, 10,
            #"<mask id="m" maskUnits="userSpaceOnUse" x="0" y="0" width="30" height="10"><rect width="10" height="10" fill="white"/><rect x="10" width="10" height="10" fill="black"/><rect x="20" width="10" height="10" fill="gray"/></mask><rect width="30" height="10" fill="red" mask="url(#m)"/>"#)
        #expect(pixel(image, 5, 5) == red)
        #expect(pixel(image, 15, 5)[3] == 0)
        #expect(abs(pixel(image, 25, 5)[3] - 128) <= 2)
        #expect(pixel(image, 25, 5)[0] == 255)  // straight colour stays red
    }

    @Test("mask-type alpha reads alpha, so black shows")
    func alphaMask() throws {
        let image = try render(
            10, 10,
            #"<mask id="m" mask-type="alpha"><rect width="10" height="10" fill="black"/></mask><rect width="10" height="10" fill="red" mask="url(#m)"/>"#)
        #expect(pixel(image, 5, 5) == red)
    }

    @Test("The mask region limits the mask; maskContentUnits objectBoundingBox scales the content")
    func maskRegionAndUnits() throws {
        let region = try render(
            20, 10,
            #"<mask id="m" x="0" y="0" width="0.5" height="1"><rect width="20" height="10" fill="white"/></mask><rect width="20" height="10" fill="red" mask="url(#m)"/>"#)
        #expect(pixel(region, 5, 5) == red)
        #expect(pixel(region, 15, 5)[3] == 0)
        let units = try render(
            40, 10,
            #"<mask id="m" maskContentUnits="objectBoundingBox"><rect width="0.25" height="1" fill="white"/></mask><rect x="20" width="20" height="10" fill="red" mask="url(#m)"/>"#)
        #expect(pixel(units, 22, 5) == red)
        #expect(pixel(units, 30, 5)[3] == 0)
    }

    @Test("Text in a clipPath clips through the text mask")
    func textClip() throws {
        let document = try document(
            20, 10,
            #"<clipPath id="c"><text x="0" y="8" fill="none">Hi</text></clipPath><rect width="20" height="10" fill="red" clip-path="url(#c)"/>"#)
        let image = document.rasterize(width: 20, height: 10, showsUnsupportedMarkers: false) {
            request in
            // Covers the left half only. / 只覆蓋左半。
            (0..<(request.width * request.height)).map { $0 % request.width < 10 ? 255 : 0 }
        }
        #expect(pixel(image, 5, 5) == red)
        #expect(pixel(image, 15, 5)[3] == 0)
    }

    @Test("A broken or circular reference draws unclipped and is reported")
    func brokenReferences() throws {
        let missing = try document(
            10, 10, #"<rect width="10" height="10" fill="red" clip-path="url(#nope)" mask="url(#gone)"/>"#)
        let details = missing.diagnostics.map(\.description)
        #expect(details.contains { $0.contains("clip-path url(#nope)") })
        #expect(details.contains { $0.contains("mask url(#gone)") })
        let image = missing.rasterize(width: 10, height: 10, showsUnsupportedMarkers: false)
        #expect(pixel(image, 5, 5) == red)

        let circular = try document(
            10, 10,
            #"<clipPath id="c" clip-path="url(#c)"><rect width="5" height="10"/></clipPath><rect width="10" height="10" fill="red" clip-path="url(#c)"/>"#)
        #expect(circular.diagnostics.map(\.description).contains { $0.contains("refers to itself") })
    }

    @Test("A working clip-path or mask is not reported")
    func notReported() throws {
        let document = try document(
            10, 10,
            #"<clipPath id="c"><rect width="5" height="10"/></clipPath><mask id="m"><rect width="10" height="10" fill="white"/></mask><rect width="10" height="10" fill="red" clip-path="url(#c)" mask="url(#m)"/>"#)
        #expect(document.diagnostics.isEmpty)
    }
}
