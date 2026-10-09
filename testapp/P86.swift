// P86: translucent meshes in a Mesh3DView -- `Mesh3D.opacity` (2026-10-10).
//
// Written for SoftPCB, whose 3D view draws the air around a board as a very
// light, highly transparent grey: the user asked for it, and an opaque air box
// hides the board it surrounds. The scene is flat, unlit and orthographic, so
// each claim is read off the screenshot as a colour:
//
//   1. BEHIND   the left RED square stays pure red. A white veil at 50% lies
//               BEHIND it: around the square the dark background turns grey,
//               and the square itself is untouched (the veil is depth-tested).
//   2. IN FRONT the right BLUE square is seen through a white veil at 50% in
//               front of it: a light blue, about (128, 128, 255) -- not pure
//               blue (the veil was not drawn) and not white (it was opaque).
//   3. NO DEPTH WRITE  a YELLOW strip at 50% lies behind that same veil, at the
//               top right. It must show as a yellowish band; if the veil wrote
//               depth the strip would be hidden and the band would be the
//               veil's plain grey.
//
// The two veils and the strip are listed FIRST in the scene, before the opaque
// squares: translucent meshes are drawn after every opaque one whatever their
// position, so claim 2 also checks that. Were they drawn in array order, the
// veil would blend over the background, and the blue square drawn afterwards
// would cover it -- pure blue.
//
// P86:Mesh3DView 裡的半透明 mesh——`Mesh3D.opacity`(2026-10-10)。為 SoftPCB 而寫：它的三維檢視把
// 電路板周圍的空氣畫成非常淺、高度透明的灰——使用者這樣要求，而且不透明的空氣盒會擋住它包住的電路板。
// 場景是平面、不打光、正交投影的，每一條判準都從截圖上讀成一個顏色：
//
//   1. 後方    左邊的**紅色**方塊保持純紅。一層 50% 的白色面紗在它**後方**:方塊周圍的深色背景變灰，
//              方塊本身不受影響(面紗有做深度測試)。
//   2. 前方    右邊的**藍色**方塊透過前方一層 50% 的白色面紗看見：淺藍，約 (128, 128, 255)——不是純藍
//              (面紗沒畫出來),也不是白(面紗不透明)。
//   3. 不寫深度 右上方有一條 50% 的**黃色**帶，位在同一層面紗之後。它必須呈現為帶黃的一條；若面紗寫入了
//              深度，黃帶會被擋住，那一條就只是面紗本身的灰。
//
// 兩層面紗與黃帶在場景中**排在最前面**、在不透明方塊之前：半透明 mesh 不論位置都在所有不透明 mesh 之後
// 才畫，因此第 2 條同時檢查這件事。若依陣列順序畫，面紗會與背景混合，之後畫的藍色方塊會蓋過它——純藍。

import DefaultBackend
import Foundation
@_spi(Backends) import SwiftCrossUI

enum P86Scene {
    /// One flat rectangle facing the camera. / 一個面向相機的平面矩形。
    static func quad(
        x: ClosedRange<Float>, y: ClosedRange<Float>, z: Float, colour: SIMD3<Float>,
        opacity: Float = 1
    ) -> Mesh3D {
        let corners: [SIMD3<Float>] = [
            SIMD3(x.lowerBound, y.lowerBound, z), SIMD3(x.upperBound, y.lowerBound, z),
            SIMD3(x.upperBound, y.upperBound, z), SIMD3(x.lowerBound, y.upperBound, z),
        ]
        return Mesh3D(
            vertices: corners.map {
                Mesh3DVertex(position: $0, normal: SIMD3(0, 0, 1), colour: colour)
            },
            indices: [0, 1, 2, 0, 2, 3],
            lit: false,
            opacity: opacity
        )
    }

    static let white = SIMD3<Float>(1, 1, 1)

    static let scene = Mesh3DScene(
        meshes: [
            // Translucent first on purpose (see the header). / 刻意把半透明的排在前面(見檔頭)。
            quad(x: 0.0...1.0, y: -0.9...0.9, z: 0.5, colour: white, opacity: 0.5),
            quad(x: 0.2...1.0, y: 0.55...0.85, z: 0.3, colour: SIMD3(1, 1, 0), opacity: 0.5),
            quad(x: -1.0...0.0, y: -0.9...0.9, z: -0.5, colour: white, opacity: 0.5),
            quad(x: -0.9...(-0.1), y: -0.4...0.4, z: 0, colour: SIMD3(1, 0, 0)),
            quad(x: 0.1...0.9, y: -0.4...0.4, z: 0, colour: SIMD3(0, 0, 1)),
        ],
        camera: Mesh3DCamera(
            position: SIMD3(0, 0, 5),
            target: SIMD3(0, 0, 0),
            fieldOfView: 45,
            projection: .orthographic(height: 2.2)
        ),
        background: Color(red: 0.1, green: 0.1, blue: 0.12)
    )
}

@main
struct P86App: App {
    var body: some Scene {
        WindowGroup("P86 translucent meshes") {
            #hotReloadable {
                P86RootView()
            }
        }
        .defaultSize(width: 460, height: 640)
    }
}

struct P86RootView: View {
    @Environment(\.backend) var backend

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("P86: translucent meshes (Mesh3D.opacity)")
                .font(.system(size: 17))
            Text(
                "mesh view supported: "
                    + "\(backend is any BackendFeatures.Mesh3DViews ? "yes" : "NO")"
            )
            Mesh3DView(P86Scene.scene)
                .frame(width: 340, height: 340)
            Text("1 left: pure red square, grey veil around it")
            Text("2 right: light blue through a white veil")
            Text("3 top right: a yellowish band behind the veil")
            Text("fail: pure blue, white square, or no yellow band")
        }
        .padding(16)
    }
}
