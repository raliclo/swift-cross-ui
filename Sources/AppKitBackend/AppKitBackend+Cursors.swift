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

    /// **Every `-cursor: trackingArea rebuilt` line this class has ever printed said
    /// `window key=false`, and `updateTrackingAreas` is only called again on a bounds change.**
    ///
    /// The area is therefore registered once, during layout, while the window has not been
    /// activated yet -- and `.activeInKeyWindow` is about the window's state, so an area added in
    /// that state is the one candidate the instrument pointed at that had not been tried.
    /// Re-registering when the window becomes key costs one notification and removes the question.
    ///
    /// `NSKeyEventTarget` watches the same notification for the same shape of reason: something
    /// that must be claimed cannot be claimed before the window is key.
    ///
    /// **本類別印出過的每一行 `-cursor: trackingArea rebuilt` 都寫著 `window key=false`,
    /// 而 `updateTrackingAreas` 只有在 bounds 改變時才會再被呼叫。**
    ///
    /// 也就是說那塊區域只在排版期間註冊過一次,而當時視窗還沒有被啟用;而 `.activeInKeyWindow`
    /// 講的正是視窗的狀態——「在那個狀態下加入的區域」,是儀器所指向、而尚未被嘗試過的唯一候選。
    /// 在視窗成為 key 時重新註冊,代價是一個通知,而那個問題就沒了。
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
        // written; `actions/mac/P72-cursor.csv` lists them.
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
        // `actions/mac/P72-cursor.csv` 列出了它們。
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
        Self.report(
            "trackingArea rebuilt: bounds \(bounds), window "
                + "\(window == nil ? "nil" : "key=\(window!.isKeyWindow)")"
        )
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
    /// **VERIFIED on macOS on 2026-09-27**: `actions/mac/P72-cursor.csv` reports crosshair over
    /// the mesh view and arrow over the label above it, three runs out of three, and a
    /// `screencapture -C` taken during each row shows the same.
    ///
    /// This class was not what was wrong, and none of the ten candidates eliminated from
    /// 2026-09-22 on was either. The 2026-09-22 version of this comment had already named the
    /// symptom exactly -- "the mouse-moved from the first row is processed during the second
    /// row's pause" -- and every attempt at it then waited LONGER, when the wait was the problem:
    /// it ran inside `onMain`, and `RunLoop.run(until:)` does not give queued events to
    /// `sendEvent`. The other cause was the action file's coordinates, "corrected" on 2026-09-23
    /// from a superview-relative frame. That file's header has both.
    ///
    /// **macOS 上已於 2026-09-27 驗證**:`actions/mac/P72-cursor.csv` 在 mesh view 上回報十字、在它
    /// 上方的標籤上回報箭頭,三次中三次;而每一列執行期間拍下的 `screencapture -C` 顯示的也一樣。
    ///
    /// 出錯的不是這個類別,而自 2026-09-22 起被排除的十個候選也都不是。2026-09-22 版的這段註解其實已經
    /// 精確說出了症狀——「第一列的 mouse-moved 是在第二列的暫停期間才被處理」——而當時的每一次嘗試都是
    /// 等**更久**,但問題正出在那個等待上:它跑在 `onMain` 裡,而 `RunLoop.run(until:)` 不會把佇列中的
    /// 事件交給 `sendEvent`。另一個成因是動作檔的座標:2026-09-23 依據一個「相對於父 view」的 frame
    /// 把它「修正」掉了。兩者都記在該檔案的檔頭。
    override func cursorUpdate(with event: NSEvent) {
        cursor.set()
        Self.report(
            "cursorUpdate on a \(bounds.width)x\(bounds.height) target at "
                + "\(convert(bounds.origin, to: nil)) -> set"
        )
    }

    /// **The instrument this class did not have, and the absence of which cost four attempts at
    /// the wrong problem.**
    ///
    /// `actions/mac/P72-cursor.csv` reads the cursor back after moving the pointer, and when the
    /// answer is wrong there are two entirely different reasons: the pointer never reached this
    /// view, or it reached it and the reading is stale. From outside they are one symptom. This
    /// line separates them -- a hover row with no `-cursor:` line beside it did not reach the
    /// view, whatever the reading says.
    ///
    /// Gated on `DebugFeatures.isEnabled` and written to stderr, exactly as
    /// `AppKitBackend+HitTesting.swift`'s `-hittest:` lines are, and for the same reason: that is
    /// the stream the action file's own lines already use.
    ///
    /// **本類別原本沒有的那個儀器,而它的缺席讓四次嘗試都花在錯的問題上。**
    ///
    /// `actions/mac/P72-cursor.csv` 會在移動指標之後把游標讀回來;而當答案是錯的時,可能有兩個
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
    /// This used to call `NSCursor.arrow.set()`, on the grounds that nothing else could restore
    /// the arrow, and cited a 2026-09-22 `hover` reading of a crosshair over plain text. That
    /// reading was the one-row-late artefact `AppKitSynthesiser`'s hover wait produced, so it
    /// measured nothing. Measured properly -- the reset removed, pointer moved off the mesh view
    /// onto the label above it -- the reading is arrow and a `screencapture -C` shows an arrow.
    /// The claim above `cursorUpdate`, that AppKit restores the arrow when no view claims the
    /// cursor, was right all along.
    ///
    /// The forced reset was removed rather than kept as harmless, because it is not: a pointer
    /// leaving this view for one that claims its own cursor could have that cursor overwritten
    /// by an exit arriving after the other view's update.
    ///
    /// **只留一行 log。AppKit 會自己把箭頭放回去,2026-09-27 實測。**
    ///
    /// 這裡原本會呼叫 `NSCursor.arrow.set()`,理由是「沒有別的東西能還原箭頭」,並引用 2026-09-22 一次
    /// `hover` 在純文字上讀到十字的讀數。那個讀數正是 `AppKitSynthesiser` 的 hover 等待所產生的「晚一列」
    /// 假象,因此它什麼也沒量到。正確地量——拿掉那個還原、把指標從 mesh view 移到它上方的標籤——
    /// 讀數是箭頭,`screencapture -C` 拍到的也是箭頭。`cursorUpdate` 上方那段說法(沒有 view 認領游標時
    /// AppKit 會自己還原箭頭)從頭到尾都是對的。
    ///
    /// 那個強制還原被拿掉、而不是當成無害的東西留著,因為它並非無害:指標離開本 view、進入一個自己
    /// 認領游標的 view 時,一個晚於對方更新才到的離開事件,可能把對方的游標蓋掉。
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        Self.report("mouseExited")
    }
}
