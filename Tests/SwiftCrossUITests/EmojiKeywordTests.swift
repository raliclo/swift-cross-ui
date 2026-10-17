import DummyBackend
import Testing

@testable @_spi(Backends) import SwiftCrossUI

/// The logic behind EmojiPicker, EmojiToggleButton and EmojiKeywordList,
/// without a backend: matching, ordering, the typed choice, the palette, Add,
/// and the CSV rows. / EmojiPicker、EmojiToggleButton 與 EmojiKeywordList 背後的邏輯，不需要 backend。
@Suite("Emoji keyword list")
struct EmojiKeywordTests {
    @Test("a word matches inside the names, both scripts, any case")
    func matchesInsideNames() {
        #expect(EmojiCatalog.matches("🅿", "停車"))
        #expect(EmojiCatalog.matches("🅿", "PARK"))
        #expect(EmojiCatalog.matches("⛽", "petrol"))
        #expect(EmojiCatalog.matches("🏧", "atm"))
        #expect(!EmojiCatalog.matches("🅿", "coffee"))
    }

    @Test("a name inside the word matches too: 加油 in 中油加油站")
    func nameInsideWord() {
        #expect(EmojiCatalog.matches("⛽", "中油加油站"))
        #expect(EmojiCatalog.matches("☕", "星巴克咖啡"))
    }

    @Test("an empty word, or an emoji with no names, matches nothing")
    func emptyMatchesNothing() {
        #expect(!EmojiCatalog.matches("🅿", ""))
        #expect(!EmojiCatalog.matches("🦄", "unicorn"))
    }

    @Test("every default choice has names, and no name is attached to a missing choice")
    func tablesAgree() {
        #expect(Set(EmojiCatalog.defaultChoices) == Set(EmojiCatalog.defaultNames.keys))
        #expect(EmojiCatalog.defaultChoices.count == 41)
    }

    @Test("keyword matches first and marked, the rest after, catalogue order kept")
    func ordering() {
        let shown = EmojiCatalog.choices(keyword: "停車場")
        #expect(shown.count == EmojiCatalog.defaultChoices.count)
        #expect(shown.first == EmojiChoice(emoji: "🅿", matchesKeyword: true))
        // 🚗 too: its name 車 is inside 停車場 -- the two-way rule of api18.
        #expect(shown.filter(\.matchesKeyword).map(\.emoji) == ["🅿", "🚗"])
        #expect(shown.dropFirst(2).map(\.emoji) == EmojiCatalog.defaultChoices.filter { $0 != "🅿" && $0 != "🚗" })
    }

    @Test("a keyword matching several: all of them first, in catalogue order")
    func severalFirst() {
        // "park" is in 🅿's names (parking park) and 🌳's (park tree).
        let shown = EmojiCatalog.choices(keyword: "park")
        #expect(shown.prefix(2).map(\.emoji) == ["🅿", "🌳"])
        #expect(shown.prefix(2).allSatisfy { $0.matchesKeyword })
        #expect(!shown[2].matchesKeyword)
    }

    @Test("the filter narrows the grid; the keyword still orders what is left")
    func filtering() {
        let shown = EmojiCatalog.choices(keyword: "公園", filter: "  park ")
        #expect(shown.map(\.emoji) == ["🌳", "🅿"])
        #expect(shown[0].matchesKeyword)
        #expect(!shown[1].matchesKeyword)
        #expect(EmojiCatalog.choices(keyword: "", filter: "銀行").map(\.emoji) == ["🏦"])
        #expect(EmojiCatalog.choices(keyword: "", filter: "zzz").isEmpty)
        #expect(EmojiCatalog.choices(keyword: "", filter: "   ").count == EmojiCatalog.defaultChoices.count)
    }

    @Test("custom choices and names are honoured")
    func customTables() {
        let shown = EmojiCatalog.choices(
            ["A", "B"],
            keyword: "bee",
            names: ["A": "apple", "B": "bee"]
        )
        #expect(shown.map(\.emoji) == ["B", "A"])
    }

    @Test("OK takes whatever was typed, trimmed, even with no name matching")
    func typedChoice() {
        #expect(EmojiCatalog.typedChoice(" 🦄 ") == "🦄")
        #expect(EmojiCatalog.typedChoice("zzz") == "zzz")
        #expect(EmojiCatalog.typedChoice("  ") == nil)
    }

    @Test("display: text-style single characters get U+FE0F, others are left alone")
    func displayed() {
        #expect(EmojiCatalog.displayed("🅿") == "🅿\u{FE0F}")
        #expect(EmojiCatalog.displayed("❤") == "❤\u{FE0F}")
        #expect(EmojiCatalog.displayed("☕") == "☕")
        #expect(EmojiCatalog.displayed("📍") == "📍")
        #expect(EmojiCatalog.displayed("❤\u{FE0F}") == "❤\u{FE0F}")
        #expect(EmojiCatalog.displayed("abc") == "abc")
        #expect(EmojiCatalog.displayed("1") == "1")
    }

    @Test("the palette cycles, negatives included, and an empty one is grey")
    func palette() {
        let colors = EmojiKeywordPalette.defaultColors
        #expect(colors.count == 10)
        #expect(EmojiKeywordPalette.color(at: 0) == "#1e88e5")
        #expect(EmojiKeywordPalette.color(at: 10) == "#1e88e5")
        #expect(EmojiKeywordPalette.color(at: 13) == colors[3])
        #expect(EmojiKeywordPalette.color(at: -1) == colors[9])
        #expect(EmojiKeywordPalette.color(at: 4, colors: []) == "#888888")
    }

    @Test("hex colours: #rgb, #rrggbb, #rrggbbaa, and garbage")
    func hex() {
        #expect(Color(hex: "#e1bee7") == Color(red: 225 / 255, green: 190 / 255, blue: 231 / 255))
        #expect(Color(hex: "fff") == Color(red: 1, green: 1, blue: 1))
        #expect(Color(hex: "#00000080") == Color(red: 0, green: 0, blue: 0, opacity: 128 / 255))
        #expect(Color(hex: "#12345") == nil)
        #expect(Color(hex: "#gggggg") == nil)
        #expect(Color(hex: "") == nil)
    }

    @Test("Add: trimmed, 📍, next palette colour, on; blank and duplicate refused")
    func adding() throws {
        var items: [EmojiKeywordItem] = []
        items = try #require(EmojiKeywordItem.adding("  停車場 ", to: items))
        items = try #require(EmojiKeywordItem.adding("便利商店", to: items))
        #expect(items.map(\.keyword) == ["停車場", "便利商店"])
        #expect(items.map(\.color) == ["#1e88e5", "#43a047"])
        #expect(items.allSatisfy { $0.emoji == "📍" && $0.isOn })
        #expect(EmojiKeywordItem.adding("停車場", to: items) == nil)
        #expect(EmojiKeywordItem.adding(" ", to: items) == nil)
        // After a deletion the colour follows the count, as in api18.
        items.removeFirst()
        let again = try #require(EmojiKeywordItem.adding("加油站", to: items))
        #expect(again.last?.color == "#43a047")
    }

    @Test("fields: api18's row, and defaults for what is missing")
    func fields() {
        let item = EmojiKeywordItem(keyword: "加油站", emoji: "⛽", color: "#e53935", isOn: false)
        #expect(item.fields == ["加油站", "⛽", "#e53935", "0"])
        #expect(EmojiKeywordItem(fields: item.fields, index: 0) == item)
        let bare = EmojiKeywordItem(fields: ["咖啡"], index: 3)
        #expect(bare == EmojiKeywordItem(keyword: "咖啡", emoji: "📍", color: "#8e24aa", isOn: true))
        #expect(EmojiKeywordItem(fields: ["", "x"], index: 0) == nil)
        #expect(EmojiKeywordItem(fields: [], index: 0) == nil)
    }

    @Test("CSV round trip, with a comma, a quote and a line break in keywords")
    func csvRoundTrip() {
        let items = [
            EmojiKeywordItem(keyword: "停車場", emoji: "🅿", color: "#1e88e5"),
            EmojiKeywordItem(keyword: "fork raliclo/busybox, branch develop", color: "#43a047", isOn: false),
            EmojiKeywordItem(keyword: "say \"hi\"", emoji: "❤", color: "#e53935"),
            EmojiKeywordItem(keyword: "two\nlines", emoji: "⭐", color: "#8e24aa"),
        ]
        let text = EmojiKeywordItem.csv(items)
        #expect(text.hasPrefix("停車場,🅿,#1e88e5,1\n"))
        #expect(text.contains("\"fork raliclo/busybox, branch develop\",📍,#43a047,0\n"))
        #expect(text.contains("\"say \"\"hi\"\"\""))
        #expect(EmojiKeywordItem.items(fromCSV: text) == items)
    }

    @Test("CSV read: CRLF, blank lines, short rows, no final newline")
    func csvRead() {
        let text = "停車場,🅿,#1e88e5,1\r\n\r\n便利商店\r\n,skipped,#000000,1\n加油站,⛽,,0"
        let items = EmojiKeywordItem.items(fromCSV: text)
        #expect(items.map(\.keyword) == ["停車場", "便利商店", "加油站"])
        #expect(items[1].color == "#43a047")
        #expect(items[1].emoji == "📍")
        #expect(items[2].color == "#e53935")
        #expect(!items[2].isOn)
        #expect(EmojiKeywordItem.items(fromCSV: "").isEmpty)
    }

    @Test("the five shipped backends' feature is a TapGestures refinement")
    @MainActor
    func protocolShape() {
        // DummyBackend is outside the shipped five and does not conform, so
        // the modifier falls back to the tap; the shipped five are checked
        // by compiling their conformances.
        let backend: Any = DummyBackend()
        #expect(!(backend is any BackendFeatures.TapAndLongPressGestures))
    }
}
