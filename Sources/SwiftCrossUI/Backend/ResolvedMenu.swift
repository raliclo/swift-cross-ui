/// A generic representation of an application menu, pop-up menu, or context menu.
/// This is what eventually gets passed through to the backend.
///
/// Referred to as 'resolved' because SwiftCrossUI provides some relatively
/// abstract ways to specify menu items, and this is the format that it resolves
/// all menus to eventually.
public struct ResolvedMenu {
    /// The menu's items.
    public var items: [Item]

    /// Creates a ``ResolvedMenu`` instance.
    ///
    /// - Parameter items: The menu's items.
    public init(items: [ResolvedMenu.Item]) {
        self.items = items
    }

    /// A menu item.
    public enum Item {
        /// A button.
        ///
        /// - Parameters:
        ///   - label: The button's label.
        ///   - action: The action to perform when the button is activated. `nil`
        ///     means the button is disabled.
        ///   - shortcut: The key that activates it without opening the menu, or
        ///     `nil` for none.
        ///
        /// **The shortcut is an associated value rather than a separate case,
        /// and that is what forces every backend to answer for it.** A
        /// `.shortcutButton` case beside this one would let a backend match
        /// `.button` and quietly never see the other; a third value makes the
        /// existing `switch` stop compiling until someone decides what to do
        /// with it. That is the loud option, and a menu item whose shortcut
        /// silently does nothing is exactly the kind of thing nobody reports.
        ///
        ///   - shortcut: 不開啟選單就能啟動它的那個按鍵;沒有則為 `nil`。
        ///
        /// **shortcut 是一個 associated value、而不是另一個 case,而那正是「強迫每一個 backend 對它
        /// 作出交代」的手段。** 在它旁邊放一個 `.shortcutButton` case,會讓某個 backend 匹配
        /// `.button` 之後,靜靜地永遠看不到另一個;而多一個值會讓既有的 `switch` **編不過**,直到有人
        /// 決定要拿它怎麼辦。那是比較大聲的選項;而一個「快捷鍵靜默無效」的選單項目,正是那種沒有人
        /// 會回報的東西。
        case button(
            _ label: String,
            _ action: (@MainActor () -> Void)?,
            _ shortcut: KeyboardShortcut?
        )
        /// A toggle that manages boolean state.
        ///
        /// Usually appears as a checkbox.
        ///
        /// - Parameters:
        ///   - label: The toggle's label.
        ///   - value: The toggle's current state.
        ///   - onChange: Called whenever the user changes the toggle's state.
        case toggle(_ label: String, _ value: Bool, onChange: @MainActor (Bool) -> Void)
        /// A section separator.
        case separator
        /// A named submenu.
        case submenu(Submenu)
        /// A wrapper for a menu item that modifies its environment.
        ///
        /// - Parameters:
        ///   - item: The item to modify the environment of.
        ///   - modification: A function that modifies a given
        ///     `EnvironmentValues` instance.
        indirect case modifiedEnvironment(
            _ item: Item,
            _ modification: (EnvironmentValues) -> EnvironmentValues
        )
    }

    /// A named submenu.
    public struct Submenu {
        /// The label of the submenu's entry in its parent menu.
        public var label: String
        /// The menu displayed when the submenu gets activated.
        public var content: ResolvedMenu

        /// Creates a ``Submenu`` instance.
        ///
        /// - Parameters:
        ///   - label: The label of the submenu's entry in its parent menu.
        ///   - content: The menu displayed when the submenu gets activated.
        public init(label: String, content: ResolvedMenu) {
            self.label = label
            self.content = content
        }
    }
}
