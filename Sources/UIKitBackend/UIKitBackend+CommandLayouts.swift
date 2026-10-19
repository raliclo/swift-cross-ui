@_spi(Backends) import SwiftCrossUI
import UIKit

#if targetEnvironment(macCatalyst) || os(iOS)
    /// ``CommandGroup`` on UIKit.
    ///
    /// **Where there is a menu bar -- iPad, Mac Catalyst -- the system's menus are
    /// kept and the app's groups go into them**, before, after or in place of the
    /// system's own group. Each placement is one of UIKit's menu identifiers, so
    /// what `replacing:` takes out is exactly what the system put there.
    ///
    /// **A phone has no menu bar.** By default nothing is shown and the items'
    /// shortcuts still work, as before. With ``Scene/enableMenu(_:)`` a menu
    /// button appears at the top left, and opens the standard menus as submenus;
    /// that button is this framework's own design -- SwiftUI shows nothing on an
    /// iPhone -- and was agreed with the user on 2026-10-14.
    ///
    /// NOT compared with SwiftUI on iPad: a SwiftUI reference app runs there but
    /// its menu could not be read (queue.md, 2026-10-13). `windowList` and
    /// `singleWindowList` do not exist on iOS in SwiftUI; here they go to the end
    /// of the Window menu.
    ///
    /// UIKit 上的 ``CommandGroup``。有選單列的地方(iPad、Mac Catalyst)保留系統的選單，app 的群組放進去——在系統自己的
    /// 群組之前、之後或取代它;每個位置對應 UIKit 的一個選單識別碼，所以 `replacing:` 拿掉的正是系統放在那裡的東西。
    /// 手機沒有選單列:預設什麼都不顯示，項目的快捷鍵照舊有效;``Scene/enableMenu(_:)`` 打開後左上角出現選單按鈕，點開是各個
    /// 標準選單的子選單。那個按鈕是本框架自己的設計(SwiftUI 在 iPhone 上什麼都不顯示),2026-10-14 與使用者確認過。
    /// iPad 上**尚未**與 SwiftUI 比對:參考 app 跑得起來，但讀不到它的選單。SwiftUI 在 iOS 上沒有 `windowList` 與
    /// `singleWindowList`;這裡把它們放在 Window 選單的尾端。
    extension UIKitBackend: BackendFeatures.CommandLayouts {
        public func setApplicationCommands(
            _ layout: CommandLayout,
            environment: EnvironmentValues
        ) {
            let appDelegate = UIApplication.shared.delegate as! ApplicationDelegate
            appDelegate.commandLayout = layout
            // The app's own items, for the shortcuts a device without a menu bar still honours.
            // app 自己的項目，供沒有選單列的裝置仍然要認的快捷鍵使用。
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
            for scene in UIApplication.shared.connectedScenes {
                for window in (scene as? UIWindowScene)?.windows ?? [] {
                    (window.rootViewController as? RootViewController)?.updateMenuButton()
                }
            }
        }
    }

    extension UIKitBackend: BackendFeatures.StandardCommands {
        /// What the phone's menu button offers of the system's commands: the
        /// editing ones, sent down the responder chain. The window and app
        /// commands have nothing to act on there.
        /// 手機選單按鈕提供的系統指令:編輯類，沿 responder chain 送出。視窗與 app 類的指令在那裡沒有作用對象。
        public func hasStandardCommand(_ command: StandardCommand) -> Bool {
            Self.editSelector(command) != nil
        }

        public func performStandardCommand(_ command: StandardCommand) {
            guard let selector = Self.editSelector(command) else { return }
            UIApplication.shared.sendAction(selector, to: nil, from: nil, for: nil)
        }

        static func editSelector(_ command: StandardCommand) -> Selector? {
            switch command {
                case .undo: Selector(("undo:"))
                case .redo: Selector(("redo:"))
                case .cut: #selector(UIResponderStandardEditActions.cut(_:))
                case .copy: #selector(UIResponderStandardEditActions.copy(_:))
                case .paste: #selector(UIResponderStandardEditActions.paste(_:))
                case .delete: #selector(UIResponderStandardEditActions.delete(_:))
                case .selectAll: #selector(UIResponderStandardEditActions.selectAll(_:))
                default: nil
            }
        }
    }

    extension CommandGroupPlacement {
        /// The system's group for this placement, and the top-level menu it is in.
        /// 這個位置對應的系統群組，以及它所在的頂層選單。
        var uiKitIdentifiers: (group: UIMenu.Identifier?, parent: UIMenu.Identifier) {
            switch name {
                case "appInfo": (.about, .application)
                case "appSettings": (.preferences, .application)
                case "systemServices": (.services, .application)
                case "appVisibility": (.hide, .application)
                case "appTermination": (.quit, .application)
                case "newItem": (UIMenu.Identifier("com.apple.menu.new-item"), .file)
                case "saveItem": (.close, .file)
                case "importExport": (nil, .file)
                case "printItem": (.print, .file)
                case "undoRedo": (.undoRedo, .edit)
                case "pasteboard": (.standardEdit, .edit)
                case "textEditing": (nil, .edit)
                case "textFormatting": (.textStyle, .format)
                case "toolbar": (.toolbar, .view)
                case "sidebar": (.sidebar, .view)
                case "windowSize": (.minimizeAndZoom, .window)
                case "windowArrangement": (.bringAllToFront, .window)
                case "help": (nil, .help)
                default: (nil, .window)
            }
        }
    }

    extension ApplicationDelegate {
        func buildCommandMenus(with builder: any UIMenuBuilder) {
            guard let layout = commandLayout, let environment else { return }
            var lastCustom: UIMenu.Identifier = .view
            var filled: Set<String> = []
            for menu in layout.menus {
                guard menu.standard != nil else {
                    // The app's own menu, after View and after the ones before it.
                    // app 自己的選單，放在 View 之後、並排在先前的自有選單後面。
                    let identifier = UIMenu.Identifier(
                        "\(Bundle.main.bundleIdentifier ?? "app").command-menu.\(menu.title).\(lastCustom.rawValue.count)"
                    )
                    let items = menu.sections.flatMap(\.entries).compactMap(Self.item)
                    let built = UIKitBackend.buildMenu(
                        content: ResolvedMenu(items: items),
                        label: menu.title,
                        identifier: identifier,
                        environment: environment
                    )
                    if builder.menu(for: lastCustom) != nil {
                        builder.insertSibling(built, afterMenu: lastCustom)
                    } else {
                        builder.insertChild(built, atEndOfMenu: .root)
                    }
                    lastCustom = identifier
                    continue
                }
                for section in menu.sections {
                    guard let placement = section.placement else { continue }
                    filled.insert(placement.name)
                    func elements(_ entries: ArraySlice<CommandLayout.Entry>) -> [UIMenuElement] {
                        let items = entries.compactMap(Self.item)
                        guard !items.isEmpty else { return [] }
                        return UIKitBackend.buildMenu(
                            content: ResolvedMenu(items: items),
                            label: "",
                            environment: environment
                        ).children
                    }
                    // The app's entries on either side of the system's; with the group
                    // replaced every entry is the app's.
                    // 系統項目兩側的 app 項目;群組被取代時，每個項目都是 app 的。
                    let before = elements(section.entries[..<section.leading])
                    let after = elements(
                        section.entries[section.leading...].filter { Self.item($0) != nil }[...]
                    )
                    func merged(_ existing: [UIMenuElement]) -> [UIMenuElement] {
                        before + (section.isReplaced ? [] : existing) + after
                    }
                    let (group, parent) = placement.uiKitIdentifiers
                    switch placement.name {
                        case "textFormatting":
                            // SwiftUI shows no Format menu on iPad and drops whatever the app
                            // put in this group (ipad-after.txt has no AFTER-textFormatting),
                            // so the entries go nowhere here too (user, 2026-10-20: follow
                            // SwiftUI). The menu itself is removed below.
                            // SwiftUI 在 iPad 上不顯示 Format 選單，app 放在這個群組的東西也一併丟掉(ipad-after.txt 沒有
                            // AFTER-textFormatting),所以這裡也不放(使用者,2026-10-20:照 SwiftUI)。選單本身在下方移除。
                            continue
                        case "importExport":
                            let inline = UIMenu(
                                title: "",
                                identifier: UIMenu.Identifier("scui.synthesized.importExport"),
                                options: .displayInline,
                                children: before + after
                            )
                            if builder.menu(for: .close) != nil {
                                builder.insertSibling(inline, afterMenu: .close)
                            } else {
                                builder.insertChild(inline, atEndOfMenu: .file)
                            }
                        case "textEditing":
                            // The system's text menus are this group's own items.
                            // 系統的文字選單就是這個群組自己的項目。
                            var existing: [UIMenuElement] = []
                            for identifier in Self.textEditingMenus {
                                if let menu = builder.menu(for: identifier) {
                                    existing.append(menu)
                                    builder.remove(menu: identifier)
                                }
                            }
                            let inline = UIMenu(
                                title: "",
                                identifier: UIMenu.Identifier("scui.synthesized.textEditing"),
                                options: .displayInline,
                                children: merged(existing)
                            )
                            builder.insertChild(inline, atEndOfMenu: .edit)
                        default:
                            let target = group ?? parent
                            if builder.menu(for: target) != nil {
                                if group == nil {
                                    // No group of the system's: at the end of the menu.
                                    // 沒有對應的系統群組:放在選單尾端。
                                    builder.replaceChildren(ofMenu: target) {
                                        placement.name == "help" ? merged($0) : $0 + before + after
                                    }
                                } else {
                                    builder.replaceChildren(ofMenu: target, from: merged)
                                }
                            }
                    }
                }
            }
            // What SwiftUI leaves out of an iPad's menu bar unless the app fills the
            // group (testapp/reference/swiftui-commands/ipad/): Print, the toolbar and
            // sidebar groups, Find and the text menus. The Format menu it leaves out
            // always, even when the app filled textFormatting (above).
            // SwiftUI 在 app 沒有填該群組時，從 iPad 選單列拿掉的東西:Print、toolbar 與 sidebar 群組、Find 與各個文字選單。
            // Format 選單它一律拿掉，即使 app 填了 textFormatting 也一樣(見上)。
            // Only what is there: taking out a menu the builder does not hold ended the app when
            // the menu bar was first built (iPad simulator, 2026-10-14).
            // 只拿掉存在的:移除 builder 沒有的選單，會讓 app 在第一次建立選單列時結束(iPad 模擬器，2026-10-14)。
            func remove(_ identifier: UIMenu.Identifier) {
                if builder.menu(for: identifier) != nil { builder.remove(menu: identifier) }
            }
            remove(.format)
            if !filled.contains("printItem") { remove(.print) }
            if !filled.contains("toolbar") { remove(.toolbar) }
            if !filled.contains("sidebar") { remove(.sidebar) }
            if !filled.contains("textEditing") {
                remove(.find)
                Self.textEditingMenus.forEach(remove)
            }
            if UIKitBackend.logsMenus {
                var lines = ["-menu: main menu built"]
                func describe(_ element: UIMenuElement, _ depth: Int) {
                    let pad = String(repeating: "  ", count: depth)
                    if let menu = element as? UIMenu {
                        let kind = menu.options.contains(.displayInline) ? "(inline)" : "MENU"
                        lines
                            .append(
                                "-menu: \(pad)\(kind) '\(menu.title)' \(menu.identifier.rawValue)"
                            )
                        menu.children.forEach { describe($0, depth + 1) }
                    } else {
                        lines.append("-menu: \(pad)\(element.title)")
                    }
                }
                if let root = builder.menu(for: .root) { describe(root, 0) }
                print(lines.joined(separator: "\n"))
                fflush(stdout)
            }
        }

        static let textEditingMenus: [UIMenu.Identifier] = [
            .spelling,
            .substitutions,
            .transformations,
            .speech,
        ]

        private static func item(_ entry: CommandLayout.Entry) -> ResolvedMenu.Item? {
            if case .item(let item) = entry { return item }
            return nil
        }
    }

    extension UIKitBackend {
        static let logsMenus = CommandLine.arguments.contains("--debug")
    }

    extension RootViewController {
        /// Shows, updates or removes the phone's menu button.
        /// 顯示、更新或移除手機上的選單按鈕。
        func updateMenuButton() {
            let appDelegate = UIApplication.shared.delegate as? ApplicationDelegate
            guard UIDevice.current.userInterfaceIdiom == .phone,
                  let layout = appDelegate?.commandLayout, layout.isMenuEnabled,
                  let environment = appDelegate?.environment
            else {
                menuButton?.removeFromSuperview()
                menuButton = nil
                refreshAvoidedRect()
                return
            }
            let button: UIButton
            if let existing = menuButton {
                button = existing
            } else {
                button = UIButton(type: .system)
                button.setImage(UIImage(systemName: "line.3.horizontal"), for: .normal)
                button.accessibilityLabel = "Menu"
                button.tintColor = .label
                button.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.9)
                button.layer.borderColor = UIColor.separator.cgColor
                button.layer.borderWidth = 1
                button.layer.cornerRadius = 6
                button.showsMenuAsPrimaryAction = true
                view.addSubview(button)
                menuButton = button
            }
            let backend = self.backend
            var shown = layout
            shown.menus = layout.menus.compactMap { menu in
                var menu = menu
                menu.sections = menu.sections.compactMap { section in
                    var section = section
                    section.entries = section.entries.filter { entry in
                        if case .standard(let command) = entry {
                            return backend.hasStandardCommand(command)
                        }
                        return true
                    }
                    return section.entries.isEmpty ? nil : section
                }
                return menu.sections.isEmpty ? nil : menu
            }
            let submenus = shown.submenus { backend.performStandardCommand($0) }
            button.menu = UIMenu(
                title: "",
                children: submenus.map {
                    UIKitBackend.buildMenu(
                        content: $0.content,
                        label: $0.label,
                        environment: environment
                    )
                }
            )
            layoutMenuButton()
        }

        /// Right of the mode button when there is one, else in its place.
        /// 有模式按鈕時在它右邊，否則在它的位置。
        func layoutMenuButton() {
            guard let button = menuButton else { return }
            let safe = view.safeAreaLayoutGuide.layoutFrame
            let x = modeButtonFrame.map { $0.maxX + 8 } ?? safe.minX + 8
            button.frame = CGRect(x: x, y: safe.minY + 8, width: 44, height: 28)
            refreshAvoidedRect()
        }
    }
#endif
