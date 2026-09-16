extension View {
    /// Gives this menu item a key that activates it without opening the menu.
    ///
    /// ```swift
    /// CommandMenu("File") {
    ///     Button("Save") { save() }
    ///         .keyboardShortcut("s")
    /// }
    /// ```
    ///
    /// **Menu items only, and saying so is the point.** SwiftUI also attaches
    /// shortcuts to buttons on screen, which needs a window-level key monitor
    /// on every backend and is a separate piece of work. A modifier that
    /// silently did nothing outside a menu would be worse than one that says
    /// where it works: ``View/onKeyPress(_:)`` is where the general case
    /// belongs when it lands.
    ///
    /// 讓這個選單項目擁有一個「不開啟選單就能啟動它」的按鍵。
    ///
    /// **只作用於選單項目,而把這件事說出來正是重點。** SwiftUI 也會把快捷鍵掛在畫面上的按鈕上,而那
    /// 需要每一個 backend 都有一個視窗層級的按鍵監聽,是另一件獨立的工作。一個「在選單之外靜默地什麼
    /// 都不做」的 modifier,會比一個「說清楚自己在哪裡有效」的更糟;通用的那個情況日後落地時,屬於
    /// ``View/onKeyPress(_:)``。
    public func keyboardShortcut(
        _ key: KeyEquivalent,
        modifiers: EventModifiers = .command
    ) -> some View {
        keyboardShortcut(KeyboardShortcut(key, modifiers: modifiers))
    }

    /// Gives this menu item a key that activates it without opening the menu.
    /// 讓這個選單項目擁有一個「不開啟選單就能啟動它」的按鍵。
    public func keyboardShortcut(_ shortcut: KeyboardShortcut) -> some View {
        KeyboardShortcutModifier(content: self, shortcut: shortcut)
    }
}

/// Attaches a shortcut to whatever menu items its content resolves to.
///
/// **It overrides ``View/_asMenuItems`` and nothing else.** There is no widget,
/// no layout and no backend call here -- the shortcut travels as data until
/// ``Menu`` resolves the item, and the backend reads it there alongside the
/// label and the action. That is what keeps a shortcut from being a second
/// thing a backend has to be told about separately and can therefore forget.
///
/// The body forwards, so the view still renders normally if it is used outside
/// a menu; it simply carries a shortcut nobody reads. See
/// ``View/keyboardShortcut(_:modifiers:)`` for why that case is not an error.
///
/// 把一個快捷鍵掛到「它的內容所解析出的那些選單項目」上。
///
/// **它只覆寫 ``View/_asMenuItems``,別的都不做。** 這裡沒有 widget、沒有版面計算、也沒有任何 backend
/// 呼叫——那個快捷鍵以**資料**的形式一路travel,直到 ``Menu`` 解析該項目,而 backend 在那裡與標籤、
/// 動作一起讀到它。這正是讓「快捷鍵」不會變成「一件 backend 必須被另外告知、因而可能忘記的事」的原因。
///
/// body 是直通的,因此這個 view 在選單之外仍然正常繪製;它只是帶著一個沒有人會讀的快捷鍵。那個情況
/// 為何不是錯誤,見 ``View/keyboardShortcut(_:modifiers:)``。
struct KeyboardShortcutModifier<Content: View>: View {
    var content: Content
    var shortcut: KeyboardShortcut

    var body: TupleView1<Content> { content }

    var _asMenuItems: [MenuItem] {
        content._asMenuItems.map { item in
            switch item {
                case .button(let button, _):
                    // The outermost modifier wins, which is why the existing
                    // shortcut is discarded rather than kept. `.keyboardShortcut("s")
                    // .keyboardShortcut("o")` is a contradiction and one of the two
                    // has to lose; the one written last is the one the reader sees
                    // last.
                    // 最外層的 modifier 獲勝,這正是既有的快捷鍵被**丟棄**而非保留的原因。
                    // `.keyboardShortcut("s").keyboardShortcut("o")` 是一個矛盾,兩者必有一個要輸;
                    // 而寫在最後的那一個,正是讀者最後看到的那一個。
                    .button(button, shortcut: shortcut)
                default:
                    // Unchanged rather than dropped. A separator or a submenu
                    // carrying a shortcut is meaningless, and silently removing
                    // the item would turn a pointless modifier into a missing
                    // menu entry.
                    // 原樣保留而非丟棄。一個帶著快捷鍵的分隔線或子選單毫無意義;而靜默地移除該項目,
                    // 會把「一個無意義的 modifier」變成「一個消失的選單項目」。
                    item
            }
        }
    }
}
