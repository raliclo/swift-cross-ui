import CGtk
import Gtk
@_spi(Backends) import SwiftCrossUI

/// `BackendFeatures.ScrollingLists` for GTK 4 (#117).
///
/// The structural half of this is in `createSelectableListView`: a `List` is a
/// `GtkScrolledWindow` wrapping the `GtkListBox`, because a bare list box does
/// not scroll and shrinking one clips its rows. This file is the other half --
/// telling that scrolled window how tall it is allowed to be.
///
/// **Why a method at all, when `setSize` follows one line later.** `List.commit`
/// calls this and then `setSize` with the same height, so on GTK the two look
/// redundant. They are not. `setSize` sets a size *request*, which is a floor
/// GTK may exceed; `maximumContentHeight` is a ceiling on how much of the
/// content the scrolled window will ask to show. Without the ceiling a
/// `GtkScrolledWindow` given a request of 400 and a 9000-point child still
/// reports a natural height in the thousands to its parent, and the window
/// grows -- which is #117 exactly, moved one widget outwards.
///
/// 為 GTK 4 實作的 `BackendFeatures.ScrollingLists`(#117)。
///
/// 結構性的那一半在 `createSelectableListView`:一個 `List` 是包住 `GtkListBox` 的
/// `GtkScrolledWindow`,因為光禿禿的 list box 不會捲動,而把它縮小只會裁掉它的列。本檔是另一半
/// ——告訴那個 scrolled window 它被允許有多高。
///
/// **既然下一行就是 `setSize`,為何還需要一個方法。** `List.commit` 先呼叫本方法、再以相同的高度
/// 呼叫 `setSize`,因此在 GTK 上兩者看似重複。並非如此。`setSize` 設定的是 size **request**,那是
/// 一個 GTK 可以超出的**下限**;而 `maximumContentHeight` 是「scrolled window 會要求顯示多少內容」
/// 的**上限**。少了這個上限,一個收到 400 的 request、內含 9000 點高子元件的 `GtkScrolledWindow`,
/// 仍會向它的父層回報數千點的自然高度,於是視窗照樣長高——那正是 #117 本身,只是往外移了一個 widget。
extension GtkBackend: BackendFeatures.ScrollingLists {
    public func setViewportHeight(ofSelectableListView listView: Widget, to height: Int) {
        let scrolled = listView as! ScrolledWindow

        // Guard against a zero or negative height rather than passing it on.
        // GTK treats -1 on these properties as "unset", so a stray negative
        // would not error -- it would quietly restore the unbounded behaviour
        // this method exists to prevent, on one list, at one moment, for
        // whatever reason produced the value. A floor of 1 keeps the ceiling
        // real.
        // 對零或負的高度就地防守，而不是把它傳下去。GTK 把這些屬性上的 -1 視為「未設定」，因此一個
        // 漏網的負值不會報錯——它會安靜地把本方法所要防止的「無上限」行為還原回來，只發生在某一個
        // list、某一個時刻，起因則是任何產生出該數值的東西。以 1 作為下限，可讓這個上限始終為真。
        let clamped = max(1, height)
        scrolled.maximumContentHeight = clamped

        // Not `minimumContentHeight`. That would make the list demand the full
        // viewport even when it holds two rows, so a short `List` would leave a
        // block of empty space below it instead of hugging its content -- which
        // is what it does on AppKit, and what SwiftUI does.
        // 不設 `minimumContentHeight`。那會讓清單即使只有兩列也要求完整的視口高度，於是一個很短的
        // `List` 底下會留下一塊空白，而不是貼合其內容——後者才是它在 AppKit 上的行為，也是 SwiftUI
        // 的行為。
    }
}
