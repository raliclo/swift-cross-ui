@_spi(Backends) import SwiftCrossUI
import UIKit

/// Scroll offsets by key-value observing `contentOffset`, which UIScrollView
/// changes for a drag, a fling's deceleration, a bounce and
/// `setContentOffset(_:animated:)` alike. KVO rather than the delegate so
/// nothing else that wants the delegate has to share it.
///
/// The raw offset is reported. With a content inset it starts negative, and a
/// view's place in the viewport is still its content position minus it,
/// because the viewport is the scroll view's bounds.
///
/// 以 key-value observing 觀察 `contentOffset` 取得捲動位移;拖曳、甩動後的減速、回彈與
/// `setContentOffset(_:animated:)` 都會改變它。用 KVO 而不是 delegate,讓其他需要 delegate 的東西不必共用。
/// 回報的是原始位移：有 content inset 時它從負值開始，而 view 在視口中的位置仍是其內容位置減去它，因為
/// 視口就是捲動視圖的 bounds。
extension UIKitBackend: BackendFeatures.ScrollOffsetReporting {
    public func contentOffset(ofScrollContainer scrollView: Widget) -> SIMD2<Double> {
        guard let widget = scrollView as? ScrollWidget else { return .zero }
        let offset = widget.scrollView.contentOffset
        return SIMD2(Double(offset.x), Double(offset.y))
    }

    public func setContentOffsetHandler(
        ofScrollContainer scrollView: Widget,
        to handler: (@MainActor (SIMD2<Double>) -> Void)?
    ) {
        guard let widget = scrollView as? ScrollWidget else { return }
        widget.offsetHandler = handler
        guard handler != nil else {
            widget.offsetObservation = nil
            return
        }
        guard widget.offsetObservation == nil else { return }
        widget.offsetObservation = widget.scrollView.observe(\.contentOffset, options: [.new]) {
            [weak widget] view, _ in
            MainActor.assumeIsolated {
                let offset = view.contentOffset
                widget?.offsetHandler?(SIMD2(Double(offset.x), Double(offset.y)))
            }
        }
    }
}
