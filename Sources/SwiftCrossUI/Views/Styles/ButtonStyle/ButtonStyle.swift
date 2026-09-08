/// A type that applies standard interaction behavior and a custom appearance to
/// all buttons within a view hierarchy.
///
/// **This is the name upstream's #590 gave to a struct.** That struct is now
/// ``PrimitiveButtonStyle``, which is what SwiftUI calls a closed set of
/// built-in appearances that own their own interaction. The name is back where
/// SwiftUI puts it: on the protocol an application conforms to in order to draw
/// a button itself.
///
///     struct Bezelled: ButtonStyle {
///         func makeBody(configuration: Configuration) -> some View {
///             configuration.label
///                 .padding(8)
///                 .background(configuration.isPressed ? .gray : .white)
///         }
///     }
///
/// Shaped after ``LabelStyle``, which is this repository's one style protocol
/// verified against SwiftUI member for member, and the two omissions it records
/// apply here for the same reasons.
///
/// **There is no `isSupported(backend:)`.** Every conformer draws itself out of
/// ordinary views, so the answer could only ever be `true`; `_BuiltinToggleStyle`
/// records what a query that can only return `true` costs. **And there is no
/// `_BuiltinButtonStyle` companion protocol**, because that protocol exists
/// elsewhere to translate a style into a backend's own vocabulary
/// (`_asBackendPickerStyle`, `_asBackendListStyle`). The backend vocabulary for
/// buttons is ``PrimitiveButtonStyle/Kind``, and a custom `ButtonStyle` does not
/// translate into it -- it replaces it. ``Button`` renders a style's body inside
/// a `.plain` platform button precisely so that nothing of the platform's own
/// appearance survives to fight with it.
///
/// The requirement is SwiftUI's `makeBody(configuration:)` rather than this
/// project's usual `makeView(...)`: ``ButtonStyleConfiguration`` already carries
/// everything a button style needs, so there is no argument list to invent.
///
/// 對某個 view 階層中的所有按鈕套用標準互動行為與自訂外觀的型別。
///
/// **這個名字原本被 upstream 的 #590 用在一個 struct 上。** 該 struct 現已改名為
/// ``PrimitiveButtonStyle``——那正是 SwiftUI 對「一組自行掌管互動行為的內建外觀」所用的名稱。名字因此
/// 回到 SwiftUI 放置它的位置：一個讓應用程式遵從、以便自行繪製按鈕的 protocol。
///
/// 形狀比照 ``LabelStyle``——本專案唯一一個逐一成員對照過 SwiftUI 的樣式 protocol——而它所記下的兩項
/// 缺席，在此處基於相同理由同樣成立。
///
/// **此處沒有 `isSupported(backend:)`。** 所有 conformer 都是以一般 view 自行繪製，答案只可能是
/// `true`；`_BuiltinToggleStyle` 已記下「一個只可能回傳 `true` 的查詢」要付出什麼代價。**此處也沒有
/// `_BuiltinButtonStyle` 這個伴生 protocol**，因為該 protocol 在別處的用途是把 style 翻譯成 backend
/// 自身的詞彙（`_asBackendPickerStyle`、`_asBackendListStyle`）。按鈕在 backend 端的詞彙是
/// ``PrimitiveButtonStyle/Kind``，而自訂的 `ButtonStyle` 並不會翻譯成它——而是取代它。``Button`` 之所以
/// 把 style 的 body 畫在一個 `.plain` 的平台按鈕內，正是為了讓平台自身的外觀不留下任何東西與之衝突。
///
/// 其 requirement 採用 SwiftUI 的 `makeBody(configuration:)`，而非本專案慣用的 `makeView(...)`：
/// ``ButtonStyleConfiguration`` 已經帶著 button style 所需的一切，因此不需要憑空設計一組參數。
@MainActor
public protocol ButtonStyle: Sendable {
    associatedtype Body: View

    /// The properties of the button being rendered.
    typealias Configuration = ButtonStyleConfiguration

    /// The method used to render ``Button``.
    /// - Parameter configuration: The label, pressed state and role of the
    ///   button being rendered.
    func makeBody(configuration: Configuration) -> Body
}

/// The label, pressed state and role of the ``Button`` being rendered.
///
/// **``Label`` is ``AnyView`` here, and SwiftUI's is an opaque struct.** The
/// name still resolves, so `ButtonStyleConfiguration.Label` carried over from
/// SwiftUI compiles, and a style writes `configuration.label` either way. This
/// follows ``LabelStyleConfiguration``, whose note states the cost a wrapper
/// struct would add: a plain `struct Label: View` gets `View.defaultAsWidget`,
/// which wraps its body in a `VStack`, so the label would gain a container that
/// exists only to hide a type that is already erased one line below. The
/// erasure is unavoidable -- this type is not generic, exactly as SwiftUI's is
/// not -- so naming it is the honest option rather than dressing it up.
///
/// ``isPressed`` is the whole reason ``BackendFeatures/ButtonPressState``
/// exists. Without a live signal from the platform a custom style would
/// compile, render, and never change; see that protocol for why it is a
/// separate backend feature rather than a parameter on `updateButton`.
///
/// 正在繪製之 ``Button`` 的 label、按下狀態與 role。
///
/// **此處的 ``Label`` 是 ``AnyView``，而 SwiftUI 的則是 opaque struct。** 名字仍然可以解析，因此從
/// SwiftUI 搬過來的 `ButtonStyleConfiguration.Label` 編得過，而 style 兩邊都是寫
/// `configuration.label`。此處比照 ``LabelStyleConfiguration``，其說明已指出包裝 struct 會多帶來的
/// 代價：一個單純的 `struct Label: View` 會走 `View.defaultAsWidget`，該實作會把 body 包進一個
/// `VStack`，於是 label 多出一個容器，而它存在的唯一目的，是去藏一個在下一行就已經被抹除的型別。
/// 這個抹除是免不了的——本型別並非泛型，正如 SwiftUI 的也不是——因此如實把它命名出來，比替它裝扮成
/// 別的東西要誠實。
///
/// ``isPressed`` 正是 ``BackendFeatures/ButtonPressState`` 存在的全部理由。若沒有來自平台的即時訊號，
/// 自訂樣式編得過、畫得出來，然後永遠不會變化；至於它為何是一個獨立的 backend feature、而非
/// `updateButton` 上的一個參數，見該 protocol。
public struct ButtonStyleConfiguration {
    /// The type of the button's label.
    public typealias Label = AnyView

    /// A view that describes the effect of pressing the button.
    public var label: Label

    /// Whether the button is currently being pressed.
    ///
    /// Kept live by ``BackendFeatures/ButtonPressState``. ``Button`` stores the
    /// value in a `@State`, so a transition re-runs ``ButtonStyle/makeBody(configuration:)``
    /// through the ordinary view-graph update rather than through anything
    /// special to buttons.
    ///
    /// 由 ``BackendFeatures/ButtonPressState`` 維持在最新狀態。``Button`` 把這個值存放於一個
    /// `@State`，因此每次轉換都會經由一般的 view graph 更新流程重新執行
    /// ``ButtonStyle/makeBody(configuration:)``，而不是靠任何按鈕專屬的機制。
    public var isPressed: Bool

    /// What the button is for, when that changes how it should look.
    ///
    /// **Not in SwiftUI's `ButtonStyleConfiguration` before iOS 26**, and
    /// included here because this project already has ``ButtonRole`` and already
    /// hands it to every backend through ``EnvironmentValues/buttonRole``. A
    /// custom style that could not see the role would have to render a
    /// destructive button identically to an ordinary one, which is the one thing
    /// ``ButtonRole`` exists to prevent.
    ///
    /// **在 iOS 26 之前，SwiftUI 的 `ButtonStyleConfiguration` 並沒有這個成員**；此處納入它，是因為本
    /// 專案已經有 ``ButtonRole``，也已經透過 ``EnvironmentValues/buttonRole`` 把它交給每一個 backend。
    /// 一個看不見 role 的自訂樣式，只能把破壞性按鈕畫得和一般按鈕一模一樣，而那恰恰是 ``ButtonRole``
    /// 存在所要避免的事。
    public var role: ButtonRole?

    /// Wraps a button's label and state for a style to draw around.
    ///
    /// Internal because ``Button`` is the only thing that should build one; a
    /// style receives a configuration, it does not manufacture one.
    ///
    /// `@MainActor` because it calls `AnyView.init`, which is main-actor
    /// isolated (`AnyView.swift:15`) -- the same reason
    /// ``LabelStyleConfiguration``'s initialiser carries the attribute, and the
    /// same reason `swiftc -parse` will not catch its absence.
    ///
    /// 標記為 internal，因為只有 ``Button`` 該建構它；style 是「收到」一個 configuration，而不是自己
    /// 製造一個。
    ///
    /// 標記 `@MainActor` 是因為它呼叫 `AnyView.init`，而後者受 main actor 隔離
    /// （`AnyView.swift:15`）——與 ``LabelStyleConfiguration`` 的建構式帶有該標記的理由相同，也與
    /// 「`swiftc -parse` 抓不到它缺席」的理由相同。
    @MainActor
    init(label: some View, isPressed: Bool, role: ButtonRole?) {
        self.label = AnyView(label)
        self.isPressed = isPressed
        self.role = role
    }
}
