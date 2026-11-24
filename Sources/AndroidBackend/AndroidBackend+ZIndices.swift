import AndroidKit
import SwiftCrossUI

extension AndroidBackend {
    /// The drawing order last handed to each container, so that the common
    /// case -- no `zIndex`, and none before -- costs no JNI call.
    /// 上一次交給每個容器的繪製順序，讓常見情況(沒有 `zIndex`,之前也沒有)不必呼叫 JNI。
    @MainActor static let drawingOrders = LastSet<[Int]>()
}

// zIndex: `CustomContainer` turns on `isChildrenDrawingOrderEnabled` and answers
// `getChildDrawingOrder` from the order, which Android uses for drawing and for
// the order touches are offered in; the children keep their indices, so
// `addView`/`getChildAt` still mean what the layout system says.
// zIndex:`CustomContainer` 開啟 `isChildrenDrawingOrderEnabled`,並以此順序回答 `getChildDrawingOrder`,
// Android 用它決定繪製順序以及觸控交給子元件的順序;子元件保留它們的索引，所以 `addView`/`getChildAt` 仍是
// 版面系統所說的意思。
extension AndroidBackend: BackendFeatures.ZIndices {
    public func setDrawingOrder(ofChildrenIn container: Widget, to order: [Int]?) {
        let last = Self.drawingOrders.value(for: container)
        guard order != last else { return }
        guard let custom = container.as(CustomContainer.self) else { return }
        if let order {
            Self.drawingOrders.set(order, for: container)
        } else {
            Self.drawingOrders.forget(container)
        }
        custom.setDrawingOrder((order ?? []).map { Int32($0) })
    }
}
