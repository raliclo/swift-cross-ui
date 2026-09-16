@_spi(Backends) import SwiftCrossUI
import UIKit

extension UIKitBackend {
    private enum RenderedMenuItem {
        case item(UIMenuElement)
        case separator
    }

    @available(tvOS 14, *)
    private static func renderMenuItem(
        _ item: ResolvedMenu.Item,
        environment: EnvironmentValues
    ) -> RenderedMenuItem {
        switch item {
            case .button(let label, let action):
                // A `UIKeyCommand` when there is a shortcut, a `UIAction`
                // otherwise, because on UIKit those are different TYPES rather
                // than one type with an optional key.
                //
                // **`UIKeyCommand` takes a selector, not a closure**, and that
                // is the whole reason this took a detour. The selector is
                // dispatched through the responder chain, so an object holding
                // the closure is not enough -- something already IN the chain
                // has to implement it. `ApplicationDelegate` is a `UIResponder`
                // and is the object that builds this menu, so it is that
                // something; `propertyList` carries the token that says which
                // closure to run, which is what that parameter exists for.
                //
                // 有快捷鍵時用 `UIKeyCommand`,沒有時用 `UIAction`;因為在 UIKit 上,那是兩個**不同的
                // 型別**,而不是同一個型別加一個 optional 的按鍵。
                //
                // **`UIKeyCommand` 收的是 selector,不是 closure**,而那正是這件事繞了一圈的全部原因。
                // 那個 selector 經由 responder chain 派送,因此「一個持有該 closure 的物件」還不夠——
                // 必須有**已經在 chain 上**的東西實作它。`ApplicationDelegate` 是一個 `UIResponder`,
                // 而且它就是建出這個選單的那個物件,所以它就是那個東西;`propertyList` 負責攜帶
                // 「該跑哪一個 closure」的 token,而那正是那個參數存在的用途。
                // Expression form, like every other case here. An early
                // `return` in one arm turns the whole `switch` from an
                // expression into a statement, and the other arms then fail to
                // infer `.item` and `.separator` at all -- an error that names
                // those two and not the arm that caused it.
                // 與此處其餘每一個 case 一樣採運算式形式。任何一支提早 `return`,都會讓整個 `switch`
                // 從運算式變成陳述句,而其餘各支便完全推不出 `.item` 與 `.separator`——那個錯誤指名的
                // 是這兩者,而不是真正肇事的那一支。
                if let action, environment.isEnabled {
                    if let shortcut = environment.keyboardShortcut {
                        .item(
                            UIKeyCommand(
                                title: label,
                                image: nil,
                                action: #selector(ApplicationDelegate.scuiPerformKeyCommand(_:)),
                                input: String(shortcut.key.character).lowercased(),
                                modifierFlags: modifierFlags(for: shortcut),
                                propertyList: MenuShortcutActions.register(action)
                            )
                        )
                    } else {
                        .item(UIAction(title: label) { _ in action() })
                    }
                } else {
                    .item(UIAction(title: label, attributes: .disabled) { _ in })
                }
            case .toggle(let label, let value, let onChange):
                .item(
                    UIAction(
                        title: label,
                        attributes: environment.isEnabled ? [] : .disabled,
                        state: value ? .on : .off
                    ) { action in
                        onChange(!action.state.isOn)
                    }
                )
            case .separator:
                .separator
            case .submenu(let submenu):
                .item(
                    buildMenu(
                        content: submenu.content,
                        label: submenu.label,
                        environment: environment
                    )
                )
            case .modifiedEnvironment(let item, let modification):
                renderMenuItem(
                    item,
                    environment: modification(environment)
                )
        }
    }

    @available(tvOS 14, *)
    static func buildMenu(
        content: ResolvedMenu,
        label: String,
        identifier: UIMenu.Identifier? = nil,
        environment: EnvironmentValues
    ) -> UIMenu {
        var currentSection: [UIMenuElement] = []
        var previousSections: [[UIMenuElement]] = []

        for item in content.items {
            switch renderMenuItem(item, environment: environment) {
                case .item(let uiMenuElement):
                    currentSection.append(uiMenuElement)
                case .separator:
                    // UIKit doesn't have explicit separators per se, but instead deals with
                    // sections (actually quite similar to what you can do in SwiftUI with the
                    // Section view). It'll automatically draw separators between sections.
                    previousSections.append(currentSection)
                    currentSection = []
            }
        }

        let children =
            if previousSections.isEmpty {
                // There are no dividers; just return the current section to keep the menu tree flat.
                currentSection
            } else {
                // Create a list of submenus, each with the displayInline option set so that they
                // display as sections with separators.
                (previousSections + [currentSection]).map {
                    UIMenu(title: "", options: .displayInline, children: $0)
                }
            }

        return UIMenu(title: label, identifier: identifier, children: children)
    }
}

@available(iOS 14, macCatalyst 14, tvOS 17, *)
extension UIKitBackend: BackendFeatures.AttachedMenus {
    public final class Menu {
        var uiMenu: UIMenu?
    }

    public func createPopoverMenu() -> Menu {
        return Menu()
    }

    public func updatePopoverMenu(
        _ menu: Menu,
        content: ResolvedMenu,
        environment: EnvironmentValues
    ) {
        menu.uiMenu = UIKitBackend.buildMenu(
            content: content,
            label: "",
            environment: environment
        )
    }

    public func updateButton(
        _ button: Widget,
        label: String,
        menu: Menu,
        environment: EnvironmentValues
    ) {
        let buttonWidget = button as! ButtonWidget
        buttonWidget.child.isEnabled = environment.isEnabled
        setSimpleButtonTitle(buttonWidget, label, environment: environment)
        buttonWidget.child.menu = menu.uiMenu
        buttonWidget.child.showsMenuAsPrimaryAction = true
        if #available(iOS 16, macCatalyst 16, *) {
            buttonWidget.child.preferredMenuElementOrder =
                switch environment.menuOrder {
                    case .automatic: .automatic
                    case .priority: .priority
                    case .fixed: .fixed
                }
        }
    }
}

// The condition this `#if` was waiting for, met.
//
// It used to read "Once keyboard shortcuts are implemented, it might be possible
// to do them on more platforms than just Mac Catalyst" and admit only Catalyst.
// Shortcuts are implemented now -- `UIKeyCommand` through the responder chain,
// see `UIKitBackend+MenuShortcuts.swift` -- so iOS and iPadOS come in.
//
// **What compiling this out actually did was remove the whole application menu,
// not just its shortcuts.** Without the conformance the framework's
// `backend as? any BackendFeatures.ApplicationMenus` in `_App.swift` fails,
// `setApplicationMenu` is never called, and the app delegate's submenu list
// stays empty. Traced on an iPad on 2026-09-16 by making `buildMenu` write what
// it saw:
//
//     buildMenu system==main: true submenus=0
//
// Nothing failed anywhere along that path. The menu system was built, correctly,
// out of an empty list -- so `.commands` and `CommandMenu` did nothing at all on
// iOS, and P71's shortcut counters read zero while the keys were arriving.
//
// tvOS stays out: it has no menu bar and no keyboard to press.
//
// 這個 `#if` 當初在等的條件,已經成立。
//
// 它原本寫著「等鍵盤快捷鍵實作出來,或許就能推廣到 Mac Catalyst 以外的平台」,並且只放行 Catalyst。
// 快捷鍵現在實作好了——`UIKeyCommand` 經由 responder chain,見 `UIKitBackend+MenuShortcuts.swift`
// ——因此 iOS 與 iPadOS 一併納入。
//
// **把這段編譯掉,實際移除的是整個應用程式選單,而不只是它的快捷鍵。** 少了這個 conformance,
// `_App.swift` 裡的 `backend as? any BackendFeatures.ApplicationMenus` 就失敗,`setApplicationMenu`
// 永遠不會被呼叫,而 app delegate 的 submenu 清單一直是空的。2026-09-16 在一台 iPad 上,讓
// `buildMenu` 寫出它所看到的東西而追出來:
//
//     buildMenu system==main: true submenus=0
//
// 那條路徑上沒有任何東西失敗過。選單系統**正確地**從一份空清單建了出來——於是 `.commands` 與
// `CommandMenu` 在 iOS 上完全沒有作用,而 P71 的快捷鍵計數是零,儘管那些按鍵確實抵達了。
//
// tvOS 不納入:它沒有選單列,也沒有鍵盤可按。
#if targetEnvironment(macCatalyst) || os(iOS)
    extension UIKitBackend: BackendFeatures.ApplicationMenus {
        public func setApplicationMenu(
            _ submenus: [ResolvedMenu.Submenu],
            environment: EnvironmentValues
        ) {
            let appDelegate = UIApplication.shared.delegate as! ApplicationDelegate
            appDelegate.menu = submenus
            appDelegate.environment = environment

            // Storing the submenus is not enough: UIKit has already built the
            // menu by now, and will not build it again unless asked.
            //
            // **`buildMenu` runs once, early, before the app's body has
            // produced anything.** Measured 2026-09-16 on an iPad by having
            // `buildMenu` write what it saw:
            //
            //     buildMenu system==main: true submenus=0
            //
            // So every `CommandMenu` item was absent from the menu system, and
            // with it every `UIKeyCommand` -- P71 reported three zeros for its
            // shortcuts while the keys were arriving correctly. Nothing failed:
            // the menu built successfully, out of nothing.
            //
            // `setNeedsRebuild()` is the documented way to say the menu is now
            // different. It is cheap and idempotent; UIKit coalesces.
            //
            // 把 submenus 存起來是不夠的:UIKit 此刻**早已**建好選單,而且不會再建一次,除非被要求。
            //
            // **`buildMenu` 只在啟動早期跑一次,那時 app 的 body 還沒產生任何東西。** 2026-09-16 在
            // 一台 iPad 上,讓 `buildMenu` 寫出它所看到的東西而量到:
            //
            //     buildMenu system==main: true submenus=0
            //
            // 因此每一個 `CommandMenu` 項目都不在選單系統裡,連帶每一個 `UIKeyCommand` 也不在——
            // P71 的三個快捷鍵計數都是 0,而那些按鍵其實正確地抵達了。沒有任何東西失敗過:那個選單
            // 建置**成功**了,只是從無到無。
            //
            // `setNeedsRebuild()` 是「選單已經不同了」的標準說法。它便宜且冪等,UIKit 自己會合併。
            if #available(iOS 13, tvOS 13, *) {
                UIMenuSystem.main.setNeedsRebuild()
            }
        }
    }
#endif

extension UIMenuElement.State {
    var isOn: Bool {
        get { self == .on }
        set { self = newValue ? .on : .off }
    }
}
