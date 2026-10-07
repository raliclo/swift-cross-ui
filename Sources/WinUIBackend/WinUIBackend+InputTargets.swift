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
                _ = try? target.focus(.programmatic)
            }
        }
        target.pointerPressed.addHandler { [weak target] _, _ in
            DispatchQueue.main.async { [weak target] in
                guard let target, target.keyEventsEnabled else { return }
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
    @MainActor
    private static func pump(until done: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(2)
        var message = MSG()
        while !done() {
            if Date() > deadline { return false }
            if PeekMessageW(&message, nil, 0, 0, UINT(PM_REMOVE)) {
                TranslateMessage(&message)
                DispatchMessageW(&message)
            } else {
                _ = MsgWaitForMultipleObjects(0, nil, false, 10, DWORD(QS_ALLINPUT))
            }
        }
        return true
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
}
