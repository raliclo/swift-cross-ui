import Foundation
import Testing
@testable import SwiftCrossUI

/// Lines, points and the orthographic camera (2026-10-05).
///
/// The renderers are not testable here, but everything they share is: the
/// projection matrix both Metal and GLES multiply by, and the `.glb` a scene
/// exports. A projection that maps the near plane to the far end of the depth
/// range draws correctly until something is behind something else, so the depth
/// ends are checked for both conventions.
///
/// 線段、點與正交相機(2026-10-05)。
///
/// renderer 在這裡測不到,但它們共用的東西測得到:Metal 與 GLES 都要乘上的投影矩陣,以及場景匯出的
/// `.glb`。一個把近平面對到深度範圍遠端的投影,在「有東西擋住東西」之前都畫得正確,因此兩種慣例的
/// 深度兩端都要檢查。
@Suite("Mesh3D lines, points and orthographic projection")
struct Mesh3DTests {
    private func project(_ m: Mesh3DMatrix4, _ p: SIMD3<Float>) -> SIMD3<Float> {
        let v = m.columns.0 * p.x + m.columns.1 * p.y + m.columns.2 * p.z + m.columns.3
        return SIMD3(v.x, v.y, v.z) / v.w
    }

    @Test("Orthographic maps near and far to the ends of each depth range")
    func orthographicDepthEnds() {
        for (range, nearEnd) in [(Mesh3DDepthRange.zeroToOne, Float(0)), (.minusOneToOne, -1)] {
            let m = Mesh3DMatrix4.orthographic(
                height: 4, aspect: 2, near: 0.5, far: 10, depthRange: range)
            #expect(abs(project(m, SIMD3(0, 0, -0.5)).z - nearEnd) < 1e-6)
            #expect(abs(project(m, SIMD3(0, 0, -10)).z - 1) < 1e-6)
        }
    }

    @Test("Orthographic keeps lengths independent of depth")
    func orthographicHasNoForeshortening() {
        let m = Mesh3DMatrix4.orthographic(
            height: 4, aspect: 2, near: 0.1, far: 100, depthRange: .zeroToOne)
        // The top of the view is height/2 up, at any depth; the right edge is
        // aspect times that across. / 畫面頂端在任何深度都是 height/2;右緣是它乘上長寬比。
        for depth: Float in [-1, -50] {
            let top = project(m, SIMD3(0, 2, depth))
            let right = project(m, SIMD3(4, 0, depth))
            #expect(abs(top.y - 1) < 1e-6)
            #expect(abs(right.x - 1) < 1e-6)
        }
    }

    @Test("The camera's projection selects the matrix")
    func cameraSelectsProjection() {
        let ortho = Mesh3DCamera(projection: .orthographic(height: 4))
        let persp = Mesh3DCamera()
        let a = Mesh3DMatrix4.viewProjection(camera: ortho, aspect: 1, depthRange: .zeroToOne)
        let b = Mesh3DMatrix4.viewProjection(camera: persp, aspect: 1, depthRange: .zeroToOne)
        // w stays 1 under orthographic and becomes the view depth under perspective.
        // 正交下 w 保持 1,透視下 w 變成視圖深度。
        #expect(a.columns.3.w == 1)
        #expect(a.columns.2.w == 0)
        #expect(b.columns.3.w != 1)
        #expect(persp.projection == .perspective)
    }

    private func gltfJSON(_ scene: Mesh3DScene) throws -> [String: Any] {
        let glb = scene.glbData()
        let length = glb.subdata(in: 12..<16).withUnsafeBytes { $0.load(as: UInt32.self) }
        let json = glb.subdata(in: 20..<(20 + Int(UInt32(littleEndian: length))))
        return try #require(
            try JSONSerialization.jsonObject(with: json) as? [String: Any])
    }

    private func vertex(_ x: Float) -> Mesh3DVertex {
        Mesh3DVertex(position: SIMD3(x, 0, 0), normal: SIMD3(0, 0, 0), colour: SIMD3(1, 1, 1))
    }

    @Test("Lines and points export with their glTF mode and no indices")
    func exportModes() throws {
        let scene = Mesh3DScene(
            meshes: [
                Mesh3D(vertices: [vertex(0), vertex(1), vertex(2)], primitive: .lines),
                Mesh3D(vertices: [vertex(0), vertex(1)], primitive: .points(size: 3)),
                Mesh3D(vertices: [vertex(0), vertex(1), vertex(2)], indices: [0, 1, 2]),
            ],
            camera: Mesh3DCamera(projection: .orthographic(height: 6))
        )
        let json = try gltfJSON(scene)
        let meshes = try #require(json["meshes"] as? [[String: Any]])
        let primitives = meshes.compactMap { ($0["primitives"] as? [[String: Any]])?.first }
        #expect(primitives.map { $0["mode"] as? Int } == [1, 0, 4])
        #expect(primitives.map { $0["indices"] == nil } == [true, true, false])
        // The odd third vertex of the line list is not drawn, so it is not written.
        // 線段清單落單的第三個頂點不會被畫出,因此也不寫出。
        let accessors = try #require(json["accessors"] as? [[String: Any]])
        let lineAttributes = try #require(primitives[0]["attributes"] as? [String: Int])
        let position = try #require(lineAttributes["POSITION"])
        #expect(accessors[position]["count"] as? Int == 2)

        let camera = try #require((json["cameras"] as? [[String: Any]])?.first)
        #expect(camera["type"] as? String == "orthographic")
        let ortho = try #require(camera["orthographic"] as? [String: Double])
        #expect(ortho["ymag"] == 3)
    }

    /// Render time is measured only when asked: measuring waits for the GPU, so it is off by
    /// default (the user's decision, 2026-10-05), and an unmeasured frame says `nil`, not 0.
    /// 算繪時間只在要求時量測:量測要等 GPU,因此預設關閉(使用者 2026-10-05 的決定);沒量的幀回報
    /// `nil`,而不是 0。
    @Test("Render time is off by default and unmeasured frames report nil")
    func renderTimeOffByDefault() {
        #expect(Mesh3DScene().measuresRenderTime == false)
        let info = Mesh3DFrameInfo(renderer: "r", drawableSize: SIMD2(1, 1), frameCount: 1)
        #expect(info.renderMicros == nil)
        var scene = Mesh3DScene()
        scene.measuresRenderTime = true
        #expect(scene != Mesh3DScene(), "turning it on must change the scene, so the view updates")
    }
}
