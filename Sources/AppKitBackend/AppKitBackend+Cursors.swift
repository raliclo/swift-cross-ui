import AppKit
import DebugFeatures
import Foundation
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

    /// **Re-registers the tracking area when the window becomes key.** The area is registered
    /// during layout, before the window has been activated (every `-cursor: trackingArea rebuilt`
    /// line reads `window key=false`), and `updateTrackingAreas` is only called again on a bounds
    /// change. `.activeInKeyWindow` is about the window's state, so re-registering once the
    /// window is key costs one notification and removes an area added in the wrong state.
    ///
    /// `NSKeyEventTarget` watches the same notification for the same shape of reason: something
    /// that must be claimed cannot be claimed before the window is key.
    ///
    /// **在視窗成為 key 時重新註冊 tracking area。** 那塊區域是在排版期間、視窗尚未被啟用時註冊的
    /// (每一行 `-cursor: trackingArea rebuilt` 都寫著 `window key=false`),而 `updateTrackingAreas`
    /// 只有在 bounds 改變時才會再被呼叫。`.activeInKeyWindow` 講的正是視窗的狀態,因此在視窗成為 key
    /// 時重新註冊,代價是一個通知,而「在錯誤狀態下加入的區域」就被換掉了。
    ///
    /// `NSKeyEventTarget` 基於同樣形狀的理由監看同一個通知:一個必須被認領的東西,
    /// 在視窗成為 key 之前認領不了。
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        guard let window else { return }

        // **`acceptsMouseMovedEvents` is false by default, and a tracking area does not switch it
        // on for you.**
        //
        // A window that does not accept mouse-moved events is not told the pointer moved, and
        // `cursorUpdate` is delivered as part of that processing -- so the area can be registered
        // at the right bounds, in a key window of an active app that is frontmost with nothing
        // over it, and still never be asked. Every one of those was measured before this line was
        // written; `actions/mac/P72-cursor.actions` lists them.
        //
        // Set here rather than on every window, because the cost belongs to the feature that
        // needs it: a window with no `.cursor(_:)` in it has no reason to be woken for every
        // pixel the pointer crosses.
        //
        // **`acceptsMouseMovedEvents` 預設是 false,而一個 tracking area **不會**替你打開它。**
        //
        // 一個不接受 mouse-moved 事件的視窗,不會被告知指標移動過;而 `cursorUpdate` 正是在那個處理過程中
        // 被送出的——因此那塊區域可以用正確的 bounds 註冊在一個「使用中 app 的 key 視窗、而且位於最前方、
        // 上面什麼都沒有」的視窗裡,卻依然從來不被詢問。上述每一項都在寫下這一行之前量過;
        // `actions/mac/P72-cursor.actions` 列出了它們。
        //
        // 設在此處而不是設在每一個視窗上,因為這個代價該由需要它的那項功能承擔:一個裡面沒有任何
        // `.cursor(_:)` 的視窗,沒有理由為指標經過的每一個像素被叫醒。
        window.acceptsMouseMovedEvents = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowBecameKey),
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc
    private func windowBecameKey() {
        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        // `.activeInKeyWindow` rather than `.activeAlways`: a background window
        // should not repaint the pointer for an app the user is not in.
        // 用 `.activeInKeyWindow` 而不是 `.activeAlways`:一個背景視窗不該替「使用者並不在其中的 app」
        // 去改變指標樣子。
        // `.mouseEnteredAndExited` is here for `mouseExited` below.
        // `.mouseEnteredAndExited` 是為了下面的 `mouseExited` 而加的。
        let area = NSTrackingArea(
            rect: bounds,
            options: [.cursorUpdate, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
        Self.report(
            "trackingArea rebuilt: bounds \(bounds), window "
                + "\(window == nil ? "nil" : "key=\(window!.isKeyWindow)")"
        )
    }

    /// **The only place the cursor is set.**
    ///
    /// `NSCursor.set()` is GLOBAL: it changes the pointer until something else
    /// changes it back, and a plain text view changes nothing. Calling it from
    /// `mouseEntered` or from the property's `didSet` as well lets the
    /// crosshair survive the pointer leaving the view. `cursorUpdate` is
    /// the cooperative half of the same API: AppKit sends it to the view under
    /// the pointer as the pointer moves, and when no view claims the cursor it
    /// restores the arrow itself. Handling only this means the region is exactly
    /// the tracking area and nothing has to be undone on the way out.
    ///
    /// **Verified on macOS on 2026-09-27**: `actions/mac/P72-cursor.actions` reports crosshair over
    /// the mesh view and arrow over the label above it, three runs out of three, and a
    /// `screencapture -C` taken during each row shows the same. A wrong reading there came from
    /// the harness, not this class: a hover wait inside `onMain` (`RunLoop.run(until:)` does not
    /// give queued events to `sendEvent`), and action-file coordinates taken from a
    /// superview-relative frame. That file's header has both.
    ///
    /// **唯一設定游標的地方。**
    ///
    /// `NSCursor.set()` 是**全域**的:它會改變指標直到別的東西把它改回來,而一個普通的文字 view 什麼都不改。
    /// 若也在 `mouseEntered` 或屬性的 `didSet` 中呼叫它,十字會在指標離開 view 之後依然留著。`cursorUpdate`
    /// 是同一個 API 中合作的那一半:AppKit 會隨著指標移動把它送給指標底下的 view,沒有 view 認領游標時
    /// 它會自己還原箭頭。只處理這一個,區域就正好是 tracking area,離開時也不必復原任何東西。
    ///
    /// **macOS 上已於 2026-09-27 驗證**:`actions/mac/P72-cursor.actions` 在 mesh view 上回報十字、在它
    /// 上方的標籤上回報箭頭,三次中三次;而每一列執行期間拍下的 `screencapture -C` 顯示的也一樣。那裡出現
    /// 錯誤讀數時,成因在測試工具而不在這個類別:一個跑在 `onMain` 裡的 hover 等待(`RunLoop.run(until:)`
    /// 不會把佇列中的事件交給 `sendEvent`),以及取自「相對於父 view」之 frame 的動作檔座標。兩者都記在
    /// 該檔案的檔頭。
    override func cursorUpdate(with event: NSEvent) {
        cursor.set()
        Self.report(
            "cursorUpdate on a \(bounds.width)x\(bounds.height) target at "
                + "\(convert(bounds.origin, to: nil)) -> set"
        )
    }

    /// **Separates the two reasons a cursor reading can be wrong.**
    ///
    /// `actions/mac/P72-cursor.actions` reads the cursor back after moving the pointer, and when the
    /// answer is wrong there are two entirely different reasons: the pointer never reached this
    /// view, or it reached it and the reading is stale. From outside they are one symptom. This
    /// line separates them -- a hover row with no `-cursor:` line beside it did not reach the
    /// view, whatever the reading says.
    ///
    /// Gated on `DebugFeatures.isEnabled` and written to stderr, exactly as
    /// `AppKitBackend+HitTesting.swift`'s `-hittest:` lines are, and for the same reason: that is
    /// the stream the action file's own lines already use.
    ///
    /// **區分游標讀數出錯的兩種理由。**
    ///
    /// `actions/mac/P72-cursor.actions` 會在移動指標之後把游標讀回來;而當答案是錯的時,可能有兩個
    /// 截然不同的理由:指標根本沒有抵達這個 view,或者它抵達了而讀數是過期的。從外面看,那是同一個症狀。
    /// 這一行把它們分開——一列 hover 旁邊沒有 `-cursor:` 行,就代表它沒有抵達這個 view,
    /// 不論讀數說了什麼。
    ///
    /// 以 `DebugFeatures.isEnabled` 為條件並寫入 stderr,與 `AppKitBackend+HitTesting.swift` 的
    /// `-hittest:` 行完全一致,理由也相同:那正是動作檔各行本來就使用的串流。
    private static func report(_ message: String) {
        guard DebugFeatures.isEnabled else { return }
        FileHandle.standardError.write(Data("-cursor: \(message)\n".utf8))
    }

    /// **Only a log line. AppKit puts the arrow back by itself, measured 2026-09-27.**
    ///
    /// With no reset here and the pointer moved off the mesh view onto the label above it, the
    /// reading is arrow and a `screencapture -C` shows an arrow: AppKit restores the arrow when no
    /// view claims the cursor, as `cursorUpdate` relies on.
    ///
    /// Calling `NSCursor.arrow.set()` here is not harmless: a pointer leaving this view for one
    /// that claims its own cursor could have that cursor overwritten by an exit arriving after the
    /// other view's update.
    ///
    /// **只留一行 log。AppKit 會自己把箭頭放回去,2026-09-27 實測。**
    ///
    /// 這裡不做還原、把指標從 mesh view 移到它上方的標籤時,讀數是箭頭,`screencapture -C` 拍到的也是
    /// 箭頭:沒有 view 認領游標時 AppKit 會自己還原箭頭,`cursorUpdate` 正是依賴這一點。
    ///
    /// 在這裡呼叫 `NSCursor.arrow.set()` 並非無害:指標離開本 view、進入一個自己認領游標的 view 時,
    /// 一個晚於對方更新才到的離開事件,可能把對方的游標蓋掉。
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        Self.report("mouseExited")
    }
}
