import AppKit

// The bounding box of the pixels of one colour in a PNG, and of the dark area
// around them -- a stand-in for PIL, which this Mac's python3 does not have.
//
//   swiftc -O -o /tmp/colour_bbox testapp/test_support/measure/colour_bbox.swift
//   /tmp/colour_bbox 102 230 255 capture1.png capture2.png ...
//   /tmp/colour_bbox 102 230 255 --tolerance 80 capture.png
//   /tmp/colour_bbox --sample capture.png      the commonest saturated colours
//
// **Sample first.** What reaches the screen is not the scene's colour: P95's circle
// is (0.4, 0.9, 1), i.e. 102 230 255, and its capture on GtkBackend on macOS read
// about 8 230 248 (2026-10-14), which a tolerance of 75 around 102 does not reach.
//
// A pixel counts when each channel is within the tolerance (default 75) of the
// colour given: thin lines are antialiased and lose saturation at their edges.
// "drawable" is the box of the rows and columns that are more than half near-black
// opaque pixels (each channel below 50), the mesh views' default background -- a
// stray dark border pixel does not widen it.
// Written 2026-10-14 for P95 (todo.md P2): a circle facing the camera must have
// a box ratio of 1 at every window size.
//
// 一張 PNG 中某一種顏色像素的外框，以及其周圍深色區域的外框——用來代替 PIL(這台 Mac 的 python3 沒有它)。
// **先取樣。** 螢幕上的顏色不等於場景的顏色:P95 的圓是 (0.4, 0.9, 1),即 102 230 255,而它在 macOS 上
// GtkBackend 的擷圖約為 8 230 248(2026-10-14),以 102 為中心、容差 75 抓不到。每個色版都落在指定顏色的容差內
// (預設 75)才算數：細線有反鋸齒，邊緣會褪色。「drawable」是超過一半為近黑不透明像素(每個色版低於 50)的那些
// 列與欄所圍成的外框，也就是 mesh view 的預設背景;零星的深色邊框像素不會撐大它。2026-10-14 為 P95(todo.md
// P2)而寫：正對鏡頭的圓，在每一種視窗尺寸下外框比例都必須是 1。

var arguments = Array(CommandLine.arguments.dropFirst())
var tolerance = 75
let sampling = arguments.first == "--sample"
if sampling { arguments.removeFirst() }
if let flag = arguments.firstIndex(of: "--tolerance"), flag + 1 < arguments.count {
    tolerance = Int(arguments[flag + 1]) ?? tolerance
    arguments.removeSubrange(flag...(flag + 1))
}
func load(_ path: String) -> (pixels: [UInt8], width: Int, height: Int)? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return nil }
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return (pixels, width, height)
}

if sampling {
    // Saturated: the largest channel at least 60 above the smallest. Bucketed by 16.
    // 飽和：最大色版比最小色版高至少 60。以 16 為一格。
    for path in arguments {
        guard let (pixels, _, _) = load(path) else { print("\(path): unreadable")
            continue }
        var buckets: [String: Int] = [:]
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let channels = [pixels[i], pixels[i + 1], pixels[i + 2]].map(Int.init)
            guard channels.max()! - channels.min()! >= 60 else { continue }
            buckets[channels.map { String($0 / 16 * 16 + 8) }.joined(separator: " "), default: 0] +=
                1
        }
        print(URL(fileURLWithPath: path).lastPathComponent)
        for (colour, count) in buckets.sorted(by: { $0.value > $1.value }).prefix(8) {
            print("  \(colour)  \(count) pixels")
        }
    }
    exit(0)
}

guard arguments.count >= 4, let red = Int(arguments[0]), let green = Int(arguments[1]),
      let blue = Int(arguments[2])
else {
    print("usage: colour_bbox R G B [--tolerance N] image.png ...")
    exit(2)
}

for path in arguments.dropFirst(3) {
    let name = URL(fileURLWithPath: path).lastPathComponent
    guard let (pixels, width, height) = load(path) else {
        print("\(name): unreadable")
        continue
    }

    var darkInRow = [Int](repeating: 0, count: height)
    var darkInColumn = [Int](repeating: 0, count: width)
    for y in 0..<height {
        for x in 0..<width {
            let i = (y * width + x) * 4
            if pixels[i + 3] == 255, pixels[i] < 50, pixels[i + 1] < 50, pixels[i + 2] < 50 {
                darkInRow[y] += 1
                darkInColumn[x] += 1
            }
        }
    }
    let darkRows = darkInRow.indices.filter { darkInRow[$0] * 2 > width }
    let darkColumns = darkInColumn.indices.filter { darkInColumn[$0] * 2 > height }

    var box = (x0: width, x1: -1, y0: height, y1: -1)
    var count = 0
    for y in 0..<height {
        for x in 0..<width {
            let i = (y * width + x) * 4
            if abs(Int(pixels[i]) - red) <= tolerance, abs(Int(pixels[i + 1]) - green) <= tolerance,
               abs(Int(pixels[i + 2]) - blue) <= tolerance
            {
                count += 1
                box = (min(box.x0, x), max(box.x1, x), min(box.y0, y), max(box.y1, y))
            }
        }
    }

    let drawable =
        darkRows.isEmpty || darkColumns.isEmpty
            ? "none"
            : "\(darkColumns.last! - darkColumns.first! + 1)x\(darkRows.last! - darkRows.first! + 1)"
    guard count > 0 else {
        print("\(name) image \(width)x\(height): no pixels of that colour; drawable \(drawable)")
        continue
    }
    let boxWidth = box.x1 - box.x0 + 1
    let boxHeight = box.y1 - box.y0 + 1
    let ratio = String(format: "%.3f", Double(boxWidth) / Double(boxHeight))
    print(
        "\(name) image \(width)x\(height) colour x \(box.x0)..\(box.x1) y \(box.y0)..\(box.y1)"
            + " = \(boxWidth)x\(boxHeight) ratio \(ratio) pixels \(count) drawable \(drawable)"
    )
}
