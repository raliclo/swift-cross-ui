/// One of the built-in button appearances, which own their own interaction
/// behaviour.
///
/// **Not named `ButtonStyle`: that name belongs to the protocol.** SwiftUI's
/// `ButtonStyle` "applies standard interaction behavior **and a custom
/// appearance** to all buttons within a view hierarchy", and a struct with
/// three static members cannot do the custom-appearance half at all: with the
/// name on a struct, `.buttonStyle(.bordered)` compiles and
///
///     struct MyStyle: ButtonStyle {
///         func makeBody(configuration: Configuration) -> some View { ... }
///     }
///
/// cannot. `PrimitiveButtonStyle` is SwiftUI's own name for exactly this thing:
/// a style that owns the button's interaction rather than restyling it.
/// (Upstream's #590 named this struct `ButtonStyle`.)
///
/// `.bordered` / `.plain` / `.borderless` spell the three appearances, and
/// every backend switches on ``Kind``.
///
/// This is deliberately *not* a conformer of ``ButtonStyle``. A `ButtonStyle`
/// draws itself out of ordinary views and is handed `isPressed`; these three
/// are drawn by the platform, which tracks its own pressed state and never
/// calls back into Swift to do it. Conforming would require inventing a
/// `makeBody` that no backend would ever call.
///
/// 三種內建按鈕外觀之一，它們自行掌管互動行為。
///
/// **不叫 `ButtonStyle`:那個名字屬於 protocol。** SwiftUI 的 `ButtonStyle`「對某個 view 階層中的所有按鈕
/// 套用標準互動行為**與自訂外觀**」,而一個只有三個靜態成員的 struct 根本做不到「自訂外觀」那一半：只要那個
/// 名字指向一個 struct,`.buttonStyle(.bordered)` 編得過，而
///
///     struct MyStyle: ButtonStyle {
///         func makeBody(configuration: Configuration) -> some View { ... }
///     }
///
/// 編不過。`PrimitiveButtonStyle` 正是 SwiftUI 自己給這種東西的名字：一個掌管按鈕互動、而非替它重新繪製
/// 外觀的樣式。(upstream 的 #590 把這個 struct 命名為 `ButtonStyle`。)
///
/// `.bordered` / `.plain` / `.borderless` 代表三種外觀，所有 backend 都對 ``Kind`` 做 switch。
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
