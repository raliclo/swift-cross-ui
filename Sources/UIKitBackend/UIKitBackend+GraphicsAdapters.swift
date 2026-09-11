import Metal
import SwiftCrossUI
import UIKit

extension UIKitBackend: BackendFeatures.GraphicsAdapters {
    /// The one Metal device an iOS device has.
    ///
    /// **`MTLCopyAllDevices()` is macOS-only**, and that is not an oversight in
    /// the SDK: an iPhone or iPad has exactly one GPU, it is not removable, and
    /// nothing can be plugged in beside it. So the list has one entry and the
    /// `isRemovable` flag is false rather than unknown.
    ///
    /// `isLowPower` is false for the same kind of reason: the flag means
    /// "integrated, and chosen to save power over a discrete one", and there is
    /// no discrete one to be chosen over.
    ///
    /// 一台 iOS 裝置所擁有的那一個 Metal 裝置。
    ///
    /// **`MTLCopyAllDevices()` 僅限 macOS**，而那並不是 SDK 的疏漏:一支 iPhone 或一台 iPad 恰好只有
    /// 一張 GPU、它不可移除，也沒有任何東西能插在它旁邊。因此這份清單只有一項，而 `isRemovable` 是
    /// false，不是「未知」。
    ///
    /// `isLowPower` 為 false 的理由是同一類的:那個旗標的意思是「內顯，且是為了省電而被選中、而非
    /// 選用獨顯」，而此處根本沒有獨顯可以被拿來相比。
    public var availableAdapters: [GraphicsAdapter] {
        guard let device = MTLCreateSystemDefaultDevice() else { return [] }
        return [
            GraphicsAdapter(name: device.name, isRemovable: false, isLowPower: false)
        ]
    }

    /// Records the device, and changes nothing about how the window is drawn.
    ///
    /// The AppKit half explains the distinction at length and it holds here more
    /// strongly: with one GPU, every selection but `.software` resolves to the
    /// same device, so an implementation that claimed to switch would be right
    /// by accident on every machine it ever ran on.
    ///
    /// 記下那個裝置，而不改變視窗的繪製方式。
    ///
    /// AppKit 那一半詳細說明了這項區別，而它在此處更強:只有一張 GPU 時，除了 `.software` 之外的
    /// 每一種選擇都會解析到同一個裝置——因此一個「宣稱自己切換了」的實作，在它所曾執行過的每一台
    /// 機器上都會**碰巧**是對的。
    public func applyAdapter(
        _ resolution: GraphicsAdapterResolution
    ) -> BackendFeatures.AdapterOutcome {
        guard resolution.adapter != nil else {
            let hadDevice = metalDevice != nil
            metalDevice = nil
            return hadDevice ? .applied : .alreadyActive
        }
        if metalDevice != nil { return .alreadyActive }
        metalDevice = MTLCreateSystemDefaultDevice()
        return .applied
    }

    /// Never fires: nothing can be unplugged.
    /// 永遠不會觸發:沒有任何東西可以被拔掉。
    public var adapterRemoved: (() -> Void)? {
        get { nil }
        set {}
    }
}
