#if os(macOS)

import AppKit
import Carbon.HIToolbox
import Foundation

/// Posts events into this process's own event queue, through `NSApp.postEvent`.
///
/// The other two synthesisers are system-wide: `SendInput` posts to the
/// foreground window and XTEST to the X server's focus, so both drive whatever
/// happens to be in front. macOS has the same shape available -- `CGEvent.post`
/// -- and it is deliberately not used.
///
/// Measured on macOS 27 with the terminal untrusted, which is the state a
/// developer's machine is in until somebody clicks in System Settings:
///
///   AXIsProcessTrusted()                     false
///   CGEvent.post(tap: .cghidEventTap)        0 events delivered
///   CGEvent.postToPid(getpid())              0 events delivered
///   NSApp.postEvent(_:atStart:)              delivered; NSButton fired,
///                                            NSTextField received the key
///
/// The first two fail *silently* -- no error, no diagnostic, an app that looks
/// as though it ignored its input. That is the worst failure this module can
/// have, and it is the one `-actionfile` exists to avoid. So this path posts
/// in-process, needs no Accessibility grant, and cannot be defeated by the app
/// not being frontmost.
///
/// Two consequences follow, and both are improvements rather than compromises.
/// Events are addressed to a window by number, so a replay cannot leak into
/// another application the way an early replay does elsewhere. And because
/// AppKit reads modifier state from the event rather than from the hardware,
/// the modifiers a file holds down are tracked here (see ``heldModifiers``)
/// instead of being left to the system.
///
/// 將事件投遞至本行程自身的事件佇列，透過 `NSApp.postEvent`。
///
/// 另外兩個 synthesiser 都是系統層級的：`SendInput` 投遞至前景視窗，XTEST 投遞至 X server 的
/// 焦點，因此兩者驅動的都是「當下位於前方的任何東西」。macOS 也有同樣形狀的機制——`CGEvent.post`
/// ——而此處刻意不使用它。
///
/// 在 macOS 27 上實測，終端機未被授予信任（在有人前往「系統設定」點擊之前，開發機器都處於此
/// 狀態）：上表所列，前兩者投遞出 0 個事件，第三者成功——NSButton 被觸發、NSTextField 收到按鍵。
///
/// 前兩者是**靜默**失敗——沒有錯誤、沒有診斷訊息，只留下一個看似忽略了輸入的應用程式。那是本模組
/// 所能發生的最糟糕的失敗，也正是 `-actionfile` 存在所要避免的。因此此路徑於行程內投遞，不需要
/// 輔助使用權限，也不會因應用程式未在前景而失效。
///
/// 由此帶來兩項後果，且兩者都是改進而非妥協。事件依視窗編號定址，因此重放不會像在其他平台上「太早
/// 開始」那樣外洩至別的應用程式。而由於 AppKit 是從事件本身而非硬體讀取修飾鍵狀態，動作檔按住的
/// 修飾鍵在此處追蹤（見 ``heldModifiers``），而不交由系統處理。
public final class AppKitSynthesiser: Synthesiser, @unchecked Sendable {
    /// Modifiers the file is currently holding down.
    ///
    /// Needed because nothing else tracks them. `SendInput` and XTEST post real
    /// key events and the system maintains the modifier state that later events
    /// inherit; a posted `NSEvent` carries its own `modifierFlags` and inherits
    /// nothing, so `keyDown(shift)` followed by `key(a)` would produce a plain
    /// "a" unless the flag is remembered and applied here.
    ///
    /// Guarded by a lock because `Synthesiser` is `Sendable` and a replay runs
    /// off the main thread.
    ///
    /// 之所以需要，是因為沒有別的東西在追蹤它們。`SendInput` 與 XTEST 投遞的是真實按鍵事件，由
    /// 系統維護修飾鍵狀態供後續事件繼承；而被 post 的 `NSEvent` 自帶 `modifierFlags` 且不繼承
    /// 任何狀態，因此若不在此記住並套用該旗標，`keyDown(shift)` 之後的 `key(a)` 只會產生一個普通的
    /// 「a」。
    ///
    /// 以鎖保護，因為 `Synthesiser` 是 `Sendable`，且重放在非主執行緒上執行。
    private let lock = NSLock()
    private var heldModifiers: NSEvent.ModifierFlags = []

    /// Where the file has moved the pointer to, in window coordinates.
    ///
    /// Tracked because nothing else does. `SendInput` and XTEST move the real
    /// cursor, so "where the pointer is" is a question the system can answer;
    /// posting an `NSEvent` moves nothing, so a `click` with no position of its
    /// own would fall back to wherever the user physically left the mouse --
    /// which is not where the file's last `move` put it, and is a click landing
    /// somewhere the file never named.
    ///
    /// `nil` until the file moves or clicks somewhere, which is the only point
    /// at which the real cursor is the honest answer.
    ///
    /// 之所以追蹤，是因為沒有別的東西在做這件事。`SendInput` 與 XTEST 會移動真實游標，因此「指標
    /// 在哪裡」是系統回答得出的問題；而 post 一個 `NSEvent` 不會移動任何東西，於是自身不帶座標的
    /// `click` 會退回到使用者實際把滑鼠留在的位置——那並非檔案上一次 `move` 所指之處，而是一次落在
    /// 檔案從未指名之處的點擊。
    ///
    /// 在檔案首次移動或點擊之前為 `nil`，而那也是「以真實游標為答案」唯一誠實的時刻。
    private var lastPoint: NSPoint?

    public init() {}

    /// The user's own double-click interval, read live.
    ///
    /// `NSEvent.doubleClickInterval` is in seconds and is a main-thread-ish
    /// AppKit read, so it is fetched on the main queue like everything else
    /// here.
    /// 使用者自身的雙擊間隔，即時讀取。`NSEvent.doubleClickInterval` 以秒為單位，且屬於 AppKit
    /// 的讀取，因此與此處其他操作一樣在主佇列上取得。
    public var doubleClickInterval: Int {
        onMain { Int(NSEvent.doubleClickInterval * 1_000_000) }
    }

    // MARK: - Geometry

    /// Where this process's key window is.
    ///
    /// Its own window, not the focused one. The other two synthesisers have to
    /// ask the system which window is focused because they post system-wide;
    /// this one addresses a window by number, so the window it will post to is
    /// the window it measures, and the two cannot disagree.
    ///
    /// 取得的是自身的視窗，而非「當前具有焦點的視窗」。另外兩個 synthesiser 因為是系統層級投遞，
    /// 必須詢問系統哪個視窗具有焦點；而此處依視窗編號定址，因此「將投遞至的視窗」與「所量測的
    /// 視窗」是同一個，兩者不可能不一致。
    public func currentWindowGeometry() throws -> WindowGeometry {
        try onMain {
            guard let window = Self.targetWindow() else {
                throw SynthesiserError.unsupported("no window to replay against")
            }
            let content = window.contentView.map { window.convertToScreen($0.frame) } ?? window.frame
            return WindowGeometry(
                frameOrigin: Self.topLeft(of: window.frame),
                clientOrigin: Self.topLeft(of: content),
                // Points, not pixels. The other two convert to physical pixels
                // because SendInput and XTEST address the display in pixels;
                // AppKit's event and screen coordinates are both in points, and
                // multiplying by backingScaleFactor here would land every click
                // at twice its intended offset on a Retina display.
                // 使用「點」而非「像素」。另外兩者轉換為實體像素，是因為 SendInput 與 XTEST 以
                // 像素定址顯示器；而 AppKit 的事件座標與螢幕座標都以點為單位，此處若再乘上
                // backingScaleFactor，在 Retina 顯示器上每次點擊都會落在預期偏移量的兩倍處。
                scale: 1
            )
        }
    }

    /// The window a replay drives.
    ///
    /// Key window first, because keyboard events go to it and a file that types
    /// must agree with where AppKit will route the text. Falling back to the
    /// first visible window covers the moment just after launch, before the
    /// window has been made key.
    /// 重放所驅動的視窗。優先取 key window，因為鍵盤事件會送往它，而會輸入文字的檔案必須與 AppKit
    /// 實際的文字路由一致。退回至第一個可見視窗，是為了涵蓋啟動後、視窗尚未成為 key 的那一刻。
    @MainActor
    private static func targetWindow() -> NSWindow? {
        NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible }
    }

    /// AppKit screen coordinates put `0,0` at the bottom-left of the primary
    /// screen and grow upwards; ``WindowGeometry`` is written top-left-origin,
    /// downwards, like the other two platforms. This is the only place the two
    /// meet.
    ///
    /// The reference edge is the primary screen's top, and it cancels: geometry
    /// is measured against it here and unwound against it in ``windowPoint``,
    /// so a wrong reference would still land on the right control. It is named
    /// correctly anyway, because a caller may supply its own geometry.
    ///
    /// AppKit 的螢幕座標以主螢幕左下角為 `0,0` 且向上增長；``WindowGeometry`` 則如同另外兩個平台，
    /// 以左上角為原點、向下增長。此處是兩者唯一交會之處。
    ///
    /// 參考邊為主螢幕頂端，而它會相互抵消：幾何資訊在此依它量測，並在 ``windowPoint`` 中依它還原，
    /// 因此即使參考取錯，仍會落在正確的控制項上。儘管如此仍取正確的值，因為呼叫端可能自行提供幾何。
    @MainActor
    private static func topLeft(of rect: NSRect) -> (x: Double, y: Double) {
        (x: Double(rect.minX), y: Double(primaryScreenTop() - rect.maxY))
    }

    @MainActor
    private static func primaryScreenTop() -> CGFloat {
        NSScreen.screens.first?.frame.maxY ?? 0
    }

    /// An action file's point, in the window coordinates `NSEvent` wants.
    ///
    /// Verified against a two-button window before this file existed: with the
    /// content view 200pt tall, client `(150, 40)` resolved to window
    /// `(150, 160)` and hit the top button, and client `(150, 160)` resolved to
    /// `(150, 40)` and hit the bottom one.
    /// 動作檔中的座標，轉換為 `NSEvent` 所需的視窗座標。在本檔存在之前已對一個雙按鈕視窗驗證：
    /// content view 高 200pt 時，client `(150, 40)` 解析為視窗座標 `(150, 160)` 並命中上方按鈕，
    /// client `(150, 160)` 解析為 `(150, 40)` 並命中下方按鈕。
    @MainActor
    private static func windowPoint(
        for point: Point,
        in geometry: WindowGeometry,
        window: NSWindow
    ) -> NSPoint {
        let screen = geometry.screenPosition(of: point)
        return window.convertPoint(
            fromScreen: NSPoint(
                x: Double(screen.x),
                y: Double(primaryScreenTop()) - Double(screen.y)
            )
        )
    }

    // MARK: - Performing

    public func perform(_ action: InputAction, in geometry: WindowGeometry) throws {
        // Sleeping stays on the calling thread. Hopping to the main queue for it
        // would make the application sleep too, which is the failure the
        // protocol's own documentation records.
        // 睡眠留在呼叫端執行緒。若為此跳到主佇列，應用程式也會一併睡著，而那正是本協定文件所記載的
        // 那個失敗。
        if case .sleep(let microseconds) = action {
            Thread.sleep(forTimeInterval: Double(microseconds) / 1_000_000)
            return
        }

        if case .doubleClick(let button, let point) = action {
            try performDoubleClick(button, at: point, in: geometry)
            return
        }

        try onMain {
            guard let window = Self.targetWindow() else {
                throw SynthesiserError.unsupported("no window to replay against")
            }

            // The pointer position a positionless click uses. AppKit has no
            // notion of "where the last synthesised event was", so it is read
            // back from the window rather than remembered: whatever the file
            // last moved to is where the cursor now is.
            // 無座標點擊所使用的指標位置。AppKit 沒有「上一個合成事件在哪裡」的概念，因此改為自
            // 視窗讀回，而非自行記憶：檔案最後移動到的位置，就是游標現在所在之處。
            @MainActor func location(_ point: Point?) -> NSPoint {
                guard let point else {
                    return self.trackedPoint() ?? window.mouseLocationOutsideOfEventStream
                }
                let resolved = Self.windowPoint(for: point, in: geometry, window: window)
                self.track(resolved)
                return resolved
            }

            switch action {
                case .move(let point):
                    try self.postMouse(.mouseMoved, .left, at: location(point), in: window, clicks: 0)

                case .click(let button, let point):
                    let at = location(point)
                    try self.postMouse(Self.downType(button), button, at: at, in: window, clicks: 1)
                    try self.postMouse(Self.upType(button), button, at: at, in: window, clicks: 1)

                case .mouseDown(let button, let point):
                    try self.postMouse(
                        Self.downType(button), button, at: location(point), in: window, clicks: 1)

                case .mouseUp(let button, let point):
                    try self.postMouse(
                        Self.upType(button), button, at: location(point), in: window, clicks: 1)

                case .keyDown(let key):
                    self.hold(key)
                    try self.postKey(key, down: true, in: window)

                case .keyUp(let key):
                    try self.postKey(key, down: false, in: window)
                    self.release(key)

                case .key(let key):
                    try self.postKey(key, down: true, in: window)
                    try self.postKey(key, down: false, in: window)

                case .scroll(let dx, let dy):
                    try self.postScroll(dx: dx, dy: dy, at: location(nil), in: window)

                case .doubleClick, .sleep:
                    // Both returned above; listed so a new case cannot be added
                    // without the compiler pointing here.
                    // 兩者皆已於上方返回；在此列出，是為了讓新增 case 時編譯器必定指向此處。
                    break
            }
        }
    }

    // MARK: - Mouse

    private static func downType(_ button: MouseButton) -> NSEvent.EventType {
        switch button {
            case .left: .leftMouseDown
            case .right: .rightMouseDown
            case .middle: .otherMouseDown
        }
    }

    private static func upType(_ button: MouseButton) -> NSEvent.EventType {
        switch button {
            case .left: .leftMouseUp
            case .right: .rightMouseUp
            case .middle: .otherMouseUp
        }
    }

    private static func buttonNumber(_ button: MouseButton) -> Int {
        switch button {
            case .left: 0
            case .right: 1
            case .middle: 2
        }
    }

    @MainActor
    private func postMouse(
        _ type: NSEvent.EventType,
        _ button: MouseButton,
        at location: NSPoint,
        in window: NSWindow,
        clicks: Int
    ) throws {
        guard
            let event = NSEvent.mouseEvent(
                with: type,
                location: location,
                modifierFlags: currentModifiers(),
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: clicks,
                // A zero-pressure mouseDown is a mouseDown that some controls
                // decline to act on; the paired up event is zero by convention.
                // 壓力為零的 mouseDown 會被部分控制項拒絕處理；成對的 up 事件依慣例為零。
                pressure: type == Self.downType(button) ? 1 : 0
            )
        else {
            throw SynthesiserError.unsupported("could not construct \(type) event")
        }

        // otherMouse events carry which button they mean in buttonNumber, which
        // NSEvent.mouseEvent cannot set; middle-click therefore goes through
        // CGEvent, whose NSEvent bridge preserves it.
        // otherMouse 事件以 buttonNumber 表示它指的是哪個按鍵，而 NSEvent.mouseEvent 無法設定它；
        // 因此中鍵改走 CGEvent，其 NSEvent 橋接會保留該欄位。
        if button == .middle, let bridged = middleClickEvent(from: event, type: type, in: window) {
            NSApp.postEvent(bridged, atStart: false)
        } else {
            NSApp.postEvent(event, atStart: false)
        }
    }

    @MainActor
    private func middleClickEvent(
        from event: NSEvent,
        type: NSEvent.EventType,
        in window: NSWindow
    ) -> NSEvent? {
        guard let cg = event.cgEvent else { return nil }
        cg.setIntegerValueField(.mouseEventButtonNumber, value: 2)
        return NSEvent(cgEvent: cg)
    }

    /// Delivers a wheel turn to the view under the file's pointer.
    ///
    /// The only verb that does not go through `NSApp.postEvent`, because it
    /// cannot. `NSEvent` has no scroll-wheel constructor, so the event has to be
    /// built as a `CGEvent` and bridged -- and a bridged event carries
    /// `windowNumber == 0`, which `sendEvent:` has no window to route to.
    /// Measured: posted that way, with the location set correctly and even with
    /// the real cursor warped on top of the target, an `NSScrollView` under the
    /// point received nothing at all. Hit-testing and calling `scrollWheel(with:)`
    /// delivers, and the same scroll view moved from offset 0 to 50.
    ///
    /// Two honest consequences. The delivery skips the event queue, so a scroll
    /// can overtake a click posted immediately before it -- action files put
    /// `sleep` rows between steps anyway, and the module's README already asks
    /// for them. And `locationInWindow` on the delivered event is whatever the
    /// bridge produced rather than the target point; scroll views read the
    /// deltas, which are correct.
    ///
    /// 唯一不經由 `NSApp.postEvent` 的動作，因為它辦不到。`NSEvent` 沒有滾輪事件的建構子，因此該
    /// 事件必須以 `CGEvent` 建構再橋接——而橋接後的事件其 `windowNumber == 0`，`sendEvent:` 沒有
    /// 可路由的視窗。實測：以該方式投遞，即使正確設定了位置、甚至把真實游標移到目標之上，位於該點
    /// 下方的 `NSScrollView` 仍然什麼也沒收到。改以 hit-test 並呼叫 `scrollWheel(with:)` 即可送達，
    /// 同一個 scroll view 的偏移量由 0 移動到 50。
    ///
    /// 兩項需要誠實說明的後果。此路徑略過事件佇列，因此一次捲動可能超前緊接在它之前 post 的點擊
    /// ——動作檔本來就會在步驟之間放置 `sleep` 列，本模組的 README 亦已如此要求。另外，送達事件的
    /// `locationInWindow` 是橋接產生的值而非目標座標；scroll view 讀取的是 delta，而那是正確的。
    @MainActor
    private func postScroll(dx: Int, dy: Int, at point: NSPoint, in window: NSWindow) throws {
        guard dx != 0 || dy != 0 else { return }

        // The sign is not inverted here. `dy` is positive downwards, and
        // AppKit's line deltas use the same convention. Windows is the one that
        // has to negate.
        // 此處不反轉符號。`dy` 以向下為正，而 AppKit 的行 delta 亦採相同慣例。需要取負的是 Windows。
        guard
            let cg = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .line,
                wheelCount: 2,
                wheel1: Int32(dy),
                wheel2: Int32(dx),
                wheel3: 0
            ),
            let event = NSEvent(cgEvent: cg)
        else {
            throw SynthesiserError.unsupported("could not construct a scroll event")
        }

        guard let hit = window.contentView?.hitTest(point) else {
            throw SynthesiserError.unsupported(
                "nothing to scroll at \(Int(point.x)),\(Int(point.y)) -- move the pointer first"
            )
        }

        // Deliver the wheel event, then check it did something, then make it
        // do something if it did not.
        //
        // The event alone is not enough, and that took measuring to establish.
        // Over a SwiftCrossUI `Text` inside a `ScrollView` the hit view is an
        // `NSTextField`, which swallows the wheel; aiming at the enclosing
        // `NSScrollView` instead did not help either -- calling
        // `scrollWheel(with:)` directly on it left its offset at 0 through four
        // notches. The scroll view was scrollable the whole time: its document
        // was 1078pt tall inside a 100pt clip, and `contentView.scroll(to:)`
        // moved it immediately. So AppKit's scroll views act on wheel events
        // from the window server, not on a synthesised one handed to them.
        //
        // The event is still delivered first, because a view with its own
        // `scrollWheel` override is entitled to see it, and that is the case
        // the compensation must not pre-empt. Then the clip view is checked,
        // and moved only if it did not move on its own -- so a scroll view that
        // does honour the event is not scrolled twice.
        //
        // 先送出滾輪事件，再檢查它是否起了作用，若無作用則使其起作用。
        //
        // 僅靠事件本身並不足夠，而這一點是實測得出的。在 `ScrollView` 內的 SwiftCrossUI `Text` 上，
        // hit view 是會吞掉滾輪事件的 `NSTextField`；改為瞄準外圍的 `NSScrollView` 亦無濟於事——
        // 直接對其呼叫 `scrollWheel(with:)`，四格捲動之後偏移量仍為 0。該 scroll view 自始至終都是
        // 可捲動的：其 document 高 1078pt、clip 僅 100pt，而 `contentView.scroll(to:)` 立即使其移動。
        // 因此 AppKit 的 scroll view 所回應的是來自 window server 的滾輪事件，而非交到它手上的合成事件。
        //
        // 仍先送出該事件，因為自行覆寫了 `scrollWheel` 的 view 有權看到它，而那正是補償機制不得搶先
        // 介入的情況。隨後檢查 clip view，僅在它未自行移動時才移動它——如此一來，確實會回應該事件的
        // scroll view 不會被捲動兩次。
        let scrollView = hit.enclosingScrollView
        let before = scrollView?.contentView.bounds.origin

        hit.scrollWheel(with: event)

        if let scrollView, let before, scrollView.contentView.bounds.origin == before {
            // Lines to points, using the scroll view's own line height rather
            // than a number chosen here, so a file scrolls by as much as a real
            // notch would in that view.
            // 由「行」換算為「點」，採用該 scroll view 自身的行高而非此處自訂的數字，使動作檔捲動的
            // 幅度與該 view 中真實的一格相同。
            let target = NSPoint(
                x: before.x + Double(dx) * scrollView.horizontalLineScroll,
                y: before.y + Double(dy) * scrollView.verticalLineScroll
            )
            scrollView.contentView.scroll(to: target)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    // MARK: - Keyboard

    @MainActor
    private func postKey(_ key: Key, down: Bool, in window: NSWindow) throws {
        guard let code = Self.virtualKeyCode(for: key) else {
            throw SynthesiserError.unsupported("key '\(key.rawValue)'")
        }

        let modifiers = currentModifiers()

        // A modifier key is a flagsChanged event, not a keyDown. Posting it as
        // a keyDown gives a control a keystroke it cannot interpret, and gives
        // nothing the flag change it is watching for.
        // 修飾鍵是 flagsChanged 事件，而非 keyDown。若以 keyDown 投遞，控制項會收到一個它無法解讀
        // 的按鍵，而真正在等待旗標變化的一方則什麼也收不到。
        if Self.modifierFlag(for: key) != nil {
            guard
                let event = NSEvent.keyEvent(
                    with: .flagsChanged,
                    location: .zero,
                    modifierFlags: modifiers,
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber,
                    context: nil,
                    characters: "",
                    charactersIgnoringModifiers: "",
                    isARepeat: false,
                    keyCode: code
                )
            else {
                throw SynthesiserError.unsupported("could not construct a flagsChanged event")
            }
            NSApp.postEvent(event, atStart: false)
            return
        }

        let characters = Self.characters(for: code, modifiers: modifiers)
        let bare = Self.characters(for: code, modifiers: modifiers.subtracting(.shift))

        guard
            let event = NSEvent.keyEvent(
                with: down ? .keyDown : .keyUp,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: bare,
                isARepeat: false,
                keyCode: code
            )
        else {
            throw SynthesiserError.unsupported("could not construct a key event")
        }
        NSApp.postEvent(event, atStart: false)
    }

    /// What the key produces on the user's actual keyboard layout.
    ///
    /// Translated rather than tabulated. A hard-coded "kVK_ANSI_A means a" is
    /// true on a US layout and false on several others, and a file that types
    /// into a text field would then insert the wrong character on a machine
    /// nobody tested on -- silently, since the keystroke still arrives.
    /// `UCKeyTranslate` asks the layout that is actually installed.
    ///
    /// 採用轉換而非查表。寫死「kVK_ANSI_A 即 a」在 US 佈局上成立，在若干其他佈局上並不成立；
    /// 而會向文字欄位輸入的動作檔，便會在無人測試過的機器上插入錯誤的字元——且是靜默的，因為按鍵
    /// 本身仍然送達。`UCKeyTranslate` 詢問的是實際安裝的佈局。
    private static func characters(
        for code: CGKeyCode,
        modifiers: NSEvent.ModifierFlags
    ) -> String {
        guard
            let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else {
            return ""
        }

        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 8)

        // Carbon's modifier field is the old event-record layout: the flags sit
        // in the high byte, hence the shift by 8.
        // Carbon 的修飾鍵欄位沿用舊的 event record 佈局：旗標位於高位元組，故右移 8 位。
        var carbonModifiers: UInt32 = 0
        if modifiers.contains(.shift) { carbonModifiers |= UInt32(shiftKey >> 8) }
        if modifiers.contains(.option) { carbonModifiers |= UInt32(optionKey >> 8) }
        if modifiers.contains(.capsLock) { carbonModifiers |= UInt32(alphaLock >> 8) }

        let status = data.withUnsafeBytes { buffer -> OSStatus in
            guard let base = buffer.baseAddress else { return -1 }
            return UCKeyTranslate(
                base.assumingMemoryBound(to: UCKeyboardLayout.self),
                code,
                UInt16(kUCKeyActionDown),
                carbonModifiers,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
        }

        guard status == noErr, length > 0 else { return "" }
        return String(utf16CodeUnits: characters, count: length)
    }

    // MARK: - Modifier state

    private func hold(_ key: Key) {
        guard let flag = Self.modifierFlag(for: key) else { return }
        lock.lock()
        heldModifiers.insert(flag)
        lock.unlock()
    }

    private func release(_ key: Key) {
        guard let flag = Self.modifierFlag(for: key) else { return }
        lock.lock()
        heldModifiers.remove(flag)
        lock.unlock()
    }

    private func track(_ point: NSPoint) {
        lock.lock()
        lastPoint = point
        lock.unlock()
    }

    private func trackedPoint() -> NSPoint? {
        lock.lock()
        defer { lock.unlock() }
        return lastPoint
    }

    private func currentModifiers() -> NSEvent.ModifierFlags {
        lock.lock()
        defer { lock.unlock() }
        return heldModifiers
    }

    private static func modifierFlag(for key: Key) -> NSEvent.ModifierFlags? {
        switch key {
            case .shift, .rightShift: .shift
            case .control, .rightControl: .control
            case .option, .rightOption: .option
            case .command, .rightCommand: .command
            case .capsLock: .capsLock
            case .function: .function
            default: nil
        }
    }

    // MARK: - Key codes

    /// `Key` to the Carbon virtual key code of the same name.
    ///
    /// The enum's cases are documented as being the `kVK_*` constants with the
    /// prefix dropped, so this reads the constants rather than repeating their
    /// numbers: a table of 90 hand-copied integers is a table with a typo in
    /// it, and the typo would present as one key in a file doing nothing.
    ///
    /// 由 `Key` 對應至同名的 Carbon 虛擬鍵碼。該列舉的 case 已載明為去除前綴的 `kVK_*` 常數，
    /// 因此此處直接引用常數而非複寫其數值：一張 90 個手抄整數的表，就是一張含有錯字的表，而該錯字
    /// 的表現形式會是「動作檔中的某一個按鍵毫無作用」。
    private static func virtualKeyCode(for key: Key) -> CGKeyCode? {
        let code: Int
        switch key {
            case .a: code = kVK_ANSI_A
            case .b: code = kVK_ANSI_B
            case .c: code = kVK_ANSI_C
            case .d: code = kVK_ANSI_D
            case .e: code = kVK_ANSI_E
            case .f: code = kVK_ANSI_F
            case .g: code = kVK_ANSI_G
            case .h: code = kVK_ANSI_H
            case .i: code = kVK_ANSI_I
            case .j: code = kVK_ANSI_J
            case .k: code = kVK_ANSI_K
            case .l: code = kVK_ANSI_L
            case .m: code = kVK_ANSI_M
            case .n: code = kVK_ANSI_N
            case .o: code = kVK_ANSI_O
            case .p: code = kVK_ANSI_P
            case .q: code = kVK_ANSI_Q
            case .r: code = kVK_ANSI_R
            case .s: code = kVK_ANSI_S
            case .t: code = kVK_ANSI_T
            case .u: code = kVK_ANSI_U
            case .v: code = kVK_ANSI_V
            case .w: code = kVK_ANSI_W
            case .x: code = kVK_ANSI_X
            case .y: code = kVK_ANSI_Y
            case .z: code = kVK_ANSI_Z

            case .zero: code = kVK_ANSI_0
            case .one: code = kVK_ANSI_1
            case .two: code = kVK_ANSI_2
            case .three: code = kVK_ANSI_3
            case .four: code = kVK_ANSI_4
            case .five: code = kVK_ANSI_5
            case .six: code = kVK_ANSI_6
            case .seven: code = kVK_ANSI_7
            case .eight: code = kVK_ANSI_8
            case .nine: code = kVK_ANSI_9

            case .delete: code = kVK_Delete
            case .forwardDelete: code = kVK_ForwardDelete
            case .escape: code = kVK_Escape
            case .space: code = kVK_Space
            case .tab: code = kVK_Tab
            case .return: code = kVK_Return

            case .leftArrow: code = kVK_LeftArrow
            case .rightArrow: code = kVK_RightArrow
            case .upArrow: code = kVK_UpArrow
            case .downArrow: code = kVK_DownArrow
            case .home: code = kVK_Home
            case .end: code = kVK_End
            case .pageUp: code = kVK_PageUp
            case .pageDown: code = kVK_PageDown

            case .shift: code = kVK_Shift
            case .control: code = kVK_Control
            case .option: code = kVK_Option
            case .command: code = kVK_Command
            case .rightShift: code = kVK_RightShift
            case .rightControl: code = kVK_RightControl
            case .rightOption: code = kVK_RightOption
            case .rightCommand: code = kVK_RightCommand
            case .capsLock: code = kVK_CapsLock
            case .function: code = kVK_Function

            case .f1: code = kVK_F1
            case .f2: code = kVK_F2
            case .f3: code = kVK_F3
            case .f4: code = kVK_F4
            case .f5: code = kVK_F5
            case .f6: code = kVK_F6
            case .f7: code = kVK_F7
            case .f8: code = kVK_F8
            case .f9: code = kVK_F9
            case .f10: code = kVK_F10
            case .f11: code = kVK_F11
            case .f12: code = kVK_F12
            case .f13: code = kVK_F13
            case .f14: code = kVK_F14
            case .f15: code = kVK_F15
            case .f16: code = kVK_F16
            case .f17: code = kVK_F17
            case .f18: code = kVK_F18
            case .f19: code = kVK_F19
            case .f20: code = kVK_F20

            case .keypad0: code = kVK_ANSI_Keypad0
            case .keypad1: code = kVK_ANSI_Keypad1
            case .keypad2: code = kVK_ANSI_Keypad2
            case .keypad3: code = kVK_ANSI_Keypad3
            case .keypad4: code = kVK_ANSI_Keypad4
            case .keypad5: code = kVK_ANSI_Keypad5
            case .keypad6: code = kVK_ANSI_Keypad6
            case .keypad7: code = kVK_ANSI_Keypad7
            case .keypad8: code = kVK_ANSI_Keypad8
            case .keypad9: code = kVK_ANSI_Keypad9
            case .keypadDecimal: code = kVK_ANSI_KeypadDecimal
            case .keypadPlus: code = kVK_ANSI_KeypadPlus
            case .keypadMinus: code = kVK_ANSI_KeypadMinus
            case .keypadMultiply: code = kVK_ANSI_KeypadMultiply
            case .keypadDivide: code = kVK_ANSI_KeypadDivide
            case .keypadEnter: code = kVK_ANSI_KeypadEnter
            case .keypadEquals: code = kVK_ANSI_KeypadEquals
            case .keypadClear: code = kVK_ANSI_KeypadClear
        }
        return CGKeyCode(code)
    }

    // MARK: - Threading

    /// Runs a body on the main queue and waits for it.
    ///
    /// AppKit is main-thread-only, and a replay deliberately is not: it spends
    /// nearly all its time asleep and must not do that on the UI's thread. So
    /// the sleeping stays where the replay runs and only the AppKit work hops
    /// across, which is the smallest arrangement that satisfies both.
    ///
    /// A replay already on the main thread would deadlock here, so that case is
    /// handled rather than assumed away -- it is exactly the mistake the
    /// protocol documentation warns about, and it should fail loudly if it is
    /// ever made.
    ///
    /// 在主佇列上執行並等待其完成。AppKit 僅限主執行緒，而重放刻意不在主執行緒上：它幾乎整段時間
    /// 都在睡眠，不能在 UI 執行緒上這麼做。因此睡眠留在重放所在之處，只有 AppKit 的工作跳過去，
    /// 這是同時滿足兩者的最小安排。
    ///
    /// 已在主執行緒上的重放會在此死鎖，因此該情況被實際處理而非假設不存在——那正是協定文件所警告的
    /// 錯誤，一旦發生就應該大聲失敗。
    private func onMain<T>(_ body: @MainActor () throws -> T) rethrows -> T {
        if Thread.isMainThread {
            return try MainActor.assumeIsolated(body)
        }
        return try DispatchQueue.main.sync {
            try MainActor.assumeIsolated(body)
        }
    }
}

#endif
