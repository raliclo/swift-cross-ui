@_spi(Backends) import SwiftCrossUI
import AndroidKit
import SwiftJava
import Foundation
import JavaTime

// swiftlint:disable force_try
extension AndroidBackend: BackendFeatures.DatePickers {
    public func createDatePicker() -> Widget {
        // TODO(bbrk24): Once DatePickerStyle is more like PickerStyle, the FrameLayout wrapper will
        //   be unnecessary
        AndroidKit.FrameLayout(Self.activity, environment: Self.env)
    }

    private static func getLocalDateTime(
        date: Foundation.Date,
        timeZone: Foundation.TimeZone
    ) -> LocalDateTime {
        var calendar = Foundation.Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let components = calendar.dateComponents(
            [.era, .year, .month, .day, .hour, .minute, .second],
            from: date
        )

        // era 0 = BC, 1 = AD
        let year = Int32(components.era == 0 ? 1 - components.year! : components.year!)

        return try! JavaClass<LocalDateTime>().of(
            year,
            Int32(components.month!),
            Int32(components.day!),
            Int32(components.hour!),
            Int32(components.minute!),
            Int32(components.second!)
        )!
    }

    private static func getFoundationDate(
        localDateTime: LocalDateTime,
        timeZone: Foundation.TimeZone
    ) -> Foundation.Date {
        var calendar = Foundation.Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let year = localDateTime.getYear()

        let components = DateComponents(
            calendar: calendar,
            timeZone: timeZone,
            era: year <= 0 ? 0 : 1,
            year: Int(year <= 0 ? 1 - year : year),
            month: Int(localDateTime.getMonthValue()),
            day: Int(localDateTime.getDayOfMonth()),
            hour: Int(localDateTime.getHour()),
            minute: Int(localDateTime.getMinute()),
            second: Int(localDateTime.getSecond())
        )

        return calendar.date(from: components)!
    }

    public func updateDatePicker(
        _ datePicker: Widget,
        environment: EnvironmentValues,
        date: Foundation.Date,
        range: ClosedRange<Foundation.Date>,
        components: DatePickerComponents,
        onChange: @escaping (Foundation.Date) -> Void
    ) {
        let frame = datePicker.as(AndroidKit.FrameLayout.self)!
        var datePicker = frame.getChildAt(0)?.as(AbstractDatePicker.self)

        switch environment.backendDatePickerStyle {
            case .automatic, .compact:
                var compactDatePicker = datePicker?.as(CompactDatePicker.self)

                if compactDatePicker == nil {
                    frame.removeAllViews()
                    compactDatePicker = CompactDatePicker(
                        Self.activity.as(FragmentActivity.self)!,
                        environment: Self.env
                    )
                    datePicker = compactDatePicker
                    frame.addView(compactDatePicker!)
                }

                compactDatePicker!
                    .setForegroundColor(
                        environment.suggestedForegroundColor.resolve(in: environment).asColorInt()
                    )
            case .graphical:
                if datePicker?.is(GraphicalDatePicker.self) != true {
                    frame.removeAllViews()
                    datePicker = GraphicalDatePicker(
                        Self.activity,
                        environment: Self.env
                    )
                    frame.addView(datePicker!)
                }
            case .wheel:
                // The TODO this replaces was right about the obstacle and wrong
                // about its being one: `datePickerMode="spinner"` can only be
                // *set* in XML, and it can be *defaulted* by a theme, which
                // needs no resource of ours. See `WheelDatePicker.kt`.
                //
                // 此處所取代的那則 TODO，對於障礙的描述是正確的，但「那是個障礙」這件事是錯的：
                // `datePickerMode="spinner"` 確實只能在 XML 中被**設定**，但它可以被主題**預設**，
                // 而那不需要我們自己的任何資源。見 `WheelDatePicker.kt`。
                if datePicker?.is(WheelDatePicker.self) != true {
                    frame.removeAllViews()
                    datePicker = WheelDatePicker(
                        Self.activity,
                        environment: Self.env
                    )
                    frame.addView(datePicker!)
                }
        }

        guard let datePicker else {
            preconditionFailure("datePicker must be set by switch above, but was not")
        }

        datePicker.setComponents(Int32(components.rawValue))
        datePicker.setRange(
            min: Self.getLocalDateTime(date: range.lowerBound, timeZone: environment.timeZone),
            max: Self.getLocalDateTime(date: range.upperBound, timeZone: environment.timeZone)
        )
        datePicker.setValue(Self.getLocalDateTime(date: date, timeZone: environment.timeZone))
        datePicker.setEnabled(environment.isEnabled)

        datePicker.setAction(SwiftAction(environment: Self.env) {
            let date = Self.getFoundationDate(
                localDateTime: datePicker.getValue()!,
                timeZone: environment.timeZone
            )
            onChange(date)
        })
    }
}
