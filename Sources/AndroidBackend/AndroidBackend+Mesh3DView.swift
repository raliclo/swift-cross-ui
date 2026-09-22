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
/// **Indices narrow to `UInt16`.** GLES 2.0 has no `GL_UNSIGNED_INT` element type without the
/// `OES_element_index_uint` extension, so a mesh with more than 65,536 vertices cannot be drawn
/// this way. That is stated in the degradation message rather than silently truncated -- a
/// truncated index draws a wrong triangle, which is the failure mode this repository's rules are
/// about.
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
/// **索引收窄為 `UInt16`。** GLES 2.0 在沒有 `OES_element_index_uint` 擴充時沒有 `GL_UNSIGNED_INT`
/// 元素型別,因此超過 65,536 個頂點的 mesh 無法以這種方式繪製。那件事寫在降級訊息裡,而不是靜默地
/// 截斷——一個被截斷的索引畫出的是一個**錯的三角形**,而那正是本倉庫的規則所針對的失敗形態。
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
        var indices: [Int16] = []
        var meshStarts: [Int32] = []
        var meshCounts: [Int32] = []

        for mesh in scene.meshes {
            let base = vertices.count / 9
            guard base + mesh.vertices.count <= Int(Int16.max) else {
                logger.warning(
                    """
                    render warning (the app keeps running and the rest of the scene is drawn): \
                    a mesh would put this scene past 32,767 vertices, and AndroidBackend draws \
                    with GLES 2.0, whose element type is GL_UNSIGNED_SHORT. Narrowing the index \
                    anyway would draw a wrong triangle rather than fail. What to change: split \
                    the mesh, or add the OES_element_index_uint path to \
                    Mesh3DSurfaceView.kt.
                    """
                )
                break
            }
            meshStarts.append(Int32(indices.count))
            meshCounts.append(Int32(mesh.indices.count))
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
            for index in mesh.indices {
                indices.append(Int16(bitPattern: UInt16(truncatingIfNeeded: Int(index) + base)))
            }
        }

        view.setGeometry(vertices, indices, meshStarts, meshCounts)

        // The DRAWABLE's size, not the widget's, and on Android they are the same number of pixels
        // -- `setSize(of:)` has already put the layout's points times the density into the view.
        // A wrong aspect ratio does not fail; it draws an oval cube.
        // 用**drawable** 的尺寸而不是 widget 的;在 Android 上它們是同一個像素數——`setSize(of:)` 已經
        // 把「排版的點乘上 density」放進那個 view 了。長寬比錯了不會失敗,它會畫出一個橢圓的立方體。
        let width = Float(max(view.getWidth(), 1))
        let height = Float(max(view.getHeight(), 1))
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
                    frameCount: Int(view.getFrameCount())
                )
                Task { @MainActor in onFrame(info) }
            })
        )

        view.redraw()
    }
}
