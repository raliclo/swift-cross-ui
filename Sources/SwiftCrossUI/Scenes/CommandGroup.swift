/// Where a ``CommandGroup`` goes: one of the groups the system's own menus are
/// made of.
///
/// The twenty placements and what each holds by default are SwiftUI's, read
/// from a real SwiftUI app rather than remembered:
/// `testapp/reference/swiftui-commands/` holds the app and its menu bar as
/// dumped on macOS 27 (2026-10-13), with nothing added, and with a group
/// before, after and in place of every placement.
///
/// | Menu | Placements, in order | Default items |
/// | --- | --- | --- |
/// | app | `appInfo`, `appSettings`, `systemServices`, `appVisibility`, `appTermination` | About; none; Services; Hide, Hide Others, Show All; Quit |
/// | File | `newItem`, `saveItem`, `importExport`, `printItem` | New Window; Close, Close All; none; none |
/// | Edit | `undoRedo`, `pasteboard`, `textEditing` | Undo, Redo; Cut, Copy, Paste, Delete, Select All; none |
/// | Format | `textFormatting` | none -- the menu exists only when an app fills it |
/// | View | `toolbar`, `sidebar` | none |
/// | Window | `windowSize`, `singleWindowList`, `windowList`, `windowArrangement` | Minimize, Zoom; none; Bring All to Front; none |
/// | Help | `help` | Help |
///
/// ``CommandGroup`` 的去處:系統自有選單所由組成的群組之一。二十個位置與各自的預設內容都是 SwiftUI 的，
/// 而且是從真正的 SwiftUI app 讀出來的，不是憑記憶:`testapp/reference/swiftui-commands/` 存有那支 app 與它在
/// macOS 27 上傾印的選單列(2026-10-13),包含什麼都沒加、以及在每個位置之前、之後、取代各放一個群組的結果。
public struct CommandGroupPlacement: Hashable, Sendable {
    /// The standard menu a placement belongs to. 位置所屬的標準選單。
    public enum Menu: Int, CaseIterable, Sendable {
        case app, file, edit, format, view, window, help
    }

    public let name: String
    public let menu: Menu

    init(_ name: String, _ menu: Menu) {
        self.name = name
        self.menu = menu
    }

    public static let appInfo = CommandGroupPlacement("appInfo", .app)
    public static let appSettings = CommandGroupPlacement("appSettings", .app)
    public static let systemServices = CommandGroupPlacement("systemServices", .app)
    public static let appVisibility = CommandGroupPlacement("appVisibility", .app)
    public static let appTermination = CommandGroupPlacement("appTermination", .app)
    public static let newItem = CommandGroupPlacement("newItem", .file)
    public static let saveItem = CommandGroupPlacement("saveItem", .file)
    public static let importExport = CommandGroupPlacement("importExport", .file)
    public static let printItem = CommandGroupPlacement("printItem", .file)
    public static let undoRedo = CommandGroupPlacement("undoRedo", .edit)
    public static let pasteboard = CommandGroupPlacement("pasteboard", .edit)
    public static let textEditing = CommandGroupPlacement("textEditing", .edit)
    public static let textFormatting = CommandGroupPlacement("textFormatting", .format)
    public static let toolbar = CommandGroupPlacement("toolbar", .view)
    public static let sidebar = CommandGroupPlacement("sidebar", .view)
    public static let windowSize = CommandGroupPlacement("windowSize", .window)
    public static let singleWindowList = CommandGroupPlacement("singleWindowList", .window)
    public static let windowList = CommandGroupPlacement("windowList", .window)
    public static let windowArrangement = CommandGroupPlacement("windowArrangement", .window)
    public static let help = CommandGroupPlacement("help", .help)

    /// Every placement, in the order the menus show them. 每個位置，依選單顯示的順序。
    public static let all: [CommandGroupPlacement] = [
        .appInfo, .appSettings, .systemServices, .appVisibility, .appTermination,
        .newItem, .saveItem, .importExport, .printItem,
        .undoRedo, .pasteboard, .textEditing,
        .textFormatting,
        .toolbar, .sidebar,
        .windowSize, .singleWindowList, .windowList, .windowArrangement,
        .help,
    ]

    /// What the system puts in the group when the app replaces nothing.
    /// app 沒有取代時，系統放在這個群組裡的東西。
    public var defaultCommands: [StandardCommand] {
        switch name {
            case "appInfo": [.about]
            case "systemServices": [.services]
            case "appVisibility": [.hide, .hideOthers, .showAll]
            case "appTermination": [.quit]
            case "newItem": [.newWindow]
            case "saveItem": [.close, .closeAll]
            case "undoRedo": [.undo, .redo]
            case "pasteboard": [.cut, .copy, .paste, .delete, .selectAll]
            case "windowSize": [.minimize, .zoom]
            case "windowList": [.bringAllToFront]
            case "help": [.help]
            default: []
        }
    }
}

/// An item the system supplies in its own menus.
///
/// AppKit has each of these as a responder-chain action; on the backends whose
/// menus this framework builds itself, ``BackendFeatures/StandardCommands``
/// says which exist and carries them out.
/// 系統在自己的選單裡提供的項目。AppKit 的每一項都是 responder chain 上的動作;在選單由本框架自己建出的 backend 上，
/// 由 ``BackendFeatures/StandardCommands`` 說明哪些存在並加以執行。
public enum StandardCommand: String, CaseIterable, Sendable {
    case about, services, hide, hideOthers, showAll, quit
    case newWindow, close, closeAll
    case undo, redo, cut, copy, paste, delete, selectAll
    case minimize, zoom, bringAllToFront
    case help

    /// The title macOS gives the item. macOS 給這個項目的標題。
    public func title(appName: String) -> String {
        switch self {
            case .about: "About \(appName)"
            case .services: "Services"
            case .hide: "Hide \(appName)"
            case .hideOthers: "Hide Others"
            case .showAll: "Show All"
            case .quit: "Quit \(appName)"
            case .newWindow: "New Window"
            case .close: "Close"
            case .closeAll: "Close All"
            case .undo: "Undo"
            case .redo: "Redo"
            case .cut: "Cut"
            case .copy: "Copy"
            case .paste: "Paste"
            case .delete: "Delete"
            case .selectAll: "Select All"
            case .minimize: "Minimize"
            case .zoom: "Zoom"
            case .bringAllToFront: "Bring All to Front"
            case .help: "\(appName) Help"
        }
    }

    /// The shortcut macOS gives the item, where it has one.
    /// macOS 給這個項目的快捷鍵(若有)。
    public var shortcut: KeyboardShortcut? {
        switch self {
            case .hide: KeyboardShortcut("h")
            case .hideOthers: KeyboardShortcut("h", modifiers: [.command, .option])
            case .quit: KeyboardShortcut("q")
            case .newWindow: KeyboardShortcut("n")
            case .close: KeyboardShortcut("w")
            case .closeAll: KeyboardShortcut("w", modifiers: [.command, .option])
            case .undo: KeyboardShortcut("z")
            case .redo: KeyboardShortcut("z", modifiers: [.command, .shift])
            case .cut: KeyboardShortcut("x")
            case .copy: KeyboardShortcut("c")
            case .paste: KeyboardShortcut("v")
            case .selectAll: KeyboardShortcut("a")
            case .minimize: KeyboardShortcut("m")
            case .help: KeyboardShortcut("?")
            default: nil
        }
    }
}

/// Commands placed relative to one of the system's own groups.
///
/// ```swift
/// .commands {
///     CommandGroup(after: .newItem) {
///         Button("New From Template") { ... }
///     }
///     CommandGroup(replacing: .help) {
///         Button("Open the Manual") { ... }
///     }
/// }
/// ```
///
/// `before:` and `after:` put the content at the start or the end of the group
/// and leave its own items alone; `replacing:` takes them out.
///
/// **On macOS the menus are always there.** On the other platforms nothing
/// changes for an app that does not ask: GTK and WinUI show a menu bar only for
/// the menus the app fills, with no default items, and a phone shows nothing
/// and keeps the shortcuts. ``Scene/enableMenu(_:)`` turns the standard menus
/// on there, default items included.
///
/// 相對於系統自有群組放置的指令。`before:` 與 `after:` 把內容放在群組的開頭或結尾，不動群組自己的項目;
/// `replacing:` 則把它們拿掉。macOS 上選單永遠存在。其他平台上，沒有要求的 app 什麼都不會變:GTK 與 WinUI 只替 app
/// 有放東西的選單顯示選單列、沒有預設項目，手機什麼都不顯示、只保留快捷鍵。``Scene/enableMenu(_:)`` 會在那些平台上
/// 打開標準選單，包含預設項目。
public struct CommandGroup {
    enum Position {
        case before, after, replacing
    }

    var placement: CommandGroupPlacement
    var position: Position
    var content: [MenuItem]

    @MainActor
    public init(before placement: CommandGroupPlacement, @ViewBuilder content: () -> some View) {
        self.placement = placement
        self.position = .before
        self.content = content()._asMenuItems
    }

    @MainActor
    public init(after placement: CommandGroupPlacement, @ViewBuilder content: () -> some View) {
        self.placement = placement
        self.position = .after
        self.content = content()._asMenuItems
    }

    @MainActor
    public init(
        replacing placement: CommandGroupPlacement, @ViewBuilder content: () -> some View
    ) {
        self.placement = placement
        self.position = .replacing
        self.content = content()._asMenuItems
    }
}

/// The application's menus, laid out: each standard menu as its groups, and the
/// app's own menus between View and Window, where SwiftUI puts them.
///
/// Made by the framework, in Swift, for every backend. AppKitBackend renders the
/// standard commands as the system's own items; the other backends turn the
/// whole layout into the menus they already draw (``submenus(perform:)``).
///
/// 排好版面的應用程式選單:每個標準選單由它的群組組成，app 自己的選單放在 View 與 Window 之間，與 SwiftUI 相同。
/// 由框架以 Swift 為每個 backend 產生。AppKitBackend 把標準指令畫成系統自己的項目;其他 backend 把整個版面轉成它們
/// 本來就會畫的選單(``submenus(perform:)``)。
public struct CommandLayout {
    public enum Entry {
        case standard(StandardCommand)
        case item(ResolvedMenu.Item)
    }

    public struct Section {
        public var placement: CommandGroupPlacement?
        public var entries: [Entry]
        /// How many of `entries`, from the start, the app put before the group.
        /// `entries` 開頭有幾個是 app 放在群組之前的。
        public var leading = 0
        /// Whether the app replaced the group's own items. app 是否取代了群組自己的項目。
        public var isReplaced = false
    }

    public struct Menu {
        /// `nil` for a menu the app made with ``CommandMenu``.
        /// app 以 ``CommandMenu`` 建立的選單為 `nil`。
        public var standard: CommandGroupPlacement.Menu?
        public var title: String
        public var sections: [Section]
    }

    public var menus: [Menu]
    public var appName: String
    /// Whether the app turned the standard menus on (``Scene/enableMenu(_:)``). A backend that
    /// draws the layout itself reads it where the platform shows no menu unless asked.
    /// app 是否打開了標準選單(``Scene/enableMenu(_:)``)。自己畫版面的 backend 在平台不會主動顯示選單的地方讀它。
    public var isMenuEnabled = false
    /// Opens another window of the app's window group, for New Window; `nil` when the app has
    /// no group that can be opened by itself, and then the item is left out.
    /// 替「New Window」開啟 app 的 window group 的另一個視窗;app 沒有可以單獨開啟的 group 時為 `nil`,此時該項目不出現。
    public var newWindow: (@MainActor () -> Void)?

    /// The layout as plain menus: a separator between sections, and each
    /// standard command a button that calls `perform`, with its shortcut.
    /// 把版面轉成一般的選單:區段之間放分隔線，每個標準指令是一個呼叫 `perform` 的按鈕並帶著它的快捷鍵。
    @MainActor
    public func submenus(
        perform: @escaping @MainActor (StandardCommand) -> Void
    ) -> [ResolvedMenu.Submenu] {
        menus.map { menu in
            var items: [ResolvedMenu.Item] = []
            for section in menu.sections {
                if !items.isEmpty { items.append(.separator) }
                for entry in section.entries {
                    switch entry {
                        case .item(let item):
                            items.append(item)
                        case .standard(.services):
                            // What macOS shows when no service applies to the selection.
                            // macOS 在沒有任何服務適用於選取內容時顯示的樣子。
                            items.append(
                                .submenu(
                                    ResolvedMenu.Submenu(
                                        label: StandardCommand.services.title(appName: appName),
                                        content: ResolvedMenu(items: [
                                            .button("No Services Apply", nil)
                                        ]))))
                        case .standard(let command):
                            let button = ResolvedMenu.Item.button(
                                command.title(appName: appName),
                                { [newWindow] in
                                    if command == .newWindow, let newWindow {
                                        newWindow()
                                    } else {
                                        perform(command)
                                    }
                                })
                            if let shortcut = command.shortcut {
                                items.append(
                                    .modifiedEnvironment(button) {
                                        $0.with(\.keyboardShortcut, shortcut)
                                    })
                            } else {
                                items.append(button)
                            }
                    }
                }
            }
            return ResolvedMenu.Submenu(label: menu.title, content: ResolvedMenu(items: items))
        }
    }

    /// The layout as indented text, one item a line and `---` for a separator:
    /// the form the reference dumps in `testapp/reference/swiftui-commands/`
    /// are in, so the two can be compared line by line.
    /// 把版面寫成縮排文字，每個項目一行、分隔線為 `---`:與 `testapp/reference/swiftui-commands/` 的參考傾印
    /// 同一種格式，兩者可以逐行比對。
    public var textDescription: String {
        var lines: [String] = []
        func describe(_ item: ResolvedMenu.Item, _ depth: Int) {
            let pad = String(repeating: "  ", count: depth)
            switch item {
                case .button(let label, _): lines.append(pad + label)
                case .toggle(let label, _, _): lines.append(pad + label)
                case .separator: lines.append(pad + "---")
                case .submenu(let submenu):
                    lines.append(pad + submenu.label)
                    submenu.content.items.forEach { describe($0, depth + 1) }
                case .modifiedEnvironment(let inner, _): describe(inner, depth)
            }
        }
        for menu in menus {
            lines.append(menu.title)
            var first = true
            for section in menu.sections {
                if !first { lines.append("  ---") }
                first = false
                for entry in section.entries {
                    switch entry {
                        case .standard(let command):
                            lines.append("  " + command.title(appName: appName))
                        case .item(let item): describe(item, 1)
                    }
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}
