/// A control for toggling between two values (usually representing on and off).
///
/// Depending on the value of ``EnvironmentValues/toggleStyle``, this control
/// can appear as a switch, a button, or a checkbox.
///
/// The label is either a string (`Toggle(_:isOn:)`) or any view
/// (`Toggle(isOn:label:)`), as in SwiftUI. A string label is drawn by the
/// native control where the control has a title of its own (the button style);
/// a view label is hosted inside the native toggle button
/// (``BackendFeatures/ViewLabelToggleButtons``), or placed beside an unlabelled
/// switch or checkbox. In the switch and checkbox styles a click on the label
/// flips the toggle as a click on the control does, and the control's
/// accessibility label is the label's text.
///
/// 在兩個值之間切換的控制項(通常代表開與關)。
///
/// 依 ``EnvironmentValues/toggleStyle`` 的值，它可以呈現為 switch、按鈕或 checkbox。
///
/// 標籤可以是字串(`Toggle(_:isOn:)`)或任何 view(`Toggle(isOn:label:)`),與 SwiftUI 相同。字串標籤在控制項本身
/// 帶有標題的地方(按鈕樣式)由原生控制項繪製;view 標籤則容納在原生 toggle 按鈕裡
/// (``BackendFeatures/ViewLabelToggleButtons``),或放在一個無標籤的 switch 或 checkbox 旁邊。在 switch 與 checkbox
/// 樣式中，點擊標籤會像點擊控制項一樣翻轉 toggle,而控制項的輔助使用標籤就是標籤的文字。
public struct Toggle: View {
    @Environment(\.self) var environment
    @Environment(\.toggleStyle) var toggleStyle

    /// The label's text: the string given, or the texts found in a view label.
    ///
    /// For a view label this is what a menu shows (a menu item can only hold a
    /// string), what a ``ToggleStyle`` written against strings receives, and
    /// the accessibility label of an unlabelled switch or checkbox.
    ///
    /// 標籤的文字：給定的字串，或在 view 標籤中找到的文字。對 view 標籤而言，這是選單所顯示的內容(選單項目只能放字串)、
    /// 以字串撰寫的 ``ToggleStyle`` 所收到的內容，也是無標籤 switch 或 checkbox 的輔助使用標籤。
    var label: String
    /// The view label, or `nil` when the toggle was given a string.
    /// view 標籤；以字串建立時為 `nil`。
    var labelView: AnyView?
    /// Whether the toggle is active or not.
    var active: Binding<Bool>

    @available(*, deprecated, renamed: "init(_:isOn:)")
    public init(_ label: String, active: Binding<Bool>) {
        self.init(label, isOn: active)
    }

    /// Creates a toggle that displays a custom label.
    ///
    /// - Parameters:
    ///   - label: The label to be shown on or beside the toggle.
    ///   - active: Whether the toggle is active or not.
    public init(_ label: String, isOn active: Binding<Bool>) {
        self.label = label
        self.labelView = nil
        self.active = active
    }

    /// Creates a toggle whose label is an arbitrary view.
    ///
    /// - Parameters:
    ///   - active: Whether the toggle is active or not.
    ///   - label: The view shown on or beside the toggle.
    ///
    /// 建立一個標籤為任意 view 的 toggle。
    public init<Label: View>(
        isOn active: Binding<Bool>,
        @ViewBuilder label: () -> Label
    ) {
        let view = label()
        self.label = Self.texts(in: view).joined(separator: " ")
        self.labelView = AnyView(view)
        self.active = active
    }

    public var body: some View {
        // Routed through the style, as `Picker` and `DatePicker` are. The built-in
        // rendering is `_BuiltinToggleImplementation`, reached by the three
        // built-in styles; a style written outside this module draws whatever it
        // likes instead. `AnyView` because the style is existential and its
        // `Body` is not known here.
        //
        // 交由 style 繪製，與 `Picker`、`DatePicker` 相同。內建的繪製是 `_BuiltinToggleImplementation`,
        // 由三個內建 style 取用；而在本模組之外撰寫的 style 則
        // 想畫什麼就畫什麼。使用 `AnyView`，因為此處的 style 是 existential，其 `Body` 型別在這裡
        // 無從得知。
        if let labelView {
            toggleStyle.makeView(
                label: labelView,
                labelText: label,
                isOn: active,
                environment: environment
            )
        } else {
            AnyView(
                toggleStyle.makeView(
                    label: label,
                    isOn: active,
                    environment: environment
                )
            )
        }
    }

    public var _asMenuItems: [MenuItem] {
        [.toggle(self)]
    }

    /// The strings of the ``Text`` views stored in `value`, in order.
    ///
    /// Read from the label's stored properties (a `TupleView`'s children, a
    /// stack's content, a `Label`'s title), not from computed bodies: a body
    /// may read state that only exists inside the view graph. A label made
    /// only of images yields nothing, and the caller then has no text to use.
    ///
    /// `value` 中所存放之 ``Text`` view 的字串，依序排列。從標籤的儲存屬性讀取(`TupleView` 的子項、堆疊的內容、
    /// `Label` 的標題),而不是從計算出來的 body 讀取:body 可能讀取只存在於 view graph 之內的狀態。只由圖片組成的標籤
    /// 得不到任何文字。
    static func texts(in value: Any, depth: Int = 0) -> [String] {
        if let text = value as? Text {
            return text.string.isEmpty ? [] : [text.string]
        }
        guard depth < 8 else {
            return []
        }
        return Mirror(reflecting: value).children.flatMap { child in
            texts(in: child.value, depth: depth + 1)
        }
    }
}

// `ToggleStyle` is a protocol in Views/Styles/ToggleStyle/. The backend's
// vocabulary is `BackendToggleStyle` in Backend/.
// `ToggleStyle` 是 Views/Styles/ToggleStyle/ 中的 protocol。backend 的詞彙是
// Backend/ 中的 `BackendToggleStyle`。
