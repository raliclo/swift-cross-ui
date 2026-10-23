import DebugFeatures
import Foundation
@_spi(Backends) import SwiftCrossUI
import UWP
import WinAppSDK
import WinSDK
import WinUI
@preconcurrency import WindowsFoundation

// Five optional features WinUI did not declare until 2026-10-07 -- `Cursors`,
// `ContextMenus`, `KeyEvents`, `ScrollGestures`, `WidgetSnapshots` -- while
// AppKit, UIKit, Android and (since 2026-10-06) GTK had all five. Each target is
// a `Canvas` with the child at the origin and a transparent background, the
// shape `TapGestureTarget` and `HoverGestureTarget` use: the background makes
// the whole area hit-testable, and the feature belongs to the target, so two
// modifiers on one view do not overwrite each other on a shared child.
//
// WinUI 在 2026-10-07 之前沒有宣告的五項選用功能——`Cursors`、`ContextMenus`、`KeyEvents`、
// `ScrollGestures`、`WidgetSnapshots`——而 AppKit、UIKit、Android 與(自 2026-10-06 起)GTK 五項都有。
// 每個 target 都是一個子 widget 在原點、背景透明的 `Canvas`,與 `TapGestureTarget`、`HoverGestureTarget`
// 的形狀相同：背景讓整個區域都能被 hit test,而功能屬於 target,同一個 view 上的兩個 modifier 不會在
// 共用的子 widget 上互相覆寫。

extension WinUIBackend {
    fileprivate func featureTarget(wrapping child: Widget) -> WinUIFeatureTarget {
        let target = WinUIFeatureTarget()
        insert(child, into: target, at: 0)
        let brush = SolidColorBrush()
        brush.color = UWP.Color(a: 0, r: 0, g: 0, b: 0)
        target.background = brush
        return target
    }
}

// MARK: Cursors

extension WinUIBackend: BackendFeatures.Cursors {
    public func createCursorTarget(wrapping child: Widget) -> Widget {
        let target = featureTarget(wrapping: child)
        // Again once loaded: a control's template parts exist only from then.
        // 載入後再套一次：控制項的 template 零件從那時才存在。
        target.loaded.addHandler { [weak target] _, _ in
            guard let target, let shape = target.cursorShape else { return }
            Self.applyCursor(shape, under: target)
        }
        return target
    }

    public func updateCursorTarget(_ target: Widget, cursor: Cursor, environment: EnvironmentValues) {
        let target = target as! WinUIFeatureTarget
        let shape: InputSystemCursorShape =
            switch cursor {
                case .arrow: .arrow
                case .pointingHand: .hand
                case .crosshair: .cross
                case .text: .ibeam
                case .resizeHorizontal: .sizeWestEast
                case .resizeVertical: .sizeNorthSouth
                case .notAllowed: .universalNo
            }
        target.cursorShape = shape
        Self.applyCursor(shape, under: target)
    }

    /// Sets the cursor on `element` and on every element under it, stopping
    /// at a nested cursor target, which keeps its own.
    ///
    /// `ProtectedCursor` is protected in C# and public in this binding. With
    /// this subtree walk, P80's six labels showed hand, cross, I-beam, both
    /// resize arrows and "no" (read with `GetCursorInfo`, 2026-10-07).
    ///
    /// NOT SETTLED: whether the target alone would have been enough. The run
    /// that showed the arrow with the target-only version had its input
    /// silently dropped by an elevated window in front (see
    /// testapp/enable_input.zsh), and the clean rerun of that version was
    /// blocked the same way. The walk is kept because it is the version that
    /// was seen working.
    ///
    /// 在 `element` 及其底下每個元素上設定游標，遇到巢狀的游標 target 就停，讓它保留自己的游標。
    /// `ProtectedCursor` 在 C# 中是 protected,此 binding 中為 public。用這個子樹走訪時，P80 的六個標籤分別顯示
    /// 手形、十字、I 形、兩種調整大小箭頭與「禁止」(2026-10-07 以 `GetCursorInfo` 讀得)。
    /// **尚未確定：**只設在 target 上是否就夠了。顯示箭頭的那次「只設 target」執行，輸入被前方一個提權視窗
    /// 無聲丟棄(見 testapp/enable_input.zsh),而該版本的乾淨重跑也同樣被擋住。保留走訪，因為它是被看到有效的版本。
    static func applyCursor(_ shape: InputSystemCursorShape, under element: WinUI.UIElement) {
        element.protectedCursor = InputSystemCursor.create(shape)
        for child in scuiChildren(of: element) {
            if let nested = child as? WinUIFeatureTarget, nested.cursorShape != nil { continue }
            applyCursor(shape, under: child)
        }
    }
}

// MARK: Context menus

extension WinUIBackend: BackendFeatures.ContextMenus {
    public func createContextMenuTarget(wrapping child: Widget) -> Widget {
        featureTarget(wrapping: child)
    }

    public func updateContextMenuTarget(
        _ target: Widget,
        menu: ResolvedMenu,
        environment: EnvironmentValues
    ) {
        // `ContextFlyout` rather than a `rightTapped` handler: WinUI opens it
        // at the pointer for a right click, a touch or pen hold, and the
        // keyboard's context-menu key or Shift+F10 -- every way Windows asks
        // for a context menu, which a handler would have to rebuild one by one.
        // 用 `ContextFlyout`,而不是 `rightTapped` handler:WinUI 會在右鍵、觸控或觸控筆長按、鍵盤的選單鍵或
        // Shift+F10 時於指標處開啟它——Windows 要求內容選單的每一種方式，用 handler 就得一一重寫。
        let target = target as! WinUIFeatureTarget
        guard environment.isEnabled else {
            target.contextFlyout = nil
            return
        }
        let flyout = target.menuFlyout ?? MenuFlyout()
        target.menuFlyout = flyout
        updatePopoverMenu(flyout, content: menu, environment: environment)
        target.contextFlyout = flyout
    }
}

// MARK: Key events

extension WinUIBackend: BackendFeatures.KeyEvents {
    public func createKeyEventTarget(wrapping child: Widget) -> Widget {
        let target = featureTarget(wrapping: child)
        target.isTabStop = true
        // Focus when shown, as AppKitBackend claims first responder and
        // GtkBackend grabs focus once mapped: a key handler that waits for a
        // click before it hears anything looks like one that never works.
        // A click inside takes it back, since a Canvas is not focused by one.
        //
        // Both on the NEXT turn of the main queue. A `ScrollViewer` above the
        // target -- the window's root scroll view -- focuses itself in its own
        // `PointerPressed`, which runs after ours as the event bubbles, and
        // initial focus is assigned after `Loaded`. Focusing inside the
        // handler returned true and lost: half a second later P80's focused
        // element was that ScrollViewer, and keys never passed the target
        // (measured 2026-10-07, 0 key events).
        //
        // 顯示時取得焦點，與 AppKitBackend 取得 first responder、GtkBackend 在 map 後取得焦點相同：要先點一下才
        // 聽得到按鍵的處理器，看起來就像從來不會動。在內部點擊會把焦點取回，因為 Canvas 不會因點擊而獲得焦點。
        // 兩者都在主佇列的**下一輪**才做。target 上方的 `ScrollViewer`(視窗的根捲動 view)會在自己的
        // `PointerPressed` 裡取得焦點，而那在事件冒泡時排在我們之後執行；初始焦點也是在 `Loaded` 之後才指定。
        // 在 handler 裡直接 focus 會回傳 true 卻輸掉：半秒後 P80 的焦點元素是那個 ScrollViewer,按鍵從未
        // 經過 target(2026-10-07 實測，按鍵事件為 0)。
        target.loaded.addHandler { [weak target] _, _ in
            DispatchQueue.main.async { [weak target] in
                guard let target, target.keyEventsEnabled else { return }
                // Around a `.focusable()` view the keys are that view's, and this
                // target is neither focused nor a Tab stop -- GtkBackend does the
                // same (holdsFocusableTarget). Measured 2026-10-19 on P91: with
                // both targets taking the focus on a press, "focus changes heard"
                // reached 20 after two presses, B heard nothing, and the app stopped
                // answering on the next button.
                // 包著 `.focusable()` 的 view 時，按鍵屬於那個 view,本 target 既不取得焦點也不是 Tab 停駐點——
                // GtkBackend 也是這樣(holdsFocusableTarget)。2026-10-19 於 P91 實測：兩個 target 都在按下時搶焦點，
                // 按兩下後「focus changes heard」到了 20,B 什麼都沒聽到，接著 app 在下一個按鈕停止回應。
                if Self.focusableTarget(in: target) != nil {
                    target.isTabStop = false
                    return
                }
                _ = try? target.focus(.programmatic)
            }
        }
        target.pointerPressed.addHandler { [weak target] _, _ in
            DispatchQueue.main.async { [weak target] in
                guard let target, target.keyEventsEnabled,
                    Self.focusableTarget(in: target) == nil
                else { return }
                _ = try? target.focus(.pointer)
            }
        }
        target.keyDown.addHandler { [weak target] _, args in
            guard let target, let args, target.keyEventsEnabled else { return }
            // VK_PACKET carries a character with no key behind it -- the touch
            // keyboard, an IME, SendInput with KEYEVENTF_UNICODE -- so the
            // layout cannot translate it; the character arrives next, in
            // CharacterReceived. P80 counted 0 events for typed text until this.
            // VK_PACKET 帶的是背後沒有按鍵的字元——觸控鍵盤、輸入法、以 KEYEVENTF_UNICODE 呼叫的 SendInput——
            // 鍵盤配置無法轉換它；字元接著在 CharacterReceived 中到達。在此之前 P80 打字時計數為 0。
            if Int32(args.key.rawValue) == VK_PACKET {
                target.awaitingPacketCharacter = true
                return
            }
            let phase: KeyPress.Phase = args.keyStatus.wasKeyDown ? .repeat : .down
            if Self.report(args.key, scanCode: args.keyStatus.scanCode, phase: phase, target.onKey) {
                args.handled = true
            }
        }
        target.characterReceived.addHandler { [weak target] _, args in
            guard let target, let args, target.awaitingPacketCharacter else { return }
            target.awaitingPacketCharacter = false
            let character = args.character
            target.packetCharacter = character
            target.onKey?(
                KeyPress(
                    key: KeyEquivalent(character),
                    characters: String(character),
                    modifiers: Self.currentModifiers(),
                    phase: .down
                )
            )
            args.handled = true
        }
        target.keyUp.addHandler { [weak target] _, args in
            guard let target, let args, target.keyEventsEnabled else { return }
            if Int32(args.key.rawValue) == VK_PACKET {
                guard let character = target.packetCharacter else { return }
                target.packetCharacter = nil
                target.onKey?(
                    KeyPress(
                        key: KeyEquivalent(character),
                        characters: String(character),
                        modifiers: Self.currentModifiers(),
                        phase: .up
                    )
                )
                args.handled = true
                return
            }
            if Self.report(args.key, scanCode: args.keyStatus.scanCode, phase: .up, target.onKey) {
                args.handled = true
            }
        }
        return target
    }

    public func updateKeyEventTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        onKey: @escaping (KeyPress) -> Void
    ) {
        let target = target as! WinUIFeatureTarget
        target.keyEventsEnabled = environment.isEnabled
        target.onKey = onKey
    }

    /// One key event as a `KeyPress`. A modifier key alone reports `key: nil`
    /// with the modifiers as they are after the event, as AppKit's
    /// `flagsChanged` and GtkBackend do.
    /// 把一個按鍵事件轉成 `KeyPress`。單獨的修飾鍵回報 `key: nil`,修飾鍵狀態為事件之後的狀態，與 AppKit 的
    /// `flagsChanged` 及 GtkBackend 相同。
    static func report(
        _ virtualKey: UWP.VirtualKey,
        scanCode: UInt32,
        phase: KeyPress.Phase,
        _ onKey: ((KeyPress) -> Void)?
    ) -> Bool {
        guard let onKey else { return false }
        let vk = Int32(virtualKey.rawValue)
        var modifiers = currentModifiers()
        if let modifier = modifierKey(vk) {
            if phase == .up { modifiers.remove(modifier) } else { modifiers.insert(modifier) }
            onKey(KeyPress(key: nil, characters: "", modifiers: modifiers, phase: phase))
            return true
        }
        let characters = Self.characters(vk: vk, scanCode: scanCode)
        let key: KeyEquivalent? = namedKey(vk) ?? characters.first.map { KeyEquivalent($0) }
        guard let key else { return false }
        onKey(KeyPress(key: key, characters: characters, modifiers: modifiers, phase: phase))
        return true
    }

    /// The text the key types, through the active keyboard layout, with Shift
    /// applied but Control and Alt left out -- GDK's keyval and AppKit's
    /// `charactersIgnoringModifiers` both give "a" for Control+A, not U+0001.
    /// AltGr (Control and Alt together) is kept, since that is how many
    /// layouts type "@" or "€". Flag 4 leaves the dead-key state untouched.
    /// 這個按鍵經目前鍵盤配置打出的文字，套用 Shift、但不含 Control 與 Alt——GDK 的 keyval 與 AppKit 的
    /// `charactersIgnoringModifiers` 對 Control+A 都給 "a",而非 U+0001。AltGr(Control 與 Alt 同時按下)保留，
    /// 因為許多配置正是以它打出「@」或「€」。旗標 4 讓 dead key 狀態不受影響。
    static func characters(vk: Int32, scanCode: UInt32) -> String {
        var state = [UInt8](repeating: 0, count: 256)
        guard GetKeyboardState(&state) else { return "" }
        let isAltGr = state[Int(VK_CONTROL)] & 0x80 != 0 && state[Int(VK_MENU)] & 0x80 != 0
        if !isAltGr {
            for code in [VK_CONTROL, VK_LCONTROL, VK_RCONTROL, VK_MENU, VK_LMENU, VK_RMENU] {
                state[Int(code)] = 0
            }
        }
        var buffer = [WCHAR](repeating: 0, count: 8)
        let count = ToUnicode(UINT(vk), UINT(scanCode), state, &buffer, Int32(buffer.count), 4)
        guard count > 0 else { return "" }
        let text = String(decoding: buffer[0..<Int(count)], as: UTF16.self)
        // Control characters (Tab, Return, Escape, Backspace) are named keys,
        // not text. 控制字元(Tab、Return、Escape、Backspace)是具名按鍵，不是文字。
        return text.unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value != 0x7F } ? text : ""
    }

    /// Control is `.control`, the Windows key `.command`, Alt `.option`, as
    /// GtkBackend reports Super. 與 GtkBackend 回報 Super 的方式相同。
    static func currentModifiers() -> EventModifiers {
        func isDown(_ key: Int32) -> Bool { GetKeyState(key) < 0 }
        var modifiers: EventModifiers = []
        if isDown(VK_CONTROL) { modifiers.insert(.control) }
        if isDown(VK_SHIFT) { modifiers.insert(.shift) }
        if isDown(VK_MENU) { modifiers.insert(.option) }
        if isDown(VK_LWIN) || isDown(VK_RWIN) { modifiers.insert(.command) }
        return modifiers
    }

    static func modifierKey(_ vk: Int32) -> EventModifiers? {
        switch vk {
            case VK_SHIFT, VK_LSHIFT, VK_RSHIFT: .shift
            case VK_CONTROL, VK_LCONTROL, VK_RCONTROL: .control
            case VK_MENU, VK_LMENU, VK_RMENU: .option
            case VK_LWIN, VK_RWIN: .command
            default: nil
        }
    }

    static func namedKey(_ vk: Int32) -> KeyEquivalent? {
        switch vk {
            case VK_UP: .upArrow
            case VK_DOWN: .downArrow
            case VK_LEFT: .leftArrow
            case VK_RIGHT: .rightArrow
            case VK_ESCAPE: .escape
            case VK_BACK: .delete
            case VK_DELETE: .deleteForward
            case VK_HOME: .home
            case VK_END: .end
            case VK_PRIOR: .pageUp
            case VK_NEXT: .pageDown
            case VK_CLEAR: .clear
            case VK_TAB: .tab
            case VK_RETURN: .return
            case VK_SPACE: .space
            default: nil
        }
    }
}

// MARK: Pointer hover

/// Written on macOS 2026-10-10; built and driven on Windows 2026-10-20 with P88, whose replay must
/// use `hover` rows: a `move` without a button is a SetCursorPos jump and raises no PointerMoved.
///
/// The pointer's place comes from `PointerMoved` and the modifiers from the key state at that
/// moment, read the way key events read them: Control is `.control` and the Windows key `.command`.
/// An app that means "the platform's command key" has to accept `.control` here, as SoftPCB does.
/// A modifier pressed while the pointer rests is reported at the next move, not at once -- the
/// same limit as GtkBackend; only AppKitBackend reports it without a move.
///
/// A finger hovers once it has rested for `touchHoverDelay` within `touchHoverSlop`, and from then
/// until it lifts, as GtkBackend, UIKit and Android do (queue item 10). Before this (2026-10-23)
/// every touch move was a hover at once: a quick touch drag across P88's panel reported 20 hovers,
/// measured with `touch_gesture.zsh drag`; `hold` drives the rest-then-move case.
///
/// 2026-10-10 在 macOS 上寫成，2026-10-20 在 Windows 以 P88 建置並驅動；重放須用 `hover` 列——沒按鍵的 `move` 是 SetCursorPos
/// 跳躍，不會觸發 PointerMoved。指標位置來自 `PointerMoved`，修飾鍵取當下的按鍵狀態，讀法與按鍵事件相同：Control 是
/// `.control`、Windows 鍵是 `.command`。想表示「這個平台的 command 鍵」的 app 在這裡得接受 `.control`，
/// SoftPCB 就是這樣。指標不動時按下修飾鍵，要到下一次移動才回報——與 GtkBackend 相同的限制，只有
/// AppKitBackend 不必移動就回報。
///
/// 手指在 `touchHoverSlop` 內靜止 `touchHoverDelay` 後開始 hover,直到抬起，與 GtkBackend、UIKit、Android 相同
/// (queue 第 10 項)。在此之前(2026-10-23)每次觸控移動都立即算 hover:用 `touch_gesture.zsh drag` 量到，快速觸控
/// 拖過 P88 的面板回報了 20 次;`hold` 驅動先靜止再移動的情形。
extension WinUIBackend: BackendFeatures.PointerHover {
    public func createPointerHoverTarget(wrapping child: Widget) -> Widget {
        let target = featureTarget(wrapping: child)
        target.pointerMoved.addHandler { [weak target] _, args in
            // Each way of reporting nothing says which one it was, under
            // --debug: P88's first run on Windows (2026-10-20) moved over the
            // panel and showed no report at all, with nothing to tell a move
            // that never arrived from one that arrived and was dropped here.
            // 每一種「什麼都不回報」的情況都在 --debug 下說明是哪一種:P88 第一次在 Windows 上跑
            // (2026-10-20)指標移過面板卻沒有任何回報，而沒有東西能區分「移動根本沒到」與「到了卻在這裡被丟掉」。
            guard let target, let args else { return }
            guard let action = target.onPointerHover else {
                DebugFeatures.log("WinUIBackend.PointerHover: a move arrived with no action set")
                return
            }
            guard let position = try? args.getCurrentPoint(target)?.position else {
                DebugFeatures.log("WinUIBackend.PointerHover: a move arrived without a position")
                return
            }
            let location = SIMD2(Double(position.x), Double(position.y))
            // A finger hovers only once it has rested; before that a move
            // past the slop makes it a drag, not a hover.
            // 手指要先靜止才算 hover;在那之前移動超過容許距離就是拖曳，不是 hover。
            if args.pointer.pointerDeviceType == .touch {
                guard target.touchHoverPointer == args.pointer.pointerId else { return }
                if target.touchHovering {
                    action(.active(location: location, modifiers: []))
                } else if Self.distance(location, target.touchHoverStart) > Self.touchHoverSlop {
                    target.touchHoverPointer = nil
                }
                return
            }
            action(
                .active(
                    location: SIMD2(Double(position.x), Double(position.y)),
                    modifiers: Self.currentModifiers()))
        }
        target.pointerPressed.addHandler { [weak target] _, args in
            guard let target, let args, args.pointer.pointerDeviceType == .touch,
                let position = try? args.getCurrentPoint(target)?.position
            else { return }
            Self.touchHoverPressed(
                on: target, pointer: args.pointer.pointerId,
                at: SIMD2(Double(position.x), Double(position.y)))
        }
        target.pointerReleased.addHandler { [weak target] _, args in
            guard let target, let args, args.pointer.pointerDeviceType == .touch else { return }
            Self.touchHoverLifted(on: target, pointer: args.pointer.pointerId)
        }
        target.pointerCanceled.addHandler { [weak target] _, args in
            guard let target, let args, args.pointer.pointerDeviceType == .touch else { return }
            Self.touchHoverLifted(on: target, pointer: args.pointer.pointerId)
        }
        target.pointerCaptureLost.addHandler { [weak target] _, args in
            guard let target, let args, args.pointer.pointerDeviceType == .touch else { return }
            Self.touchHoverLifted(on: target, pointer: args.pointer.pointerId)
        }
        target.pointerExited.addHandler { [weak target] _, args in
            // A lifted finger exits too; touch ends through touchHoverLifted.
            // 抬起的手指也會觸發 exited;觸控改由 touchHoverLifted 結束。
            guard let target, args?.pointer.pointerDeviceType != .touch else { return }
            target.onPointerHover?(.ended)
        }
        return target
    }

    public func updatePointerHoverTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        action: @escaping (PointerHoverPhase) -> Void
    ) {
        let target = target as! WinUIFeatureTarget
        target.onPointerHover = environment.isEnabled ? action : nil
    }

    /// How long a finger rests before it hovers, and how far it may move
    /// meanwhile: 0.5 s and 10 DIPs, as UIKit's long press and GTK's
    /// `gtk-long-press-time` (queue item 10, 2026-10-15). A finger that moves
    /// further first is a drag and never hovers.
    /// 手指靜止多久才 hover,以及其間可移動多遠:0.5 秒與 10 DIP,同 UIKit 的長按與 GTK 的
    /// `gtk-long-press-time`(queue 第 10 項,2026-10-15)。先移得更遠的手指是拖曳，永不 hover。
    static let touchHoverDelay = 0.5
    static let touchHoverSlop = 10.0

    static func distance(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
        let d = a - b
        return (d.x * d.x + d.y * d.y).squareRoot()
    }

    /// A finger went down: it hovers if it is still there, within the slop,
    /// after `touchHoverDelay`.
    /// 手指按下：若 `touchHoverDelay` 之後仍在容許距離內，即開始 hover。
    static func touchHoverPressed(on target: WinUIFeatureTarget, pointer: UInt32, at location: SIMD2<Double>) {
        target.touchHoverGeneration += 1
        let generation = target.touchHoverGeneration
        target.touchHoverPointer = pointer
        target.touchHoverStart = location
        target.touchHovering = false
        DispatchQueue.main.asyncAfter(deadline: .now() + touchHoverDelay) { [weak target] in
            MainActor.assumeIsolated {
                guard let target, target.touchHoverGeneration == generation,
                    target.touchHoverPointer == pointer
                else { return }
                target.touchHovering = true
                target.onPointerHover?(.active(location: target.touchHoverStart, modifiers: []))
            }
        }
    }

    /// The finger lifted or was cancelled: a hover it started ends.
    /// 手指抬起或被取消：它開始的 hover 隨之結束。
    static func touchHoverLifted(on target: WinUIFeatureTarget, pointer: UInt32) {
        guard target.touchHoverPointer == pointer else { return }
        let wasHovering = target.touchHovering
        target.touchHoverPointer = nil
        target.touchHovering = false
        target.touchHoverGeneration += 1
        if wasHovering {
            target.onPointerHover?(.ended)
        }
    }
}

// MARK: Scroll gestures

extension WinUIBackend: BackendFeatures.ScrollGestures {
    public func createScrollGestureTarget(wrapping child: Widget) -> Widget {
        let target = featureTarget(wrapping: child)
        target.pointerWheelChanged.addHandler { [weak target] _, args in
            guard let target, let args, target.scrollEnabled,
                let properties = try? args.getCurrentPoint(target)?.properties
            else { return }
            // One wheel message is one gesture, AppKitBackend's rule for an
            // event with no phase and GtkBackend's for a wheel: Windows sends
            // no begin or end for a wheel, and a precision touchpad arrives
            // here as wheel messages too. WHEEL_DELTA (120) is one notch; a
            // delta that is not a multiple of it came from a touchpad.
            // Vertical deltas are positive away from the user, so they are
            // negated into the content's direction, as AppKit and GTK report;
            // horizontal ones are already positive to the right.
            // 一則滾輪訊息就是一個手勢，與 AppKitBackend 對無階段事件、GtkBackend 對滾輪的規則相同:Windows 不為滾輪
            // 送開始或結束，精密觸控板在這裡也是以滾輪訊息到達。WHEEL_DELTA(120)為一格；不是它倍數的 delta 來自
            // 觸控板。垂直 delta 以遠離使用者為正，因此取負號換成內容的方向，與 AppKit、GTK 回報的相同；水平的
            // 本來就以向右為正。
            let wheel = Double(properties.mouseWheelDelta)
            let lines = wheel / Double(WHEEL_DELTA)
            let delta =
                properties.isHorizontalMouseWheel
                ? SIMD2(lines * Self.pointsPerScrollLine, 0)
                : SIMD2(0, -lines * Self.pointsPerScrollLine)
            let isPrecise = properties.mouseWheelDelta % Int32(WHEEL_DELTA) != 0
            target.onScrollChange?(ScrollGestureValue(delta: delta, translation: delta, isPrecise: isPrecise))
            target.onScrollEnd?(ScrollGestureValue(delta: .zero, translation: delta, isPrecise: isPrecise))
            args.handled = true
        }
        return target
    }

    public func updateScrollGestureTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (ScrollGestureValue) -> Void,
        onEnd: @escaping (ScrollGestureValue) -> Void
    ) {
        let target = target as! WinUIFeatureTarget
        target.scrollEnabled = environment.isEnabled
        target.onScrollChange = onChange
        target.onScrollEnd = onEnd
    }

    /// Points per wheel notch, AppKitBackend's and GtkBackend's figure.
    /// 每一格滾輪的點數，與 AppKitBackend、GtkBackend 相同。
    static let pointsPerScrollLine: Double = 16
}

// MARK: Widget snapshots

extension WinUIBackend: BackendFeatures.WidgetSnapshots {
    public func snapshotWidget(_ widget: Widget) -> WidgetSnapshot? {
        Self.snapshot(of: widget)
    }

    /// The widget rendered through `RenderTargetBitmap`, read back as
    /// premultiplied RGBA -- the layout AppKitBackend and GtkBackend produce,
    /// in device pixels like GTK's.
    ///
    /// `RenderAsync` and `GetPixelsAsync` finish on the UI thread's next
    /// render pass, and this protocol is synchronous and is called on that
    /// thread; waiting would deadlock and returning early would hand back
    /// nothing. So this pumps the thread's messages until each operation
    /// leaves `.started`, the way a modal dialog keeps the UI alive, with a
    /// two-second limit. A widget that is not in a loaded window cannot be
    /// rendered: `nil`.
    ///
    /// 以 `RenderTargetBitmap` 繪製 widget,讀回成 premultiplied RGBA——與 AppKitBackend、GtkBackend 產出的
    /// 排列相同，與 GTK 一樣是裝置像素。`RenderAsync` 與 `GetPixelsAsync` 在 UI 執行緒下一次繪製時才完成，而本
    /// 協定是同步的、且就在那條執行緒上被呼叫：等待會 deadlock,提早返回則什麼都拿不到。因此這裡抽取該執行緒的
    /// 訊息，直到每個操作離開 `.started`——就像 modal 對話框讓 UI 保持運作那樣——上限兩秒。不在已載入視窗中的
    /// widget 無法繪製：回傳 `nil`。
    @MainActor
    public static func snapshot(of widget: Widget) -> WidgetSnapshot? {
        // A mesh view draws into a swap chain, which `RenderTargetBitmap` does
        // not see; it reads its own back buffer instead, as the Metal, GLES and
        // GL mesh views do. mesh view 畫進 swap chain,`RenderTargetBitmap` 看不到;改讀它自己的 back buffer,
        // 與 Metal、GLES、GL 的 mesh view 相同。
        if let mesh = widget as? Mesh3DD3DView {
            return mesh.snapshot()
        }
        guard widget.isLoaded else { return nil }
        let bitmap = RenderTargetBitmap()
        guard let render = try? bitmap.renderAsync(widget),
            pump(until: { render.status != .started }), render.status == .completed,
            let read = try? bitmap.getPixelsAsync(),
            pump(until: { read.status != .started }), read.status == .completed,
            let buffer = try? read.getResults(),
            let reader = DataReader.fromBuffer(buffer)
        else { return nil }
        let width = Int(bitmap.pixelWidth)
        let height = Int(bitmap.pixelHeight)
        guard width > 0, height > 0, Int(reader.unconsumedBufferLength) >= width * height * 4
        else { return nil }
        reader.byteOrder = .littleEndian
        // BGRA8 premultiplied, one little-endian UInt32 per pixel.
        // BGRA8 premultiplied,每個像素一個 little-endian UInt32。
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for pixel in 0..<(width * height) {
            guard let bgra = try? reader.readUInt32() else { return nil }
            rgba[pixel * 4] = UInt8(truncatingIfNeeded: bgra >> 16)
            rgba[pixel * 4 + 1] = UInt8(truncatingIfNeeded: bgra >> 8)
            rgba[pixel * 4 + 2] = UInt8(truncatingIfNeeded: bgra)
            rgba[pixel * 4 + 3] = UInt8(truncatingIfNeeded: bgra >> 24)
        }
        return WidgetSnapshot(width: width, height: height, rgbaData: rgba)
    }

    /// Dispatches this thread's messages until `done` holds or two seconds
    /// pass. 抽取本執行緒的訊息，直到 `done` 成立或經過兩秒。
    ///
    /// `WM_QUIT` ends the pump and is posted again for the loop it belongs to.
    /// A nested loop that removes it and carries on swallows the app's exit:
    /// the outer loop never sees it, so a window closed while a snapshot was
    /// pending left the process running (todo.md review item, 2026-10-14).
    /// `PostQuitMessage` re-queues it with the same exit code.
    /// `WM_QUIT` 會結束這個 pump,並為它所屬的迴圈重新送出。巢狀迴圈若把它取出後繼續跑，就會吞掉 app 的退出：
    /// 外層迴圈永遠看不到它，於是 snapshot 等待中關閉視窗時，行程仍留著(todo.md 審查項目,2026-10-14)。
    /// `PostQuitMessage` 以相同的結束碼把它重新排入。
    @MainActor
    private static func pump(until done: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(2)
        var message = MSG()
        while !done() {
            if Date() > deadline { return false }
            if PeekMessageW(&message, nil, 0, 0, UINT(PM_REMOVE)) {
                if message.message == UINT(WM_QUIT) {
                    PostQuitMessage(Int32(truncatingIfNeeded: message.wParam))
                    return false
                }
                TranslateMessage(&message)
                DispatchMessageW(&message)
            } else {
                _ = MsgWaitForMultipleObjects(0, nil, false, 10, DWORD(QS_ALLINPUT))
            }
        }
        return true
    }
}

// MARK: Focusable targets

extension WinUIBackend: BackendFeatures.FocusableTargets {
    /// A feature target made a tab stop, which is all a `Canvas` needs to hold
    /// the keyboard focus -- it accepts focus unconditionally (instrumented
    /// 2026-09-16, see WinUIBackend+Focus.swift). A press focuses it on the next
    /// main-queue turn, as the key-event target does, because the window's root
    /// `ScrollViewer` focuses itself in its own PointerPressed after ours.
    ///
    /// **Tab is the target's** (BackendFeatures.FocusableTargets): `.onKeyPress`
    /// outside it cannot decline a key, so the target moves the focus itself
    /// with `FocusManager.tryMoveFocus` and marks Tab handled before the key
    /// handler hears it. Only when the window's root is known: the call needs a
    /// search root on desktop WinUI, and the binding wraps it in `try!`.
    ///
    /// A `Canvas` draws no focus visual, so a 3-px `Border` above the child,
    /// sized with the target and transparent to the pointer, shows while the
    /// target itself (not a child) holds the focus -- GtkBackend draws the same
    /// ring with an outline.
    ///
    /// 一個設成 tab stop 的 feature target——這就是 `Canvas` 持有鍵盤焦點所需的全部，它會無條件接受焦點
    /// (2026-09-16 加儀器量到，見 WinUIBackend+Focus.swift)。按下時在主佇列的下一輪取得焦點，與按鍵 target
    /// 相同，因為視窗根部的 `ScrollViewer` 會在我們之後、在它自己的 PointerPressed 中取得焦點。
    ///
    /// **Tab 歸 target**(BackendFeatures.FocusableTargets):外層的 `.onKeyPress` 無法拒收按鍵，所以 target
    /// 自己以 `FocusManager.tryMoveFocus` 移動焦點，並在按鍵處理器聽到之前把 Tab 標為已處理。只在知道視窗根
    /// 時才這樣做：桌面版 WinUI 的這個呼叫需要 search root,而綁定把它包在 `try!` 裡。
    ///
    /// `Canvas` 不畫焦點外框，所以在子 view 上方疊一個 3 px 的 `Border`,大小隨 target、不攔截指標，只在
    /// target 本身(而非子 view)持有焦點時顯示——GtkBackend 以 outline 畫出同樣的框。
    public func createFocusableTarget(wrapping child: Widget) -> Widget {
        let target = featureTarget(wrapping: child)
        target.isFocusableTarget = true
        target.focusableWanted = true
        target.isTabStop = true

        let ring = WinUI.Border()
        ring.borderThickness = Thickness(left: 3, top: 3, right: 3, bottom: 3)
        ring.borderBrush = Self.focusRingBrush()
        ring.isHitTestVisible = false
        ring.visibility = .collapsed
        insert(ring, into: target, at: 1)
        target.focusRing = ring
        target.sizeChanged.addHandler { [weak target] _, _ in
            guard let target, let ring = target.focusRing else { return }
            ring.width = target.actualWidth
            ring.height = target.actualHeight
        }
        target.gotFocus.addHandler { [weak target] _, args in
            guard let target, (args?.originalSource as AnyObject?) === target else { return }
            target.focusRing?.visibility = .visible
        }
        target.lostFocus.addHandler { [weak target] _, args in
            guard let target, (args?.originalSource as AnyObject?) === target else { return }
            target.focusRing?.visibility = .collapsed
        }
        target.pointerPressed.addHandler { [weak target] _, _ in
            DispatchQueue.main.async { [weak target] in
                guard let target, target.focusableWanted else { return }
                _ = try? target.focus(.pointer)
            }
        }
        target.keyDown.addHandler { [weak target] _, args in
            guard let target, let args, args.key == .tab,
                (args.originalSource as AnyObject?) === target,
                let root = target.xamlRoot?.content
            else { return }
            let options = FindNextElementOptions()
            options.searchRoot = root
            let backward = Self.currentModifiers().contains(.shift)
            _ = FocusManager.tryMoveFocus(backward ? .previous : .next, options)
            args.handled = true
        }
        return target
    }

    public func updateFocusableTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        isFocusable: Bool
    ) {
        let target = target as! WinUIFeatureTarget
        let wanted = isFocusable && environment.isEnabled
        if !wanted {
            unfocus(target)
        }
        target.focusableWanted = wanted
        target.isTabStop = wanted
    }

    /// Fluent's focus stroke from the app's theme resources; Windows blue when
    /// the resource cannot be read. Fluent 的焦點描邊色，取自 app 的主題資源；讀不到時用 Windows 藍。
    static func focusRingBrush() -> WinUI.Brush {
        if let brush = WinUI.Application.current?.resources
            .lookup("FocusStrokeColorOuterBrush") as? WinUI.Brush
        {
            return brush
        }
        let brush = SolidColorBrush()
        brush.color = UWP.Color(a: 255, r: 0x00, g: 0x67, b: 0xC0)
        return brush
    }
}

/// The wrapper every target above uses.
/// 上方每個 target 所用的包裝。
final class WinUIFeatureTarget: WinUI.Canvas {
    var menuFlyout: MenuFlyout?
    var cursorShape: InputSystemCursorShape?
    var keyEventsEnabled = true
    var onKey: ((KeyPress) -> Void)?
    var awaitingPacketCharacter = false
    var packetCharacter: Character?
    var scrollEnabled = true
    var onScrollChange: ((ScrollGestureValue) -> Void)?
    var onScrollEnd: ((ScrollGestureValue) -> Void)?
    var onPointerHover: ((PointerHoverPhase) -> Void)?
    /// The touch that may become a hover: its pointer, where it went down,
    /// whether it has rested long enough, and which hold timer is current.
    /// 可能成為 hover 的那次觸控：它的 pointer、按下的位置、是否已靜止夠久，以及哪個按住計時器有效。
    var touchHoverPointer: UInt32?
    var touchHoverStart = SIMD2<Double>(0, 0)
    var touchHovering = false
    var touchHoverGeneration = 0
    /// Set by `createFocusableTarget`: whether this target is one, whether it
    /// may hold the focus now, and the ring drawn while it does.
    /// 由 `createFocusableTarget` 設定：本 target 是否為可聚焦 target、此刻能否持有焦點，以及持有時畫出的外框。
    var isFocusableTarget = false
    var focusableWanted = false
    var focusRing: WinUI.Border?
}
