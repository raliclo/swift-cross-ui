import Foundation
@_spi(Backends) import SwiftCrossUI
import UWP
import WinAppSDK
import WinSDK
import WinUI

/// `BackendFeatures.BackNavigation` and `SheetBackNavigation` on WinUI: Alt+Left,
/// the Back key (`VK_BROWSER_BACK`) and the mouse's back button (`XButton1`),
/// the three Back inputs desktop apps on Windows answer to.
///
/// **Read from the thread's messages, not from focus.** Keyboard accelerators
/// on the root grid alone were measured not to fire after a pushed screen's
/// button had been clicked (Windows, P114, 2026-10-29: three `VK_BROWSER_BACK`
/// and three Alt+Left at depth 3 popped nothing), consistent with the clicked
/// button being removed by the push and the focus left on nothing. So the
/// inputs are taken in four places, in the order a press meets them, and the
/// first that goes back stops the rest:
///
/// 1. A `WH_GETMESSAGE` hook on the UI thread sees `WM_KEYDOWN` `VK_BROWSER_BACK`,
///    `WM_SYSKEYDOWN` `VK_LEFT` with Alt, and `WM_XBUTTONDOWN` `XBUTTON1` for any
///    window of the thread -- XAML's input site child included -- before they
///    are dispatched, and finds the top-level window with `GetAncestor`. A
///    press that went back is turned into `WM_NULL`, so XAML and
///    `DefWindowProc` never see it (and no `WM_APPCOMMAND` is made from it); the
///    matching `WM_XBUTTONUP` is dropped the same way. Alt+Left is the
///    exception: its Left becomes the unassigned virtual key 0xE8, so that
///    releasing Alt does not put the window into menu mode.
/// 2. `WM_APPCOMMAND` `APPCOMMAND_BROWSER_BACKWARD` in the window procedure, for
///    a device that sends only that.
/// 3. The root grid's `KeyboardAccelerator`s (and a sheet's), as before.
/// 4. The root grid's `pointerPressed` with `isXButton1Pressed`, for a mouse
///    whose buttons arrive as pointer messages rather than `WM_XBUTTON*`.
///
/// Every Back that runs prints `SCUI-BackNavigation: <source>: popped` or
/// `nothing to pop`, so a run shows which path fired. A second Back from a
/// different source within 0.3 s of one that popped is taken as the same press
/// reaching two of these paths, and swallowed.
///
/// **Sheets.** A sheet is a `ContentDialog` in a popup over the window's
/// content. While one is presenting (`CustomWindow.presentedSheet`), every
/// path above runs the sheet's handler instead of the window's, so Back never
/// reaches under a sheet; with no stack in the sheet able to pop, nothing
/// changes and the sheet keeps its own Escape.
///
/// WinUI 上的 `BackendFeatures.BackNavigation` 與 `SheetBackNavigation`:Alt+Left、返回鍵(`VK_BROWSER_BACK`)與滑鼠返回鍵
/// (`XButton1`)——Windows 上桌面 app 慣用的三種返回輸入。
///
/// **從執行緒的訊息讀取，而不是依賴焦點。** 只掛在根 grid 上的 keyboard accelerator,在點過被推入畫面的按鈕之後實測不會觸發
/// (Windows,P114,2026-10-29:在深度 3 按三次 `VK_BROWSER_BACK` 與三次 Alt+Left 都沒有彈出),與「被點的按鈕被推入移除、焦點
/// 落在空處」相符。因此在四個地方接下這些輸入，依一次按壓遇到它們的順序，第一個返回成功的就擋下其餘的：
///
/// 1. UI 執行緒上的 `WH_GETMESSAGE` hook,在派送之前看到本執行緒任何視窗(含 XAML 的 input site 子視窗)的 `WM_KEYDOWN`
///    `VK_BROWSER_BACK`、帶 Alt 的 `WM_SYSKEYDOWN` `VK_LEFT` 與 `WM_XBUTTONDOWN` `XBUTTON1`,並以 `GetAncestor` 找到頂層視窗。
///    返回成功的按壓被改成 `WM_NULL`,XAML 與 `DefWindowProc` 都看不到它(也不會由它產生 `WM_APPCOMMAND`);對應的
///    `WM_XBUTTONUP` 也以同樣方式丟掉。Alt+Left 例外：它的 Left 被換成未指派的 virtual key 0xE8,以免 Alt 放開時進入選單模式。
/// 2. 視窗程序中的 `WM_APPCOMMAND` `APPCOMMAND_BROWSER_BACKWARD`,給只送這個的裝置。
/// 3. 根 grid(與 sheet)上的 `KeyboardAccelerator`,與以往相同。
/// 4. 根 grid 的 `pointerPressed` 搭配 `isXButton1Pressed`,給按鍵以 pointer 訊息而非 `WM_XBUTTON*` 抵達的滑鼠。
///
/// 每次執行的返回都會印出 `SCUI-BackNavigation: <來源>: popped` 或 `nothing to pop`,讓一次執行看得出是哪條路徑觸發。在一次
/// 成功彈出之後 0.3 秒內、來自不同來源的第二次返回，視為同一次按壓抵達了兩條路徑，予以吞掉。
///
/// **sheet。** sheet 是視窗內容之上 popup 中的 `ContentDialog`。有 sheet 正在呈現時(`CustomWindow.presentedSheet`),上述每條
/// 路徑都改為執行 sheet 的 handler,因此返回永遠不會穿到 sheet 底下；sheet 中沒有可彈出的堆疊時，什麼都不變,sheet 保留它自己的
/// Escape。
extension WinUIBackend: BackendFeatures.BackNavigation, BackendFeatures.SheetBackNavigation {
    public func setBackNavigationHandler(
        ofWindow window: Window,
        to action: (@MainActor () -> Bool)?
    ) {
        window.backNavigationHandler = action
    }

    public func setBackNavigationHandler(
        ofSheet sheet: Sheet,
        to action: (@MainActor () -> Bool)?
    ) {
        sheet.backNavigationHandler = action
    }
}

@MainActor
enum WinUIBackNavigation {
    /// The last Back that popped, for telling one press reaching two paths
    /// from two presses. 上一次成功彈出的返回，用來分辨「一次按壓抵達兩條路徑」與「兩次按壓」。
    private static var lastPop: (time: TimeInterval, source: String)?

    /// Runs Back in `window`: the presenting sheet's handler while a sheet is
    /// up, the window's otherwise. Returns whether it went back.
    /// 在 `window` 中執行返回：有 sheet 開著時執行該 sheet 的 handler,否則執行視窗的。回傳是否返回了。
    static func goBack(in window: CustomWindow, source: String) -> Bool {
        let handler: (@MainActor () -> Bool)?
        if let sheet = window.presentedSheet, sheet.isPresenting {
            handler = sheet.backNavigationHandler
        } else {
            handler = window.backNavigationHandler
        }
        guard let handler else { return false }
        let now = ProcessInfo.processInfo.systemUptime
        if let lastPop, now - lastPop.time < 0.3, lastPop.source != source {
            log("\(source): ignored, same press as \(lastPop.source)")
            return true
        }
        let wentBack = handler()
        log("\(source): \(wentBack ? "popped" : "nothing to pop")")
        if wentBack { lastPop = (now, source) }
        return wentBack
    }

    /// One line on stderr, unbuffered, so it survives the app being killed.
    /// stderr 上的一行(不經緩衝),app 被終止也不會遺失。
    nonisolated static func log(_ message: String) {
        FileHandle.standardError.write(Data("SCUI-BackNavigation: \(message)\n".utf8))
    }

    // MARK: Thread messages

    private static var messageHook: HHOOK?
    /// Set when an `XBUTTON1` press went back, so that its release is dropped
    /// too. 某次 `XBUTTON1` 按下返回成功時設定，讓它的放開也一併丟掉。
    nonisolated(unsafe) fileprivate static var dropNextXButtonUp = false

    /// Installs the `WH_GETMESSAGE` hook once, on the UI thread.
    /// 在 UI 執行緒上安裝 `WH_GETMESSAGE` hook,只做一次。
    static func installMessageHook() {
        guard messageHook == nil else { return }
        messageHook = SetWindowsHookExW(WH_GETMESSAGE, backNavigationMessageHook, nil, GetCurrentThreadId())
        if messageHook == nil {
            log("WH_GETMESSAGE hook not installed, error \(GetLastError())")
        }
    }

    /// The source a message is a Back press from, or `nil`.
    /// 一則訊息若是返回按壓，回傳它的來源；否則為 `nil`。
    nonisolated static func backSource(of message: MSG) -> String? {
        let virtualKey = UInt64(message.wParam)
        switch message.message {
            case UINT(WM_KEYDOWN) where virtualKey == 0xA6:  // VK_BROWSER_BACK
                return "VK_BROWSER_BACK (WM_KEYDOWN)"
            case UINT(WM_SYSKEYDOWN) where virtualKey == 0x25:  // VK_LEFT
                // Bit 29 of lParam: Alt is down. No other modifier.
                // lParam 的第 29 位元:Alt 按著。沒有其他修飾鍵。
                let altDown = (Int64(message.lParam) >> 29) & 1 == 1
                let othersUp = [0x10, 0x11, 0x5B, 0x5C].allSatisfy { GetKeyState(Int32($0)) >= 0 }
                return altDown && othersUp ? "Alt+Left (WM_SYSKEYDOWN)" : nil
            case UINT(WM_XBUTTONDOWN) where (UInt64(message.wParam) >> 16) & 0xFFFF == 1:  // XBUTTON1
                return "XButton1 (WM_XBUTTONDOWN)"
            default:
                return nil
        }
    }

    /// `WM_APPCOMMAND` from the window procedure; returns whether it went back.
    /// 來自視窗程序的 `WM_APPCOMMAND`;回傳是否返回了。
    static func handleAppCommand(_ lParam: LPARAM, in window: CustomWindow) -> Bool {
        // GET_APPCOMMAND_LPARAM: the high word without FAPPCOMMAND_MASK (0xF000).
        // GET_APPCOMMAND_LPARAM:去掉 FAPPCOMMAND_MASK(0xF000)的高位字。
        let command = (Int64(lParam) >> 16) & 0x0FFF
        guard command == 1 else { return false }  // APPCOMMAND_BROWSER_BACKWARD
        return goBack(in: window, source: "APPCOMMAND_BROWSER_BACKWARD (WM_APPCOMMAND)")
    }

    // MARK: XAML

    /// Attaches the accelerators and the `XButton1` press to `element` once.
    /// They act for whatever window `window` returns at the time.
    /// 把加速鍵與 `XButton1` 按壓掛到 `element` 上，只做一次。它們替 `window` 當下回傳的視窗行動。
    static func install(
        on element: WinUI.UIElement,
        name: String,
        window: @escaping @MainActor () -> CustomWindow?
    ) {
        let backKey = WinUI.KeyboardAccelerator()
        backKey.key = .goBack
        let altLeft = WinUI.KeyboardAccelerator()
        altLeft.key = .left
        altLeft.modifiers = .menu
        for (accelerator, label) in [(backKey, "GoBack"), (altLeft, "Alt+Left")] {
            accelerator.invoked.addHandler { _, args in
                guard let args else { return }
                // WinUI raises the event on the UI thread, the main actor.
                // WinUI 在 UI 執行緒(即 main actor)上引發此事件。
                let wentBack = MainActor.assumeIsolated { () -> Bool in
                    guard let window = window() else { return false }
                    return goBack(in: window, source: "\(label) accelerator on \(name)")
                }
                if wentBack {
                    args.handled = true
                }
            }
            element.keyboardAccelerators.append(accelerator)
        }
        // No tooltip naming the accelerators. 不顯示列出加速鍵的提示。
        element.keyboardAcceleratorPlacementMode = .hidden

        element.pointerPressed.addHandler { [weak element] _, args in
            guard let element, let args,
                (try? args.getCurrentPoint(element))?.properties.isXButton1Pressed == true
            else { return }
            // WinUI raises the event on the UI thread, the main actor.
            // WinUI 在 UI 執行緒(即 main actor)上引發此事件。
            let wentBack = MainActor.assumeIsolated { () -> Bool in
                guard let window = window() else { return false }
                return goBack(in: window, source: "XButton1 pointerPressed on \(name)")
            }
            if wentBack {
                args.handled = true
            }
        }
    }
}

/// The `WH_GETMESSAGE` hook: runs on the UI thread for every message taken off
/// its queue. `PM_REMOVE` only, so a message that is peeked and left is not
/// handled twice.
/// `WH_GETMESSAGE` hook:對 UI 執行緒佇列中取出的每則訊息執行。只處理 `PM_REMOVE`,以免被 peek 後留下的訊息處理兩次。
private let backNavigationMessageHook: HOOKPROC = {
    (nCode: Int32, wParam: WPARAM, lParam: LPARAM) in
    if nCode >= 0, wParam == WPARAM(PM_REMOVE),
       let message = UnsafeMutableRawPointer(bitPattern: Int(lParam))?
           .assumingMemoryBound(to: MSG.self)
    {
        if message.pointee.message == UINT(WM_XBUTTONUP), WinUIBackNavigation.dropNextXButtonUp {
            WinUIBackNavigation.dropNextXButtonUp = false
            message.pointee.message = UINT(WM_NULL)
        } else if let source = WinUIBackNavigation.backSource(of: message.pointee),
                  let hwnd = message.pointee.hwnd,
                  let root = GetAncestor(hwnd, UINT(GA_ROOT))
        {
            // An address, not the HWND: a pointer is not Sendable into the closure. 傳位址而非 HWND:指標不能以 Sendable 送進閉包。
            let rootAddress = Int(bitPattern: root)
            let wentBack = MainActor.assumeIsolated { () -> Bool in
                guard let root = HWND(bitPattern: rootAddress),
                    let window = CustomWindow.window(forHWND: root)
                else { return false }
                return WinUIBackNavigation.goBack(in: window, source: source)
            }
            if wentBack {
                if message.pointee.message == UINT(WM_XBUTTONDOWN) {
                    WinUIBackNavigation.dropNextXButtonUp = true
                }
                if message.pointee.message == UINT(WM_SYSKEYDOWN) {
                    // Not WM_NULL: with no key seen between Alt going down and
                    // up, the window would enter menu mode on Alt's release and
                    // swallow the next key. 0xE8 is an unassigned virtual key,
                    // the usual "menu mask" key: the window sees a key with Alt and
                    // nothing acts on it.
                    // 不改成 WM_NULL:若在 Alt 按下與放開之間沒看到任何鍵，視窗會在 Alt 放開時進入選單模式並吞掉下一個鍵。
                    // 0xE8 是未指派的 virtual key,也就是常用的「選單遮罩」鍵：視窗看到一個帶 Alt 的鍵，而沒有任何東西對它動作。
                    message.pointee.wParam = 0xE8
                } else {
                    message.pointee.message = UINT(WM_NULL)
                }
            }
        }
    }
    return CallNextHookEx(nil, nCode, wParam, lParam)
}

extension CustomWindow {
    /// Attaches the Back inputs, once, from `init`. They do nothing while
    /// neither the window nor a presenting sheet has a handler.
    /// 從 `init` 掛上返回輸入，只做一次。視窗與正在呈現的 sheet 都沒有 handler 時，它們什麼也不做。
    func installBackNavigation() {
        // CustomWindow is created on the UI thread, the main actor. CustomWindow 在 UI 執行緒(main actor)上建立。
        nonisolated(unsafe) let window = self
        MainActor.assumeIsolated {
            WinUIBackNavigation.installMessageHook()
            WinUIBackNavigation.install(on: window.grid, name: "root grid") { [weak window] in window }
        }
    }
}
