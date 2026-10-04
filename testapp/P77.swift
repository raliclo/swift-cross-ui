// P77: one triangle mesh past 1,000,000 vertices, drawn with 32-bit indices
// (M10 follow-up, Android GLES option B, 2026-10-05).
//
// queue.md's acceptance for the GLES path asks for "a mesh past 1,000,000
// vertices with no missing or crossed triangles". P76's helix is lines, which
// need no indices, so it cannot show this; this does.
//
// A 1001 x 1001 vertex grid (1,002,001 vertices, 2,000,000 triangles, indices
// up to 1,002,000) filling the view under an orthographic camera, unlit, red
// rising left to right and green rising bottom to top, on a BLACK background.
// What the screenshot must show:
//
//   - one smooth gradient filling the square, corner to corner;
//   - NO black hole anywhere in it (a missing triangle shows the background);
//   - NO streak or sliver crossing it (an index narrowed to 16 bits points at a
//     vertex 65,536 places away, which draws a long thin triangle across the
//     grid; everything past row 65 depends on indices above 65,535).
//
// Before 2026-10-05 AndroidBackend refused any scene past 32,767 vertices, so
// on Android the view stayed empty with a render warning in the log -- that is
// the failure this distinguishes.
//
// P77:一個超過 1,000,000 個頂點的三角形 mesh,以 32 位元索引繪製(M10 後續,Android GLES 做法 B,
// 2026-10-05)。
//
// queue.md 對 GLES 路徑的驗收要求「一個超過 1,000,000 個頂點的 mesh,沒有缺漏或交錯的三角形」。P76 的
// 螺旋是線段,不需要索引,因此證明不了這件事;這支可以。
//
// 1001 x 1001 的頂點網格(1,002,001 個頂點、2,000,000 個三角形、索引最大 1,002,000),在正交相機下填滿
// 視圖,不打光,紅色由左往右漸增、綠色由下往上漸增,背景為**黑色**。截圖必須顯示:
//
//   - 一片平滑的漸層,從角落到角落填滿正方形;
//   - 其中**沒有**任何黑洞(缺一個三角形就會露出背景);
//   - **沒有**任何橫越它的條紋或細片(被收窄成 16 位元的索引會指向 65,536 格外的頂點,於是畫出一個
//     橫跨網格的細長三角形;第 65 列之後的一切都依賴大於 65,535 的索引)。
//
// 2026-10-05 之前,AndroidBackend 會拒絕任何超過 32,767 個頂點的場景,因此在 Android 上這個視圖會是空的,
// log 裡有一則 render warning——那正是這支要區分出來的失敗。

import DefaultBackend
import Foundation
@_spi(Backends) import SwiftCrossUI

enum P77Scene {
    static let side = 1001

    /// Built once and kept, so a re-render compares shared storage instead of rebuilding
    /// two million triangles (see `Mesh3D`'s note on keeping the arrays).
    /// 只建一次並保留,好讓重新繪製時比對的是共用的儲存空間,而不是重建兩百萬個三角形
    /// (見 `Mesh3D` 關於保留陣列的說明)。
    static let grid: Mesh3D = {
        let n = side
        var vertices: [Mesh3DVertex] = []
        vertices.reserveCapacity(n * n)
        let step = 2 / Float(n - 1)
        for row in 0..<n {
            for column in 0..<n {
                let u = Float(column) / Float(n - 1)
                let v = Float(row) / Float(n - 1)
                vertices.append(
                    Mesh3DVertex(
                        position: SIMD3(-1 + Float(column) * step, -1 + Float(row) * step, 0),
                        normal: SIMD3(0, 0, 1),
                        colour: SIMD3(0.25 + 0.75 * u, 0.25 + 0.75 * v, 0.3)
                    )
                )
            }
        }
        var indices: [UInt32] = []
        indices.reserveCapacity((n - 1) * (n - 1) * 6)
        for row in 0..<(n - 1) {
            for column in 0..<(n - 1) {
                let a = UInt32(row * n + column)
                let b = a + 1
                let c = a + UInt32(n)
                let d = c + 1
                indices += [a, b, d, a, d, c]
            }
        }
        return Mesh3D(vertices: vertices, indices: indices, lit: false)
    }()

    static let scene = Mesh3DScene(
        meshes: [grid],
        camera: Mesh3DCamera(
            position: SIMD3(0, 0, 5),
            target: SIMD3(0, 0, 0),
            fieldOfView: 45,
            projection: .orthographic(height: 2.2)
        ),
        background: Color(red: 0, green: 0, blue: 0)
    )
}

/// The render-time button's label, and the guard that keeps showing it from redrawing forever.
/// A measured frame updates the label once; that update redraws the view, and the frame it draws
/// is not shown, so the loop stops there. Off by default (`Mesh3DScene.measuresRenderTime`).
/// 算繪時間按鈕的標籤,以及讓「顯示它」不會無止盡重繪的防護。量到一幀就更新標籤一次;那次更新會讓
/// view 重畫,而它畫出的那一幀不再顯示,迴圈到此為止。預設關閉(`Mesh3DScene.measuresRenderTime`)。
final class P77RenderTime: SwiftCrossUI.ObservableObject {
    static let shared = P77RenderTime()
    @SwiftCrossUI.Published var on = false
    @SwiftCrossUI.Published var label = "Render: off"
    private var ownRedraw = false

    func record(_ info: Mesh3DFrameInfo) {
        guard let micros = info.renderMicros else { return }
        if ownRedraw {
            ownRedraw = false
            return
        }
        ownRedraw = true
        label = "\(micros) µs"
    }

    func toggle() {
        on.toggle()
        ownRedraw = false
        label = on ? "… µs" : "Render: off"
    }
}

@main
struct P77App: App {
    var body: some Scene {
        WindowGroup("P77 one million vertices") {
            #hotReloadable {
                P77RootView()
            }
        }
        .defaultSize(width: 520, height: 720)
    }
}

struct P77RootView: View {
    @Environment(\.backend) var backend
    @ObservedObject var renderTime = P77RenderTime.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("P77: one mesh past 1,000,000 vertices")
                .font(.system(size: 17))
            Text(
                "mesh view supported: "
                    + "\(backend is any BackendFeatures.Mesh3DViews ? "yes" : "NO")"
            )
            Text(
                "grid: \(P77Scene.side * P77Scene.side) vertices, "
                    + "\((P77Scene.side - 1) * (P77Scene.side - 1) * 2) triangles"
            )
            Text("largest index: \(P77Scene.side * P77Scene.side - 1) (16-bit limit 65,535)")
            Mesh3DView(
                {
                    var scene = P77Scene.scene
                    scene.measuresRenderTime = renderTime.on
                    return scene
                }(),
                onFrame: { info in P77RenderTime.shared.record(info) }
            )
                .frame(width: 340, height: 340)
            Text("pass: one smooth red-green gradient, no black hole, no streak")
            Text("fail: empty view, holes, or slivers crossing the square")
            Button(renderTime.label) { P77RenderTime.shared.toggle() }
                .frame(width: 130, alignment: .leading)
        }
        .padding(16)
    }
}
