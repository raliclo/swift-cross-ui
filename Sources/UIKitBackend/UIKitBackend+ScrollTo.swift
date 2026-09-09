@_spi(Backends) import SwiftCrossUI
import UIKit

extension UIKitBackend {
    /// Scrolls a container so that one of its descendants is visible.
    ///
    /// `scrollRectToVisible(_:animated:)` takes the shortest scroll that brings
    /// the rectangle into view, which is what `anchor: nil` asks for. An
    /// explicit anchor asks for a position instead, so that path converts the
    /// child's frame into the scroll view's coordinates and sets the offset.
    ///
    /// The offset is clamped. A UIScrollView will accept an offset past its
    /// content and then rubber-band back, which looks like the scroll
    /// overshooting and settling rather than like a value that was out of range.
    ///
    /// 捲動某個容器,使它的某個子孫可見。
    ///
    /// `scrollRectToVisible(_:animated:)` 採取的是「讓該矩形進入視野的最短捲動」,那正是
    /// `anchor: nil` 所要求的。明確給定 anchor 則是在要求一個**位置**,因此該路徑會把子元件的框架
    /// 換算到捲動視圖的座標系中,並直接設定 offset。
    ///
    /// 該 offset 會被夾限。UIScrollView 會接受一個超出其內容的 offset,然後彈回來,那看起來像是
    /// 捲動衝過頭再穩定下來,而不像一個超出範圍的值。
    public func scrollContainer(
        _ scrollView: Widget,
        to child: Widget,
        anchor: UnitPoint?
    ) {
        guard let widget = scrollView as? ScrollWidget else { return }
        let container = widget.scrollView
        guard child.view.isDescendant(of: container) else { return }

        let frame = child.view.convert(child.view.bounds, to: container)

        guard let anchor else {
            container.scrollRectToVisible(frame, animated: false)
            return
        }

        let visible = container.bounds.size
        let content = container.contentSize
        let target = CGPoint(
            x: min(
                max(0, frame.minX - (visible.width - frame.width) * CGFloat(anchor.x)),
                max(0, content.width - visible.width)
            ),
            y: min(
                max(0, frame.minY - (visible.height - frame.height) * CGFloat(anchor.y)),
                max(0, content.height - visible.height)
            )
        )
        container.setContentOffset(target, animated: false)
    }
}
