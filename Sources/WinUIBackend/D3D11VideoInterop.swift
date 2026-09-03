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

enum D3D11Error: Swift.Error {
    case failed(String, HRESULT)
}

extension D3D11Error: CustomStringConvertible {
    var description: String {
        switch self {
        case .failed(let step, let hr):
            return "\(step) failed with HRESULT 0x\(String(UInt32(bitPattern: hr), radix: 16))"
        }
    }
}

private func D3D11_CHECK(_ step: String, _ hr: HRESULT) throws {
    if hr < 0 {
        throw D3D11Error.failed(step, hr)
    }
}

/// A live `Microsoft.UI.Xaml.Controls.SwapChainPanel`, driven entirely through
/// the C ABI.
///
/// XAML composes its own content through DirectComposition, which draws over
/// any plain child `HWND` of the same window, so a child-window swap chain
/// stays invisible no matter where it is positioned. A SwapChainPanel is the
/// supported way in: it hands its own composition visual to DXGI.
///
/// swift-winui does not project SwapChainPanel, and its generated wrapper
/// classes resolve their COM interface lazily behind a `try!`, so wrapping the
/// activated object as `WinUI.Panel` traps as soon as any property is touched.
/// Every call here goes through a vtable instead, so a failure surfaces as an
/// HRESULT rather than an illegal instruction.
///
/// XAML 透過 DirectComposition 合成自身內容，會蓋掉同一視窗中的一般子 HWND，
/// 因此子視窗上的 swap chain 無論擺在哪裡都看不到。SwapChainPanel 是官方支援的
/// 途徑：它會把自己的合成 visual 交給 DXGI。
/// swift-winui 未投影 SwapChainPanel，且其產生的包裝類別以 `try!` 延後解析 COM
/// 介面，所以一旦碰到任何屬性就會中止。此處全部改走 vtable，失敗會以 HRESULT
/// 呈現而非非法指令。
public final class RawSwapChainPanel {
    /// Deliberately kept as `IInspectable`: constructing any swift-winui
    /// wrapper around this object is exactly what traps.
    private let inspectable: WindowsFoundation.IInspectable
    private let uiElement: __ABI_Microsoft_UI_Xaml.IUIElement
    private let frameworkElement: __ABI_Microsoft_UI_Xaml.IFrameworkElement

    /// `ISwapChainPanelNative::SetSwapChain` lives here.
    public let native: SwiftISwapChainPanelNative

    /// All four QueryInterface calls happen up front rather than lazily, so a
    /// missing interface is reported at creation time instead of trapping
    /// somewhere later.
    public init() throws {
        inspectable = try RoActivateInstance(
            HString("Microsoft.UI.Xaml.Controls.SwapChainPanel")
        )
        native = try inspectable.QueryInterface()
        uiElement = try inspectable.QueryInterface()
        frameworkElement = try inspectable.QueryInterface()
    }

    /// The runtime class name, which confirms `RoActivateInstance` really
    /// produced a SwapChainPanel.
    public var runtimeClassName: String {
        var raw: HSTRING?
        do {
            try inspectable.GetRuntimeClassName(&raw)
        } catch {
            return "<GetRuntimeClassName failed: \(error)>"
        }
        guard let raw else { return "<null>" }
        let name = String(from: raw)
        _ = WindowsDeleteString(raw)
        return name
    }

    /// Sets the layout size in DIPs. A `Canvas` child gets no size from
    /// layout, and a SwapChainPanel has no natural size, so without this it
    /// measures as zero and never composes.
    /// 設定版面配置尺寸（DIP）。Canvas 的子元件不會由版面配置取得尺寸，而
    /// SwapChainPanel 本身也沒有自然尺寸，未設定時會量測為零而不會被合成。
    public func setSize(width: Double, height: Double) throws {
        try frameworkElement.perform(
            as: __x_ABI_CMicrosoft_CUI_CXaml_CIFrameworkElement.self
        ) { pThis in
            try D3D11_CHECK(
                "IFrameworkElement::put_Width",
                pThis.pointee.lpVtbl.pointee.put_Width(pThis, width)
            )
            try D3D11_CHECK(
                "IFrameworkElement::put_Height",
                pThis.pointee.lpVtbl.pointee.put_Height(pThis, height)
            )
        }
    }

    /// The laid-out size in DIPs, or zero before the first layout pass.
    public func actualSize() throws -> SIMD2<Double> {
        try frameworkElement.perform(
            as: __x_ABI_CMicrosoft_CUI_CXaml_CIFrameworkElement.self
        ) { pThis in
            var width: DOUBLE = 0
            var height: DOUBLE = 0
            try D3D11_CHECK(
                "IFrameworkElement::get_ActualWidth",
                pThis.pointee.lpVtbl.pointee.get_ActualWidth(pThis, &width)
            )
            try D3D11_CHECK(
                "IFrameworkElement::get_ActualHeight",
                pThis.pointee.lpVtbl.pointee.get_ActualHeight(pThis, &height)
            )
            return SIMD2(width, height)
        }
    }

    /// Appends the panel to a projected parent's `Children`. The parent is a
    /// normal projected type, so only the child side needs raw COM.
    public func attach(to parent: WinUI.Panel) throws {
        let parentPanel: __ABI_Microsoft_UI_Xaml_Controls.IPanel =
            try parent.thisPtr.QueryInterface()

        try parentPanel.perform(
            as: __x_ABI_CMicrosoft_CUI_CXaml_CControls_CIPanel.self
        ) { pParent in
            var children:
                UnsafeMutablePointer<
                    __x_ABI_C__FIVector_1___x_ABI_CMicrosoft__CUI__CXaml__CUIElement
                >?
            try D3D11_CHECK(
                "IPanel::get_Children",
                pParent.pointee.lpVtbl.pointee.get_Children(pParent, &children)
            )
            guard let children else {
                throw D3D11Error.failed("IPanel::get_Children returned null", S_OK)
            }
            defer { _ = children.pointee.lpVtbl.pointee.Release(children) }

            try uiElement.perform(
                as: __x_ABI_CMicrosoft_CUI_CXaml_CIUIElement.self
            ) { pChild in
                try D3D11_CHECK(
                    "IVector<UIElement>::Append",
                    children.pointee.lpVtbl.pointee.Append(children, pChild)
                )
            }
        }
    }
}

/// Well-known public COM interface IIDs, hand-declared (matching the
/// `SwiftISwapChainPanelNative.IID` approach above) rather than linking
/// against dxguid.lib, so no extra linker settings are needed.
// Internal rather than private since 2026-09-04: WinUIBackend+GraphicsAdapters
// needs IDXGIFactory1 for `EnumAdapters1`, and a second hand-written copy of a
// GUID is a copy that can drift. One wrong hex digit produces E_NOINTERFACE at
// runtime and nothing at compile time, so the two copies would disagree
// silently -- the same reasoning as sharing `largestByArea` in the synthesiser.
// 自 2026-09-04 起改為 internal 而非 private：WinUIBackend+GraphicsAdapters 需要
// IDXGIFactory1 來呼叫 `EnumAdapters1`，而手寫 GUID 的第二份副本正是會漂移的那種副本。
// 一個十六進位數字打錯，在執行期得到 E_NOINTERFACE、在編譯期什麼也沒有，因此兩份副本會**靜默地**
// 不一致——與合成器中共用 `largestByArea` 的理由相同。
enum D3D11IID {
    // 770aae78-f26f-4dba-a829-253c83d1b387
    static var IDXGIFactory1: WinUIInterop.IID {
        WinUIInterop.IID(
            Data1: 0x770A_AE78,
            Data2: 0xF26F,
            Data3: 0x4DBA,
            Data4: (0xA8, 0x29, 0x25, 0x3C, 0x83, 0xD1, 0xB3, 0x87)
        )
    }

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

    // 10ec4d5b-975a-4689-b9e4-d0aac30fe333
    static var ID3D11VideoDevice: WinUIInterop.IID {
        WinUIInterop.IID(
            Data1: 0x10EC_4D5B,
            Data2: 0x975A,
            Data3: 0x4689,
            Data4: (0xB9, 0xE4, 0xD0, 0xAA, 0xC3, 0x0F, 0xE3, 0x33)
        )
    }

    // a7f026da-a5f8-4487-a564-15e34357651e
    static var ID3D11VideoContext1: WinUIInterop.IID {
        WinUIInterop.IID(
            Data1: 0xA7F0_26DA,
            Data2: 0xA5F8,
            Data3: 0x4487,
            Data4: (0xA5, 0x64, 0x15, 0xE3, 0x43, 0x57, 0x65, 0x1E)
        )
    }

    // a8be2ac4-199f-4946-b331-79599fb98de7
    static var IDXGISwapChain2: WinUIInterop.IID {
        WinUIInterop.IID(
            Data1: 0xA8BE_2AC4,
            Data2: 0x199F,
            Data3: 0x4946,
            Data4: (0xB3, 0x31, 0x79, 0x59, 0x9F, 0xB9, 0x8D, 0xE7)
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
///
/// `Raw` marks this as our own low-level wrapper, the same way
/// ``RawSwapChainPanel`` does. Without it the name sits one `I` away from the
/// SDK's `ID3D11Device`, which it holds a pointer to, in a file where nearly
/// every other type is a COM interface.
/// `Raw` 表示這是我方的低階包裝，與 ``RawSwapChainPanel`` 一致。若省略，名稱會與
/// 其所持有指標的 SDK 型別 `ID3D11Device` 僅差一個 `I`，而本檔案中幾乎其他所有
/// 型別都是 COM 介面。
public final class RawD3D11Device {
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
            throw D3D11Error.failed("D3D11CreateDevice returned a null device", S_OK)
        }
        self.device = device
        self.context = context
        self.factory = try RawD3D11Device.obtainFactory(from: device)
    }

    /// Walks device -> DXGI adapter -> DXGI factory, the standard way to get
    /// an `IDXGIFactory2` capable of `CreateSwapChainForComposition` without
    /// creating a second, unrelated factory via `CreateDXGIFactory2`.
    private static func obtainFactory(
        from device: UnsafeMutablePointer<ID3D11Device>
    ) throws -> UnsafeMutablePointer<IDXGIFactory2> {
        var dxgiDeviceIID = D3D11IID.IDXGIDevice
        var dxgiDeviceRaw: UnsafeMutableRawPointer?
        try D3D11_CHECK(
            "ID3D11Device::QueryInterface(IDXGIDevice)",
            device.pointee.lpVtbl.pointee.QueryInterface(device, &dxgiDeviceIID, &dxgiDeviceRaw)
        )
        guard let dxgiDeviceRaw else {
            throw D3D11Error.failed("QueryInterface(IDXGIDevice) returned null", S_OK)
        }
        let dxgiDevice = dxgiDeviceRaw.assumingMemoryBound(to: IDXGIDevice.self)
        defer { _ = dxgiDevice.pointee.lpVtbl.pointee.Release(dxgiDevice) }

        var adapter: UnsafeMutablePointer<IDXGIAdapter>?
        try D3D11_CHECK(
            "IDXGIDevice::GetAdapter",
            dxgiDevice.pointee.lpVtbl.pointee.GetAdapter(dxgiDevice, &adapter)
        )
        guard let adapter else {
            throw D3D11Error.failed("GetAdapter returned null", S_OK)
        }
        defer { _ = adapter.pointee.lpVtbl.pointee.Release(adapter) }

        var factoryIID = D3D11IID.IDXGIFactory2
        var factoryRaw: UnsafeMutableRawPointer?
        try D3D11_CHECK(
            "IDXGIAdapter::GetParent(IDXGIFactory2)",
            adapter.pointee.lpVtbl.pointee.GetParent(adapter, &factoryIID, &factoryRaw)
        )
        guard let factoryRaw else {
            throw D3D11Error.failed("GetParent(IDXGIFactory2) returned null", S_OK)
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
            throw D3D11Error.failed("CreateSwapChainForComposition returned null", S_OK)
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
            throw D3D11Error.failed("clearAndPresent called before attachSwapChain", S_OK)
        }

        var textureIID = D3D11IID.ID3D11Texture2D
        var backBufferRaw: UnsafeMutableRawPointer?
        try D3D11_CHECK(
            "IDXGISwapChain1::GetBuffer",
            swapChain.pointee.lpVtbl.pointee.GetBuffer(swapChain, 0, &textureIID, &backBufferRaw)
        )
        guard let backBufferRaw else {
            throw D3D11Error.failed("GetBuffer returned null", S_OK)
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
            throw D3D11Error.failed("CreateRenderTargetView returned null", S_OK)
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

// MARK: - Zero-copy composition video surface

/// Which GPU the presentation device is created on.
///
/// A composition swap chain is composed by DWM on the adapter that drives the
/// display. Presenting from any other adapter makes DXGI copy every frame
/// across the PCIe bus first, so `.display` is the right choice unless you are
/// deliberately measuring the difference.
/// composition swap chain 由 DWM 在「驅動該顯示器的介面卡」上合成。若從其他介面卡
/// 呈現，DXGI 必須先把每一張影格跨 PCIe 複製過去，因此除非是刻意量測差異，否則
/// 應使用 `.display`。
public enum GPUPreference: String, Sendable {
    /// DXGI's default adapter, which is the one driving the primary display.
    case display
    case amd
    case nvidia
    /// Microsoft's Basic Render Driver (WARP), which rasterises on the CPU.
    /// Useful as a no-GPU baseline.
    /// Microsoft 的 Basic Render Driver（WARP），以 CPU 進行光柵化，可作為「不用
    /// GPU」的基準線。
    case software

    var vendorID: UInt32? {
        switch self {
        case .display: return nil
        case .amd: return 0x1002
        case .nvidia: return 0x10DE
        case .software: return 0x1414
        }
    }
}

/// The pixel format frames are delivered and uploaded in.
///
/// Despite the name, NV12 has nothing to do with Nvidia -- "NV" is the FourCC,
/// and the D3D11 video processor that converts it is available on integrated
/// GPUs too. What it buys is size: NV12 stores full-resolution luma and
/// quarter-resolution chroma, 12 bits per pixel against RGBA's 32, so a 4K
/// frame is 12.4 MB instead of 33.2 MB. That matters because the decoder's
/// frames reach this process through a pipe, and at 4K60 the RGBA path needs
/// about 2 GB/s through it, which is past what it can carry.
/// NV12 與 Nvidia 無關 —— "NV" 是 FourCC，而負責轉換的 D3D11 video processor 在
/// 內顯上同樣可用。它換到的是尺寸：NV12 以全解析度儲存亮度、四分之一解析度儲存
/// 色度，每像素 12 位元，而 RGBA 是 32 位元，因此一張 4K 影格是 12.4 MB 而非
/// 33.2 MB。這很重要，因為解碼器的影格是經由管線送進本行程的，4K60 下 RGBA 需要
/// 約 2 GB/s，已超過管線能承載的量。
public enum VideoPixelFormat: String, Sendable {
    case rgba
    case nv12

    /// What ffmpeg's `-pix_fmt` has to be set to.
    public var ffmpegPixelFormat: String { rawValue }

    public var dxgiFormat: DXGI_FORMAT {
        switch self {
        case .rgba: return DXGI_FORMAT_R8G8B8A8_UNORM
        case .nv12: return DXGI_FORMAT_NV12
        }
    }

    public func frameByteCount(width: Int, height: Int) -> Int {
        switch self {
        case .rgba: return width * height * 4
        case .nv12: return width * height * 3 / 2
        }
    }
}

/// The on-screen area a video is presented into.
///
/// A SwapChainPanel composes one swap chain pixel per DIP, so the swap chain
/// has to be sized in the display's physical pixels to stay sharp, and then
/// mapped back down onto the viewport. Both numbers live here so a window
/// resize, a display-scale change, and a decoder resolution change all go
/// through the same path.
/// SwapChainPanel 以「一個 swap chain 像素對一個 DIP」的方式合成，因此 swap chain
/// 必須以顯示器的實體像素建立才能維持清晰，再映射回 viewport。兩個數值都放在
/// 這裡，讓視窗縮放、顯示器縮放比例變更與解碼解析度變更走同一條路徑。
public struct VideoViewport: Equatable, Sendable {
    /// The visible area in DIPs, which is what XAML lays out in.
    public var width: Double
    public var height: Double
    /// How many physical pixels one DIP is, i.e. `XamlRoot.rasterizationScale`.
    public var pixelsPerDIP: Double

    public init(width: Double, height: Double, pixelsPerDIP: Double) {
        self.width = width
        self.height = height
        self.pixelsPerDIP = pixelsPerDIP
    }

    /// The viewport in physical pixels: the swap chain resolution that maps
    /// one buffer pixel to one screen pixel.
    public var pixelSize: SIMD2<UInt32> {
        SIMD2(
            UInt32(max(1, (width * pixelsPerDIP).rounded())),
            UInt32(max(1, (height * pixelsPerDIP).rounded()))
        )
    }
}

/// A D3D11 composition swap chain bound to a `SwapChainPanel`, plus a rotating
/// pool of CPU-writable staging textures that decoded frames are written into
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
public final class D3D11VideoSurface {
    /// Matches the macOS Metal path's pool size: enough buffers that the CPU
    /// can fill one while the GPU still reads another.
    private static let poolSize = 3

    private let panel: RawSwapChainPanel
    private let device: UnsafeMutablePointer<ID3D11Device>
    private let context: UnsafeMutablePointer<ID3D11DeviceContext>
    private let factory: UnsafeMutablePointer<IDXGIFactory2>

    private var swapChain: UnsafeMutablePointer<IDXGISwapChain1>?
    private var pool: [UnsafeMutablePointer<ID3D11Texture2D>] = []
    private var poolIndex = 0
    private var frameWidth: UInt32 = 0
    private var frameHeight: UInt32 = 0
    private var bufferWidth: UInt32 = 0
    private var bufferHeight: UInt32 = 0

    /// The format frames arrive in. Fixed for the surface's lifetime because
    /// the decoder is told the same thing when it starts.
    /// 影格送達時的格式。在此表面的生命週期內固定不變，因為解碼器啟動時也被告知
    /// 同一個格式。
    public let format: VideoPixelFormat

    /// NV12 only: the video processor converts to RGB on the way to the back
    /// buffer. A video input view cannot be created on a STAGING resource, so
    /// each pool slot has a DEFAULT twin that the staging texture is copied
    /// into first.
    /// 僅 NV12 使用：video processor 會在送往 back buffer 的途中轉成 RGB。
    /// STAGING 資源無法建立 video input view，因此每個 pool slot 都有一個 DEFAULT
    /// 對應 texture，staging 會先複製過去。
    private var defaultPool: [UnsafeMutablePointer<ID3D11Texture2D>] = []
    private var inputViews: [UnsafeMutablePointer<ID3D11VideoProcessorInputView>] = []
    private var videoDevice: UnsafeMutablePointer<ID3D11VideoDevice>?
    private var videoContext: UnsafeMutablePointer<ID3D11VideoContext1>?
    private var processorEnumerator: UnsafeMutablePointer<ID3D11VideoProcessorEnumerator>?
    private var processor: UnsafeMutablePointer<ID3D11VideoProcessor>?

    /// A human-readable description of every adapter, and which one this
    /// surface ended up on.
    public private(set) var adapterReport = ""

    /// Whether this machine can convert NV12 to RGB with the D3D11 video
    /// processor, probed once against a throwaway device so the answer is
    /// available before any panel exists -- the decoder has to be told which
    /// pixel format to emit before the first frame.
    ///
    /// This is a capability probe rather than a check for a particular vendor:
    /// the video processor is a Direct3D feature, not an Nvidia one, and the
    /// software rasteriser is the case that actually lacks it.
    /// 以一個拋棄式裝置探測一次「本機能否用 D3D11 video processor 把 NV12 轉成
    /// RGB」，讓答案在任何面板存在之前就可取得 —— 解碼器必須在第一張影格之前就
    /// 知道要輸出哪種像素格式。這是能力探測而非廠商判斷：video processor 是
    /// Direct3D 的功能而非 Nvidia 的功能，真正缺少它的是軟體光柵化裝置。
    ///
    /// The probe runs on the adapter the surface will actually present from,
    /// because the answer differs per adapter: the hardware GPUs here support
    /// it and the software rasteriser does not, so probing the default adapter
    /// and then presenting from another one reports a capability that is not
    /// there.
    /// 探測必須在「表面實際用來呈現的那張介面卡」上進行，因為答案因卡而異：本機的
    /// 硬體 GPU 支援、軟體光柵化裝置不支援；若在預設介面卡上探測卻從另一張卡呈現，
    /// 回報的就會是一個並不存在的能力。
    public static func nv12Support(
        for gpu: GPUPreference = .display
    ) -> (isSupported: Bool, report: String) {
        let (adapter, _) = selectAdapter(for: gpu)
        defer {
            if let adapter { _ = adapter.pointee.lpVtbl.pointee.Release(adapter) }
        }

        var device: UnsafeMutablePointer<ID3D11Device>?
        var context: UnsafeMutablePointer<ID3D11DeviceContext>?
        var obtainedLevel = D3D_FEATURE_LEVEL_11_0
        let levels: [D3D_FEATURE_LEVEL] = [D3D_FEATURE_LEVEL_11_0]
        let created = levels.withUnsafeBufferPointer { levelsPtr in
            D3D11CreateDevice(
                adapter,
                adapter == nil ? D3D_DRIVER_TYPE_HARDWARE : D3D_DRIVER_TYPE_UNKNOWN,
                nil, 0,
                levelsPtr.baseAddress, UINT32(levelsPtr.count),
                UINT32(D3D11_SDK_VERSION), &device, &obtainedLevel, &context
            )
        }
        guard created >= 0, let device, let context else {
            return (false, "nv12: no D3D11 device")
        }
        defer {
            _ = context.pointee.lpVtbl.pointee.Release(context)
            _ = device.pointee.lpVtbl.pointee.Release(device)
        }

        var videoDeviceIID = D3D11IID.ID3D11VideoDevice
        var videoDeviceRaw: UnsafeMutableRawPointer?
        guard device.pointee.lpVtbl.pointee.QueryInterface(
            device, &videoDeviceIID, &videoDeviceRaw
        ) >= 0, let videoDeviceRaw else {
            return (false, "nv12: no ID3D11VideoDevice")
        }
        let videoDevice = videoDeviceRaw.assumingMemoryBound(to: ID3D11VideoDevice.self)
        defer { _ = videoDevice.pointee.lpVtbl.pointee.Release(videoDevice) }

        // A representative size; the enumerator is per content description, so
        // this only answers "does the format pair work at all".
        // 使用具代表性的尺寸；enumerator 依內容描述建立，因此這裡只回答「這組格式
        // 是否可行」。
        guard let enumerator = makeProcessorEnumerator(
            videoDevice: videoDevice,
            inputWidth: 1920, inputHeight: 1080,
            outputWidth: 1920, outputHeight: 1080
        ) else {
            return (false, "nv12: no video processor enumerator")
        }
        defer { _ = enumerator.pointee.lpVtbl.pointee.Release(enumerator) }

        let inputSupported = formatSupport(enumerator, DXGI_FORMAT_NV12) & 0x1 != 0
        let outputSupported =
            formatSupport(enumerator, DXGI_FORMAT_R8G8B8A8_UNORM) & 0x2 != 0
        let supported = inputSupported && outputSupported
        return (
            supported,
            "nv12: input \(inputSupported), output \(outputSupported)"
        )
    }

    /// D3D11_VIDEO_PROCESSOR_FORMAT_SUPPORT_INPUT is 1, _OUTPUT is 2.
    private static func formatSupport(
        _ enumerator: UnsafeMutablePointer<ID3D11VideoProcessorEnumerator>,
        _ format: DXGI_FORMAT
    ) -> UINT {
        var flags: UINT = 0
        guard enumerator.pointee.lpVtbl.pointee.CheckVideoProcessorFormat(
            enumerator, format, &flags
        ) >= 0 else {
            return 0
        }
        return flags
    }

    fileprivate static func makeProcessorEnumerator(
        videoDevice: UnsafeMutablePointer<ID3D11VideoDevice>,
        inputWidth: UInt32, inputHeight: UInt32,
        outputWidth: UInt32, outputHeight: UInt32
    ) -> UnsafeMutablePointer<ID3D11VideoProcessorEnumerator>? {
        var contentDesc = D3D11_VIDEO_PROCESSOR_CONTENT_DESC()
        contentDesc.InputFrameFormat = D3D11_VIDEO_FRAME_FORMAT_PROGRESSIVE
        contentDesc.InputWidth = inputWidth
        contentDesc.InputHeight = inputHeight
        contentDesc.OutputWidth = outputWidth
        contentDesc.OutputHeight = outputHeight
        contentDesc.Usage = D3D11_VIDEO_USAGE_PLAYBACK_NORMAL

        var enumerator: UnsafeMutablePointer<ID3D11VideoProcessorEnumerator>?
        let result = withUnsafePointer(to: &contentDesc) { descPtr in
            videoDevice.pointee.lpVtbl.pointee.CreateVideoProcessorEnumerator(
                videoDevice, descPtr, &enumerator
            )
        }
        return result >= 0 ? enumerator : nil
    }

    public init(
        panel: RawSwapChainPanel,
        gpu: GPUPreference = .display,
        format: VideoPixelFormat = .rgba
    ) throws {
        self.panel = panel
        self.format = format

        let (adapter, report) = D3D11VideoSurface.selectAdapter(for: gpu)
        adapterReport = report
        defer {
            if let adapter { _ = adapter.pointee.lpVtbl.pointee.Release(adapter) }
        }

        var device: UnsafeMutablePointer<ID3D11Device>?
        var context: UnsafeMutablePointer<ID3D11DeviceContext>?
        var obtainedLevel = D3D_FEATURE_LEVEL_11_0
        let levels: [D3D_FEATURE_LEVEL] = [D3D_FEATURE_LEVEL_11_0]
        try D3D11_CHECK(
            "D3D11CreateDevice",
            levels.withUnsafeBufferPointer { levelsPtr in
                // An explicit adapter requires DRIVER_TYPE_UNKNOWN; passing
                // HARDWARE with an adapter is an invalid-argument error.
                // 指定介面卡時必須用 DRIVER_TYPE_UNKNOWN；同時傳入 HARDWARE 與
                // 介面卡會得到參數錯誤。
                D3D11CreateDevice(
                    adapter,
                    adapter == nil ? D3D_DRIVER_TYPE_HARDWARE : D3D_DRIVER_TYPE_UNKNOWN,
                    nil, 0,
                    levelsPtr.baseAddress, UINT32(levelsPtr.count),
                    UINT32(D3D11_SDK_VERSION), &device, &obtainedLevel, &context
                )
            }
        )
        guard let device, let context else {
            throw D3D11Error.failed("D3D11CreateDevice returned null", S_OK)
        }
        self.device = device
        self.context = context
        self.factory = try RawD3D11Device.makeFactory(from: device)
    }

    /// Finds the adapter matching `gpu`, and describes every adapter found.
    /// Returns nil for `.display` (and when nothing matches), which leaves
    /// `D3D11CreateDevice` to pick DXGI's default.
    /// 依 `gpu` 找出對應的介面卡並描述所有介面卡。`.display`（以及找不到對應者時）
    /// 回傳 nil，交由 `D3D11CreateDevice` 選擇 DXGI 的預設介面卡。
    private static func selectAdapter(
        for gpu: GPUPreference
    ) -> (UnsafeMutablePointer<IDXGIAdapter>?, String) {
        var factoryIID = D3D11IID.IDXGIFactory1
        var factoryRaw: UnsafeMutableRawPointer?
        guard CreateDXGIFactory1(&factoryIID, &factoryRaw) >= 0, let factoryRaw else {
            return (nil, "adapters=<CreateDXGIFactory1 failed>")
        }
        let factory = factoryRaw.assumingMemoryBound(to: IDXGIFactory1.self)
        defer { _ = factory.pointee.lpVtbl.pointee.Release(factory) }

        var descriptions: [String] = []
        var selected: UnsafeMutablePointer<IDXGIAdapter>?
        var index: UINT = 0
        while true {
            var adapter: UnsafeMutablePointer<IDXGIAdapter1>?
            guard factory.pointee.lpVtbl.pointee.EnumAdapters1(factory, index, &adapter) >= 0,
                  let adapter
            else {
                break
            }
            var desc = DXGI_ADAPTER_DESC1()
            if adapter.pointee.lpVtbl.pointee.GetDesc1(adapter, &desc) >= 0 {
                let name = withUnsafeBytes(of: desc.Description) { raw in
                    String(decodingCString: raw.baseAddress!.assumingMemoryBound(to: UInt16.self),
                           as: UTF16.self)
                }
                descriptions.append("[\(index)] \(name) (vendor 0x\(String(desc.VendorId, radix: 16)))")
                if selected == nil, let wanted = gpu.vendorID, desc.VendorId == wanted {
                    selected = UnsafeMutableRawPointer(adapter)
                        .assumingMemoryBound(to: IDXGIAdapter.self)
                    index += 1
                    continue  // keep this one; do not release it
                }
            }
            _ = adapter.pointee.lpVtbl.pointee.Release(adapter)
            index += 1
        }

        let chosen = selected == nil ? "default" : gpu.rawValue
        return (selected, "adapters=\(descriptions.joined(separator: ", ")) using=\(chosen)")
    }

    /// Whether the pool and swap chain already match a given frame size.
    /// The decode thread checks this instead of configuring, because
    /// `configure` has to run on the UI thread.
    public func isConfigured(frameWidth: UInt32, frameHeight: UInt32) -> Bool {
        swapChain != nil && frameWidth == self.frameWidth && frameHeight == self.frameHeight
    }

    /// Presents `frameWidth`x`frameHeight` frames into `viewport`.
    ///
    /// This is the single entry point for every geometry change: a decoder
    /// resolution change, a window resize, or a move to a display with a
    /// different scale all just pass a new viewport or frame size. The swap
    /// chain and staging pool are rebuilt only when their sizes actually
    /// change; the mapping onto the viewport is re-applied either way.
    ///
    /// Sizing rules:
    /// - The buffer is the larger of the viewport and the frame, so a frame
    ///   smaller than the viewport is stretched up by DXGI (`SetSourceSize`)
    ///   and a larger one keeps its full resolution.
    /// - The transform is `viewport DIPs / buffer pixels`, which lands the
    ///   buffer exactly on the viewport at any resolution, including a 4K
    ///   frame scaled down into a small viewport, with no shader pass.
    ///
    /// **Must be called on the UI thread**: `ISwapChainPanelNative::SetSwapChain`
    /// is documented as UI-thread only. Map/CopyResource/Present stay callable
    /// from the decode thread.
    ///
    /// 這是所有幾何變更的唯一入口：解碼解析度變更、視窗縮放、移到不同縮放比例的
    /// 顯示器，都只是傳入新的 viewport 或影格尺寸。只有尺寸真的改變時才重建 swap
    /// chain 與 staging pool，映射則一律重新套用。
    /// 尺寸規則：buffer 取 viewport 與影格中較大者，較小的影格由 DXGI
    /// （`SetSourceSize`）拉伸，較大的則保留完整解析度；變換為「viewport DIP ÷
    /// buffer 像素」，任何解析度都能精準落在 viewport 上，包含 4K 影格縮入小
    /// viewport，且不需要 shader 階段。
    /// **必須在 UI 執行緒呼叫**：`ISwapChainPanelNative::SetSwapChain` 依文件僅能
    /// 於 UI 執行緒使用；Map/CopyResource/Present 仍可由解碼執行緒呼叫。
    public func setViewport(
        _ viewport: VideoViewport,
        frameWidth: UInt32,
        frameHeight: UInt32
    ) throws {
        let viewportPixels = viewport.pixelSize
        let bufferWidth = max(viewportPixels.x, frameWidth)
        let bufferHeight = max(viewportPixels.y, frameHeight)

        if !isConfigured(frameWidth: frameWidth, frameHeight: frameHeight)
            || bufferWidth != self.bufferWidth || bufferHeight != self.bufferHeight
        {
            try rebuild(
                frameWidth: frameWidth,
                frameHeight: frameHeight,
                bufferWidth: bufferWidth,
                bufferHeight: bufferHeight
            )
        }

        // The presented region differs per path. RGBA copies the frame into the
        // buffer's corner and lets DXGI stretch that region out, so the source
        // is the frame. NV12 goes through the video processor, which scales the
        // frame across the whole buffer, so the source is the whole buffer --
        // asking for the frame region there would present only its top-left
        // corner, stretched. That is invisible whenever the frame is at least
        // as large as the viewport, because the buffer is then the frame size;
        // it shows up at 960x540 into a 1200x675 viewport.
        // 兩條路徑呈現的區域不同。RGBA 是把影格複製到 buffer 的角落，再交給 DXGI
        // 把該區域拉伸開，因此來源是「影格」。NV12 走 video processor，它會把影格
        // 縮放填滿整個 buffer，因此來源是「整個 buffer」；若在此仍指定影格區域，
        // 呈現出來的只會是其左上角並被拉伸。影格不小於檢視區時看不出差異（此時
        // buffer 就等於影格尺寸），只有像 960x540 進 1200x675 檢視區時才會顯現。
        if format == .nv12 {
            try setSourceSize(width: bufferWidth, height: bufferHeight)
        } else {
            try setSourceSize(width: frameWidth, height: frameHeight)
        }
        try setMatrixTransform(
            x: Float(viewport.width / Double(bufferWidth)),
            y: Float(viewport.height / Double(bufferHeight))
        )
    }

    /// Whether the swap chain and pool have to be recreated for these sizes.
    /// Callers use it to know when to detach the surface from the decode
    /// thread first.
    /// swap chain 與 pool 是否需要為這組尺寸重建；呼叫端據此判斷是否要先把表面
    /// 自解碼執行緒卸離。
    public func needsRebuild(
        for viewport: VideoViewport, frameWidth: UInt32, frameHeight: UInt32
    ) -> Bool {
        let viewportPixels = viewport.pixelSize
        return !isConfigured(frameWidth: frameWidth, frameHeight: frameHeight)
            || max(viewportPixels.x, frameWidth) != bufferWidth
            || max(viewportPixels.y, frameHeight) != bufferHeight
    }

    private func rebuild(
        frameWidth: UInt32,
        frameHeight: UInt32,
        bufferWidth: UInt32,
        bufferHeight: UInt32
    ) throws {
        releaseFrameResources()

        var desc = DXGI_SWAP_CHAIN_DESC1()
        desc.Width = bufferWidth
        desc.Height = bufferHeight
        desc.Format = DXGI_FORMAT_R8G8B8A8_UNORM
        desc.SampleDesc.Count = 1
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
                    UnsafeMutableRawPointer(device).assumingMemoryBound(
                        to: WinUIInterop.IUnknown.self
                    ),
                    descPtr, nil, &created
                )
            }
        )
        guard let created else {
            throw D3D11Error.failed("CreateSwapChainForComposition returned null", S_OK)
        }
        try panel.native.setSwapChain(
            UnsafeMutableRawPointer(created).assumingMemoryBound(to: IDXGISwapChain.self)
        )
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
        textureDesc.Format = format.dxgiFormat
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
                throw D3D11Error.failed("CreateTexture2D returned null", S_OK)
            }
            pool.append(texture)
        }

        if format == .nv12 {
            try buildVideoProcessor(
                frameWidth: frameWidth,
                frameHeight: frameHeight,
                bufferWidth: bufferWidth,
                bufferHeight: bufferHeight,
                textureDesc: textureDesc
            )
        }

        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
        self.bufferWidth = bufferWidth
        self.bufferHeight = bufferHeight
    }

    /// Scales the swap chain's contents as they are composed. Kept alongside
    /// `setSourceSize` because the two act at different points and only a
    /// measurement can say which one the panel actually honours.
    /// 與 `setSourceSize` 並存：兩者作用的階段不同，只有實測才能得知面板實際採用
    /// 的是哪一個。
    private func setMatrixTransform(x: Float, y: Float) throws {
        try withSwapChain2 { swapChain2 in
            var matrix = DXGI_MATRIX_3X2_F()
            matrix._11 = x
            matrix._22 = y
            try D3D11_CHECK(
                "IDXGISwapChain2::SetMatrixTransform",
                withUnsafePointer(to: &matrix) { matrixPtr in
                    swapChain2.pointee.lpVtbl.pointee.SetMatrixTransform(swapChain2, matrixPtr)
                }
            )
        }
    }

    private func withSwapChain2(
        _ body: (UnsafeMutablePointer<IDXGISwapChain2>) throws -> Void
    ) throws {
        guard let swapChain else { return }

        var swapChain2IID = D3D11IID.IDXGISwapChain2
        var raw: UnsafeMutableRawPointer?
        try D3D11_CHECK(
            "IDXGISwapChain1::QueryInterface(IDXGISwapChain2)",
            swapChain.pointee.lpVtbl.pointee.QueryInterface(
                swapChain, &swapChain2IID, &raw
            )
        )
        guard let raw else {
            throw D3D11Error.failed("QueryInterface(IDXGISwapChain2) returned null", S_OK)
        }
        let swapChain2 = raw.assumingMemoryBound(to: IDXGISwapChain2.self)
        defer { _ = swapChain2.pointee.lpVtbl.pointee.Release(swapChain2) }
        try body(swapChain2)
    }

    /// Builds the GPU-side half of the NV12 path: a DEFAULT texture per pool
    /// slot, an input view on each, and the processor that converts NV12 to the
    /// back buffer's RGB while scaling frame size to buffer size.
    /// 建立 NV12 路徑的 GPU 端：每個 pool slot 一張 DEFAULT texture、各自的 input
    /// view，以及負責把 NV12 轉成 back buffer 的 RGB 並同時把影格尺寸縮放到 buffer
    /// 尺寸的 processor。
    private func buildVideoProcessor(
        frameWidth: UInt32,
        frameHeight: UInt32,
        bufferWidth: UInt32,
        bufferHeight: UInt32,
        textureDesc: D3D11_TEXTURE2D_DESC
    ) throws {
        var videoDeviceIID = D3D11IID.ID3D11VideoDevice
        var videoDeviceRaw: UnsafeMutableRawPointer?
        try D3D11_CHECK(
            "ID3D11Device::QueryInterface(ID3D11VideoDevice)",
            device.pointee.lpVtbl.pointee.QueryInterface(
                device, &videoDeviceIID, &videoDeviceRaw
            )
        )
        guard let videoDeviceRaw else {
            throw D3D11Error.failed("QueryInterface(ID3D11VideoDevice) null", S_OK)
        }
        let videoDevice = videoDeviceRaw.assumingMemoryBound(to: ID3D11VideoDevice.self)
        self.videoDevice = videoDevice

        var videoContextIID = D3D11IID.ID3D11VideoContext1
        var videoContextRaw: UnsafeMutableRawPointer?
        try D3D11_CHECK(
            "ID3D11DeviceContext::QueryInterface(ID3D11VideoContext1)",
            context.pointee.lpVtbl.pointee.QueryInterface(
                context, &videoContextIID, &videoContextRaw
            )
        )
        guard let videoContextRaw else {
            throw D3D11Error.failed("QueryInterface(ID3D11VideoContext1) null", S_OK)
        }
        let videoContext = videoContextRaw.assumingMemoryBound(to: ID3D11VideoContext1.self)
        self.videoContext = videoContext

        guard let enumerator = Self.makeProcessorEnumerator(
            videoDevice: videoDevice,
            inputWidth: frameWidth, inputHeight: frameHeight,
            outputWidth: bufferWidth, outputHeight: bufferHeight
        ) else {
            throw D3D11Error.failed("CreateVideoProcessorEnumerator", S_OK)
        }
        processorEnumerator = enumerator

        var processor: UnsafeMutablePointer<ID3D11VideoProcessor>?
        try D3D11_CHECK(
            "ID3D11VideoDevice::CreateVideoProcessor",
            videoDevice.pointee.lpVtbl.pointee.CreateVideoProcessor(
                videoDevice, enumerator, 0, &processor
            )
        )
        guard let processor else {
            throw D3D11Error.failed("CreateVideoProcessor returned null", S_OK)
        }
        self.processor = processor

        // Stated rather than left to the driver's default: getting this wrong
        // is silent, and shows up as washed-out or green-tinted video rather
        // than as an error. ffmpeg's rgba/nv12 output for HD is BT.709 with
        // studio range, and the swap chain is full-range sRGB.
        // 明確指定而非交給驅動預設：設錯不會報錯，只會讓畫面泛白或偏綠。ffmpeg 對
        // HD 的 nv12 輸出是 BT.709、studio range，而 swap chain 是 full range sRGB。
        videoContext.pointee.lpVtbl.pointee.VideoProcessorSetStreamColorSpace1(
            videoContext, processor, 0, DXGI_COLOR_SPACE_YCBCR_STUDIO_G22_LEFT_P709
        )
        videoContext.pointee.lpVtbl.pointee.VideoProcessorSetOutputColorSpace1(
            videoContext, processor, DXGI_COLOR_SPACE_RGB_FULL_G22_NONE_P709
        )

        // A video processor input has to be bound as decoder output, not as a
        // shader resource: the video engine reads it, the shader units do not.
        // Using D3D11_BIND_SHADER_RESOURCE here fails CreateVideoProcessorInputView
        // with E_INVALIDARG.
        // video processor 的輸入必須以 decoder 輸出的身分繫結，而非 shader
        // resource：讀取它的是視訊引擎而非著色器單元。此處若用
        // D3D11_BIND_SHADER_RESOURCE，CreateVideoProcessorInputView 會回
        // E_INVALIDARG。
        var defaultDesc = textureDesc
        defaultDesc.Usage = D3D11_USAGE_DEFAULT
        defaultDesc.CPUAccessFlags = 0
        defaultDesc.BindFlags = UINT(D3D11_BIND_DECODER.rawValue)

        for _ in 0..<Self.poolSize {
            var texture: UnsafeMutablePointer<ID3D11Texture2D>?
            try D3D11_CHECK(
                "ID3D11Device::CreateTexture2D(default NV12)",
                withUnsafeMutablePointer(to: &defaultDesc) { descPtr in
                    device.pointee.lpVtbl.pointee.CreateTexture2D(
                        device, descPtr, nil, &texture
                    )
                }
            )
            guard let texture else {
                throw D3D11Error.failed("CreateTexture2D(default) null", S_OK)
            }
            defaultPool.append(texture)

            var viewDesc = D3D11_VIDEO_PROCESSOR_INPUT_VIEW_DESC()
            viewDesc.FourCC = 0
            viewDesc.ViewDimension = D3D11_VPIV_DIMENSION_TEXTURE2D
            viewDesc.Texture2D.MipSlice = 0
            viewDesc.Texture2D.ArraySlice = 0

            var view: UnsafeMutablePointer<ID3D11VideoProcessorInputView>?
            try D3D11_CHECK(
                "ID3D11VideoDevice::CreateVideoProcessorInputView",
                withUnsafePointer(to: &viewDesc) { descPtr in
                    videoDevice.pointee.lpVtbl.pointee.CreateVideoProcessorInputView(
                        videoDevice,
                        UnsafeMutableRawPointer(texture)
                            .assumingMemoryBound(to: ID3D11Resource.self),
                        enumerator, descPtr, &view
                    )
                }
            )
            guard let view else {
                throw D3D11Error.failed("CreateVideoProcessorInputView null", S_OK)
            }
            inputViews.append(view)
        }
    }

    /// Restricts presentation to the frame-sized top-left corner of a larger
    /// back buffer, which DXGI then stretches over the whole swap chain.
    ///
    /// This is what makes a 960x540 frame cover a panel that is far more
    /// pixels wide: the buffer is sized to the panel, the frame is copied into
    /// its corner, and `DXGI_SCALING_STRETCH` scales that region up on present
    /// with no shader pass of our own.
    /// 這就是讓 960x540 的影格能覆蓋像素數大得多的面板的方法：buffer 依面板尺寸
    /// 建立，影格複製到左上角，`DXGI_SCALING_STRETCH` 在 present 時把該區域放大，
    /// 不需要自己寫 shader。
    private func setSourceSize(width: UInt32, height: UInt32) throws {
        try withSwapChain2 { swapChain2 in
            try D3D11_CHECK(
                "IDXGISwapChain2::SetSourceSize",
                swapChain2.pointee.lpVtbl.pointee.SetSourceSize(swapChain2, width, height)
            )
        }
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
    /// `body` receives the destination, the row pitch, and the total mapped
    /// size. The size matters for NV12: the chroma plane follows the luma
    /// plane in the same mapping, and its offset has to be derived rather than
    /// assumed.
    /// `body` 會取得目的地位址、列間距與整段對映的大小。大小對 NV12 很重要：色度
    /// 平面接在亮度平面之後、位於同一段對映中，其偏移量必須推算而非假設。
    public func writeFrame(
        _ body: (UnsafeMutableRawPointer, Int, Int) throws -> Void
    ) throws {
        guard !pool.isEmpty else {
            throw D3D11Error.failed("writeFrame called before configure", S_OK)
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
            throw D3D11Error.failed("Map returned null pData", S_OK)
        }
        try body(destination, Int(mapped.RowPitch), Int(mapped.DepthPitch))
    }

    /// Copies the most recently written staging texture to the back buffer and
    /// presents it. Presentation is driven by frame arrival, exactly like the
    /// Metal path, rather than by a separate render timer.
    public func present() throws {
        guard let swapChain, !pool.isEmpty else { return }
        let lastIndex = (poolIndex + pool.count - 1) % pool.count
        let source = UnsafeMutableRawPointer(pool[lastIndex])
            .assumingMemoryBound(to: ID3D11Resource.self)

        var textureIID = D3D11IID.ID3D11Texture2D
        var backBufferRaw: UnsafeMutableRawPointer?
        try D3D11_CHECK(
            "IDXGISwapChain1::GetBuffer",
            swapChain.pointee.lpVtbl.pointee.GetBuffer(
                swapChain, 0, &textureIID, &backBufferRaw
            )
        )
        guard let backBufferRaw else {
            throw D3D11Error.failed("GetBuffer returned null", S_OK)
        }
        let backBuffer = backBufferRaw.assumingMemoryBound(to: ID3D11Texture2D.self)
        defer { _ = backBuffer.pointee.lpVtbl.pointee.Release(backBuffer) }

        if format == .nv12 {
            try convertToBackBuffer(lastIndex: lastIndex, backBuffer: backBuffer)
        } else {
            // The back buffer is sized to the panel, which is usually larger
            // than the frame, so the frame goes into its top-left corner and
            // the source region set at configure time is what actually gets
            // presented.
            // back buffer 依面板尺寸建立，通常大於影格，因此影格放在左上角，實際
            // 呈現的是 configure 時設定的來源區域。
            context.pointee.lpVtbl.pointee.CopySubresourceRegion(
                context,
                UnsafeMutableRawPointer(backBuffer)
                    .assumingMemoryBound(to: ID3D11Resource.self),
                0, 0, 0, 0,
                source, 0, nil
            )
        }
        try D3D11_CHECK(
            "IDXGISwapChain1::Present",
            swapChain.pointee.lpVtbl.pointee.Present(swapChain, 1, 0)
        )
    }

    /// NV12: copy the written staging texture to its DEFAULT twin, then let the
    /// video processor convert and scale it into the back buffer. The blt does
    /// the scaling, so the source-region stretch used by the RGBA path is not
    /// needed here.
    /// NV12：把寫好的 staging texture 複製到對應的 DEFAULT texture，再由 video
    /// processor 轉換並縮放進 back buffer。縮放由 blt 完成，因此不需要 RGBA 路徑
    /// 使用的來源區域拉伸。
    private func convertToBackBuffer(
        lastIndex: Int,
        backBuffer: UnsafeMutablePointer<ID3D11Texture2D>
    ) throws {
        guard let videoDevice, let videoContext, let processor, let processorEnumerator,
              lastIndex < defaultPool.count, lastIndex < inputViews.count
        else {
            throw D3D11Error.failed("NV12 present before the processor was built", S_OK)
        }

        context.pointee.lpVtbl.pointee.CopyResource(
            context,
            UnsafeMutableRawPointer(defaultPool[lastIndex])
                .assumingMemoryBound(to: ID3D11Resource.self),
            UnsafeMutableRawPointer(pool[lastIndex])
                .assumingMemoryBound(to: ID3D11Resource.self)
        )

        // Created per present: with a flip-model swap chain the back buffer
        // rotates, so a cached view would target the wrong texture.
        // 每次呈現時建立：flip model 的 back buffer 會輪替，快取的 view 會指到
        // 錯誤的 texture。
        var outputDesc = D3D11_VIDEO_PROCESSOR_OUTPUT_VIEW_DESC()
        outputDesc.ViewDimension = D3D11_VPOV_DIMENSION_TEXTURE2D
        outputDesc.Texture2D.MipSlice = 0

        var outputView: UnsafeMutablePointer<ID3D11VideoProcessorOutputView>?
        try D3D11_CHECK(
            "ID3D11VideoDevice::CreateVideoProcessorOutputView",
            withUnsafePointer(to: &outputDesc) { descPtr in
                videoDevice.pointee.lpVtbl.pointee.CreateVideoProcessorOutputView(
                    videoDevice,
                    UnsafeMutableRawPointer(backBuffer)
                        .assumingMemoryBound(to: ID3D11Resource.self),
                    processorEnumerator, descPtr, &outputView
                )
            }
        )
        guard let outputView else {
            throw D3D11Error.failed("CreateVideoProcessorOutputView null", S_OK)
        }
        defer { _ = outputView.pointee.lpVtbl.pointee.Release(outputView) }

        var stream = D3D11_VIDEO_PROCESSOR_STREAM()
        stream.Enable = true
        stream.pInputSurface = inputViews[lastIndex]

        try D3D11_CHECK(
            "ID3D11VideoContext::VideoProcessorBlt",
            withUnsafePointer(to: &stream) { streamPtr in
                videoContext.pointee.lpVtbl.pointee.VideoProcessorBlt(
                    videoContext, processor, outputView, 0, 1, streamPtr
                )
            }
        )
    }

    private func releaseFrameResources() {
        for texture in pool {
            _ = texture.pointee.lpVtbl.pointee.Release(texture)
        }
        pool.removeAll()
        poolIndex = 0

        for view in inputViews {
            _ = view.pointee.lpVtbl.pointee.Release(view)
        }
        inputViews.removeAll()
        for texture in defaultPool {
            _ = texture.pointee.lpVtbl.pointee.Release(texture)
        }
        defaultPool.removeAll()
        if let processor {
            _ = processor.pointee.lpVtbl.pointee.Release(processor)
        }
        processor = nil
        if let processorEnumerator {
            _ = processorEnumerator.pointee.lpVtbl.pointee.Release(processorEnumerator)
        }
        processorEnumerator = nil
        if let videoContext {
            _ = videoContext.pointee.lpVtbl.pointee.Release(videoContext)
        }
        videoContext = nil
        if let videoDevice {
            _ = videoDevice.pointee.lpVtbl.pointee.Release(videoDevice)
        }
        videoDevice = nil
        if let swapChain {
            _ = swapChain.pointee.lpVtbl.pointee.Release(swapChain)
        }
        swapChain = nil
        frameWidth = 0
        frameHeight = 0
        bufferWidth = 0
        bufferHeight = 0
    }

    deinit {
        releaseFrameResources()
        _ = context.pointee.lpVtbl.pointee.Release(context)
        _ = device.pointee.lpVtbl.pointee.Release(device)
        _ = factory.pointee.lpVtbl.pointee.Release(factory)
    }
}
