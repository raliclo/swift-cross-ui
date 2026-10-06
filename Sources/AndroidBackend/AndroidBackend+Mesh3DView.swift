import AndroidKit
@_spi(Backends) import SwiftCrossUI

/// M10 on Android: the framework describes a scene, OpenGL ES 2.0 draws it.
///
/// **The arithmetic is not here and is not in the Kotlin either.** `Mesh3DMatrix4` in SwiftCrossUI
/// produces the model, view and projection matrices, and the Metal renderer uses the same type --
/// so the Euler order, the handedness of `lookAt` and the field of view are decided once. What
/// this file does is multiply them per mesh, flatten the result, and hand sixteen floats over the
/// JNI boundary.
///
/// **The one place the two renderers must differ, and it is a parameter rather than a copy.**
/// Metal's clip space runs z from 0 to 1 and OpenGL's from -1 to 1, so this asks for
/// ``Mesh3DDepthRange/minusOneToOne`` where `Mesh3DMetalView` asks for `.zeroToOne`. Getting that
/// wrong draws a scene that looks correct until something is behind something else.
///
/// **Vertices go across as flat floats, nine per vertex, for a reason Metal already paid for.**
/// `SIMD3<Float>` has a stride of 16 bytes, not 12; an array of three of them per vertex is 48
/// bytes where the shader expects 36, and what that produces is scattered stretched triangles
/// rather than an error. The Metal renderer carries the same note at its upload.
///
/// **Indices go across as 32 bits (2026-10-05).** They used to narrow to 16, which refused any
/// scene past 32,767 vertices in total -- every mesh shares one index space. GLES 2.0 draws
/// `GL_UNSIGNED_INT` elements when `OES_element_index_uint` is present (core in GLES 3); the Kotlin
/// side checks for it and, on a device without it, refuses triangles whose indices exceed 65,535
/// with a warning rather than truncating them, because a truncated index draws a wrong triangle.
///
/// **Lines and points are drawn from the vertex array, never lit; any mesh may skip the depth
/// test.** The same rules as `Mesh3DMetalView`, carried per mesh in `modes`, `pointSizes` and
/// `flags`. Every mesh gets an entry, empty ones included, so the per-mesh matrices line up: the
/// version that skipped meshes it could not draw still sent a matrix for each of them, shifting
/// every later mesh onto its predecessor's transform.
///
/// Android 上的 M10:框架描述一個場景,由 OpenGL ES 2.0 畫出它。
///
/// **運算不在這裡,也不在 Kotlin 那邊。** SwiftCrossUI 的 `Mesh3DMatrix4` 產生模型、視圖與投影矩陣,
/// 而 Metal renderer 用的是同一個型別——因此 Euler 順序、`lookAt` 的慣用手系與視野角只被決定一次。
/// 本檔做的是「逐 mesh 相乘、攤平、把十六個 float 交過 JNI 邊界」。
///
/// **兩個 renderer 必須不同的唯一一處,而它是一個參數、不是一份複製。** Metal 的 clip space z 從 0 到 1,
/// OpenGL 的從 -1 到 1,因此此處要的是 ``Mesh3DDepthRange/minusOneToOne``,而 `Mesh3DMetalView`
/// 要的是 `.zeroToOne`。選錯的話,畫出來的場景在「有東西擋住東西」之前都看起來正確。
///
/// **頂點以攤平的 float 送過去、每個頂點九個,理由是 Metal 已經付過的代價。** `SIMD3<Float>` 的 stride
/// 是 16 位元組而不是 12;每個頂點放三個就是 48 位元組,而 shader 期待的是 36——那產生的是四散拉長的
/// 三角形,不是一個錯誤。Metal renderer 在它的上傳處帶著同一段註記。
///
/// **索引以 32 位元送過去(2026-10-05)。** 原本收窄為 16 位元,於是整個場景超過 32,767 個頂點就被拒絕
/// ——所有 mesh 共用一個索引空間。GLES 2.0 在有 `OES_element_index_uint`(GLES 3 的核心功能)時可畫
/// `GL_UNSIGNED_INT` 元素;Kotlin 端會檢查它,在沒有它的裝置上,索引超過 65,535 的三角形會被拒絕並警告,
/// 而不是被截斷——被截斷的索引畫出的是一個錯的三角形。
///
/// **線段與點依頂點陣列繪製、永不打光;任何 mesh 都可以略過深度測試。** 規則與 `Mesh3DMetalView` 相同,
/// 以 `modes`、`pointSizes`、`flags` 逐 mesh 帶過去。每個 mesh 都有一筆,空的也算,好讓逐 mesh 的矩陣
/// 對齊:先前那個略過畫不了的 mesh 的版本,仍為每一個送出矩陣,於是後面每個 mesh 都套上了前一個的變換。
extension AndroidBackend: BackendFeatures.Mesh3DViews {
    public func createMesh3DView() -> Widget {
        Mesh3DSurfaceView(context: Self.activity).as(AndroidKit.View.self)!
    }

    public func updateMesh3DView(
        _ view: Widget,
        scene: Mesh3DScene,
        onFrame: @escaping @MainActor (Mesh3DFrameInfo) -> Void,
        environment: EnvironmentValues
    ) {
        guard let view = view.as(Mesh3DSurfaceView.self) else { return }

        var vertices: [Float] = []
        var indices: [Int32] = []
        var modes: [Int32] = []
        var starts: [Int32] = []
        var counts: [Int32] = []
        var pointSizes: [Float] = []
        var flags: [Int32] = []
        let totalVertices = scene.meshes.reduce(0) { $0 + $1.vertices.count }
        // A Java array is indexed by a 32-bit Int, and the vertex array holds nine floats each.
        // Java 陣列以 32 位元的 Int 為索引,而頂點陣列每個頂點占九個 float。
        guard totalVertices <= Int(Int32.max) / 9 else {
            logger.warning(
                """
                render warning (the app keeps running; this scene is not drawn): it has \
                \(totalVertices) vertices, past the \(Int(Int32.max) / 9) that fit one Java \
                float array at nine floats each. What to change: split the scene.
                """
            )
            return
        }
        vertices.reserveCapacity(totalVertices * 9)
        for mesh in scene.meshes {
            let base = vertices.count / 9
            for vertex in mesh.vertices {
                vertices.append(contentsOf: [
                    vertex.position.x,
                    vertex.position.y,
                    vertex.position.z,
                    vertex.normal.x,
                    vertex.normal.y,
                    vertex.normal.z,
                    vertex.colour.x,
                    vertex.colour.y,
                    vertex.colour.z,
                ])
            }
            // Whole groups only, as on Metal: the remainder of the triangle indices, or an odd last
            // line vertex, is not drawn rather than repaired.
            // 只畫完整的組,與 Metal 相同:三角形索引的餘數、或線段落單的最後一個頂點不畫,也不修補。
            let lit: Bool
            switch mesh.primitive {
                case .triangles:
                    let whole = mesh.indices.count - mesh.indices.count % 3
                    modes.append(0)
                    starts.append(Int32(indices.count))
                    counts.append(Int32(whole))
                    pointSizes.append(1)
                    // Truncating, not trapping: an index past the mesh's own vertices is the
                    // caller's error and draws a wrong triangle on Metal too; it must not crash.
                    // 截斷而不是中止:超出 mesh 自身頂點的索引是呼叫端的錯誤,在 Metal 上也會畫出錯的
                    // 三角形;它不該讓程式崩潰。
                    for index in mesh.indices.prefix(whole) {
                        indices.append(Int32(truncatingIfNeeded: Int(index) + base))
                    }
                    lit = mesh.lit
                case .lines:
                    modes.append(1)
                    starts.append(Int32(base))
                    counts.append(Int32(mesh.vertices.count - mesh.vertices.count % 2))
                    pointSizes.append(1)
                    lit = false
                case .points(let size):
                    modes.append(2)
                    starts.append(Int32(base))
                    counts.append(Int32(mesh.vertices.count))
                    pointSizes.append(max(size, 1))
                    lit = false
            }
            flags.append((lit ? 1 : 0) | (mesh.depthTested ? 2 : 0))
        }
        view.setGeometry(vertices, indices, modes, starts, counts, pointSizes, flags)
        view.setMeasureRenderTime(scene.measuresRenderTime)

        // The DRAWABLE's size, which is the one `setSize(of:)` has just put into the layout params
        // -- not `getWidth()`/`getHeight()`, which report the PREVIOUS layout pass. `commit` sets
        // the size and then calls this before Android has laid the view out, so on the first
        // update both read 0, `max(..., 1)` made the aspect 1, and the first frame was stretched
        // sideways until an unrelated state change ran this again (measured on P76, 2026-10-06).
        // After a resize they are one layout stale in the same way. A layout param below 1 is
        // MATCH_PARENT or WRAP_CONTENT rather than a length, and only then is the view's own size
        // used. A wrong aspect ratio does not fail; it draws an oval cube.
        // 用 **drawable** 的尺寸,也就是 `setSize(of:)` 剛放進 layout params 的那個——而不是
        // `getWidth()`/`getHeight()`,它們回報的是**上一次**排版的結果。`commit` 先設尺寸、接著在
        // Android 排版之前呼叫這裡,所以第一次更新時兩者都是 0,`max(..., 1)` 讓長寬比變成 1,第一幀
        // 被橫向拉長,直到某個無關的狀態變更再跑一次這裡(P76 實測,2026-10-06)。改變大小之後也同樣
        // 落後一次排版。layout param 小於 1 是 MATCH_PARENT 或 WRAP_CONTENT 而不是長度,只有那時才
        // 退回用 view 自己的尺寸。長寬比錯了不會失敗,它會畫出一個橢圓的立方體。
        let params = view.getLayoutParams()
        let paramWidth = params.map { Int($0.width) } ?? 0
        let paramHeight = params.map { Int($0.height) } ?? 0
        let width = Float(paramWidth > 0 ? paramWidth : max(Int(view.getWidth()), 1))
        let height = Float(paramHeight > 0 ? paramHeight : max(Int(view.getHeight()), 1))
        let viewProjection = Mesh3DMatrix4.viewProjection(
            camera: scene.camera,
            aspect: width / height,
            depthRange: .minusOneToOne
        )

        var mvps: [Float] = []
        var normals: [Float] = []
        for mesh in scene.meshes {
            mvps.append(contentsOf: (viewProjection * .model(mesh.transform)).elements)
            normals.append(contentsOf: Mesh3DMatrix4.rotation(mesh.transform.rotation).elements)
        }
        view.setMatrices(mvps, normals)

        let light = scene.lightDirection
        view.setLight(light.x, light.y, light.z)

        let background = scene.background.resolve(in: environment)
        view.setBackground(background.red, background.green, background.blue, background.opacity)

        view.setOnFrame(
            SwiftAction(action: {
                // **Read on the GL thread, reported on the main one.** `onFrame` is `@MainActor`
                // and this callback arrives from `onDrawFrame`, so the hop is required rather
                // than tidy; `MainActor.assumeIsolated` here would be a lie about which thread
                // this is.
                // **在 GL 執行緒上讀取、在主執行緒上回報。** `onFrame` 是 `@MainActor`,而這個
                // callback 來自 `onDrawFrame`,因此這一跳是**必要的**、不是整潔問題;此處用
                // `MainActor.assumeIsolated` 會是在「這是哪個執行緒」上說謊。
                let info = Mesh3DFrameInfo(
                    renderer: view.getRendererName(),
                    drawableSize: SIMD2(
                        Int(view.getDrawableWidth()),
                        Int(view.getDrawableHeight())
                    ),
                    frameCount: Int(view.getFrameCount()),
                    renderMicros: { let micros = view.getRenderMicros(); return micros >= 0 ? Int(micros) : nil }()
                )
                Task { @MainActor in onFrame(info) }
            })
        )

        view.redraw()
    }
}
