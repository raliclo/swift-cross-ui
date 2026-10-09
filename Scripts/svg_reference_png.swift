// Renders an SVG with macOS's own SVG support (NSImage, i.e. CoreSVG) into a
// PNG, as the reference that SwiftCrossUI's SVG renderer is compared with.
// Test-only: nothing in the library uses it.
//
//   swift Scripts/svg_reference_png.swift in.svg out.png 640 400
//   zsh Scripts/svg_golden.zsh          # every fixture in Tests/SwiftCrossUITests/SVGFixtures
//
// CoreSVG is a reference, not the truth. Measured 2026-10-09 on macOS 27 with
// the feature sheet: it ignores a compound selector (`rect.swatch`), draws
// `hsl()` in the wrong colour and `#rrggbbaa` as black. The golden feature
// sheet therefore uses only what CoreSVG draws correctly; those three are
// covered by unit tests instead.
//
// 以 macOS 自己的 SVG 支援(NSImage,也就是 CoreSVG)把 SVG 算繪成 PNG,作為 SwiftCrossUI SVG
// 算繪器的比對參考。僅供測試使用，函式庫不會用到它。
//
// CoreSVG 是參考，不是標準答案。2026-10-09 在 macOS 27 上以功能表實測：它忽略複合選擇器
// (`rect.swatch`)、把 `hsl()` 畫成錯誤的顏色、把 `#rrggbbaa` 畫成黑色。因此黃金功能表只使用
// CoreSVG 畫得正確的功能；這三項改由單元測試涵蓋。

import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 5, let width = Int(arguments[3]), let height = Int(arguments[4]) else {
    FileHandle.standardError.write(
        "usage: swift svg_reference_png.swift in.svg out.png width height\n".data(using: .utf8)!)
    exit(2)
}
guard let image = NSImage(contentsOf: URL(fileURLWithPath: arguments[1])) else {
    FileHandle.standardError.write("NSImage could not read \(arguments[1])\n".data(using: .utf8)!)
    exit(1)
}
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: width * 4, bitsPerPixel: 32)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(
    to: URL(fileURLWithPath: arguments[2]))
