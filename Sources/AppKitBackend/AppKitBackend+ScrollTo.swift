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

        guard let anchor, container.documentView != nil else {
            child.scrollToVisible(child.bounds)
            return
        }

        // In the CLIP view's bounds coordinates, which is what `scroll(to:)`
        // takes. The document's own coordinates are not the clip's: the
        // document (a non-flipped NSStackView) sits at y -700 in a 300-point
        // clip when its content is 1000 tall, its top pinned to the clip's
        // top. With document coordinates P101's scrollTo(3, anchor: .center)
        // scrolled to y 675, past the content, and showed an empty scroll view.
        // The anchor's y counts from the top, so a non-flipped
        // clip places the child's top edge (maxY) rather than its minY.
        // 使用 **clip view** 的 bounds 座標，那正是 `scroll(to:)` 所接受的。文件自己的座標不是 clip 的:
        // 內容 1000 高時，文件(未 flipped 的 NSStackView)位於 300 點高 clip 的 y -700,頂端由 constraint
        // 釘在 clip 頂端;用文件座標時,P101 的 scrollTo(3, anchor: .center) 捲到 y 675,超出內容，畫面上是
        // 一個空的捲動視圖。anchor 的 y 從頂端算起，所以未 flipped 的 clip 對齊的是子元件的上緣
        // (maxY)而非 minY。
        let clipView = container.contentView
        let frame = child.convert(child.bounds, to: clipView)
        let clip = clipView.bounds.size
        let slackX = (clip.width - frame.width) * CGFloat(anchor.x)
        let slackY = (clip.height - frame.height) * CGFloat(anchor.y)
        let target = NSPoint(
            x: frame.minX - slackX,
            y: clipView.isFlipped
                ? frame.minY - slackY
                : frame.maxY + slackY - clip.height
        )
        let constrained = clipView.constrainBoundsRect(NSRect(origin: target, size: clip)).origin
        clipView.scroll(to: constrained)
        container.reflectScrolledClipView(clipView)
    }
}
