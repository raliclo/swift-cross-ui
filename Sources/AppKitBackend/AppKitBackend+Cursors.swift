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
        let area = NSTrackingArea(
            rect: bounds,
            options: [.cursorUpdate, .activeInKeyWindow, .inVisibleRect],
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
    /// **What was verified and what was not, because the difference matters
    /// here.** VERIFIED: `.cursor(.crosshair)` takes effect -- a
    /// `screencapture -C` of P72 shows a crosshair, which is not the system
    /// default over that window. NOT VERIFIED: that the crosshair is confined to
    /// the mesh view. It cannot be, by this route: the action file's `move` goes
    /// through `NSApp.postEvent`, which delivers a synthetic mouse-moved event
    /// to the application and does NOT move the physical pointer, so
    /// `screencapture -C` draws the real pointer wherever it happens to sit. A
    /// capture taken that way showed the crosshair 300 points from the view, and
    /// the honest reading of that is "the mouse was over there", not "the region
    /// is wrong". Confinement needs a real pointer: `CGWarpMouseCursorPosition`,
    /// or a person moving a mouse.
    ///
    /// **設定游標的唯一地方,而第一版還多了兩處。**
    ///
    /// `NSCursor.set()` 是**全域**的:它會一直改變指標,直到有別的東西把它改回來;而一個普通的文字 view
    /// 什麼也不會改。第一版還從 `mouseEntered` 與屬性的 `didSet` 呼叫它,因此指標離開那個 view 之後,
    /// 十字仍然留著。`cursorUpdate` 是同一組 API 中協作的那一半:AppKit 會在指標移動時,把它送給指標
    /// 底下的那個 view;而當沒有任何 view 認領游標時,AppKit 自己會還原成箭頭。只處理這一個,代表那塊
    /// 區域**恰好**就是 tracking area,離開時也不需要撤銷任何東西。
    ///
    /// **已驗證什麼、未驗證什麼——因為此處這個分別很重要。** **已驗證**:`.cursor(.crosshair)` 確實生效
    /// ——P72 的 `screencapture -C` 拍到一個十字,而那不是該視窗上方的系統預設。**未驗證**:那個十字
    /// 被侷限在 mesh view 之內。以這條路徑**驗不了**:動作檔的 `move` 走的是 `NSApp.postEvent`,
    /// 它把一個合成的 mouse-moved 事件送給**應用程式**,並**不會**移動實體指標;因此
    /// `screencapture -C` 畫的是實體指標當下所在之處。一張那樣拍出來的擷圖顯示十字在距離該 view 三百點
    /// 之外,而它誠實的讀法是「滑鼠在那邊」,不是「區域錯了」。要驗證侷限性,需要一個**真的**指標:
    /// `CGWarpMouseCursorPosition`,或一個人去移動滑鼠。
    override func cursorUpdate(with event: NSEvent) {
        cursor.set()
    }
}
