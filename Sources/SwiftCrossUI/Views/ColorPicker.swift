/// A labelled control for choosing a colour.
///
/// Composed from ``HStack``, ``Slider``, ``Button`` and a filled rectangle, so it
/// needs nothing from any backend and behaves identically on all five. That is
/// the same reason ``Stepper``, ``Gauge`` and ``LabeledContent`` were done
/// before the protocol-level parity items, and it is the reason this one is not
/// waiting for a native colour panel on each platform.
///
/// **It is not the system colour panel, and that is a deliberate trade rather
/// than a stand-in.** SwiftUI's `ColorPicker` opens the platform's own picker:
/// `NSColorPanel` on macOS, `UIColorPickerViewController` on iOS,
/// `GtkColorDialog` on GTK, a `ColorPicker` flyout on WinUI, and on Android
/// nothing that is part of the platform at all -- there is no stock colour
/// dialog, so that one would have to be drawn regardless. Five native pickers
/// are five separate presentations to drive and photograph, and four of them
/// are modal, which means the action files that exercise this view would each
/// have to know how to dismiss a different sheet. What is here works everywhere
/// today and can be driven by a coordinate.
///
/// A backend that wants its native panel can add one later without changing
/// this API, because the API is a `Binding<Color>` and a label -- which is all
/// SwiftUI's is.
///
/// 一個用來選擇顏色的、帶標籤的控制項。
///
/// 由 ``HStack``、``Slider``、``Button`` 與一個填色矩形組合而成，因此不需要任何 backend 支援，在五個
/// backend 上的行為也完全相同。這與 ``Stepper``、``Gauge`` 與 ``LabeledContent`` 先於協定層級的
/// parity 項目被完成是同一個理由，也是它不必等待各平台原生調色盤的理由。
///
/// **它不是系統的調色盤，而那是一項刻意的取捨，不是一個代用品。** SwiftUI 的 `ColorPicker` 會開啟
/// 平台自身的選擇器:macOS 的 `NSColorPanel`、iOS 的 `UIColorPickerViewController`、GTK 的
/// `GtkColorDialog`、WinUI 的 `ColorPicker` flyout——而在 Android 上則根本沒有屬於平台的那種東西:
/// 系統沒有內建的顏色對話框，因此那一個無論如何都得自己畫。五個原生選擇器就是五套要驅動、要拍照的
/// 呈現方式，其中四個還是 modal 的，意味著演練本 view 的動作檔各自都得知道如何關掉一個不同的 sheet。
/// 此處的實作今天就能在每個地方運作，而且可以用一個座標來驅動。
///
/// 想要原生面板的 backend 日後可以自行加上，而不必改動這個 API——因為這個 API 就是一個
/// `Binding<Color>` 加一個標籤，而 SwiftUI 的也就是這樣。
public struct ColorPicker<Label: View>: View {
    private let label: Label
    private let selection: Binding<Color>

    @Environment(\.self) private var environment
    @State private var isEditing = false

    public init(selection: Binding<Color>, @ViewBuilder label: () -> Label) {
        self.init(selection: selection, label: label())
    }

    init(selection: Binding<Color>, label: Label) {
        self.selection = selection
        self.label = label
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                label
                ColorPickerSwatch(color: selection.wrappedValue)
                Button(isEditing ? "Done" : "Edit") {
                    isEditing.toggle()
                }
            }

            // Shown rather than always present, because three sliders under
            // every colour well would dominate any form that has more than one.
            // 採用「展開才顯示」而非常駐,因為每一個顏色選擇器底下都掛三個 slider,會在任何有一個
            // 以上選擇器的表單中喧賓奪主。
            if isEditing {
                ColorPickerChannel(name: "R", value: channel(\.red))
                ColorPickerChannel(name: "G", value: channel(\.green))
                ColorPickerChannel(name: "B", value: channel(\.blue))
            }
        }
    }

    /// One channel, as a binding a ``Slider`` can drive.
    ///
    /// Reads through ``Color/resolve(in:)`` rather than off the stored
    /// representation, because a `Color` may be `.system` or `.adaptive` and
    /// those have no red until an environment says which one applies. Writing
    /// produces a plain `.rgb` colour, which is what picking a colour means:
    /// the result stops following the colour scheme, and it should, because the
    /// user chose a colour rather than a role.
    ///
    /// 單一通道,包裝成 ``Slider`` 能驅動的 binding。
    ///
    /// 透過 ``Color/resolve(in:)`` 讀取,而非直接讀取其儲存的 representation——因為一個 `Color`
    /// 可能是 `.system` 或 `.adaptive`,而在有 environment 說明何者適用之前,它們並沒有「紅色」這個值。
    /// 寫入則產生一個單純的 `.rgb` 顏色,而那正是「選一個顏色」的意思:結果不再跟隨配色方案,而它本來
    /// 就不該跟隨,因為使用者選的是一個顏色,不是一個角色。
    private func channel(
        _ keyPath: WritableKeyPath<Color.Resolved, Float>
    ) -> Binding<Double> {
        Binding(
            get: { Double(selection.wrappedValue.resolve(in: environment)[keyPath: keyPath]) },
            set: { newValue in
                var resolved = selection.wrappedValue.resolve(in: environment)
                resolved[keyPath: keyPath] = Float(newValue)
                selection.wrappedValue = Color(
                    red: Double(resolved.red),
                    green: Double(resolved.green),
                    blue: Double(resolved.blue),
                    opacity: Double(resolved.opacity)
                )
            }
        )
    }
}

extension ColorPicker where Label == Text {
    /// The SwiftUI spelling.
    /// SwiftUI 的寫法。
    public init(_ title: String, selection: Binding<Color>) {
        // Constructed directly rather than through the ViewBuilder form: the
        // builder wraps a single view in a TupleView1, which is not Text, and
        // this overload's whole point is that Label IS Text.
        // 直接建構而非走 ViewBuilder 那一版:builder 會把單一個 view 包進 TupleView1,而那不是 Text,
        // 而本多載存在的全部意義正是「Label 就是 Text」。
        self.init(selection: selection, label: Text(title))
    }
}

/// The colour itself, shown at a fixed size.
///
/// Present because a picker whose only readout is three numbers is a form, not
/// a colour picker -- and because a swatch is the one part of this a screenshot
/// can check without reading text.
///
/// 顏色本身,以固定尺寸顯示。
///
/// 它之所以存在,是因為一個「唯一讀數是三個數字」的選擇器是一份表單,不是一個顏色選擇器——也因為
/// 色塊是本控制項中唯一「螢幕截圖不必讀文字就能檢查」的部分。
struct ColorPickerSwatch: View {
    let color: Color

    var body: some View {
        color
            .frame(width: 28, height: 18)
            .cornerRadius(4)
    }
}

/// One named channel and its slider.
/// 一個具名通道及其 slider。
struct ColorPickerChannel: View {
    let name: String
    let value: Binding<Double>

    var body: some View {
        HStack(spacing: 8) {
            Text(name)
            Slider(value: value, in: 0.0...1.0)
            // The number, because a slider alone cannot say whether a drag
            // landed where it was aimed -- which is exactly what an action file
            // needs to assert.
            // 加上數字,因為單憑一個 slider 無法說出「一次拖曳是否落在它所瞄準的位置」——而那正是
            // 動作檔需要斷言的東西。
            Text(String(format: "%.2f", value.wrappedValue))
        }
    }
}
