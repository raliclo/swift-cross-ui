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

// Once keyboard shortcuts are implemented, it might be possible to do them on
// more platforms than just Mac Catalyst. For now, we only conform to the
// protocol when built for Catalyst.
#if targetEnvironment(macCatalyst)
    extension UIKitBackend: BackendFeatures.ApplicationMenus {
        public func setApplicationMenu(
            _ submenus: [ResolvedMenu.Submenu],
            environment: EnvironmentValues
        ) {
            let appDelegate = UIApplication.shared.delegate as! ApplicationDelegate
            appDelegate.menu = submenus
            appDelegate.environment = environment
        }
    }
#endif

extension UIMenuElement.State {
    var isOn: Bool {
        get { self == .on }
        set { self = newValue ? .on : .off }
    }
}
