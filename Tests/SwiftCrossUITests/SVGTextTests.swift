import Foundation
import ImageFormats
import Testing

@testable import SwiftCrossUI

/// SVG `<text>` drawn through a backend's text mask (2026-10-09).
/// 經 backend 文字遮罩繪製的 SVG `<text>`(2026-10-09)。
@Suite("SVG text")
struct SVGTextTests {
    func svg(_ width: Int, _ height: Int, _ body: String, viewBox: String? = nil) -> String {
        let box = viewBox.map { " viewBox=\"\($0)\"" } ?? ""
        return
            "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(width)\" height=\"\(height)\"\(box)>\(body)</svg>"
    }

    func pixel(_ image: ImageFormats.Image<RGBA>, _ x: Int, _ y: Int) -> [UInt8] {
        let index = (y * image.width + x) * 4
        return Array(image.bytes[index..<(index + 4)])
    }

    /// A masker that covers one fixed rectangle fully and records every request.
    /// 把一個固定矩形完全覆蓋、並記錄每次請求的遮罩繪製器。
    final class FakeMasker: @unchecked Sendable {
        var requests: [SVGTextMaskRequest] = []
        let rect: (x: Range<Int>, y: Range<Int>)
        let answers: Bool

        init(x: Range<Int>, y: Range<Int>, answers: Bool = true) {
            rect = (x, y)
            self.answers = answers
        }

        func mask(_ request: SVGTextMaskRequest) -> [UInt8]? {
            requests.append(request)
            guard answers else { return nil }
            var bytes = [UInt8](repeating: 0, count: request.width * request.height)
            for y in rect.y where y < request.height {
                for x in rect.x where x < request.width {
                    bytes[y * request.width + x] = 255
                }
            }
            return bytes
        }
    }

    @Test("The mask is filled with the text's own colour, and drawn text is not outlined")
    func fillsWithTextColour() throws {
        let document = try SVGDocument(
            string: svg(20, 10, #"<text x="2" y="8" fill="red">Hi</text>"#))
        let masker = FakeMasker(x: 2..<6, y: 2..<8)
        let image = document.rasterize(width: 20, height: 10, textMasker: masker.mask)
        #expect(pixel(image, 3, 4) == [255, 0, 0, 255])
        #expect(pixel(image, 10, 4)[3] == 0)
        #expect(pixel(image, 0, 0)[3] == 0)  // no corner flag: nothing was left undrawn
        #expect(document.diagnostics.map(\.kind) == [.textNeedsRenderer])
    }

    @Test("Paint order: a rectangle after the text covers it")
    func paintOrder() throws {
        let document = try SVGDocument(
            string: svg(
                20, 10,
                #"<text x="2" y="8" fill="red">Hi</text><rect x="0" y="0" width="20" height="10" fill="blue"/>"#))
        let image = document.rasterize(
            width: 20, height: 10, textMasker: FakeMasker(x: 2..<6, y: 2..<8).mask)
        #expect(pixel(image, 3, 4) == [0, 0, 255, 255])
    }

    @Test("The request carries the font, anchor and the transform to device pixels")
    func requestContents() throws {
        let document = try SVGDocument(
            string: svg(
                40, 20,
                #"<text x="5" y="7" font-family="'Liberation Sans', sans-serif" font-weight="700" font-style="italic" font-size="4" text-anchor="middle" fill="black">a  b</text>"#,
                viewBox: "0 0 20 10"))
        let masker = FakeMasker(x: 0..<1, y: 0..<1)
        _ = document.rasterize(width: 40, height: 20, textMasker: masker.mask)
        let request = try #require(masker.requests.first)
        #expect(request.run.text == "a b")
        #expect(request.run.fontFamilies == ["Liberation Sans", "sans-serif"])
        #expect(request.run.isBold)
        #expect(request.run.isItalic)
        #expect(request.run.fontSize == 4)
        #expect(request.run.anchor == .middle)
        #expect(request.strokeWidth == nil)
        // viewBox 20x10 shown at 40x20: scale 2, anchor point (5, 7) -> (10, 14).
        // viewBox 20x10 以 40x20 顯示：縮放 2,錨點 (5, 7) -> (10, 14)。
        #expect(request.transform == SVGTextTransform(a: 2, b: 0, c: 0, d: 2, tx: 10, ty: 14))
        #expect(request.width == 40 && request.height == 20)
    }

    @Test("Stroked text asks for a second, stroked mask")
    func strokeRequest() throws {
        let document = try SVGDocument(
            string: svg(20, 10, #"<text x="1" y="8" fill="none" stroke="green" stroke-width="0.5">Hi</text>"#))
        let masker = FakeMasker(x: 2..<4, y: 2..<8)
        let image = document.rasterize(width: 20, height: 10, textMasker: masker.mask)
        #expect(masker.requests.map(\.strokeWidth) == [0.5])
        #expect(pixel(image, 3, 4) == [0, 128, 0, 255])
    }

    @Test("A masker that draws nothing leaves the magenta outline")
    func failingMasker() throws {
        let document = try SVGDocument(string: svg(20, 10, #"<text x="2" y="8">Hi</text>"#))
        let image = document.rasterize(
            width: 20, height: 10, textMasker: FakeMasker(x: 0..<0, y: 0..<0, answers: false).mask)
        #expect(pixel(image, 1, 1) == [255, 0, 255, 255])  // corner flag
    }

    #if canImport(CoreText)
        func coverage(_ mask: [UInt8], width: Int, columns: Range<Int>) -> Int {
            var total = 0
            for (index, value) in mask.enumerated() where columns.contains(index % width) {
                total += Int(value)
            }
            return total
        }

        @Test("Core Text draws Latin text, centred on its anchor for text-anchor middle")
        func coreTextLatin() throws {
            let run = SVGTextRun(
                text: "HHHH", fontFamilies: ["sans-serif"], fontSize: 20, isBold: false,
                isItalic: false, anchor: .middle)
            let request = SVGTextMaskRequest(
                run: run, transform: SVGTextTransform(a: 1, b: 0, c: 0, d: 1, tx: 50, ty: 30),
                width: 100, height: 40)
            let mask = try #require(SVGCoreTextMasker.mask(request))
            #expect(mask.count == 4000)
            let left = coverage(mask, width: 100, columns: 0..<50)
            let right = coverage(mask, width: 100, columns: 50..<100)
            #expect(left > 1000 && right > 1000)
            #expect(abs(left - right) * 10 < left + right)  // within 10% of each other
        }

        @Test("Core Text draws Chinese through font substitution")
        func coreTextChinese() throws {
            let run = SVGTextRun(
                text: "電", fontFamilies: ["Helvetica"], fontSize: 24, isBold: false, isItalic: false,
                anchor: .start)
            let request = SVGTextMaskRequest(
                run: run, transform: SVGTextTransform(a: 1, b: 0, c: 0, d: 1, tx: 4, ty: 28),
                width: 40, height: 36)
            let mask = try #require(SVGCoreTextMasker.mask(request))
            #expect(mask.reduce(0) { $0 + Int($1) } > 255 * 40)
        }
    #endif
}
