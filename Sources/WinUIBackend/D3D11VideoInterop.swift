import CWinRT
import WinSDK
import WinUIInterop
@preconcurrency import WindowsFoundation
@_spi(WinRTInternal) import WinUI

/// Raw COM wrapper for `ISwapChainPanelNative`, following the same shape as
/// `SwiftIInitializeWithWindow` in WinUIBackend.swift.
public class SwiftISwapChainPanelNative: WindowsFoundation.IUnknown {
    override public class var IID: WindowsFoundation.IID {
        // 63aad0b8-7c24-40ff-85a8-640d944cc325
        WindowsFoundation.IID(
            Data1: 0x63AA_D0B8,
            Data2: 0x7C24,
            Data3: 0x40FF,
            Data4: (0x85, 0xA8, 0x64, 0x0D, 0x94, 0x4C, 0xC3, 0x25)
        )
    }

    public func setSwapChain(_ swapChain: UnsafeMutablePointer<IDXGISwapChain>) throws {
        _ = try perform(as: ISwapChainPanelNative.self) { pThis in
            try CHECKED(pThis.pointee.lpVtbl.pointee.SetSwapChain(pThis, swapChain))
        }
    }
}

/// `WinUI.SwapChainPanel` isn't projected by swift-winui. Activate the native
/// WinRT control directly and wrap the resulting ABI object as a
/// `FrameworkElement`, matching the technique documented in
/// C:\Users\lowei\.claude\plans\quizzical-jingling-music.md.
public enum P6D3D11SwapChainPanelActivation {
    /// Split into individual steps so callers can log between them and see
    /// exactly which one fails. swift-winui's wrapper classes do their COM
    /// QueryInterface lazily, so simply constructing a wrapper proves
    /// nothing -- the QI only happens when a wrapped-type-specific property
    /// is first touched, and traps there if the interface isn't supported.
    public static func activateInspectable() throws -> WindowsFoundation.IInspectable {
        try RoActivateInstance(HString("Microsoft.UI.Xaml.Controls.SwapChainPanel"))
    }

    public static func queryNative(
        _ inspectable: WindowsFoundation.IInspectable
    ) throws -> SwiftISwapChainPanelNative {
        try inspectable.QueryInterface()
    }

    /// Reports whether the activated object actually supports the interface
    /// behind a given wrapper, without trapping. Returns the runtime class
    /// name too, which tells us whether RoActivateInstance really produced a
    /// SwapChainPanel.
    public static func describe(_ inspectable: WindowsFoundation.IInspectable) -> String {
        var raw: HSTRING?
        do {
            try inspectable.GetRuntimeClassName(&raw)
        } catch {
            return "runtimeClass=<GetRuntimeClassName failed: \(error)>"
        }
        guard let raw else { return "runtimeClass=<null>" }
        let name = String(from: raw)
        _ = WindowsDeleteString(raw)
        return "runtimeClass=\(name)"
    }

    public static func wrapAsPanel(_ inspectable: WindowsFoundation.IInspectable) -> WinUI.Panel {
        WinUI.Panel(fromAbi: inspectable)
    }

    public static func wrapAsFrameworkElement(
        _ inspectable: WindowsFoundation.IInspectable
    ) -> WinUI.FrameworkElement {
        WinUI.FrameworkElement(fromAbi: inspectable)
    }
}

enum P6D3D11Error: Swift.Error {
    case failed(String, HRESULT)
}

extension P6D3D11Error: CustomStringConvertible {
    var description: String {
        switch self {
        case .failed(let step, let hr):
            return "\(step) failed with HRESULT 0x\(String(UInt32(bitPattern: hr), radix: 16))"
        }
    }
}

private func D3D11_CHECK(_ step: String, _ hr: HRESULT) throws {
    if hr < 0 {
        throw P6D3D11Error.failed(step, hr)
    }
}

/// Well-known public COM interface IIDs, hand-declared (matching the
/// `SwiftISwapChainPanelNative.IID` approach above) rather than linking
/// against dxguid.lib, so no extra linker settings are needed.
private enum P6IID {
    // 54ec77fa-1377-44e6-8c32-88fd5f44c84c
    static var IDXGIDevice: WinUIInterop.IID {
        WinUIInterop.IID(
            Data1: 0x54EC_77FA,
            Data2: 0x1377,
            Data3: 0x44E6,
            Data4: (0x8C, 0x32, 0x88, 0xFD, 0x5F, 0x44, 0xC8, 0x4C)
        )
    }

    // 50c83a1c-e072-4c48-87b0-3630fa36a6d0
    static var IDXGIFactory2: WinUIInterop.IID {
        WinUIInterop.IID(
            Data1: 0x50C8_3A1C,
            Data2: 0xE072,
            Data3: 0x4C48,
            Data4: (0x87, 0xB0, 0x36, 0x30, 0xFA, 0x36, 0xA6, 0xD0)
        )
    }

    // 6f15aaf2-d208-4e89-9ab4-489535d34f9c
    static var ID3D11Texture2D: WinUIInterop.IID {
        WinUIInterop.IID(
            Data1: 0x6F15_AAF2,
            Data2: 0xD208,
            Data3: 0x4E89,
            Data4: (0x9A, 0xB4, 0x48, 0x95, 0x35, 0xD3, 0x4F, 0x9C)
        )
    }
}

/// Owns a D3D11 device/context, a composition swap chain sized to the video
/// viewport, and a small pool of `ID3D11Texture2D`s that frames are copied
/// into before `Present()`, mirroring the macOS Metal path's fixed texture
/// pool (see plan §Phase 1).
public final class P6D3D11Device {
    public let device: UnsafeMutablePointer<ID3D11Device>
    public let context: UnsafeMutablePointer<ID3D11DeviceContext>
    private let factory: UnsafeMutablePointer<IDXGIFactory2>

    public private(set) var swapChain: UnsafeMutablePointer<IDXGISwapChain1>?
    public private(set) var width: UInt32 = 0
    public private(set) var height: UInt32 = 0

    public init() throws {
        var device: UnsafeMutablePointer<ID3D11Device>?
        var context: UnsafeMutablePointer<ID3D11DeviceContext>?
        var obtainedLevel = D3D_FEATURE_LEVEL_11_0
        let levels: [D3D_FEATURE_LEVEL] = [D3D_FEATURE_LEVEL_11_0]

        try D3D11_CHECK(
            "D3D11CreateDevice",
            levels.withUnsafeBufferPointer { levelsPtr in
                D3D11CreateDevice(
                    nil,
                    D3D_DRIVER_TYPE_HARDWARE,
                    nil,
                    0,
                    levelsPtr.baseAddress,
                    UINT32(levelsPtr.count),
                    UINT32(D3D11_SDK_VERSION),
                    &device,
                    &obtainedLevel,
                    &context
                )
            }
        )
        guard let device, let context else {
            throw P6D3D11Error.failed("D3D11CreateDevice returned a null device", S_OK)
        }
        self.device = device
        self.context = context
        self.factory = try P6D3D11Device.obtainFactory(from: device)
    }

    /// Walks device -> DXGI adapter -> DXGI factory, the standard way to get
    /// an `IDXGIFactory2` capable of `CreateSwapChainForComposition` without
    /// creating a second, unrelated factory via `CreateDXGIFactory2`.
    private static func obtainFactory(
        from device: UnsafeMutablePointer<ID3D11Device>
    ) throws -> UnsafeMutablePointer<IDXGIFactory2> {
        var dxgiDeviceIID = P6IID.IDXGIDevice
        var dxgiDeviceRaw: UnsafeMutableRawPointer?
        try D3D11_CHECK(
            "ID3D11Device::QueryInterface(IDXGIDevice)",
            device.pointee.lpVtbl.pointee.QueryInterface(device, &dxgiDeviceIID, &dxgiDeviceRaw)
        )
        guard let dxgiDeviceRaw else {
            throw P6D3D11Error.failed("QueryInterface(IDXGIDevice) returned null", S_OK)
        }
        let dxgiDevice = dxgiDeviceRaw.assumingMemoryBound(to: IDXGIDevice.self)
        defer { _ = dxgiDevice.pointee.lpVtbl.pointee.Release(dxgiDevice) }

        var adapter: UnsafeMutablePointer<IDXGIAdapter>?
        try D3D11_CHECK(
            "IDXGIDevice::GetAdapter",
            dxgiDevice.pointee.lpVtbl.pointee.GetAdapter(dxgiDevice, &adapter)
        )
        guard let adapter else {
            throw P6D3D11Error.failed("GetAdapter returned null", S_OK)
        }
        defer { _ = adapter.pointee.lpVtbl.pointee.Release(adapter) }

        var factoryIID = P6IID.IDXGIFactory2
        var factoryRaw: UnsafeMutableRawPointer?
        try D3D11_CHECK(
            "IDXGIAdapter::GetParent(IDXGIFactory2)",
            adapter.pointee.lpVtbl.pointee.GetParent(adapter, &factoryIID, &factoryRaw)
        )
        guard let factoryRaw else {
            throw P6D3D11Error.failed("GetParent(IDXGIFactory2) returned null", S_OK)
        }
        return factoryRaw.assumingMemoryBound(to: IDXGIFactory2.self)
    }

    /// Creates (or recreates) a composition swap chain sized to `width`x`height`
    /// and attaches it to `panel` via `ISwapChainPanelNative::SetSwapChain`.
    public func attachSwapChain(
        to panel: SwiftISwapChainPanelNative,
        width: UInt32,
        height: UInt32
    ) throws {
        if let existing = swapChain {
            _ = existing.pointee.lpVtbl.pointee.Release(existing)
            swapChain = nil
        }

        var desc = DXGI_SWAP_CHAIN_DESC1()
        desc.Width = width
        desc.Height = height
        desc.Format = DXGI_FORMAT_R8G8B8A8_UNORM
        desc.Stereo = false
        desc.SampleDesc.Count = 1
        desc.SampleDesc.Quality = 0
        desc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT
        desc.BufferCount = 2
        desc.Scaling = DXGI_SCALING_STRETCH
        desc.SwapEffect = DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL
        desc.AlphaMode = DXGI_ALPHA_MODE_IGNORE

        var created: UnsafeMutablePointer<IDXGISwapChain1>?
        try D3D11_CHECK(
            "IDXGIFactory2::CreateSwapChainForComposition",
            withUnsafeMutablePointer(to: &desc) { descPtr in
                factory.pointee.lpVtbl.pointee.CreateSwapChainForComposition(
                    factory,
                    UnsafeMutableRawPointer(device).assumingMemoryBound(to: WinUIInterop.IUnknown.self),
                    descPtr,
                    nil,
                    &created
                )
            }
        )
        guard let created else {
            throw P6D3D11Error.failed("CreateSwapChainForComposition returned null", S_OK)
        }

        try panel.setSwapChain(
            UnsafeMutableRawPointer(created).assumingMemoryBound(to: IDXGISwapChain.self)
        )

        self.swapChain = created
        self.width = width
        self.height = height
    }

    /// Spike-only helper: clears the current back buffer to a solid color and
    /// presents it, used to visually confirm the SwapChainPanel is actually
    /// composited by WinUI before wiring in real frame uploads.
    public func clearAndPresent(r: Float, g: Float, b: Float, a: Float) throws {
        guard let swapChain else {
            throw P6D3D11Error.failed("clearAndPresent called before attachSwapChain", S_OK)
        }

        var textureIID = P6IID.ID3D11Texture2D
        var backBufferRaw: UnsafeMutableRawPointer?
        try D3D11_CHECK(
            "IDXGISwapChain1::GetBuffer",
            swapChain.pointee.lpVtbl.pointee.GetBuffer(swapChain, 0, &textureIID, &backBufferRaw)
        )
        guard let backBufferRaw else {
            throw P6D3D11Error.failed("GetBuffer returned null", S_OK)
        }
        let backBuffer = backBufferRaw.assumingMemoryBound(to: ID3D11Texture2D.self)
        defer { _ = backBuffer.pointee.lpVtbl.pointee.Release(backBuffer) }

        var rtv: UnsafeMutablePointer<ID3D11RenderTargetView>?
        try D3D11_CHECK(
            "ID3D11Device::CreateRenderTargetView",
            device.pointee.lpVtbl.pointee.CreateRenderTargetView(
                device,
                UnsafeMutableRawPointer(backBuffer).assumingMemoryBound(to: ID3D11Resource.self),
                nil,
                &rtv
            )
        )
        guard let rtv else {
            throw P6D3D11Error.failed("CreateRenderTargetView returned null", S_OK)
        }
        defer { _ = rtv.pointee.lpVtbl.pointee.Release(rtv) }

        var clearColor = (r, g, b, a)
        withUnsafeBytes(of: &clearColor) { raw in
            context.pointee.lpVtbl.pointee.ClearRenderTargetView(
                context, rtv, raw.baseAddress!.assumingMemoryBound(to: Float.self)
            )
        }

        try D3D11_CHECK(
            "IDXGISwapChain1::Present",
            swapChain.pointee.lpVtbl.pointee.Present(swapChain, 1, 0)
        )
    }

    fileprivate static func makeFactory(
        from device: UnsafeMutablePointer<ID3D11Device>
    ) throws -> UnsafeMutablePointer<IDXGIFactory2> {
        try obtainFactory(from: device)
    }
}

// MARK: - Zero-copy HWND video surface

/// A child window hosting a D3D11 swap chain, plus a rotating pool of
/// CPU-writable staging textures that decoded frames are written into
/// directly.
///
/// This mirrors the macOS Metal path: a fixed pool of GPU textures updated in
/// place, presentation driven by frame arrival, bypassing the UI framework's
/// image path entirely. Frames never pass through Data, Array, or a
/// WriteableBitmap -- the decoder reads pipe bytes straight into mapped GPU
/// memory, so there is no CPU-side copy and no pixel conversion (ffmpeg's
/// `rgba` output is byte-identical to DXGI_FORMAT_R8G8B8A8_UNORM).
///
/// 這對應 macOS 的 Metal 路徑：固定數量的 GPU texture 就地更新，由影格抵達驅動
/// 呈現，完全繞開 UI 框架的影像路徑。影格不經過 Data、Array 或 WriteableBitmap，
/// 解碼器直接把位元組寫入已對映的 GPU 記憶體，因此 CPU 端零複製，也不需要像素
/// 格式轉換（ffmpeg 的 `rgba` 與 DXGI_FORMAT_R8G8B8A8_UNORM 位元組完全相同）。
public final class P6D3D11VideoSurface {
    /// Matches the macOS Metal path's pool size: enough buffers that the CPU
    /// can fill one while the GPU still reads another.
    private static let poolSize = 3

    public let hwnd: HWND
    private let device: UnsafeMutablePointer<ID3D11Device>
    private let context: UnsafeMutablePointer<ID3D11DeviceContext>
    private let factory: UnsafeMutablePointer<IDXGIFactory2>

    private var swapChain: UnsafeMutablePointer<IDXGISwapChain1>?
    private var pool: [UnsafeMutablePointer<ID3D11Texture2D>] = []
    private var poolIndex = 0
    private var frameWidth: UInt32 = 0
    private var frameHeight: UInt32 = 0

    public init(parent: HWND, width: Int32, height: Int32) throws {
        hwnd = try P6D3D11VideoSurface.makeChildWindow(
            parent: parent, width: width, height: height
        )

        var device: UnsafeMutablePointer<ID3D11Device>?
        var context: UnsafeMutablePointer<ID3D11DeviceContext>?
        var obtainedLevel = D3D_FEATURE_LEVEL_11_0
        let levels: [D3D_FEATURE_LEVEL] = [D3D_FEATURE_LEVEL_11_0]
        try D3D11_CHECK(
            "D3D11CreateDevice",
            levels.withUnsafeBufferPointer { levelsPtr in
                D3D11CreateDevice(
                    nil, D3D_DRIVER_TYPE_HARDWARE, nil, 0,
                    levelsPtr.baseAddress, UINT32(levelsPtr.count),
                    UINT32(D3D11_SDK_VERSION), &device, &obtainedLevel, &context
                )
            }
        )
        guard let device, let context else {
            throw P6D3D11Error.failed("D3D11CreateDevice returned null", S_OK)
        }
        self.device = device
        self.context = context
        self.factory = try P6D3D11Device.makeFactory(from: device)
    }

    private static var registeredClass = false

    private static func makeChildWindow(
        parent: HWND, width: Int32, height: Int32
    ) throws -> HWND {
        try "P6D3D11Surface".withCString(encodedAs: UTF16.self) { className in
            let instance = GetModuleHandleW(nil)
            if !registeredClass {
                var windowClass = WNDCLASSEXW()
                windowClass.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
                windowClass.lpfnWndProc = { hwnd, message, wParam, lParam in
                    DefWindowProcW(hwnd, message, wParam, lParam)
                }
                windowClass.hInstance = instance
                windowClass.lpszClassName = className
                if RegisterClassExW(&windowClass) == 0 {
                    let error = GetLastError()
                    if error != ERROR_CLASS_ALREADY_EXISTS {
                        throw P6D3D11Error.failed(
                            "RegisterClassExW (GetLastError \(error))", S_OK
                        )
                    }
                }
                registeredClass = true
            }

            guard let hwnd = CreateWindowExW(
                0, className, nil, DWORD(WS_CHILD | WS_VISIBLE),
                0, 0, width, height, parent, nil, instance, nil
            ) else {
                throw P6D3D11Error.failed(
                    "CreateWindowExW (GetLastError \(GetLastError()))", S_OK
                )
            }
            return hwnd
        }
    }

    /// Moves/resizes the child window to sit exactly over the video viewport.
    public func setBounds(x: Int32, y: Int32, width: Int32, height: Int32) {
        _ = SetWindowPos(
            hwnd, nil, x, y, width, height, UINT(SWP_NOZORDER | SWP_NOACTIVATE)
        )
    }

    /// (Re)creates the swap chain and staging pool for a given frame size.
    ///
    /// The swap chain is sized to the *frame*, not the window, so DXGI scales
    /// on present and CopyResource can move a whole frame in one call without
    /// needing a shader pass.
    /// swap chain 依「影格」尺寸建立而非視窗尺寸，讓 DXGI 於 present 時縮放，
    /// CopyResource 便能一次搬移整張影格，不需額外的 shader 階段。
    public func configure(frameWidth: UInt32, frameHeight: UInt32) throws {
        guard frameWidth != self.frameWidth || frameHeight != self.frameHeight else {
            return
        }
        releaseFrameResources()

        var desc = DXGI_SWAP_CHAIN_DESC1()
        desc.Width = frameWidth
        desc.Height = frameHeight
        desc.Format = DXGI_FORMAT_R8G8B8A8_UNORM
        desc.SampleDesc.Count = 1
        desc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT
        desc.BufferCount = 2
        desc.Scaling = DXGI_SCALING_STRETCH
        desc.SwapEffect = DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL
        desc.AlphaMode = DXGI_ALPHA_MODE_IGNORE

        var created: UnsafeMutablePointer<IDXGISwapChain1>?
        try D3D11_CHECK(
            "IDXGIFactory2::CreateSwapChainForHwnd",
            withUnsafeMutablePointer(to: &desc) { descPtr in
                factory.pointee.lpVtbl.pointee.CreateSwapChainForHwnd(
                    factory,
                    UnsafeMutableRawPointer(device).assumingMemoryBound(
                        to: WinUIInterop.IUnknown.self
                    ),
                    hwnd, descPtr, nil, nil, &created
                )
            }
        )
        guard let created else {
            throw P6D3D11Error.failed("CreateSwapChainForHwnd returned null", S_OK)
        }
        swapChain = created

        // Staging usage keeps the texture CPU-writable and legal as a
        // CopyResource source; the pool means a Map never waits on the GPU
        // still reading the previous frame.
        // STAGING 讓 texture 可由 CPU 寫入並可作為 CopyResource 來源；使用 pool
        // 可避免 Map 時等待 GPU 仍在讀取的前一張影格。
        var textureDesc = D3D11_TEXTURE2D_DESC()
        textureDesc.Width = frameWidth
        textureDesc.Height = frameHeight
        textureDesc.MipLevels = 1
        textureDesc.ArraySize = 1
        textureDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM
        textureDesc.SampleDesc.Count = 1
        textureDesc.Usage = D3D11_USAGE_STAGING
        textureDesc.CPUAccessFlags = UINT(D3D11_CPU_ACCESS_WRITE.rawValue)

        for _ in 0..<Self.poolSize {
            var texture: UnsafeMutablePointer<ID3D11Texture2D>?
            try D3D11_CHECK(
                "ID3D11Device::CreateTexture2D",
                withUnsafeMutablePointer(to: &textureDesc) { descPtr in
                    device.pointee.lpVtbl.pointee.CreateTexture2D(
                        device, descPtr, nil, &texture
                    )
                }
            )
            guard let texture else {
                throw P6D3D11Error.failed("CreateTexture2D returned null", S_OK)
            }
            pool.append(texture)
        }

        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
    }

    /// Maps the next staging texture and hands its memory to `body`, which
    /// fills it with exactly one frame. This is the zero-copy seam: the
    /// decoder reads pipe bytes straight into GPU-visible memory.
    ///
    /// `body` receives the destination pointer and the row pitch in bytes,
    /// which may exceed width*4, so rows must be written individually when the
    /// pitch does not match.
    /// `body` 取得目的地指標與每列位元組數（row pitch）；pitch 可能大於
    /// width*4，不相符時必須逐列寫入。
    public func writeFrame(
        _ body: (UnsafeMutableRawPointer, Int) throws -> Void
    ) throws {
        guard !pool.isEmpty else {
            throw P6D3D11Error.failed("writeFrame called before configure", S_OK)
        }
        let texture = pool[poolIndex]
        poolIndex = (poolIndex + 1) % pool.count

        let resource = UnsafeMutableRawPointer(texture)
            .assumingMemoryBound(to: ID3D11Resource.self)
        var mapped = D3D11_MAPPED_SUBRESOURCE()
        try D3D11_CHECK(
            "ID3D11DeviceContext::Map",
            context.pointee.lpVtbl.pointee.Map(
                context, resource, 0, D3D11_MAP_WRITE, 0, &mapped
            )
        )
        defer { context.pointee.lpVtbl.pointee.Unmap(context, resource, 0) }

        guard let destination = mapped.pData else {
            throw P6D3D11Error.failed("Map returned null pData", S_OK)
        }
        try body(destination, Int(mapped.RowPitch))
    }

    /// Copies the most recently written staging texture to the back buffer and
    /// presents it. Presentation is driven by frame arrival, exactly like the
    /// Metal path, rather than by a separate render timer.
    public func present() throws {
        guard let swapChain, !pool.isEmpty else { return }
        let lastIndex = (poolIndex + pool.count - 1) % pool.count
        let source = UnsafeMutableRawPointer(pool[lastIndex])
            .assumingMemoryBound(to: ID3D11Resource.self)

        var textureIID = P6IID.ID3D11Texture2D
        var backBufferRaw: UnsafeMutableRawPointer?
        try D3D11_CHECK(
            "IDXGISwapChain1::GetBuffer",
            swapChain.pointee.lpVtbl.pointee.GetBuffer(
                swapChain, 0, &textureIID, &backBufferRaw
            )
        )
        guard let backBufferRaw else {
            throw P6D3D11Error.failed("GetBuffer returned null", S_OK)
        }
        let backBuffer = backBufferRaw.assumingMemoryBound(to: ID3D11Texture2D.self)
        defer { _ = backBuffer.pointee.lpVtbl.pointee.Release(backBuffer) }

        context.pointee.lpVtbl.pointee.CopyResource(
            context,
            UnsafeMutableRawPointer(backBuffer)
                .assumingMemoryBound(to: ID3D11Resource.self),
            source
        )
        try D3D11_CHECK(
            "IDXGISwapChain1::Present",
            swapChain.pointee.lpVtbl.pointee.Present(swapChain, 1, 0)
        )
    }

    private func releaseFrameResources() {
        for texture in pool {
            _ = texture.pointee.lpVtbl.pointee.Release(texture)
        }
        pool.removeAll()
        poolIndex = 0
        if let swapChain {
            _ = swapChain.pointee.lpVtbl.pointee.Release(swapChain)
        }
        swapChain = nil
        frameWidth = 0
        frameHeight = 0
    }

    deinit {
        releaseFrameResources()
        _ = context.pointee.lpVtbl.pointee.Release(context)
        _ = device.pointee.lpVtbl.pointee.Release(device)
        _ = factory.pointee.lpVtbl.pointee.Release(factory)
        _ = DestroyWindow(hwnd)
    }
}
