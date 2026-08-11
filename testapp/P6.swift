import DefaultBackend
import Dispatch
import Foundation
import ImageFormats
@_spi(Backends) import SwiftCrossUI

#if os(macOS)
import AppKit
import AppKitBackend
import Darwin
import Metal
import MetalKit
#endif

#if os(Windows)
import UWP
import WinSDK
import WinUI
import WinUIBackend
import WindowsFoundation

/// Phase 0/1 spike view: activates a native `SwapChainPanel`, attaches a
/// D3D11 composition swap chain, and presents a solid clear color. This
/// exists only to visually confirm WinUI's compositor actually renders a
/// SwapChainPanel obtained via `RoActivateInstance` before real video frames
/// are wired in. See the plan at
/// C:\Users\lowei\.claude\plans\quizzical-jingling-music.md.
/// Shared handle to the D3D11 surface so the background decode task can write
/// frames into it directly.
///
/// D3D11 devices serialise immediate-context calls internally unless created
/// with SINGLETHREADED, so Map/CopyResource/Present are safe from the decode
/// thread. Keeping them off the main actor is deliberate: it removes the
/// per-frame main-thread hop and the view-graph update that the old
/// ImageFormats path required.
/// D3D11 裝置預設會在內部序列化 immediate context 的呼叫（除非以 SINGLETHREADED
/// 建立），因此可安全地從解碼執行緒呼叫 Map/CopyResource/Present。刻意不放在
/// 主執行者上：可省去每幀切回主執行緒，以及舊 ImageFormats 路徑所需的 view
/// graph 更新。
final class P6VideoSurfaceBox: @unchecked Sendable {
    private let lock = NSLock()
    private var surface: P6D3D11VideoSurface?

    func set(_ surface: P6D3D11VideoSurface?) {
        lock.lock()
        defer { lock.unlock() }
        self.surface = surface
    }

    func withSurface<T>(_ body: (P6D3D11VideoSurface) throws -> T) rethrows -> T? {
        lock.lock()
        defer { lock.unlock() }
        guard let surface else { return nil }
        return try body(surface)
    }
}

/// Result holder for the EnumThreadWindows callback, which is a C function
/// pointer and so cannot capture anything.
/// EnumThreadWindows 的 callback 是 C 函式指標、無法捕捉外部變數，因此用它來
/// 承接結果。
final class P6WindowSearch {
    var hwnd: HWND?
}

/// Applies `-maximized` once the XAML window exists.
///
/// There is no window handle at app start, so this is driven from the video
/// view's first update, which runs on the main actor after the window is up.
/// App 啟動當下還沒有視窗控制代碼，因此改由影片 view 的首次更新觸發：該時點在
/// 主執行者上執行，視窗已經存在。
enum P6WindowFlags {
    static let isMaximizedRequested = CommandLine.arguments.contains("-maximized")

    /// `-calib` fills the swap chain with a measurable pattern instead of
    /// video, so one screenshot gives the exact mapping from swap chain pixels
    /// to screen pixels. This is the regression check for the viewport maths.
    /// `-calib` 會以可量測的圖樣填滿 swap chain 而非影片，單張截圖即可得知 swap
    /// chain 像素與螢幕像素的精確對應；這是 viewport 計算的迴歸檢查方式。
    static let isCalibration = CommandLine.arguments.contains("-calib")
    private static var didLogMetrics = false

    /// Retried on every layout pass until it takes: the backend applies its
    /// own size after the window appears, which undoes an early maximize.
    /// 每次版面配置都重試直到生效：視窗出現後 backend 會再套用自己的尺寸，
    /// 過早的最大化會被蓋掉。
    /// `-topmost` keeps the window above others without needing focus, which
    /// is what makes an unattended screenshot capture it: a background process
    /// cannot take the foreground on Windows, so activating the window from a
    /// script does not work.
    /// `-topmost` 讓視窗不需焦點也保持在最上層，無人值守的螢幕擷取才能拍到它：
    /// Windows 不允許背景行程搶前景，因此由指令稿啟動視窗是行不通的。
    static let isTopmostRequested = CommandLine.arguments.contains("-topmost")

    static func applyIfNeeded() {
        guard let hwnd = topLevelWindow() else { return }
        logMetricsOnce(hwnd)
        if isTopmostRequested {
            // Re-applied every time rather than once: the backend resizes the
            // window with its own SetWindowPos, which drops the topmost state.
            // HWND_TOPMOST is `((HWND)-1)`, a macro Swift does not import.
            // 每次都重新套用而非只做一次：backend 會以自己的 SetWindowPos 調整
            // 視窗尺寸，那會清掉置頂狀態。
            // HWND_TOPMOST 是 `((HWND)-1)` 巨集，Swift 不會匯入。
            _ = SetWindowPos(
                hwnd, HWND(bitPattern: -1), 0, 0, 0, 0,
                UINT(SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE)
            )
        }
        // Retried until it takes, then latched: the backend applies its own
        // size after the window appears, which undoes a maximize done too
        // early. Latching on the first pass that observes it stick is what
        // leaves the user free to restore the window afterwards.
        // 重試到生效為止，之後就閂住：視窗出現後 backend 會套用自己的尺寸，太早
        // 最大化會被蓋掉。在觀察到生效的第一輪就閂住，使用者之後才還原得了視窗。
        guard isMaximizedRequested, !didMaximize else { return }
        if IsZoomed(hwnd) {
            didMaximize = true
        } else {
            _ = ShowWindow(hwnd, SW_MAXIMIZE)
        }
    }

    private static var didMaximize = false

    /// The numbers needed to work out how a swap chain's pixels map onto the
    /// panel: the window's DPI, its client size in physical pixels, and the
    /// screen size this process sees (which is the virtualised size if the
    /// process is not per-monitor DPI aware).
    /// 用來推算 swap chain 像素如何對應到面板的數據：視窗 DPI、client 區的實體
    /// 像素尺寸，以及本行程看到的螢幕尺寸（若行程非 per-monitor DPI aware，這會
    /// 是虛擬化後的尺寸）。
    private static func logMetricsOnce(_ hwnd: HWND) {
        guard !didLogMetrics else { return }
        didLogMetrics = true
        var client = RECT()
        _ = GetClientRect(hwnd, &client)
        P6Diagnostics.write(
            "window metrics: dpi \(GetDpiForWindow(hwnd)) "
                + "client \(client.right - client.left)x\(client.bottom - client.top) px, "
                + "screen \(GetSystemMetrics(SM_CXSCREEN))x\(GetSystemMetrics(SM_CYSCREEN)) px, "
                + "systemDpi \(GetDpiForSystem()), "
                + "display mode \(displayMode().x)x\(displayMode().y) px, "
                + "virtualization \(virtualizationFactor), "
                + "monitor dpi \(monitorDPI(for: hwnd).map(String.init) ?? "unknown")"
        )
    }

    /// The display's real pixel mode, which `EnumDisplaySettingsW` reports
    /// regardless of the process's DPI awareness.
    /// `EnumDisplaySettingsW` 回報的是顯示器真實的像素模式，不受行程 DPI
    /// awareness 影響。
    private static func displayMode() -> SIMD2<Int> {
        // ENUM_CURRENT_SETTINGS is `((DWORD)-1)`, which Swift imports as an
        // unsigned constant while the parameter is signed, so spell it out.
        // ENUM_CURRENT_SETTINGS 是 `((DWORD)-1)`，Swift 會匯入成無號常數，但參數
        // 是有號型別，因此直接寫出數值。
        let currentSettings = DWORD.max
        var mode = DEVMODEW()
        mode.dmSize = WORD(MemoryLayout<DEVMODEW>.size)
        guard EnumDisplaySettingsW(nil, currentSettings, &mode) else {
            return SIMD2(0, 0)
        }
        return SIMD2(Int(mode.dmPelsWidth), Int(mode.dmPelsHeight))
    }

    /// How much DWM stretches this process's output to reach real pixels.
    ///
    /// A process that is only system-DPI aware is handed a virtualised screen
    /// size and its output is stretched to the monitor's real scaling. XAML's
    /// `rasterizationScale` describes DIPs to *process* pixels, while a D3D
    /// swap chain is composed in *real* pixels, so a swap chain has to be this
    /// much larger again to cover the same area.
    /// 僅具 system DPI awareness 的行程會拿到虛擬化的螢幕尺寸，其輸出再由 DWM
    /// 拉伸到顯示器真實的縮放比例。XAML 的 `rasterizationScale` 描述的是 DIP 對
    /// 「行程像素」，而 D3D swap chain 是以「真實像素」合成，因此 swap chain 還
    /// 要再放大這個倍率才能覆蓋同一塊區域。
    static var virtualizationFactor: Double {
        let real = Double(displayMode().x)
        let seen = Double(GetSystemMetrics(SM_CXSCREEN))
        guard real > 0, seen > 0 else { return 1 }
        return real / seen
    }

    /// The monitor's own effective DPI.
    ///
    /// `GetDpiForWindow` reports the DPI the *process* works in, which for a
    /// system-DPI-aware process is the system setting rather than the
    /// monitor's. A composition swap chain is composed against the monitor, so
    /// this is the number its pixels are measured in.
    ///
    /// Loaded from shcore.dll at runtime, matching how `HWNDInterop.swift`
    /// reaches APIs that aren't in a linked import library.
    /// `GetDpiForWindow` 回報的是「行程」所使用的 DPI；對僅具 system DPI
    /// awareness 的行程來說那是系統設定值，而非顯示器的值。composition swap
    /// chain 是對著顯示器合成，因此其像素是以此為單位。
    /// 以執行期載入 shcore.dll 取得，作法與 `HWNDInterop.swift` 取用未連結匯入
    /// 函式庫之 API 的方式一致。
    static func monitorDPI(for hwnd: HWND) -> UInt32? {
        typealias GetDpiForMonitor = @convention(c) (
            HMONITOR?, Int32, UnsafeMutablePointer<UINT>?, UnsafeMutablePointer<UINT>?
        ) -> HRESULT

        guard let library = "shcore.dll".withCString(encodedAs: UTF16.self, LoadLibraryW) else {
            return nil
        }
        defer { FreeLibrary(library) }
        guard let symbol = GetProcAddress(library, "GetDpiForMonitor") else { return nil }
        let getDpiForMonitor = unsafeBitCast(symbol, to: GetDpiForMonitor.self)

        guard let monitor = MonitorFromWindow(hwnd, DWORD(MONITOR_DEFAULTTONEAREST)) else {
            return nil
        }
        var x: UINT = 0
        var y: UINT = 0
        // MDT_EFFECTIVE_DPI == 0
        guard getDpiForMonitor(monitor, 0, &x, &y) >= 0, x > 0 else { return nil }
        return x
    }


    private static func topLevelWindow() -> HWND? {
        if let active = GetActiveWindow() { return active }

        let search = P6WindowSearch()
        _ = EnumThreadWindows(
            GetCurrentThreadId(),
            { hwnd, lParam in
                guard let hwnd, IsWindowVisible(hwnd) else { return true }
                guard let raw = UnsafeMutableRawPointer(bitPattern: Int(lParam)) else {
                    return true
                }
                Unmanaged<P6WindowSearch>.fromOpaque(raw)
                    .takeUnretainedValue()
                    .hwnd = hwnd
                return false
            },
            LPARAM(Int(bitPattern: Unmanaged.passUnretained(search).toOpaque()))
        )
        return search.hwnd ?? GetForegroundWindow()
    }
}

final class P6D3D11SpikeCoordinator {
    var device: P6D3D11Device?
    var panel: P6SwapChainPanel?
    var presentCount = 0
}

final class P6D3D11VideoCoordinator {
    var panel: P6SwapChainPanel?
    var surface: P6D3D11VideoSurface?
    /// Stops retrying after a genuine failure, so the log is not spammed on
    /// every layout pass.
    /// 真正失敗後不再重試，避免每次版面配置都寫入相同的 log。
    var setupFailed = false
    var configuredSize: SIMD2<UInt32>?
    var configuredViewport: P6VideoViewport?
}

/// Hosts the video SwapChainPanel over the video viewport.
///
/// A plain `WinUI.Canvas` is the representable element -- it is a projected
/// swift-winui type, so its wrapper works -- and the SwapChainPanel is added
/// as its child through raw COM.
/// 代表元件使用一般的 `WinUI.Canvas`：它是 swift-winui 已投影的型別，包裝可正常
/// 運作；SwapChainPanel 則以原始 COM 加入為其子元件。
struct P6D3D11VideoView: WinUIElementRepresentable {
    typealias WinUIElementType = WinUI.Canvas
    typealias Coordinator = P6D3D11VideoCoordinator

    var surfaceBox: P6VideoSurfaceBox
    var width: Int32
    var height: Int32
    /// The decoder's output size, which is what the swap chain has to match.
    /// 解碼輸出尺寸，swap chain 必須與其一致。
    var frameWidth: UInt32
    var frameHeight: UInt32

    func makeCoordinator() -> Coordinator {
        P6D3D11VideoCoordinator()
    }

    func makeWinUIElement(context: Context) -> WinUI.Canvas {
        WinUI.Canvas()
    }

    /// A `Canvas` never measures its children, so the default implementation
    /// -- which asks the element for its desired size -- reports 0x0 here.
    /// The layout then centres a zero-sized view, which put the top-left of
    /// the swap chain in the middle of the video area and let the rest be
    /// clipped away.
    /// `Canvas` 不會量測子元件，因此預設實作（詢問元件的 desired size）在此會回報
    /// 0x0。版面配置便把一個零尺寸的 view 置中，導致 swap chain 的左上角落在影片
    /// 區域的正中央，其餘部分則被裁切掉。
    func sizeThatFits(
        _ proposal: ProposedViewSize, winUIElement: WinUI.Canvas, context: Context
    ) -> ViewSize {
        ViewSize(Double(width), Double(height))
    }

    func updateWinUIElement(_ winUIElement: WinUI.Canvas, context: Context) {
        P6WindowFlags.applyIfNeeded()

        let coordinator = context.coordinator
        guard !coordinator.setupFailed else { return }

        do {
            if coordinator.surface == nil {
                let panel = try P6SwapChainPanel()
                P6Diagnostics.write(
                    "d3d11 surface: activated \(panel.runtimeClassName)"
                )
                try panel.setSize(width: Double(width), height: Double(height))
                try panel.attach(to: winUIElement)
                coordinator.panel = panel
                coordinator.surface = try P6D3D11VideoSurface(panel: panel)
                P6Diagnostics.write(
                    "d3d11 surface: panel attached \(width)x\(height)"
                )
            }
            guard let surface = coordinator.surface else { return }

            // The swap chain is bound to the panel here, on the UI thread,
            // because SetSwapChain is UI-thread only. The decode thread only
            // maps textures and presents.
            // swap chain 在此處（UI 執行緒）綁定到面板，因為 SetSwapChain 僅能於
            // UI 執行緒呼叫；解碼執行緒只負責對映 texture 與呈現。
            // The swap chain is composed in the display's real pixels, so the
            // buffer has to be the panel's size in those, not in DIPs.
            // swap chain 以顯示器的真實像素合成，因此 buffer 要用面板在真實像素下
            // 的尺寸，而不是 DIP。
            guard let rasterizationScale = winUIElement.xamlRoot?.rasterizationScale,
                  rasterizationScale > 0
            else {
                return
            }
            let viewport = P6VideoViewport(
                width: Double(width),
                height: Double(height),
                pixelsPerDIP: rasterizationScale
            )

            let size = SIMD2(frameWidth, frameHeight)
            guard coordinator.configuredSize != size
                || coordinator.configuredViewport != viewport
            else {
                return
            }

            let needsRebuild = surface.needsRebuild(
                for: viewport, frameWidth: frameWidth, frameHeight: frameHeight
            )
            if needsRebuild {
                // Detach first: withSurface holds a lock the decode thread also
                // takes, so this waits for any frame currently being written
                // before the pool is torn down.
                // 先解除掛載：withSurface 與解碼執行緒共用同一把鎖，因此這裡會等待
                // 正在寫入的影格完成，才會釋放舊的 texture pool。
                surfaceBox.set(nil)
            }
            try surface.setViewport(
                viewport, frameWidth: frameWidth, frameHeight: frameHeight
            )
            coordinator.configuredSize = size
            coordinator.configuredViewport = viewport
            surfaceBox.set(surface)

            let actual = (try? coordinator.panel?.actualSize()) ?? SIMD2(0, 0)
            P6Diagnostics.write(
                "d3d11 surface: frame \(frameWidth)x\(frameHeight), "
                    + "viewport \(viewport.width)x\(viewport.height) dip "
                    + "(\(viewport.pixelSize.x)x\(viewport.pixelSize.y) px), "
                    + "panel actual \(actual.x)x\(actual.y) dip, "
                    + "rasterization scale \(rasterizationScale)"
            )

            if P6WindowFlags.isCalibration, needsRebuild {
                drawCalibrationPattern(
                    surface: surface, width: Int(frameWidth), height: Int(frameHeight)
                )
            }
        } catch {
            coordinator.setupFailed = true
            coordinator.surface = nil
            surfaceBox.set(nil)
            P6Diagnostics.write("d3d11 surface: setup failed (\(error))")
        }
    }

    /// Fills the swap chain with a pattern whose geometry is known exactly, so
    /// a single screenshot measures how swap chain pixels land on screen: the
    /// red edge marks the buffer's bounds, the green cross its centre, and the
    /// corner blocks say which corner survived any clipping.
    /// 以幾何完全已知的圖樣填滿 swap chain，單張截圖即可量出 swap chain 像素如何
    /// 落在螢幕上：紅色邊框標示 buffer 邊界、綠色十字標示中心，角落色塊則指出被
    /// 裁切後保留的是哪一角。
    private func drawCalibrationPattern(
        surface: P6D3D11VideoSurface, width: Int, height: Int
    ) {
        let edge = 8
        let corner = min(width, height) / 8
        do {
            try surface.writeFrame { destination, rowPitch in
                for y in 0..<height {
                    let row = destination.advanced(by: y * rowPitch)
                        .assumingMemoryBound(to: UInt8.self)
                    for x in 0..<width {
                        var color: (UInt8, UInt8, UInt8) = (40, 40, 40)
                        if x < edge || y < edge || x >= width - edge || y >= height - edge {
                            color = (255, 0, 0)
                        } else if abs(x - width / 2) < edge || abs(y - height / 2) < edge {
                            color = (0, 255, 0)
                        } else if x < corner, y < corner {
                            color = (255, 255, 255)
                        } else if x >= width - corner, y >= height - corner {
                            color = (0, 160, 255)
                        }
                        let pixel = row + x * 4
                        pixel[0] = color.0
                        pixel[1] = color.1
                        pixel[2] = color.2
                        pixel[3] = 255
                    }
                }
            }
            try surface.present()
            P6Diagnostics.write("d3d11 surface: calibration pattern presented")
        } catch {
            P6Diagnostics.write("d3d11 surface: calibration failed (\(error))")
        }
    }

    static func dismantleWinUIElement(_: WinUI.Canvas, coordinator: Coordinator) {
        coordinator.surface = nil
        coordinator.panel = nil
    }
}

struct P6D3D11SpikeView: WinUIElementRepresentable {
    typealias WinUIElementType = WinUI.Canvas
    typealias Coordinator = P6D3D11SpikeCoordinator

    func makeCoordinator() -> Coordinator {
        P6D3D11SpikeCoordinator()
    }

    func makeWinUIElement(context: Context) -> WinUI.Canvas {
        let canvas = WinUI.Canvas()

        // Log between every step so a failure is attributable to one call.
        P6Diagnostics.write("d3d11 spike step 1: activating SwapChainPanel")
        let panel = try! P6SwapChainPanel()
        P6Diagnostics.write("d3d11 spike step 2: activated \(panel.runtimeClassName)")

        try! panel.setSize(width: 120, height: 90)
        try! panel.attach(to: canvas)
        P6Diagnostics.write("d3d11 spike step 3: panel added to canvas")

        let device = try! P6D3D11Device()
        P6Diagnostics.write("d3d11 spike step 4: D3D11 device created")

        try! device.attachSwapChain(to: panel.native, width: 120, height: 90)
        P6Diagnostics.write("d3d11 spike step 5: swap chain attached to panel")

        context.coordinator.device = device
        context.coordinator.panel = panel
        return canvas
    }

    func updateWinUIElement(_ winUIElement: WinUI.Canvas, context: Context) {
        // Present after layout rather than during creation: at creation time
        // the panel isn't in the visual tree yet, so a composition swap
        // chain presented then may never reach the screen.
        guard let device = context.coordinator.device else { return }
        try? device.clearAndPresent(r: 1, g: 0, b: 1, a: 1)
        context.coordinator.presentCount += 1
        P6Diagnostics.write(
            "d3d11 spike: present #\(context.coordinator.presentCount) "
                + "actualSize \(winUIElement.actualWidth)x\(winUIElement.actualHeight)"
        )
    }
}
#endif

// P6 stream player test app:
// - Select MP4, WebM, Y4M, or Y4M.ZST input.
// - Decode through FFmpeg; Zstd input is streamed through zstd first.
// - Exercise playback, stop, timeline seek, speed, output FPS, output
//   resolution controls, and audio playback for inputs with audio tracks.
//
// Runtime dependencies: ffmpeg, ffprobe, and (for .zst input) zstd on PATH.
// On macOS, Homebrew and MacPorts tool paths are searched even when PATH is
// minimal.
// Renderer flags: Metal is the default; -core selects Core Animation. If both
// flags are present, the last renderer flag wins.
// 渲染旗標：Metal 為預設值；-core 選擇 Core Animation。若同時提供兩者，
// 最後一個渲染旗標會生效。
// --debug enables full-frame duplicate checks and detailed frame diagnostics.
// --debug 會啟用完整影格重複檢查與詳細的逐幀診斷。
// --frame-drop drops video frames that miss the audio-anchored deadline.
// Frame dropping is disabled by default.
// --frame-drop 會丟棄錯過音訊基準期限的視訊影格；預設不丟棄影格。

enum P6RenderingBackend: String, Sendable {
    case metal
    case core

    // The last rendering flag wins; Metal is the default.
    // 最後一個渲染旗標會生效；Metal 是預設值。
    static func selected(from arguments: [String]) -> Self {
        arguments.reduce(.metal) { selected, argument in
            switch argument {
                case "-metal": .metal
                case "-core": .core
                default: selected
            }
        }
    }

    var label: String {
        switch self {
            case .metal: "Metal (default, -metal)"
            case .core: "Core Animation (-core)"
        }
    }
}

@main
@HotReloadable
struct P6StreamPlayerApp: App {
    var body: some Scene {
        WindowGroup("P6 stream player") {
            #hotReloadable {
                P6StreamPlayerView()
            }
        }
        .defaultSize(width: 1_120, height: 800)
    }
}

struct P6StreamPlayerView: View {
    @State var player = P6StreamPlayerModel()
    @State var didLoadStartupInput = false

    @Environment(\.chooseFile) var chooseFile

    #if os(macOS)
    // The backend-owned window comes from the environment. This is reliable
    // during onAppear, unlike NSApp.keyWindow which may still be nil.
    // backend 所管理的視窗由 environment 提供；onAppear 執行時此方式可靠，
    // 不會遇到 NSApp.keyWindow 仍為 nil 的時序問題。
    @Environment(\.window) var enclosingWindow
    #endif

    let speedOptions = ["1x", "2x", "3x"]
    let fpsOptions = ["30", "45", "60"]
    let resolutionOptions = P6OutputResolution.allCases.map(\.label)

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("P6: Zstd stream player")
                        .font(.system(size: 20))

                    Text(player.selectedFileName)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    #if os(macOS)
                    Text("Renderer: \(player.renderingBackend.label)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    #endif
                }

                #if os(Windows)
                // Phase 0/1 spike: confirms the SwapChainPanel activation +
                // D3D11 device/swapchain/present path actually renders,
                // before wiring real video frames into it. Should show as a
                // solid magenta rectangle. See plan at
                // C:\Users\lowei\.claude\plans\quizzical-jingling-music.md.
                //
                // Gated behind -d3d-spike (default off): a crash was observed
                // right at first-frame publish while this was always-on, so
                // it's opt-in until the interaction with the normal video
                // path is root-caused.
                if CommandLine.arguments.contains("-d3d-spike") {
                    P6D3D11SpikeView()
                        .frame(width: 120, height: 90)
                }
                #endif

                Spacer()

                Button("Choose file") {
                    Task {
                        guard let file = await chooseFile(
                            title: "Choose MP4, WebM, Y4M, or Y4M.ZST stream",
                            defaultButtonLabel: "Open",
                            initialDirectory: P6StreamPlayerModel.suggestedInputDirectory,
                            allowSelectingFiles: true,
                            allowSelectingDirectories: false
                        ) else {
                            return
                        }
                        player.load(file)
                    }
                }
            }

            ZStack(alignment: .center) {
                Color.black
                    .frame(width: 960, height: 540)

                #if os(macOS)
                if player.hasVideoFrame {
                    if player.renderingBackend == .metal {
                        P6MetalVideoView(store: player.frameStore)
                            .frame(width: 960, height: 540)
                    } else {
                        P6CoreVideoView(store: player.frameStore)
                            .frame(width: 960, height: 540)
                    }
                } else if player.isLoading {
                    ProgressView("Decoding frame...")
                } else {
                    Text("Choose a stream to begin")
                }
                #elseif os(Windows)
                // The SwapChainPanel draws the video itself; this view only
                // hosts it and keeps its swap chain sized to the decoder.
                // 影片由 SwapChainPanel 自行繪製，此 view 僅負責承載它，並讓其
                // swap chain 與解碼輸出尺寸保持一致。
                P6D3D11VideoView(
                    surfaceBox: player.surfaceBox,
                    width: 960,
                    height: 540,
                    frameWidth: UInt32(player.outputResolution.width),
                    frameHeight: UInt32(player.outputResolution.height)
                )
                .frame(width: 960, height: 540)
                #else
                if let frame = player.frame {
                    SwiftCrossUI.Image(frame)
                        .resizable()
                        .frame(width: 960, height: 540)
                } else if player.isLoading {
                    ProgressView("Decoding frame...")
                } else {
                    Text("Choose a stream to begin")
                }
                #endif
            }
            .frame(width: 960, height: 540)
            .cornerRadius(4)

            VStack(spacing: 4) {
                Slider(
                    value: player.$seekPosition.onChange { value in
                        player.seekPositionChanged(to: value)
                    },
                    in: 0...player.seekUpperBound
                )
                .frame(width: 960)
                .disabled(!player.hasInput || player.seekUpperBound <= 0)

                HStack {
                    Text(
                        "Current: \(player.timeDescription) "
                            + "(\(player.progressDescription))"
                    )
                    .textSelectionEnabled()
                    Spacer()
                    Text("Seek target: \(player.seekDescription)")
                }
                .frame(width: 960)
            }

            HStack(spacing: 6) {
                Button("-5s") {
                    player.seek(by: -5)
                }
                .disabled(!player.hasInput || player.isLoading)

                Button(player.isPlaying || player.isLoading ? "Stop" : "Play") {
                    if player.isPlaying || player.isLoading {
                        player.stop()
                    } else {
                        player.play()
                    }
                }
                .disabled(!player.hasInput)

                Button("+5s") {
                    player.seek(by: 5)
                }
                .disabled(!player.hasInput || player.isLoading)

                Button("Seek") {
                    player.seek(to: player.seekPosition, shouldPlay: player.isPlaying)
                }
                .disabled(!player.hasInput || player.isLoading)

                Text("Speed")
                Picker(
                    of: speedOptions,
                    selection: player.$speedSelection.onChange { _ in
                        player.playbackSettingsChanged()
                    }
                )
                .pickerStyle(.menu)
                .frame(width: 84)

                Text("FPS")
                Picker(
                    of: fpsOptions,
                    selection: player.$fpsSelection.onChange { _ in
                        player.playbackSettingsChanged()
                    }
                )
                .pickerStyle(.menu)
                .frame(width: 84)

                Text("Resolution")
                Picker(
                    of: resolutionOptions,
                    selection: player.$resolutionSelection.onChange { _ in
                        player.playbackSettingsChanged()
                    }
                )
                .pickerStyle(.menu)
                .frame(width: 142)

                Toggle(
                    "Sound",
                    isOn: player.$soundEnabled.onChange { isEnabled in
                        player.soundSettingChanged(isEnabled: isEnabled)
                    }
                )
                .toggleStyle(.button)
                .toggleColor(.blue)
                .disabled(!player.hasInput)

                Toggle(
                    "Frame drop",
                    isOn: player.$frameDropEnabled.onChange { isEnabled in
                        player.frameDropSettingChanged(isEnabled: isEnabled)
                    }
                )
                .toggleStyle(.button)
                .toggleColor(.blue)

                Toggle(
                    "Show resolution",
                    isOn: player.$showsResolution.onChange { isShowing in
                        player.resolutionDisplayChanged(isShowing: isShowing)
                    }
                )
                .toggleStyle(.button)
                .toggleColor(.blue)
                .disabled(!player.hasInput || player.frameDropEnabled)
            }
            .frame(width: 1_040)

            Text(player.statusDescription)
                .frame(width: 960, alignment: .leading)

            if player.showsResolution {
                Text(player.resolutionDescription)
                    .frame(width: 960, alignment: .leading)
            }
        }
        .padding(18)
        .onAppear {
            guard !didLoadStartupInput else { return }
            didLoadStartupInput = true

            #if os(macOS)
            player.installCloseConfirmation(on: enclosingWindow)
            player.installTerminationSignalHandlers()
            P6Diagnostics.write("renderer \(player.renderingBackend.rawValue)")
            #endif

            if let inputFile = P6StreamPlayerModel.fileFromCommandLine() {
                P6Diagnostics.write(
                    "auto-load \(inputFile.path) "
                        + "autoplay \(P6Diagnostics.isAutoplayEnabled ? "on" : "off") "
                        + "frame-drop \(P6Diagnostics.isFrameDropEnabled ? "on" : "off")"
                )
                player.load(inputFile)
                if P6Diagnostics.isAutoplayEnabled {
                    player.play()
                }
            }
        }
        .onDisappear {
            player.shutdown()
        }
    }
}

@MainActor
final class P6StreamPlayerModel: SwiftCrossUI.ObservableObject {
    static var suggestedInputDirectory: URL? {
        for projectName in ["LZFSE2", "lzfse2"] {
            let candidate = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("proj")
                .appendingPathComponent(projectName)
                .appendingPathComponent("swift_tar")
                .appendingPathComponent("images")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    /// Media extensions `-f` will match when searching by substring.
    private static let mediaExtensions: Set<String> = [
        "mp4", "webm", "y4m", "zst", "mkv", "mov",
    ]

    /// Resolves the `-f` flag, which avoids re-picking the same file through
    /// the file dialog on every launch.
    ///
    /// - `-f <path>` loads that path directly.
    /// - `-f <substring>` loads the first media file whose name contains that
    ///   substring, searched in the current directory, then the default input
    ///   directory.
    /// - `-f` with no value falls back to `defaultFilePattern`.
    static let defaultFilePattern = "耶利米"

    static func fileFromCommandLine() -> URL? {
        let arguments = CommandLine.arguments.dropFirst()
        guard let flagIndex = arguments.firstIndex(of: "-f") else {
            // No -f: keep supporting a bare positional path.
            guard let path = arguments.first(where: { !$0.hasPrefix("-") }) else {
                return nil
            }
            return URL(fileURLWithPath: path)
        }

        let next = arguments.index(after: flagIndex)
        let value: String
        if next < arguments.endIndex, !arguments[next].hasPrefix("-") {
            value = arguments[next]
        } else {
            value = defaultFilePattern
        }

        if FileManager.default.fileExists(atPath: value) {
            return URL(fileURLWithPath: value)
        }
        return findMediaFile(containing: value)
    }

    private static func findMediaFile(containing substring: String) -> URL? {
        var directories = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        ]
        // Also look beside the executable, so -f works no matter which
        // directory P6 was launched from (test_P6.sh runs it from the repo
        // root, while the sample videos live next to the binary).
        // 同時搜尋執行檔所在目錄，讓 -f 不受啟動目錄影響（test_P6.sh 由 repo
        // 根目錄啟動，但範例影片放在執行檔旁邊）。
        if let executablePath = CommandLine.arguments.first {
            let executableDirectory = URL(fileURLWithPath: executablePath)
                .deletingLastPathComponent()
            directories.append(executableDirectory)
        }
        if let suggested = suggestedInputDirectory {
            directories.append(suggested)
        }

        for directory in directories {
            let contents = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
            let match = contents?
                .filter { mediaExtensions.contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .first { $0.lastPathComponent.contains(substring) }
            if let match {
                return match
            }
        }
        return nil
    }

    @SwiftCrossUI.Published
    var frame: ImageFormats.Image<RGBA>?

    #if os(macOS)
    @SwiftCrossUI.Published
    // Publish only the empty/non-empty transition. Publishing every large frame
    // would repeatedly rebuild the view graph and can leave the native view stale.
    // 只發布「沒有影格／已有影格」的狀態轉換。若每個大型影格都發布，會反覆
    // 重建 view graph，並可能讓原生 view 停留在舊影格。
    var hasVideoFrame = false

    let renderingBackend = P6RenderingBackend.selected(from: CommandLine.arguments)
    let frameStore = P6FrameStore()
    private var terminationSignalSources: [DispatchSourceSignal] = []
#endif

    @SwiftCrossUI.Published
    var selectedURL: URL?

    @SwiftCrossUI.Published
    var currentTime: Double = 0

    @SwiftCrossUI.Published
    var seekPosition: Double = 0

    @SwiftCrossUI.Published
    var duration: Double?

    @SwiftCrossUI.Published
    var isPlaying = false

    @SwiftCrossUI.Published
    var isLoading = false

    @SwiftCrossUI.Published
    var status = "Ready. ffmpeg, ffprobe, and zstd are searched on PATH plus platform tool directories."

    @SwiftCrossUI.Published
    var speedSelection: String? = "1x"

    @SwiftCrossUI.Published
    var fpsSelection: String? = "30"

    @SwiftCrossUI.Published
    /// `-res <substring>` preselects an output resolution, so the 1080p and 4K
    /// paths can be exercised in an unattended run.
    /// `-res <關鍵字>` 可預先選定輸出解析度，讓 1080p 與 4K 路徑能在無人值守的
    /// 測試中被涵蓋。
    var resolutionSelection: String? = {
        guard let index = CommandLine.arguments.firstIndex(of: "-res"),
              index + 1 < CommandLine.arguments.count
        else {
            return P6OutputResolution.preview.label
        }
        let pattern = CommandLine.arguments[index + 1].lowercased()
        return P6OutputResolution.allCases
            .first { $0.label.lowercased().contains(pattern) }?
            .label ?? P6OutputResolution.preview.label
    }()

    @SwiftCrossUI.Published
    var soundEnabled = true

    @SwiftCrossUI.Published
    var detectedInputResolution: SIMD2<Int>?

    @SwiftCrossUI.Published
    var showsResolution = P6Diagnostics.isFrameDropEnabled

    @SwiftCrossUI.Published
    var frameDropEnabled = P6Diagnostics.isFrameDropEnabled

    @SwiftCrossUI.Published
    var droppedFramesPerSecond = 0

    private var generation = 0
    private var frameSerial = 0
    /// Whether playback stopped because the stream ended, so Play restarts
    /// from the beginning instead of resuming at the final frame.
    /// 是否因串流播畢而停止；若是，按下播放應從頭開始，而非停在最後一張影格。
    private var reachedEndOfStream = false

    #if os(Windows)
    /// Set once the D3D11 child-window surface exists. While it is nil the
    /// decoder falls back to the old image path, so the app still runs before
    /// the surface is created (or if creating it fails).
    /// 建立 D3D11 子視窗表面後才會設定；為 nil 時解碼器沿用舊的影像路徑，
    /// 因此在表面建立前（或建立失敗時）程式仍可運作。
    let surfaceBox = P6VideoSurfaceBox()
    #endif
    private var seekDebounceTask: Task<Void, Never>?
    private var playbackTask: Task<Void, Never>?
    private var decoderSession: P6DecoderSession?
    private var audioSession: P6AudioSession?

    var hasInput: Bool { selectedURL != nil }

    var selectedFileName: String {
        selectedURL?.lastPathComponent ?? "No file selected"
    }

    var speed: Double {
        switch speedSelection {
            case "2x": 2
            case "3x": 3
            default: 1
        }
    }

    var framesPerSecond: Int {
        switch fpsSelection {
            case "30": 30
            case "45": 45
            default: 60
        }
    }

    var outputResolution: P6OutputResolution {
        P6OutputResolution(label: resolutionSelection)
    }

    var resolutionDescription: String {
        let inputText = detectedInputResolution
            .map { "\($0.x)x\($0.y)" } ?? "unknown"
        let output = outputResolution
        var description = "Input: \(inputText). Output: \(output.width)x\(output.height). Viewport: 960x540."
        if frameDropEnabled {
            description += " Dropped frames/sec: \(droppedFramesPerSecond)."
        }
        return description
    }

    var statusDescription: String {
        "\(status) Frame drop \(frameDropEnabled ? "on" : "off")."
    }

    var progress: Double? {
        guard let duration, duration > 0 else { return nil }
        return min(1, max(0, currentTime / duration))
    }

    var seekUpperBound: Double {
        duration.map { max(0, $0) } ?? max(1, currentTime)
    }

    var timeDescription: String {
        let elapsed = Self.formatTime(currentTime)
        guard let duration else { return "\(elapsed) / --:--" }
        return "\(elapsed) / \(Self.formatTime(duration))"
    }

    var seekDescription: String {
        guard duration != nil else { return "--:--" }
        return Self.formatTime(seekPosition)
    }

    var progressDescription: String {
        guard let progress else { return "--%" }
        return "\(Int((progress * 100).rounded()))%"
    }

    func load(_ url: URL) {
        P6Diagnostics.write("load \(url.path)")
        selectedURL = url
        currentTime = 0
        seekPosition = 0
        duration = nil
        detectedInputResolution = showsResolution
            ? P6MediaProbe.resolution(for: url)
            : nil
        if frameDropEnabled {
            droppedFramesPerSecond = 0
        }
        frame = nil
        #if os(macOS)
        hasVideoFrame = false
        frameStore.clear()
        #endif
        startDecoder(at: 0, shouldPlay: false, singleFrame: true)
    }

    func play() {
        guard selectedURL != nil else { return }
        // At end of stream currentTime holds the last decoded frame's
        // timestamp, which is slightly *below* the probed duration, so a
        // `currentTime >= duration` test misses and playback would restart
        // at the very end -- decoding nothing and immediately ending again,
        // which looks like Play doing nothing. Track the end explicitly.
        // 播放結束時 currentTime 是最後一張影格的時間戳，會略小於探測到的總長，
        // 因此 `currentTime >= duration` 判斷不會成立，導致從結尾重新開始播放：
        // 解不到任何影格便立刻再次結束，看起來就像按下播放沒有反應。
        // 改為明確記錄是否已播放到結尾。
        if reachedEndOfStream {
            currentTime = 0
            seekPosition = 0
        }
        startDecoder(at: currentTime, shouldPlay: true, singleFrame: false)
    }

    func stop() {
        invalidateCurrentDecoder()
        isPlaying = false
        isLoading = false
        status = "Stopped at \(Self.formatTime(currentTime))."
    }

    func seek(by offset: Double) {
        guard selectedURL != nil else { return }
        let target = clampedSeekTime(currentTime + offset)
        seek(to: target, shouldPlay: isPlaying)
    }

    func seek(to target: Double, shouldPlay: Bool) {
        guard selectedURL != nil else { return }
        let clampedTarget = clampedSeekTime(target)
        seekPosition = clampedTarget
        startDecoder(at: clampedTarget, shouldPlay: shouldPlay, singleFrame: !shouldPlay)
    }

    // Debounce continuous slider updates so one drag creates one decoder session.
    // The last target is applied after the slider has been still for 200 ms.
    // 對連續滑桿更新進行 debounce，讓一次拖曳只建立一個解碼工作；滑桿停止
    // 200 毫秒後才套用最後的目標時間。
    func seekPositionChanged(to target: Double) {
        guard selectedURL != nil else { return }
        let clampedTarget = clampedSeekTime(target)
        seekPosition = clampedTarget
        let resumePlayback = isPlaying

        seekDebounceTask?.cancel()
        seekDebounceTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 200_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            self.seekDebounceTask = nil
            self.startDecoder(
                at: clampedTarget,
                shouldPlay: resumePlayback,
                singleFrame: !resumePlayback
            )
        }
    }

    // Playback settings belong to the next decoder session. Restarting at the
    // current timestamp applies the new speed, FPS, and resolution immediately.
    // 播放設定會套用到下一個解碼工作；從目前時間戳重啟即可立即套用新的速度、
    // FPS 與解析度。
    func playbackSettingsChanged() {
        guard selectedURL != nil else { return }
        let resolution = outputResolution
        let position = currentTime
        if isPlaying {
            startDecoder(at: position, shouldPlay: true, singleFrame: false)
        } else if !isLoading {
            startDecoder(at: position, shouldPlay: false, singleFrame: true)
        } else {
            status = "Selected \(speedSelection ?? "1x"), \(framesPerSecond) FPS, \(resolution.label). Press Play to apply."
        }
    }

    func soundSettingChanged(isEnabled: Bool) {
        if !isEnabled {
            audioSession?.terminate()
            audioSession = nil
            status = "Sound disabled."
        } else {
            status = "Sound enabled. Audio starts on Play for inputs with audio tracks."
            if isPlaying {
                // Restart both streams from one media timestamp so a newly
                // enabled audio process does not begin on an unrelated clock.
                // 從同一媒體時間戳重新啟動影音，避免新開啟的音訊程序使用
                // 與既有視訊無關的時鐘。
                startDecoder(at: currentTime, shouldPlay: true, singleFrame: false)
            }
        }
    }

    func resolutionDisplayChanged(isShowing: Bool) {
        if !isShowing, frameDropEnabled {
            showsResolution = true
            return
        }
        guard isShowing, let selectedURL else { return }
        detectedInputResolution = detectedInputResolution
            ?? P6MediaProbe.resolution(for: selectedURL)
    }

    // Apply frame dropping immediately during playback by restarting both media
    // processes from the current timestamp. When stopped, the next Play applies it.
    // 播放中從目前時間戳重新啟動兩個媒體程序，立即套用丟幀設定；停止時則由
    // 下一次 Play 套用。
    func frameDropSettingChanged(isEnabled: Bool) {
        droppedFramesPerSecond = 0
        let settingText = isEnabled ? "on" : "off"
        P6Diagnostics.write("runtime frame-drop \(settingText)")

        if isEnabled {
            showsResolution = true
            if let selectedURL {
                detectedInputResolution = detectedInputResolution
                    ?? P6MediaProbe.resolution(for: selectedURL)
            }
        }

        if isPlaying {
            startDecoder(at: currentTime, shouldPlay: true, singleFrame: false)
            status = "Restarting playback with the updated setting."
        } else {
            status = "Playback setting updated."
        }
    }

    func shutdown() {
        invalidateCurrentDecoder()
        isPlaying = false
        isLoading = false
    }

    #if os(macOS)
    // The synchronous handler asks first, then waits for the retained ffplay
    // Process to exit before AppKit is allowed to destroy the window.
    // 同步 handler 會先詢問使用者，接著等待所保留的 ffplay Process 結束，
    // 最後才允許 AppKit 銷毀視窗。
    func installCloseConfirmation(on enclosingWindow: Any?) {
        guard let window = enclosingWindow as? NSCustomWindow else {
            P6Diagnostics.write("close confirmation not installed: window unavailable")
            return
        }
        AppKitBackend().setShouldCloseHandler(ofWindow: window) { [weak self] in
            guard let self else { return true }

            let pidText = self.audioSession
                .map { String($0.processIdentifier) } ?? "none"
            P6Diagnostics.write("close requested ffplay pid \(pidText)")

            let alert = NSAlert()
            alert.messageText = "Close P6? / 關閉 P6？"
            if let ffplayPID = self.audioSession?.processIdentifier {
                alert.informativeText = "ffplay PID \(ffplayPID) is still active. Close and stop it? / ffplay PID \(ffplayPID) 仍在執行，是否關閉並停止它？"
            } else {
                alert.informativeText = "Close the P6 window? / 是否關閉 P6 視窗？"
            }
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Close / 關閉")
            alert.addButton(withTitle: "Cancel / 取消")

            guard alert.runModal() == .alertFirstButtonReturn else { return false }
            self.shutdownAndWait()

            // AppKit keeps the process alive after the last window closes, which
            // leaves P6 running in the terminal. P6 is a single-window player, so
            // closing the window means quitting. Terminate on the next runloop
            // pass, once AppKit has finished destroying the window.
            // AppKit 在最後一個視窗關閉後仍會保留行程，導致 P6 留在終端機中執行。
            // P6 是單視窗播放器，關閉視窗即代表結束程式。待 AppKit 完成銷毀視窗後，
            // 於下一輪 runloop 終止。
            DispatchQueue.main.async {
                P6Diagnostics.write("window closed, terminating app")
                NSApplication.shared.terminate(nil)
            }
            return true
        }
        P6Diagnostics.write("close confirmation installed")
    }

    // Retain Dispatch signal sources so terminal SIGINT/SIGTERM can stop and
    // reap the retained ffplay Process before P6 exits.
    // 保留 Dispatch 訊號來源，讓終端機 SIGINT／SIGTERM 能在 P6 結束前停止並
    // 回收所保存的 ffplay Process。
    func installTerminationSignalHandlers() {
        guard terminationSignalSources.isEmpty else { return }

        for signalNumber in [SIGINT, SIGTERM] {
            Darwin.signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(
                signal: signalNumber,
                queue: .main
            )
            source.setEventHandler { [weak self] in
                guard let self else {
                    Darwin.exit(128 + signalNumber)
                }

                let pidText = self.audioSession
                    .map { String($0.processIdentifier) } ?? "none"
                P6Diagnostics.write(
                    "received signal \(signalNumber), terminating ffplay pid \(pidText)"
                )
                self.shutdownAndWait()
                P6Diagnostics.write("signal cleanup complete")
                Darwin.exit(128 + signalNumber)
            }
            source.resume()
            terminationSignalSources.append(source)
        }

        P6Diagnostics.write("SIGINT/SIGTERM cleanup installed")
    }

    private func shutdownAndWait() {
        // Window closing is the one lifecycle point where waiting is intentional:
        // it guarantees that the known ffplay PID is reaped before close returns.
        // 視窗關閉是刻意等待的生命週期節點：可保證已知的 ffplay PID 在關閉
        // callback 回傳前完成回收。
        invalidateCurrentDecoder(waitForAudioExit: true)
        isPlaying = false
        isLoading = false
    }
    #endif

    private func startDecoder(at startTime: Double, shouldPlay: Bool, singleFrame: Bool) {
        guard let selectedURL else { return }

        invalidateCurrentDecoder()
        // Any new decode session (play, seek, or single-frame scrub) means we
        // are no longer parked at the end of the stream.
        // 任何新的解碼工作（播放、seek、單張影格預覽）都代表已離開串流結尾。
        reachedEndOfStream = false
        currentTime = max(0, startTime)
        seekPosition = currentTime
        isPlaying = shouldPlay
        isLoading = true
        status = singleFrame ? "Seeking to \(Self.formatTime(currentTime))..." : "Starting playback..."

        let token = generation
        let requestedSpeed = speed
        let requestedFPS = framesPerSecond
        let requestedResolution = outputResolution
        let dropsLateFrames = frameDropEnabled
        if dropsLateFrames {
            droppedFramesPerSecond = 0
        }
        let knownDuration = duration
        // Format on the main actor; the detached decode task below cannot reach
        // main actor-isolated helpers.
        // 在主執行者上先格式化；下方的分離解碼任務無法存取主執行者隔離的輔助方法。
        let startTimeLabel = Self.formatTime(startTime)
        P6Diagnostics.write(
            "session token \(token) start seek \(String(format: "%.3f", startTime))s "
                + "speed \(requestedSpeed)x fps \(requestedFPS) "
                + "resolution \(requestedResolution.width)x\(requestedResolution.height) "
                + "mode \(shouldPlay ? "play" : "frame") "
                + "frame-drop \(dropsLateFrames ? "on" : "off")"
        )

        playbackTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            do {
                if knownDuration == nil,
                   let probedDuration = P6MediaProbe.duration(for: selectedURL)
                {
                    await self.acceptDuration(probedDuration, token: token)
                }

                let session = try P6DecoderSession(
                    inputURL: selectedURL,
                    startTime: startTime,
                    speed: requestedSpeed,
                    framesPerSecond: requestedFPS,
                    outputResolution: requestedResolution
                )

                guard await self.install(session, token: token) else {
                    session.terminate()
                    return
                }

                var previousFrame: Data?
                var frameIndex = 0
                var playbackStartUptime: TimeInterval?
                var didLogFirstPresent = false
                var didLogPresentError = false
                var droppedFrameCount = 0
                var droppedFramesInSample = 0
                var dropRateSampleStart = ProcessInfo.processInfo.systemUptime
                let displayInterval = 1 / Double(requestedFPS)
                let sourceAdvance = requestedSpeed / Double(requestedFPS)

                while !Task.isCancelled {
                    #if os(Windows)
                    // Zero-copy path: read the frame straight into mapped GPU
                    // memory. Nothing is allocated or copied per frame, and no
                    // pixel conversion is needed because ffmpeg's rgba output
                    // already matches DXGI_FORMAT_R8G8B8A8_UNORM.
                    // 零複製路徑：影格直接讀入已對映的 GPU 記憶體。每幀不配置也
                    // 不複製任何緩衝區，且因 ffmpeg 的 rgba 輸出已符合
                    // DXGI_FORMAT_R8G8B8A8_UNORM，無需像素格式轉換。
                    var zeroCopyFrameRead: Bool?
                    try surfaceBox.withSurface { surface in
                        // The swap chain is created on the UI thread, so this
                        // only checks; a mismatch means the view has not caught
                        // up with a resolution change yet.
                        // swap chain 由 UI 執行緒建立，此處僅檢查；尺寸不符代表
                        // view 尚未跟上解析度變更。
                        guard surface.isConfigured(
                            frameWidth: UInt32(requestedResolution.width),
                            frameHeight: UInt32(requestedResolution.height)
                        ) else {
                            return
                        }
                        var didRead = false
                        try surface.writeFrame { destination, rowPitch in
                            didRead = try session.readFrame(
                                into: destination,
                                rowPitch: rowPitch,
                                width: requestedResolution.width,
                                height: requestedResolution.height
                            )
                        }
                        zeroCopyFrameRead = didRead
                    }

                    if let zeroCopyFrameRead {
                        guard zeroCopyFrameRead else {
                            await self.finish(token: token, reachedEnd: true, error: nil)
                            return
                        }
                    }
                    let frameData: Data?
                    if zeroCopyFrameRead == nil {
                        guard let data = try session.readFrame() else {
                            await self.finish(token: token, reachedEnd: true, error: nil)
                            return
                        }
                        frameData = data
                    } else {
                        frameData = nil
                    }
                    #else
                    guard let readData = try session.readFrame() else {
                        await self.finish(token: token, reachedEnd: true, error: nil)
                        return
                    }
                    let frameData: Data? = readData
                    #endif

                    let position = startTime + Double(frameIndex) * sourceAdvance

                    if shouldPlay {
                        if let playbackStartUptime {
                            // Use one absolute monotonic timeline. Relative
                            // per-frame sleeps accumulate decode and render time,
                            // which eventually leaves video behind audio.
                            // 使用單一絕對單調時間軸。逐幀相對休眠會累積解碼與
                            // 渲染時間，最終造成畫面落後音訊。
                            let deadline = playbackStartUptime
                                + Double(frameIndex) * displayInterval
                            let now = ProcessInfo.processInfo.systemUptime
                            let remaining = deadline - now
                            var shouldDropFrame = false
                            // Keep lateness checks, counters, sampling, and UI
                            // publication entirely out of the default path.
                            // 將逾期判斷、計數、取樣與 UI 發布完全排除於預設路徑。
                            if dropsLateFrames {
                                shouldDropFrame = remaining <= -displayInterval
                                if shouldDropFrame {
                                    // Audio is the practical master clock. Do not
                                    // enqueue an obsolete 4K frame when video falls
                                    // behind; consume it and continue toward the frame
                                    // that belongs at the current wall-clock time.
                                    // 音訊是實際主時鐘。視訊落後時不將過期的 4K 影格
                                    // 排入佇列；讀取消耗後繼續追趕目前牆鐘應顯示的影格。
                                    droppedFrameCount += 1
                                    droppedFramesInSample += 1
                                    if droppedFrameCount == 1
                                        || droppedFrameCount % requestedFPS == 0
                                    {
                                        P6Diagnostics.writeFrame(
                                            "session token \(token) dropped \(droppedFrameCount) "
                                                + "late frames at \(String(format: "%.3f", position))s"
                                        )
                                    }
                                }
                                if now - dropRateSampleStart >= 1 {
                                    let elapsed = now - dropRateSampleStart
                                    let droppedPerSecond = Int(
                                        (Double(droppedFramesInSample) / elapsed).rounded()
                                    )
                                    await self.acceptDroppedFramesPerSecond(
                                        droppedPerSecond,
                                        token: token
                                    )
                                    droppedFramesInSample = 0
                                    dropRateSampleStart = now
                                }
                            }
                            if shouldDropFrame {
                                frameIndex += 1
                                continue
                            }
                            if remaining > 0 {
                                try await Task.sleep(
                                    nanoseconds: UInt64(remaining * 1_000_000_000)
                                )
                            }
                        } else {
                            // Decode the first frame before starting ffplay, then
                            // anchor both streams at the same media timestamp.
                            // 先解出第一幀才啟動 ffplay，再以相同媒體時間戳建立
                            // 影音共用起點。
                            await self.startAudioIfNeeded(
                                at: startTime,
                                speed: requestedSpeed,
                                token: token
                            )
                            let clockStart = ProcessInfo.processInfo.systemUptime
                            playbackStartUptime = clockStart
                            dropRateSampleStart = clockStart
                            P6Diagnostics.write(
                                "playback clock token \(token) started \(startTimeLabel) "
                                    + "speed \(requestedSpeed)x fps \(requestedFPS) "
                                    + "frame-drop \(dropsLateFrames ? "on" : "off")"
                            )
                        }
                    }

                    #if os(Windows)
                    if zeroCopyFrameRead != nil {
                        // The frame is already in GPU memory; presenting is a
                        // CopyResource plus Present, with nothing crossing the
                        // CPU again. acceptFrame is still called with no image
                        // so the timeline and status text keep updating.
                        // 影格已位於 GPU 記憶體，呈現只需 CopyResource 與 Present，
                        // 不再有資料回到 CPU。仍以無影像參數呼叫 acceptFrame，
                        // 讓時間軸與狀態文字持續更新。
                        surfaceBox.withSurface { surface in
                            do {
                                try surface.present()
                                if !didLogFirstPresent {
                                    didLogFirstPresent = true
                                    P6Diagnostics.write("d3d11 surface: first present ok")
                                }
                            } catch {
                                if !didLogPresentError {
                                    didLogPresentError = true
                                    P6Diagnostics.write("d3d11 surface: present failed \(error)")
                                }
                            }
                        }
                        await self.acceptFrame(
                            nil,
                            rawFrame: nil,
                            at: position,
                            resolution: requestedResolution,
                            token: token
                        )
                        if singleFrame {
                            session.terminate()
                            await self.finish(token: token, reachedEnd: false, error: nil)
                            return
                        }
                        frameIndex += 1
                        continue
                    }
                    #endif

                    // Full Data equality scans every RGBA byte. Keep it out of
                    // normal playback and enable it only for explicit diagnostics.
                    // 完整 Data 相等比較會掃描每個 RGBA 位元組；一般播放不執行，
                    // 僅在明確要求診斷時啟用。
                    let isDuplicateFrame: Bool
                    if P6Diagnostics.isDebugEnabled {
                        isDuplicateFrame = previousFrame == frameData
                        previousFrame = frameData
                    } else {
                        isDuplicateFrame = false
                    }

                    var rawFrame: Data?
                    var image: ImageFormats.Image<RGBA>?
                    if isDuplicateFrame || frameData == nil {
                        rawFrame = nil
                        image = nil
                    } else {
                        #if os(macOS)
                        rawFrame = frameData
                        image = nil
                        #else
                        rawFrame = nil
                        image = frameData.map {
                            ImageFormats.Image(
                                width: requestedResolution.width,
                                height: requestedResolution.height,
                                bytes: Array($0)
                            )
                        }
                        #endif
                    }

                    await self.acceptFrame(
                        image,
                        rawFrame: rawFrame,
                        at: position,
                        resolution: requestedResolution,
                        token: token
                    )

                    if singleFrame {
                        session.terminate()
                        await self.finish(token: token, reachedEnd: false, error: nil)
                        return
                    }

                    frameIndex += 1
                }
            } catch is CancellationError {
                return
            } catch {
                await self.finish(
                    token: token,
                    reachedEnd: false,
                    error: error.localizedDescription
                )
            }
        }
    }

    private func invalidateCurrentDecoder(waitForAudioExit: Bool = false) {
        seekDebounceTask?.cancel()
        seekDebounceTask = nil
        generation &+= 1
        decoderSession?.terminate()
        decoderSession = nil
        if waitForAudioExit {
            audioSession?.terminateAndWait()
        } else {
            audioSession?.terminate()
        }
        audioSession = nil
        playbackTask?.cancel()
        playbackTask = nil
    }

    private func install(_ session: P6DecoderSession, token: Int) -> Bool {
        guard generation == token else { return false }
        decoderSession = session
        return true
    }

    private func acceptDuration(_ value: Double, token: Int) {
        guard generation == token else { return }
        duration = value
        seekPosition = min(seekPosition, value)
    }

    // Update the optional diagnostic at most once per sampling interval so the
    // UI is not rebuilt for every dropped frame.
    // 每個取樣區間最多更新一次選用診斷，避免每丟棄一幀就重建 UI。
    private func acceptDroppedFramesPerSecond(_ value: Int, token: Int) {
        guard generation == token else { return }
        droppedFramesPerSecond = value
    }

    private func acceptFrame(
        _ image: ImageFormats.Image<RGBA>?,
        rawFrame: Data?,
        at position: Double,
        resolution: P6OutputResolution,
        token: Int
    ) {
        guard generation == token else { return }
        #if os(macOS)
        if let rawFrame {
            frameSerial &+= 1
            let newFrame = P6VideoFrame(
                width: resolution.width,
                height: resolution.height,
                rgbaBytes: rawFrame,
                serial: frameSerial
            )
            frameStore.update(newFrame)
            if !hasVideoFrame {
                hasVideoFrame = true
            }
            P6Diagnostics.writeFrame(
                "video frame \(Self.formatTime(position)) \(resolution.width)x\(resolution.height)"
            )
        }
        #else
        if let image {
            frame = image
            P6Diagnostics.writeFrame(
                "frame \(Self.formatTime(position)) \(resolution.width)x\(resolution.height)"
            )
        }
        #endif
        currentTime = position
        // Preserve the user's final slider target while its debounce timer is
        // pending; playback progress must not overwrite that target first.
        // debounce 計時尚未完成時保留使用者最後的滑桿目標，避免播放進度先將
        // 該目標覆寫回舊時間。
        if seekDebounceTask == nil,
           isPlaying || abs(seekPosition - position) < 0.5
        {
            seekPosition = position
        }
        isLoading = false
        status = isPlaying
            ? "Playing \(speedSelection ?? "1x") at \(framesPerSecond) FPS, \(resolution.label). \(audioStatusText)"
            : "Frame ready at \(Self.formatTime(position))."
    }

    private func finish(token: Int, reachedEnd: Bool, error: String?) {
        guard generation == token else { return }
        decoderSession?.terminate()
        decoderSession = nil
        playbackTask = nil
        isPlaying = false
        isLoading = false

        if let error {
            status = "Playback failed: \(error)"
            P6Diagnostics.write(status)
        } else if reachedEnd {
            if duration == nil {
                duration = currentTime
            }
            reachedEndOfStream = true
            status = "End of stream."
            P6Diagnostics.write(status)
        } else {
            status = "Frame ready at \(Self.formatTime(currentTime))."
            P6Diagnostics.write(status)
        }
    }

    private var audioStatusText: String {
        guard soundEnabled else { return "Sound off." }
        guard audioSession != nil else { return "Video-only or ffplay unavailable." }
        return "Sound on."
    }

    private func clampedSeekTime(_ time: Double) -> Double {
        let lowerBound = max(0, time)
        if let duration {
            let upperBound = max(0, duration - 1 / Double(framesPerSecond))
            return min(upperBound, lowerBound)
        }
        return lowerBound
    }

    private func startAudioIfNeeded(
        at startTime: Double,
        speed requestedSpeed: Double,
        token: Int
    ) {
        guard generation == token else { return }
        restartAudio(at: startTime, speed: requestedSpeed, token: token)
    }

    private func restartAudio(at startTime: Double, speed requestedSpeed: Double, token: Int) {
        audioSession?.terminate()
        audioSession = nil

        guard soundEnabled, let selectedURL else { return }
        do {
            audioSession = try P6AudioSession(
                inputURL: selectedURL,
                startTime: startTime,
                speed: requestedSpeed
            )
            P6Diagnostics.write(
                "audio token \(token) started \(Self.formatTime(startTime)) "
                    + "speed \(requestedSpeed)x"
            )
        } catch P6PlayerError.unsupportedAudioInput {
            P6Diagnostics.write("audio skipped for \(selectedURL.lastPathComponent)")
        } catch {
            status = "Video playing; audio unavailable: \(error.localizedDescription)"
            P6Diagnostics.write(status)
        }
    }

    private static func formatTime(_ seconds: Double) -> String {
        let safeSeconds = max(0, seconds.isFinite ? seconds : 0)
        let totalSeconds = Int(safeSeconds.rounded(.down))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

#if os(macOS)
struct P6VideoFrame: Sendable, Equatable {
    let width: Int
    let height: Int
    let rgbaBytes: Data
    let serial: Int

    // Sample the frame for diagnostics without hashing every pixel.
    // 診斷時以間隔取樣影格，避免對每個像素進行雜湊。
    var diagnosticChecksum: UInt64 {
        rgbaBytes.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.bindMemory(to: UInt8.self).baseAddress else {
                return 0
            }
            var hash: UInt64 = 14_695_981_039_346_656_037
            let step = max(1, bytes.count / 4_096)
            var index = 0
            while index < bytes.count {
                hash ^= UInt64(baseAddress[index])
                hash &*= 1_099_511_628_211
                index += step
            }
            return hash
        }
    }
}

@MainActor
protocol P6FrameDisplaying: AnyObject {
    func update(_ frame: P6VideoFrame)
    func clearFrame()
}

@MainActor
final class P6FrameStore {
    // SwiftCrossUI may not rebuild a representable view for every large frame.
    // This store keeps the selected native renderer alive and pushes later frames directly.
    // SwiftCrossUI 不一定會為每個大型影格重建 representable view；此儲存器讓
    // 選定的原生 renderer 持續存在，並直接推送後續影格。
    private weak var view: (any P6FrameDisplaying)?
    private var pendingFrame: P6VideoFrame?

    func attach(_ view: any P6FrameDisplaying) {
        self.view = view
        if let pendingFrame {
            view.update(pendingFrame)
        }
    }

    func update(_ frame: P6VideoFrame) {
        // Keep the newest frame when the view has not been attached yet.
        // 若 view 尚未附加，先保留最新影格，之後 attach 時立即補送。
        pendingFrame = frame
        view?.update(frame)
        if frame.serial == 1 || frame.serial % 60 == 0 {
            P6Diagnostics.writeFrame("frame store pushed serial \(frame.serial)")
        }
    }

    func clear() {
        pendingFrame = nil
        view?.clearFrame()
    }
}

struct P6CoreVideoView: NSViewRepresentable {
    let store: P6FrameStore

    @MainActor
    func makeNSView(context _: Context) -> P6CoreVideoNSView {
        let view = P6CoreVideoNSView(frame: .zero)
        store.attach(view)
        return view
    }

    @MainActor
    func updateNSView(_ nsView: P6CoreVideoNSView, context _: Context) {
        store.attach(nsView)
    }
}

@MainActor
final class P6CoreVideoNSView: NSImageView, P6FrameDisplaying {
    private var lastFrameSerial: Int?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func update(_ frame: P6VideoFrame) {
        guard lastFrameSerial != frame.serial else { return }
        guard let nextImage = makeImage(from: frame) else {
            P6Diagnostics.write("core graphics image failed serial \(frame.serial)")
            return
        }

        lastFrameSerial = frame.serial
        // NSImageView owns the immutable image and displayIfNeeded performs the
        // AppKit redraw immediately instead of waiting for a layer transaction.
        // NSImageView 會持有不可變影像，displayIfNeeded 則立即執行 AppKit
        // 重繪，不等待 layer transaction。
        image = nextImage
        needsDisplay = true
        displayIfNeeded()
        if P6Diagnostics.isDebugEnabled,
           frame.serial == 1 || frame.serial % 60 == 0
        {
            let checksum = String(frame.diagnosticChecksum, radix: 16)
            P6Diagnostics.writeFrame(
                "core graphics displayed serial \(frame.serial) checksum \(checksum)"
            )
        }
    }

    func clearFrame() {
        lastFrameSerial = nil
        image = nil
    }

    private func configure() {
        imageAlignment = .alignCenter
        imageScaling = .scaleProportionallyUpOrDown
        imageFrameStyle = .none
    }

    private func makeImage(from frame: P6VideoFrame) -> NSImage? {
        guard let provider = CGDataProvider(data: frame.rgbaBytes as CFData) else {
            return nil
        }
        guard let image = CGImage(
            width: frame.width,
            height: frame.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: frame.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            return nil
        }
        return NSImage(
            cgImage: image,
            size: NSSize(width: frame.width, height: frame.height)
        )
    }
}

struct P6MetalVideoView: NSViewRepresentable {
    let store: P6FrameStore

    @MainActor
    func makeNSView(context _: Context) -> P6MetalVideoNSView {
        let view = P6MetalVideoNSView(frame: .zero, device: nil)
        store.attach(view)
        return view
    }

    @MainActor
    func updateNSView(_ nsView: P6MetalVideoNSView, context _: Context) {
        store.attach(nsView)
    }
}

@MainActor
final class P6MetalVideoNSView: MTKView, MTKViewDelegate, P6FrameDisplaying {
    private static let texturePoolSize = 3

    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
    private var samplerState: MTLSamplerState?
    private var videoTextures: [MTLTexture] = []
    private var nextTextureIndex = 0
    private var videoTexture: MTLTexture?
    private var lastFrameSerial: Int?

    override init(frame frameRect: NSRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device ?? MTLCreateSystemDefaultDevice())
        configure()
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        device = MTLCreateSystemDefaultDevice()
        configure()
    }

    func update(_ frame: P6VideoFrame) {
        guard lastFrameSerial != frame.serial else { return }
        guard replaceTexture(with: frame) else { return }
        lastFrameSerial = frame.serial
        setNeedsDisplay(bounds)
        if P6Diagnostics.isDebugEnabled,
           frame.serial == 1 || frame.serial % 60 == 0
        {
            let checksum = String(frame.diagnosticChecksum, radix: 16)
            P6Diagnostics.writeFrame(
                "metal texture uploaded serial \(frame.serial) checksum \(checksum)"
            )
        }
    }

    func clearFrame() {
        lastFrameSerial = nil
        videoTextures.removeAll(keepingCapacity: false)
        nextTextureIndex = 0
        videoTexture = nil
        setNeedsDisplay(bounds)
    }

    func draw(in view: MTKView) {
        renderCurrentTexture()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    private func configure() {
        guard let device else { return }
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        delegate = self
        isPaused = true
        enableSetNeedsDisplay = true
        clearColor = MTLClearColorMake(0, 0, 0, 1)
        commandQueue = device.makeCommandQueue()
        samplerState = makeSampler(device: device)
        pipelineState = makePipeline(device: device)
    }

    private func replaceTexture(with frame: P6VideoFrame) -> Bool {
        guard let device else { return false }

        if videoTextures.count != Self.texturePoolSize
            || videoTextures.first?.width != frame.width
            || videoTextures.first?.height != frame.height
        {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: frame.width,
                height: frame.height,
                mipmapped: false
            )
            descriptor.usage = [.shaderRead]

            var replacementPool: [MTLTexture] = []
            replacementPool.reserveCapacity(Self.texturePoolSize)
            for _ in 0..<Self.texturePoolSize {
                guard let texture = device.makeTexture(descriptor: descriptor) else {
                    return false
                }
                replacementPool.append(texture)
            }
            videoTextures = replacementPool
            nextTextureIndex = 0
        }

        // Rotate through three reusable textures instead of allocating roughly
        // 31.6 MiB for every 4K RGBA frame.
        // 循環使用三個紋理，避免每個 4K RGBA 影格都重新配置約 31.6 MiB。
        let texture = videoTextures[nextTextureIndex]
        nextTextureIndex = (nextTextureIndex + 1) % videoTextures.count
        frame.rgbaBytes.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            texture.replace(
                region: MTLRegionMake2D(0, 0, frame.width, frame.height),
                mipmapLevel: 0,
                withBytes: baseAddress,
                bytesPerRow: frame.width * 4
            )
        }
        videoTexture = texture
        return true
    }

    private func renderCurrentTexture() {
        guard let commandQueue,
              let pipelineState,
              let samplerState,
              let videoTexture,
              let currentDrawable,
              let descriptor = currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else {
            return
        }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentTexture(videoTexture, index: 0)
        encoder.setFragmentSamplerState(samplerState, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        commandBuffer.present(currentDrawable)
        commandBuffer.commit()
        if P6Diagnostics.isDebugEnabled,
           let serial = lastFrameSerial,
           serial == 1 || serial % 60 == 0
        {
            P6Diagnostics.writeFrame("metal presented serial \(serial)")
        }
    }

    private func makeSampler(device: MTLDevice) -> MTLSamplerState? {
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.sAddressMode = .clampToEdge
        descriptor.tAddressMode = .clampToEdge
        return device.makeSamplerState(descriptor: descriptor)
    }

    private func makePipeline(device: MTLDevice) -> MTLRenderPipelineState? {
        let source = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexOut {
            float4 position [[position]];
            float2 texCoord;
        };

        vertex VertexOut vertex_main(uint vertexID [[vertex_id]]) {
            float2 positions[4] = {
                float2(-1.0, -1.0), float2(1.0, -1.0),
                float2(-1.0, 1.0), float2(1.0, 1.0)
            };
            float2 texCoords[4] = {
                float2(0.0, 1.0), float2(1.0, 1.0),
                float2(0.0, 0.0), float2(1.0, 0.0)
            };
            VertexOut out;
            out.position = float4(positions[vertexID], 0.0, 1.0);
            out.texCoord = texCoords[vertexID];
            return out;
        }

        fragment float4 fragment_main(
            VertexOut in [[stage_in]],
            texture2d<float> imageTexture [[texture(0)]],
            sampler imageSampler [[sampler(0)]])
        {
            return imageTexture.sample(imageSampler, in.texCoord);
        }
        """

        do {
            let library = try device.makeLibrary(source: source, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "vertex_main")
            descriptor.fragmentFunction = library.makeFunction(name: "fragment_main")
            descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            P6Diagnostics.write("metal pipeline failed: \(error.localizedDescription)")
            return nil
        }
    }
}
#endif

struct P6OutputResolution: Sendable, Equatable {
    static let preview = P6OutputResolution(label: "Preview 960x540", width: 960, height: 540)
    static let fullHD = P6OutputResolution(label: "1080p 1920x1080", width: 1_920, height: 1_080)
    static let ultraHD = P6OutputResolution(label: "4K 3840x2160", width: 3_840, height: 2_160)

    static let allCases = [preview, fullHD, ultraHD]

    let label: String
    let width: Int
    let height: Int

    init(label: String, width: Int, height: Int) {
        self.label = label
        self.width = width
        self.height = height
    }

    init(label: String?) {
        self = Self.allCases.first { $0.label == label } ?? .preview
    }
}

/// Buffers a child process's stderr instead of letting it reach the terminal.
/// Stopping the decoder early makes ffmpeg fail its pending writes with EPIPE,
/// which is expected noise, so the text is only surfaced for real failures.
/// 將子程序的 stderr 緩衝起來而不直接輸出到終端機。提早停止解碼會讓 ffmpeg 的
/// 待寫入資料以 EPIPE 失敗，那是預期中的雜訊，因此只在真正失敗時才顯示內容。
final class P6ProcessErrorLog: @unchecked Sendable {
    private static let byteLimit = 8192

    private let lock = NSLock()
    private var buffer = Data()

    func append(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(data)
        // A failing tool can emit output without bound; keep only the tail.
        // 失敗的工具可能無上限地輸出，因此只保留尾端。
        if buffer.count > Self.byteLimit {
            buffer.removeFirst(buffer.count - Self.byteLimit)
        }
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: buffer, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

final class P6DecoderSession: @unchecked Sendable {
    private let ffmpeg: Process
    private let zstd: Process?
    private let outputHandle: FileHandle
    private let errorHandle: FileHandle
    private let errorLog: P6ProcessErrorLog
    private let frameByteCount: Int
    private let stateLock = NSLock()
    private var terminated = false

    init(
        inputURL: URL,
        startTime: Double,
        speed: Double,
        framesPerSecond: Int,
        outputResolution: P6OutputResolution
    ) throws {
        guard let ffmpegURL = P6ToolLocator.find("ffmpeg") else {
            throw P6PlayerError.missingTool("ffmpeg")
        }

        self.frameByteCount = outputResolution.width * outputResolution.height * 4

        let compressed = inputURL.pathExtension.lowercased() == "zst"
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let errorLog = P6ProcessErrorLog()
        // Capture the local log, not self, so the handler cannot retain the
        // session and prevent deinit from terminating the child processes.
        // 捕捉區域變數而非 self，避免 handler 保留 session 而讓 deinit 無法終止子程序。
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            errorLog.append(data)
        }

        let ffmpeg = Process()
        ffmpeg.executableURL = ffmpegURL
        ffmpeg.standardOutput = outputPipe
        ffmpeg.standardError = errorPipe

        let seekValue = String(format: "%.6f", max(0, startTime))
        let filter = [
            "setpts=(PTS-STARTPTS)/\(speed)",
            "fps=\(framesPerSecond)",
            "scale=\(outputResolution.width):\(outputResolution.height):force_original_aspect_ratio=decrease:flags=fast_bilinear",
            "pad=\(outputResolution.width):\(outputResolution.height):(ow-iw)/2:(oh-ih)/2:color=black",
        ].joined(separator: ",")

        var arguments = ["-nostdin", "-hide_banner", "-loglevel", "error"]
        var zstdProcess: Process?
        var sourcePipe: Pipe?

        if compressed {
            guard let zstdURL = P6ToolLocator.find("zstd") else {
                throw P6PlayerError.missingTool("zstd")
            }

            let pipe = Pipe()
            sourcePipe = pipe
            ffmpeg.standardInput = pipe
            arguments += ["-f", "yuv4mpegpipe", "-i", "pipe:0"]
            if startTime > 0 {
                arguments += ["-ss", seekValue]
            }

            let process = Process()
            process.executableURL = zstdURL
            process.arguments = ["-q", "-d", "-c", inputURL.path]
            process.standardOutput = pipe
            process.standardError = errorPipe
            zstdProcess = process
        } else {
            if startTime > 0 {
                arguments += ["-ss", seekValue]
            }
            arguments += ["-i", inputURL.path]
        }

        arguments += [
            "-an", "-sn", "-dn",
            "-vf", filter,
            "-pix_fmt", "rgba",
            "-f", "rawvideo",
            "pipe:1",
        ]
        ffmpeg.arguments = arguments

        do {
            try ffmpeg.run()
            P6ChildProcessReaper.adopt(ffmpeg)
            outputPipe.fileHandleForWriting.closeFile()
            sourcePipe?.fileHandleForReading.closeFile()

            if let zstdProcess {
                try zstdProcess.run()
                P6ChildProcessReaper.adopt(zstdProcess)
                sourcePipe?.fileHandleForWriting.closeFile()
            }

            // Close the parent's write end last, once every child that inherits
            // it has spawned; otherwise the read end never sees EOF.
            // 待所有繼承此描述符的子程序都啟動後才關閉父程序的寫入端，
            // 否則讀取端永遠等不到 EOF。
            errorPipe.fileHandleForWriting.closeFile()
        } catch {
            errorPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForWriting.closeFile()
            if ffmpeg.isRunning {
                ffmpeg.terminate()
            }
            if let zstdProcess, zstdProcess.isRunning {
                zstdProcess.terminate()
            }
            throw error
        }

        self.ffmpeg = ffmpeg
        self.zstd = zstdProcess
        self.outputHandle = outputPipe.fileHandleForReading
        self.errorHandle = errorPipe.fileHandleForReading
        self.errorLog = errorLog
    }

    deinit {
        terminate()
    }

    #if os(Windows)
    /// Reads exactly one frame straight into caller-provided memory.
    ///
    /// This is the zero-copy path: `destination` is a mapped D3D11 staging
    /// texture, so bytes go from the pipe into GPU-visible memory with no
    /// intermediate Data, Array, or image object. `rowPitch` is the mapped
    /// texture's stride, which may exceed the frame's own row length, so rows
    /// are read one at a time.
    /// 這是零複製路徑：`destination` 是已對映的 D3D11 staging texture，位元組
    /// 直接從 pipe 進入 GPU 可見記憶體，中間不產生 Data、Array 或影像物件。
    /// `rowPitch` 為對映後的列間距，可能大於影格本身的列長度，因此逐列讀取。
    ///
    /// NOTE: this still performs one memcpy from Foundation's buffer into the
    /// mapped texture. Reading the pipe *directly* into GPU memory needs a
    /// Win32 HANDLE, but Foundation on Windows refuses to expose one
    /// (`FileHandle.fileDescriptor` is unavailable: "Cannot perform
    /// non-owning handle to fd conversion"), so eliminating this last copy
    /// requires replacing Foundation's Pipe with a named pipe read via
    /// ReadFile. Everything else on the old path -- the Array copy, the
    /// ImageFormats.Image, the per-frame WriteableBitmap allocation, the
    /// 8.3M-pixel conversion loop and the view-graph update -- is already gone.
    /// 註：此處仍有一次從 Foundation 緩衝區複製到已對映 texture 的 memcpy。
    /// 若要直接從 pipe 讀入 GPU 記憶體需要 Win32 HANDLE，但 Windows 上的
    /// Foundation 不提供（`FileHandle.fileDescriptor` 不可用），因此要消除最後
    /// 這次複製，必須改以具名管線搭配 ReadFile 取代 Foundation 的 Pipe。
    func readFrame(
        into destination: UnsafeMutableRawPointer,
        rowPitch: Int,
        width: Int,
        height: Int
    ) throws -> Bool {
        guard let data = try readFrame() else { return false }
        let bytesPerRow = width * 4

        data.withUnsafeBytes { source in
            guard let base = source.baseAddress else { return }
            if rowPitch == bytesPerRow {
                memcpy(destination, base, bytesPerRow * height)
            } else {
                for row in 0..<height {
                    memcpy(
                        destination.advanced(by: row * rowPitch),
                        base.advanced(by: row * bytesPerRow),
                        bytesPerRow
                    )
                }
            }
        }
        return true
    }
    #endif

    func readFrame() throws -> Data? {
        var data = Data()
        data.reserveCapacity(frameByteCount)

        while data.count < frameByteCount {
            if isTerminated { return nil }
            let remaining = frameByteCount - data.count
            guard let chunk = try outputHandle.read(upToCount: remaining), !chunk.isEmpty else {
                if data.isEmpty { return nil }
                throw P6PlayerError.incompleteFrame(
                    data.count,
                    frameByteCount,
                    errorLog.text
                )
            }
            data.append(chunk)
        }

        return data
    }

    func terminate() {
        stateLock.lock()
        if terminated {
            stateLock.unlock()
            return
        }
        terminated = true
        stateLock.unlock()

        // Signal the children before closing the read end. Closing first makes
        // ffmpeg's in-flight writes fail with EPIPE, which it reports as
        // "Broken pipe" muxer/trailer errors even though the shutdown is ours.
        // 先向子程序送出訊號再關閉讀取端。若先關閉，ffmpeg 進行中的寫入會以 EPIPE
        // 失敗，即使關閉是我方主動發起，它仍會回報 "Broken pipe" 的 muxer/trailer 錯誤。
        if ffmpeg.isRunning {
            ffmpeg.terminate()
        }
        if let zstd, zstd.isRunning {
            zstd.terminate()
        }

        // Drain the read end in the background so a child blocked writing into a
        // full pipe can observe the signal and exit. Waiting here would stall the
        // UI, because invalidateCurrentDecoder() calls terminate() on the main
        // actor. The handler closes the descriptor once the child reaches EOF.
        // 於背景排空讀取端，讓因管線寫滿而阻塞的子程序能收到訊號並結束。在此等待會
        // 卡住 UI，因為 invalidateCurrentDecoder() 是在主執行者上呼叫 terminate()。
        // handler 會在子程序送出 EOF 後關閉該描述符。
        outputHandle.readabilityHandler = { handle in
            if handle.availableData.isEmpty {
                handle.readabilityHandler = nil
                // Closing synchronously here would call FileHandle.close(),
                // which dispatches a barrier sync onto this same handle's
                // internal source queue -- but we're currently running on
                // that queue, inside its own readability callback. That
                // self-sync is a deadlock; dispatch detects it and traps
                // (observed as an illegal instruction in dispatch.dll on
                // Windows) instead of actually hanging. Close from a
                // different queue so it isn't a same-queue sync.
                DispatchQueue.global().async {
                    try? handle.close()
                }
            }
        }

        errorHandle.readabilityHandler = nil
        try? errorHandle.close()
    }

    /// Buffered stderr from the child tools, used to explain real failures.
    /// 子工具緩衝後的 stderr，用於說明真正的失敗原因。
    var errorOutput: String {
        errorLog.text
    }

    private var isTerminated: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return terminated
    }
}

final class P6AudioSession: @unchecked Sendable {
    private let ffplay: Process
    private let stateLock = NSLock()
    private var terminated = false

    var processIdentifier: Int32 {
        // Keep PID access tied to the retained Process instead of searching the
        // global process table, which could match an unrelated ffplay instance.
        // PID 直接取自所保留的 Process，不搜尋全域程序表，避免誤認其他 ffplay。
        ffplay.processIdentifier
    }

    init(
        inputURL: URL,
        startTime: Double,
        speed: Double
    ) throws {
        let lowercasedName = inputURL.lastPathComponent.lowercased()
        if lowercasedName.hasSuffix(".zst") || lowercasedName.hasSuffix(".y4m") {
            throw P6PlayerError.unsupportedAudioInput
        }

        guard let ffplayURL = P6ToolLocator.find("ffplay") else {
            throw P6PlayerError.missingTool("ffplay")
        }

        let process = Process()
        process.executableURL = ffplayURL
        process.arguments = [
            "-nodisp",
            "-autoexit",
            "-hide_banner",
            "-loglevel",
            "error",
            // WebM's default demuxer seek can fall back several seconds to the
            // preceding indexed video keyframe even though ffplay outputs audio
            // only. Allow seeking to an audio packet near the requested time.
            // WebM 預設 demuxer seek 可能退回數秒前的視訊索引關鍵影格，即使
            // ffplay 只輸出音訊亦然；允許定位至接近要求時間的音訊封包。
            "-seek2any",
            "1",
            "-ss",
            String(format: "%.6f", max(0, startTime)),
            "-i",
            inputURL.path,
            "-vn",
            "-sn",
            "-af",
            "atempo=\(speed)",
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.standardError

        do {
            try process.run()
        } catch {
            throw error
        }

        P6ChildProcessReaper.adopt(process)
        ffplay = process
    }

    deinit {
        terminate()
    }

    func terminate() {
        terminate(waitForExit: false)
    }

    func terminateAndWait() {
        terminate(waitForExit: true)
    }

    private func terminate(waitForExit: Bool) {
        stateLock.lock()
        if terminated {
            stateLock.unlock()
            return
        }
        terminated = true
        stateLock.unlock()

        if ffplay.isRunning {
            // Send SIGTERM first. Window closing waits synchronously so AppKit
            // cannot close before ffplay exits; normal restarts reap it in the background.
            // 先送出 SIGTERM。關閉視窗時會同步等待，避免 AppKit 在 ffplay 結束前
            // 關閉；一般重啟時則由背景工作回收程序。
            P6Diagnostics.write("ffplay terminating pid \(ffplay.processIdentifier)")
            ffplay.terminate()
            let process = ffplay
            if waitForExit {
                process.waitUntilExit()
                P6Diagnostics.write(
                    "ffplay exited status \(process.terminationStatus)"
                )
            } else {
                DispatchQueue.global(qos: .utility).async {
                    process.waitUntilExit()
                    P6Diagnostics.write(
                        "ffplay exited status \(process.terminationStatus)"
                    )
                }
            }
        }
    }
}

enum P6MediaProbe {
    static func duration(for inputURL: URL) -> Double? {
        guard let probeInput = probeInput(for: inputURL),
              let ffprobeURL = P6ToolLocator.find("ffprobe")
        else {
            return nil
        }

        let outputPipe = Pipe()
        let process = Process()
        process.executableURL = ffprobeURL
        process.arguments = [
            "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1",
            probeInput.path,
        ]
        process.standardOutput = outputPipe
        process.standardError = FileHandle.standardError

        do {
            try process.run()
            outputPipe.fileHandleForWriting.closeFile()
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let value = String(data: data, encoding: .utf8)
                    .flatMap({ Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }),
                  value.isFinite,
                  value > 0
            else {
                return nil
            }
            return value
        } catch {
            return nil
        }
    }

    static func resolution(for inputURL: URL) -> SIMD2<Int>? {
        guard let probeInput = probeInput(for: inputURL),
              let ffprobeURL = P6ToolLocator.find("ffprobe")
        else {
            return nil
        }

        let outputPipe = Pipe()
        let process = Process()
        process.executableURL = ffprobeURL
        process.arguments = [
            "-v", "error",
            "-select_streams", "v:0",
            "-show_entries", "stream=width,height",
            "-of", "csv=s=x:p=0",
            probeInput.path,
        ]
        process.standardOutput = outputPipe
        process.standardError = FileHandle.standardError

        do {
            try process.run()
            outputPipe.fileHandleForWriting.closeFile()
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let value = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            else {
                return nil
            }

            let parts = value.split(separator: "x")
            guard parts.count == 2,
                  let width = Int(parts[0]),
                  let height = Int(parts[1]),
                  width > 0,
                  height > 0
            else {
                return nil
            }

            return SIMD2(width, height)
        } catch {
            return nil
        }
    }

    private static func probeInput(for inputURL: URL) -> URL? {
        let name = inputURL.lastPathComponent
        let lowercasedName = name.lowercased()

        if lowercasedName.hasSuffix(".y4m.zst") {
            let baseName = String(name.dropLast(".y4m.zst".count))
            let sibling = inputURL.deletingLastPathComponent()
                .appendingPathComponent("\(baseName).mp4")
            return FileManager.default.fileExists(atPath: sibling.path) ? sibling : nil
        }

        if lowercasedName.hasSuffix(".zst") {
            return nil
        }

        return inputURL
    }
}

enum P6ToolLocator {
    static func find(_ tool: String) -> URL? {
        #if os(Windows)
            let executableName = tool.lowercased().hasSuffix(".exe") ? tool : "\(tool).exe"
            let separator: Character = ";"
        #else
            let executableName = tool
            let separator: Character = ":"
        #endif

        var directories = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: separator)
            .map(String.init) ?? []

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #if os(Windows)
            directories.append("\(home)\\scoop\\shims")
            directories.append("\(home)\\AppData\\Local\\Microsoft\\WinGet\\Links")
        #elseif os(macOS)
            directories += [
                "/opt/homebrew/bin",
                "/usr/local/bin",
                "/opt/local/bin",
                "/usr/bin",
                "/bin",
            ]
        #else
            directories += ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        #endif

        var seen = Set<String>()
        for directory in directories {
            let cleanDirectory = directory.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            guard seen.insert(cleanDirectory).inserted else { continue }
            let candidate = URL(fileURLWithPath: cleanDirectory)
                .appendingPathComponent(executableName)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }
}

enum P6PlayerError: LocalizedError {
    case missingTool(String)
    case incompleteFrame(Int, Int, String)
    case unsupportedAudioInput

    var errorDescription: String? {
        switch self {
            case .missingTool(let tool):
                return "Required tool '\(tool)' was not found on PATH."
            case .incompleteFrame(let actual, let expected, let toolOutput):
                let summary =
                    "Decoder returned an incomplete RGBA frame (\(actual) of \(expected) bytes)."
                // Child stderr is buffered rather than printed, so a genuine
                // decode failure has to carry it here to stay diagnosable.
                // 子程序的 stderr 是緩衝而非直接輸出，因此真正的解碼失敗必須在此
                // 一併帶出，才不會失去可診斷性。
                guard !toolOutput.isEmpty else { return summary }
                return "\(summary) \(toolOutput)"
            case .unsupportedAudioInput:
                return "This input is treated as video-only."
        }
    }
}

/// Guarantees child tools (ffmpeg/ffplay/zstd) die with P6.
///
/// On macOS the close-confirmation and signal handlers already reap them, but
/// those are AppKit-only, so on Windows a closed window could leave ffplay
/// still playing audio. A Job Object with KILL_ON_JOB_CLOSE makes Windows
/// itself terminate every adopted child as soon as the P6 process exits --
/// including on a crash or force-kill, which no in-process handler can cover.
enum P6ChildProcessReaper {
    #if os(Windows)
    private static let job: HANDLE? = {
        guard let job = CreateJobObjectW(nil, nil) else { return nil }
        var limits = JOBOBJECT_EXTENDED_LIMIT_INFORMATION()
        limits.BasicLimitInformation.LimitFlags =
            DWORD(JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE)
        let ok = withUnsafeMutablePointer(to: &limits) { pointer in
            SetInformationJobObject(
                job,
                JobObjectExtendedLimitInformation,
                pointer,
                DWORD(MemoryLayout<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>.size)
            )
        }
        guard ok else {
            CloseHandle(job)
            return nil
        }
        return job
    }()
    #endif

    static func adopt(_ process: Process) {
        #if os(Windows)
        guard let job else {
            P6Diagnostics.write("child reaper unavailable; job object not created")
            return
        }
        let pid = DWORD(process.processIdentifier)
        guard let handle = OpenProcess(DWORD(PROCESS_SET_QUOTA | PROCESS_TERMINATE), false, pid)
        else {
            P6Diagnostics.write("child reaper could not open pid \(pid)")
            return
        }
        defer { CloseHandle(handle) }
        if !AssignProcessToJobObject(job, handle) {
            P6Diagnostics.write("child reaper could not adopt pid \(pid)")
        }
        #endif
    }
}

enum P6Diagnostics {
    static let isDebugEnabled = CommandLine.arguments.contains("--debug")
    /// `-enable-dropframe` is the short spelling used alongside `-f` for
    /// unattended test runs.
    static let isFrameDropEnabled =
        CommandLine.arguments.contains("--frame-drop")
        || CommandLine.arguments.contains("-enable-dropframe")
    /// Starts playback immediately after `-f` auto-loads a file, so a test
    /// run needs no clicks at all.
    static let isAutoplayEnabled = CommandLine.arguments.contains("-autoplay")

    static func writeFrame(_ message: @autoclosure () -> String) {
        guard isDebugEnabled else { return }
        write(message())
    }

    static func write(_ message: String) {
        guard let data = "P6 \(Date()) \(message)\n".data(using: .utf8) else { return }

        let logURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p6-debug-events.log")
        if FileManager.default.fileExists(atPath: logURL.path),
           let handle = try? FileHandle(forWritingTo: logURL)
        {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: logURL)
        }
    }
}
