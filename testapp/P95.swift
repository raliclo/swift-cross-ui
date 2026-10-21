// P95: a mesh view that fills its window, holding one circle that faces the camera.
//
// todo.md P2: GtkBackend baked the view-projection into each mesh's matrix when the
// scene was committed, from the widget's size then, and a static scene kept it; the
// fix (f191f46c) computes it again on every draw from the drawable's own size. P76,
// P77 and P86 give their mesh views a fixed frame, so a window resize never changes
// the drawable there and cannot show the difference. Here the view takes whatever the
// window has.
//
// Pass: at every window size the circle's bounding box is square -- width/height 1 --
// while its size follows the window's height (the field of view is vertical). A
// projection made for another aspect draws an ellipse. Each new drawable size is
// logged as "drawable WxH" to stdout and p95-mesh.log.
//
// P95:一個填滿視窗的 mesh view,裡面只有一個正對鏡頭的圓。todo.md P2:GtkBackend 在場景提交時，以當下
// widget 的尺寸把 view-projection 烘進每個 mesh 的矩陣，靜態場景就一直沿用;修正(f191f46c)改為每次繪製時以
// drawable 自己的尺寸重算。P76、P77、P86 的 mesh view 都是固定 frame,調整視窗大小不會改變 drawable,因此看不出
// 差別;這裡的 view 取得視窗給的所有空間。通過條件：在每一種視窗尺寸下，圓的外框都是正方形(寬/高為 1),大小
// 隨視窗高度改變(視野角是垂直的)。以其他長寬比做的投影會畫成橢圓。每個新的 drawable 尺寸都以
// 「drawable WxH」記到 stdout 與 p95-mesh.log。

import DefaultBackend
import Foundation
import ImageFormats
import SwiftCrossUI

@MainActor
enum P95Log {
    static var lastSize: SIMD2<Int>?
    /// SCUI_P95_GROW=1: the content changes width every 3 s and the window follows.
    /// SCUI_P95_GROW=1:內容每 3 秒改變寬度，視窗跟著改變。
    static let grow = ProcessInfo.processInfo.environment["SCUI_P95_GROW"] == "1"

    /// Appends a line to p95-mesh.log. / 在 p95-mesh.log 加一行。
    static func log(_ line: String) {
        print("[P95] \(line)")
        let directory =
            ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
                ?? FileManager.default.currentDirectoryPath
        let url = URL(fileURLWithPath: directory).appendingPathComponent("p95-mesh.log")
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    static func frame(_ info: Mesh3DFrameInfo) {
        guard info.drawableSize != lastSize else { return }
        lastSize = info.drawableSize
        log("drawable \(info.drawableSize.x)x\(info.drawableSize.y)")
    }
}

enum P95Scene {
    /// A circle of radius 1 in the z = 0 plane, as 720 line segments, in the colour
    /// P76's helix uses. / z = 0 平面上半徑 1 的圓，以 720 段線段畫成，顏色與 P76 的螺旋相同。
    /// 8x8 pixels of (0.8, 0.3, 0.25), i.e. 204 77 64, for the bitmap swatch.
    /// 8x8 個 (0.8, 0.3, 0.25) 的像素，即 204 77 64,供點陣圖色塊使用。
    static let swatchImage = ImageFormats.Image<RGBA>(
        width: 8,
        height: 8,
        bytes: Array(repeating: [204, 77, 64, 255], count: 64).flatMap { $0 }
    )

    static let scene: Mesh3DScene = {
        let segments = 720
        var vertices: [Mesh3DVertex] = []
        vertices.reserveCapacity(segments * 2)
        for s in 0..<segments {
            for k in 0..<2 {
                // In Double: Android's libc has no Float cos/sin (see P76).
                // 以 Double 計算:Android 的 libc 沒有 Float 版的 cos/sin(見 P76)。
                let angle = Double(s + k) / Double(segments) * 2 * Double.pi
                let p = SIMD3<Float>(Float(cos(angle)), Float(sin(angle)), 0)
                vertices.append(Mesh3DVertex(
                    position: p,
                    normal: .zero,
                    colour: SIMD3(0.4, 0.9, 1)
                ))
            }
        }
        // A square in the middle, unlit, in a colour whose sRGB and Display P3 readings
        // differ in every channel (queue item 16): 204 77 64 if read as sRGB.
        // 中央一個不打光的方塊，顏色在 sRGB 與 Display P3 下每個色版都不同(queue 第 16 項):以 sRGB 讀是 204 77 64。
        let swatch: [Mesh3DVertex] = [(-0.2, -0.2), (0.2, -0.2), (0.2, 0.2), (-0.2, 0.2)].map {
            Mesh3DVertex(
                position: SIMD3($0.0, $0.1, 0),
                normal: SIMD3(0, 0, 1),
                colour: SIMD3(0.8, 0.3, 0.25)
            )
        }
        return Mesh3DScene(meshes: [
            Mesh3D(vertices: vertices, primitive: .lines),
            Mesh3D(vertices: swatch, indices: [0, 1, 2, 0, 2, 3], lit: false),
        ])
    }()
}

@main
struct P95App: App {
    var body: some Scene {
        WindowGroup("P95 mesh resize") {
            #hotReloadable {
                P95View()
            }
        }
        .defaultSize(width: 520, height: 420)
        .windowResizability(P95Log.grow ? .contentSize : .automatic)
    }
}

struct P95View: View {
    @State var wide = false

    var body: some View {
        VStack(spacing: 0) {
            // The same two colours drawn by the backend's ordinary views, outside GL, to
            // tell a colour space applied to the whole window from one applied to the GL
            // area alone (queue item 16).
            // 同樣兩種顏色由 backend 的一般 view 畫出、不經過 GL,用來分辨「整個視窗套了某個色彩空間」
            // 與「只有 GL area 套了」(queue 第 16 項)。
            HStack(spacing: 0) {
                Color(red: 0.4, green: 0.9, blue: 1).frame(width: 60, height: 24)
                Color(red: 0.8, green: 0.3, blue: 0.25).frame(width: 60, height: 24)
                // The second colour again as a two-stop gradient of itself and as a bitmap: both
                // must read 204 77 64, as the swatch beside them does.
                // 第二種顏色再以「自己到自己」的漸層、以及點陣圖各畫一次：兩者都必須讀到 204 77 64,與旁邊的色塊相同。
                LinearGradient(
                    colors: [
                        Color(red: 0.8, green: 0.3, blue: 0.25),
                        Color(red: 0.8, green: 0.3, blue: 0.25)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ).frame(width: 60, height: 24)
                Image(P95Scene.swatchImage).resizable().frame(width: 60, height: 24)
                // Not in grow mode: a Spacer gives the content an unbounded maximum
                // width, so `.contentSize` had no maximum width to shrink the window
                // back to, and the window stayed 720 wide after its first growth
                // (SCUI_DEBUG_WINDOW_SIZE=1 logged maximum Int.max, 2026-10-21).
                // 成長模式下不放:Spacer 讓內容的最大寬度沒有上限，`.contentSize` 因此沒有可以把視窗
                // 縮回去的最大寬度，視窗第一次長大後就一直是 720 寬(SCUI_DEBUG_WINDOW_SIZE=1 記到最大值 Int.max,2026-10-21)。
                if !P95Log.grow {
                    Spacer()
                }
            }
            if P95Log.grow {
                // Grow mode: the window follows its content (`.contentSize`), so the
                // core resizes it through setSize(ofWindow:) -- a resize made by the
                // program rather than by a hand on the corner.
                // 成長模式：視窗跟著內容走(`.contentSize`),因此由核心經 setSize(ofWindow:) 改變它的大小——
                // 由程式而不是由手拖曳角落造成的縮放。
                Mesh3DView(P95Scene.scene, onFrame: { P95Log.frame($0) })
                    .frame(width: wide ? 720 : 360, height: 300)
                    .task {
                        while !Task.isCancelled {
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                            wide.toggle()
                            P95Log.log("content width \(wide ? 720 : 360)")
                        }
                    }
            } else {
                Mesh3DView(P95Scene.scene, onFrame: { P95Log.frame($0) })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
