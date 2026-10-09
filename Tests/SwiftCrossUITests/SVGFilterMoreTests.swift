import Foundation
import ImageFormats
import Testing

@testable import SwiftCrossUI

/// The rest of SVG 1.1's filter primitives (2026-10-10).
/// SVG 1.1 其餘的濾鏡 primitive(2026-10-10)。
@Suite("SVG filters, the rest")
struct SVGFilterMoreTests {
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

    /// A filter over the whole drawing, in sRGB unless asked otherwise.
    /// 涵蓋整張圖的濾鏡，除非另外指定，否則用 sRGB。
    func filter(_ primitives: String, space: String = "sRGB") -> String {
        #"<filter id="f" filterUnits="userSpaceOnUse" x="0" y="0" width="100" height="100" color-interpolation-filters="\#(space)">\#(primitives)</filter>"#
    }

    let square = #"<rect x="10" y="10" width="10" height="10" fill="red" filter="url(#f)"/>"#

    @Test("feMorphology dilate grows the shape, erode shrinks it")
    func morphology() throws {
        let dilate = try render(30, 30, filter(#"<feMorphology operator="dilate" radius="2"/>"#) + square)
        #expect(pixel(dilate, 8, 15) == red)
        #expect(pixel(dilate, 6, 15)[3] == 0)
        let erode = try render(30, 30, filter(#"<feMorphology radius="2"/>"#) + square)
        #expect(pixel(erode, 11, 15)[3] == 0)
        #expect(pixel(erode, 15, 15) == red)
    }

    @Test("feConvolveMatrix applies its kernel turned 180 degrees")
    func convolve() throws {
        // A single 1 in the middle row's left cell samples the pixel to the right,
        // so the picture moves one pixel left. / 中列左格的單一 1 取右邊的像素，所以圖往左移一像素。
        let image = try render(
            30, 30,
            filter(#"<feConvolveMatrix order="3" kernelMatrix="0 0 0 1 0 0 0 0 0"/>"#) + square)
        #expect(pixel(image, 9, 15) == red)
        #expect(pixel(image, 19, 15)[3] == 0)
        let identity = try render(
            30, 30,
            filter(#"<feConvolveMatrix kernelMatrix="0 0 0 0 1 0 0 0 0"/>"#) + square)
        #expect(pixel(identity, 10, 15) == red)
        #expect(pixel(identity, 9, 15)[3] == 0)
    }

    @Test("feTile repeats its input's subregion")
    func tile() throws {
        let image = try render(
            30, 10,
            filter(
                #"<feFlood flood-color="blue" x="0" y="0" width="10" height="10" result="b"/><feFlood flood-color="red" x="0" y="0" width="5" height="10" result="r"/><feMerge x="0" y="0" width="10" height="10"><feMergeNode in="b"/><feMergeNode in="r"/></feMerge><feTile/>"#)
                + #"<rect width="30" height="10" fill="black" filter="url(#f)"/>"#)
        #expect(pixel(image, 2, 5) == red)
        #expect(pixel(image, 7, 5) == [0, 0, 255, 255])
        #expect(pixel(image, 12, 5) == red)  // the next tile / 下一個圖塊
        #expect(pixel(image, 27, 5) == [0, 0, 255, 255])
    }

    @Test("feDisplacementMap moves pixels by the map's channels")
    func displacement() throws {
        // R = 1 moves by +scale/2 = 10, G = 0.5 by 0: the picture appears 10 to the left.
        // R = 1 位移 +scale/2 = 10,G = 0.5 位移 0:圖出現在左邊 10 處。
        let image = try render(
            40, 30,
            filter(
                #"<feFlood flood-color="rgb(255,128,128)" result="map"/><feDisplacementMap in="SourceGraphic" in2="map" scale="20" xChannelSelector="R" yChannelSelector="G"/>"#)
                + #"<rect x="20" y="10" width="10" height="10" fill="red" filter="url(#f)"/>"#)
        #expect(pixel(image, 15, 15) == red)
        #expect(pixel(image, 25, 15)[3] == 0)
    }

    @Test("feTurbulence is deterministic per seed and varies across the region")
    func turbulence() throws {
        let body = #"<rect width="40" height="40" fill="black" filter="url(#f)"/>"#
        func noise(_ seed: Int, _ type: String) throws -> ImageFormats.Image<RGBA> {
            try render(
                40, 40,
                filter(#"<feTurbulence type="\#(type)" baseFrequency="0.1" numOctaves="2" seed="\#(seed)"/>"#)
                    + body)
        }
        let a = try noise(1, "fractalNoise")
        let b = try noise(1, "fractalNoise")
        let c = try noise(2, "fractalNoise")
        #expect(a.bytes == b.bytes)
        #expect(a.bytes != c.bytes)
        let alphas = stride(from: 3, to: a.bytes.count, by: 4).map { Int(a.bytes[$0]) }
        let mean = alphas.reduce(0, +) / alphas.count
        #expect((96...160).contains(mean))  // fractal noise centres on one half / 分形雜訊以一半為中心
        #expect(Set(alphas).count > 50)  // it varies / 有變化
        let turbulence = try noise(1, "turbulence")
        #expect(turbulence.bytes != a.bytes)
    }

    @Test("Diffuse light on a flat surface is kd times N.L: overhead 1, at 30 degrees 0.5")
    func diffuse() throws {
        func lit(_ elevation: Int) throws -> [Int] {
            let image = try render(
                30, 30,
                filter(
                    #"<feDiffuseLighting lighting-color="white"><feDistantLight azimuth="0" elevation="\#(elevation)"/></feDiffuseLighting>"#)
                    + square)
            return pixel(image, 15, 15)
        }
        #expect(try lit(90) == [255, 255, 255, 255])
        let half = try lit(30)
        #expect(abs(half[0] - 128) <= 2 && half[3] == 255)
    }

    @Test("Specular light overhead on a flat surface is ks, with alpha the largest channel")
    func specular() throws {
        let image = try render(
            30, 30,
            filter(
                #"<feSpecularLighting specularExponent="10" lighting-color="rgb(255,0,0)"><feDistantLight elevation="90"/></feSpecularLighting>"#)
                + square)
        #expect(pixel(image, 15, 15) == red)
    }

    @Test("A point light is brighter right under it than far away")
    func pointLight() throws {
        let image = try render(
            60, 20,
            filter(#"<feDiffuseLighting><fePointLight x="5" y="10" z="10"/></feDiffuseLighting>"#)
                + #"<rect width="60" height="20" fill="red" filter="url(#f)"/>"#)
        #expect(pixel(image, 5, 10)[0] > pixel(image, 50, 10)[0] + 50)
    }

    @Test("feImage draws a referenced element, or a picture in its subregion")
    func image() throws {
        let element = try render(
            30, 30,
            #"<defs><rect id="r" x="0" y="0" width="5" height="5" fill="blue"/></defs>"#
                + filter(##"<feImage href="#r"/>"##) + square)
        #expect(pixel(element, 2, 2) == [0, 0, 255, 255])
        #expect(pixel(element, 15, 15)[3] == 0)  // the source is replaced / 來源被取代
        let png =
            "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAADklEQVR4nGP4z8AAQv8BD/kD/YURmXYAAAAASUVORK5CYII="
        let picture = try render(
            30, 30,
            filter(
                "<feImage href=\"\(png)\" x=\"0\" y=\"0\" width=\"20\" height=\"10\" preserveAspectRatio=\"none\"/>")
                + square)
        #expect(pixel(picture, 1, 5) == red)
        #expect(pixel(picture, 18, 5) == [0, 0, 255, 255])
    }

    @Test("BackgroundImage reads as transparent, as in browsers, and nothing is reported")
    func background() throws {
        let document = try document(
            30, 30,
            filter(#"<feMerge><feMergeNode in="BackgroundImage"/><feMergeNode in="SourceGraphic"/></feMerge>"#)
                + square)
        #expect(document.diagnostics.isEmpty)
        let image = document.rasterize(width: 30, height: 30)
        #expect(pixel(image, 15, 15) == red)
        #expect(pixel(image, 5, 5)[3] == 0)
    }
}
