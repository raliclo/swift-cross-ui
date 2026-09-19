#if canImport(MetalKit)
    import Metal
    import MetalKit
    import SwiftCrossUI
    import simd

    /// The renderer behind ``BackendFeatures/Mesh3DViews`` on AppKit and UIKit.
    ///
    /// **One target, two backends, and that is the point.** `MTKView` is the same
    /// MetalKit class on macOS and iOS, so the shaders, the buffer packing and the
    /// camera arithmetic are written once. Writing them twice is how two backends
    /// start disagreeing about what a mesh looks like, which is the divergence this
    /// tree spent the week of 2026-09-17 removing from popovers, accessibility
    /// names and gesture placement.
    ///
    /// AppKit 與 UIKit 上 ``BackendFeatures/Mesh3DViews`` 背後的 renderer。
    ///
    /// **一個 target、兩個 backend,而那正是重點。** `MTKView` 在 macOS 與 iOS 上是 MetalKit 的同一個類別,
    /// 因此著色器、buffer 打包與相機運算只寫一次。寫兩次正是兩個 backend 開始對「一個 mesh 該長什麼樣」
    /// 各說各話的起點——而那正是 2026-09-17 那一週,這棵樹從 popover、無障礙名稱與手勢位置上移除的分歧。
    public final class Mesh3DMetalView: MTKView {
        private var commandQueue: MTLCommandQueue?
        private var pipeline: MTLRenderPipelineState?
        private var depthState: MTLDepthStencilState?

        private var vertexBuffer: MTLBuffer?
        private var indexBuffer: MTLBuffer?

        /// Where each mesh's triangles sit inside the one shared index buffer.
        ///
        /// One draw call per mesh, because each mesh now carries its own
        /// ``Mesh3DTransform`` and a transform is a uniform, not vertex data.
        /// The alternative -- baking each transform into the vertices before
        /// upload -- would mean re-uploading every mesh on every frame anything
        /// moved, which is the cost this design exists to avoid.
        ///
        /// 每個 mesh 的三角形,落在那一份共用索引 buffer 的哪一段。
        ///
        /// 每個 mesh 一次 draw call——因為現在每個 mesh 各自帶著自己的 ``Mesh3DTransform``,而變換是
        /// uniform、不是頂點資料。另一條路——在上傳前把各自的變換烘進頂點——會變成「只要有東西動,
        /// 每一幀都要重傳每一個 mesh」,而那正是這個設計要避開的代價。
        private var meshRanges: [(offset: Int, count: Int)] = []

        /// What was last uploaded, so a scene that only moves its camera does not
        /// re-upload its geometry every frame.
        ///
        /// The comparison is on the meshes alone: `Mesh3DScene` is `Equatable`,
        /// and comparing the whole scene would also compare the camera, which
        /// changes on exactly the frames this is trying to skip.
        ///
        /// **It compares GEOMETRY, not meshes, and that distinction is the
        /// point of putting the transform in the protocol.** A `Mesh3D` is
        /// `Equatable` including its ``Mesh3DTransform``, so comparing whole
        /// meshes would find a spinning cube different on every frame and
        /// re-upload bytes that did not change. Vertices and indices are what
        /// live in the buffers; the transform is a uniform. P72 spins its cube
        /// at 60 Hz and this uploads exactly once.
        ///
        /// 上一次上傳的內容,好讓「只動相機」的場景不必每幀重傳幾何資料。
        ///
        /// 此處只比較 mesh:`Mesh3DScene` 是 `Equatable`,而比較整個場景會連相機一起比——而相機正好在
        /// 「這段程式想跳過的那些幀」上改變。
        ///
        /// **P72 不是那支會走到「跳過」的 app,而說它是,會是一個「聽起來有用」的錯誤說法。** P72 是以
        /// 變換頂點來讓立方體自轉的,因此它的 mesh 每一幀都不同,而這裡每一幀都重新上傳——無論如何,那也是
        /// 更該先被測到的路徑:一個無法接受新幾何的 renderer,不算 renderer。「跳過」會發生在
        /// 「一次 commit 沒有改變幾何」的時候;在 P72 裡,那就是它的動作檔所按下的那兩個按鈕。
        private var uploadedGeometry: [([Mesh3DVertex], [UInt32])] = []

        private var scene = Mesh3DScene()

        /// Frames this view has drawn, which is the number P72 puts on screen.
        ///
        /// **A count is the difference between "the pipeline compiles" and "the
        /// pipeline runs".** A still of a cube proves the first; two stills whose
        /// counts differ prove the second, and that distinction is what M9's
        /// gesture work turned on.
        ///
        /// 這個 view 已經畫過的幀數,也就是 P72 印在畫面上的那個數字。
        ///
        /// **一個計數,是「pipeline 編得過」與「pipeline 真的在跑」之間的差別。** 一張立方體的靜止畫面
        /// 只證明前者;兩張計數不同的畫面才證明後者——而那正是 M9 手勢那件事上的同一個分野。
        public private(set) var framesDrawn = 0

        /// Called after each frame, on the main actor, so an application can show
        /// the count without polling.
        /// 每一幀之後在 main actor 上被呼叫,讓應用程式不必輪詢就能顯示那個計數。
        public var onFrame: (@MainActor (Mesh3DFrameInfo) -> Void)?

        /// The device's name, taken once: `MTLDevice.name` is a string this view
        /// has no reason to re-read sixty times a second.
        /// 裝置名稱,只取一次:`MTLDevice.name` 是一個沒有理由每秒重讀六十次的字串。
        private let rendererName: String

        public init(device: MTLDevice) {
            rendererName = "Metal (\(device.name))"
            super.init(frame: .zero, device: device)
            commandQueue = device.makeCommandQueue()
            colorPixelFormat = .bgra8Unorm
            depthStencilPixelFormat = .depth32Float
            // Draw when told to, not on a timer of the view's own. The framework
            // already has `FrameClocks`, and two clocks racing is how an app ends
            // up with frames it did not ask for.
            //
            // **`enableSetNeedsDisplay` is the line that does it; `isPaused` is
            // along for the ride.** With `enableSetNeedsDisplay = true` the view
            // draws only on a display request and ignores `isPaused` and
            // `preferredFramesPerSecond` entirely. Measured on 2026-09-19 with
            // P72's action file, which reads the frame count 1.5 seconds after
            // the frame clock is stopped:
            //
            //   isPaused = false, enableSetNeedsDisplay = true   ->  1 frame
            //   isPaused = false, enableSetNeedsDisplay = false  ->  90 frames
            //
            // The first of those was run expecting it to fail and it did not,
            // which is the only reason the right line is named here.
            //
            // 由外部要求時才畫,而不是由這個 view 自己的計時器驅動。框架本來就有 `FrameClocks`,
            // 而兩個時鐘互相競速,正是一支 app 拿到「它沒有要求過的幀」的原因。
            //
            // **真正起作用的是 `enableSetNeedsDisplay`;`isPaused` 只是順帶。** 當
            // `enableSetNeedsDisplay = true` 時,這個 view 只在收到顯示要求時繪製,並且完全忽略
            // `isPaused` 與 `preferredFramesPerSecond`。2026-09-19 以 P72 的動作檔實測——它在
            // frame clock 停掉 1.5 秒之後讀取幀計數:
            //
            //   isPaused = false、enableSetNeedsDisplay = true   ->  1 幀
            //   isPaused = false、enableSetNeedsDisplay = false  ->  90 幀
            //
            // 上面第一項是「預期它會失敗」而跑的,結果它沒有失敗——那正是此處寫得出正確那一行的唯一理由。
            isPaused = true
            enableSetNeedsDisplay = true
            delegate = self
            buildPipeline(device: device)
        }

        @available(*, unavailable)
        required init(coder: NSCoder) {
            fatalError("Mesh3DMetalView is created in code, never from a nib")
        }

        /// Replaces the scene and asks for one frame.
        ///
        /// The background arrives already resolved, because resolving a `Color`
        /// needs the environment -- a `.system` colour asks the backend, and an
        /// adaptive one asks the colour scheme. This target has neither and is
        /// the wrong place to acquire them: the backend has both at the moment it
        /// calls this.
        ///
        /// 換掉場景,並要求畫一幀。
        ///
        /// 背景色傳進來時已經解析過了,因為解析一個 `Color` 需要 environment——`.system` 顏色要問
        /// backend,adaptive 顏色要問 color scheme。這個 target 兩者都沒有,也不該是取得它們的地方:
        /// backend 在呼叫本方法的那一刻兩者都有。
        @MainActor
        public func setScene(_ scene: Mesh3DScene, background: Color.Resolved) {
            self.scene = scene
            clearColor = MTLClearColor(
                red: Double(background.red),
                green: Double(background.green),
                blue: Double(background.blue),
                alpha: Double(background.opacity)
            )
            let geometry = scene.meshes.map { ($0.vertices, $0.indices) }
            if !geometryMatchesUpload(geometry) {
                upload(scene.meshes)
                uploadedGeometry = geometry
            }
            #if canImport(AppKit) && !targetEnvironment(macCatalyst)
                needsDisplay = true
            #else
                setNeedsDisplay()
            #endif
        }

        private func geometryMatchesUpload(
            _ geometry: [([Mesh3DVertex], [UInt32])]
        ) -> Bool {
            guard geometry.count == uploadedGeometry.count else { return false }
            for (new, old) in zip(geometry, uploadedGeometry) where
                new.0 != old.0 || new.1 != old.1
            {
                return false
            }
            return true
        }

        private func buildPipeline(device: MTLDevice) {
            // Compiled from source at run time rather than from a `.metal` file in
            // the target. SwiftPM would build that into a default library, which
            // the two backends would then have to find at run time from whichever
            // bundle they were embedded in -- and `Bundle.module` inside a library
            // that an application links statically is exactly the lookup that fails
            // on one platform and not the other. Source text has no bundle.
            //
            // 在執行期由原始碼編譯,而不是放一個 `.metal` 檔在 target 裡。那會讓 SwiftPM 建出一個 default
            // library,而兩個 backend 接著得在執行期從「它們被嵌進的那個 bundle」裡找到它——而
            // 「被 app 靜態連結的函式庫裡的 `Bundle.module`」正是那種「在某個平台上找不到、在另一個上沒事」
            // 的查找。原始碼文字沒有 bundle 問題。
            guard let library = try? device.makeLibrary(source: Self.shaderSource, options: nil)
            else { return }

            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "mesh3d_vertex")
            descriptor.fragmentFunction = library.makeFunction(name: "mesh3d_fragment")
            descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
            descriptor.depthAttachmentPixelFormat = depthStencilPixelFormat
            pipeline = try? device.makeRenderPipelineState(descriptor: descriptor)

            let depth = MTLDepthStencilDescriptor()
            depth.depthCompareFunction = .less
            depth.isDepthWriteEnabled = true
            depthState = device.makeDepthStencilState(descriptor: depth)
        }

        private func upload(_ meshes: [Mesh3D]) {
            guard let device else { return }

            // The meshes are concatenated into one pair of buffers, with each
            // mesh's indices shifted by the vertices already written. A draw call
            // per mesh would also work and would cost a call per mesh per frame;
            // this costs one addition per index, once per upload.
            //
            // 所有 mesh 被串接進同一組 buffer,而每個 mesh 的索引會依「已寫入的頂點數」位移。
            // 「每個 mesh 一次 draw call」也可行,代價是每幀每個 mesh 一次呼叫;此處的代價則是
            // 每個索引一次加法,而且只在上傳時發生一次。
            // **Nine loose floats per vertex, NOT `[Mesh3DVertex]` copied
            // wholesale, and that is a measured bug rather than a preference.**
            // `SIMD3<Float>` has a stride of 16, not 12 -- it is 16-byte aligned
            // for the vector unit -- so a `Mesh3DVertex` of three of them is 48
            // bytes with four bytes of padding after each field. The shader's
            // `VertexIn` of three `packed_float3` is 36. Uploading the Swift
            // struct hands the GPU a buffer whose every vertex is read from the
            // wrong offset, and what it draws is not a crash and not a blank
            // view: it is a cube-shaped scatter of stretched triangles in
            // interpolated colours, which looks like a broken projection matrix
            // and sends you to the wrong file. Measured 2026-09-19:
            // `MemoryLayout<Mesh3DVertex>.stride` is 48 on arm64 macOS.
            //
            // **每個頂點九個鬆散的 float,而不是把 `[Mesh3DVertex]` 整包複製過去——這是量出來的 bug,
            // 不是偏好。** `SIMD3<Float>` 的 stride 是 16 而非 12(它為了向量單元而以 16 位元組對齊),
            // 因此由三個它構成的 `Mesh3DVertex` 是 48 位元組,每個欄位後面各有四個位元組的填充;而
            // 著色器中由三個 `packed_float3` 構成的 `VertexIn` 是 36。上傳那個 Swift struct,等於交給
            // GPU 一份「每個頂點都從錯誤偏移量讀取」的 buffer,而它畫出來的東西既不是崩潰、也不是空白:
            // 是一團立方體大小、被拉長、顏色漸層的三角形散射——那看起來像投影矩陣壞了,會把你送去錯的檔案。
            // 2026-09-19 實測:在 arm64 macOS 上 `MemoryLayout<Mesh3DVertex>.stride` 是 48。
            var vertices: [Float] = []
            var indices: [UInt32] = []
            var vertexCount = 0
            meshRanges = []
            for mesh in meshes {
                let offset = UInt32(vertexCount)
                for vertex in mesh.vertices {
                    vertices += [
                        vertex.position.x,
                        vertex.position.y,
                        vertex.position.z,
                        vertex.normal.x,
                        vertex.normal.y,
                        vertex.normal.z,
                        vertex.colour.x,
                        vertex.colour.y,
                        vertex.colour.z,
                    ]
                }
                vertexCount += mesh.vertices.count
                let start = indices.count
                indices.append(contentsOf: mesh.indices.map { $0 + offset })
                // Whole triples only. A mesh whose index count is not a multiple
                // of three is a caller error `Mesh3D` documents and this will not
                // repair: inventing a vertex is worse than dropping a triangle.
                // 只取完整的三元組。索引數不是三的倍數,是 `Mesh3D` 已載明的呼叫端錯誤,此處不予修補:
                // 憑空生出一個頂點,比少畫一個三角形更糟。
                let whole = ((indices.count - start) / 3) * 3
                if whole > 0 { meshRanges.append((offset: start, count: whole)) }
            }

            guard !vertices.isEmpty, !meshRanges.isEmpty else {
                vertexBuffer = nil
                indexBuffer = nil
                meshRanges = []
                return
            }

            vertexBuffer = vertices.withUnsafeBytes { bytes in
                device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count)
            }
            indexBuffer = indices.withUnsafeBytes { bytes in
                device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count)
            }
        }

        fileprivate func render() {
            guard
                let commandQueue,
                let descriptor = currentRenderPassDescriptor,
                let drawable = currentDrawable,
                let buffer = commandQueue.makeCommandBuffer()
            else { return }

            encodeScene(into: descriptor, commandBuffer: buffer)
            buffer.present(drawable)
            buffer.commit()

            framesDrawn += 1
            let info = Mesh3DFrameInfo(
                renderer: rendererName,
                drawableSize: SIMD2(Int(drawableSize.width), Int(drawableSize.height)),
                frameCount: framesDrawn
            )
            // Delivered synchronously, not through a `Task`. `MTKView` draws on
            // the main thread, so the hop would only delay the count by a frame
            // -- and a readout that lags the picture by one frame is exactly the
            // ambiguity P72's two captures exist to remove.
            //
            // 同步送出,而不是經由 `Task`。`MTKView` 在主執行緒上繪製,因此那一跳只會讓計數
            // 慢一幀——而一個「比畫面慢一幀」的讀數,正是 P72 那兩張擷圖所要消除的那種歧義。
            MainActor.assumeIsolated { onFrame?(info) }
        }

        /// The one place the scene is turned into draw calls.
        ///
        /// **Shared by the screen and by ``snapshot()``, on purpose.** A
        /// snapshot taken through a second, separate encode path would be a
        /// picture of that path rather than of what the user is looking at, and
        /// the two would drift the first time either was touched. This is the
        /// whole value of the read-back: the bytes it returns went through the
        /// same pipeline, the same uniforms and the same buffers as the frame on
        /// screen.
        ///
        /// 場景被轉成 draw call 的唯一一個地方。
        ///
        /// **刻意由畫面與 ``snapshot()`` 共用。** 一張「經由第二條、獨立的編碼路徑」取得的快照,拍到的是
        /// 那條路徑、而不是使用者正在看的東西;而兩者會在任何一邊第一次被改動時就開始漂移。這正是這個
        /// 讀回機制的全部價值:它回傳的位元組,走的是與畫面上那一幀相同的 pipeline、相同的 uniform、
        /// 相同的 buffer。
        private func encodeScene(
            into descriptor: MTLRenderPassDescriptor,
            commandBuffer buffer: MTLCommandBuffer
        ) {
            guard
                let pipeline,
                let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor)
            else { return }

            if let vertexBuffer, let indexBuffer, !meshRanges.isEmpty {
                let viewProjection = viewProjectionMatrix()
                let light = normalize(scene.lightDirection)
                encoder.setRenderPipelineState(pipeline)
                if let depthState { encoder.setDepthStencilState(depthState) }
                encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

                for (index, range) in meshRanges.enumerated()
                    where index < scene.meshes.count
                {
                    let transform = scene.meshes[index].transform
                    var uniforms = Uniforms(
                        modelViewProjection: viewProjection * modelMatrix(transform),
                        normalMatrix: rotationMatrix(transform.rotation),
                        lightDirection: light
                    )
                    encoder.setVertexBytes(
                        &uniforms,
                        length: MemoryLayout<Uniforms>.stride,
                        index: 1
                    )
                    encoder.setFragmentBytes(
                        &uniforms,
                        length: MemoryLayout<Uniforms>.stride,
                        index: 0
                    )
                    encoder.drawIndexedPrimitives(
                        type: .triangle,
                        indexCount: range.count,
                        indexType: .uint32,
                        indexBuffer: indexBuffer,
                        indexBufferOffset: range.offset * MemoryLayout<UInt32>.stride
                    )
                }
            }

            encoder.endEncoding()
        }

        /// Draws one more frame into a texture of its own and reads the pixels
        /// back.
        ///
        /// **Not a capture of the drawable, and the reason is lifetime.** A
        /// `CAMetalDrawable`'s texture belongs to a pool that reuses it as soon
        /// as the frame is presented, so reading it afterwards returns whatever
        /// was drawn next -- intermittently, and more often on a fast machine
        /// than a slow one, which is the worst shape a defect can have. Its
        /// `framebufferOnly` is also true by default, and reading from such a
        /// texture is undefined rather than an error. An offscreen texture this
        /// view owns has neither problem.
        ///
        /// The cost is one extra frame per snapshot and a `waitUntilCompleted`.
        /// Both are correct here: a snapshot is a deliberate act, not something
        /// that happens sixty times a second.
        ///
        /// 把場景再畫一幀到一張它自己的 texture 上,然後把像素讀回來。
        ///
        /// **不是去擷取那個 drawable,理由是生命週期。** 一個 `CAMetalDrawable` 的 texture 屬於一個
        /// pool,而該 pool 在這一幀被呈現之後就會立刻重用它;因此事後去讀它,讀到的是「接下來畫的東西」
        /// ——而且是間歇性的,在快的機器上比慢的機器上更常發生,那是一個缺陷所能擁有的最糟糕形狀。
        /// 它的 `framebufferOnly` 預設也是 true,而從那樣的 texture 讀取是**未定義**、不是錯誤。
        /// 一張由這個 view 自己持有的離屏 texture,兩個問題都沒有。
        ///
        /// 代價是每次快照多畫一幀,外加一次 `waitUntilCompleted`。在這裡兩者都是對的:拍一張快照是一個
        /// 刻意的動作,不是每秒發生六十次的事。
        @MainActor
        public func snapshot() -> WidgetSnapshot? {
            let width = Int(drawableSize.width)
            let height = Int(drawableSize.height)
            guard
                width > 0, height > 0,
                let device,
                let commandQueue
            else { return nil }

            let colourDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: colorPixelFormat,
                width: width,
                height: height,
                mipmapped: false
            )
            colourDescriptor.usage = [.renderTarget, .shaderRead]
            #if os(macOS) && !targetEnvironment(macCatalyst)
                // `.managed` on macOS so `getBytes` sees what the GPU wrote; a
                // `.private` texture cannot be read from the CPU at all, and
                // `.shared` is not available for every macOS texture.
                // macOS 上用 `.managed`,好讓 `getBytes` 看得到 GPU 寫下的內容;`.private` 的 texture
                // 根本無法由 CPU 讀取,而 `.shared` 並非對每一種 macOS texture 都可用。
                colourDescriptor.storageMode = .managed
            #else
                colourDescriptor.storageMode = .shared
            #endif

            let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: depthStencilPixelFormat,
                width: width,
                height: height,
                mipmapped: false
            )
            depthDescriptor.usage = [.renderTarget]
            depthDescriptor.storageMode = .private

            guard
                let colourTexture = device.makeTexture(descriptor: colourDescriptor),
                let depthTexture = device.makeTexture(descriptor: depthDescriptor),
                let buffer = commandQueue.makeCommandBuffer()
            else { return nil }

            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = colourTexture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = clearColor
            pass.depthAttachment.texture = depthTexture
            pass.depthAttachment.loadAction = .clear
            pass.depthAttachment.clearDepth = 1
            pass.depthAttachment.storeAction = .dontCare

            encodeScene(into: pass, commandBuffer: buffer)
            #if os(macOS) && !targetEnvironment(macCatalyst)
                if let blit = buffer.makeBlitCommandEncoder() {
                    // A managed texture the GPU wrote is not visible to the CPU
                    // until it is synchronised. Without this, `getBytes` returns
                    // the texture's initial contents -- zeroes, which read as a
                    // perfectly plausible black image.
                    // GPU 寫過的 managed texture,在同步之前 CPU 是看不到的。少了這一步,`getBytes`
                    // 回傳的是那張 texture 的初始內容——全零,而那讀起來是一張完全合理的黑色影像。
                    blit.synchronize(resource: colourTexture)
                    blit.endEncoding()
                }
            #endif
            buffer.commit()
            buffer.waitUntilCompleted()

            var bgra = [UInt8](repeating: 0, count: width * height * 4)
            bgra.withUnsafeMutableBytes { raw in
                colourTexture.getBytes(
                    raw.baseAddress!,
                    bytesPerRow: width * 4,
                    from: MTLRegionMake2D(0, 0, width, height),
                    mipmapLevel: 0
                )
            }

            // The view's pixel format is `.bgra8Unorm` and `WidgetSnapshot` is
            // RGBA, so red and blue swap. Getting this wrong produces an image
            // that looks like a plausible render of a scene with different
            // colours, which is exactly the kind of wrong that survives a glance.
            // 這個 view 的像素格式是 `.bgra8Unorm`,而 `WidgetSnapshot` 是 RGBA,因此紅與藍要對調。
            // 弄錯的話,產生的會是一張「看起來像是某個換了配色的場景的合理算繪」——而那正是那種
            // 「瞄一眼看不出來」的錯。
            var rgba = bgra
            var i = 0
            while i + 3 < rgba.count {
                rgba.swapAt(i, i + 2)
                i += 4
            }
            return WidgetSnapshot(width: width, height: height, rgbaData: rgba)
        }

        private func viewProjectionMatrix() -> simd_float4x4 {
            let size = drawableSize
            let aspect = size.height > 0 ? Float(size.width / size.height) : 1
            let camera = scene.camera
            return perspective(
                fovyDegrees: camera.fieldOfView,
                aspect: aspect,
                near: camera.near,
                far: camera.far
            ) * lookAt(eye: camera.position, target: camera.target, up: camera.up)
        }

        private struct Uniforms {
            var modelViewProjection: simd_float4x4
            /// Rotation only, for the normals.
            ///
            /// **A normal is not transformed by the model matrix.** It is a
            /// direction, so translation must not touch it, and under a
            /// non-uniform scale the correct transform is the inverse transpose
            /// rather than the matrix itself -- scale a cube flat and a
            /// matrix-transformed normal stops being perpendicular to its face.
            /// Rotation is the part that is the same either way, and it is the
            /// part a normal needs, so it is sent on its own.
            ///
            /// 只有旋轉,供法線使用。
            ///
            /// **法線不是用 model 矩陣去變換的。** 它是一個方向,因此平移不得碰它;而在非均勻縮放之下,
            /// 正確的變換是**逆轉置**而不是矩陣本身——把一個立方體壓扁,用矩陣變換過的法線就不再垂直於
            /// 它所屬的面了。旋轉是兩種算法下都相同的那一部分,也正是法線需要的那一部分,因此單獨傳送。
            var normalMatrix: simd_float4x4
            var lightDirection: SIMD3<Float>
        }

        /// The shaders, as text.
        ///
        /// Lambert against one directional light plus a fixed ambient term, which
        /// is the least that makes a cube read as a cube: with no shading at all
        /// its faces are one silhouette and a still capture cannot show that it
        /// turned.
        ///
        /// 著色器,以文字形式存在。
        ///
        /// 一盞方向光的 Lambert 加上固定環境光——那是「讓一個立方體看起來像立方體」的最低限度:
        /// 完全不打光時,它的各面會是同一塊剪影,而一張靜止擷圖就無法顯示它轉過。
        private static let shaderSource = """
            #include <metal_stdlib>
            using namespace metal;

            struct VertexIn {
                packed_float3 position;
                packed_float3 normal;
                packed_float3 colour;
            };

            // float3, not packed_float3: this one mirrors a Swift struct whose
            // field IS a SIMD3, so the 16-byte slot is what the Swift side
            // writes. The vertex struct above is the opposite case and is packed
            // for the opposite reason -- see the note on the upload.
            // 此處是 float3 而非 packed_float3:它對映的 Swift struct 其欄位**就是**一個 SIMD3,
            // 因此 Swift 那一側寫入的正是那個 16 位元組的槽。上面那個頂點結構是相反的情況,
            // 並因相反的理由而採 packed——見上傳處的說明。
            struct Uniforms {
                float4x4 modelViewProjection;
                float4x4 normalMatrix;
                float3 lightDirection;
            };

            struct VertexOut {
                float4 position [[position]];
                float3 normal;
                float3 colour;
            };

            vertex VertexOut mesh3d_vertex(const device VertexIn *vertices [[buffer(0)]],
                                           constant Uniforms &uniforms [[buffer(1)]],
                                           uint id [[vertex_id]]) {
                VertexOut out;
                out.position = uniforms.modelViewProjection * float4(vertices[id].position, 1.0);
                out.normal = (uniforms.normalMatrix * float4(vertices[id].normal, 0.0)).xyz;
                out.colour = float3(vertices[id].colour);
                return out;
            }

            fragment float4 mesh3d_fragment(VertexOut in [[stage_in]],
                                            constant Uniforms &uniforms [[buffer(0)]]) {
                float3 n = normalize(in.normal);
                float3 l = normalize(-uniforms.lightDirection);
                float lambert = max(dot(n, l), 0.0);
                float3 shaded = in.colour * (0.25 + 0.75 * lambert);
                return float4(shaded, 1.0);
            }
            """
    }

    extension Mesh3DMetalView: MTKViewDelegate {
        public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        public func draw(in view: MTKView) {
            render()
        }
    }

    // MARK: - The three matrices, written out

    /// Scale, then rotate (Z, then Y, then X), then translate -- the order
    /// ``Mesh3DTransform`` documents, written in one place so that no backend
    /// can pick a different one.
    /// 先縮放、再旋轉(Z、Y、X 之序)、最後平移——即 ``Mesh3DTransform`` 所載明的順序;寫在同一個地方,
    /// 好讓沒有任何 backend 能挑一個不同的順序。
    private func modelMatrix(_ transform: Mesh3DTransform) -> simd_float4x4 {
        let s = transform.scale
        let scale = simd_float4x4(
            SIMD4(s.x, 0, 0, 0),
            SIMD4(0, s.y, 0, 0),
            SIMD4(0, 0, s.z, 0),
            SIMD4(0, 0, 0, 1)
        )
        var m = rotationMatrix(transform.rotation) * scale
        m.columns.3 = SIMD4(
            transform.translation.x,
            transform.translation.y,
            transform.translation.z,
            1
        )
        return m
    }

    /// The rotation alone, as Euler angles applied Z, then Y, then X.
    /// 只有旋轉,以 Euler 角依 Z、Y、X 之序套用。
    private func rotationMatrix(_ euler: SIMD3<Float>) -> simd_float4x4 {
        let sx = sin(euler.x)
        let cx = cos(euler.x)
        let sy = sin(euler.y)
        let cy = cos(euler.y)
        let sz = sin(euler.z)
        let cz = cos(euler.z)
        let rx = simd_float4x4(
            SIMD4(1, 0, 0, 0),
            SIMD4(0, cx, sx, 0),
            SIMD4(0, -sx, cx, 0),
            SIMD4(0, 0, 0, 1)
        )
        let ry = simd_float4x4(
            SIMD4(cy, 0, -sy, 0),
            SIMD4(0, 1, 0, 0),
            SIMD4(sy, 0, cy, 0),
            SIMD4(0, 0, 0, 1)
        )
        let rz = simd_float4x4(
            SIMD4(cz, sz, 0, 0),
            SIMD4(-sz, cz, 0, 0),
            SIMD4(0, 0, 1, 0),
            SIMD4(0, 0, 0, 1)
        )
        return rx * ry * rz
    }

    /// Right-handed look-at, the same construction three.js's `Matrix4.lookAt`
    /// makes, kept here rather than pulled from a maths package: it is eleven
    /// lines, and a dependency for eleven lines is a dependency to update.
    /// 右手系的 look-at,與 three.js `Matrix4.lookAt` 的構造相同;留在此處而不引入數學套件:
    /// 它只有十一行,而為了十一行引入相依,就是多一個要維護的相依。
    private func lookAt(
        eye: SIMD3<Float>,
        target: SIMD3<Float>,
        up: SIMD3<Float>
    ) -> simd_float4x4 {
        let forward = normalize(target - eye)
        let right = normalize(cross(forward, up))
        let trueUp = cross(right, forward)
        return simd_float4x4(
            SIMD4(right.x, trueUp.x, -forward.x, 0),
            SIMD4(right.y, trueUp.y, -forward.y, 0),
            SIMD4(right.z, trueUp.z, -forward.z, 0),
            SIMD4(-dot(right, eye), -dot(trueUp, eye), dot(forward, eye), 1)
        )
    }

    /// Perspective with Metal's depth range of [0, 1], **not** OpenGL's [-1, 1].
    ///
    /// A matrix copied from a GL tutorial renders a scene that looks right until
    /// something is behind something else, and then the depth test decides
    /// wrongly in the half of the range that got squashed. Named here because the
    /// symptom appears far from the cause.
    ///
    /// 採 Metal 的深度範圍 [0, 1],**不是** OpenGL 的 [-1, 1]。
    ///
    /// 從 GL 教學抄來的矩陣,畫出來的場景在「沒有東西擋住東西」之前都看起來正確;一旦有遮擋,
    /// 深度測試就會在被壓扁的那半個範圍裡做出錯誤判斷。此處寫明,是因為那個症狀離成因很遠。
    private func perspective(
        fovyDegrees: Float,
        aspect: Float,
        near: Float,
        far: Float
    ) -> simd_float4x4 {
        let fovy = fovyDegrees * .pi / 180
        let y = 1 / tan(fovy * 0.5)
        let x = y / max(aspect, 0.0001)
        let z = far / (near - far)
        return simd_float4x4(
            SIMD4(x, 0, 0, 0),
            SIMD4(0, y, 0, 0),
            SIMD4(0, 0, z, -1),
            SIMD4(0, 0, z * near, 0)
        )
    }
#endif
