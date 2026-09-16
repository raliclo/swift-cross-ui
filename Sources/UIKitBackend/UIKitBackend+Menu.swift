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
            // The shortcut is bound and NOT used, and that is a statement, not
            // an oversight.
            //
            // `UIAction` takes a closure and cannot carry a key; `UIKeyCommand`
            // carries a key and takes a SELECTOR, dispatched through the
            // responder chain -- so an object holding the closure is not enough,
            // something in the chain has to implement the selector. That is a
            // real piece of work and it is not this one. Binding the value here
            // rather than writing `_` is what keeps the gap greppable.
            //
            // 這個 shortcut 被綁定了、而且**沒有被使用**;那是一句陳述,不是疏漏。
            //
            // `UIAction` 收的是 closure,帶不了按鍵;`UIKeyCommand` 帶得了按鍵,但收的是 **selector**,
            // 經由 responder chain 派送——因此「一個持有該 closure 的物件」還不夠,必須有 chain 上的
            // 某個東西實作那個 selector。那是一件真正的工作,而它不是這一件。此處綁定該值、而不是寫成
            // `_`,正是為了讓這個缺口 grep 得到。
            case .button(let label, let action, _):
                if let action, environment.isEnabled {
                    .item(UIAction(title: label) { _ in action() })
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
