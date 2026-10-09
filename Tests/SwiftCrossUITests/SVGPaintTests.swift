import Foundation
import ImageFormats
import Testing

@testable import SwiftCrossUI

/// Gradients (2026-10-10). Each expectation is chosen so a wrong rule gives a
/// clearly different number, not just a slightly different one.
/// 漸層(2026-10-10)。每個預期值都選成：規則錯了會得到明顯不同的數字，而不只是略有差異。
@Suite("SVG paint servers")
struct SVGPaintTests {
    func svg(_ width: Int, _ height: Int, _ body: String) -> String {
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(width)\" height=\"\(height)\">\(body)</svg>"
    }

    func render(_ width: Int, _ height: Int, _ body: String) throws -> ImageFormats.Image<RGBA> {
        try SVGDocument(string: svg(width, height, body)).rasterize(width: width, height: height)
    }

    func pixel(_ image: ImageFormats.Image<RGBA>, _ x: Int, _ y: Int) -> [Int] {
        let index = (y * image.width + x) * 4
        return image.bytes[index..<(index + 4)].map(Int.init)
    }

    func close(_ actual: [Int], _ expected: [Int], within tolerance: Int = 3) -> Bool {
        zip(actual, expected).allSatisfy { abs($0 - $1) <= tolerance }
    }

    let redToBlue = #"<stop offset="0" stop-color="red"/><stop offset="1" stop-color="blue"/>"#

    @Test("Linear: red at the start, blue at the end, the mix between")
    func linear() throws {
        let image = try render(
            100, 10,
            #"<linearGradient id="g">\#(redToBlue)</linearGradient><rect width="100" height="10" fill="url(#g)"/>"#)
        #expect(close(pixel(image, 0, 5), [254, 0, 1, 255]))
        #expect(close(pixel(image, 99, 5), [1, 0, 254, 255]))
        // Pixel 49's centre is at t = 0.495. / 第 49 個像素的中心在 t = 0.495。
        #expect(close(pixel(image, 49, 5), [129, 0, 126, 255]))
    }

    @Test("userSpaceOnUse spans the drawing; objectBoundingBox spans each shape")
    func units() throws {
        let user = try render(
            200, 10,
            #"<linearGradient id="g" gradientUnits="userSpaceOnUse" x1="0" x2="200">\#(redToBlue)</linearGradient><rect x="100" width="100" height="10" fill="url(#g)"/>"#)
        let box = try render(
            200, 10,
            #"<linearGradient id="g">\#(redToBlue)</linearGradient><rect x="100" width="100" height="10" fill="url(#g)"/>"#)
        // x = 150.5: t = 0.7525 across the drawing, 0.505 across the shape.
        // x = 150.5:整張圖上 t = 0.7525,形狀上 t = 0.505。
        #expect(close(pixel(user, 150, 5), [63, 0, 192, 255]))
        #expect(close(pixel(box, 150, 5), [126, 0, 129, 255]))
    }

    @Test("spreadMethod: pad holds the end colour, repeat restarts, reflect mirrors")
    func spread() throws {
        func at75(_ method: String) throws -> [Int] {
            let image = try render(
                100, 10,
                #"<linearGradient id="g" x2="50%" spreadMethod="\#(method)">\#(redToBlue)</linearGradient><rect width="100" height="10" fill="url(#g)"/>"#)
            return pixel(image, 75, 5)
        }
        // x = 75.5 is t = 1.51. / x = 75.5 為 t = 1.51。
        #expect(close(try at75("pad"), [0, 0, 255, 255]))
        #expect(close(try at75("repeat"), [125, 0, 130, 255]))
        #expect(close(try at75("reflect"), [130, 0, 125, 255]))
    }

    @Test("Radial: red at the centre, blue at the circle and beyond it")
    func radial() throws {
        let image = try render(
            100, 100,
            #"<radialGradient id="g">\#(redToBlue)</radialGradient><rect width="100" height="100" fill="url(#g)"/>"#)
        #expect(pixel(image, 50, 50)[0] > 245)
        #expect(pixel(image, 50, 0)[2] > 245)  // 49.5 from the centre, r = 50
        #expect(close(pixel(image, 0, 0), [0, 0, 255, 255]))  // outside the circle: padded
    }

    @Test("A focal point moves the red end of a radial gradient")
    func focal() throws {
        let image = try render(
            100, 100,
            #"<radialGradient id="g" fx="0.25" fy="0.5">\#(redToBlue)</radialGradient><rect width="100" height="100" fill="url(#g)"/>"#)
        #expect(pixel(image, 25, 50)[0] > 245)
        #expect(pixel(image, 75, 50)[0] < pixel(image, 30, 50)[0])
    }

    @Test("stop-opacity and fill-opacity both reach the alpha")
    func opacity() throws {
        let image = try render(
            100, 10,
            #"<linearGradient id="g"><stop offset="0" stop-color="red" stop-opacity="0"/><stop offset="1" style="stop-color: blue"/></linearGradient><rect width="100" height="10" fill="url(#g)" fill-opacity="0.5"/>"#)
        #expect(pixel(image, 0, 5)[3] < 3)
        #expect(abs(pixel(image, 99, 5)[3] - 127) <= 3)
        #expect(pixel(image, 99, 5)[2] > 250)  // straight alpha: still blue
    }

    @Test("href: stops and attributes come from the referenced gradient unless overridden")
    func inheritance() throws {
        let image = try render(
            100, 10,
            ##"<linearGradient id="base" spreadMethod="reflect">\##(redToBlue)</linearGradient><linearGradient id="g" href="#base" x2="50%"/><rect width="100" height="10" fill="url(#g)"/>"##)
        #expect(close(pixel(image, 75, 5), [130, 0, 125, 255]))  // reflect inherited, x2 overridden
    }

    @Test("gradientTransform rotates the gradient")
    func gradientTransform() throws {
        let image = try render(
            10, 100,
            #"<linearGradient id="g" gradientTransform="rotate(90)">\#(redToBlue)</linearGradient><rect width="10" height="100" fill="url(#g)"/>"#)
        #expect(pixel(image, 5, 0)[0] > 245)
        #expect(pixel(image, 5, 99)[2] > 245)
    }

    @Test("No stops paints nothing; one stop paints a solid colour")
    func stopCounts() throws {
        let none = try render(
            10, 10, #"<linearGradient id="g"/><rect width="10" height="10" fill="url(#g)"/>"#)
        #expect(pixel(none, 5, 5)[3] == 0)
        let one = try render(
            10, 10,
            #"<linearGradient id="g"><stop offset="0.3" stop-color="lime"/></linearGradient><rect width="10" height="10" fill="url(#g)"/>"#)
        #expect(pixel(one, 5, 5) == [0, 255, 0, 255])
    }

    @Test("Text takes a gradient fill through the text mask")
    func textGradient() throws {
        let document = try SVGDocument(
            string: svg(
                100, 20,
                #"<linearGradient id="g">\#(redToBlue)</linearGradient><text x="0" y="16" textLength="100" font-size="20" fill="url(#g)">Hi</text>"#))
        let image = document.rasterize(width: 100, height: 20) { request in
            [UInt8](repeating: 255, count: request.width * request.height)
        }
        #expect(pixel(image, 1, 10)[0] > 240)
        #expect(pixel(image, 98, 10)[2] > 240)
    }
}
