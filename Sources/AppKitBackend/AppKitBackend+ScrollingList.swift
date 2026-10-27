import AppKit
@_spi(Backends) import SwiftCrossUI

extension AppKitBackend: BackendFeatures.ScrollingLists {
    /// Turns the list's own scroll view back on and holds it to the viewport.
    ///
    /// `createSelectableListView` builds an `NSDisabledScrollView`, whose
    /// `scrollWheel` forwards to the next responder so an enclosing ScrollView
    /// does the scrolling. That was correct while the framework laid the table
    /// out at full content height; with a viewport it is exactly backwards, and
    /// a list that refuses the wheel inside a viewport it cannot fill is a list
    /// nobody can read past the first screen.
    ///
    /// The scroller is enabled here rather than at creation so that a backend
    /// conforming to this protocol is the only thing that changes behaviour --
    /// `createSelectableListView` is shared with the path that has no viewport.
    ///
    /// 把清單自己的捲動視圖重新開啟,並讓它維持在視口大小。
    ///
    /// `createSelectableListView` 建立的是一個 `NSDisabledScrollView`,它的 `scrollWheel` 會轉交給
    /// next responder,由外圍的 ScrollView 負責捲動。在「框架把 table 排版成完整內容高度」的前提下
    /// 那是正確的;有了視口之後它恰好反了,而一個「在自己填不滿的視口裡拒絕滾輪」的清單,
    /// 是一個沒有人讀得過第一頁的清單。
    ///
    /// 在此處而非建立時啟用捲軸,是為了讓「有實作本協定」成為唯一改變行為的因素——
    /// `createSelectableListView` 與那條沒有視口的路徑是共用的。
    public func setViewportHeight(ofSelectableListView listView: Widget, to height: Int) {
        guard let scrollView = listView as? NSDisabledScrollView else { return }
        scrollView.ownsScrolling = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .allowed

        // The document keeps its full height; only the scroll view is held to
        // the viewport. That is what makes the table scroll rather than shrink,
        // and it is the one line that would be wrong the other way round.
        // document 保有它的完整高度;被限制在視口大小的只有那個捲動視圖。那正是讓 table「捲動」
        // 而不是「縮小」的原因,也是唯一一行反過來寫就會錯的地方。
        // Assigned only when it CHANGES.
        //
        // `setViewportHeight` runs on every commit, and assigning `frame` makes
        // `NSScrollView` re-tile even when the value is identical. Skipping the
        // no-op is worth doing on its own.
        //
        // **It has nothing to do with wheel scrolling working.** A scrolled list
        // snapping back to the top came from two defects in the test
        // synthesiser, an inverted wheel delta and a fallback that hid it; see
        // `AppKitSynthesiser.postScroll`.
        //
        // 只在它**改變時**才指派。
        //
        // `setViewportHeight` 每一次 commit 都會執行,而指派 `frame` 會讓 `NSScrollView` 重新 tile
        // ——即使值完全相同。省掉這個空操作,本身就值得做。
        //
        // **它與滾輪捲動是否正常無關。** 被捲動的清單彈回頂端,成因是測試合成器裡的兩個缺陷:一個反了的
        // 滾輪 delta,以及一道把它蓋住的退路;見 `AppKitSynthesiser.postScroll`。
        guard scrollView.frame.size.height != CGFloat(height) else { return }
        var frame = scrollView.frame
        frame.size.height = CGFloat(height)
        scrollView.frame = frame
    }
}
