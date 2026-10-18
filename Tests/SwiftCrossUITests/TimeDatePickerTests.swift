import Foundation
import Testing

@testable import SwiftCrossUI

/// `.clock` and `.rows` drawn in SwiftCrossUI views: the fields a region writes,
/// and the clock face's arithmetic (P41).
/// 以 SwiftCrossUI view 畫的 `.clock` 與 `.rows`:地區書寫的欄位，以及鐘面的計算(P41)。
@MainActor
@Suite("Clock and rows date pickers")
struct TimeDatePickerTests {
    @Test("A region's time fields, in its order")
    func fields() {
        let us = TimeFields(locale: Locale(identifier: "en_US"), seconds: true)
        #expect(us.twentyFour == false)
        #expect(us.order == ["hour", "minute", "second", "period"])

        let gb = TimeFields(locale: Locale(identifier: "en_GB"), seconds: false)
        #expect(gb.twentyFour == true)
        #expect(gb.order == ["hour", "minute"])

        // zh_TW writes 上午 before the hour. / zh_TW 把上午寫在小時前面。
        let tw = TimeFields(locale: Locale(identifier: "zh_TW"), seconds: false)
        #expect(tw.order.first == "period")
    }

    @Test("Setting a field wraps it and stays in the range")
    func set() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let date = calendar.date(from: DateComponents(year: 2025, month: 8, day: 24, hour: 23, minute: 59))!
        let next = TimeFields.set(date, hour: 24, range: Date.distantPast...Date.distantFuture)
        #expect(TimeFields.parts(of: next).hour == 0)
        // The same day: a field wraps, it does not carry into the date.
        // 同一天：欄位循環，不進位到日期。
        #expect(calendar.component(.day, from: next) == 24)
        let early = TimeFields.set(date, minute: -1, range: date...Date.distantFuture)
        #expect(early == date)
    }

    @Test("Hand angles, clockwise from twelve")
    func angles() {
        let angles = _SwiftClockDatePicker.angles(hour: 15, minute: 30, second: 0)
        #expect(abs(angles.minute - Double.pi) < 1e-9)
        #expect(abs(angles.hour - (3.5 / 12 * 2 * Double.pi)) < 1e-9)
        let centre = SIMD2(80.0, 80.0)
        #expect(_SwiftClockDatePicker.angle(of: SIMD2(80, 0), centre: centre)! < 1e-9)
        #expect(abs(_SwiftClockDatePicker.angle(of: SIMD2(160, 80), centre: centre)! - Double.pi / 2) < 1e-9)
        #expect(_SwiftClockDatePicker.angle(of: centre, centre: centre) == nil)
    }

    @Test("A drag moves the nearest hand; the minute hand carries past twelve")
    func drag() {
        let angles = _SwiftClockDatePicker.angles(hour: 9, minute: 46, second: 0)
        #expect(_SwiftClockDatePicker.nearestHand(to: angles.minute + 0.1, angles: angles, seconds: false) == .minute)
        #expect(_SwiftClockDatePicker.nearestHand(to: angles.hour - 0.1, angles: angles, seconds: false) == .hour)

        // Minute hand from :50 to :05 is ten o'clock. / 分針從 :50 轉到 :05 就是十點。
        let carried = _SwiftClockDatePicker.time(.minute, at: 5.0 / 60 * 2 * Double.pi, hour: 9, minute: 50, second: 0)
        #expect(carried.hour == 10 && carried.minute == 5)
        let back = _SwiftClockDatePicker.time(.minute, at: 55.0 / 60 * 2 * Double.pi, hour: 10, minute: 5, second: 0)
        #expect(back.hour == 9 && back.minute == 55)

        // The hour hand keeps PM. / 時針保持下午。
        let pm = _SwiftClockDatePicker.time(.hour, at: 3.2 / 12 * 2 * Double.pi, hour: 21, minute: 46, second: 0)
        #expect(pm.hour == 15 && pm.minute == 46)
    }
}
