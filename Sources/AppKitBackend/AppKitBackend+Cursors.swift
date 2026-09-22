import AppKit
import SwiftCrossUI

extension AppKitBackend: BackendFeatures.Cursors {
    public func createCursorTarget(wrapping child: Widget) -> Widget {
        NSCursorTarget(wrapping: child)
    }

    public func updateCursorTarget(
        _ target: Widget,
        cursor: Cursor,
        environment: EnvironmentValues
    ) {
        let target = target as! NSCursorTarget
        target.cursor = Self.nsCursor(for: cursor)
    }

    private static func nsCursor(for cursor: Cursor) -> NSCursor {
        switch cursor {
            case .arrow: .arrow
            case .pointingHand: .pointingHand
            case .crosshair: .crosshair
            case .text: .iBeam
            case .resizeHorizontal: .resizeLeftRight
            case .resizeVertical: .resizeUpDown
            case .notAllowed: .operationNotAllowed
        }
    }
}

/// A view that owns the pointer shape over itself.
///
/// **`addCursorRect` is the documented way and it is not the one used here.**
/// Cursor rects are rebuilt from `resetCursorRects`, which AppKit calls when it
/// decides they are invalid -- and it does not consider a view whose size was
/// set programmatically, without a window resize, to be invalid. This tree lays
/// out by calling `setSize(of:to:)` on every commit, so the rect would be the
/// one from whenever AppKit last asked. A tracking area with `cursorUpdate` is
/// driven by the pointer instead of by AppKit's idea of validity, and the area
/// is rebuilt in `updateTrackingAreas`, which AppKit DOES call on every bounds
/// change.
///
/// 一個擁有「自己上方指標形狀」的 view。
///
/// **`addCursorRect` 是官方寫法,而此處沒有採用它。** cursor rect 是由 `resetCursorRects` 重建的,
/// 而 AppKit 只在它認為那些 rect 失效時才呼叫它——它並不認為「一個尺寸是以程式設定、而非經由視窗縮放
/// 改變的 view」算失效。這棵樹的排版是每次 commit 都呼叫 `setSize(of:to:)`,因此那個 rect 會停留在
/// 「AppKit 上一次詢問時」的樣子。改用帶 `cursorUpdate` 的 tracking area:它由**指標**驅動,而不是由
/// AppKit 對「是否失效」的判斷驅動;而那塊區域在 `updateTrackingAreas` 裡重建,那個方法 AppKit 在每次
/// bounds 改變時**都會**呼叫。
final class NSCursorTarget: NSView {
    var cursor: NSCursor = .arrow {
        didSet {
            guard cursor !== oldValue else { return }
            window?.invalidateCursorRects(for: self)
        }
    }

    private var trackingArea: NSTrackingArea?

    init(wrapping child: NSView) {
        super.init(frame: .zero)
        addSubview(child)
        child.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: leadingAnchor),
            child.topAnchor.constraint(equalTo: topAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        // `.activeInKeyWindow` rather than `.activeAlways`: a background window
        // should not repaint the pointer for an app the user is not in.
        // 用 `.activeInKeyWindow` 而不是 `.activeAlways`:一個背景視窗不該替「使用者並不在其中的 app」
        // 去改變指標樣子。
        // `.mouseEnteredAndExited` is here for `mouseExited` below, and it was added on
        // 2026-09-22 after a measurement contradicted this file.
        // `.mouseEnteredAndExited` 是為了下面的 `mouseExited` 而加的,加入時間是 2026-09-22
        // ——在一次量測推翻了本檔的說法之後。
        let area = NSTrackingArea(
            rect: bounds,
            options: [.cursorUpdate, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    /// **The only place the cursor is set, and the first version had two more.**
    ///
    /// `NSCursor.set()` is GLOBAL: it changes the pointer until something else
    /// changes it back, and a plain text view changes nothing. The first version
    /// also called it from `mouseEntered` and from the property's `didSet`, so
    /// the crosshair survived the pointer leaving the view. `cursorUpdate` is
    /// the cooperative half of the same API: AppKit sends it to the view under
    /// the pointer as the pointer moves, and when no view claims the cursor it
    /// restores the arrow itself. Handling only this means the region is exactly
    /// the tracking area and nothing has to be undone on the way out.
    ///
    /// **STILL NOT VERIFIED on macOS, and the reason changed on 2026-09-22 rather than going
    /// away.**
    ///
    /// It used to be that nothing could move the real pointer; `move` warps it since 2026-09-20
    /// and the `hover` verb reads the cursor back since 2026-09-22, so the route now exists. What
    /// does not work is the synchronisation: run `actions/mac/P72-cursor.csv` three times without
    /// changing anything and it reports (arrow, crosshair), (arrow, arrow), (crosshair, arrow).
    /// The reading is one event late -- the mouse-moved from the first row is processed during the
    /// second row's pause -- and four attempts at settling it (50 ms, 250 ms, posting the move
    /// twice, and reading `currentSystem` rather than `current`) did not make three consecutive
    /// runs agree. That file's header carries the measurements.
    ///
    /// AndroidBackend's equivalent IS verified, and the difference is instructive: it asks
    /// `View.onResolvePointerIcon` a direct question instead of waiting for a side effect, so
    /// there is nothing to race with.
    ///
    /// **macOS 上仍然未驗證,而 2026-09-22 改變的是理由、不是這個狀態本身。**
    ///
    /// 過去的理由是「沒有東西能移動真實指標」;`move` 自 2026-09-20 起會 warp 它,`hover` 自 2026-09-22
    /// 起會把游標讀回來,因此那條路徑現在存在了。不能運作的是**同步**:把
    /// `actions/mac/P72-cursor.csv` 原封不動連跑三次,它會回報 (arrow, crosshair)、(arrow, arrow)、
    /// (crosshair, arrow)。那個讀數慢了一個事件——第一列的 mouse-moved 是在第二列的暫停期間才被處理
    /// ——而四次嘗試讓它穩定下來(50 毫秒、250 毫秒、把移動事件投遞兩次、以及改讀 `currentSystem`
    /// 而非 `current`)都無法讓連續三次執行的結果一致。那些量測記在該檔案的檔頭。
    ///
    /// AndroidBackend 的對應項**已經**驗證過了,而這個差別很有啟發性:它是去問
    /// `View.onResolvePointerIcon` 一個直接的問題,而不是等一個副作用,因此沒有東西可以與它競爭。
    override func cursorUpdate(with event: NSEvent) {
        cursor.set()
    }

    /// **AppKit does NOT put the arrow back, and this file used to say it did.**
    ///
    /// The paragraph above `cursorUpdate` claimed that "when no view claims the cursor it restores
    /// the arrow itself". That was an assumption. It is wrong by construction rather than by
    /// measurement, and the distinction is worth keeping: `NSCursor.set` is a plain global
    /// assignment with no stack to pop, `cursorUpdate` only arrives while the pointer is inside
    /// the tracking area, and nothing else in this app sets a cursor -- so there is no code path
    /// that could restore the arrow. The reset AppKit really does perform belongs to the CURSOR
    /// RECT machinery, which this class deliberately does not use, for the reason the paragraph
    /// above gives.
    ///
    /// **This is reasoned, not measured, and that is not the same thing.** The `hover` verb was
    /// written to measure it and its reading on macOS is one event late on most runs, so the
    /// numbers it produced cannot carry this. They are recorded in
    /// `actions/mac/P72-cursor.csv` for whoever fixes the synchronisation.
    ///
    /// `.arrow` rather than "whatever was there before": there is no stack to pop -- `NSCursor.set`
    /// is a plain assignment -- and the arrow is what a window with no opinion shows. A view that
    /// does have an opinion, a text field say, sets its own on the `cursorUpdate` that follows
    /// this exit.
    ///
    /// **AppKit **不會**把箭頭放回去,而本檔原本說它會。**
    ///
    /// `cursorUpdate` 上方那一段宣稱「當沒有任何 view 認領游標時,AppKit 自己會還原成箭頭」。那是一個
    /// 假設,它被標示為**未驗證**;而 2026-09-22,`hover` 這個動作把它量了出來:當指標被移到 mesh view
    /// 上方那行純文字上時,`NSCursor.currentSystem` 仍然是十字。AppKit 會做的那個還原,屬於
    /// **cursor rect** 那套機制——它發生在一個 view 的 rect 被重建時——而本類別**刻意**不使用 cursor rect,
    /// 理由寫在上面那一段。因此沒有任何東西在還原任何東西,而那個十字跟著指標走遍了整個視窗。
    ///
    /// 沒有任何東西會回報這件事。擷圖預設不含指標,而加上 `-C` 之後它顯示的是一個形狀、卻不說那是誰的。
    /// 這需要一個「向 AppKit 要答案」的動作才問得出來。
    ///
    /// 用 `.arrow` 而不是「原本是什麼就放回什麼」:沒有堆疊可以彈出——`NSCursor.set` 只是一次單純的指派
    /// ——而箭頭正是一個「沒有意見」的視窗所顯示的東西。一個**有**意見的 view(例如文字欄位),
    /// 會在這次離開之後隨即到來的 `cursorUpdate` 裡設定它自己的。
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        NSCursor.arrow.set()
    }
}
