import AppKit
import Metal
import SwiftCrossUI

extension AppKitBackend: BackendFeatures.GraphicsAdapters {
    /// The Metal devices this machine has, system default first.
    ///
    /// **The three fields of ``SwiftCrossUI/GraphicsAdapter`` are the three
    /// properties of an `MTLDevice`** -- `name`, `isRemovable`, `isLowPower` --
    /// which is why this half needs no translation at all. The type was designed
    /// with Metal in the room.
    ///
    /// System default first because `GraphicsAdapterSelection.systemDefault`
    /// resolves to `adapters.first`, and "the first device Metal happens to
    /// enumerate" is not the same thing as "the one the system would choose".
    ///
    /// 這台機器上的 Metal 裝置，系統預設排在最前面。
    ///
    /// **``SwiftCrossUI/GraphicsAdapter`` 的三個欄位，就是 `MTLDevice` 的三個屬性**——`name`、
    /// `isRemovable`、`isLowPower`——這正是這一半完全不需要轉譯的原因。那個型別在設計時，Metal 就在
    /// 場上。
    ///
    /// 系統預設排最前面，是因為 `GraphicsAdapterSelection.systemDefault` 解析為 `adapters.first`;
    /// 而「Metal 恰好第一個列舉到的裝置」與「系統會選的那一個」並不是同一件事。
    public var availableAdapters: [GraphicsAdapter] {
        let devices = MTLCopyAllDevices()
        let systemDefault = MTLCreateSystemDefaultDevice()
        let ordered =
            devices.sorted { first, _ in
                first.registryID == systemDefault?.registryID
            }
        return ordered.map { device in
            GraphicsAdapter(
                name: device.name,
                isRemovable: device.isRemovable,
                isLowPower: device.isLowPower
            )
        }
    }

    /// Records the chosen device, and says plainly what that does and does not
    /// change.
    ///
    /// **It does NOT move the window to another GPU, and no application on macOS
    /// can.** The window server composites a window on the GPU driving the
    /// display the window is on; an app chooses a device for the work IT does,
    /// not for its window. Windows is different -- `WinUIBackend` writes a
    /// registry value and the process has to restart -- and the protocol already
    /// carries that difference in ``AdapterOutcome/requiresRestart``, whose own
    /// documentation says "macOS does not need this, Metal chooses at runtime".
    ///
    /// So the outcome here is `applied` or `alreadyActive`, never
    /// `requiresRestart`, and the thing that was applied is the device this
    /// backend will use for Metal work. Reporting `applied` while pretending the
    /// window moved would be the kind of true-looking answer this tree keeps
    /// catching.
    ///
    /// 記下所選的裝置，並明白說出那件事改變了什麼、沒改變什麼。
    ///
    /// **它**不會**把視窗移到另一張 GPU 上，而在 macOS 上沒有任何應用程式做得到。** 視窗由
    /// window server 在「驅動該視窗所在顯示器的那張 GPU」上合成;一個 app 選的是**它自己**要做的
    /// 工作用哪一張，而不是它的視窗用哪一張。Windows 不同——`WinUIBackend` 會寫入一個登錄檔值、
    /// 且行程必須重啟——而這項差異協定本身早已帶著:見 ``AdapterOutcome/requiresRestart``，其文件
    /// 就寫著「macOS 不需要這個，Metal 在執行期選擇」。
    ///
    /// 因此此處的結果是 `applied` 或 `alreadyActive`，永遠不會是 `requiresRestart`;而被套用的
    /// 東西，是「這個 backend 之後要用來做 Metal 工作的那個裝置」。若回報 `applied` 並讓人以為視窗
    /// 換了 GPU，那正是這棵樹一再抓到的那種「看起來為真」的答案。
    public func applyAdapter(_ resolution: GraphicsAdapterResolution) -> BackendFeatures.AdapterOutcome {
        guard let wanted = resolution.adapter else {
            // Software was asked for, or nothing resolved. There is no software
            // path to switch to: AppKit draws through Core Graphics and the
            // window server composites, both of which use whatever the system
            // gives them. The device is cleared so no Metal work picks one up.
            // 要求的是軟體算繪，或什麼都沒有解析出來。此處沒有可切換過去的軟體路徑:AppKit 透過
            // Core Graphics 繪製、由 window server 合成，兩者都使用系統給它們的東西。此處清空該
            // 裝置，好讓任何 Metal 工作都不會撿到一個。
            let hadDevice = metalDevice != nil
            metalDevice = nil
            return hadDevice ? .applied : .alreadyActive
        }

        let device = MTLCopyAllDevices().first { $0.name == wanted.name }
        if let current = metalDevice, current.name == device?.name {
            return .alreadyActive
        }
        metalDevice = device
        return device == nil ? .alreadyActive : .applied
    }

    /// Fires when a removable GPU is unplugged.
    ///
    /// `MTLCopyAllDevicesWithObserver` is the only public way to hear about it;
    /// there is no notification on `NotificationCenter` for device removal.
    /// The observer must be KEPT, or the callbacks stop -- Metal holds it weakly
    /// and hands back a token that is the owner.
    ///
    /// 當一張可移除的 GPU 被拔掉時觸發。
    ///
    /// `MTLCopyAllDevicesWithObserver` 是唯一能得知此事的公開方式;`NotificationCenter` 上並沒有
    /// 裝置移除的通知。那個 observer **必須被保留住**，否則回呼就會停止——Metal 以弱參考持有它，並
    /// 交回一個「本身就是擁有者」的 token。
    public var adapterRemoved: (() -> Void)? {
        get { adapterRemovedHandler }
        set {
            adapterRemovedHandler = newValue
            guard newValue != nil, metalDeviceObserver == nil else { return }
            var observer: NSObjectProtocol?
            _ = MTLCopyAllDevicesWithObserver(handler: { _, notification in
                guard notification == .wasRemoved else { return }
                MainActor.assumeIsolated {
                    AppKitBackend.currentAdapterRemovedHandler?()
                }
            })
            metalDeviceObserver = observer
        }
    }
}
