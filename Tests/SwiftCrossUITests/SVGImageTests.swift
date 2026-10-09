import Foundation
import ImageFormats
import Testing

@testable import SwiftCrossUI

/// `<image>` with a `data:` URI (2026-10-10). / 帶 `data:` URI 的 `<image>`(2026-10-10)。
@Suite("SVG images")
struct SVGImageTests {
    func svg(_ width: Int, _ height: Int, _ body: String) -> String {
        "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" width=\"\(width)\" height=\"\(height)\">\(body)</svg>"
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

    /// A 2x1 PNG: red, then blue. / 2x1 的 PNG:紅，然後藍。
    let redBlue =
        "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAADklEQVR4nGP4z8AAQv8BD/kD/YURmXYAAAAASUVORK5CYII="
    /// A 2x1 PNG: opaque green, then fully transparent. / 2x1 的 PNG:不透明綠，然後全透明。
    let greenClear =
        "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAADUlEQVR4nGNg+A+GDAAO+gL+i7GK9gAAAABJRU5ErkJggg=="
    /// An 8x8 JPEG of (0, 200, 0). / (0, 200, 0) 的 8x8 JPEG。
    let green8 =
        "data:image/jpeg;base64,/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAIBAQEBAQIBAQECAgICAgQDAgICAgUEBAMEBgUGBgYFBgYGBwkIBgcJBwYGCAsICQoKCgoKBggLDAsKDAkKCgr/2wBDAQICAgICAgUDAwUKBwYHCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgr/wAARCAAIAAgDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDk6KKK/wA9z/K8/9k="

    @Test("preserveAspectRatio none stretches the picture over the viewport")
    func stretched() throws {
        let image = try render(
            20, 10,
            "<image width=\"20\" height=\"10\" preserveAspectRatio=\"none\" href=\"\(redBlue)\"/>")
        #expect(pixel(image, 2, 5) == [255, 0, 0, 255])
        #expect(pixel(image, 17, 5) == [0, 0, 255, 255])
        // Bilinear between the two pixel centres. / 兩個像素中心之間雙線性內插。
        #expect(abs(pixel(image, 10, 5)[0] - pixel(image, 10, 5)[2]) < 30)
    }

    @Test("The default, xMidYMid meet, centres the picture and leaves a margin")
    func meet() throws {
        let image = try render(
            20, 20, "<image width=\"20\" height=\"20\" xlink:href=\"\(redBlue)\"/>")
        #expect(pixel(image, 2, 2)[3] == 0)  // margin above / 上方邊距
        #expect(pixel(image, 2, 10) == [255, 0, 0, 255])
        #expect(pixel(image, 17, 10) == [0, 0, 255, 255])
        #expect(pixel(image, 2, 17)[3] == 0)  // margin below / 下方邊距
    }

    @Test("slice fills the viewport and is cut to it")
    func slice() throws {
        let image = try render(
            20, 10,
            "<image width=\"10\" height=\"10\" preserveAspectRatio=\"xMidYMid slice\" href=\"\(redBlue)\"/>")
        // Scaled 10x and centred: x -5 to 15, red then blue, blended between the two pixel
        // centres (bilinear, as browsers smooth an enlarged picture by default).
        // 放大 10 倍並置中：x 從 -5 到 15,先紅後藍，兩個像素中心之間混色(雙線性，與瀏覽器放大圖片的預設平滑相同)。
        #expect(pixel(image, 0, 5)[0] > 230 && pixel(image, 0, 5)[3] == 255)
        #expect(pixel(image, 9, 5)[2] > 230 && pixel(image, 9, 5)[3] == 255)
        #expect(pixel(image, 13, 5)[3] == 0)  // cut at the viewport / 在視窗處裁掉
    }

    @Test("Without width and height the picture keeps its own size")
    func intrinsicSize() throws {
        let image = try render(4, 2, "<image x=\"1\" y=\"1\" href=\"\(redBlue)\"/>")
        #expect(pixel(image, 1, 1) == [255, 0, 0, 255])
        #expect(pixel(image, 2, 1) == [0, 0, 255, 255])
        #expect(pixel(image, 3, 1)[3] == 0)
        #expect(pixel(image, 1, 0)[3] == 0)
    }

    @Test("Transparency in the picture and the element's opacity both reach the result")
    func transparency() throws {
        let image = try render(
            20, 10,
            "<image width=\"20\" height=\"10\" preserveAspectRatio=\"none\" opacity=\"0.5\" href=\"\(greenClear)\"/>")
        #expect(pixel(image, 1, 5)[1] == 255)
        #expect(abs(pixel(image, 1, 5)[3] - 128) <= 1)
        #expect(pixel(image, 18, 5)[3] == 0)
    }

    @Test("JPEG decodes too")
    func jpeg() throws {
        let image = try render(8, 8, "<image width=\"8\" height=\"8\" href=\"\(green8)\"/>")
        let center = pixel(image, 4, 4)
        #expect(center[0] < 20 && abs(center[1] - 200) < 10 && center[2] < 20 && center[3] == 255)
    }

    @Test("A drawn picture is not reported; a file reference still is, and is outlined")
    func diagnostics() throws {
        let drawn = try document(
            10, 10, "<image width=\"10\" height=\"10\" href=\"\(redBlue)\"/>")
        #expect(drawn.diagnostics.isEmpty)
        let file = try document(10, 10, #"<image width="10" height="10" href="photo.png"/>"#)
        #expect(file.diagnostics.map(\.description).contains { $0.contains("only data: URIs") })
        let image = file.rasterize(width: 10, height: 10)
        #expect(pixel(image, 0, 5) == [255, 0, 255, 255])
    }

    @Test("data: URIs, base64 and percent-encoded")
    func dataURIs() {
        #expect(SVGBuilder.dataURIBytes("data:text/plain;base64,SGk=") == Array("Hi".utf8))
        #expect(SVGBuilder.dataURIBytes("data:,a%20b") == Array("a b".utf8))
        #expect(SVGBuilder.dataURIBytes("photo.png") == nil)
    }
}
