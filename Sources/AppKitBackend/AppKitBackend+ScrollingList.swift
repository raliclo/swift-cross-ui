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
        // **It is NOT what fixed wheel scrolling, and the first version of this
        // comment said it was.** That claim was a hypothesis written before it
        // was tested: a scrolled list really was snapping back to the top, and
        // this looked like the cause. It was not -- the list still snapped back
        // with this guard in place. The cause was two defects in the test
        // synthesiser, an inverted wheel delta and a fallback that hid it; see
        // `AppKitSynthesiser.postScroll`.
        //
        // 只在它**改變時**才指派。
        //
        // `setViewportHeight` 每一次 commit 都會執行,而指派 `frame` 會讓 `NSScrollView` 重新 tile
        // ——即使值完全相同。省掉這個空操作,本身就值得做。
        //
        // **它**不是**修好滾輪捲動的原因,而本註解的第一版曾經這麼宣稱。** 那個宣稱是一個「在被測試
        // 之前就寫下的假設」:當時確實有一份被捲動的清單會彈回頂端,而這看起來像是原因。它不是
        // ——加上這道防護之後,那份清單照樣彈回去。真正的原因是測試合成器裡的兩個缺陷:一個反了的
        // 滾輪 delta,以及一道把它蓋住的退路;見 `AppKitSynthesiser.postScroll`。
        guard scrollView.frame.size.height != CGFloat(height) else { return }
        var frame = scrollView.frame
        frame.size.height = CGFloat(height)
        scrollView.frame = frame
    }
}
