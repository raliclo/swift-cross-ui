@_spi(Backends) import SwiftCrossUI
import UIKit

extension UIKitBackend: BackendFeatures.ScrollingLists {
    /// A `UITableView` already scrolls and already recycles cells; what it
    /// lacked was a viewport to do it in.
    ///
    /// Nothing had to be re-enabled here, unlike AppKit's
    /// `NSDisabledScrollView`. `UITableView` IS a `UIScrollView` and scrolling
    /// was never switched off -- the table simply never had a frame smaller
    /// than its content, so there was nothing to scroll within.
    ///
    /// **On iOS the window is the screen, so the measurement AppKit used --
    /// does the window stop growing -- cannot fail here and proves nothing.**
    /// Two screenshots at 50 and 400 rows were both 2556 px tall and would have
    /// been 2556 px tall with this file deleted. What distinguishes a viewport
    /// from a full-height table under the root scroll view is the table's own
    /// frame against its content size, measured in-process (`-rows` varying, one
    /// binary, 2026-09-09):
    ///
    ///     rows=10     frame.h  340    content.h    440
    ///     rows=50     frame.h  382    content.h   2200
    ///     rows=400    frame.h  382    content.h  17600
    ///     rows=2000   frame.h  382    content.h  88000
    ///
    /// The content is linear in the row count, at 44 pt a row, and the frame
    /// stops at the height the layout proposed. That constant is the viewport.
    ///
    /// 一個 `UITableView` 本來就會捲動、也本來就會回收 cell;它缺的是一個可供如此運作的視口。
    ///
    /// 此處不需要重新啟用任何東西,這一點與 AppKit 的 `NSDisabledScrollView` 不同——`UITableView`
    /// **就是**一個 `UIScrollView`,捲動從未被關閉;那個 table 只是從來沒有拿到過一個小於其內容的框,
    /// 因此沒有東西可供在其中捲動。
    ///
    /// **在 iOS 上,視窗就是螢幕,因此 AppKit 所用的那個量測——視窗有沒有停止長大——在此處不可能失敗,
    /// 也因此什麼都證明不了。** 50 列與 400 列的兩張截圖都是 2556 像素高,而即使把這個檔案刪掉,
    /// 它們仍然會是 2556 像素高。真正能分辨「視口」與「一個位於根捲動視圖下的全高 table」的,是那個
    /// table 自身的框相對於它的內容尺寸,於行程內量測(僅 `-rows` 變動,同一個二進位檔,2026-09-09):
    /// 內容隨列數線性成長(每列 44 pt),而框停在版面所提議的高度。那個常數就是視口。
    public func setViewportHeight(ofSelectableListView listView: Widget, to height: Int) {
        guard let wrapper = listView as? WrapperWidget<UICustomTableView> else { return }
        var frame = wrapper.child.frame
        frame.size.height = CGFloat(height)
        wrapper.child.frame = frame
    }
}
