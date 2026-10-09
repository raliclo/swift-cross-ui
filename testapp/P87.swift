// P87: SVG paint servers and effects (2026-10-10).
//
// Everything here is drawn by the core rasteriser, the same on every backend:
// gradients, clipPath, mask, pattern, markers, <image> from a data: URI and the
// filter subset. SVGPaintTests, SVGEffectsTests, SVGPatternTests,
// SVGMarkerTests, SVGImageTests and SVGFilterTests check each by pixel; this
// shows them together so a person can see them.
//
// Pass, per numbered cell:
//   1 a red-to-blue linear gradient       2 a radial gradient, white centre
//   3 a red bar fading left to right (mask)  4 the left half of a blue disc (clipPath)
//   5 a checkerboard (pattern)            6 a line with a dot at each end and
//                                           an arrow in the middle (markers)
//   7 a picture: red left, blue right     8 a blurred blue disc
//   9 a red square with a black shadow
// Fail: magenta boxes or a magenta flag in the top-left corner -- something
// was not drawn and is listed.
//
// P87:SVG 塗料伺服器與效果(2026-10-10)。這裡的一切都由核心點陣化器繪製，在每個 backend 上相同：漸層、
// clipPath、mask、pattern、標記、data: URI 的 <image> 以及濾鏡子集。各項由 SVGPaintTests 等逐像素檢查；
// 這裡把它們放在一起，讓人看得到。通過條件見上方各格；失敗：洋紅色框或左上角的洋紅色旗標——表示有東西
// 沒畫出來並被列出。

import DefaultBackend
@_spi(Backends) import SwiftCrossUI

enum P87Fixture {
    static let picture =
        "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAADklEQVR4nGP4z8AAQv8BD/kD/YURmXYAAAAASUVORK5CYII="

    static let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="360" height="360" viewBox="0 0 360 360">
          <defs>
            <linearGradient id="lin"><stop offset="0" stop-color="red"/><stop offset="1" stop-color="blue"/></linearGradient>
            <radialGradient id="rad"><stop offset="0" stop-color="white"/><stop offset="1" stop-color="#0057d9"/></radialGradient>
            <clipPath id="half"><rect x="0" y="130" width="60" height="100"/></clipPath>
            <linearGradient id="fade"><stop offset="0" stop-color="white"/><stop offset="1" stop-color="black"/></linearGradient>
            <mask id="m"><rect x="250" y="40" width="90" height="40" fill="url(#fade)"/></mask>
            <pattern id="checks" patternUnits="userSpaceOnUse" width="20" height="20">
              <rect width="10" height="10" fill="#333"/><rect x="10" y="10" width="10" height="10" fill="#333"/>
            </pattern>
            <marker id="dot" markerWidth="4" markerHeight="4" refX="2" refY="2"><circle cx="2" cy="2" r="2" fill="#c00000"/></marker>
            <marker id="arrow" markerWidth="6" markerHeight="6" refX="3" refY="3" orient="auto"><path d="M0 0 L6 3 L0 6 Z" fill="#007a3d"/></marker>
            <filter id="soft"><feGaussianBlur stdDeviation="4"/></filter>
            <filter id="shadow"><feDropShadow dx="6" dy="6" stdDeviation="2" flood-color="black" flood-opacity="0.6"/></filter>
          </defs>
          <rect width="360" height="360" fill="#fffbe6"/>
          <rect x="10" y="40" width="100" height="40" fill="url(#lin)"/>
          <circle cx="180" cy="60" r="30" fill="url(#rad)"/>
          <rect x="250" y="40" width="90" height="40" fill="#c00000" mask="url(#m)"/>
          <circle cx="60" cy="180" r="40" fill="#0057d9" clip-path="url(#half)"/>
          <rect x="130" y="150" width="100" height="60" fill="url(#checks)" stroke="#333"/>
          <polyline points="250,210 295,150 340,210" fill="none" stroke="#333" stroke-width="2"
            marker-start="url(#dot)" marker-mid="url(#arrow)" marker-end="url(#dot)"/>
          <image x="10" y="270" width="100" height="60" preserveAspectRatio="none" href="\(picture)"/>
          <circle cx="180" cy="300" r="30" fill="#0057d9" filter="url(#soft)"/>
          <rect x="275" y="275" width="50" height="50" fill="#c00000" filter="url(#shadow)"/>
        </svg>
        """

    // swiftlint:disable:next force_try
    static let document = try! SVGDocument(string: svg)
}

@main
struct P87SVGEffectsApp: App {
    var body: some Scene {
        WindowGroup("P87 SVG paint and effects") {
            #hotReloadable {
                P87View()
            }
        }
        .defaultSize(width: 420, height: 640)
    }
}

struct P87View: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("P87: SVG gradients, clip, mask, pattern, markers, image, filters")
            Text("diagnostics: \(P87Fixture.document.diagnostics.count) (pass: 0)")
            Image(P87Fixture.document)
                .frame(width: 360, height: 360)
            Text("1 red-to-blue gradient  2 radial, white centre")
            Text("3 red bar fading to the right (mask)  4 left half of a disc (clip)")
            Text("5 checkerboard  6 dots at the ends, green arrow mid")
            Text("7 picture: red left, blue right  8 blurred blue disc")
            Text("9 red square with a soft black shadow")
        }
        .padding(12)
    }
}
