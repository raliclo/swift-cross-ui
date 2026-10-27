import Foundation

/// The menus and command groups an app adds to the menu bar.
/// app 加到選單列的選單與指令群組。
public struct Commands {
    /// Represents an empty menu bar.
    public static var empty: Commands {
        Commands(menus: [])
    }

    var menus: [CommandMenu]
    var groups: [CommandGroup]
    /// Set by ``Scene/enableMenu(_:)``. 由 ``Scene/enableMenu(_:)`` 設定。
    var isMenuEnabled: Bool

    init(menus: [CommandMenu], groups: [CommandGroup] = [], isMenuEnabled: Bool = false) {
        self.menus = menus
        self.groups = groups
        self.isMenuEnabled = isMenuEnabled
    }

    /// Overlays `newCommands` onto `self`: its menus and groups follow `self`'s.
    ///
    /// **Menus with the same name are not merged**, as in SwiftUI, where two
    /// `CommandMenu("File")` are two menus and neither is the system's File
    /// menu (`testapp/reference/swiftui-commands/dupfile.txt`). An item goes
    /// into a system menu through
    /// ``CommandGroup``.
    ///
    /// 把 `newCommands` 疊到 `self` 上:它的選單與群組接在 `self` 的後面。同名的選單不合併，與 SwiftUI 相同——
    /// 兩個 `CommandMenu("File")` 是兩個選單，也都不是系統的 File 選單。要把項目放進系統選單，
    /// 用 ``CommandGroup``。
    ///
    /// - Parameter newCommands: The commands to overlay.
    public consuming func overlayed(with newCommands: Commands) -> Commands {
        menus += newCommands.menus
        groups += newCommands.groups
        isMenuEnabled = isMenuEnabled || newCommands.isMenuEnabled
        return self
    }

    /// Resolves the app's own menus to a representation used by backends.
    @MainActor
    func resolve() -> [ResolvedMenu.Submenu] {
        menus.map { menu in
            menu.resolve()
        }
    }

    /// Lays the menus out: the standard menus as their groups, with the app's
    /// groups put before, after or in place of each, and the app's own menus
    /// between View and Window.
    ///
    /// - Parameters:
    ///   - appName: The name the app menu and its items carry.
    ///   - defaults: Which standard command to include, for a backend that has
    ///     the standard menus on. `nil` leaves every default out, and then only
    ///     the standard menus the app put something into exist.
    ///
    /// 排出選單版面:標準選單由各自的群組組成，app 的群組放在每個群組之前、之後或取代它，app 自己的選單放在
    /// View 與 Window 之間。`defaults` 為 `nil` 時不含任何預設項目，此時只有 app 有放東西的標準選單才存在。
    @MainActor
    public func layout(
        appName: String,
        defaults: ((StandardCommand) -> Bool)?,
        newWindow: (@MainActor () -> Void)? = nil,
        sceneItems: [CommandGroupPlacement: [ResolvedMenu.Item]] = [:]
    ) -> CommandLayout {
        var result: [CommandLayout.Menu] = []
        func standardMenu(_ kind: CommandGroupPlacement.Menu) -> CommandLayout.Menu? {
            var sections: [CommandLayout.Section] = []
            for placement in CommandGroupPlacement.all where placement.menu == kind {
                let own = groups.filter { $0.placement == placement }
                func items(_ position: CommandGroup.Position) -> [CommandLayout.Entry] {
                    own.filter { $0.position == position }
                        .flatMap { Menu.resolve(items: $0.content).items }
                        .map { .item($0) }
                }
                var entries = items(.before)
                let leading = entries.count
                let isReplaced = own.contains { $0.position == .replacing }
                if own.contains(where: { $0.position == .replacing }) {
                    entries += items(.replacing)
                } else if let defaults {
                    entries += placement.defaultCommands
                        .filter { $0 != .newWindow || newWindow != nil }
                        .filter(defaults).map { .standard($0) }
                    entries += (sceneItems[placement] ?? []).map { .item($0) }
                }
                entries += items(.after)
                if !entries.isEmpty {
                    sections.append(
                        CommandLayout.Section(
                            placement: placement,
                            entries: entries,
                            leading: leading,
                            isReplaced: isReplaced
                        )
                    )
                }
            }
            // With the standard menus on, each is there even when empty -- macOS
            // shows an empty View menu -- except Format, which SwiftUI only makes
            // for an app that fills it.
            // 標準選單打開時，每個選單即使是空的也存在(macOS 會顯示空的 View 選單)——Format 除外，SwiftUI 只在
            // app 填了內容時才建立它。
            if sections.isEmpty, defaults == nil || kind == .format { return nil }
            let title: String =
                switch kind {
                    case .app: appName
                    case .file: "File"
                    case .edit: "Edit"
                    case .format: "Format"
                    case .view: "View"
                    case .window: "Window"
                    case .help: "Help"
                }
            return CommandLayout.Menu(standard: kind, title: title, sections: sections)
        }
        for kind in [CommandGroupPlacement.Menu.app, .file, .edit, .format, .view] {
            if let menu = standardMenu(kind) { result.append(menu) }
        }
        for menu in menus {
            let resolved = menu.resolve()
            result.append(
                CommandLayout.Menu(
                    standard: nil,
                    title: resolved.label,
                    sections: [
                        CommandLayout.Section(
                            placement: nil,
                            entries: resolved.content.items.map { .item($0) }
                        )
                    ]
                )
            )
        }
        for kind in [CommandGroupPlacement.Menu.window, .help] {
            if let menu = standardMenu(kind) { result.append(menu) }
        }
        return CommandLayout(menus: result, appName: appName, newWindow: newWindow)
    }
}

extension Scene {
    /// Turns the standard menus on where the platform does not show them by
    /// itself -- the app menu, File, Edit, View, Window and Help, with the items
    /// macOS puts in each.
    ///
    /// macOS always has them and this changes nothing there. On GTK and WinUI
    /// the menu bar otherwise holds only what the app put in it; on a phone
    /// there is otherwise no menu at all, only the shortcuts.
    /// ``MenuBarSettings/isEnabled`` is the same switch as a variable.
    ///
    /// 在平台不會自己顯示標準選單的地方把它們打開——app 選單、File、Edit、View、Window 與 Help,以及 macOS 放在各選單裡的
    /// 項目。macOS 本來就有，這在那裡不改變任何東西。GTK 與 WinUI 的選單列原本只有 app 放進去的東西;手機原本完全沒有選單，
    /// 只有快捷鍵。``MenuBarSettings/isEnabled`` 是同一個開關的變數形式。
    public func enableMenu(_ isEnabled: Bool = true) -> some Scene {
        CommandsModifier(
            content: self,
            commands: Commands(menus: [], isMenuEnabled: isEnabled)
        )
    }
}

/// The switch ``Scene/enableMenu(_:)`` sets, as a variable: set it before the
/// app starts, or at any time and the menus follow at the next update.
/// ``Scene/enableMenu(_:)`` 所設定的開關，以變數形式提供:在 app 啟動前設定，或隨時設定，選單會在下一次更新時跟上。
@MainActor
public enum MenuBarSettings {
    public static var isEnabled = false
}

extension Commands {
    /// Hands the menus to the backend, in the form it takes.
    ///
    /// A backend with ``BackendFeatures/CommandLayouts`` gets the layout and
    /// draws the standard commands itself. Any other gets plain menus: the
    /// standard menus the app put something into, and -- with the standard menus
    /// on -- the default items the backend has.
    ///
    /// **With no ``CommandGroup`` and the switch off, the second path hands over
    /// exactly the app's own menus**, which is what it did before there were
    /// groups.
    /// 把選單以 backend 接受的形式交給它。有 ``BackendFeatures/CommandLayouts`` 的 backend 收到版面，自己畫標準指令。
    /// 其他 backend 收到一般的選單:app 有放東西的標準選單，以及(標準選單打開時)backend 具備的預設項目。
    /// 沒有任何 ``CommandGroup`` 且開關關閉時，第二條路交出去的正好就是 app 自己的選單，與有群組之前相同。
    @MainActor
    func apply(to backend: Any, environment: EnvironmentValues) {
        let appName = ProcessInfo.processInfo.processName
        // New Window opens the app's window group when it has one; with several, SwiftUI shows a
        // New submenu naming each, and single windows are listed in the Window menu.
        // app 只有一個 window group 時「New Window」開啟它;有多個時 SwiftUI 顯示逐一列名的 New 子選單，
        // 單一視窗則列在 Window 選單。
        let multipleWindows = (backend as? any BaseAppBackend)?.supportsMultipleWindows ?? false
        let scenes = WindowOpeners.defaults()
        let newWindow = multipleWindows ? scenes.newWindow : nil
        let sceneItems = multipleWindows ? scenes.items : [:]
        if let backend = backend as? any BackendFeatures.CommandLayouts {
            var layout = layout(
                appName: appName,
                defaults: { _ in true },
                newWindow: newWindow,
                sceneItems: sceneItems
            )
            layout.isMenuEnabled = isMenuEnabled || MenuBarSettings.isEnabled
            backend.setApplicationCommands(layout, environment: environment)
            return
        }
        guard let menus = backend as? any BackendFeatures.ApplicationMenus else { return }
        let standard = backend as? any BackendFeatures.StandardCommands
        let enabled =
            isMenuEnabled || MenuBarSettings.isEnabled
            || (standard?.showsStandardMenusByDefault ?? false)
        let layout = layout(
            appName: appName,
            defaults: enabled ? standard
                .map { backend in { backend.hasStandardCommand($0) } } : nil,
            newWindow: newWindow,
            sceneItems: enabled ? sceneItems : [:]
        )
        menus.setApplicationMenu(
            layout.submenus { standard?.performStandardCommand($0) },
            environment: environment
        )
    }
}

/// The app's window scenes, in the order they were declared, for the menus:
/// File > New Window (or, with several groups, the New submenu that names each)
/// and the single windows the Window menu lists
/// (`testapp/reference/swiftui-commands/two-groups.txt`).
/// app 的視窗場景，依宣告順序，供選單使用:File > New Window(有多個 group 時則是逐一列名的 New 子選單),
/// 以及 Window 選單所列的單一視窗。
@MainActor
enum WindowOpeners {
    struct Entry {
        var key: String
        var title: String
        var isGroup: Bool
        var open: @MainActor () -> Void
    }

    static var entries: [Entry] = []

    static func register(
        key: String,
        title: String,
        isGroup: Bool,
        open: @escaping @MainActor () -> Void
    ) {
        let entry = Entry(key: key, title: title, isGroup: isGroup, open: open)
        if let index = entries.firstIndex(where: { $0.key == key }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
    }

    /// What the framework itself puts in a group, beside the standard commands.
    /// 框架自己放進群組的東西(標準指令之外)。
    static func defaults() -> (
        newWindow: (@MainActor () -> Void)?,
        items: [CommandGroupPlacement: [ResolvedMenu.Item]]
    ) {
        let groups = entries.filter(\.isGroup)
        var items: [CommandGroupPlacement: [ResolvedMenu.Item]] = [:]
        if groups.count > 1 {
            // SwiftUI: a New submenu, one item a group, Command-N on the first.
            // SwiftUI:一個 New 子選單，每個 group 一項，第一項帶 Command-N。
            let children = groups.enumerated().map { index, group -> ResolvedMenu.Item in
                let button = ResolvedMenu.Item.button("New \(group.title) Window", group.open)
                return index == 0
                    ? .modifiedEnvironment(button) { $0.with(
                        \.keyboardShortcut,
                        KeyboardShortcut("n")
                    ) }
                    : button
            }
            items[.newItem] = [
                .submenu(ResolvedMenu.Submenu(label: "New", content: ResolvedMenu(items: children)))
            ]
        }
        let singles = entries.filter { !$0.isGroup }
        if !singles.isEmpty {
            items[.singleWindowList] = singles.map { .button($0.title, $0.open) }
        }
        return (groups.count == 1 ? groups[0].open : nil, items)
    }
}
