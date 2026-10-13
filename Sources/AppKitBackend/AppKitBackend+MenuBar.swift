import AppKit
@_spi(Backends) import SwiftCrossUI

@MainActor
enum MenuBar {
    // You may notice that multiple different base types are used in the
    // action selectors of the various menu items. This is because the
    // selectors get sent to the app's first responder at the time of
    // the command getting sent. If the first responder doesn't have a
    // method matching the selector, then AppKit automatically disables
    // the corresponding menu item.

    /// The app's name to use in menus.
    private static var appName: String {
        ProcessInfo.processInfo.processName
    }

    private static var appMenu: (appMenu: NSMenu, servicesMenu: NSMenu) {
        let servicesMenu = NSMenu(title: "Services")
        let servicesMenuItem = NSMenuItem(title: "Services", action: nil)
        servicesMenuItem.submenu = servicesMenu

        // The first menu item is special and always takes on the name of the app.
        let appMenu = NSMenu(
            title: appName,
            items: [
                NSMenuItem(
                    title: "About \(appName)",
                    action: #selector(NSApplication.orderFrontStandardAboutPanel(_:))
                ),
                NSMenuItem.separator(),
                servicesMenuItem,
                NSMenuItem.separator(),
                NSMenuItem(
                    title: "Hide \(appName)",
                    action: #selector(NSApplication.hide(_:)),
                    keyEquivalent: ("h", .command)
                ),
                NSMenuItem(
                    title: "Hide Others",
                    action: #selector(NSApplication.hideOtherApplications(_:)),
                    keyEquivalent: ("h", [.option, .command])
                ),
                NSMenuItem(
                    title: "Show All",
                    action: #selector(NSApplication.unhideAllApplications(_:))
                ),
                NSMenuItem.separator(),
                NSMenuItem(
                    title: "Quit \(appName)",
                    action: #selector(NSApplication.terminate(_:)),
                    keyEquivalent: ("q", .command)
                ),
            ]
        )

        return (appMenu, servicesMenu)
    }

    private static var fileMenu: NSMenu {
        NSMenu(
            title: "File",
            items: [
                NSMenuItem(
                    title: "Close",
                    action: #selector(NSWindow.performClose(_:)),
                    keyEquivalent: ("w", .command)
                )
            ]
        )
    }

    private static var editMenu: NSMenu {
        NSMenu(
            title: "Edit",
            items: [
                // NB: We've failed to find which class (if any) `undo:` and `redo: are supposed
                // to come from, and the following Apple documentation article makes it sound
                // like they're just stringly-typed ObjC messages:
                // https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/UndoArchitecture/Articles/AppKitUndo.html
                //
                // The double parentheses are needed to silence compiler warnings.
                NSMenuItem(
                    title: "Undo",
                    action: Selector(("undo:")),
                    keyEquivalent: ("z", .command)
                ),
                NSMenuItem(
                    title: "Redo",
                    action: Selector(("redo:")),
                    keyEquivalent: ("z", [.command, .shift])
                ),

                NSMenuItem.separator(),

                NSMenuItem(
                    title: "Cut",
                    action: #selector(NSText.cut(_:)),
                    keyEquivalent: ("x", .command)
                ),
                NSMenuItem(
                    title: "Copy",
                    action: #selector(NSText.copy(_:)),
                    keyEquivalent: ("c", .command)
                ),
                NSMenuItem(
                    title: "Paste",
                    action: #selector(NSText.paste(_:)),
                    keyEquivalent: ("v", .command)
                ),
                NSMenuItem(
                    title: "Delete",
                    action: #selector(NSText.delete(_:))
                ),
                NSMenuItem(
                    title: "Select All",
                    action: #selector(NSText.selectAll(_:)),
                    keyEquivalent: ("a", .command)
                ),
            ]
        )
    }

    private static var viewMenu: NSMenu {
        // AppKit adds the default menu items for us.
        NSMenu(title: "View")
    }

    private static var windowMenu: NSMenu {
        NSMenu(
            title: "Window",
            items: [
                // AppKit automatically adds the Command+M shortcut to Minimize. (This is the
                // only menu item I know of where this happens.)
                NSMenuItem(
                    title: "Minimize",
                    action: #selector(NSWindow.performMiniaturize(_:))
                ),
                NSMenuItem(
                    title: "Zoom",
                    action: #selector(NSWindow.performZoom(_:))
                ),

                NSMenuItem.separator(),
                NSMenuItem(
                    title: "Bring All to Front",
                    action: #selector(NSApplication.arrangeInFront(_:))
                ),
            ]
        )
    }

    private static var helpMenu: NSMenu {
        NSMenu(
            title: "Help",
            items: [
                NSMenuItem(
                    title: "\(appName) Help",
                    action: #selector(NSApplication.showHelp(_:))
                )
            ]
        )
    }

    static func setUpMenuBar(extraMenus: [NSMenuItem]) {
        let (appMenu, servicesMenu) = MenuBar.appMenu
        let fileMenu = MenuBar.fileMenu
        let editMenu = MenuBar.editMenu
        let viewMenu = MenuBar.viewMenu
        let windowMenu = MenuBar.windowMenu
        let helpMenu = MenuBar.helpMenu

        var uniqueMenus: [NSMenuItem] = []
        do {
            let defaultMenus = [fileMenu, editMenu, viewMenu, windowMenu, helpMenu]
            for menu in extraMenus {
                // To merge app-defined File, Edit, View, Window, and Help menus with our own, we
                // check if the menu titles match. If they do, we move every item from the user's
                // menu to our own.
                if let submenu = menu.submenu,
                   let matchingMenu = defaultMenus.first(where: { $0.title == menu.title })
                {
                    let items = submenu.items
                    submenu.removeAllItems()
                    matchingMenu.items += items
                } else {
                    uniqueMenus.append(menu)
                }
            }
        }

        let menuBar = NSMenu()
        for menu in [appMenu, fileMenu, editMenu, viewMenu] {
            let menuItem = NSMenuItem()
            menuItem.submenu = menu
            menuBar.addItem(menuItem)
        }
        menuBar.items += uniqueMenus
        for menu in [windowMenu, helpMenu] {
            let menuItem = NSMenuItem()
            menuItem.submenu = menu
            menuBar.addItem(menuItem)
        }

        NSApplication.shared.servicesMenu = servicesMenu
        NSApplication.shared.windowsMenu = windowMenu
        NSApplication.shared.helpMenu = helpMenu
        NSApplication.shared.mainMenu = menuBar
    }
}

extension NSMenuItem {
    convenience init(
        title: String,
        action selector: Selector?,
        keyEquivalent: (key: String, modifiers: NSEvent.ModifierFlags)? = nil
    ) {
        self.init(title: title, action: selector, keyEquivalent: keyEquivalent?.key ?? "")
        if let modifiers = keyEquivalent?.modifiers {
            self.keyEquivalentModifierMask = modifiers
        }
    }
}

extension NSMenu {
    convenience init(title: String, items: [NSMenuItem]) {
        self.init(title: title)
        self.items = items
    }
}

// MARK: Command layouts

extension AppKitBackend: BackendFeatures.CommandLayouts {
    public func setApplicationCommands(_ layout: CommandLayout, environment: EnvironmentValues) {
        MenuBar.setUp(layout: layout, environment: environment)
    }
}

extension MenuBar {
    /// The menu bar from the framework's layout: SwiftUI's menus and groups, with
    /// each standard command as AppKit's own item, so the responder chain
    /// enables Undo or Copy exactly when something can do it.
    ///
    /// `setUpMenuBar(extraMenus:)` above is what built the bar until 2026-10-13
    /// and merged an app menu named File into the system's; the framework no
    /// longer calls it.
    /// 依框架的版面建立選單列:SwiftUI 的選單與群組，每個標準指令都是 AppKit 自己的項目，所以 Undo 或 Copy 會由
    /// responder chain 在有東西能執行時才啟用。上方的 `setUpMenuBar(extraMenus:)` 是 2026-10-13 之前建立選單列的方式，
    /// 會把名為 File 的 app 選單併進系統的;框架已不再呼叫它。
    static func setUp(layout: CommandLayout, environment: EnvironmentValues) {
        CommandTarget.shared.newWindow = layout.newWindow
        let menuBar = NSMenu()
        var servicesMenu: NSMenu?
        var windowMenu: NSMenu?
        var helpMenu: NSMenu?
        for menu in layout.menus {
            let rendered = NSMenu(title: menu.title)
            for (index, section) in menu.sections.enumerated() {
                if index > 0 { rendered.addItem(.separator()) }
                for entry in section.entries {
                    switch entry {
                        case .item(let item):
                            rendered.addItem(
                                AppKitBackend.renderMenuItem(item, environment: environment)
                            )
                        case .standard(let command):
                            let item = standardItem(command, appName: layout.appName)
                            if command == .services { servicesMenu = item.submenu }
                            rendered.addItem(item)
                    }
                }
            }
            let holder = NSMenuItem()
            holder.title = menu.title
            holder.submenu = rendered
            menuBar.addItem(holder)
            if menu.standard == .window { windowMenu = rendered }
            if menu.standard == .help { helpMenu = rendered }
        }
        NSApplication.shared.servicesMenu = servicesMenu
        NSApplication.shared.windowsMenu = windowMenu
        NSApplication.shared.helpMenu = helpMenu
        NSApplication.shared.mainMenu = menuBar
    }

    private static func standardItem(_ command: StandardCommand, appName: String) -> NSMenuItem {
        let selector: Selector? =
            switch command {
                case .about: #selector(NSApplication.orderFrontStandardAboutPanel(_:))
                case .services: nil
                case .hide: #selector(NSApplication.hide(_:))
                case .hideOthers: #selector(NSApplication.hideOtherApplications(_:))
                case .showAll: #selector(NSApplication.unhideAllApplications(_:))
                case .quit: #selector(NSApplication.terminate(_:))
                case .newWindow: #selector(CommandTarget.openNewWindow(_:))
                case .close: #selector(NSWindow.performClose(_:))
                case .closeAll: #selector(CommandTarget.closeAllWindows(_:))
                case .undo: Selector(("undo:"))
                case .redo: Selector(("redo:"))
                case .cut: #selector(NSText.cut(_:))
                case .copy: #selector(NSText.copy(_:))
                case .paste: #selector(NSText.paste(_:))
                case .delete: #selector(NSText.delete(_:))
                case .selectAll: #selector(NSText.selectAll(_:))
                case .minimize: #selector(NSWindow.performMiniaturize(_:))
                case .zoom: #selector(NSWindow.performZoom(_:))
                case .bringAllToFront: #selector(NSApplication.arrangeInFront(_:))
                case .help: #selector(NSApplication.showHelp(_:))
            }
        let item = NSMenuItem(
            title: command.title(appName: appName),
            action: selector,
            keyEquivalent: ""
        )
        if let shortcut = command.shortcut {
            item.keyEquivalent = String(shortcut.key.character)
            var flags: NSEvent.ModifierFlags = []
            if shortcut.modifiers.contains(.command) { flags.insert(.command) }
            if shortcut.modifiers.contains(.shift) { flags.insert(.shift) }
            if shortcut.modifiers.contains(.option) { flags.insert(.option) }
            if shortcut.modifiers.contains(.control) { flags.insert(.control) }
            item.keyEquivalentModifierMask = flags
        }
        switch command {
            case .services:
                item.submenu = NSMenu(title: "Services")
            case .newWindow, .closeAll:
                item.target = CommandTarget.shared
            default:
                break
        }
        return item
    }
}

/// The two standard commands AppKit has no selector of its own for.
/// AppKit 沒有現成 selector 的兩個標準指令。
@MainActor
final class CommandTarget: NSObject {
    static let shared = CommandTarget()
    var newWindow: (@MainActor () -> Void)?

    @objc func openNewWindow(_ sender: Any?) {
        newWindow?()
    }

    @objc func closeAllWindows(_ sender: Any?) {
        for window in NSApplication.shared.windows where window.isVisible {
            window.performClose(sender)
        }
    }
}
