import SwiftCrossUI
import UIKit

extension UIKitBackend: BackendFeatures.ContextMenus {
    public func createContextMenuTarget(wrapping child: Widget) -> Widget {
        ContextMenuWidget(child: child)
    }

    public func updateContextMenuTarget(
        _ target: Widget,
        menu: ResolvedMenu,
        environment: EnvironmentValues
    ) {
        let target = target as! ContextMenuWidget
        target.menu = menu
    }
}

/// A menu raised by a long press, or by a secondary click with a pointer.
///
/// **`UIContextMenuInteraction`, which is a different shape from AppKit's
/// `NSView.menu` in one way worth knowing.** AppKit hands the menu over
/// synchronously and pops it itself. UIKit asks for a CONFIGURATION first, then
/// asks that configuration for a `UIMenu` when it is ready to present -- so the
/// items are built at presentation time rather than when the modifier commits.
/// A caller sees no difference; an implementer does, because the closure has to
/// capture something that is still valid later. It captures `self` and reads
/// `menu`, so the newest committed menu is the one shown.
///
/// **A `UIMenu` is built fresh each time, not cached.** `ResolvedMenu.Item`
/// carries the action closures the framework resolved on the last commit, and a
/// cached `UIMenu` would hold the ones from whenever it was built. That is the
/// same defect class as a stale cursor rect, and here it would run yesterday's
/// action.
///
/// 由長按、或由帶指標時的次要點擊所叫出的選單。
///
/// **`UIContextMenuInteraction`,它與 AppKit 的 `NSView.menu` 在一件值得知道的事情上形狀不同。**
/// AppKit 是同步把選單交出去、並自己彈出它。UIKit 則是**先**要一份 configuration,等到它準備好呈現時,
/// 才向那份 configuration 要一個 `UIMenu`——因此那些項目是在**呈現當下**才建立的,不是在 modifier
/// commit 時。呼叫端看不出差別;實作者看得出來,因為那個 closure 必須捕捉一個「稍後仍然有效」的東西。
/// 它捕捉 `self` 並讀取 `menu`,因此顯示的會是最新一次 commit 的那個選單。
///
/// **每一次都重新建一個 `UIMenu`,不快取。** `ResolvedMenu.Item` 帶著框架在上一次 commit 所解析出的
/// action closure;而一個被快取的 `UIMenu` 會抓著「它被建立當時」的那些。那與「過期的 cursor rect」
/// 是同一類缺陷,而在這裡它會執行昨天的動作。
final class ContextMenuWidget: ContainerWidget {
    var menu = ResolvedMenu(items: [])

    override init(child: some WidgetProtocol) {
        super.init(child: child)
        // On `view` for the reason `CursorWidget` gives: a `ContainerWidget` is
        // a view controller.
        // 加在 `view` 上,理由與 `CursorWidget` 相同:`ContainerWidget` 是一個 view controller。
        view.addInteraction(UIContextMenuInteraction(delegate: self))
    }
}

extension ContextMenuWidget: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            return Self.uiMenu(for: self.menu)
        }
    }

    private static func uiMenu(for menu: ResolvedMenu) -> UIMenu {
        UIMenu(title: "", children: menu.items.compactMap(element(for:)))
    }

    private static func element(for item: ResolvedMenu.Item) -> UIMenuElement? {
        switch item {
            case .button(let label, let action):
                let element = UIAction(title: label) { _ in action?() }
                // A button with no action is a label in this representation, and
                // `ResolvedMenu` allows it -- `Menu.resolve` turns a `Text` into
                // exactly that. Disabled rather than dropped, so the menu still
                // reads the way the caller wrote it.
                // 在這個表示法裡,一個沒有 action 的 button 就是一個標籤,而 `ResolvedMenu` 允許它
                // ——`Menu.resolve` 正是把一個 `Text` 轉成那個。此處把它設為停用而不是丟掉,
                // 好讓那個選單讀起來仍與呼叫端所寫的一致。
                if action == nil { element.attributes = [.disabled] }
                return element
            case .toggle(let label, let value, let onChange):
                let element = UIAction(title: label) { _ in onChange(!value) }
                element.state = value ? .on : .off
                return element
            case .separator:
                // UIKit has no separator element. A menu's sections are made by
                // nesting an inline UIMenu, and a separator with nothing between
                // it and the next one would produce an empty section -- so it is
                // dropped, and this is the one place the two backends differ in
                // what the user sees.
                // UIKit 沒有分隔線元素。選單的分段是靠巢狀一個 inline `UIMenu` 做出來的,而一個
                // 「與下一個之間沒有任何東西」的分隔線會產生一個空的分段——因此它被丟棄;
                // 而這是兩個 backend 在「使用者看到什麼」上唯一不同的地方。
                return nil
            case .submenu(let submenu):
                return UIMenu(
                    title: submenu.label,
                    children: submenu.content.items.compactMap(element(for:))
                )
            case .modifiedEnvironment(let item, _):
                // The modification is dropped, and it has to be: it changes an
                // `EnvironmentValues`, and a `UIMenuElement` has no environment
                // to change. AppKit's renderer applies it because it is building
                // `NSMenuItem`s whose appearance it controls. Reported here so
                // that a menu which looked different on the two backends has a
                // written reason rather than a mystery.
                // 那個修改被丟棄了,而且必須被丟棄:它改的是一個 `EnvironmentValues`,而一個
                // `UIMenuElement` 沒有 environment 可以被改。AppKit 的 renderer 會套用它,是因為它在
                // 建立「外觀由它掌控」的 `NSMenuItem`。此處寫明,好讓「同一個選單在兩個 backend 上
                // 長得不同」有一個寫下來的理由,而不是一個謎。
                return element(for: item)
        }
    }
}
