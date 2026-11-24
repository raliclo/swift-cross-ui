import CWinRT
import Mutex
@_spi(Backends) import SwiftCrossUI
@_spi(WinRTInternal) import WinUI

/// The containers whose children have been given a `Canvas.ZIndex`, keyed by
/// the ABI pointer (a projected object's Swift wrapper is not stable). Only
/// those need resetting when the order goes back to `nil`, which keeps the
/// common case free of COM calls. A key reused by a new container costs one
/// harmless reset to zero.
///
/// 子元件曾被設定 `Canvas.ZIndex` 的容器，以 ABI 指標為鍵(投影物件的 Swift 包裝並不穩定)。順序回到 `nil`
/// 時只有它們需要重設，這讓常見情況不必呼叫任何 COM。新容器重用到同一個鍵，代價只是一次無害的歸零。
private let zIndexedContainers = Mutex<Set<UInt>>([])

private func winUIZIndexKey(_ widget: WinUI.FrameworkElement) -> UInt {
    let pointer: UnsafeMutablePointer<__x_ABI_CMicrosoft_CUI_CXaml_CIFrameworkElement>? =
        widget._getABI()
    return UInt(bitPattern: pointer)
}

// zIndex: each child's `Canvas.ZIndex` is its rank in the drawing order. XAML
// draws and hit-tests a panel's children by ZIndex, then by index, and the
// collection keeps declaration order, so indices still mean what the layout
// system says.
// zIndex:每個子元件的 `Canvas.ZIndex` 是它在繪製順序中的名次。XAML 依 ZIndex、再依索引繪製面板的子元件
// 並做 hit test,而集合維持宣告順序，所以索引仍是版面系統所說的意思。
extension WinUIBackend: BackendFeatures.ZIndices {
    public func setDrawingOrder(ofChildrenIn container: Widget, to order: [Int]?) {
        guard let canvas = container as? Canvas else { return }
        let key = winUIZIndexKey(canvas)
        let count = Int(canvas.children.size)
        guard let order, order.count == count else {
            guard zIndexedContainers.withLock({ $0.remove(key) != nil }) else { return }
            for index in 0..<count {
                if let child = canvas.children.getAt(UInt32(index)) {
                    try? Canvas.setZIndex(child, 0)
                }
            }
            return
        }
        zIndexedContainers.withLock { _ = $0.insert(key) }
        for (rank, index) in order.enumerated() {
            if let child = canvas.children.getAt(UInt32(index)) {
                try? Canvas.setZIndex(child, Int32(rank))
            }
        }
    }
}
