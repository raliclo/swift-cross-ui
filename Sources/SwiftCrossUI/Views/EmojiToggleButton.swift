/// An emoji in a circle that a tap switches on and off and a long press lets
/// the user change, from the api18 app's "interested places" list.
///
/// ```swift
/// EmojiToggleButton(emoji: $item.emoji, isOn: $item.isOn, keyword: item.keyword)
/// ```
///
/// - On: light purple (#e1bee7) with a purple (#8e24aa) border.
/// - Off: light grey with a grey border, dimmed to 55 %.
/// - A tap toggles `isOn`. A long press (about half a second) presents an
///   ``EmojiPicker`` in a sheet; choosing sets `emoji` and closes it. A long
///   press does not also toggle.
///
/// The tap and the long press go through
/// ``View/onTapAndLongPressGesture(onTap:onLongPress:)``, which every shipped
/// backend implements.
///
/// 圓圈裡的 emoji:點一下開關，長按讓使用者更換，來自 api18 app「感興趣的地點」清單。開啟：淺紫色(#e1bee7)底、
/// 紫色(#8e24aa)邊框;關閉：淺灰底、灰邊框，淡化為 55%。點一下切換 `isOn`;長按(約半秒)以 sheet 顯示
/// ``EmojiPicker``,選了就設定 `emoji` 並關閉。長按不會同時切換。點按與長按經由
/// ``View/onTapAndLongPressGesture(onTap:onLongPress:)``,每個已發布的 backend 都有實作。
public struct EmojiToggleButton: View {
    @Binding private var emoji: String
    @Binding private var isOn: Bool
    private var keyword: String
    private var size: Double
    private var choices: [String]
    private var onPickerPresented: () -> Void

    @State private var isPickerPresented = false

    /// - Parameters:
    ///   - emoji: The emoji shown; the picker changes it.
    ///   - isOn: Switched by a tap.
    ///   - keyword: What the picker puts first; also its title.
    ///   - size: The circle's diameter.
    ///   - choices: The emoji the picker offers.
    ///   - onPickerPresented: Called when a long press opens the picker.
    public init(
        emoji: Binding<String>,
        isOn: Binding<Bool>,
        keyword: String = "",
        size: Double = 38,
        choices: [String] = EmojiCatalog.defaultChoices,
        onPickerPresented: @escaping () -> Void = {}
    ) {
        self._emoji = emoji
        self._isOn = isOn
        self.keyword = keyword
        self.size = size
        self.choices = choices
        self.onPickerPresented = onPickerPresented
    }

    public var body: some View {
        let fill = isOn ? EmojiKeywordPalette.highlightFill : Color(hex: "#f2f2f2")!
        let border = isOn ? EmojiKeywordPalette.highlightBorder : Color(hex: "#cccccc")!
        Text(EmojiCatalog.displayed(emoji))
            .font(.system(size: (size * 0.53).rounded()))
            .foregroundColor(.black)
            .frame(width: size, height: size)
            .background(Circle().fill(fill))
            .overlay {
                Circle().stroke(border, style: StrokeStyle(width: 2))
            }
            .opacity(isOn ? 1 : 0.55)
            .onTapAndLongPressGesture {
                isOn.toggle()
            } onLongPress: {
                isPickerPresented = true
                onPickerPresented()
            }
            .sheet(isPresented: $isPickerPresented) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(keyword.isEmpty ? "圖示 / icon" : "\(keyword) 的圖示 / icon")
                            .emphasized()
                        Spacer()
                        Button("✕") { isPickerPresented = false }
                    }
                    EmojiPicker(selection: $emoji, keyword: keyword, choices: choices) { _ in
                        isPickerPresented = false
                    }
                }
                .padding(12)
            }
    }
}
