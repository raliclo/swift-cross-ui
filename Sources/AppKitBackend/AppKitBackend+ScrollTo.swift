import AppKit
@_spi(Backends) import SwiftCrossUI

extension AppKitBackend {
    /// Scrolls a container so that one of its descendants is visible.
    ///
    /// `NSView.scrollToVisible(_:)` does the search and the arithmetic, and it
    /// takes the shortest scroll that brings the rectangle into view -- which is
    /// what `anchor: nil` means in SwiftUI. An explicit anchor asks for a
    /// position rather than mere visibility, so that case converts the child's
    /// frame into the document's coordinates and scrolls the clip view there
    /// directly.
    ///
    /// `reflectScrolledClipView(_:)` after the manual path, without which the
    /// scroll bars keep drawing the old position: the content moves and the
    /// indicator does not, which reads as a rendering glitch rather than as a
    /// missing call.
    ///
    /// 捲動某個容器,使它的某個子孫可見。
    ///
    /// `NSView.scrollToVisible(_:)` 會完成搜尋與算術,而且它採取的是「讓該矩形進入視野的最短捲動」
    /// ——那正是 SwiftUI 中 `anchor: nil` 的意思。明確給定 anchor 則是在要求一個**位置**而不只是可見,
    /// 因此該情況會把子元件的框架換算到 document 的座標系中,並直接把 clip view 捲到那裡。
    ///
    /// 手動路徑之後要呼叫 `reflectScrolledClipView(_:)`,少了它捲軸會繼續畫在舊位置上:內容動了而
    /// 指示器沒動,那讀起來像是繪製上的毛病,而不像少呼叫了一個方法。
    public func scrollContainer(
        _ scrollView: Widget,
        to child: Widget,
        anchor: UnitPoint?
    ) {
        guard let container = scrollView as? NSScrollView,
            child.isDescendant(of: container)
        else { return }

        guard let anchor, let document = container.documentView else {
            child.scrollToVisible(child.bounds)
            return
        }

        let frame = child.convert(child.bounds, to: document)
        let clip = container.contentView.bounds.size
        let target = NSPoint(
            x: frame.minX - (clip.width - frame.width) * CGFloat(anchor.x),
            y: frame.minY - (clip.height - frame.height) * CGFloat(anchor.y)
        )
        container.contentView.scroll(to: target)
        container.reflectScrolledClipView(container.contentView)
    }
}
