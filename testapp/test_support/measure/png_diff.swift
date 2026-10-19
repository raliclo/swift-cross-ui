// png_diff.swift -- how far apart two PNG captures of the same window are.
//
//   swiftc -O -o /tmp/png_diff testapp/test_support/measure/png_diff.swift
//   /tmp/png_diff a.png b.png [tolerance]
//
// Prints the size, the number of pixels whose largest channel difference is
// above `tolerance` (default 8 of 255), the largest difference anywhere, and the
// box around the differing pixels. Written to compare GtkBackend's shapes drawn
// through cairo and as GSK nodes (SCUI_GTK_CAIRO_PATHS=1 and unset), where
// antialiasing differs by a few levels along edges and anything more is a shape
// drawn differently.
//
// png_diff.swift——同一個視窗的兩張 PNG 擷圖相差多少。印出尺寸、最大通道差超過 `tolerance`(預設 255 中的 8)的
// 像素數、任一處的最大差值，以及相異像素的外框。寫來比較 GtkBackend 經由 cairo 與以 GSK 節點畫出的形狀
// (SCUI_GTK_CAIRO_PATHS=1 與未設定):反鋸齒在邊緣差幾個色階，超過的就是畫法不同的形狀。

import CoreGraphics
import Foundation
import ImageIO

func pixels(_ path: String) -> (width: Int, height: Int, bytes: [UInt8])? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return nil }
    let width = image.width
    let height = image.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
        guard
            let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    return drawn ? (width, height, bytes) : nil
}

let arguments = CommandLine.arguments
guard arguments.count >= 3, let a = pixels(arguments[1]), let b = pixels(arguments[2]) else {
    print("usage: png_diff a.png b.png [tolerance]")
    exit(2)
}
let tolerance = arguments.count > 3 ? Int(arguments[3]) ?? 8 : 8
guard a.width == b.width, a.height == b.height else {
    print("size differs: \(a.width)x\(a.height) against \(b.width)x\(b.height)")
    exit(1)
}
var over = 0
var largest = 0
var box = (minX: Int.max, minY: Int.max, maxX: -1, maxY: -1)
for y in 0..<a.height {
    for x in 0..<a.width {
        let i = (y * a.width + x) * 4
        var difference = 0
        for channel in 0..<4 {
            difference = max(difference, abs(Int(a.bytes[i + channel]) - Int(b.bytes[i + channel])))
        }
        largest = max(largest, difference)
        if difference > tolerance {
            over += 1
            box = (min(box.minX, x), min(box.minY, y), max(box.maxX, x), max(box.maxY, y))
        }
    }
}
let boxText = over == 0 ? "none" : "\(box.minX),\(box.minY) to \(box.maxX),\(box.maxY)"
print("\(a.width)x\(a.height): \(over) pixels over \(tolerance), largest difference \(largest), box \(boxText)")
