import Foundation
import WinSDK
import WinUIInterop

@_spi(Backends) import SwiftCrossUI

/// WinUIBackend's half of adapter selection: what exists, and how to select it.
///
/// The rules -- the numbering, the fallback chain, what to report -- are in
/// ``GraphicsAdapterSelection`` and are not repeated here.
///
/// WinUIBackend 在介面卡選擇上所負責的那一半：有哪些介面卡，以及如何選定。
///
/// 規則本身——編號方式、退路鏈、該回報什麼——位於 ``GraphicsAdapterSelection``，此處不重複。
///
/// **Verified at runtime 2026-09-04**, in a real terminal:
///
///     ./P5-WinUI.exe -GPU 2
///     -GPU 2: already using AMD Radeon(TM) Graphics (fell back: no external adapter is attached)
///
/// The adapter name proves the DXGI enumeration below runs end to end; the name
/// being a real card rather than WARP proves the software filter works; and the
/// fallback clause is the part that matters most -- "already using X" on its own
/// reads as success while quietly not being the card that was asked for.
///
/// `Console.swift` leaves a redirected stdout or stderr alone (see
/// `attachToParentConsole()`), so a run through a pipe is not discarded. The
/// 2026-09-04 check above was made in a terminal because, at the time, a
/// redirected run showed nothing whether this worked or not -- a check that
/// cannot fail, so it cannot pass.
///
/// **2026-09-04 於真實終端機中完成執行期驗證**：
///
///     ./P5-WinUI.exe -GPU 2
///     -GPU 2: already using AMD Radeon(TM) Graphics (fell back: no external adapter is attached)
///
/// 印出介面卡名稱，證明下方的 DXGI 列舉從頭到尾都能運作；名稱是一張真卡而非 WARP，證明軟體 renderer
/// 的濾除有效；而**退路子句才是最要緊的那一項**——單獨的「already using X」讀起來像成功，實際上卻
/// 悄悄地不是被要求的那張卡。
///
/// `Console.swift` 不會去動已被重導的 stdout 或 stderr(見 `attachToParentConsole()`),所以透過管線的執行
/// 不會被丟棄；上面那次 2026-09-04 的檢查在終端機中進行，是因為當時被重導的執行無論成功與否都看不到東西。
/// **那樣的檢查無法失敗，因此也無法通過。**
extension WinUIBackend: BackendFeatures.GraphicsAdapters {
    /// Every adapter DXGI reports, in DXGI's own order.
    ///
    /// `EnumAdapters1` returns index 0 first and that is the adapter DXGI would
    /// choose on its own, which is exactly what
    /// ``GraphicsAdapterSelection/systemDefault`` takes -- so the platform order
    /// is kept rather than sorted. `GtkBackend` has to reorder because
    /// `EnumDisplayDevicesW` does not promise the primary first; DXGI does.
    ///
    /// The software renderer is filtered out by name. WARP appears in this list
    /// as a real adapter, and leaving it in would let `-GPU 2` "succeed" onto a
    /// CPU renderer while reporting a card -- the precise failure
    /// ``GraphicsAdapterResolution`` exists to make visible.
    ///
    /// DXGI 所回報的每一張介面卡，依 DXGI 自身的順序。
    ///
    /// `EnumAdapters1` 先回傳 index 0，而那正是 DXGI 自己會選的那一張，也正是
    /// ``GraphicsAdapterSelection/systemDefault`` 所取的——因此保留平台順序，而不重新排序。
    /// `GtkBackend` 必須重排，是因為 `EnumDisplayDevicesW` 並不保證主要介面卡排在最前；DXGI 保證。
    ///
    /// 軟體 renderer 依名稱濾除。WARP 在此清單中會以一張真實介面卡的身分出現，若把它留下，
    /// `-GPU 2` 就會「成功」落到一個 CPU renderer 上、卻回報了一張顯示卡——那正是
    /// ``GraphicsAdapterResolution`` 存在所要讓人看見的失敗。
    public var availableAdapters: [GraphicsAdapter] {
        var factoryIID = D3D11IID.IDXGIFactory1
        var factoryRaw: UnsafeMutableRawPointer?
        guard CreateDXGIFactory1(&factoryIID, &factoryRaw) >= 0, let factoryRaw else {
            return []
        }
        let factory = factoryRaw.assumingMemoryBound(to: IDXGIFactory1.self)
        defer { _ = factory.pointee.lpVtbl.pointee.Release(factory) }

        var adapters: [GraphicsAdapter] = []
        var index: UINT = 0
        while true {
            var adapter: UnsafeMutablePointer<IDXGIAdapter1>?
            guard factory.pointee.lpVtbl.pointee.EnumAdapters1(factory, index, &adapter) >= 0,
                let adapter
            else { break }
            defer { _ = adapter.pointee.lpVtbl.pointee.Release(adapter) }
            index += 1

            var description = DXGI_ADAPTER_DESC1()
            guard adapter.pointee.lpVtbl.pointee.GetDesc1(adapter, &description) >= 0 else {
                continue
            }
            let name = withUnsafeBytes(of: description.Description) { raw -> String in
                guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt16.self) else {
                    return ""
                }
                return String(decodingCString: base, as: UTF16.self)
            }
            // DXGI_ADAPTER_FLAG_SOFTWARE is 2. Spelled out because Swift imports
            // values and not macros, the same reason GtkBackend spells out its
            // wingdi.h flags.
            // DXGI_ADAPTER_FLAG_SOFTWARE 為 2。之所以寫成字面值，是因為 Swift 匯入的是值而非
            // 巨集——與 GtkBackend 寫明其 wingdi.h 旗標的理由相同。
            let isSoftware = description.Flags & 2 != 0
            guard !name.isEmpty, !isSoftware, !name.hasPrefix("Microsoft Basic") else { continue }

            // Integrated parts share system memory, so a dedicated budget of
            // zero is what distinguishes them. Reported rather than guessed from
            // the name: vendor strings change and "Intel" is no longer a
            // synonym for integrated.
            // 內顯共用系統記憶體，因此「專屬記憶體為 0」正是區分它們的依據。這是**回報**而非從名稱
            // 猜測：廠商字串會變，而「Intel」早已不等同於內顯。
            adapters.append(
                GraphicsAdapter(
                    name: name,
                    isRemovable: false,
                    isLowPower: description.DedicatedVideoMemory == 0
                )
            )
        }
        return adapters
    }

    /// Reports what WinUI can and cannot do with a request, without pretending.
    ///
    /// **WinUI's XAML compositor owns its D3D device and does not expose a way
    /// to place it on a chosen adapter.** That is a checked claim, not one made
    /// from memory: `Microsoft.UI.Composition` has no adapter or device
    /// parameter, `Application` has no render-device hook, and the one place
    /// this backend does pick a card -- `D3D11VideoInterop.selectAdapter` --
    /// works because the app creates that device itself for content it draws
    /// into a swap chain panel. Selection is available for app-owned surfaces
    /// and not for the compositor.
    ///
    /// So the honest answers are: software is `.unavailable` because the
    /// compositor will use the GPU regardless of what this returns, and a named
    /// external card is `.unavailable` with the reason spelled out. Neither is
    /// a stub. The protocol's own documentation prescribes exactly this shape
    /// for a backend that can see adapters but not choose one, and returning
    /// `.applied` for a request that changed nothing would be the failure the
    /// whole feature exists to prevent.
    ///
    /// 如實回報 WinUI 對某項要求做得到什麼、做不到什麼，不加掩飾。
    ///
    /// **WinUI 的 XAML compositor 擁有自己的 D3D device，且未提供任何將它放到指定介面卡上的方式。**
    /// 這是查證過的主張，不是憑印象所寫：`Microsoft.UI.Composition` 沒有 adapter 或 device 參數、
    /// `Application` 沒有 render-device 掛勾，而本 backend 唯一真的會挑卡的地方——
    /// `D3D11VideoInterop.selectAdapter`——之所以可行，是因為那個 device 是 app 為「自己畫進 swap
    /// chain panel 的內容」所建立的。**選擇能力存在於 app 自有的繪製表面，而不存在於 compositor。**
    ///
    /// 因此誠實的答案是：軟體繪製回 `.unavailable`，因為無論此處回傳什麼，compositor 都會使用
    /// GPU；而指名的外接卡同樣回 `.unavailable`，並寫明理由。兩者都不是敷衍的 stub。協定自身的
    /// 文件正是為「看得到介面卡、卻無法選擇」的 backend 規定了這個形狀；而對一個什麼都沒改變的
    /// 要求回傳 `.applied`，才會是整個功能所要防止的那種失敗。
    public func applyAdapter(
        _ resolution: GraphicsAdapterResolution
    ) -> BackendFeatures.AdapterOutcome {
        switch resolution.resolved {
            case .software:
                return .unavailable(
                    reason: """
                        WinUI composes through its own D3D device and renders on the GPU whatever \
                        this backend does, so software rendering cannot be selected. GtkBackend \
                        honours -GPU 0 by not requesting Direct Composition.
                        """
                )
            case .systemDefault:
                // Nothing to do, and it is genuinely already true: the request
                // is for whatever DXGI would pick, which is what the compositor
                // took at startup. `alreadyActive` rather than `applied`,
                // because nothing was changed.
                // 無須任何動作，而且它確實已經成立：這個要求就是「DXGI 自己會挑的那一張」，而那正是
                // compositor 啟動時所取得的。回 `alreadyActive` 而非 `applied`，因為沒有任何東西
                // 被改變。
                return .alreadyActive
            case .external(let ordinal):
                let name = resolution.adapter?.name ?? "external adapter \(ordinal)"
                return .unavailable(
                    reason: """
                        WinUI's XAML compositor owns its D3D device and exposes no way to place it \
                        on a chosen adapter, so "\(name)" cannot be selected for the window's own \
                        rendering. It CAN be selected for content this app draws itself into a \
                        swap chain panel -- that path is D3D11VideoInterop.selectAdapter, which \
                        testapp/P6.swift uses.
                        """
                )
        }
    }

}
/// What fires ``WinUIBackend/adapterRemoved``: the adapter the window renders
/// on, by LUID, compared with the adapters DXGI lists each time its adapter
/// enumeration changes (adapter_watch.cpp).
///
/// The adapter in use is DXGI's first hardware adapter: the XAML compositor
/// takes the adapter DXGI would choose on its own (see `applyAdapter(_:)` above),
/// and this backend's own composition device is created with no adapter named
/// (composition_surface.cpp), which is the same one. After a removal the
/// watch moves to whichever adapter DXGI then lists first, the one the
/// compositor recreates its device on.
///
/// 觸發 ``WinUIBackend/adapterRemoved`` 的機制：視窗繪製所用的介面卡，以 LUID 表示，每當 DXGI 的介面卡列舉改變，就與
/// DXGI 重新列出的介面卡比對(adapter_watch.cpp)。
///
/// 使用中的介面卡是 DXGI 的第一張硬體介面卡:XAML compositor 取的是 DXGI 自己會選的那一張(見上方的 `applyAdapter(_:)`),
/// 本 backend 自己的 composition device 也不指定介面卡而建立(composition_surface.cpp),是同一張。移除之後，監看改為
/// DXGI 當時列在第一的介面卡，也就是 compositor 重建 device 所在的那一張。
@MainActor
enum WinUIAdapterRemoval {
    private static weak var backend: WinUIBackend?
    private static var watch: GraphicsAdapterRemovalWatch<UInt64>?

    /// Starts watching, once; later calls only change the backend told.
    /// 開始監看(只做一次);之後的呼叫只改變要通知的 backend。
    static func start(for backend: WinUIBackend) {
        self.backend = backend
        guard watch == nil else { return }
        watch = GraphicsAdapterRemovalWatch(inUse: hardwareAdapters().first)
        // adapter_watch.cpp calls back on a thread-pool thread.
        // adapter_watch.cpp 在 thread pool 執行緒上回呼。
        _ = scui_dxgi_watch_adapters {
            DispatchQueue.main.async {
                MainActor.assumeIsolated { WinUIAdapterRemoval.check() }
            }
        }
    }

    /// Lists the adapters again and fires the handler if the one in use is gone.
    /// 重新列出介面卡；使用中的那一張不見了就觸發 handler。
    static func check() {
        guard var current = watch else { return }
        let present = hardwareAdapters()
        let removed = current.update(present: present)
        if removed {
            current.rearm(inUse: present.first)
        }
        watch = current
        if removed {
            backend?.adapterRemoved?()
        }
    }

    /// The LUIDs of the hardware adapters DXGI lists, in DXGI's order.
    /// DXGI 所列硬體介面卡的 LUID,依 DXGI 的順序。
    static func hardwareAdapters() -> [UInt64] {
        var entries = [scui_dxgi_adapter_identity](
            repeating: scui_dxgi_adapter_identity(), count: 16
        )
        let count = Int(scui_dxgi_hardware_adapters(&entries, Int32(entries.count)))
        return entries.prefix(count).map(\.luid)
    }
}
