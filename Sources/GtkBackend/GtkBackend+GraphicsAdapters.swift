import Foundation
import GtkCHelpers

@_spi(Backends) import SwiftCrossUI

#if os(Windows)
    import WinSDK
#elseif os(macOS)
    import Metal
#endif

/// GtkBackend's half of adapter selection: what exists, and how to select it.
///
/// The rules -- the numbering, the fallback chain, what to report -- are in
/// ``GraphicsAdapterSelection`` and are not repeated here. This file answers
/// only the two platform questions.
///
/// GtkBackend 在介面卡選擇上所負責的那一半：有哪些介面卡，以及如何選定。
///
/// 規則本身——編號方式、退路鏈、該回報什麼——位於 ``GraphicsAdapterSelection``，此處不重複。
/// 本檔只回答那兩個與平台有關的問題。
extension GtkBackend: BackendFeatures.GraphicsAdapters {
    public var availableAdapters: [GraphicsAdapter] {
        #if os(Windows)
            // The primary adapter first, because
            // `GraphicsAdapterSelection.systemDefault` takes the first and that
            // is what Windows would itself choose.
            // 主要介面卡排在最前，因為 `GraphicsAdapterSelection.systemDefault` 取的是第一張，
            // 而那正是 Windows 自己會選的那一張。
            var adapters: [GraphicsAdapter] = []
            var index: DWORD = 0
            while true {
                var device = DISPLAY_DEVICEW()
                device.cb = DWORD(MemoryLayout<DISPLAY_DEVICEW>.size)
                guard EnumDisplayDevicesW(nil, index, &device, 0) else { break }
                index += 1
                let name = withUnsafeBytes(of: device.DeviceString) { raw -> String in
                    guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt16.self) else {
                        return ""
                    }
                    return String(decodingCString: base, as: UTF16.self)
                }
                guard !name.isEmpty, !name.hasPrefix("Microsoft Basic"),
                    !adapters.contains(where: { $0.name == name })
                else { continue }

                // wingdi.h flags, spelled out because Swift imports values and
                // not macros: PRIMARY_DEVICE 0x4, REMOVABLE 0x20.
                // 取自 wingdi.h 的旗標，之所以寫成字面值，是因為 Swift 匯入的是值而非巨集：
                // PRIMARY_DEVICE 為 0x4、REMOVABLE 為 0x20。
                let isPrimary = device.StateFlags & 0x0000_0004 != 0
                let adapter = GraphicsAdapter(
                    name: name,
                    isRemovable: device.StateFlags & 0x0000_0020 != 0,
                    isLowPower: isPrimary
                )
                if isPrimary {
                    adapters.insert(adapter, at: 0)
                } else {
                    adapters.append(adapter)
                }
            }
            return adapters
        #elseif os(macOS)
            // The same list AppKitBackend reports, from Metal, system default first:
            // the GPUs exist whichever toolkit draws the window.
            // 與 AppKitBackend 回報的是同一份清單，取自 Metal,系統預設排第一：不論由哪個工具組繪製視窗，
            // GPU 都在那裡。
            let systemDefault = MTLCreateSystemDefaultDevice()
            let ordered = MTLCopyAllDevices().sorted { first, _ in
                first.registryID == systemDefault?.registryID
            }
            return ordered.map { device in
                GraphicsAdapter(
                    name: device.name,
                    isRemovable: device.isRemovable,
                    isLowPower: device.isLowPower
                )
            }
        #else
            // Linux: the cards /sys/class/drm lists, the boot GPU first (`drmCards`).
            // Linux:/sys/class/drm 列出的顯示卡，開機用的那張排第一(`drmCards`)。
            // Under WSL there are none, and the GPUs come from DXCore instead.
            // WSL 下一張都沒有，改由 DXCore 提供 GPU。
            let cards = Self.drmCards()
            return cards.isEmpty ? Self.dxcoreAdapters() : cards.map(\.adapter)
        #endif
    }

    public func applyAdapter(
        _ resolution: GraphicsAdapterResolution
    ) -> BackendFeatures.AdapterOutcome {
        #if os(Windows)
            guard let adapter = resolution.adapter else {
                // Software was asked for, or fallen back to. Direct Composition
                // is simply not requested, which `enableDirectCompositionIfRequested`
                // already handles from the same number.
                // 使用者要求軟體繪製，或退路至此。此時單純不要求 Direct Composition，而
                // `enableDirectCompositionIfRequested` 已依同一個數字處理了這件事。
                return .applied
            }

            // Windows selects an OpenGL adapter by POLICY, not by name or index:
            // UserGpuPreferences takes 0 unspecified, 1 power saving, 2 high
            // performance, and a WGL context has no per-adapter selection. So an
            // ordinal beyond the second cannot be honoured here -- and that is a
            // GtkBackend limit, not a Windows one. WinUIBackend reaches the same
            // cards through DXGI, where D3D11CreateDevice takes an explicit
            // adapter.
            //
            // Windows 是以**政策**而非名稱或索引來選擇 OpenGL 介面卡：UserGpuPreferences 接受
            // 0 未指定、1 省電、2 高效能，而 WGL context 沒有逐一介面卡的選擇機制。因此超過第二
            // 張的序數在此無法被遵從——而這是 GtkBackend 的限制，並非 Windows 的限制。
            // WinUIBackend 透過 DXGI 觸及同一批卡，其 D3D11CreateDevice 可接受明確指定的 adapter。
            let wanted: Int
            switch resolution.resolved {
                case .software: return .applied
                case .systemDefault: wanted = 1
                case .external(let ordinal):
                    guard ordinal == 1 else {
                        return .unavailable(
                            reason: """
                                GtkBackend renders through OpenGL, and Windows selects an OpenGL \
                                adapter only by policy (0 unspecified, 1 power saving, \
                                2 high performance). "\(adapter.name)" is external adapter \
                                \(ordinal), which cannot be named. Use WinUIBackend, which \
                                selects through DXGI.
                                """
                        )
                    }
                    wanted = 2
            }

            guard let executable = Self.executablePath() else {
                return .unavailable(reason: "could not determine this executable's path")
            }
            if Self.readGpuPreference(for: executable) == wanted {
                return .alreadyActive
            }
            return .needsRestart(
                reason: """
                    Windows fixes an OpenGL process's adapter when the process is created, from \
                    HKCU\\Software\\Microsoft\\DirectX\\UserGpuPreferences. Selecting \
                    "\(adapter.name)" means writing GpuPreference=\(wanted) and starting again.
                    """
            )
        #elseif os(macOS)
            // GTK on macOS draws through the system's OpenGL, which runs on the GPU
            // Metal calls the system default: the process does not pick one. Selecting
            // the default is therefore already in effect, and another card cannot be
            // chosen from inside GTK (GDK creates its own context).
            // macOS 上的 GTK 經由系統的 OpenGL 繪製，它跑在 Metal 稱為系統預設的那張 GPU 上，行程不自行挑選。
            // 因此選預設那張就是已生效；其他卡無法從 GTK 內部選定(GDK 自己建立 context)。
            guard let adapter = resolution.adapter else { return .applied }
            if adapter.name == MTLCreateSystemDefaultDevice()?.name {
                return .alreadyActive
            }
            return .unavailable(
                reason: """
                    GtkBackend on macOS renders through GDK's OpenGL context, which macOS puts on \
                    the system default GPU. "\(adapter.name)" is not that GPU, and GDK has no \
                    call to place its context elsewhere.
                    """
            )
        #else
            // Linux selects a GL device per process from the environment, read when GL
            // initialises -- and this runs before any drawing (`_App`). Mesa takes
            // DRI_PRIME=pci-<bus id>; the NVIDIA driver takes PRIME render offload.
            // Linux 由環境變數為每個行程選定 GL 裝置，於 GL 初始化時讀取——而這段在任何繪製之前執行(`_App`)。
            // Mesa 接受 DRI_PRIME=pci-<匯流排位址>;NVIDIA 驅動接受 PRIME render offload。
            guard let adapter = resolution.adapter else {
                setenv("LIBGL_ALWAYS_SOFTWARE", "1", 1)
                return .applied
            }
            // Under WSL the GPUs come from DXCore, and Mesa's d3d12 driver takes
            // the one to use by name, read at GL initialisation like the above.
            // WSL 下 GPU 來自 DXCore,Mesa 的 d3d12 驅動以名稱選擇要用的那張，與上方相同於 GL 初始化時讀取。
            if Self.drmCards().isEmpty,
                Self.dxcoreAdapters().contains(where: { $0.name == adapter.name })
            {
                setenv("MESA_D3D12_DEFAULT_ADAPTER_NAME", adapter.name, 1)
                return .applied
            }
            guard let card = Self.drmCards().first(where: { $0.adapter.name == adapter.name }) else {
                return .unavailable(reason: "\"\(adapter.name)\" is no longer listed under /sys/class/drm")
            }
            if card.isBootVGA {
                return .alreadyActive
            }
            if card.driver == "nvidia" {
                setenv("__NV_PRIME_RENDER_OFFLOAD", "1", 1)
                setenv("__GLX_VENDOR_LIBRARY_NAME", "nvidia", 1)
            } else {
                setenv("DRI_PRIME", Self.primeName(busID: card.busID), 1)
            }
            return .applied
        #endif
    }

    #if !os(Windows) && !os(macOS)
        /// The GPUs DXCore lists, for WSL, which has no /sys/class/drm: its GPUs
        /// reach Linux through /dev/dxg and Mesa's d3d12 driver draws on them
        /// (gtk_dxcore.c). Empty outside WSL. Inside WSL, /sys/class/drm lists
        /// only the virtual vgem device.
        /// DXCore 所列的 GPU,給沒有 /sys/class/drm 的 WSL 用：它的 GPU 經 /dev/dxg 進入 Linux,
        /// 由 Mesa 的 d3d12 驅動繪製(gtk_dxcore.c)。WSL 以外為空；在 WSL 中 /sys/class/drm 只列出虛擬的 vgem 裝置。
        static func dxcoreAdapters() -> [GraphicsAdapter] {
            var entries = [scui_dxcore_adapter](repeating: scui_dxcore_adapter(), count: 8)
            let count = Int(scui_dxcore_adapters(&entries, Int32(entries.count)))
            return entries.prefix(count).map { entry in
                let name = withUnsafeBytes(of: entry.name) { raw in
                    String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
                }
                return GraphicsAdapter(
                    name: name,
                    isRemovable: false,
                    isLowPower: entry.integrated != 0
                )
            }
        }

        /// One GPU as /sys/class/drm describes it.
        struct DRMCard {
            var adapter: GraphicsAdapter
            var driver: String
            var busID: String
            var isBootVGA: Bool
        }

        /// The cards under /sys/class/drm (card0, card1, ...; not their connectors),
        /// the one the firmware booted on first, which is what GL picks unasked.
        /// /sys/class/drm 底下的顯示卡(card0、card1……,不含其接頭),韌體開機所用的那張排第一，
        /// 也就是不指定時 GL 會選的那張。
        /// `root` is a parameter for the tests, which build a fake tree
        /// (GtkDRMCardTests); everything else reads the real one.
        /// `root` 是給測試用的參數，測試會建一棵假的目錄樹(GtkDRMCardTests);其他呼叫都讀真正的那棵。
        static func drmCards(root: String = "/sys/class/drm") -> [DRMCard] {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
            func read(_ path: String) -> String? {
                (try? String(contentsOfFile: path, encoding: .utf8))?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            var cards: [DRMCard] = []
            for name in names.sorted()
            where name.hasPrefix("card") && name.dropFirst(4).allSatisfy(\.isNumber) {
                let device = "\(root)/\(name)/device"
                let uevent = read("\(device)/uevent") ?? ""
                func field(_ key: String) -> String? {
                    uevent.split(separator: "\n").first { $0.hasPrefix(key + "=") }
                        .map { String($0.dropFirst(key.count + 1)) }
                }
                let driver = field("DRIVER") ?? "unknown"
                let busID = field("PCI_SLOT_NAME")
                    ?? ((try? FileManager.default.destinationOfSymbolicLink(atPath: device))
                        .map { ($0 as NSString).lastPathComponent } ?? name)
                let pciID = field("PCI_ID") ?? ""
                // Not GPUs: vgem and vkms are virtual memory and modesetting devices
                // that draw nothing, on the faux bus in newer kernels. WSL lists vgem as
                // "faux_driver vgem", and it hid the two real GPUs DXCore has (P68 read
                // "adapters: 1  faux_driver vgem (vgem)", 2026-10-19).
                // 不是 GPU:vgem 與 vkms 是不繪圖的虛擬記憶體與 modesetting 裝置，在較新的核心掛在 faux bus 上。
                // WSL 把 vgem 列為 "faux_driver vgem",於是蓋掉了 DXCore 那兩張真正的 GPU(2026-10-19)。
                let virtualDevices: Set<String> = ["vgem", "vkms", "faux_driver"]
                if virtualDevices.contains(driver) || virtualDevices.contains(busID) {
                    continue
                }
                let isBootVGA = read("\(device)/boot_vga") == "1"
                let removable = read("\(device)/removable") == "removable"
                let card = DRMCard(
                    adapter: GraphicsAdapter(
                        name: "\(driver) \(pciID.isEmpty ? busID : pciID) (\(busID))",
                        isRemovable: removable,
                        // The boot GPU is the integrated one on a hybrid laptop.
                        // 混合顯示筆電上，開機用的 GPU 是內建的那張。
                        isLowPower: isBootVGA
                    ),
                    driver: driver,
                    busID: busID,
                    isBootVGA: isBootVGA
                )
                if isBootVGA {
                    cards.insert(card, at: 0)
                } else {
                    cards.append(card)
                }
            }
            // Low power means the integrated half of a hybrid machine: the boot GPU
            // when there is another one. A desktop with one discrete card has none.
            // 低功耗指的是混合顯示機器上內建的那一半：有另一張卡時，開機用的那張。只有一張獨顯的桌機沒有低功耗卡。
            if cards.count < 2, let only = cards.first {
                cards[0].adapter = GraphicsAdapter(
                    name: only.adapter.name,
                    isRemovable: only.adapter.isRemovable,
                    isLowPower: false
                )
            }
            return cards
        }

        /// The `DRI_PRIME` value Mesa takes for a PCI bus ID: 0000:03:00.0 is
        /// spelled pci-0000_03_00_0.
        /// Mesa 接受的 PCI 匯流排位址 `DRI_PRIME` 值:0000:03:00.0 寫作 pci-0000_03_00_0。
        static func primeName(busID: String) -> String {
            "pci-" + busID.replacingOccurrences(of: ":", with: "_")
                .replacingOccurrences(of: ".", with: "_")
        }
    #endif
}
/// What fires ``GtkBackend/adapterRemoved``: the adapter GTK renders on, by a
/// key its platform keeps stable, compared with the adapters listed again each
/// time the platform says the set may have changed (gtk_adapter_watch.c, and
/// Metal's device observer on macOS, as AppKitBackend uses).
///
/// The adapter in use is the one each platform's GL puts this process on:
/// - Windows: the first adapter DXGI orders for this executable's
///   UserGpuPreferences value -- the policy `applyAdapter` writes and the one
///   Windows applies to an OpenGL process.
/// - WSL: the DXCore adapter Mesa's d3d12 driver picks, the first whose name
///   contains `MESA_D3D12_DEFAULT_ADAPTER_NAME` (ignoring case), otherwise the
///   first listed.
/// - Linux: the DRM card `DRI_PRIME` names, otherwise the boot GPU; nothing under
///   `LIBGL_ALWAYS_SOFTWARE`, where no GPU can go away.
/// - macOS: Metal's system default device, which GDK's OpenGL context runs on.
///
/// GL context loss is not the signal, because GTK cannot report it: GDK 4's
/// public GdkGLContext API (gdkglcontext.h, 4.24.1) has no way to ask for a
/// context with reset notification, and without one KHR_robustness's
/// glGetGraphicsResetStatus always answers GL_NO_ERROR.
///
/// 觸發 ``GtkBackend/adapterRemoved`` 的機制:GTK 繪製所用的介面卡，以平台保持穩定的鍵值表示，每當平台表示
/// 「集合可能變了」就與重新列出的介面卡比對(gtk_adapter_watch.c;macOS 上則用 Metal 的裝置 observer,與
/// AppKitBackend 相同)。
///
/// 使用中的介面卡，就是各平台的 GL 把本行程放上去的那一張:
/// - Windows:DXGI 依本執行檔 UserGpuPreferences 值排出的第一張——即 `applyAdapter` 寫入、Windows 套用在 OpenGL
///   行程上的政策。
/// - WSL:Mesa 的 d3d12 驅動所挑的 DXCore 介面卡，即名稱包含 `MESA_D3D12_DEFAULT_ADAPTER_NAME`(不分大小寫)的第一張，
///   否則是清單第一張。
/// - Linux:`DRI_PRIME` 指名的 DRM 卡，否則是開機用的 GPU;`LIBGL_ALWAYS_SOFTWARE` 下沒有，因為沒有 GPU 會消失。
/// - macOS:Metal 的系統預設裝置,GDK 的 OpenGL context 就跑在它上面。
///
/// 不以 GL context 遺失作為訊號，因為 GTK 無法回報它:GDK 4 公開的 GdkGLContext API(gdkglcontext.h,4.24.1)沒有任何
/// 方式要求帶 reset 通知的 context,而沒有它時 KHR_robustness 的 glGetGraphicsResetStatus 永遠回答 GL_NO_ERROR。
@MainActor
enum GtkAdapterRemoval {
    private static weak var backend: GtkBackend?
    private static var watch: GraphicsAdapterRemovalWatch<String>?
    #if os(macOS)
        /// Metal holds its observer weakly; this token is the owner.
        /// Metal 以弱參考持有 observer;這個 token 才是擁有者。
        private static var observer: NSObject?
    #endif

    /// Starts watching, once; later calls only change the backend told.
    /// 開始監看(只做一次);之後的呼叫只改變要通知的 backend。
    static func start(for backend: GtkBackend) {
        self.backend = backend
        guard watch == nil else { return }
        watch = GraphicsAdapterRemovalWatch(inUse: inUseAdapter())
        #if os(macOS)
            observer = MTLCopyAllDevicesWithObserver { _, _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { GtkAdapterRemoval.check() }
                }
            }.observer
        #else
            // gtk_adapter_watch.c calls back on the GTK main thread.
            // gtk_adapter_watch.c 在 GTK 主執行緒上回呼。
            _ = scui_adapter_watch_start {
                MainActor.assumeIsolated { GtkAdapterRemoval.check() }
            }
        #endif
    }

    /// Lists the adapters again and fires the handler if the one in use is gone.
    /// 重新列出介面卡；使用中的那一張不見了就觸發 handler。
    static func check() {
        guard var current = watch else { return }
        let removed = current.update(present: presentAdapters(), adopting: inUseAdapter())
        if removed {
            current.rearm(inUse: inUseAdapter())
        }
        watch = current
        if removed {
            backend?.adapterRemoved?()
        }
    }

    static func inUseAdapter() -> String? {
        #if os(Windows)
            let preference = GtkBackend.executablePath()
                .flatMap { GtkBackend.readGpuPreference(for: $0) } ?? 0
            let luid = scui_dxgi_preferred_adapter_luid(Int32(preference))
            return luid == 0 ? nil : String(luid, radix: 16)
        #elseif os(macOS)
            return MTLCreateSystemDefaultDevice().map { String($0.registryID) }
        #else
            let environment = ProcessInfo.processInfo.environment
            let identities = adapterIdentities()
            if !identities.isEmpty {
                let wanted = environment["MESA_D3D12_DEFAULT_ADAPTER_NAME"]?.lowercased() ?? ""
                let chosen =
                    identities.first { !wanted.isEmpty && $0.name.lowercased().contains(wanted) }
                    ?? identities.first
                return chosen.map { String($0.luid, radix: 16) }
            }
            if environment["LIBGL_ALWAYS_SOFTWARE"] == "1" {
                return nil
            }
            let cards = GtkBackend.drmCards()
            if let prime = environment["DRI_PRIME"], prime.hasPrefix("pci-"),
                let card = cards.first(where: { GtkBackend.primeName(busID: $0.busID) == prime })
            {
                return card.busID
            }
            return cards.first?.busID
        #endif
    }

    static func presentAdapters() -> [String] {
        #if os(Windows)
            return adapterIdentities().map { String($0.luid, radix: 16) }
        #elseif os(macOS)
            return MTLCopyAllDevices().map { String($0.registryID) }
        #else
            let identities = adapterIdentities()
            if !identities.isEmpty {
                return identities.map { String($0.luid, radix: 16) }
            }
            return GtkBackend.drmCards().map(\.busID)
        #endif
    }

    #if !os(macOS)
        static func adapterIdentities() -> [(luid: UInt64, name: String)] {
            var entries = [scui_adapter_identity](repeating: scui_adapter_identity(), count: 16)
            let count = Int(scui_adapter_identities(&entries, Int32(entries.count)))
            return entries.prefix(count).map { entry in
                let name = withUnsafeBytes(of: entry.name) { raw in
                    String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
                }
                return (luid: UInt64(entry.luid), name: name)
            }
        }
    #endif
}
