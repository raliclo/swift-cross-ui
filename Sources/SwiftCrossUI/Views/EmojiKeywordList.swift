/// An editable list of keywords, each with an emoji toggle, a colour bar and a
/// delete button, and a field with an Add button below -- the api18 app's
/// "interested places" panel as a component.
///
/// ```swift
/// @State var places = [
///     EmojiKeywordItem(keyword: "停車場", emoji: "🅿", color: "#1e88e5"),
/// ]
///
/// EmojiKeywordList(items: $places)
/// ```
///
/// Each row: an ``EmojiToggleButton`` (tap: on/off; long press: change the
/// emoji), the keyword behind a bar in the row's colour, and ✕. Add appends
/// the trimmed keyword with 📍 and the next palette colour, switched on;
/// a blank or duplicate keyword is ignored (see
/// ``EmojiKeywordItem/adding(_:to:palette:)``). Persist the rows with
/// ``EmojiKeywordItem/csv(_:)`` and ``EmojiKeywordItem/items(fromCSV:palette:)``.
///
/// 可編輯的關鍵字清單，每列有 emoji 切換鈕、顏色條與刪除鈕，下方是欄位與「新增」按鈕——即 api18 app「感興趣的
/// 地點」面板的元件版。每列：``EmojiToggleButton``(點：開關;長按：換 emoji)、前面有該列顏色條的關鍵字，以及
/// ✕。「新增」把去掉前後空白的關鍵字以 📍 與下一個調色盤顏色加入並開啟;空白或重複的關鍵字會被忽略。以
/// ``EmojiKeywordItem/csv(_:)`` 與 ``EmojiKeywordItem/items(fromCSV:palette:)`` 保存各列。
public struct EmojiKeywordList: View {
    @Binding private var items: [EmojiKeywordItem]
    private var title: String?
    private var placeholder: String
    private var addLabel: String
    private var palette: [String]
    private var choices: [String]
    private var onPickerPresented: (EmojiKeywordItem) -> Void

    @State private var newKeyword = ""

    /// - Parameters:
    ///   - items: The rows; edited in place.
    ///   - title: Shown above the rows; `nil` for none.
    ///   - placeholder: The new keyword field's placeholder.
    ///   - addLabel: The Add button's title.
    ///   - palette: Colours given to new rows in turn, `#rrggbb`.
    ///   - choices: The emoji the pickers offer.
    ///   - onPickerPresented: Called with the row whose picker a long press opened.
    public init(
        items: Binding<[EmojiKeywordItem]>,
        title: String? = "感興趣的地點 / Places",
        placeholder: String = "關鍵字 / keyword",
        addLabel: String = "新增 Add",
        palette: [String] = EmojiKeywordPalette.defaultColors,
        choices: [String] = EmojiCatalog.defaultChoices,
        onPickerPresented: @escaping (EmojiKeywordItem) -> Void = { _ in }
    ) {
        self._items = items
        self.title = title
        self.placeholder = placeholder
        self.addLabel = addLabel
        self.palette = palette
        self.choices = choices
        self.onPickerPresented = onPickerPresented
    }

    /// A binding to one field of the row with `id`, found again on every
    /// access so a deletion above it cannot make it write to the wrong row.
    /// 指向 `id` 那一列某個欄位的 binding,每次存取時重新尋找，使上方的刪除不會讓它寫到錯的列。
    private func binding<Value>(
        _ id: String,
        _ keyPath: WritableKeyPath<EmojiKeywordItem, Value>,
        fallback: Value
    ) -> Binding<Value> {
        let items = $items
        return Binding(
            get: {
                items.wrappedValue.first { $0.id == id }?[keyPath: keyPath] ?? fallback
            },
            set: { value in
                if let index = items.wrappedValue.firstIndex(where: { $0.id == id }) {
                    items.wrappedValue[index][keyPath: keyPath] = value
                }
            }
        )
    }

    private func add() {
        if let added = EmojiKeywordItem.adding(newKeyword, to: items, palette: palette) {
            items = added
            newKeyword = ""
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title).emphasized()
            }
            ForEach(items) { item in
                HStack(spacing: 6) {
                    EmojiToggleButton(
                        emoji: binding(item.id, \.emoji, fallback: item.emoji),
                        isOn: binding(item.id, \.isOn, fallback: item.isOn),
                        keyword: item.keyword,
                        choices: choices,
                        onPickerPresented: { onPickerPresented(item) }
                    )
                    item.resolvedColor
                        .frame(width: 6, height: 26)
                    Text(item.keyword)
                    Spacer()
                    Button("✕") {
                        items.removeAll { $0.id == item.id }
                    }
                }
            }
            HStack(spacing: 6) {
                TextField(placeholder, text: $newKeyword)
                    .onSubmit { add() }
                Button(addLabel) { add() }
            }
        }
    }
}

/// The 📍 button that opens and closes an ``EmojiKeywordList`` below it, from
/// the api18 app's map control (`poi-button`): 40 x 40, white, the emoji at
/// 22 pt. Open, the list is shown under the button in a white rounded panel
/// 270 points wide, as the api18 panel is.
///
/// ```swift
/// EmojiKeywordListButton(items: $places)
/// ```
///
/// Inline rather than a popover so that the rows' long-press pickers (sheets)
/// are not presented from inside another presentation. Put it in an
/// `overlay(alignment: .topTrailing)` to float it over a map the way api18
/// does.
///
/// 開關其下方 ``EmojiKeywordList`` 的 📍 按鈕，來自 api18 app 的地圖控制項(`poi-button`):40 x 40、白色、
/// emoji 22 pt。開啟時，清單顯示在按鈕下方一個 270 點寬的白色圓角面板中，與 api18 的面板相同。採就地展開而非
/// popover,使各列長按叫出的選擇器(sheet)不會從另一個呈現之中再呈現。要像 api18 那樣浮在地圖上，就放進
/// `overlay(alignment: .topTrailing)`。
public struct EmojiKeywordListButton: View {
    @Binding private var items: [EmojiKeywordItem]
    private var externalIsOpen: Binding<Bool>?
    private var emoji: String
    private var title: String?
    private var palette: [String]
    private var choices: [String]
    private var onPickerPresented: (EmojiKeywordItem) -> Void

    @State private var internalIsOpen = false

    /// - Parameters:
    ///   - items: The rows of the list.
    ///   - isOpen: Whether the list is shown; kept internally when `nil`.
    ///   - emoji: The button's emoji.
    ///   - title: The list's title.
    ///   - palette: Colours given to new rows in turn.
    ///   - choices: The emoji the pickers offer.
    ///   - onPickerPresented: Called with the row whose picker a long press opened.
    public init(
        items: Binding<[EmojiKeywordItem]>,
        isOpen: Binding<Bool>? = nil,
        emoji: String = EmojiCatalog.defaultEmoji,
        title: String? = "感興趣的地點 / Places",
        palette: [String] = EmojiKeywordPalette.defaultColors,
        choices: [String] = EmojiCatalog.defaultChoices,
        onPickerPresented: @escaping (EmojiKeywordItem) -> Void = { _ in }
    ) {
        self._items = items
        self.externalIsOpen = isOpen
        self.emoji = emoji
        self.title = title
        self.palette = palette
        self.choices = choices
        self.onPickerPresented = onPickerPresented
    }

    private var isOpen: Binding<Bool> {
        externalIsOpen ?? $internalIsOpen
    }

    public var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(EmojiCatalog.displayed(emoji))
                .font(.system(size: 22))
                .foregroundColor(.black)
                .frame(width: 40, height: 40)
                .background(EmojiKeywordPanelBackground(cornerRadius: 4, borderWidth: 2))
                .onTapGesture {
                    isOpen.wrappedValue.toggle()
                }
            if isOpen.wrappedValue {
                // A white panel in either scheme, as api18's is, so its text,
                // field and buttons are drawn light. / 不論哪種配色都是白色面板(與 api18 相同),
                // 因此其中的文字、欄位與按鈕以淺色配色繪製。
                EmojiKeywordList(
                    items: $items,
                    title: title,
                    palette: palette,
                    choices: choices,
                    onPickerPresented: onPickerPresented
                )
                    .foregroundColor(.black)
                    .colorScheme(.light)
                    .padding(8)
                    .frame(width: 270)
                    .background(EmojiKeywordPanelBackground(cornerRadius: 6, borderWidth: 1))
            }
        }
        // As wide as the panel whether it is open or not, the pin at the
        // trailing edge: without this the stack shrank to the button when the
        // list closed and the pin jumped left, so a second tap missed it
        // (P103 on AppKit, 2026-10-17). / 不論開或關都與面板同寬、釘選鈕在尾端：少了這一行，清單關閉時
        // 堆疊縮成按鈕的寬度、釘選鈕跳到左邊，第二次點擊就點不到(P103,AppKit,2026-10-17)。
        .frame(width: 270, alignment: .topTrailing)
    }
}

/// White with a faint border, drawn BEHIND the content. An `overlay` stroke
/// sits above the rows and, on AppKit, takes their clicks: measured on P103
/// (2026-10-17), the rows' taps and long presses did nothing while the SOLO
/// toggle outside the panel worked.
/// 白底加淡邊框，畫在內容**後面**。`overlay` 的描邊位在各列之上，在 AppKit 上會吃掉它們的點擊:P103 實測
/// (2026-10-17),面板外的 SOLO 切換鈕正常，面板內各列的點按與長按都沒有反應。
struct EmojiKeywordPanelBackground: View {
    var cornerRadius: Double
    var borderWidth: Double

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius).fill(Color.white)
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color(hex: "#00000033")!, style: StrokeStyle(width: borderWidth))
        }
    }
}
