@_spi(Backends) import SwiftCrossUI
import WinUI

/// A refresh affordance for `ScrollViewer`.
///
/// WinUI has `RefreshContainer` and `RefreshVisualizer`, which are the right
/// answer on paper: a pull gesture with the platform's own spinner. They are
/// not used here, for a reason this project has already paid for once. A
/// `RefreshContainer` has to WRAP the scroll viewer, so reaching for it changes
/// what `createScrollContainer(for:)` returns, and every cast of the form
/// `scrollView as! WinUI.ScrollViewer` in `updateScrollContainer` would then
/// trap at runtime on a backend nobody here can run.
///
/// So the action gets a button, placed in the scroll viewer's own top-left
/// corner. It costs no structural change, it works with a mouse -- which is
/// what a Windows desktop has -- and it is the same shape AppKitBackend and
/// AndroidBackend use.
///
/// **Written on macOS and NOT verified.** WinUIBackend builds and runs on the
/// Windows machine. What to check first: whether a `Grid` is the right host for
/// the button, and whether the button needs its own row so it does not scroll
/// away with the content.
///
/// 給 `ScrollViewer` 使用的重新整理操作方式。
///
/// WinUI 有 `RefreshContainer` 與 `RefreshVisualizer`,在紙面上那是正確答案:一個下拉手勢,配上該平台
/// 自己的轉圈。此處沒有採用它們,理由是本專案已經為此付過一次代價。`RefreshContainer` 必須**包住**
/// scroll viewer,因此伸手去拿它會改變 `createScrollContainer(for:)` 的回傳值,而
/// `updateScrollContainer` 中每一個 `scrollView as! WinUI.ScrollViewer` 形式的轉型,都會在一個
/// 「此地無人跑得起來」的 backend 上於執行期崩潰。
///
/// 所以這個動作得到的是一顆按鈕,放在 scroll viewer 自己的左上角。它不需要任何結構性改動、用滑鼠
/// 就能操作——而那正是 Windows 桌面所擁有的——並且與 AppKitBackend 及 AndroidBackend 採用的形狀相同。
///
/// **在 macOS 上寫成,且未經驗證。** WinUIBackend 是在 Windows 機器上建置與執行的。應優先檢查的是:
/// `Grid` 是否為這顆按鈕的正確宿主,以及該按鈕是否需要自己的一列,好讓它不會隨內容一起捲走。
extension WinUIBackend {
    public func setRefreshHandler(
        ofScrollContainer scrollView: Widget,
        to handler: (@MainActor @Sendable () -> Void)?
    ) {
        guard let scrollViewer = scrollView as? WinUI.ScrollViewer else { return }
        let key = ObjectIdentifier(scrollViewer)

        // REMOVING THE HANDLER NOW REMOVES THE BUTTON. Until 2026-09-09 this
        // branch deleted the dictionary entry and nothing else, which left two
        // defects that a compiler cannot see and a screenshot reads as fine:
        //
        //   1. a "Refresh" button stayed on screen with nothing behind it. Its
        //      click handler looks up `refreshHandlers[key]`, which is now nil,
        //      so pressing it did nothing AND reported nothing -- a control
        //      that is present, enabled, and inert.
        //   2. re-enabling wrapped AGAIN. `isFirst` was true once more, so a
        //      second Grid was built, and the `scrollViewer.content as?
        //      UIElement` below picked up the FIRST Grid and nested it inside
        //      the second. Toggle `.refreshable` n times and the tree carries n
        //      Grids and n buttons, n-1 of them dead.
        //
        // Found by a code review on 2026-09-09, in a file whose own header says
        // it was "written on macOS and NOT verified" -- the review could not run
        // it either, which is why it was handed to the Windows side to check.
        //
        // **移除 handler 現在會一併移除按鈕。** 在 2026-09-09 之前，這個分支只刪掉字典項目而不做別的，
        // 留下兩個編譯器看不見、截圖也讀不出來的缺陷：(1) 一顆「Refresh」按鈕留在畫面上，背後卻空無
        // 一物——它的 click handler 查的是 `refreshHandlers[key]`，而那已是 nil，因此按下去**既不做事
        // 也不回報**，是一個存在、啟用、卻毫無作用的控制項；(2) 重新啟用時會**再包一次**——`isFirst`
        // 又變成 true，於是第二個 Grid 被建立，而下方的 `scrollViewer.content as? UIElement` 會抓到
        // **第一個** Grid 並把它巢狀進去。把 `.refreshable` 開關 n 次，樹裡就有 n 個 Grid 與 n 顆按鈕，
        // 其中 n-1 顆是死的。
        //
        // 由 2026-09-09 的一次程式碼審查發現；而本檔自己的標頭寫著它「在 macOS 上寫成，且未經驗證」
        // ——審查方同樣跑不動它，這正是它被交給 Windows 側查證的原因。
        guard let handler else {
            Self.refreshHandlers[key] = nil
            if let wrap = Self.refreshWraps[key] {
                // Clear FIRST, then reassign: the original child is still
                // parented to the Grid until the Grid lets go of it, and
                // assigning a still-parented element is what throws.
                // **先 clear、再指派**：在 Grid 放手之前，原本的子項仍掛在 Grid 之下，而指派一個
                // 仍有父節點的元素，正是會拋錯的那件事。
                wrap.grid.children.clear()
                scrollViewer.content = wrap.original
                Self.refreshWraps[key] = nil
            }
            return
        }

        Self.refreshHandlers[key] = handler
        // Keyed off the WRAP, not off whether a handler existed. Those two
        // answered the same question until removal started unwrapping; now they
        // do not, and the wrap is the one that says whether the button is
        // already in the tree. The existing button keeps working because its
        // click handler reads `refreshHandlers[key]` at press time rather than
        // capturing the closure.
        // 判斷依據是**包裝狀態**，而不是「先前是否存在 handler」。在移除開始會還原之前，這兩者回答的是
        // 同一個問題；現在不是了，而能說明「按鈕是否已在樹中」的是包裝狀態。既有的按鈕仍然有效，因為
        // 它的 click handler 是在**按下當時**去讀 `refreshHandlers[key]`，而不是把 closure 捕獲起來。
        guard Self.refreshWraps[key] == nil else { return }

        let button = WinUI.Button()
        button.content = "Refresh"
        button.horizontalAlignment = .left
        button.verticalAlignment = .top
        button.click.addHandler { _, _ in
            MainActor.assumeIsolated {
                Self.refreshHandlers[key]?()
            }
        }

        // Wrapped in a Grid with the existing content, so the button overlays
        // rather than replaces it. A ScrollViewer holds one child, and
        // assigning the button to `content` would throw the app's entire view
        // away in exchange for a refresh button -- a change that compiles.
        // 與既有內容一起包進一個 Grid 中,讓這顆按鈕是**疊在**其上而非取代它。ScrollViewer 只持有一個
        // 子項,而把這顆按鈕指派給 `content`,等於用整個 app 的畫面去換一顆重新整理按鈕——而那是一個
        // 編譯得過的改動。
        let grid = WinUI.Grid()
        let existing = scrollViewer.content as? WinUI.UIElement
        if let existing {
            scrollViewer.content = nil
            grid.children.append(existing)
        }
        grid.children.append(button)
        scrollViewer.content = grid
        // Recorded so removal can put things back. `original` is stored rather
        // than searched for at removal time: with the button in the same Grid,
        // "the child that is not the button" needs identity comparison across a
        // COM boundary, and remembering what was wrapped is both cheaper and
        // exact.
        // 記錄下來，好讓移除時能還原。此處**儲存** `original` 而非在移除時去尋找它：由於按鈕與它同在
        // 一個 Grid 內，「不是按鈕的那個子項」得跨 COM 邊界做識別比較，而記住「當初包了什麼」既便宜
        // 又精確。
        Self.refreshWraps[key] = RefreshWrap(grid: grid, button: button, original: existing)
    }

    nonisolated(unsafe) static var refreshHandlers:
        [ObjectIdentifier: @MainActor @Sendable () -> Void] = [:]

    /// What was put around a scroll viewer's content, so it can be taken off
    /// again. Without this, `setRefreshHandler(to: nil)` could only forget the
    /// callback; the widgets it had added stayed in the tree.
    ///
    /// 為了讓「加在 scroll viewer 內容外面的東西」能被取下來而記錄的狀態。少了它，
    /// `setRefreshHandler(to: nil)` 就只能忘掉 callback，而它先前加進去的 widget 會留在樹裡。
    struct RefreshWrap {
        var grid: WinUI.Grid
        var button: WinUI.Button
        var original: WinUI.UIElement?
    }

    /// Keyed by the scroll viewer, like ``refreshHandlers``. Both share the same
    /// known limitation: an entry outlives a scroll viewer that goes away, so
    /// the tables grow with the number of scroll viewers ever created rather
    /// than the number alive. Pre-existing, not introduced here, and stated so
    /// it is not rediscovered as new.
    ///
    /// 與 ``refreshHandlers`` 同樣以 scroll viewer 為鍵。兩者共有同一項已知限制：當某個 scroll viewer
    /// 消失時，其項目仍會留存，因此這兩張表的成長量取決於「曾經被建立過的 scroll viewer 數量」，而非
    /// 「當前存活的數量」。此限制既有，非本次引入；寫明於此，以免日後被當成新問題重新發現。
    nonisolated(unsafe) static var refreshWraps: [ObjectIdentifier: RefreshWrap] = [:]
}
