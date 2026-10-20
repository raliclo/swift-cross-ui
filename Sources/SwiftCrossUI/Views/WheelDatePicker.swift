import Foundation

// `.datePickerStyle(.wheel)` on every backend. UIKitBackend, WinUIBackend and
// AndroidBackend (on API levels with the spinner) draw their own wheel; the
// others -- AppKit has no wheel control and GTK 4 has no spinning widget of any
// kind -- draw this one, built from SwiftCrossUI views, so the style is the same
// everywhere it is asked for rather than "unavailable on macOS" (P90 on AppKit
// and GTK until 2026-10-18).
//
// What a wheel shows follows UIDatePicker, which P90 compares against: one
// column per field, in the order the region writes a date (August | 24 | 2025
// in en_US, 24 | August | 2025 in en_GB, 2025年 | 8月 | 24日 in zh_TW), the
// region's calendar (Buddhist years in th_TH), 12 or 24 hours as the region
// writes a time, and AM/PM before or after the hours where the region puts it.
// Each column shows the chosen value in a band with two neighbours either side;
// the scroll wheel or a drag turns it, and a click on a neighbour chooses it.
//
// 每個 backend 上的 `.datePickerStyle(.wheel)`。UIKitBackend、WinUIBackend 與 AndroidBackend(在有 spinner 的 API
// 層級)畫它們自己的滾輪;其他的——AppKit 沒有滾輪控制項,GTK 4 根本沒有會轉的 widget——畫這一個，以 SwiftCrossUI
// 的 view 組成，讓這個樣式在每個要求它的地方都一樣，而不是「macOS 上不可用」(P90 在 AppKit 與 GTK 上，直到 2026-10-18)。
// 滾輪顯示什麼跟隨 UIDatePicker(P90 拿它比對):每個欄位一欄，依地區書寫日期的順序排列，用地區的曆法(th_TH 為佛曆),
// 依地區寫時間的方式用 12 或 24 小時，上午/下午放在地區放的那一側。每欄把選中的值放在一條帶子裡，上下各兩個鄰居;
// 滾輪或拖曳轉動它，點鄰居就選中它。

/// The wheel date picker's view: the backend's own wheel where it has one,
/// otherwise ``_SwiftWheelDatePicker``.
/// 滾輪日期選擇器的 view:backend 有自己的滾輪就用它，否則用 ``_SwiftWheelDatePicker``。
@available(tvOS, unavailable)
public struct _WheelDatePickerImplementation: View {
    var selection: Binding<Date>
    var range: ClosedRange<Date>
    var components: DatePickerComponents
    var nativeWheel: Bool

    public var body: some View {
        #if os(macOS)
            _SwiftWheelDatePicker(selection: selection, range: range, components: components)
        #else
            if nativeWheel {
                _BuiltinDatePickerImplementation(
                    style: .wheel,
                    selection: selection,
                    range: range,
                    components: components
                )
            } else {
                _SwiftWheelDatePicker(selection: selection, range: range, components: components)
            }
        #endif
    }
}

/// One wheel column: its labels, which one is chosen, and whether it wraps.
/// 一個滾輪欄：它的標籤、選中哪一個，以及是否循環。
struct WheelColumnModel {
    var id: String
    var labels: [String]
    var selected: Int
    var cyclic: Bool
    var select: (Int) -> Void
}

/// The wheel drawn in SwiftCrossUI views, for backends without one of their own.
/// 以 SwiftCrossUI view 畫的滾輪，給沒有自己滾輪的 backend 用。
@available(tvOS, unavailable)
public struct _SwiftWheelDatePicker: View {
    var selection: Binding<Date>
    var range: ClosedRange<Date>
    var components: DatePickerComponents
    @Environment(\.locale) private var locale

    public var body: some View {
        let columns = Self.columns(
            for: selection.wrappedValue,
            components: components,
            locale: locale,
            range: range,
            set: { selection.wrappedValue = $0 }
        )
        return HStack(spacing: 4) {
            ForEach(columns.indices, id: \.self) { index in
                _WheelColumn(model: columns[index])
            }
        }
    }

    /// The fields a region writes, in its order. Pure, so the order is tested
    /// without a backend.
    /// 地區書寫的欄位，依它的順序。純函式，因此不需要 backend 就能測試順序。
    nonisolated static func fieldOrder(pattern: String, fields: [Character: String]) -> [String] {
        var order: [String] = []
        var quoted = false
        for character in pattern {
            if character == "'" {
                quoted.toggle()
                continue
            }
            guard !quoted, let field = fields[character], !order.contains(field) else { continue }
            order.append(field)
        }
        return order
    }

    static func columns(
        for date: Date,
        components: DatePickerComponents,
        locale: Locale,
        range: ClosedRange<Date>,
        set: @escaping (Date) -> Void
    ) -> [WheelColumnModel] {
        var calendar = locale.calendar
        calendar.locale = locale
        calendar.timeZone = TimeZone.current
        func formatter(_ template: String) -> DateFormatter {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.setLocalizedDateFormatFromTemplate(template)
            return formatter
        }
        let parts = calendar.dateComponents([.era, .year, .month, .day, .hour, .minute], from: date)

        /// Moves one field and lands inside the range, the day kept inside its month.
        /// 移動一個欄位並落在範圍之內，日期保持在它的月份之內。
        func change(_ edit: (inout DateComponents) -> Void) {
            var next = parts
            edit(&next)
            if let day = next.day,
                let firstOfMonth = calendar.date(
                    from: DateComponents(era: next.era, year: next.year, month: next.month, day: 1)
                ),
                let days = calendar.range(of: .day, in: .month, for: firstOfMonth)?.count
            {
                next.day = min(day, days)
            }
            guard let moved = calendar.date(from: next) else { return }
            set(min(max(moved, range.lowerBound), range.upperBound))
        }

        var columns: [WheelColumnModel] = []

        if components.contains(.date) {
            let pattern = DateFormatter.dateFormat(fromTemplate: "yMMMMd", options: 0, locale: locale)
                ?? "MMMM d y"
            let order = fieldOrder(
                pattern: pattern,
                fields: ["y": "year", "M": "month", "L": "month", "d": "day"]
            )
            let year = parts.year ?? 2000
            let month = parts.month ?? 1
            for field in order {
                switch field {
                    case "month":
                        let monthName = formatter("MMMM")
                        let months = calendar.range(of: .month, in: .year, for: date)?.count ?? 12
                        let labels = (1...months).map { value -> String in
                            let first = calendar.date(
                                from: DateComponents(era: parts.era, year: year, month: value, day: 1)
                            ) ?? date
                            return monthName.string(from: first)
                        }
                        columns.append(
                            WheelColumnModel(
                                id: "month", labels: labels, selected: month - 1, cyclic: true,
                                select: { index in change { $0.month = index + 1 } }
                            )
                        )
                    case "day":
                        let dayName = formatter("d")
                        let days = calendar.range(of: .day, in: .month, for: date)?.count ?? 31
                        let labels = (1...days).map { value -> String in
                            let day = calendar.date(
                                from: DateComponents(era: parts.era, year: year, month: month, day: value)
                            ) ?? date
                            return dayName.string(from: day)
                        }
                        columns.append(
                            WheelColumnModel(
                                id: "day", labels: labels, selected: (parts.day ?? 1) - 1, cyclic: true,
                                select: { index in change { $0.day = index + 1 } }
                            )
                        )
                    default:
                        // A hundred years either side, inside the range.
                        // 前後各一百年，限制在範圍之內。
                        let yearName = formatter("y")
                        let lowest = max(
                            year - 100,
                            calendar.component(.year, from: max(range.lowerBound, Date(timeIntervalSince1970: -6e10)))
                        )
                        let highest = min(
                            year + 100,
                            calendar.component(.year, from: min(range.upperBound, Date(timeIntervalSince1970: 6e10)))
                        )
                        let years = Array(min(lowest, year)...max(highest, year))
                        let labels = years.map { value -> String in
                            let first = calendar.date(
                                from: DateComponents(era: parts.era, year: value, month: 1, day: 1)
                            ) ?? date
                            return yearName.string(from: first)
                        }
                        columns.append(
                            WheelColumnModel(
                                id: "year", labels: labels,
                                selected: years.firstIndex(of: year) ?? 0, cyclic: false,
                                select: { index in change { $0.year = years[index] } }
                            )
                        )
                }
            }
        }

        if components.contains(.hourAndMinute) {
            let pattern = DateFormatter.dateFormat(fromTemplate: "jmm", options: 0, locale: locale)
                ?? "h:mm a"
            let twentyFour = pattern.contains("H") || pattern.contains("k")
            let order = fieldOrder(
                pattern: pattern,
                fields: [
                    "h": "hour", "H": "hour", "k": "hour", "K": "hour", "m": "minute",
                    "a": "period", "b": "period", "B": "period",
                ]
            )
            let hour = parts.hour ?? 0
            let periodNames = formatter("h a")
            for field in order {
                switch field {
                    case "hour":
                        let labels: [String]
                        let selected: Int
                        if twentyFour {
                            let padded = pattern.contains("HH")
                            labels = (0..<24).map { padded ? String(format: "%02d", $0) : String($0) }
                            selected = hour
                        } else {
                            labels = (1...12).map(String.init)
                            selected = (hour + 11) % 12
                        }
                        columns.append(
                            WheelColumnModel(
                                id: "hour", labels: labels, selected: selected, cyclic: true,
                                select: { index in
                                    change {
                                        $0.hour = twentyFour ? index : (index + 1) % 12 + (hour >= 12 ? 12 : 0)
                                    }
                                }
                            )
                        )
                    case "minute":
                        columns.append(
                            WheelColumnModel(
                                id: "minute", labels: (0..<60).map { String(format: "%02d", $0) },
                                selected: parts.minute ?? 0, cyclic: true,
                                select: { index in change { $0.minute = index } }
                            )
                        )
                    default:
                        guard !twentyFour else { continue }
                        columns.append(
                            WheelColumnModel(
                                id: "period",
                                labels: [periodNames.amSymbol, periodNames.pmSymbol],
                                selected: hour >= 12 ? 1 : 0, cyclic: false,
                                select: { index in change { $0.hour = hour % 12 + (index == 1 ? 12 : 0) } }
                            )
                        )
                }
            }
        }
        return columns
    }
}

/// One column: the chosen value in a band, two neighbours either side.
/// 一欄：選中的值在帶子裡，上下各兩個鄰居。
struct _WheelColumn: View {
    var model: WheelColumnModel
    /// Scroll travel not yet turned into a step. / 還沒變成一步的捲動量。
    @State var travel = 0.0
    /// The value chosen when a drag began. / 拖曳開始時選中的值。
    @State var dragBase: Int?

    static let rowHeight = 24.0
    /// Scroll travel per row: one wheel notch, 16 pt on GtkBackend (and WinUIBackend's
    /// pointsPerScrollLine), where each notch is a gesture of its own. At the row height (24 pt)
    /// a notch ended short of a row and its travel was dropped, so the wheel never
    /// turned under a mouse wheel on GTK (P41, 2026-10-20). A drag still moves by rows.
    /// 每列的捲動量：滾輪一格,GtkBackend 上是 16 pt(WinUIBackend 的 pointsPerScrollLine 也是),且在 GTK 上每格是獨立的一次手勢。用列高(24 pt)時一格到不了
    /// 一列，其捲動量就被丟掉，所以在 GTK 上用滑鼠滾輪轉不動(P41,2026-10-20)。拖曳仍以列為單位。
    static let scrollStep = 16.0
    static let neighbours = 2

    func index(_ offset: Int) -> Int? {
        let count = model.labels.count
        guard count > 0 else { return nil }
        let raw = model.selected + offset
        if model.cyclic {
            return ((raw % count) + count) % count
        }
        return model.labels.indices.contains(raw) ? raw : nil
    }

    func step(_ steps: Int) {
        if let target = index(steps) {
            model.select(target)
        } else if !model.cyclic {
            model.select(steps > 0 ? model.labels.count - 1 : 0)
        }
    }

    var body: some View {
        let longest = model.labels.max { $0.count < $1.count } ?? ""
        return ZStack {
            VStack(spacing: 0) {
                ForEach(Array(-Self.neighbours...Self.neighbours), id: \.self) { offset in
                    let shown = index(offset)
                    Text(shown.map { model.labels[$0] } ?? " ")
                        .frame(height: Self.rowHeight)
                        .opacity(offset == 0 ? 1 : (abs(offset) == 1 ? 0.55 : 0.3))
                        .onTapGesture {
                            if let shown, offset != 0 { model.select(shown) }
                        }
                }
            }
            // Holds the column at its widest label, so it does not change width as it turns.
            // 讓欄寬固定在最寬的標籤，轉動時不會變寬變窄。
            Text(longest).opacity(0)
        }
        // At its own width: the band would otherwise take an equal share of the
        // row and a long month be cut ("Sept...") in the date-and-time wheel.
        // 用自己的寬度：否則帶子會平分整列，日期加時間的滾輪裡較長的月份會被截斷("Sept...")。
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 8)
        // The band behind the chosen row, as wide as the column: a background is
        // offered the content's size, where inside the fixed-size stack it was
        // offered nothing and drew 10 pt wide.
        // 選中那一列後面的帶子，與欄同寬:background 會拿到內容的尺寸;放在固定尺寸的堆疊裡時它什麼都拿不到，只畫了 10 pt 寬。
        .background(
            Color(white: 0.5, opacity: 0.22)
                .frame(height: Self.rowHeight + 2)
                .cornerRadius(6)
        )
        .onScrollGesture(onChanged: { value in
            travel += value.delta.y
            let steps = Int((travel / Self.scrollStep).rounded(.towardZero))
            if steps != 0 {
                travel -= Double(steps) * Self.scrollStep
                step(steps)
            }
        }, onEnded: { _ in travel = 0 })
        .onDragGesture(onChanged: { value in
            let base = dragBase ?? model.selected
            if dragBase == nil { dragBase = base }
            let steps = Int(((value.startLocation.y - value.location.y) / Self.rowHeight).rounded())
            let raw = base + steps
            let count = model.labels.count
            let target = model.cyclic ? ((raw % count) + count) % count : min(max(raw, 0), count - 1)
            if target != model.selected { model.select(target) }
        }, onEnded: { _ in dragBase = nil })
    }
}
