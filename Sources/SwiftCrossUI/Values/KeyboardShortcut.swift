/// A key, in the sense SwiftUI means it: the character you press, not a
/// platform key code.
///
/// A character rather than an enum of every key, because that is what makes
/// `.keyboardShortcut("s")` read the way it does in SwiftUI, and because a key
/// code is a property of a keyboard layout rather than of the shortcut. The
/// named statics below are the keys that have no printable character.
///
/// `ExpressibleByExtendedGraphemeClusterLiteral`, not `ByUnicodeScalarLiteral`,
/// because `Character` is a grapheme cluster: "é" typed as e-then-combining-
/// acute is one Character and two scalars. Choosing the narrower literal would
/// compile and then reject exactly the inputs a non-English keyboard produces.
///
/// 一個「鍵」,採 SwiftUI 的意義:你所按下的**字元**,而不是平台的 key code。
///
/// 用字元而非「窮舉每個鍵的 enum」,是因為那才讓 `.keyboardShortcut("s")` 讀起來與 SwiftUI 一致;
/// 也因為 **key code 是鍵盤配置的性質,不是快捷鍵的性質**。下方的具名靜態值,則是那些沒有可列印
/// 字元的鍵。
///
/// 採用 `ExpressibleByExtendedGraphemeClusterLiteral` 而非 `ByUnicodeScalarLiteral`,因為
/// `Character` 是一個字素叢集:以 e 加上結合尖音符打出的「é」是**一個** Character、**兩個** scalar。
/// 選較窄的那種字面量會編得過,然後恰好拒絕掉非英語鍵盤所產生的輸入。
public struct KeyEquivalent: Hashable, Sendable {
    /// The character this shortcut is written with.
    /// 這個快捷鍵所使用的字元。
    public var character: Character

    public init(_ character: Character) {
        self.character = character
    }

    /// Keys with no printable character. The scalars are the ones SwiftUI uses,
    /// so a shortcut written against SwiftUI's names means the same thing here.
    ///
    /// `delete` is U+007F (forward delete / DEL), matching SwiftUI, NOT U+0008
    /// backspace. They are different keys on every platform this ships on, and
    /// the two are easy to conflate because macOS labels backspace "delete".
    ///
    /// 沒有可列印字元的鍵。此處的 scalar 與 SwiftUI 所用者相同,因此照 SwiftUI 的名稱所寫的快捷鍵,
    /// 在這裡意義一致。
    ///
    /// `delete` 是 U+007F(向前刪除 / DEL),與 SwiftUI 一致,**不是** U+0008 的 backspace。在本專案
    /// 所出貨的每個平台上,那都是兩個不同的鍵;而兩者容易被混為一談,是因為 macOS 把 backspace
    /// 標示為「delete」。
    public static let upArrow = KeyEquivalent("\u{F700}")
    public static let downArrow = KeyEquivalent("\u{F701}")
    public static let leftArrow = KeyEquivalent("\u{F702}")
    public static let rightArrow = KeyEquivalent("\u{F703}")
    public static let escape = KeyEquivalent("\u{1B}")
    public static let delete = KeyEquivalent("\u{7F}")
    public static let deleteForward = KeyEquivalent("\u{F728}")
    public static let home = KeyEquivalent("\u{F729}")
    public static let end = KeyEquivalent("\u{F72B}")
    public static let pageUp = KeyEquivalent("\u{F72C}")
    public static let pageDown = KeyEquivalent("\u{F72D}")
    public static let clear = KeyEquivalent("\u{F739}")
    public static let tab = KeyEquivalent("\u{9}")
    public static let space = KeyEquivalent(" ")
    public static let `return` = KeyEquivalent("\r")
}

extension KeyEquivalent: ExpressibleByExtendedGraphemeClusterLiteral {
    public init(extendedGraphemeClusterLiteral value: Character) {
        self.init(value)
    }
}

/// The modifier keys held with a shortcut.
///
/// **`.command` DOES NOT MEAN A COMMAND KEY ON WINDOWS OR LINUX**, and this is
/// the one thing about this type worth reading twice. SwiftUI's default modifier
/// for `.keyboardShortcut(_:)` is `.command`, so almost every shortcut anyone
/// writes carries it -- and the platforms this project ships on have no such
/// key. It resolves to Ctrl on GTK, WinUI and Android, and to the Command key
/// only on AppKit and UIKit.
///
/// The alternative was to name it `.primary` and be honest at the cost of not
/// compiling SwiftUI code, and that is the trade this project has already made
/// the other way several times: the point of the parity work is that code moves
/// across unchanged. So the NAME is SwiftUI's and the MEANING is per-platform,
/// documented here rather than discovered later.
///
/// `.option` has the same shape: Alt everywhere that is not Apple.
///
/// 隨快捷鍵一同按下的修飾鍵。
///
/// **`.command` 在 Windows 與 Linux 上並不代表某個 Command 鍵**,而這是本型別最值得讀兩遍的一點。
/// SwiftUI 中 `.keyboardShortcut(_:)` 的預設修飾鍵就是 `.command`,因此幾乎每一個有人寫下的快捷鍵
/// 都帶著它——而本專案所出貨的平台上根本沒有那顆鍵。它在 GTK、WinUI 與 Android 上解析為 **Ctrl**,
/// 僅在 AppKit 與 UIKit 上才是 Command 鍵。
///
/// 另一個選項是把它命名為 `.primary`,以「SwiftUI 程式碼編不過」為代價換取誠實;而本專案在許多地方
/// 已經做過相反方向的取捨:parity 工作的重點,正是**程式碼能原封不動地移植過來**。因此**名稱**採用
/// SwiftUI 的,而**意義**依平台而定,並記載於此處,而非留待日後被發現。
///
/// `.option` 的形狀相同:在非 Apple 平台上就是 Alt。
public struct EventModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Ctrl on GTK, WinUI and Android; the Command key on AppKit and UIKit.
    /// 在 GTK、WinUI 與 Android 上是 Ctrl;在 AppKit 與 UIKit 上是 Command 鍵。
    public static let command = EventModifiers(rawValue: 1 << 0)
    public static let shift = EventModifiers(rawValue: 1 << 1)
    /// Alt on GTK, WinUI and Android; the Option key on AppKit and UIKit.
    /// 在 GTK、WinUI 與 Android 上是 Alt;在 AppKit 與 UIKit 上是 Option 鍵。
    public static let option = EventModifiers(rawValue: 1 << 2)
    /// The physical Control key, on every platform.
    ///
    /// On Apple platforms this is a DIFFERENT key from ``command``. Elsewhere
    /// the two resolve to the same physical key, so `[.command, .control]` is
    /// not two modifiers there -- it is one. A backend that emits both would
    /// produce a shortcut nobody can press.
    ///
    /// 實體的 Control 鍵,在每個平台上皆然。
    ///
    /// 在 Apple 平台上,它與 ``command`` 是**不同**的鍵;在其他平台上兩者解析為**同一顆**實體鍵,
    /// 因此 `[.command, .control]` 在那裡不是兩個修飾鍵,而是一個。若某個 backend 把兩者都送出,
    /// 會產生一個**沒有人按得出來**的快捷鍵。
    public static let control = EventModifiers(rawValue: 1 << 3)
    public static let capsLock = EventModifiers(rawValue: 1 << 4)
    public static let numericPad = EventModifiers(rawValue: 1 << 5)

    public static let all: EventModifiers = [
        .command, .shift, .option, .control, .capsLock, .numericPad,
    ]
}

/// A key plus its modifiers.
///
/// Separate from ``KeyEquivalent`` because SwiftUI separates them, and because
/// a menu item stores the pair while `.keyboardShortcut(_:modifiers:)` takes
/// them apart.
///
/// 一個鍵,加上它的修飾鍵。
///
/// 與 ``KeyEquivalent`` 分開,因為 SwiftUI 就是分開的,也因為選單項目儲存的是這一對,而
/// `.keyboardShortcut(_:modifiers:)` 則把它們拆開來接收。
public struct KeyboardShortcut: Hashable, Sendable {
    public var key: KeyEquivalent
    public var modifiers: EventModifiers

    /// `.command` by default, matching SwiftUI -- which means Ctrl on three of
    /// the five backends. See ``EventModifiers/command``.
    /// 預設為 `.command`,與 SwiftUI 一致——而那在五個 backend 中的三個上意謂 Ctrl。
    /// 見 ``EventModifiers/command``。
    public init(_ key: KeyEquivalent, modifiers: EventModifiers = .command) {
        self.key = key
        self.modifiers = modifiers
    }
}
