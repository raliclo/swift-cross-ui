import DebugFeatures
import Foundation
@_spi(Backends) import SwiftCrossUI
import UWP
import WinSDK
import WinSDK.DirectX.D3DCompiler
import WinUI
import WinUIInterop
@preconcurrency import WindowsFoundation

// Mesh3DViews on WinUI: Direct3D 11 into a SwapChainPanel, the WinUI way to put
// GPU output in the XAML tree (D3D11VideoInterop.swift explains why a child
// HWND does not work). The renderer mirrors GtkBackend's GL one -- same vertex
// packing (position, normal, colour; nine floats), same lighting, same draw
// modes -- with three D3D-specific parts: depth in 0...1, HLSL compiled at run
// time with D3DCompile, and points drawn as quads by a geometry shader, since
// D3D11 has no point size.
//
// WinUI 上的 Mesh3DViews:以 Direct3D 11 畫進 SwapChainPanel——把 GPU 輸出放進 XAML 樹的 WinUI 做法
// (D3D11VideoInterop.swift 說明了子 HWND 為何行不通)。renderer 與 GtkBackend 的 GL 版對應——相同的頂點打包
// (位置、法線、顏色，九個 float)、相同的光照、相同的繪製模式——另有三處 D3D 特有：深度範圍 0...1、HLSL 於執行期
// 以 D3DCompile 編譯、點由 geometry shader 畫成四邊形(D3D11 沒有點大小)。

extension WinUIBackend: BackendFeatures.Mesh3DViews {
    public func createMesh3DView() -> Widget {
        Mesh3DD3DView()
    }

    public func updateMesh3DView(
        _ view: Widget,
        scene: Mesh3DScene,
        onFrame: @escaping @MainActor (Mesh3DFrameInfo) -> Void,
        environment: EnvironmentValues
    ) {
        let view = view as! Mesh3DD3DView
        view.update(scene: scene, clearColour: scene.background.resolve(in: environment))
        view.onFrame = { [weak view] in
            guard let view else { return }
            onFrame(
                Mesh3DFrameInfo(
                    renderer: view.rendererName,
                    drawableSize: view.drawableSize,
                    frameCount: view.frameCount,
                    renderMicros: view.renderMicros
                )
            )
        }
        view.requestRender()
    }
}

/// The widget: a Canvas holding the SwapChainPanel, sized with it.
/// widget:一個裝著 SwapChainPanel 的 Canvas,兩者尺寸同步。
final class Mesh3DD3DView: WinUI.Canvas {
    private var panel: RawSwapChainPanel?
    private var renderer: D3D11MeshRenderer?
    private var renderQueued = false
    private var packed = PackedScene()
    private var scene: Mesh3DScene?
    private var clearColour = SIMD4<Float>(0, 0, 0, 1)

    private(set) var rendererName = ""
    private(set) var drawableSize = SIMD2<Int>(0, 0)
    private(set) var frameCount = 0
    private(set) var renderMicros: Int?
    var onFrame: (() -> Void)?
    /// Why nothing draws, when something failed; reported once.
    /// 失敗時說明為何什麼都沒畫;只回報一次。
    private(set) var failure: String?

    override init() {
        super.init()
        do {
            let panel = try RawSwapChainPanel()
            try panel.attach(to: self)
            let renderer = try D3D11MeshRenderer()
            self.panel = panel
            self.renderer = renderer
            rendererName = renderer.name
        } catch {
            fail("creating the Direct3D 11 view: \(error)")
        }
    }

    private var watchesSize = false

    /// Registered from the first update rather than `init`, which is not on
    /// the main actor. 從第一次更新註冊而非在 `init`,因為後者不在 main actor 上。
    @MainActor
    private func watchSize() {
        guard !watchesSize else { return }
        watchesSize = true
        sizeChanged.addHandler { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.requestRender()
            }
        }
    }

    private func fail(_ message: String) {
        guard failure == nil else { return }
        failure = message
        logger.error("Mesh3DView (WinUIBackend): \(message)")
    }

    @MainActor
    func update(scene: Mesh3DScene, clearColour: SwiftCrossUI.Color.Resolved) {
        watchSize()
        packed.update(from: scene)
        self.scene = scene
        self.clearColour = SIMD4(
            clearColour.red, clearColour.green, clearColour.blue, clearColour.opacity
        )
    }

    /// Drawn on the next turn of the main queue, so a size set by this update's
    /// layout is the one drawn at, and several updates in one turn draw once.
    /// 在主佇列下一輪才畫，讓本次更新的排版所設定的尺寸就是繪製時的尺寸，且同一輪的多次更新只畫一次。
    @MainActor
    func requestRender() {
        guard !renderQueued else { return }
        renderQueued = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.renderQueued = false
                self.renderNow(capture: false)
            }
        }
    }

    @MainActor
    @discardableResult
    private func renderNow(capture: Bool) -> (width: Int, height: Int, rgba: [UInt8])? {
        guard failure == nil, let panel, let renderer, let scene else { return nil }
        let scale = xamlRoot?.rasterizationScale ?? 1
        let width = actualWidth
        let height = actualHeight
        guard width >= 1, height >= 1 else { return nil }
        let pixels = SIMD2(
            max(Int((width * scale).rounded()), 1),
            max(Int((height * scale).rounded()), 1)
        )
        do {
            try panel.setSize(width: width, height: height)
            try renderer.resize(to: pixels, panel: panel)
            let viewProjection = Mesh3DMatrix4.viewProjection(
                camera: scene.camera,
                aspect: Float(pixels.x) / Float(pixels.y),
                depthRange: .zeroToOne
            )
            let result = try renderer.render(
                packed: packed,
                meshes: scene.meshes,
                viewProjection: viewProjection,
                light: scene.lightDirection,
                background: clearColour,
                measure: scene.measuresRenderTime,
                capture: capture
            )
            drawableSize = pixels
            renderMicros = result.micros
            frameCount += 1
            onFrame?()
            return result.capture
        } catch {
            fail("drawing a frame: \(error)")
            return nil
        }
    }

    /// The frame rendered now and read back, in device pixels, premultiplied
    /// RGBA -- what the Metal, GLES and GL mesh views return. A swap chain's
    /// content is invisible to `RenderTargetBitmap`, so this draws once more
    /// into the back buffer and copies it out before presenting.
    /// 現在繪製一幀並讀回(裝置像素、premultiplied RGBA)——與 Metal、GLES、GL 的 mesh view 回傳的相同。
    /// `RenderTargetBitmap` 看不到 swap chain 的內容，因此這裡再畫一次進 back buffer,在 present 前複製出來。
    @MainActor
    func snapshot() -> WidgetSnapshot? {
        renderNow(capture: true).map {
            WidgetSnapshot(width: $0.width, height: $0.height, rgbaData: $0.rgba)
        }
    }
}

/// The scene packed into one vertex array and one index array, with a draw
/// entry per mesh -- GtkBackend's layout. Repacked only when the geometry
/// changed: comparing arrays that share storage returns at once, so a scene
/// whose meshes keep their arrays costs nothing per frame (P77 has 1,002,001
/// vertices).
/// 整個場景打包成一個頂點陣列與一個索引陣列，每個 mesh 一筆繪製項——與 GtkBackend 的排列相同。只在幾何改變時才重新
/// 打包：比較共用儲存空間的陣列會立刻返回，因此保持陣列不變的場景每幀不花任何成本(P77 有 1,002,001 個頂點)。
struct PackedScene {
    enum Mode { case triangles, lines, points(size: Float) }
    struct Draw {
        var mode: Mode
        var start: Int
        var count: Int
    }

    private(set) var vertices: [Float] = []
    private(set) var indices: [UInt32] = []
    private(set) var draws: [Draw] = []
    private(set) var revision = 0
    private var sourceVertices: [[Mesh3DVertex]] = []
    private var sourceIndices: [[UInt32]] = []
    private var sourcePrimitives: [Mesh3DPrimitive] = []

    mutating func update(from scene: Mesh3DScene) {
        let newVertices = scene.meshes.map(\.vertices)
        let newIndices = scene.meshes.map(\.indices)
        let newPrimitives = scene.meshes.map(\.primitive)
        guard newVertices != sourceVertices || newIndices != sourceIndices
            || newPrimitives != sourcePrimitives
        else { return }
        sourceVertices = newVertices
        sourceIndices = newIndices
        sourcePrimitives = newPrimitives

        vertices = []
        indices = []
        draws = []
        vertices.reserveCapacity(newVertices.reduce(0) { $0 + $1.count } * 9)
        for mesh in scene.meshes {
            let base = vertices.count / 9
            for vertex in mesh.vertices {
                vertices.append(contentsOf: [
                    vertex.position.x, vertex.position.y, vertex.position.z,
                    vertex.normal.x, vertex.normal.y, vertex.normal.z,
                    vertex.colour.x, vertex.colour.y, vertex.colour.z,
                ])
            }
            switch mesh.primitive {
                case .triangles:
                    let whole = mesh.indices.count - mesh.indices.count % 3
                    draws.append(Draw(mode: .triangles, start: indices.count, count: whole))
                    for index in mesh.indices.prefix(whole) {
                        indices.append(UInt32(truncatingIfNeeded: Int(index) + base))
                    }
                case .lines:
                    let count = mesh.vertices.count - mesh.vertices.count % 2
                    draws.append(Draw(mode: .lines, start: base, count: count))
                case .points(let size):
                    draws.append(
                        Draw(mode: .points(size: max(size, 1)), start: base, count: mesh.vertices.count)
                    )
            }
        }
        revision += 1
    }
}

/// HLSL for the mesh: the GL shaders of gtk_mesh3d_gl.c, plus the point quad.
/// mesh 的 HLSL:gtk_mesh3d_gl.c 的 GL shader,加上點的四邊形。
private let meshShaderSource = """
    cbuffer Constants : register(b0) {
        float4x4 uMvp;
        float4x4 uNormal;
        float4 uLight;
        float4 uParams; // x: lit, y: point size in pixels, zw: viewport in pixels
    };
    struct VSIn { float3 position : POSITION; float3 normal : NORMAL; float3 colour : COLOR; };
    struct VSOut { float4 position : SV_Position; float3 normal : NORMAL; float3 colour : COLOR; };
    VSOut vs_main(VSIn input) {
        VSOut output;
        output.position = mul(uMvp, float4(input.position, 1.0));
        output.normal = mul(uNormal, float4(input.normal, 0.0)).xyz;
        output.colour = input.colour;
        return output;
    }
    [maxvertexcount(4)]
    void gs_main(point VSOut p[1], inout TriangleStream<VSOut> stream) {
        float2 extent = uParams.y / uParams.zw * p[0].position.w;
        VSOut v = p[0];
        v.position = p[0].position + float4(-extent.x, -extent.y, 0, 0); stream.Append(v);
        v.position = p[0].position + float4(-extent.x,  extent.y, 0, 0); stream.Append(v);
        v.position = p[0].position + float4( extent.x, -extent.y, 0, 0); stream.Append(v);
        v.position = p[0].position + float4( extent.x,  extent.y, 0, 0); stream.Append(v);
    }
    float4 ps_main(VSOut input) : SV_Target {
        if (uParams.x < 0.5) return float4(input.colour, 1.0);
        float3 n = normalize(input.normal);
        float3 l = normalize(-uLight.xyz);
        float lambert = max(dot(n, l), 0.0);
        return float4(input.colour * (0.25 + 0.75 * lambert), 1.0);
    }
    """

/// The constant buffer, laid out as `Constants` above (160 bytes).
/// 常數緩衝區，排列與上方 `Constants` 相同(160 位元組)。
private struct MeshConstants {
    var mvp: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)
    var normal: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)
    var light: SIMD4<Float>
    var params: SIMD4<Float>
}

private func columns(_ elements: [Float]) -> (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>) {
    (
        SIMD4(elements[0], elements[1], elements[2], elements[3]),
        SIMD4(elements[4], elements[5], elements[6], elements[7]),
        SIMD4(elements[8], elements[9], elements[10], elements[11]),
        SIMD4(elements[12], elements[13], elements[14], elements[15])
    )
}

private func release<T>(_ pointer: UnsafeMutablePointer<T>?) {
    guard let pointer else { return }
    let unknown = UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: WinSDK.IUnknown.self)
    _ = unknown.pointee.lpVtbl.pointee.Release(unknown)
}

private func asResource<T>(_ pointer: UnsafeMutablePointer<T>) -> UnsafeMutablePointer<ID3D11Resource> {
    UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: ID3D11Resource.self)
}

/// Owns the device, shaders, states, buffers and the size-dependent targets.
/// 持有裝置、shader、各種 state、緩衝區，以及隨尺寸變動的 target。
final class D3D11MeshRenderer {
    private let d3d: RawD3D11Device
    private var device: UnsafeMutablePointer<ID3D11Device> { d3d.device }
    private var context: UnsafeMutablePointer<ID3D11DeviceContext> { d3d.context }
    let name: String

    private var vertexShader: UnsafeMutablePointer<ID3D11VertexShader>?
    private var geometryShader: UnsafeMutablePointer<ID3D11GeometryShader>?
    private var pixelShader: UnsafeMutablePointer<ID3D11PixelShader>?
    private var inputLayout: UnsafeMutablePointer<ID3D11InputLayout>?
    private var constantBuffer: UnsafeMutablePointer<ID3D11Buffer>?
    private var rasterizer: UnsafeMutablePointer<ID3D11RasterizerState>?
    private var depthOn: UnsafeMutablePointer<ID3D11DepthStencilState>?
    private var depthOff: UnsafeMutablePointer<ID3D11DepthStencilState>?

    private var vertexBuffer: UnsafeMutablePointer<ID3D11Buffer>?
    private var indexBuffer: UnsafeMutablePointer<ID3D11Buffer>?
    private var uploadedRevision = -1

    private var size = SIMD2<Int>(0, 0)
    private var renderTarget: UnsafeMutablePointer<ID3D11RenderTargetView>?
    private var depthTexture: UnsafeMutablePointer<ID3D11Texture2D>?
    private var depthView: UnsafeMutablePointer<ID3D11DepthStencilView>?

    init() throws {
        let adapter = Self.preferredAdapter()
        defer { release(adapter) }
        d3d = try RawD3D11Device(adapter: adapter)
        name = Self.adapterName(of: d3d.device) + " / Direct3D 11"
        try buildPipeline()
    }

    /// The adapter to render on. The default adapter is the one driving the
    /// primary display, and that is right whenever it is real hardware. When it
    /// is Microsoft's Basic Render Driver -- WARP, the CPU rasteriser -- while a
    /// GPU sits beside it, the GPU is chosen instead: measured 2026-10-07 on a
    /// laptop whose integrated AMD adapter had dropped to the Basic Display
    /// Driver, DXGI listed "Microsoft Basic Render Driver" first and the RTX
    /// 4060 second with no outputs, so the default put every mesh on the CPU.
    /// A swap chain on another adapter still composes; DXGI copies the frames
    /// across. `-GPU 0` keeps WARP on purpose, as a no-GPU baseline.
    /// 繪製所用的介面卡。預設介面卡是驅動主要顯示器的那一張，只要它是真正的硬體就是對的。當它是微軟的 Basic Render
    /// Driver——WARP,CPU 光柵化器——而旁邊另有 GPU 時，改選 GPU:2026-10-07 在一台內顯 AMD 已退回 Basic Display Driver
    /// 的筆電上實測,DXGI 先列出「Microsoft Basic Render Driver」、再列出沒有輸出的 RTX 4060,預設因此把每個 mesh 都放在
    /// CPU 上。位於另一張介面卡的 swap chain 仍可合成，由 DXGI 跨卡複製畫面。`-GPU 0` 刻意保留 WARP,作為不用 GPU 的基準線。
    private static func preferredAdapter() -> UnsafeMutablePointer<IDXGIAdapter>? {
        var factoryIID = D3D11IID.IDXGIFactory1
        var factoryRaw: UnsafeMutableRawPointer?
        guard CreateDXGIFactory1(&factoryIID, &factoryRaw) >= 0, let factoryRaw else { return nil }
        let factory = factoryRaw.assumingMemoryBound(to: IDXGIFactory1.self)
        defer { _ = factory.pointee.lpVtbl.pointee.Release(factory) }

        let softwareVendor: UINT = 0x1414
        let wantsSoftware = DebugFeatures.gpuSelection == 0
        var defaultIsSoftware = false
        var index: UINT = 0
        while true {
            var adapter: UnsafeMutablePointer<IDXGIAdapter1>?
            guard factory.pointee.lpVtbl.pointee.EnumAdapters1(factory, index, &adapter) >= 0,
                let adapter
            else { return nil }
            var description = DXGI_ADAPTER_DESC1()
            _ = adapter.pointee.lpVtbl.pointee.GetDesc1(adapter, &description)
            let isSoftware =
                description.VendorId == softwareVendor
                || description.Flags & UINT(DXGI_ADAPTER_FLAG_SOFTWARE.rawValue) != 0
            if index == 0 {
                if isSoftware == wantsSoftware {
                    // The default already is what is wanted: let DXGI choose.
                    // 預設正是所要的：交給 DXGI 選。
                    _ = adapter.pointee.lpVtbl.pointee.Release(adapter)
                    return nil
                }
                defaultIsSoftware = isSoftware
            } else if isSoftware == wantsSoftware || (defaultIsSoftware && !isSoftware) {
                return UnsafeMutableRawPointer(adapter).assumingMemoryBound(to: IDXGIAdapter.self)
            }
            _ = adapter.pointee.lpVtbl.pointee.Release(adapter)
            index += 1
        }
    }

    deinit {
        releaseTargets()
        for pointer in [vertexBuffer, indexBuffer, constantBuffer] { release(pointer) }
        release(vertexShader)
        release(geometryShader)
        release(pixelShader)
        release(inputLayout)
        release(rasterizer)
        release(depthOn)
        release(depthOff)
    }

    private static func adapterName(of device: UnsafeMutablePointer<ID3D11Device>) -> String {
        var iid = D3D11IID.IDXGIDevice
        var raw: UnsafeMutableRawPointer?
        guard device.pointee.lpVtbl.pointee.QueryInterface(device, &iid, &raw) == S_OK, let raw
        else { return "Direct3D 11 device" }
        let dxgiDevice = raw.assumingMemoryBound(to: IDXGIDevice.self)
        defer { _ = dxgiDevice.pointee.lpVtbl.pointee.Release(dxgiDevice) }
        var adapter: UnsafeMutablePointer<IDXGIAdapter>?
        guard dxgiDevice.pointee.lpVtbl.pointee.GetAdapter(dxgiDevice, &adapter) == S_OK, let adapter
        else { return "Direct3D 11 device" }
        defer { _ = adapter.pointee.lpVtbl.pointee.Release(adapter) }
        var description = DXGI_ADAPTER_DESC()
        guard adapter.pointee.lpVtbl.pointee.GetDesc(adapter, &description) == S_OK else {
            return "Direct3D 11 device"
        }
        return withUnsafeBytes(of: description.Description) { raw in
            let units = raw.bindMemory(to: UInt16.self)
            let length = units.firstIndex(of: 0) ?? units.count
            return String(decoding: units.prefix(length), as: UTF16.self)
        }
    }

    // MARK: Pipeline

    private func compile(_ entry: String, _ target: String) throws -> UnsafeMutablePointer<ID3DBlob> {
        var code: UnsafeMutablePointer<ID3DBlob>?
        var errors: UnsafeMutablePointer<ID3DBlob>?
        // D3DCOMPILE_OPTIMIZATION_LEVEL3 is (1 << 15); the macro is not imported.
        // D3DCOMPILE_OPTIMIZATION_LEVEL3 為 (1 << 15);該巨集不會被匯入。
        let optimizationLevel3: UINT = 1 << 15
        let result = meshShaderSource.withCString { source in
            entry.withCString { entryName in
                target.withCString { targetName in
                    "mesh3d.hlsl".withCString { sourceName in
                        D3DCompile(
                            source, SIZE_T(strlen(source)), sourceName, nil, nil,
                            entryName, targetName, optimizationLevel3, 0, &code, &errors
                        )
                    }
                }
            }
        }
        defer { release(errors) }
        guard result == S_OK, let code else {
            var message = "D3DCompile \(entry) failed (0x\(String(UInt32(bitPattern: result), radix: 16)))"
            if let errors, let text = errors.pointee.lpVtbl.pointee.GetBufferPointer(errors) {
                message += ": " + String(cString: text.assumingMemoryBound(to: CChar.self))
            }
            throw D3D11Error.failed(message, result)
        }
        return code
    }

    private func bytes(_ blob: UnsafeMutablePointer<ID3DBlob>) -> (UnsafeMutableRawPointer?, SIZE_T) {
        (
            blob.pointee.lpVtbl.pointee.GetBufferPointer(blob),
            blob.pointee.lpVtbl.pointee.GetBufferSize(blob)
        )
    }

    private func buildPipeline() throws {
        let vsBlob = try compile("vs_main", "vs_5_0")
        defer { release(vsBlob) }
        let gsBlob = try compile("gs_main", "gs_5_0")
        defer { release(gsBlob) }
        let psBlob = try compile("ps_main", "ps_5_0")
        defer { release(psBlob) }

        let (vsCode, vsSize) = bytes(vsBlob)
        try D3D11_CHECK(
            "CreateVertexShader",
            device.pointee.lpVtbl.pointee.CreateVertexShader(device, vsCode, vsSize, nil, &vertexShader)
        )
        let (gsCode, gsSize) = bytes(gsBlob)
        try D3D11_CHECK(
            "CreateGeometryShader",
            device.pointee.lpVtbl.pointee.CreateGeometryShader(device, gsCode, gsSize, nil, &geometryShader)
        )
        let (psCode, psSize) = bytes(psBlob)
        try D3D11_CHECK(
            "CreatePixelShader",
            device.pointee.lpVtbl.pointee.CreatePixelShader(device, psCode, psSize, nil, &pixelShader)
        )

        // Semantic names must outlive the call; strdup'd and freed after.
        // 語意名稱必須活過這次呼叫，因此 strdup 後於呼叫後釋放。
        let semantics: [String] = ["POSITION", "NORMAL", "COLOR"]
        let names: [UnsafeMutablePointer<CChar>] = semantics.map { strdup($0)! }
        defer { names.forEach { free($0) } }
        var elements = (0..<3).map { index in
            D3D11_INPUT_ELEMENT_DESC(
                SemanticName: UnsafePointer(names[index]),
                SemanticIndex: 0,
                Format: DXGI_FORMAT_R32G32B32_FLOAT,
                InputSlot: 0,
                AlignedByteOffset: UINT(index * 12),
                InputSlotClass: D3D11_INPUT_PER_VERTEX_DATA,
                InstanceDataStepRate: 0
            )
        }
        try D3D11_CHECK(
            "CreateInputLayout",
            device.pointee.lpVtbl.pointee.CreateInputLayout(
                device, &elements, UINT(elements.count), vsCode, vsSize, &inputLayout
            )
        )

        var constantDesc = D3D11_BUFFER_DESC()
        constantDesc.ByteWidth = UINT(MemoryLayout<MeshConstants>.size)
        constantDesc.Usage = D3D11_USAGE_DYNAMIC
        constantDesc.BindFlags = UINT(D3D11_BIND_CONSTANT_BUFFER.rawValue)
        constantDesc.CPUAccessFlags = UINT(D3D11_CPU_ACCESS_WRITE.rawValue)
        try D3D11_CHECK(
            "CreateBuffer(constants)",
            device.pointee.lpVtbl.pointee.CreateBuffer(device, &constantDesc, nil, &constantBuffer)
        )

        // No culling: a mesh's winding is whatever its author wrote, and the
        // GL path draws both faces too.
        // 不剔除:mesh 的繞向由作者決定,GL 路徑同樣畫兩面。
        var rasterizerDesc = D3D11_RASTERIZER_DESC()
        rasterizerDesc.FillMode = D3D11_FILL_SOLID
        rasterizerDesc.CullMode = D3D11_CULL_NONE
        rasterizerDesc.DepthClipEnable = true
        try D3D11_CHECK(
            "CreateRasterizerState",
            device.pointee.lpVtbl.pointee.CreateRasterizerState(device, &rasterizerDesc, &rasterizer)
        )

        var depthDesc = D3D11_DEPTH_STENCIL_DESC()
        depthDesc.DepthEnable = true
        depthDesc.DepthWriteMask = D3D11_DEPTH_WRITE_MASK_ALL
        depthDesc.DepthFunc = D3D11_COMPARISON_LESS
        try D3D11_CHECK(
            "CreateDepthStencilState(on)",
            device.pointee.lpVtbl.pointee.CreateDepthStencilState(device, &depthDesc, &depthOn)
        )
        // `depthTested: false`: drawn over whatever is there and leaving no depth,
        // GL_ALWAYS with the mask off on the other backends.
        // `depthTested: false`:畫在既有內容之上、不留下深度——其他 backend 上的 GL_ALWAYS 加關閉 mask。
        depthDesc.DepthFunc = D3D11_COMPARISON_ALWAYS
        depthDesc.DepthWriteMask = D3D11_DEPTH_WRITE_MASK_ZERO
        try D3D11_CHECK(
            "CreateDepthStencilState(off)",
            device.pointee.lpVtbl.pointee.CreateDepthStencilState(device, &depthDesc, &depthOff)
        )
    }

    // MARK: Size

    private func releaseTargets() {
        release(renderTarget)
        release(depthView)
        release(depthTexture)
        renderTarget = nil
        depthView = nil
        depthTexture = nil
    }

    /// Recreates the swap chain and the depth buffer when the pixel size moved.
    /// 像素尺寸改變時，重建 swap chain 與深度緩衝區。
    func resize(to pixels: SIMD2<Int>, panel: RawSwapChainPanel) throws {
        guard pixels != size || d3d.swapChain == nil else { return }
        releaseTargets()
        try d3d.attachSwapChain(to: panel.native, width: UInt32(pixels.x), height: UInt32(pixels.y))
        size = pixels

        guard let swapChain = d3d.swapChain else { return }
        var textureIID = D3D11IID.ID3D11Texture2D
        var backBufferRaw: UnsafeMutableRawPointer?
        try D3D11_CHECK(
            "GetBuffer",
            swapChain.pointee.lpVtbl.pointee.GetBuffer(swapChain, 0, &textureIID, &backBufferRaw)
        )
        guard let backBufferRaw else { throw D3D11Error.failed("GetBuffer returned null", S_OK) }
        let backBuffer = backBufferRaw.assumingMemoryBound(to: ID3D11Texture2D.self)
        defer { release(backBuffer) }
        try D3D11_CHECK(
            "CreateRenderTargetView",
            device.pointee.lpVtbl.pointee.CreateRenderTargetView(
                device, asResource(backBuffer), nil, &renderTarget
            )
        )

        var depthDesc = D3D11_TEXTURE2D_DESC()
        depthDesc.Width = UINT(pixels.x)
        depthDesc.Height = UINT(pixels.y)
        depthDesc.MipLevels = 1
        depthDesc.ArraySize = 1
        depthDesc.Format = DXGI_FORMAT_D24_UNORM_S8_UINT
        depthDesc.SampleDesc.Count = 1
        depthDesc.Usage = D3D11_USAGE_DEFAULT
        depthDesc.BindFlags = UINT(D3D11_BIND_DEPTH_STENCIL.rawValue)
        try D3D11_CHECK(
            "CreateTexture2D(depth)",
            device.pointee.lpVtbl.pointee.CreateTexture2D(device, &depthDesc, nil, &depthTexture)
        )
        guard let depthTexture else { throw D3D11Error.failed("depth texture null", S_OK) }
        try D3D11_CHECK(
            "CreateDepthStencilView",
            device.pointee.lpVtbl.pointee.CreateDepthStencilView(
                device, asResource(depthTexture), nil, &depthView
            )
        )
    }

    // MARK: Geometry

    private func upload(_ packed: PackedScene) throws {
        guard packed.revision != uploadedRevision else { return }
        release(vertexBuffer)
        release(indexBuffer)
        vertexBuffer = nil
        indexBuffer = nil
        vertexBuffer = try makeBuffer(packed.vertices, bind: D3D11_BIND_VERTEX_BUFFER)
        indexBuffer = try makeBuffer(packed.indices, bind: D3D11_BIND_INDEX_BUFFER)
        uploadedRevision = packed.revision
    }

    private func makeBuffer<T>(_ array: [T], bind: D3D11_BIND_FLAG) throws -> UnsafeMutablePointer<ID3D11Buffer>? {
        guard !array.isEmpty else { return nil }
        var desc = D3D11_BUFFER_DESC()
        desc.ByteWidth = UINT(array.count * MemoryLayout<T>.stride)
        desc.Usage = D3D11_USAGE_IMMUTABLE
        desc.BindFlags = UINT(bind.rawValue)
        var buffer: UnsafeMutablePointer<ID3D11Buffer>?
        try array.withUnsafeBytes { raw in
            var initial = D3D11_SUBRESOURCE_DATA()
            initial.pSysMem = raw.baseAddress
            try D3D11_CHECK(
                "CreateBuffer",
                device.pointee.lpVtbl.pointee.CreateBuffer(device, &desc, &initial, &buffer)
            )
        }
        return buffer
    }

    // MARK: Drawing

    func render(
        packed: PackedScene,
        meshes: [Mesh3D],
        viewProjection: Mesh3DMatrix4,
        light: SIMD3<Float>,
        background: SIMD4<Float>,
        measure: Bool,
        capture: Bool
    ) throws -> (micros: Int?, capture: (width: Int, height: Int, rgba: [UInt8])?) {
        guard let swapChain = d3d.swapChain, let renderTarget, let depthView else {
            return (nil, nil)
        }
        let started = DispatchTime.now()
        try upload(packed)

        var clear = background
        withUnsafeBytes(of: &clear) { raw in
            context.pointee.lpVtbl.pointee.ClearRenderTargetView(
                context, renderTarget, raw.baseAddress!.assumingMemoryBound(to: Float.self)
            )
        }
        context.pointee.lpVtbl.pointee.ClearDepthStencilView(
            context, depthView, UINT(D3D11_CLEAR_DEPTH.rawValue), 1, 0
        )
        var target: UnsafeMutablePointer<ID3D11RenderTargetView>? = renderTarget
        context.pointee.lpVtbl.pointee.OMSetRenderTargets(context, 1, &target, depthView)
        var viewport = D3D11_VIEWPORT(
            TopLeftX: 0, TopLeftY: 0, Width: Float(size.x), Height: Float(size.y),
            MinDepth: 0, MaxDepth: 1
        )
        context.pointee.lpVtbl.pointee.RSSetViewports(context, 1, &viewport)
        context.pointee.lpVtbl.pointee.RSSetState(context, rasterizer)
        context.pointee.lpVtbl.pointee.IASetInputLayout(context, inputLayout)
        var vertexBuffers: UnsafeMutablePointer<ID3D11Buffer>? = vertexBuffer
        var stride = UINT(9 * MemoryLayout<Float>.size)
        var offset: UINT = 0
        context.pointee.lpVtbl.pointee.IASetVertexBuffers(context, 0, 1, &vertexBuffers, &stride, &offset)
        context.pointee.lpVtbl.pointee.IASetIndexBuffer(context, indexBuffer, DXGI_FORMAT_R32_UINT, 0)
        context.pointee.lpVtbl.pointee.VSSetShader(context, vertexShader, nil, 0)
        context.pointee.lpVtbl.pointee.PSSetShader(context, pixelShader, nil, 0)
        var constants: UnsafeMutablePointer<ID3D11Buffer>? = constantBuffer
        context.pointee.lpVtbl.pointee.VSSetConstantBuffers(context, 0, 1, &constants)
        context.pointee.lpVtbl.pointee.GSSetConstantBuffers(context, 0, 1, &constants)
        context.pointee.lpVtbl.pointee.PSSetConstantBuffers(context, 0, 1, &constants)

        if vertexBuffer != nil {
            for (draw, mesh) in zip(packed.draws, meshes) where draw.count > 0 {
                let mvp = viewProjection * .model(mesh.transform)
                let pointSize: Float
                let lit: Bool
                switch draw.mode {
                    case .triangles: (pointSize, lit) = (1, mesh.lit)
                    case .lines: (pointSize, lit) = (1, false)
                    case .points(let size): (pointSize, lit) = (size, false)
                }
                var values = MeshConstants(
                    mvp: columns(mvp.elements),
                    normal: columns(Mesh3DMatrix4.rotation(mesh.transform.rotation).elements),
                    light: SIMD4(light.x, light.y, light.z, 0),
                    params: SIMD4(lit ? 1 : 0, pointSize, Float(size.x), Float(size.y))
                )
                try writeConstants(&values)
                context.pointee.lpVtbl.pointee.OMSetDepthStencilState(
                    context, mesh.depthTested ? depthOn : depthOff, 0
                )
                switch draw.mode {
                    case .triangles:
                        guard indexBuffer != nil else { continue }
                        context.pointee.lpVtbl.pointee.GSSetShader(context, nil, nil, 0)
                        context.pointee.lpVtbl.pointee.IASetPrimitiveTopology(
                            context, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST
                        )
                        context.pointee.lpVtbl.pointee.DrawIndexed(
                            context, UINT(draw.count), UINT(draw.start), 0
                        )
                    case .lines:
                        context.pointee.lpVtbl.pointee.GSSetShader(context, nil, nil, 0)
                        context.pointee.lpVtbl.pointee.IASetPrimitiveTopology(
                            context, D3D11_PRIMITIVE_TOPOLOGY_LINELIST
                        )
                        context.pointee.lpVtbl.pointee.Draw(context, UINT(draw.count), UINT(draw.start))
                    case .points:
                        context.pointee.lpVtbl.pointee.GSSetShader(context, geometryShader, nil, 0)
                        context.pointee.lpVtbl.pointee.IASetPrimitiveTopology(
                            context, D3D11_PRIMITIVE_TOPOLOGY_POINTLIST
                        )
                        context.pointee.lpVtbl.pointee.Draw(context, UINT(draw.count), UINT(draw.start))
                }
            }
            context.pointee.lpVtbl.pointee.GSSetShader(context, nil, nil, 0)
        }

        let captured = capture ? try readBack(swapChain) : nil
        var micros: Int?
        if measure {
            // Until the GPU finishes this frame, as `waitUntilCompleted` and
            // `glFinish` measure on the other backends.
            // 直到 GPU 完成這一幀為止，與其他 backend 的 `waitUntilCompleted`、`glFinish` 相同。
            try waitForGPU()
            micros = Int((DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1000)
        }
        try D3D11_CHECK(
            "Present",
            swapChain.pointee.lpVtbl.pointee.Present(swapChain, 0, 0)
        )
        return (micros, captured)
    }

    private func writeConstants(_ values: inout MeshConstants) throws {
        guard let constantBuffer else { return }
        var mapped = D3D11_MAPPED_SUBRESOURCE()
        try D3D11_CHECK(
            "Map(constants)",
            context.pointee.lpVtbl.pointee.Map(
                context, asResource(constantBuffer), 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped
            )
        )
        withUnsafeBytes(of: &values) { raw in
            mapped.pData.copyMemory(from: raw.baseAddress!, byteCount: raw.count)
        }
        context.pointee.lpVtbl.pointee.Unmap(context, asResource(constantBuffer), 0)
    }

    private func waitForGPU() throws {
        var desc = D3D11_QUERY_DESC(Query: D3D11_QUERY_EVENT, MiscFlags: 0)
        var query: UnsafeMutablePointer<ID3D11Query>?
        try D3D11_CHECK("CreateQuery", device.pointee.lpVtbl.pointee.CreateQuery(device, &desc, &query))
        guard let query else { return }
        defer { release(query) }
        let asynchronous = UnsafeMutableRawPointer(query).assumingMemoryBound(to: ID3D11Asynchronous.self)
        context.pointee.lpVtbl.pointee.End(context, asynchronous)
        var done: WindowsBool = false
        while context.pointee.lpVtbl.pointee.GetData(
            context, asynchronous, &done, UINT(MemoryLayout<WindowsBool>.size), 0
        ) == S_FALSE {
            Thread.sleep(forTimeInterval: 0.0002)
        }
    }

    /// The back buffer copied into a staging texture and read, RGBA. Alpha is
    /// forced to 255: the swap chain ignores alpha, so the stored byte means
    /// nothing, and an opaque frame is premultiplied by definition.
    /// back buffer 複製到 staging 材質後讀出(RGBA)。alpha 強制為 255:swap chain 忽略 alpha,儲存的位元組不具意義,
    /// 而不透明的畫面依定義就是 premultiplied。
    private func readBack(
        _ swapChain: UnsafeMutablePointer<IDXGISwapChain1>
    ) throws -> (width: Int, height: Int, rgba: [UInt8]) {
        var textureIID = D3D11IID.ID3D11Texture2D
        var backBufferRaw: UnsafeMutableRawPointer?
        try D3D11_CHECK(
            "GetBuffer",
            swapChain.pointee.lpVtbl.pointee.GetBuffer(swapChain, 0, &textureIID, &backBufferRaw)
        )
        guard let backBufferRaw else { throw D3D11Error.failed("GetBuffer returned null", S_OK) }
        let backBuffer = backBufferRaw.assumingMemoryBound(to: ID3D11Texture2D.self)
        defer { release(backBuffer) }

        var desc = D3D11_TEXTURE2D_DESC()
        backBuffer.pointee.lpVtbl.pointee.GetDesc(backBuffer, &desc)
        desc.Usage = D3D11_USAGE_STAGING
        desc.BindFlags = 0
        desc.CPUAccessFlags = UINT(D3D11_CPU_ACCESS_READ.rawValue)
        desc.MiscFlags = 0
        var staging: UnsafeMutablePointer<ID3D11Texture2D>?
        try D3D11_CHECK(
            "CreateTexture2D(staging)",
            device.pointee.lpVtbl.pointee.CreateTexture2D(device, &desc, nil, &staging)
        )
        guard let staging else { throw D3D11Error.failed("staging texture null", S_OK) }
        defer { release(staging) }
        context.pointee.lpVtbl.pointee.CopyResource(context, asResource(staging), asResource(backBuffer))

        var mapped = D3D11_MAPPED_SUBRESOURCE()
        try D3D11_CHECK(
            "Map(staging)",
            context.pointee.lpVtbl.pointee.Map(context, asResource(staging), 0, D3D11_MAP_READ, 0, &mapped)
        )
        defer { context.pointee.lpVtbl.pointee.Unmap(context, asResource(staging), 0) }
        let width = Int(desc.Width)
        let height = Int(desc.Height)
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let source = mapped.pData.assumingMemoryBound(to: UInt8.self)
        let pitch = Int(mapped.RowPitch)
        rgba.withUnsafeMutableBufferPointer { destination in
            for row in 0..<height {
                let from = source + row * pitch
                let to = destination.baseAddress! + row * width * 4
                to.update(from: from, count: width * 4)
                for column in 0..<width {
                    to[column * 4 + 3] = 255
                }
            }
        }
        return (width, height, rgba)
    }
}
