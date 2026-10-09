import Foundation
import ImageFormats
import Testing

@testable import SwiftCrossUI

/// `<image>` referring to files, and `<image>` of an SVG (2026-10-10).
/// 參照檔案的 `<image>`,以及內容為 SVG 的 `<image>`(2026-10-10)。
@Suite("SVG image files")
struct SVGImageFileTests {
    /// A 2x1 PNG: red, then blue. / 2x1 的 PNG:紅，然後藍。
    static let redBlue = Data(
        base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAADklEQVR4nGP4z8AAQv8BD/kD/YURmXYAAAAASUVORK5CYII="
    )!

    /// A fresh folder holding `files`, path to contents.
    /// 一個新的資料夾，內含 `files`(路徑對內容)。
    func folder(_ files: [String: Data]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("svg-image-files-\(UUID().uuidString)")
        for (path, data) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        return root
    }

    func svg(_ width: Int, _ height: Int, _ body: String) -> Data {
        Data(
            "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" width=\"\(width)\" height=\"\(height)\">\(body)</svg>"
                .utf8)
    }

    func pixel(_ image: ImageFormats.Image<RGBA>, _ x: Int, _ y: Int) -> [Int] {
        let index = (y * image.width + x) * 4
        return image.bytes[index..<(index + 4)].map(Int.init)
    }

    func open(_ root: URL, _ name: String) throws -> SVGDocument {
        try SVGDocument(contentsOf: root.appendingPathComponent(name))
    }

    @Test("A picture beside the document, or in a folder below it, is drawn")
    func besideAndBelow() throws {
        let root = try folder([
            "pic.png": Self.redBlue, "img/sub/pic.png": Self.redBlue,
            "a.svg": svg(
                20, 20,
                #"<image width="20" height="10" preserveAspectRatio="none" href="pic.png"/><image y="10" width="20" height="10" preserveAspectRatio="none" xlink:href="img/sub/pic.png"/>"#),
        ])
        let document = try open(root, "a.svg")
        #expect(document.diagnostics.isEmpty)
        let image = document.rasterize(width: 20, height: 20)
        #expect(pixel(image, 2, 5) == [255, 0, 0, 255])
        #expect(pixel(image, 17, 15) == [0, 0, 255, 255])
    }

    @Test("Outside the folder, an absolute path or a network address is refused and reported")
    func refused() throws {
        let root = try folder([
            "outside.png": Self.redBlue,
            "doc/a.svg": svg(
                10, 10,
                #"<image width="10" height="10" href="../outside.png"/><image width="10" height="10" href="/etc/hosts"/><image width="10" height="10" href="https://example.com/p.png"/>"#),
        ])
        let details = try open(root, "doc/a.svg").diagnostics.map(\.description)
        #expect(details.contains { $0.contains("../outside.png is outside the document's folder") })
        #expect(details.contains { $0.contains("/etc/hosts is outside the document's folder") })
        #expect(details.contains { $0.contains("network address") })
    }

    @Test("A document from a string reads no files")
    func fromString() throws {
        let document = try SVGDocument(
            string: #"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><image width="10" height="10" href="pic.png"/></svg>"#)
        #expect(document.diagnostics.map(\.description).contains { $0.contains("only data: URIs") })
    }

    @Test("An SVG picture is placed as vectors, scaled and clipped to the viewport")
    func nestedSVG() throws {
        let root = try folder([
            // 10x10, left half red, and a square sticking out past the right edge.
            // 10x10,左半紅，以及一個超出右緣的方塊。
            "inner.svg": svg(
                10, 10,
                #"<rect width="5" height="10" fill="red"/><rect x="8" y="0" width="10" height="2" fill="blue"/>"#),
            "a.svg": svg(60, 40, #"<image width="40" height="40" href="inner.svg"/>"#),
        ])
        let document = try open(root, "a.svg")
        #expect(document.diagnostics.isEmpty)
        let image = document.rasterize(width: 60, height: 40)
        #expect(pixel(image, 10, 20) == [255, 0, 0, 255])  // scaled 4x / 放大 4 倍
        #expect(pixel(image, 30, 20)[3] == 0)
        #expect(pixel(image, 38, 4) == [0, 0, 255, 255])
        // The blue square would run on to x 72; the viewport ends at 40.
        // 藍方塊原本會延伸到 x 72;視窗止於 40。
        #expect(pixel(image, 50, 4)[3] == 0)
    }

    @Test("What a nested SVG cannot draw is reported against the image; text still goes to the masker")
    func nestedDiagnosticsAndText() throws {
        let root = try folder([
            "inner.svg": svg(
                10, 10, #"<foreignObject width="5" height="5"/><text x="0" y="8">Hi</text>"#),
            "a.svg": svg(20, 20, #"<image width="20" height="20" href="inner.svg"/>"#),
        ])
        let document = try open(root, "a.svg")
        let details = document.diagnostics.map(\.description)
        #expect(details.contains { $0.contains("in inner.svg: <foreignObject> is not drawn") })
        var requests: [SVGTextMaskRequest] = []
        _ = document.rasterize(width: 20, height: 20) { request in
            requests.append(request)
            return nil
        }
        #expect(requests.first?.transform.a == 2)  // 10 -> 20 / 10 放到 20
    }

    @Test("A picture that includes itself is reported, not followed")
    func cycle() throws {
        let root = try folder([
            "a.svg": svg(10, 10, #"<image width="10" height="10" href="a.svg"/>"#)
        ])
        let details = try open(root, "a.svg").diagnostics.map(\.description)
        #expect(details.contains { $0.contains("refers to itself") })
    }

    @Test("A data: URI holding an SVG is drawn as vectors too")
    func dataSVG() throws {
        let inner = #"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect width="10" height="10" fill="red"/></svg>"#
        let encoded = inner.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        let document = try SVGDocument(
            string: #"<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20"><image width="20" height="20" href="data:image/svg+xml,\#(encoded)"/></svg>"#)
        #expect(document.diagnostics.isEmpty)
        #expect(pixel(document.rasterize(width: 20, height: 20), 10, 10) == [255, 0, 0, 255])
    }
}
