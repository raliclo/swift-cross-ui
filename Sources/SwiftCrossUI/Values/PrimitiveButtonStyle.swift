/// One of the built-in button appearances, which own their own interaction
/// behaviour.
///
/// **Renamed from `ButtonStyle` on 2026-09-08, and the name it gave up now
/// belongs to a protocol.** Upstream's #590 introduced this as a struct called
/// `ButtonStyle` with a closed set of three cases, carrying SwiftUI's doc
/// comment for the *protocol* of that name -- "applies standard interaction
/// behavior **and a custom appearance** to all buttons within a view
/// hierarchy". A struct with three static members cannot do the
/// custom-appearance half at all: `.buttonStyle(.bordered)` compiled, and
///
///     struct MyStyle: ButtonStyle {
///         func makeBody(configuration: Configuration) -> some View { ... }
///     }
///
/// could not, and could not be made to, for as long as the name referred to a
/// struct. `PrimitiveButtonStyle` is SwiftUI's own name for exactly this thing:
/// a style that owns the button's interaction rather than restyling it. The
/// doc comment above is written for what this type actually is.
///
/// The three cases are unchanged, and `.bordered` / `.plain` / `.borderless`
/// still spell the same appearances they did before the rename. Every backend
/// keeps switching on ``Kind``.
///
/// This is deliberately *not* a conformer of ``ButtonStyle``. A `ButtonStyle`
/// draws itself out of ordinary views and is handed `isPressed`; these three
/// are drawn by the platform, which tracks its own pressed state and never
/// calls back into Swift to do it. Conforming would require inventing a
/// `makeBody` that no backend would ever call.
///
/// 三種內建按鈕外觀之一，它們自行掌管互動行為。
///
/// **2026-09-08 由 `ButtonStyle` 更名而來，而它讓出的名字現在屬於一個 protocol。** upstream 的 #590
/// 以名為 `ButtonStyle` 的 struct 引入了這個封閉的三元集合，並沿用了 SwiftUI 中**同名 protocol** 的
/// 文件註解——「對某個 view 階層中的所有按鈕套用標準互動行為**與自訂外觀**」。一個只有三個靜態成員的
/// struct 根本做不到「自訂外觀」那一半：`.buttonStyle(.bordered)` 編得過，而
///
///     struct MyStyle: ButtonStyle {
///         func makeBody(configuration: Configuration) -> some View { ... }
///     }
///
/// 編不過，而且只要那個名字仍指向一個 struct，就永遠無法讓它編得過。`PrimitiveButtonStyle` 正是
/// SwiftUI 自己給這種東西的名字：一個掌管按鈕互動、而非替它重新繪製外觀的樣式。上方的文件註解，寫的
/// 是這個型別實際上是什麼。
///
/// 三個 case 沒有改變，`.bordered` / `.plain` / `.borderless` 仍然代表更名前的同一批外觀。所有
/// backend 依舊是對 ``Kind`` 做 switch。
///
/// 它刻意**不**遵從 ``ButtonStyle``。一個 `ButtonStyle` 是以一般 view 自行繪製、並會收到 `isPressed`；
/// 而這三者是由平台繪製的，平台自行追蹤按下狀態，從不為此回呼 Swift。若要它遵從，就得憑空造出一個
/// 沒有任何 backend 會呼叫的 `makeBody`。
public struct PrimitiveButtonStyle: Hashable, Sendable {
    package enum Kind {
        case bordered
        case plain
        case borderless
    }

    package var kind: Kind

    /// A button style that applies the standard border style based on the button’s context.
    @available(iOS 15.0, tvOS 15.0, macCatalyst 15.0, *)
    public static let bordered = Self(kind: .bordered)
    /// A button style that doesn’t style or decorate its content while idle,
    /// but may apply a visual effect to indicate the pressed, focused, or enabled state of the button.
    public static let plain = Self(kind: .plain)
    /// A button style that doesn’t apply a border.
    ///
    /// On desktop operating systems it behaves mostly the same as ``PrimitiveButtonStyle/plain``
    /// due to the SwiftUI borderless behavior on mac being stupid.
    /// The only difference is a default foreground color of gray being applied.
    public static let borderless = Self(kind: .borderless)
}

extension PrimitiveButtonStyle: CustomStringConvertible {
    public var description: String {
        "\(self.kind)"
    }
}
