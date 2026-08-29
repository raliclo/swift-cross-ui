import Foundation

@_spi(Backends) import SwiftCrossUI

#if os(Windows)
    import WinSDK
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
        #else
            // Not implemented on Linux. Returning nothing is honest -- the
            // shared resolution then falls back and says why -- whereas
            // inventing a single unnamed adapter would report a choice that
            // was never made. Selecting on Linux is DRI_PRIME or
            // __NV_PRIME_RENDER_OFFLOAD, set before GL initialises, and needs
            // no restart; see testapp/plan/plan-gpu-selection.md.
            // 在 Linux 上尚未實作。回傳空集合才是誠實的——共用的解析邏輯會據此退路並說明原因——
            // 而憑空捏造一張無名介面卡，等於回報一個從未做過的選擇。Linux 上的選擇方式是
            // DRI_PRIME 或 __NV_PRIME_RENDER_OFFLOAD，於 GL 初始化前設定，且不需要重新啟動；
            // 詳見 testapp/plan/plan-gpu-selection.md。
            return []
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
        #else
            return .unavailable(
                reason: """
                    Adapter selection is not implemented for GtkBackend on this platform. On \
                    Linux it would be DRI_PRIME or __NV_PRIME_RENDER_OFFLOAD, set before GL \
                    initialises, which needs no restart.
                    """
            )
        #endif
    }
}
