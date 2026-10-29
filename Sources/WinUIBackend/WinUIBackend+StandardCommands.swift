import Foundation
@_spi(Backends) import SwiftCrossUI
import WinAppSDK
import WinUIInterop
// `@preconcurrency` for `FocusManager.gotFocus`, a class property swift-winui does not annotate;
// the same answer as WinUIBackend+FrameClock.swift gives for `CompositionTarget.rendering`.
// `@preconcurrency` 是為了 `FocusManager.gotFocus`(swift-winui 未加註的 class property),與 FrameClock 檔相同。
@preconcurrency import WinUI

/// The standard menu commands -- Undo, Copy, Close, Minimize, Quit and the rest
/// -- that a ``CommandGroup`` places in the menu bar, performed the way a WinUI
/// app performs them.
///
/// WinUIBackend draws the menu bar through `ApplicationMenus` already; without
/// this conformance SwiftCrossUI could not tell which standard items WinUI can
/// carry out, so a `CommandGroup` placed beside a standard item found nothing
/// to stand beside (queue item 2, 2026-10-19). Item for item it follows
/// GtkBackend+StandardCommands.swift: the text commands go to the focused text
/// box, the window commands to the active window, and Hide Others minimizes the
/// other applications' windows as Win+Home does.
///
/// ``CommandGroup`` 放進選單列的標準指令——Undo、Copy、Close、Minimize、Quit 等——以 WinUI app 的方式執行。
///
/// WinUIBackend 早已經由 `ApplicationMenus` 畫出選單列；少了這個 conformance,SwiftCrossUI 無從得知 WinUI 能執行
/// 哪些標準項目，於是放在標準項目旁邊的 `CommandGroup` 找不到可以並列的對象(queue 第 2 項,2026-10-19)。逐項比照
/// GtkBackend+StandardCommands.swift：文字指令交給有焦點的文字框，視窗指令交給作用中的視窗,Hide Others
/// 像 Win+Home 一樣把其他 app 的視窗最小化。
extension WinUIBackend: BackendFeatures.StandardCommands {
    public func hasStandardCommand(_ command: StandardCommand) -> Bool {
        WinUITextCommandTarget.watch()
        // Every standard command, Hide Others included: hide_others.cpp minimizes the
        // other applications' windows the way Win+Home does.
        // 每個標準指令都提供,Hide Others 也是:hide_others.cpp 像 Win+Home 一樣把其他 app 的視窗最小化。
        return true
    }

    public func performStandardCommand(_ command: StandardCommand) {
        let active = windows.first(where: \.isActive) ?? windows.first

        func presenter(_ window: Window) -> OverlappedPresenter? {
            window.appWindow.presenter as? OverlappedPresenter
        }

        // The focused element of the active window, as a text box or a
        // password box -- the two that take the clipboard commands.
        // 作用中視窗裡有焦點的元素，以文字框或密碼框取得——接受剪貼簿指令的就是這兩種。
        func focused() -> WinUI.DependencyObject? {
            guard let root = active?.content.xamlRoot else { return WinUITextCommandTarget.element }
            let focused = FocusManager.getFocusedElement(root) as? WinUI.DependencyObject
            if focused is WinUI.TextBox || focused is WinUI.PasswordBox { return focused }
            return WinUITextCommandTarget.element
        }

        switch command {
            case .undo, .redo, .cut, .copy, .paste, .delete, .selectAll:
                if let box = focused() as? WinUI.TextBox {
                    switch command {
                        case .undo: try? box.undo()
                        case .redo: try? box.redo()
                        case .cut: try? box.cutSelectionToClipboard()
                        case .copy: try? box.copySelectionToClipboard()
                        case .paste: try? box.pasteFromClipboard()
                        case .delete: box.selectedText = ""
                        default: try? box.selectAll()
                    }
                } else if let box = focused() as? WinUI.PasswordBox {
                    switch command {
                        case .paste: try? box.pasteFromClipboard()
                        case .selectAll: try? box.selectAll()
                        default: break
                    }
                }
            case .close:
                if let active { close(window: active) }
            case .closeAll:
                for window in windows { close(window: window) }
            case .minimize:
                if let active { try? presenter(active)?.minimize() }
            case .zoom:
                guard let active, let presenter = presenter(active) else { return }
                if presenter.state == .maximized {
                    try? presenter.restore()
                } else {
                    try? presenter.maximize()
                }
            case .bringAllToFront:
                for window in windows { activate(window: window) }
            case .quit:
                try? WinUI.Application.current?.exit()
            case .about:
                showInformation("About \(ProcessInfo.processInfo.processName)", in: active)
            case .hide:
                for window in windows { try? presenter(window)?.minimize() }
            case .hideOthers:
                // The other applications' windows minimized, as Win+Home does (hide_others.cpp).
                // 把其他 app 的視窗最小化，與 Win+Home 相同(hide_others.cpp)。
                _ = scui_win32_hide_other_applications()
            case .showAll:
                // Back: the windows Hide Others minimized, then this app's own.
                // 回來:先是 Hide Others 最小化的視窗，再是本 app 自己的視窗。
                _ = scui_win32_show_hidden_applications()
                for window in windows {
                    if presenter(window)?.state == .minimized {
                        try? presenter(window)?.restore()
                    }
                    activate(window: window)
                }
            case .help:
                showInformation(
                    "Help isn’t available for \(ProcessInfo.processInfo.processName).",
                    in: active
                )
            case .newWindow, .services:
                // New Window is resolved by SwiftCrossUI into the window group's own
                // item; Services has nothing behind it here, as on GtkBackend.
                // New Window 由 SwiftCrossUI 解析為 window group 自己的項目;Services 在此沒有任何對應，與 GtkBackend 相同。
                break
        }
    }

    /// A one-button alert, as GtkBackend shows for About and Help.
    /// 單一按鈕的警示，與 GtkBackend 在 About 與 Help 所顯示的相同。
    private func showInformation(_ text: String, in window: Window?) {
        let alert = createAlert()
        updateAlert(alert, title: text, actionLabels: ["OK"], environment: EnvironmentValues(backend: self))
        showAlert(alert, window: window) { [weak self] _ in
            self?.dismissAlert(alert, window: window)
        }
    }
}

/// The text box the text commands act on.
///
/// Not simply the focused element: a command chosen from the menu bar runs
/// while focus is on the menu item, so `FocusManager.getFocusedElement` named
/// the item and P92's Select All, Copy, Delete, Paste, Undo and Redo changed
/// nothing (2026-10-19). FocusManager's own GotFocus event keeps the last text
/// box or password box that had focus, weakly, and that is the one used when
/// focus is elsewhere -- focus returns to it when the menu closes anyway.
///
/// 文字指令作用的文字框。
///
/// 不能單純取有焦點的元素：從選單列選取的指令在焦點位於選單項目時執行，於是
/// `FocusManager.getFocusedElement` 回傳的是那個項目,P92 的全選、複製、刪除、貼上、復原、重做都沒有改到任何東西
/// (2026-10-19)。以 FocusManager 自己的 GotFocus 事件(弱參照)記住最後一個取得焦點的文字框或密碼框，焦點在別處時
/// 就用它——選單關閉後焦點本來也會回到它。
@MainActor
enum WinUITextCommandTarget {
    private final class Box {
        weak var element: WinUI.DependencyObject?
    }

    private static let last = Box()
    private static var isWatching = false

    static func watch() {
        guard !isWatching else { return }
        isWatching = true
        FocusManager.gotFocus.addHandler { _, args in
            guard let element = args?.newFocusedElement else { return }
            if element is WinUI.TextBox || element is WinUI.PasswordBox {
                MainActor.assumeIsolated { last.element = element }
            }
        }
    }

    static var element: WinUI.DependencyObject? { last.element }
}
