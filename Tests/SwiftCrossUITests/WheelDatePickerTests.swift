import Foundation
import Testing

@testable import SwiftCrossUI

/// The Swift wheel's columns for a region: their order and their text, as
/// UIDatePicker draws them (P90).
/// Swift 滾輪在某個地區的欄：順序與文字，與 UIDatePicker 的畫法相同(P90)。
@MainActor
@Suite("Swift wheel date picker columns")
struct WheelDatePickerTests {
    static let date: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        return calendar.date(from: DateComponents(year: 2025, month: 8, day: 24, hour: 21, minute: 46))!
    }()

    func columns(_ region: String, _ components: DatePickerComponents) -> [WheelColumnModel] {
        _SwiftWheelDatePicker.columns(
            for: Self.date,
            components: components,
            locale: Locale(identifier: region),
            range: Date.distantPast...Date.distantFuture,
            set: { _ in }
        )
    }

    func chosen(_ columns: [WheelColumnModel]) -> [String] {
        columns.map { $0.labels[$0.selected] }
    }

    @Test("A quoted literal in a pattern is not read as a field")
    func quoted() {
        let order = _SwiftWheelDatePicker.fieldOrder(
            pattern: "d 'de' MMMM 'de' y",
            fields: ["y": "year", "M": "month", "d": "day"]
        )
        #expect(order == ["day", "month", "year"])
    }

    @Test("en_US writes month, day, year and a 12-hour time with AM/PM after")
    func enUS() {
        #expect(columns("en_US", .date).map(\.id) == ["month", "day", "year"])
        #expect(chosen(columns("en_US", .date)) == ["August", "24", "2025"])
        #expect(columns("en_US", .hourAndMinute).map(\.id) == ["hour", "minute", "period"])
        #expect(chosen(columns("en_US", .hourAndMinute)) == ["9", "46", "PM"])
    }

    @Test("en_GB writes day, month, year and a 24-hour time")
    func enGB() {
        #expect(columns("en_GB", .date).map(\.id) == ["day", "month", "year"])
        #expect(columns("en_GB", .hourAndMinute).map(\.id) == ["hour", "minute"])
        #expect(chosen(columns("en_GB", .hourAndMinute)) == ["21", "46"])
    }

    @Test("zh_TW writes year, month, day with their characters, and the period before the hour")
    func zhTW() {
        #expect(columns("zh_TW", .date).map(\.id) == ["year", "month", "day"])
        #expect(chosen(columns("zh_TW", .date)) == ["2025年", "8月", "24日"])
        #expect(columns("zh_TW", .hourAndMinute).first?.id == "period")
    }

    @Test("A move inside a month keeps the day inside the next one")
    func dayClamped() {
        var set: Date?
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let january31 = calendar.date(from: DateComponents(year: 2025, month: 1, day: 31))!
        let columns = _SwiftWheelDatePicker.columns(
            for: january31,
            components: .date,
            locale: Locale(identifier: "en_US"),
            range: Date.distantPast...Date.distantFuture,
            set: { set = $0 }
        )
        columns.first { $0.id == "month" }?.select(1)
        #expect(set.map { calendar.component(.day, from: $0) } == 28)
        #expect(set.map { calendar.component(.month, from: $0) } == 2)
    }
}
