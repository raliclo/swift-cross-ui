import Foundation
import ImageFormats
import Testing

@_spi(Backends) @testable import SwiftCrossUI

/// Finite but enormous coordinates must not stop the process (2026-10-14).
///
/// `SVGRasterizer.coverage` converted the shape's bounds to `Int` before
/// clipping them to the canvas, so a finite coordinate such as `1e20` -- well
/// past `Int.max`, about 9.2e18 -- trapped the conversion and took the app down
/// for one malformed or hostile SVG (todo.md, review item "SVG large-coordinate
/// crash"). Near `Double`'s own limit a second path existed: an edge from
/// -1.7e308 to 1.7e308 has a span that overflows to infinity, its slope became
/// infinity over infinity, NaN, and a NaN crossing passed every clamp.
///
/// Each test below is a rendering that must FINISH; where the geometry is still
/// exact at that magnitude (axis-aligned edges) the coverage is checked too.
///
/// 有限但巨大的座標不可以讓行程中止(2026-10-14)。
///
/// `SVGRasterizer.coverage` 先把形狀的邊界轉成 `Int`,才裁切到畫布，因此像 `1e20` 這樣的有限座標——遠超過
/// 約 9.2e18 的 `Int.max`——會讓轉換中止，一份格式錯誤或惡意的 SVG 就拖垮整個 app(todo.md 審查項目
/// 「SVG 大座標可能造成 crash」)。接近 `Double` 本身上限時還有第二條路：從 -1.7e308 到 1.7e308 的邊，
/// 其跨度溢位成無限大，斜率成了無限大除以無限大，即 NaN,而 NaN 的交點能穿過每一道夾值。
///
/// 以下每個測試都是一次必須**完成**的算繪；在該量級下幾何仍然精確的情況(軸對齊的邊),也檢查覆蓋率。
@Suite("SVG extreme coordinates")
struct SVGExtremeCoordinateTests {
    private func render(_ body: String) throws -> ImageFormats.Image<RGBA> {
        let source = """
            <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" \
            viewBox="0 0 10 10">\(body)</svg>
            """
        return try SVGDocument(string: source).rasterize(width: 10, height: 10)
    }

    private func alphas(_ image: ImageFormats.Image<RGBA>) -> [Double] {
        stride(from: 3, to: image.bytes.count, by: 4).map { Double(image.bytes[$0]) / 255 }
    }

    @Test("A square from -1e20 to 1e20 covers the whole canvas")
    func hugeSquareCoversCanvas() throws {
        let image = try render(
            #"<path d="M -1e20 -1e20 L 1e20 -1e20 L 1e20 1e20 L -1e20 1e20 Z" fill="black"/>"#)
        #expect(alphas(image).allSatisfy { $0 == 1 })
    }

    @Test("A shape entirely past the canvas, far positive, draws nothing")
    func offCanvasPositive() throws {
        let image = try render(
            #"<path d="M 1e20 1e20 L 2e20 1e20 L 2e20 2e20 L 1e20 2e20 Z" fill="black"/>"#)
        #expect(alphas(image).allSatisfy { $0 == 0 })
    }

    @Test("A shape entirely past the canvas, far negative, draws nothing")
    func offCanvasNegative() throws {
        let image = try render(
            #"<path d="M -2e20 -2e20 L -1e20 -2e20 L -1e20 -1e20 L -2e20 -1e20 Z" fill="black"/>"#)
        #expect(alphas(image).allSatisfy { $0 == 0 })
    }

    @Test("A band from -1e20 to 1e20 across rows 2..5 covers exactly those rows")
    func hugeBandIsExact() throws {
        let image = try render(
            #"<path d="M -1e20 2 L 1e20 2 L 1e20 5 L -1e20 5 Z" fill="black"/>"#)
        let values = alphas(image)
        for row in 0..<10 {
            let expected: Double = (2..<5).contains(row) ? 1 : 0
            #expect(values[(row * 10)..<(row * 10 + 10)].allSatisfy { $0 == expected })
        }
    }

    @Test("Edges spanning -1.7e308 to 1.7e308 render without a trap")
    func nearDoubleLimit() throws {
        let image = try render(
            #"<path d="M -1.7e308 -1.7e308 L 1.7e308 1.7e308 L -1.7e308 1.7e308 Z" fill="black"/>"#)
        let values = alphas(image)
        #expect(values.count == 100)
        #expect(values.allSatisfy { $0 >= 0 && $0 <= 1 })
    }
}
