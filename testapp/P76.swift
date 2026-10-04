import DefaultBackend
import Foundation
@_spi(Backends) import SwiftCrossUI

// P76: lines, points, unlit faces, overlays and an orthographic camera in a
// Mesh3DView (M10 follow-up, 2026-10-05).
//
// Written for SoftPCB, whose tab 9 draws a board with its own Metal renderer
// because Mesh3DView drew indexed triangles only: no wireframe, no node cloud,
// no flat legend colours, no highlight drawn over the geometry, and no
// projection a length can be measured in. Each of those is one claim below, and
// each is meant to be read off the screenshot:
//
//   1. LINES      red/green/blue axes and a white wire box around each cube.
//   2. POINTS     a 9x9 grid of white dots under the cubes, 5 px each.
//   3. UNLIT      the right cube's faces are flat: one colour per face with no
//                 shading, while the left cube is lit.
//   4. OVERLAY    a yellow line runs through the LEFT cube and stays visible in
//                 front of its faces; the same line through the RIGHT cube is
//                 hidden inside it except where it sticks out.
//   5. ORTHO      three upright ticks of equal length at different depths draw
//                 the same height under "orthographic" and different heights
//                 under "perspective". The button switches between them.
//   6. NO INDEX LIMIT  a helix of 120,000 line vertices -- past the 65,536 that a
//                 16-bit index can reach -- is drawn whole, as a closed ring of
//                 coils around the scene.
//
// Mesh 0 is EMPTY on purpose. Until 2026-10-05 the Metal renderer matched draw
// ranges to meshes by position and skipped meshes with no triangle, so one
// empty mesh moved every later mesh onto its predecessor's transform. If that
// comes back, the two cubes swap places or overlap.
//
// P76:Mesh3DView 中的線段、點、不打光的面、覆蓋層與正交相機(M10 後續,2026-10-05)。
//
// 為 SoftPCB 而寫:它的分頁 9 用自己的 Metal renderer 畫電路板,因為 Mesh3DView 只畫帶索引的三角形——
// 沒有線框、沒有節點點雲、沒有不打光的圖例色、沒有畫在幾何之上的高亮,也沒有能拿來量長度的投影。
// 上面每一項都是一個主張,而且都要能從截圖讀出來:
//
//   1. 線段    紅/綠/藍三軸,以及每個立方體外的白色線框。
//   2. 點      立方體下方 9x9 的白點格,每點 5 像素。
//   3. 不打光  右邊立方體的面是平的:每面一個顏色、沒有明暗;左邊的有光照。
//   4. 覆蓋層  一條黃線穿過**左邊**立方體,並且在它的面之前仍然看得見;同一條線穿過**右邊**立方體時,
//              除了露出來的兩端之外都被擋住。
//   5. 正交    三根等長、位於不同深度的直立刻度,在「orthographic」下畫成一樣高、在「perspective」下
//              畫成不同高。按鈕在兩者間切換。
//   6. 沒有索引上限  一條 120,000 個頂點的螺旋線——超過 16 位元索引能到的 65,536——完整畫出,
//              是一圈繞著場景、首尾相接的線圈。
//
// mesh 0 **刻意是空的**。2026-10-05 之前,Metal renderer 依位置把繪製範圍對到 mesh,並略過沒有三角形的
// mesh,於是一個空 mesh 會讓之後每個 mesh 套上前一個的變換。若這個問題回來,兩個立方體會對調或重疊。

enum P76Scene {
    static let helixVertexCount = 120_000

    static func cube(lit: Bool, at x: Float) -> Mesh3D {
        let h: Float = 0.5
        let faces: [(normal: SIMD3<Float>, colour: SIMD3<Float>, corners: [SIMD3<Float>])] = [
            (SIMD3(0, 0, 1), SIMD3(0.85, 0.35, 0.30),
             [SIMD3(-h, -h, h), SIMD3(h, -h, h), SIMD3(h, h, h), SIMD3(-h, h, h)]),
            (SIMD3(0, 0, -1), SIMD3(0.30, 0.55, 0.85),
             [SIMD3(h, -h, -h), SIMD3(-h, -h, -h), SIMD3(-h, h, -h), SIMD3(h, h, -h)]),
            (SIMD3(1, 0, 0), SIMD3(0.95, 0.75, 0.25),
             [SIMD3(h, -h, h), SIMD3(h, -h, -h), SIMD3(h, h, -h), SIMD3(h, h, h)]),
            (SIMD3(-1, 0, 0), SIMD3(0.30, 0.78, 0.45),
             [SIMD3(-h, -h, -h), SIMD3(-h, -h, h), SIMD3(-h, h, h), SIMD3(-h, h, -h)]),
            (SIMD3(0, 1, 0), SIMD3(0.92, 0.92, 0.95),
             [SIMD3(-h, h, h), SIMD3(h, h, h), SIMD3(h, h, -h), SIMD3(-h, h, -h)]),
            (SIMD3(0, -1, 0), SIMD3(0.45, 0.40, 0.70),
             [SIMD3(-h, -h, -h), SIMD3(h, -h, -h), SIMD3(h, -h, h), SIMD3(-h, -h, h)]),
        ]
        var vertices: [Mesh3DVertex] = []
        var indices: [UInt32] = []
        for face in faces {
            let base = UInt32(vertices.count)
            for corner in face.corners {
                vertices.append(
                    Mesh3DVertex(position: corner, normal: face.normal, colour: face.colour))
            }
            indices += [base, base + 1, base + 2, base, base + 2, base + 3]
        }
        return Mesh3D(
            vertices: vertices,
            indices: indices,
            transform: Mesh3DTransform(translation: SIMD3(x, 0, 0)),
            lit: lit
        )
    }

    static func line(
        _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ colour: SIMD3<Float>
    ) -> [Mesh3DVertex] {
        [
            Mesh3DVertex(position: a, normal: .zero, colour: colour),
            Mesh3DVertex(position: b, normal: .zero, colour: colour),
        ]
    }

    static func wireBox(centre x: Float) -> [Mesh3DVertex] {
        let h: Float = 0.56
        let white = SIMD3<Float>(1, 1, 1)
        var out: [Mesh3DVertex] = []
        let corners = (0..<8).map { i in
            SIMD3<Float>(
                x + (i & 1 == 0 ? -h : h), i & 2 == 0 ? -h : h, i & 4 == 0 ? -h : h)
        }
        for i in 0..<8 {
            for bit in [1, 2, 4] where i & bit == 0 {
                out += line(corners[i], corners[i | bit], white)
            }
        }
        return out
    }

    static let staticMeshes: [Mesh3D] = {
        var lines: [Mesh3DVertex] = []
        lines += line(.zero, SIMD3(2.2, 0, 0), SIMD3(1, 0.2, 0.2))
        lines += line(.zero, SIMD3(0, 1.6, 0), SIMD3(0.2, 1, 0.2))
        lines += line(.zero, SIMD3(0, 0, 2.2), SIMD3(0.3, 0.5, 1))
        lines += wireBox(centre: -1.1)
        lines += wireBox(centre: 1.1)
        // Three ticks 0.6 tall at z = -1.6, 0 and 1.6. / 三根 0.6 高的刻度,位於 z = -1.6、0、1.6。
        for z: Float in [-1.6, 0, 1.6] {
            lines += line(SIMD3(2.4, -0.8, z), SIMD3(2.4, -0.2, z), SIMD3(1, 1, 1))
        }

        var dots: [Mesh3DVertex] = []
        for i in 0..<9 {
            for j in 0..<9 {
                let p = SIMD3<Float>(Float(i) * 0.4 - 1.6, -0.8, Float(j) * 0.4 - 1.6)
                dots.append(Mesh3DVertex(position: p, normal: .zero, colour: SIMD3(1, 1, 1)))
            }
        }

        var helix: [Mesh3DVertex] = []
        helix.reserveCapacity(helixVertexCount)
        let segments = helixVertexCount / 2
        for s in 0..<segments {
            for k in 0..<2 {
                let t = Float(s + k) / Float(segments) * 2 * .pi
                // Typed steps rather than one expression: the 6.3.3 toolchain the Android build
                // uses could not type-check the single `SIMD3(...)` in reasonable time
                // (2026-10-05); the arithmetic is unchanged.
                // 拆成有型別的步驟而不是單一運算式：Android 建置用的 6.3.3 toolchain 無法在合理時間內
                // 推出那一個 `SIMD3(...)` 的型別（2026-10-05）；運算本身不變。
                // In Double, then narrowed once: Android's libc has no Float `cos`/`sin` overloads,
                // so `cos(t)` on a Float resolved to the Double one there and would not store.
                // 以 Double 計算、最後收窄一次：Android 的 libc 沒有 Float 版的 `cos`／`sin`，
                // Float 的 `cos(t)` 在那裡解析成 Double 版，存不回 Float。
                let angle = Double(t)
                let radius = 2.6 + 0.12 * cos(angle * 60)
                let height = 0.12 * sin(angle * 60) + 0.9
                let p = SIMD3<Float>(
                    Float(radius * cos(angle)), Float(height), Float(radius * sin(angle)))
                helix.append(Mesh3DVertex(position: p, normal: .zero, colour: SIMD3(0.4, 0.9, 1)))
            }
        }

        let yellow = SIMD3<Float>(1, 0.9, 0)
        return [
            Mesh3D(vertices: []),
            cube(lit: true, at: -1.1),
            cube(lit: false, at: 1.1),
            Mesh3D(vertices: lines, primitive: .lines),
            Mesh3D(vertices: dots, primitive: .points(size: 5)),
            Mesh3D(vertices: helix, primitive: .lines),
            // Through the right cube, depth-tested: hidden inside it.
            // 穿過右邊立方體、做深度測試:在立方體內的部分被擋住。
            Mesh3D(
                vertices: line(SIMD3(1.1, 0, -1.2), SIMD3(1.1, 0, 1.2), yellow),
                primitive: .lines
            ),
            // Through the left cube, not depth-tested, drawn last: always on top.
            // 穿過左邊立方體、不做深度測試、最後畫:永遠在最上層。
            Mesh3D(
                vertices: line(SIMD3(-1.1, 0, -1.2), SIMD3(-1.1, 0, 1.2), yellow),
                primitive: .lines,
                depthTested: false
            ),
        ]
    }()

    static func scene(orthographic: Bool) -> Mesh3DScene {
        Mesh3DScene(
            meshes: staticMeshes,
            camera: Mesh3DCamera(
                position: SIMD3(3.4, 2.6, 4.6),
                target: SIMD3(0, -0.1, 0),
                fieldOfView: 45,
                projection: orthographic ? .orthographic(height: 5.2) : .perspective
            )
        )
    }
}

/// The render-time button's label, and the guard that keeps showing it from redrawing forever.
/// A measured frame updates the label once; that update redraws the view, and the frame it draws
/// is not shown, so the loop stops there. Off by default (`Mesh3DScene.measuresRenderTime`).
/// 算繪時間按鈕的標籤,以及讓「顯示它」不會無止盡重繪的防護。量到一幀就更新標籤一次;那次更新會讓
/// view 重畫,而它畫出的那一幀不再顯示,迴圈到此為止。預設關閉(`Mesh3DScene.measuresRenderTime`)。
final class P76RenderTime: SwiftCrossUI.ObservableObject {
    static let shared = P76RenderTime()
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
struct P76App: App {
    var body: some Scene {
        WindowGroup("P76 mesh primitives") {
            #hotReloadable {
                P76RootView()
            }
        }
        .defaultSize(width: 520, height: 720)
    }
}

struct P76RootView: View {
    @State var orthographic = true
    @Environment(\.backend) var backend
    @ObservedObject var renderTime = P76RenderTime.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("P76: lines, points, unlit, overlay, orthographic")
                .font(.system(size: 17))
            Text(
                "mesh view supported: "
                    + "\(backend is any BackendFeatures.Mesh3DViews ? "yes" : "NO")"
            )
            Text("helix: \(P76Scene.helixVertexCount) line vertices (16-bit index limit 65,536)")
            // Beside the projection button, fixed width, so neither the row's height nor the
            // column's width changes and the action files' coordinates stay valid (2026-10-05).
            // 放在投影按鈕旁、固定寬度,好讓列高與欄寬都不變,動作檔的座標仍然有效(2026-10-05)。
            HStack(spacing: 10) {
                Button("Projection: \(orthographic ? "orthographic" : "perspective")") {
                    orthographic.toggle()
                }
                Button(renderTime.label) { P76RenderTime.shared.toggle() }
                    .frame(width: 130, alignment: .leading)
            }
            // No `onFrame` into `@State`: that redraws on every frame, because the
            // update it causes commits the scene and the commit asks for a frame.
            // `P76RenderTime` shows a measured frame once and skips the frame that
            // showing it causes, so the render-time readout does not loop either.
            // 不把 `onFrame` 寫進 `@State`:那會每幀重畫——它引起的更新會 commit 場景,而 commit 又要求一幀。
            // `P76RenderTime` 量到一幀只顯示一次,並略過「顯示它」所引起的那一幀,因此算繪時間的讀數也不會循環。
            Mesh3DView(
                {
                    var scene = P76Scene.scene(orthographic: orthographic)
                    scene.measuresRenderTime = renderTime.on
                    return scene
                }(),
                onFrame: { info in P76RenderTime.shared.record(info) }
            )
            .frame(width: 360, height: 300)
            Text("1 lines: RGB axes, white wire boxes")
            Text("2 points: 9x9 white dots under the cubes")
            Text("3 unlit: right cube flat, left cube shaded")
            Text("4 overlay: yellow line visible through LEFT cube only")
            Text("5 ortho: the three white ticks at right are equal height")
            Text("6 helix: a closed cyan coil ring around the scene")
        }
        .padding(16)
    }
}
