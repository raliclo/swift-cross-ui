import Foundation
@_spi(Backends) import SwiftCrossUI
import WinUI

// Date and time wheels drawn from Foundation, not by WinUI's DatePicker and
// TimePicker. Those two format with the app's languages only: on P90
// (2026-10-20) `.environment(\.locale, zh_TW)` still drew "August 24 2025 /
// 9 46 AM", and setting `FrameworkElement.Language` to zh-TW -- on the live
// controls, and on fresh ones before they loaded -- changed nothing. So the
// month names, the column order and the AM/PM words come from the calendar's
// locale here, the shape GtkBackend's DateWheel and TimeRow already have.
//
// 以 Foundation 畫出的日期與時間滾輪，取代 WinUI 的 DatePicker 與 TimePicker。那兩者只依 app 的語言格式化：
// P90(2026-10-20)在 `.environment(\.locale, zh_TW)` 下仍畫出「August 24 2025 / 9 46 AM」,而把
// `FrameworkElement.Language` 設成 zh-TW——不論是已上畫面的控制項，還是載入前新建的——都毫無變化。因此月份名稱、
// 欄位順序與上午/下午的字樣在此取自 calendar 的 locale,與 GtkBackend 的 DateWheel、TimeRow 同一個形狀。

/// Year, month and day as three `WheelPicker` columns, in the order the
/// locale writes a date.
///
/// The order is read from `DateFormatter.dateFormat(fromTemplate: "yMMMMd")`:
/// zh_TW gives y M d, en_US M d y, de_DE d M y. The month column shows
/// `calendar.monthSymbols`, the same names GtkBackend's wheel shows.
///
/// 年、月、日三個 `WheelPicker` 欄位，依 locale 書寫日期的順序排列。順序取自
/// `DateFormatter.dateFormat(fromTemplate: "yMMMMd")`:zh_TW 為 y M d,en_US 為 M d y,de_DE 為 d M y。
/// 月份欄顯示 `calendar.monthSymbols`,與 GtkBackend 的滾輪相同。
final class LocaleDateWheel: WinUI.StackPanel {
    var onChange: ((_ year: Int, _ month: Int, _ day: Int) -> Void)?

    let yearColumn = WheelPicker()
    let monthColumn = WheelPicker()
    let dayColumn = WheelPicker()

    private var calendar = Calendar.current
    private var years: ClosedRange<Int> = 0...0
    private var order: [Character] = []
    private var environment: EnvironmentValues?

    override init() {
        super.init()
        orientation = .horizontal
        spacing = 4
        for column in columns {
            // Selection events arrive on the UI thread, as every WinUI event does.
            // 選取事件和每個 WinUI 事件一樣，都在 UI 執行緒上送達。
            column.onChangeSelection = { [weak self] _ in
                guard let self else { return }
                nonisolated(unsafe) let wheel = self
                MainActor.assumeIsolated { wheel.picked() }
            }
            // `scrollIntoView` before the list is laid out does nothing, and a
            // wheel gets its first selection before it is laid out, so it
            // showed 1925 and January at the top with 2025 / August selected
            // out of sight (P90 on WinUI, 2026-10-20). Scroll again once loaded.
            // 清單排版前的 `scrollIntoView` 沒有作用，而滾輪第一次被設定選取時還沒排版，所以頂端停在
            // 1925 與一月，選中的 2025/八月看不到(P90,WinUI,2026-10-20)。載入後再捲一次。
            column.loaded.addHandler { [weak column] _, _ in
                guard let column, column.selectedIndex >= 0 else { return }
                column.setSelectedIndex(to: Int(column.selectedIndex))
            }
        }
    }

    var columns: [WheelPicker] { [yearColumn, monthColumn, dayColumn] }

    /// Fills the year and month columns and orders the three. Cheap to repeat:
    /// `WheelPicker.update` rebuilds rows only when the options change.
    /// 填入年與月兩欄並排定三欄順序。重複呼叫不貴:`WheelPicker.update` 只在選項改變時重建各列。
    @MainActor func configure(calendar: Calendar, years: ClosedRange<Int>, environment: EnvironmentValues) {
        self.calendar = calendar
        self.years = years
        self.environment = environment
        yearColumn.update(options: years.map { String($0) }, environment: environment)
        monthColumn.update(options: calendar.monthSymbols, environment: environment)

        let order = Self.order(for: calendar.locale ?? .current)
        if order != self.order {
            self.order = order
            children.clear()
            for field in order {
                switch field {
                    case "y": children.append(yearColumn)
                    case "M": children.append(monthColumn)
                    default: children.append(dayColumn)
                }
            }
        }
    }

    /// Shows a date without reporting it back.
    /// 顯示一個日期，不回報。
    @MainActor func show(year: Int, month: Int, day: Int) {
        updateDays(year: year, month: month)
        yearColumn.setSelectedIndex(to: years.contains(year) ? year - years.lowerBound : nil)
        monthColumn.setSelectedIndex(to: month - 1)
        dayColumn.setSelectedIndex(to: day - 1)
    }

    func setEnabled(_ isEnabled: Bool) {
        for column in columns {
            column.isEnabled = isEnabled
        }
    }

    @MainActor func naturalSize() -> SIMD2<Int> {
        let sizes = columns.map { $0.naturalSize() }
        return SIMD2(
            sizes.map(\.x).reduce(0, +) + Int(spacing) * (sizes.count - 1),
            sizes.map(\.y).max() ?? 0
        )
    }

    /// The fields of `yMMMMd` in the order the locale's pattern writes them,
    /// skipping quoted literals; any field the pattern lacks goes last.
    /// `yMMMMd` 各欄位在該 locale 樣式中出現的順序，略過引號內的字面文字；樣式裡沒有的欄位排在最後。
    static func order(for locale: Locale) -> [Character] {
        let pattern =
            DateFormatter.dateFormat(fromTemplate: "yMMMMd", options: 0, locale: locale) ?? "yMd"
        var order: [Character] = []
        var inQuote = false
        for character in pattern {
            if character == "'" {
                inQuote.toggle()
                continue
            }
            guard !inQuote else { continue }
            let field: Character? =
                switch character {
                    case "y", "Y", "u", "r": "y"
                    case "M", "L": "M"
                    case "d": "d"
                    default: nil
                }
            if let field, !order.contains(field) {
                order.append(field)
            }
        }
        for field: Character in ["y", "M", "d"] where !order.contains(field) {
            order.append(field)
        }
        return order
    }

    private func dayCount(year: Int, month: Int) -> Int {
        guard
            let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
            let days = calendar.range(of: .day, in: .month, for: first)
        else { return 31 }
        return days.count
    }

    @MainActor private func updateDays(year: Int, month: Int) {
        guard let environment else { return }
        let count = dayCount(year: year, month: month)
        dayColumn.update(options: (1...count).map { String($0) }, environment: environment)
    }

    private func index(of column: WheelPicker) -> Int? {
        column.selectedIndex < 0 ? nil : Int(column.selectedIndex)
    }

    @MainActor private func picked() {
        guard
            let yearIndex = index(of: yearColumn),
            let monthIndex = index(of: monthColumn),
            let dayIndex = index(of: dayColumn)
        else { return }
        let year = years.lowerBound + yearIndex
        let month = monthIndex + 1
        updateDays(year: year, month: month)
        // The 31st of a month with 30 days becomes the 30th, as GtkBackend's wheel does.
        // 30 天的月份裡選到 31 日時改為 30 日，與 GtkBackend 的滾輪相同。
        let day = min(dayIndex + 1, dayColumn.options.count)
        if day != dayIndex + 1 {
            dayColumn.setSelectedIndex(to: day - 1)
        }
        onChange?(year, month, day)
    }
}

/// Hour, minute, optionally second, and AM/PM where the locale uses a
/// 12-hour clock -- in the order the locale's `jm` pattern writes them, with
/// the AM/PM words from `calendar.amSymbol` and `pmSymbol` (上午/下午 in zh_TW).
///
/// ComboBoxes, as the seconds selector beside WinUI's TimePicker already was.
///
/// 時、分、可選的秒，以及 locale 使用 12 小時制時的上午/下午——依 locale 的 `jm` 樣式排列，上午/下午的字樣取自
/// `calendar.amSymbol` 與 `pmSymbol`(zh_TW 為上午/下午)。使用 ComboBox,與原本放在 WinUI TimePicker 旁的
/// 秒數選擇器相同。
final class LocaleTimeRow: WinUI.StackPanel {
    var onChange: ((_ hour: Int, _ minute: Int, _ second: Int?) -> Void)?

    private(set) var showsSeconds = false
    private let hourBox = WinUI.ComboBox()
    private let minuteBox = WinUI.ComboBox()
    private let secondBox = WinUI.ComboBox()
    private let meridiemBox = WinUI.ComboBox()
    private(set) var separators: [WinUI.TextBlock] = []
    private var isTwelveHour = false
    private var configuredKey: String?
    private var isApplying = false

    /// Wide enough for "00" plus the drop-down chevron.
    /// 足以容納「00」加上下拉箭頭的寬度。
    static let fieldWidth = 72.0
    /// A ComboBox's height at the default font. Fixed rather than measured:
    /// measuring a ComboBox with 60 items returns its item list's height (P41,
    /// 2026-09-17: a 2757 px window).
    /// 預設字型下 ComboBox 的高度。用固定值而不量測：量一個有 60 項的 ComboBox 會得到它項目清單的高度
    /// (P41,2026-09-17:視窗被撐到 2757 px)。
    static let rowHeight = 32
    static let separatorWidth = 8

    override init() {
        super.init()
        orientation = .horizontal
        spacing = 4
        for box in [hourBox, minuteBox, secondBox, meridiemBox] {
            box.width = Self.fieldWidth
            box.verticalAlignment = .center
            box.selectionChanged.addHandler { [weak self] _, _ in self?.changed() }
        }
        for value in 0..<60 {
            minuteBox.items.append(String(format: "%02d", value))
            secondBox.items.append(String(format: "%02d", value))
        }
    }

    /// The boxes on screen, for enabling and colouring.
    /// 畫面上的各個框，供啟用與上色使用。
    var boxes: [WinUI.ComboBox] {
        children.compactMap { $0 as? WinUI.ComboBox }
    }

    func configure(calendar: Calendar, showsSeconds: Bool) {
        let locale = calendar.locale ?? .current
        let key = "\(locale.identifier)|\(showsSeconds)|\(calendar.amSymbol)|\(calendar.pmSymbol)"
        guard key != configuredKey else { return }
        configuredKey = key
        self.showsSeconds = showsSeconds

        isApplying = true
        defer { isApplying = false }

        let pattern = Self.unquoted(
            DateFormatter.dateFormat(fromTemplate: "jm", options: 0, locale: locale) ?? "HH:mm"
        )
        isTwelveHour = pattern.contains("h") || pattern.contains("K")
        let hourPosition = pattern.firstIndex { "hHkK".contains($0) }
        let meridiemPosition = pattern.firstIndex { "abB".contains($0) }
        let meridiemFirst =
            if let hourPosition, let meridiemPosition { meridiemPosition < hourPosition } else { false }

        hourBox.items.clear()
        for hour in isTwelveHour ? Array(1...12) : Array(0...23) {
            hourBox.items.append(String(format: "%02d", hour))
        }
        meridiemBox.items.clear()
        meridiemBox.items.append(calendar.amSymbol)
        meridiemBox.items.append(calendar.pmSymbol)
        meridiemBox.width = Self.meridiemWidth(calendar.amSymbol, calendar.pmSymbol)

        children.clear()
        separators = []
        if isTwelveHour && meridiemFirst { children.append(meridiemBox) }
        children.append(hourBox)
        children.append(separator())
        children.append(minuteBox)
        if showsSeconds {
            children.append(separator())
            children.append(secondBox)
        }
        if isTwelveHour && !meridiemFirst { children.append(meridiemBox) }
    }

    /// Shows a 24-hour time without reporting it back.
    /// 顯示一個 24 小時制的時間，不回報。
    func show(hour: Int, minute: Int, second: Int) {
        isApplying = true
        defer { isApplying = false }
        hourBox.selectedIndex = Int32(isTwelveHour ? (hour + 11) % 12 : hour)
        minuteBox.selectedIndex = Int32(minute)
        secondBox.selectedIndex = Int32(second)
        meridiemBox.selectedIndex = hour < 12 ? 0 : 1
    }

    func setEnabled(_ isEnabled: Bool) {
        for box in [hourBox, minuteBox, secondBox, meridiemBox] {
            box.isEnabled = isEnabled
        }
    }

    func naturalSize() -> SIMD2<Int> {
        var width = 0
        for child in children {
            if let box = child as? WinUI.ComboBox {
                width += Int(box.width.rounded(.up))
            } else {
                width += Self.separatorWidth
            }
        }
        width += Int(spacing) * max(Int(children.size) - 1, 0)
        return SIMD2(width, Self.rowHeight)
    }

    private func changed() {
        guard !isApplying else { return }
        let hourIndex = Int(hourBox.selectedIndex)
        let minute = Int(minuteBox.selectedIndex)
        // -1 is WinUI's transient "no selection" while a list opens.
        // -1 是清單開啟時 WinUI 暫時性的「無選取」。
        guard hourIndex >= 0, minute >= 0 else { return }
        var hour = hourIndex
        if isTwelveHour {
            let isPM = meridiemBox.selectedIndex == 1
            hour = (hourIndex + 1) % 12 + (isPM ? 12 : 0)
        }
        var second: Int? = nil
        if showsSeconds {
            let index = Int(secondBox.selectedIndex)
            guard index >= 0 else { return }
            second = index
        }
        onChange?(hour, minute, second)
    }

    private func separator() -> WinUI.TextBlock {
        let text = WinUI.TextBlock()
        text.text = ":"
        text.verticalAlignment = .center
        text.width = Double(Self.separatorWidth)
        text.textAlignment = .center
        separators.append(text)
        return text
    }

    /// The pattern with quoted literals removed, so a quoted letter is not read as a field.
    /// 去掉引號內字面文字的樣式，以免引號裡的字母被當成欄位。
    private static func unquoted(_ pattern: String) -> String {
        var result = ""
        var inQuote = false
        for character in pattern {
            if character == "'" {
                inQuote.toggle()
            } else if !inQuote {
                result.append(character)
            }
        }
        return result
    }

    /// A width for the longer of the two words: about 8 px a Latin letter and
    /// 15 px a CJK character at the default font, plus the chevron and padding.
    /// 兩個字樣中較長者所需的寬度：預設字型下拉丁字母約 8 px、CJK 字約 15 px,再加上下拉箭頭與內距。
    private static func meridiemWidth(_ words: String...) -> Double {
        let widest =
            words.map { word in
                word.unicodeScalars.reduce(0.0) { $0 + ($1.value >= 0x2E80 ? 15 : 8) }
            }.max() ?? 0
        return max(fieldWidth, widest + 52)
    }
}
