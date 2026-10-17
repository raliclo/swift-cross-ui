/// A grid of emoji with a search field below it, from the api18 app's
/// "interested places" icon picker.
///
/// ```swift
/// EmojiPicker(selection: $emoji, keyword: "加油站") {
///     isPickerPresented = false
/// }
/// ```
///
/// - The choices matching `keyword` (by their Chinese and English names, see
///   ``EmojiCatalog/defaultNames``) come first, on light purple with a purple
///   border.
/// - Typing in the field filters the grid by the same names.
/// - OK chooses the typed text itself, so an emoji the grid does not have can
///   be typed or pasted.
///
/// Composed from `Text`, shapes, `onTapGesture`, `TextField` and `Button`, so
/// it needs nothing from a backend beyond what every shipped backend has.
///
/// 一格格的 emoji,下方是搜尋欄，來自 api18 app「感興趣的地點」的圖示選擇器。與 `keyword` 相符的選項(依中英文
/// 名稱，見 ``EmojiCatalog/defaultNames``)排在最前面，以淺紫色底、紫色邊框標示;在欄位中打字以同樣的名稱篩選;
/// OK 選擇輸入的文字本身，因此格子裡沒有的 emoji 也能輸入或貼上。由 `Text`、形狀、`onTapGesture`、`TextField`
/// 與 `Button` 組成，不需要每個已發布 backend 都有的功能以外的任何東西。
public struct EmojiPicker: View {
    @Binding private var selection: String
    private var keyword: String
    private var choices: [String]
    private var names: [String: String]
    private var columns: Int
    private var onChoose: (String) -> Void

    @State private var filter = ""

    /// - Parameters:
    ///   - selection: The chosen emoji; set when a cell is tapped or OK pressed.
    ///   - keyword: Choices whose names match it come first, highlighted.
    ///   - choices: The emoji offered, in order.
    ///   - names: Search names per emoji, space-separated.
    ///   - columns: Cells per row.
    ///   - onChoose: Called after `selection` is set, for example to dismiss.
    public init(
        selection: Binding<String>,
        keyword: String,
        choices: [String] = EmojiCatalog.defaultChoices,
        names: [String: String] = EmojiCatalog.defaultNames,
        columns: Int = 8,
        onChoose: @escaping (String) -> Void = { _ in }
    ) {
        self._selection = selection
        self.keyword = keyword
        self.choices = choices
        self.names = names
        self.columns = max(1, columns)
        self.onChoose = onChoose
    }

    private var rows: [[EmojiChoice]] {
        let shown = EmojiCatalog.choices(choices, keyword: keyword, filter: filter, names: names)
        return stride(from: 0, to: shown.count, by: columns).map {
            Array(shown[$0..<min($0 + columns, shown.count)])
        }
    }

    private func choose(_ emoji: String) {
        selection = emoji
        onChoose(emoji)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if rows.isEmpty {
                Text("No match -- OK uses what you typed / 沒有相符的，OK 會用輸入的文字")
                    .foregroundColor(.gray)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.emoji) { choice in
                        EmojiPickerCell(choice: choice, isSelected: choice.emoji == selection) {
                            choose(choice.emoji)
                        }
                    }
                }
            }
            HStack(spacing: 6) {
                TextField("篩選或輸入 / filter or type", text: $filter)
                    .onSubmit {
                        if let typed = EmojiCatalog.typedChoice(filter) { choose(typed) }
                    }
                Button("OK") {
                    if let typed = EmojiCatalog.typedChoice(filter) { choose(typed) }
                }
            }
        }
    }
}

/// One cell: 44 x 44, the emoji at 24 pt, highlighted when it matches.
/// 一格:44 x 44,emoji 24 pt,相符時醒目標示。
struct EmojiPickerCell: View {
    var choice: EmojiChoice
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        let fill = choice.matchesKeyword ? EmojiKeywordPalette.highlightFill : Color.white
        let border =
            choice.matchesKeyword
            ? EmojiKeywordPalette.highlightBorder
            : (isSelected ? Color.gray : Color(hex: "#dddddd")!)
        Text(EmojiCatalog.displayed(choice.emoji))
            .font(.system(size: 24))
            .foregroundColor(.black)
            .frame(width: 44, height: 44)
            .background(RoundedRectangle(cornerRadius: 6).fill(fill))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(border, style: StrokeStyle(width: choice.matchesKeyword || isSelected ? 2 : 1))
            }
            .onTapGesture(perform: action)
    }
}
