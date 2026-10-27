import AndroidKit
import SwiftCrossUI
import SwiftJava

/// ``CommandGroup`` on Android.
///
/// A phone has no menu bar. By default nothing is shown and the items'
/// shortcuts work, as before there were groups. With ``Scene/enableMenu(_:)``
/// a menu button sits at the top left and opens the standard menus as the
/// submenus of one `PopupMenu` -- the layout the framework makes in Swift for
/// every backend, with the standard commands this backend has.
///
/// The button is this framework's own design;
/// there is no SwiftUI on Android to copy.
///
/// Android 上的 ``CommandGroup``。手機沒有選單列:預設什麼都不顯示，項目的快捷鍵照舊有效;``Scene/enableMenu(_:)``
/// 打開後左上角出現選單按鈕，以一個 `PopupMenu` 的子選單打開各個標準選單——版面是框架以 Swift 為每個 backend 排出的，
/// 加上本 backend 具備的標準指令。那個按鈕是本框架自己的設計;Android 上沒有 SwiftUI 可以照抄。
extension AndroidBackend: BackendFeatures.CommandLayouts {
    nonisolated(unsafe) static var scrollHosts: [RootScrollHost] = []
    nonisolated(unsafe) static var commandLayout: CommandLayout?
    nonisolated(unsafe) static var commandEnvironment: EnvironmentValues?
    nonisolated(unsafe) static var commandPopup: AndroidKit.PopupMenu?

    public func setApplicationCommands(_ layout: CommandLayout, environment: EnvironmentValues) {
        Self.commandLayout = layout
        Self.commandEnvironment = environment
        // The app's own items, for the shortcut table.
        // app 自己的項目，供快捷鍵表使用。
        let own = layout.menus.map { menu in
            ResolvedMenu.Submenu(
                label: menu.title,
                content: ResolvedMenu(
                    items: menu.sections.flatMap { section in
                        section.entries.compactMap { entry -> ResolvedMenu.Item? in
                            if case .item(let item) = entry { return item }
                            return nil
                        }
                    }
                )
            )
        }
        setApplicationMenu(own, environment: environment)
        for host in Self.scrollHosts { applyMenuButton(to: host) }
    }

    func applyMenuButton(to host: RootScrollHost) {
        let shown = Self.commandLayout?.isMenuEnabled ?? false
        host.setOnMenuButton(
            shown
                ? SwiftAction(environment: Self.env) { [weak self] in
                    MainActor.assumeIsolated { self?.showCommandMenu(from: host) }
                } : nil
        )
        host.setMenuButtonShown(Self.activity, shown)
    }

    private func showCommandMenu(from host: RootScrollHost) {
        guard var layout = Self.commandLayout, let environment = Self.commandEnvironment,
              let anchor = host.getMenuButton()
        else { return }
        // The process is app_process64 here, and the activity's title is the window's; the
        // application's label is the app's name.
        // 這裡的行程名稱是 app_process64,activity 的標題則是視窗的;application 的 label 才是 app 的名稱。
        if let title = Self.activity.getApplicationInfo()?
            .loadLabel(Self.activity.getPackageManager())?.toString(), !title.isEmpty
        {
            layout.appName = title
        }
        let appName = layout.appName
        layout.menus = layout.menus.compactMap { menu in
            var menu = menu
            menu.sections = menu.sections.compactMap { section in
                // No Format menu, as in the iPhone's menu button (89793ac1): the textFormatting
                // group is dropped, and with it the menu it was the only part of.
                // 與 iPhone 的選單按鈕相同(89793ac1):沒有 Format 選單。丟掉 textFormatting 群組，只由它組成的那個選單也就一併消失。
                if section.placement?.name == "textFormatting" { return nil }
                var section = section
                section.entries = section.entries.filter { entry in
                    if case .standard(let command) = entry { return hasStandardCommand(command) }
                    return true
                }
                return section.entries.isEmpty ? nil : section
            }
            if menu.standard == .app { menu.title = appName }
            return menu.sections.isEmpty ? nil : menu
        }
        let submenus = layout.submenus { [weak self] in self?.performStandardCommand($0) }
        let popup = AndroidKit.PopupMenu.construct(Self.activity, anchor, environment: Self.env)
        Menu.realizeMenu(
            menu: popup.getMenu(),
            items: submenus.map { .submenu($0) },
            environment: environment
        )
        // Kept: the popup holds the listeners, and must outlive this call.
        // 留著:popup 持有那些 listener,必須活得比這次呼叫久。
        Self.commandPopup = popup
        popup.show()
    }
}

extension AndroidBackend: BackendFeatures.StandardCommands {
    /// The editing commands, which every Android text view carries as context-menu
    /// items; the focused one is asked to carry it out. Delete is the Delete key.
    /// The window and app commands have nothing to act on in a phone's one window.
    /// 編輯指令:每個 Android 文字 view 都以內容選單項目的形式具備，交給目前聚焦的那個執行。Delete 就是 Delete 鍵。
    /// 視窗與 app 類的指令在手機的單一視窗裡沒有作用對象。
    public func hasStandardCommand(_ command: StandardCommand) -> Bool {
        Self.textMenuItem(command) != nil || command == .delete
    }

    public func performStandardCommand(_ command: StandardCommand) {
        guard let focused = Self.activity.getWindow()?.getDecorView()?.findFocus() else { return }
        if command == .delete {
            let delete: Int32 = 67 // KeyEvent.KEYCODE_DEL
            for action in [Int32(0), 1] {
                _ = focused.dispatchKeyEvent(AndroidKit.KeyEvent(action, delete))
            }
            return
        }
        guard let item = Self.textMenuItem(command),
              let text = focused.as(AndroidKit.TextView.self)
        else { return }
        _ = text.onTextContextMenuItem(item)
    }

    /// `android.R.id.selectAll`, `cut`, `copy`, `paste`, `undo`, `redo`.
    static func textMenuItem(_ command: StandardCommand) -> Int32? {
        switch command {
            case .selectAll: 0x0102_001f
            case .cut: 0x0102_0020
            case .copy: 0x0102_0021
            case .paste: 0x0102_0022
            case .undo: 0x0102_0032
            case .redo: 0x0102_0033
            default: nil
        }
    }
}
