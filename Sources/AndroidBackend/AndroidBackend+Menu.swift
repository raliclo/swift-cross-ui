import SwiftCrossUI
import AndroidKit
import SwiftJava

// swiftlint:disable force_try
extension AndroidKit.PopupMenu {
    // Workaround for the fact that you can't put @JavaMethod inits in extensions
    static func construct(
        _ context: AndroidKit.Context!,
        _ anchor: AndroidKit.View!,
        environment: JNIEnvironment!
    ) -> AndroidKit.PopupMenu {
        try! Self.dynamicJavaNewObject(in: environment, arguments: context, anchor)
    }

    @JavaMethod
    func getMenu() -> AndroidKit.Menu!
}

@JavaClass(
    "dev.swiftcrossui.androidbackend.CustomMenuItemClickListener",
    implements: AndroidKit.MenuItem.OnMenuItemClickListener.self
)
class CustomMenuItemClickListener: JavaObject {
    @JavaMethod
    convenience init(
        _ action: SwiftAction!,
        environment: JNIEnvironment? = nil
    )
}

// Note: This implementation relies on the fact that SwiftCrossUI::Menu.commit always calls
// updatePopoverMenu before calling updateButton. If that is changed,
// AndroidBackend.Menu.realizeMenu needs to be moved to be called in updatePopoverMenu instead of
// updateButton. I'm not including it in both to avoid duplicating work.
extension AndroidBackend: BackendFeatures.AttachedMenus {
    @MainActor
    public final class Menu {
        private var popupMenu: AndroidKit.PopupMenu? = nil
        private var anchor: AndroidKit.View? = nil

        var content = ResolvedMenu(items: [])

        func setView(_ view: AndroidKit.View, environment: EnvironmentValues) {
            let popupMenu =
                if
                    view.javaThisOptional == self.anchor?.javaThisOptional,
                    let popupMenu = self.popupMenu
                {
                    popupMenu
                } else {
                    AndroidKit.PopupMenu.construct(activity, view, environment: env)
                }

            self.popupMenu = popupMenu
            self.anchor = view

            Self.realizeMenu(
                menu: popupMenu.getMenu(),
                items: content.items,
                environment: environment
            )
        }

        private static func realizeMenu(
            menu: AndroidKit.Menu,
            items: [ResolvedMenu.Item],
            environment: EnvironmentValues
        ) {
            menu.clear()

            var groupId: Int32 = 1

            for (index, item) in items.enumerated() {
                addMenuItem(
                    item,
                    to: menu,
                    index: index,
                    environment: environment,
                    groupId: &groupId
                )
            }
        }

        private static func addMenuItem(
            _ item: ResolvedMenu.Item,
            to menu: AndroidKit.Menu,
            index: Int,
            environment: EnvironmentValues,
            groupId: inout Int32
        ) {
            switch item {
                case .button(let label, let action):
                    // From the ENVIRONMENT, the same place GTK, WinUI and
                    // AppKit read it. See `EnvironmentValues.keyboardShortcut`.
                    // 從 **environment** 來,與 GTK、WinUI、AppKit 讀取的是同一個地方。
                    // 見 `EnvironmentValues.keyboardShortcut`。
                    let shortcut = environment.keyboardShortcut
                    let menuItem = menu.add(
                        groupId,
                        0,
                        Int32(index),
                        charSequence(from: label)
                    )
                    .setEnabled(environment.isEnabled)!
                    if let shortcut,
                        let scalar = String(shortcut.key.character).lowercased().unicodeScalars
                            .first
                    {
                        // `setAlphabeticShortcut(char, modifiers)`, with the
                        // modifier mask separate from the key.
                        //
                        // **Android's shortcuts reach a hardware keyboard, not
                        // the touch screen**, and that is the whole of what this
                        // does: the item shows its shortcut in the overflow menu
                        // and a keyboard fires it. A phone with no keyboard is
                        // not a platform that fails this -- it is a platform
                        // with no key to press, the same way `onHover` has no
                        // pointer there.
                        //
                        // Non-ASCII keys are skipped rather than mangled: the
                        // API takes a single `char`, and an arrow key or an
                        // emoji has no alphabetic form to take. `first` being
                        // nil is that case, and it leaves the item working
                        // without a shortcut rather than with a wrong one.
                        //
                        // `setAlphabeticShortcut(char, modifiers)`,modifier mask 與按鍵分開。
                        //
                        // **Android 的快捷鍵抵達的是實體鍵盤,不是觸控螢幕**,而這就是它的全部:該項目
                        // 會在溢位選單裡顯示它的快捷鍵,而鍵盤按下去會觸發它。一支沒有鍵盤的手機不是
                        // 「在這一項上失敗」的平台——它是一個「沒有鍵可按」的平台,與 `onHover` 在那裡
                        // 沒有指標是同一回事。
                        //
                        // 非 ASCII 的按鍵是被**跳過**、而不是被硬轉:那個 API 收的是單一個 `char`,
                        // 而一個方向鍵或 emoji 沒有可取的字母形式。`first` 為 nil 就是那個情況,它讓該
                        // 項目在「沒有快捷鍵」的狀態下正常運作,而不是帶著一個錯的快捷鍵。
                        _ = menuItem.setAlphabeticShortcut(
                            UInt16(scalar.value),
                            AndroidBackend.keyModifiers(for: shortcut)
                        )
                    }

                    if environment.isEnabled {
                        let onClick = CustomMenuItemClickListener(
                            SwiftAction(environment: env) { action?() },
                            environment: env
                        )

                        _ = menuItem.setOnMenuItemClickListener(
                            onClick.as(MenuItem.OnMenuItemClickListener.self)
                        )
                    }
                case .toggle(let label, let value, let onChange):
                    let menuItem = menu.add(
                        groupId,
                        0,
                        Int32(index),
                        charSequence(from: label)
                    )
                    .setEnabled(environment.isEnabled)
                    .setCheckable(true)
                    .setChecked(value)!

                    if environment.isEnabled {
                        let onClick = CustomMenuItemClickListener(
                            SwiftAction(environment: env) { onChange(!value) },
                            environment: env
                        )

                        _ = menuItem.setOnMenuItemClickListener(
                            onClick.as(MenuItem.OnMenuItemClickListener.self)
                        )
                    }
                case .separator:
                    menu.setGroupDividerEnabled(true)
                    groupId += 1
                case .submenu(let resolvedSubmenu):
                    let submenu = menu.addSubMenu(
                        groupId,
                        0,
                        Int32(index),
                        charSequence(from: resolvedSubmenu.label)
                    )!

                    realizeMenu(
                        menu: submenu.as(AndroidKit.Menu.self),
                        items: resolvedSubmenu.content.items,
                        environment: environment
                    )
                case .modifiedEnvironment(let innerItem, let modification):
                    addMenuItem(
                        innerItem,
                        to: menu,
                        index: index,
                        environment: modification(environment),
                        groupId: &groupId
                    )
            }
        }

        func show() {
            popupMenu?.show()
        }
    }

    public func createPopoverMenu() -> AndroidBackend.Menu {
        AndroidBackend.Menu()
    }

    public func updatePopoverMenu(
        _ menu: AndroidBackend.Menu,
        content: ResolvedMenu,
        environment: EnvironmentValues
    ) {
        menu.content = content
    }

    public func updateButton(
        _ button: Widget,
        label: String,
        menu: Menu,
        environment: EnvironmentValues
    ) {
        menu.setView(
            button,
            environment: environment
        )

        self.updateSimpleButton(
            button,
            label: label,
            environment: environment,
            action: menu.show
        )
    }
}

extension AndroidBackend {
    /// Maps SwiftCrossUI's modifiers onto `KeyEvent`'s meta-state mask.
    ///
    /// `.command` becomes CTRL here, which is the convention
    /// ``EventModifiers/command`` records: SwiftUI's `.command` is Command on
    /// Apple platforms and Ctrl on the other three. Android also has META -- the
    /// Command key on an attached Apple keyboard -- and mapping `.command` to
    /// that instead would make every existing shortcut stop working on the
    /// hardware most Android users actually have.
    ///
    /// The constants are spelled out because they are not in the generated
    /// bindings, and a bare `0x1000` at the call site would say nothing about
    /// which key it meant.
    ///
    /// 把 SwiftCrossUI 的 modifier 映射到 `KeyEvent` 的 meta-state mask。
    ///
    /// `.command` 在此成為 CTRL,而那正是 ``EventModifiers/command`` 所記載的慣例:SwiftUI 的
    /// `.command` 在 Apple 平台上是 Command,在其餘三個平台上是 Ctrl。Android 同樣有 META——接上
    /// Apple 鍵盤時的 Command 鍵——而把 `.command` 改映射到它,會讓既有的每一個快捷鍵在「多數 Android
    /// 使用者手上真正擁有的硬體」上失效。
    ///
    /// 這些常數明寫出來,因為它們不在產生出來的綁定裡;而呼叫處光禿禿的 `0x1000`,說不出它指的是哪一個鍵。
    static func keyModifiers(for shortcut: KeyboardShortcut) -> Int32 {
        /// `KeyEvent.META_CTRL_ON`
        let ctrl: Int32 = 0x1000
        /// `KeyEvent.META_SHIFT_ON`
        let shift: Int32 = 0x1
        /// `KeyEvent.META_ALT_ON`
        let alt: Int32 = 0x2
        var mask: Int32 = 0
        if shortcut.modifiers.contains(.command) { mask |= ctrl }
        if shortcut.modifiers.contains(.control) { mask |= ctrl }
        if shortcut.modifiers.contains(.shift) { mask |= shift }
        if shortcut.modifiers.contains(.option) { mask |= alt }
        return mask
    }
}
