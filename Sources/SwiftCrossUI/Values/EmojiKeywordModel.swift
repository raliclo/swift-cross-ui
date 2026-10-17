// The logic behind EmojiPicker, EmojiToggleButton and EmojiKeywordList, kept
// free of views so it can be tested without a backend. Ported from the
// "interested places" list of the api18 test app (testapp/api18/libs/js/maps.js:
// EMOJI_CHOICES, EMOJI_NAMES, emojiMatches, PALETTE, the Add button).
//
// EmojiPicker、EmojiToggleButton 與 EmojiKeywordList 背後的邏輯，不含 view,因此不需要 backend 就能測試。
// 移植自 api18 測試 app 的「感興趣的地點」清單(testapp/api18/libs/js/maps.js 的 EMOJI_CHOICES、EMOJI_NAMES、
// emojiMatches、PALETTE 與「新增」按鈕)。

import Foundation

/// The emoji a picker offers by default, their search names, and the matching
/// rules. / 選擇器預設提供的 emoji、它們的搜尋名稱，以及比對規則。
public enum EmojiCatalog {
    /// Emoji that Android 4.4's own font draws (about Unicode 6), so the list
    /// renders on the oldest device the api18 app runs on.
    /// Android 4.4 自己的字型畫得出的 emoji(約 Unicode 6),讓清單在 api18 app 最舊的裝置上也畫得出來。
    public static let defaultChoices: [String] = [
        "🅿", "🏪", "⛽", "☕", "🍜", "🍔", "🍕", "🍱", "🍣", "🍰", "🍺", "🏥", "💊", "🏦", "🏧",
        "🏨", "🏫", "🏬", "🏢", "⛪", "🚻", "🚗", "🚕", "🚌", "🚉", "✈", "⛺", "🌳", "🎬", "🎤", "👕", "💇", "🐶",
        "📮", "📚", "🔧", "⚡", "🔋", "⭐", "❤", "📍",
    ]

    /// Space-separated names per emoji, Chinese and English, for filtering.
    /// 每個 emoji 以空白分隔的名稱，中文與英文，供篩選。
    public static let defaultNames: [String: String] = [
        "🅿": "停車 停車場 車位 parking park", "🏪": "便利商店 超商 7-11 全家 萊爾富 store convenience shop",
        "⛽": "加油站 加油 油 gas fuel petrol station", "☕": "咖啡 咖啡廳 星巴克 coffee cafe",
        "🍜": "麵 拉麵 牛肉麵 noodle ramen", "🍔": "漢堡 速食 麥當勞 burger fast food", "🍕": "披薩 pizza",
        "🍱": "便當 餐廳 吃飯 bento lunch restaurant", "🍣": "壽司 日本料理 sushi japanese",
        "🍰": "蛋糕 甜點 麵包 cake dessert bakery", "🍺": "啤酒 酒吧 bar beer pub",
        "🏥": "醫院 診所 hospital clinic", "💊": "藥局 藥 pharmacy drug", "🏦": "銀行 bank", "🏧": "提款機 ATM",
        "🏨": "飯店 旅館 hotel", "🏫": "學校 school", "🏬": "百貨 商場 mall department",
        "🏢": "大樓 辦公 office building", "⛪": "教會 教堂 church", "🚻": "廁所 洗手間 toilet restroom",
        "🚗": "汽車 車 car", "🚕": "計程車 taxi", "🚌": "公車 巴士 bus", "🚉": "車站 火車 捷運 station train metro",
        "✈": "機場 飛機 airport plane", "⛺": "露營 camping", "🌳": "公園 樹 park tree",
        "🎬": "電影 戲院 movie cinema", "🎤": "KTV 唱歌 karaoke", "👕": "衣服 服飾 clothes",
        "💇": "美髮 理髮 hair salon", "🐶": "寵物 狗 pet dog", "📮": "郵局 郵筒 post office",
        "📚": "書店 圖書館 book library", "🔧": "修車 維修 汽車保養 repair garage",
        "⚡": "充電 電動車 charging ev", "🔋": "電池 充電站 battery charge", "⭐": "最愛 星 favourite star",
        "❤": "喜歡 love heart", "📍": "地點 place pin",
    ]

    /// The emoji a new row starts with. / 新一列的預設 emoji。
    public static let defaultEmoji = "📍"

    /// Whether `word` matches `emoji`'s names, case-insensitively, in either
    /// direction: the word inside the names ("park" in "parking"), or one of
    /// the names inside the word ("加油" in "中油加油站"). An empty word
    /// matches nothing. The api18 rule, unchanged.
    ///
    /// `word` 是否與 `emoji` 的名稱相符，不分大小寫、雙向：字詞在名稱之中(「park」在「parking」中)，或某個
    /// 名稱在字詞之中(「加油」在「中油加油站」中)。空字詞不符合任何東西。與 api18 的規則相同。
    public static func matches(
        _ emoji: String,
        _ word: String,
        names: [String: String] = defaultNames
    ) -> Bool {
        let word = word.lowercased()
        guard !word.isEmpty else { return false }
        let all = (names[emoji] ?? "").lowercased()
        if all.contains(word) { return true }
        return all.split(separator: " ").contains { !$0.isEmpty && word.contains($0) }
    }

    /// The choices to show, in order: those passing `filter` (all of them when
    /// it is empty or blank), the ones matching `keyword` first and marked,
    /// the rest after them, each group in catalogue order.
    ///
    /// 要顯示的選項及其順序:通過 `filter` 的(為空或只有空白時全部)，與 `keyword` 相符的排在最前面並標示，其餘
    /// 排在後面，各組內保持目錄順序。
    public static func choices(
        _ choices: [String] = defaultChoices,
        keyword: String,
        filter: String = "",
        names: [String: String] = defaultNames
    ) -> [EmojiChoice] {
        let filter = filter.trimmingWhitespace
        var first: [EmojiChoice] = []
        var rest: [EmojiChoice] = []
        for emoji in choices {
            if !filter.isEmpty && !matches(emoji, filter, names: names) { continue }
            if matches(emoji, keyword, names: names) {
                first.append(EmojiChoice(emoji: emoji, matchesKeyword: true))
            } else {
                rest.append(EmojiChoice(emoji: emoji, matchesKeyword: false))
            }
        }
        return first + rest
    }

    /// `emoji` as it should be drawn: a single character whose default is the
    /// text style (🅿 ✈ ❤ ⛪ ...) gets U+FE0F, the emoji presentation
    /// selector, so it is drawn in colour rather than in the text colour --
    /// which on a white cell in dark mode is white. Only for display; the
    /// stored value is left as it was (api18 keeps the bare characters,
    /// which Android 4.4's font draws).
    ///
    /// `emoji` 該如何繪製：預設為文字樣式的單一字元(🅿 ✈ ❤ ⛪ ...)加上 U+FE0F(emoji 呈現選擇符),讓它以彩色
    /// 繪製，而不是以文字顏色——深色模式下白色格子上的文字顏色是白色。只用於顯示;儲存的值保持原樣(api18 保留
    /// 不帶選擇符的字元，Android 4.4 的字型畫得出來)。
    public static func displayed(_ emoji: String) -> String {
        let scalars = emoji.unicodeScalars
        guard scalars.count == 1, let scalar = scalars.first,
            scalar.value > 0x7f,  // digits, # and * are "emoji" too, as keycap bases
            scalar.properties.isEmoji, !scalar.properties.isEmojiPresentation
        else { return emoji }
        return emoji + "\u{FE0F}"
    }

    /// What the picker's OK button chooses from the typed text: the text
    /// itself, trimmed, whether or not any name matches it -- so a user can
    /// type or paste an emoji the grid does not have. `nil` when blank.
    ///
    /// 選擇器的 OK 按鈕從輸入文字中選出的值：文字本身(去掉前後空白)，不論是否有名稱相符——讓使用者能輸入或
    /// 貼上格子裡沒有的 emoji。空白時為 `nil`。
    public static func typedChoice(_ text: String) -> String? {
        let text = text.trimmingWhitespace
        return text.isEmpty ? nil : text
    }
}

/// One cell of an ``EmojiPicker``. / ``EmojiPicker`` 的一格。
public struct EmojiChoice: Hashable, Sendable {
    public var emoji: String
    /// Matches the picker's keyword: shown first and highlighted.
    /// 與選擇器的關鍵字相符：排在前面並醒目標示。
    public var matchesKeyword: Bool

    public init(emoji: String, matchesKeyword: Bool) {
        self.emoji = emoji
        self.matchesKeyword = matchesKeyword
    }
}

/// The colours rows are given in turn, as `#rrggbb`.
/// 依序指派給各列的顏色，格式為 `#rrggbb`。
public enum EmojiKeywordPalette {
    public static let defaultColors: [String] = [
        "#1e88e5", "#43a047", "#e53935", "#8e24aa", "#fb8c00",
        "#00897b", "#6d4c41", "#3949ab", "#d81b60", "#7cb342",
    ]

    /// The colour for the row at `index`, cycling through `colors`.
    /// 第 `index` 列的顏色，在 `colors` 中循環。
    public static func color(at index: Int, colors: [String] = defaultColors) -> String {
        guard !colors.isEmpty else { return "#888888" }
        let count = colors.count
        return colors[((index % count) + count) % count]
    }

    /// Light purple behind a selected toggle or a matching picker cell.
    /// 已開啟的切換鈕，或相符的選擇器格子背後的淺紫色。
    public static let highlightFill = Color(hex: "#e1bee7")!
    /// The border around them. / 它們的邊框。
    public static let highlightBorder = Color(hex: "#8e24aa")!
}

extension Color {
    /// A colour from `#rgb`, `#rrggbb` or `#rrggbbaa` (the `#` optional);
    /// `nil` for anything else.
    /// 由 `#rgb`、`#rrggbb` 或 `#rrggbbaa`(`#` 可省略)建立顏色;其他格式為 `nil`。
    public init?(hex: String) {
        var digits = Substring(hex.trimmingWhitespace)
        if digits.hasPrefix("#") { digits = digits.dropFirst() }
        guard digits.allSatisfy(\.isHexDigit) else { return nil }
        var text = String(digits)
        if text.count == 3 {
            text = text.map { "\($0)\($0)" }.joined()
        }
        guard text.count == 6 || text.count == 8, let value = UInt64(text, radix: 16) else {
            return nil
        }
        let hasAlpha = text.count == 8
        let rgb = hasAlpha ? value >> 8 : value
        let alpha = hasAlpha ? Double(value & 0xff) / 255 : 1
        self.init(
            red: Double((rgb >> 16) & 0xff) / 255,
            green: Double((rgb >> 8) & 0xff) / 255,
            blue: Double(rgb & 0xff) / 255,
            opacity: alpha
        )
    }
}

/// One row of an ``EmojiKeywordList``: a keyword, its emoji, its colour and
/// whether it is switched on. Identified by its keyword, which the list keeps
/// unique.
///
/// ``EmojiKeywordList`` 的一列：關鍵字、它的 emoji、它的顏色，以及是否開啟。以關鍵字識別，清單會讓它保持唯一。
public struct EmojiKeywordItem: Identifiable, Hashable, Sendable {
    public var keyword: String
    public var emoji: String
    /// `#rrggbb`, so a row can be stored as text. / `#rrggbb`,讓一列能以文字儲存。
    public var color: String
    public var isOn: Bool

    public var id: String { keyword }

    public init(
        keyword: String,
        emoji: String = EmojiCatalog.defaultEmoji,
        color: String,
        isOn: Bool = true
    ) {
        self.keyword = keyword
        self.emoji = emoji
        self.color = color
        self.isOn = isOn
    }

    /// The colour as a ``Color``; grey when it does not parse.
    /// 顏色的 ``Color``;無法解析時為灰色。
    public var resolvedColor: Color {
        Color(hex: color) ?? .gray
    }

    /// The row as the api18 app stores it: keyword, emoji, colour, `1`/`0`.
    /// 以 api18 app 的方式儲存的一列：關鍵字、emoji、顏色、`1`/`0`。
    public var fields: [String] {
        [keyword, emoji, color, isOn ? "1" : "0"]
    }

    /// A row read back; missing fields take the api18 defaults (📍, the
    /// palette colour for `index`, on). `nil` without a keyword.
    /// 讀回的一列;缺少的欄位採 api18 的預設值(📍、第 `index` 個調色盤顏色、開啟)。沒有關鍵字時為 `nil`。
    public init?(fields: [String], index: Int, palette: [String] = EmojiKeywordPalette.defaultColors) {
        guard let keyword = fields.first, !keyword.isEmpty else { return nil }
        func field(_ n: Int) -> String? {
            n < fields.count && !fields[n].isEmpty ? fields[n] : nil
        }
        self.init(
            keyword: keyword,
            emoji: field(1) ?? EmojiCatalog.defaultEmoji,
            color: field(2) ?? EmojiKeywordPalette.color(at: index, colors: palette),
            isOn: fields.count > 3 ? fields[3] != "0" : true
        )
    }

    /// `items` with a new row for `keyword` appended -- trimmed, 📍, the next
    /// palette colour, on -- or `nil` when the keyword is blank or already
    /// there. The api18 Add button.
    /// 在 `items` 後面加上 `keyword` 的新一列(去掉前後空白、📍、下一個調色盤顏色、開啟);關鍵字為空白或已存在
    /// 時為 `nil`。即 api18 的「新增」按鈕。
    public static func adding(
        _ keyword: String,
        to items: [EmojiKeywordItem],
        palette: [String] = EmojiKeywordPalette.defaultColors
    ) -> [EmojiKeywordItem]? {
        let keyword = keyword.trimmingWhitespace
        guard !keyword.isEmpty, !items.contains(where: { $0.keyword == keyword }) else {
            return nil
        }
        let item = EmojiKeywordItem(
            keyword: keyword,
            color: EmojiKeywordPalette.color(at: items.count, colors: palette)
        )
        return items + [item]
    }

    /// The rows as CSV text (RFC 4180: fields with a comma, quote or line
    /// break are quoted, quotes doubled), LF line endings, no header -- the
    /// api18 app's interested.csv.
    /// 以 CSV 文字表示各列(RFC 4180:含逗號、引號或換行的欄位加引號，引號重複一次),LF 換行，沒有標題列——即
    /// api18 app 的 interested.csv。
    public static func csv(_ items: [EmojiKeywordItem]) -> String {
        items.map { item in
            item.fields.map(EmojiKeywordCSV.quoted).joined(separator: ",") + "\n"
        }.joined()
    }

    /// Rows read from CSV text written by ``csv(_:)`` or by hand; rows
    /// without a keyword are skipped.
    /// 從 ``csv(_:)`` 或手寫的 CSV 文字讀出各列;沒有關鍵字的列會略過。
    public static func items(
        fromCSV text: String,
        palette: [String] = EmojiKeywordPalette.defaultColors
    ) -> [EmojiKeywordItem] {
        var items: [EmojiKeywordItem] = []
        for fields in EmojiKeywordCSV.records(text) {
            if let item = EmojiKeywordItem(fields: fields, index: items.count, palette: palette) {
                items.append(item)
            }
        }
        return items
    }
}

/// The row type the api18 app calls it. / api18 app 對這個列型別的稱呼。
public typealias InterestedItem = EmojiKeywordItem

/// A small RFC 4180 reader and writer for ``EmojiKeywordItem``'s rows: a comma
/// inside quotes is data, which a split on "," would get wrong.
/// 供 ``EmojiKeywordItem`` 各列使用的小型 RFC 4180 讀寫器：引號內的逗號是資料，以 "," 切割會出錯。
enum EmojiKeywordCSV {
    static func quoted(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func records(_ text: String) -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var inQuotes = false
        var fieldStarted = false
        var iterator = Array(text).makeIterator()
        var pending: Character? = nil
        func next() -> Character? {
            if let character = pending {
                pending = nil
                return character
            }
            return iterator.next()
        }
        func endRecord() {
            record.append(field)
            if !(record.count == 1 && record[0].isEmpty) { records.append(record) }
            record = []
            field = ""
            fieldStarted = false
        }
        while let character = next() {
            if inQuotes {
                if character == "\"" {
                    if let after = next() {
                        if after == "\"" {
                            field.append("\"")
                        } else {
                            inQuotes = false
                            pending = after
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
                continue
            }
            switch character {
                case "\"" where !fieldStarted:
                    inQuotes = true
                    fieldStarted = true
                case ",":
                    record.append(field)
                    field = ""
                    fieldStarted = false
                case "\n", "\r\n":
                    endRecord()
                case "\r":
                    endRecord()
                default:
                    field.append(character)
                    fieldStarted = true
            }
        }
        if fieldStarted || !field.isEmpty || !record.isEmpty { endRecord() }
        return records
    }
}

extension String {
    /// Without leading and trailing spaces, tabs and line breaks (Foundation-free).
    /// 去掉前後的空白、tab 與換行(不依賴 Foundation)。
    var trimmingWhitespace: String {
        var view = Substring(self)
        while let first = view.first, first.isWhitespace { view = view.dropFirst() }
        while let last = view.last, last.isWhitespace { view = view.dropLast() }
        return String(view)
    }
}
