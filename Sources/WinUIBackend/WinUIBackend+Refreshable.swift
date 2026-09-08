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

        guard let handler else {
            Self.refreshHandlers[ObjectIdentifier(scrollViewer)] = nil
            return
        }

        let key = ObjectIdentifier(scrollViewer)
        let isFirst = Self.refreshHandlers[key] == nil
        Self.refreshHandlers[key] = handler
        guard isFirst else { return }

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
        if let existing = scrollViewer.content as? WinUI.UIElement {
            scrollViewer.content = nil
            grid.children.append(existing)
        }
        grid.children.append(button)
        scrollViewer.content = grid
    }

    nonisolated(unsafe) static var refreshHandlers:
        [ObjectIdentifier: @MainActor @Sendable () -> Void] = [:]
}
