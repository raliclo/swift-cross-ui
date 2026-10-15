import Foundation

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
            // the GPUs exist whichever toolkit draws the window. Until 2026-10-16 this
            // branch was the Linux one and P68 read "adapters: 0" on a Mac with one.
            // 與 AppKitBackend 回報的是同一份清單，取自 Metal,系統預設排第一：不論由哪個工具組繪製視窗，
            // GPU 都在那裡。2026-10-16 之前這裡走的是 Linux 分支,P68 在有一張卡的 Mac 上顯示 adapters: 0。
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
            return Self.drmCards().map(\.adapter)
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
                // 0000:03:00.0 is spelled pci-0000_03_00_0. / 0000:03:00.0 寫作 pci-0000_03_00_0。
                let prime = "pci-" + card.busID.replacingOccurrences(of: ":", with: "_")
                    .replacingOccurrences(of: ".", with: "_")
                setenv("DRI_PRIME", prime, 1)
            }
            return .applied
        #endif
    }

    #if !os(Windows) && !os(macOS)
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
        static func drmCards() -> [DRMCard] {
            let root = "/sys/class/drm"
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
    #endif
}
