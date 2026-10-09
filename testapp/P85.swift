// P85: SVG <text> drawn by each platform's own text engine (2026-10-09).
//
// The user chose this over a bundled font, for size: no font file ships in the
// library, and every script the platform has fonts for draws, Chinese included.
// The core rasterises the shapes; for each text run it asks the backend for a
// coverage mask (BackendFeatures.SVGText) and composites it with the SVG's own
// colour, opacity and paint order. Text therefore looks a little different from
// platform to platform -- each uses its own fonts -- and that is expected.
//
// Pass, per numbered line under the picture:
//   1 black text, top left
//   2 centred on the blue line           3 right edge on the blue line
//   4 serif, mono, bold and italic each look different
//   5 a blue outline with no fill        6 red Chinese, no empty boxes
//   7 green, tilted up to the right      8 grey: black at 40% opacity
//   9 the orange box covers part of 'under', the text visible through it
// Fail: magenta boxes where text should be (no text renderer), text off its
// line, or anything drawn over the orange box.
//
// P85:SVG <text> 由各平台自己的文字引擎繪製(2026-10-09)。使用者為了大小而選了這種做法，而不是打包字型：
// 程式庫裡不放字型檔，平台有字型的每一種文字都畫得出來，包括中文。核心點陣化形狀；每一段文字向 backend 要
// 一張覆蓋率遮罩(BackendFeatures.SVGText),再以 SVG 自己的顏色、不透明度與繪製順序合成。因此文字在各平台
// 之間略有差異——每個平台都用自己的字型——這是預期的。通過條件見上方各行；失敗：該有文字的地方出現洋紅色框
// (沒有文字繪製器)、文字偏離參考線，或有東西畫在橘色方塊之上。

import DefaultBackend
@_spi(Backends) import SwiftCrossUI

enum P85Fixture {
    static let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="360" height="300" viewBox="0 0 360 300">
          <rect width="360" height="300" fill="#fffbe6"/>
          <text x="10" y="30" font-size="22" fill="black">1 Hello SVG</text>
          <line x1="180" y1="40" x2="180" y2="66" stroke="#0088cc" stroke-width="1"/>
          <text x="180" y="60" font-size="18" text-anchor="middle" fill="black">2 centred</text>
          <line x1="350" y1="68" x2="350" y2="92" stroke="#0088cc" stroke-width="1"/>
          <text x="350" y="86" font-size="18" text-anchor="end" fill="black">3 end</text>
          <text x="10" y="118" font-family="serif" font-size="18" fill="black">4 serif</text>
          <text x="96" y="118" font-family="monospace" font-size="18" fill="black">mono</text>
          <text x="170" y="118" font-weight="bold" font-size="18" fill="black">Bold</text>
          <text x="232" y="118" font-style="italic" font-size="18" fill="black">Italic</text>
          <text x="10" y="152" font-size="26" fill="none" stroke="#0057d9" stroke-width="1">5 Outline</text>
          <text x="10" y="190" font-size="24" fill="#c00000">6 電路板 測試</text>
          <g transform="translate(220 196) rotate(-15)">
            <text x="0" y="0" font-size="18" fill="#007a3d">7 rotated</text>
          </g>
          <text x="10" y="228" font-size="22" fill="black" fill-opacity="0.4">8 faint 40%</text>
          <text x="10" y="270" font-size="26" fill="black">9 under</text>
          <rect x="60" y="244" width="70" height="34" fill="#ff8800" fill-opacity="0.75"/>
          <text x="250" y="292" font-size="11" fill="#666666">SwiftCrossUI P85</text>
        </svg>
        """

    // swiftlint:disable:next force_try
    static let document = try! SVGDocument(string: svg)
}

@main
struct P85SVGTextApp: App {
    var body: some Scene {
        WindowGroup("P85 SVG text") {
            #hotReloadable {
                P85View()
            }
        }
        .defaultSize(width: 420, height: 720)
    }
}

struct P85View: View {
    @Environment(\.backend) var backend

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("P85: SVG <text> by the platform's text engine")
            Text(
                "text renderer: \(backend is any BackendFeatures.SVGText ? "yes" : "NO (magenta boxes expected)")"
            )
            Image(P85Fixture.document)
                .frame(width: 360, height: 300)
            Text("1 black text, top left")
            Text("2 centred on the blue line  3 right edge on the line")
            Text("4 serif, mono, bold, italic look different")
            Text("5 blue outline, no fill  6 red Chinese, no boxes")
            Text("7 green, tilted up  8 grey (40% black)")
            Text("9 orange box over 'under', text seen through it")
        }
        .padding(12)
    }
}
