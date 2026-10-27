import Foundation

// `.datePickerStyle(.clock)` and `.datePickerStyle(.rows)`: the two ways P41
// showed the same `.hourAndMinute` picker, given names so an app asks for one
// and gets it on every backend. `.clock` is what AppKit draws, an
// analogue face with hands; `.rows` is what GtkBackend draws, hour, minute and
// second fields with minus and plus. Where the backend's own picker already
// draws the one asked for (``BackendFeatures/DatePickers/nativeTimePresentation``)
// it is used; everywhere else the face or the row is built from SwiftCrossUI
// views, so a `.clock` on GTK looks like a `.clock` on AppKit.
//
// `.datePickerStyle(.clock)` 與 `.datePickerStyle(.rows)`:P41 顯示同一個 `.hourAndMinute` 選擇器的兩種方式，取了名字，
// 讓 app 要哪一種就在每個 backend 上拿到哪一種。`.clock` 是 AppKit 畫的，有指針的類比鐘面;`.rows` 是
// GtkBackend 畫的，時、分、秒欄位加上減號與加號。backend 自己的選擇器已經畫出所要的那一種時
// (``BackendFeatures/DatePickers/nativeTimePresentation``)就用它;其他地方以 SwiftCrossUI 的 view 組出鐘面或列，所以
// GTK 上的 `.clock` 看起來跟 AppKit 上的一樣。

/// A time shown as an analogue clock face, its hands dragged to set it.
///
/// AppKitBackend draws its own (NSDatePicker's clock); every other backend
/// draws ``_SwiftClockDatePicker``. A date, if asked for too, is a calendar
/// beside the face, as on AppKit.
///
/// 以類比鐘面顯示時間，拖曳指針來設定。AppKitBackend 畫它自己的(NSDatePicker 的時鐘);其他 backend 畫
/// ``_SwiftClockDatePicker``。若也要求日期，日期是鐘面旁的月曆，與 AppKit 相同。
@available(iOS 14, macCatalyst 14, *)
public struct ClockDatePickerStyle: DatePickerStyle {
    public nonisolated init() {}

    public func makeView(
        selection: Binding<Date>,
        range: ClosedRange<Date>,
        components: DatePickerComponents,
        environment: EnvironmentValues
    ) -> _TimeDatePickerImplementation {
        _TimeDatePickerImplementation(
            presentation: .clock,
            selection: selection,
            range: range,
            components: components,
            native: Self.native(.clock, environment)
        )
    }

    static func native(_ presentation: TimePickerPresentation, _ environment: EnvironmentValues) -> Bool {
        let datePickers = environment.backend as? any BackendFeatures.DatePickers
        return datePickers?.nativeTimePresentation == presentation
    }
}

@available(iOS 14, macCatalyst 14, *)
extension DatePickerStyle where Self == ClockDatePickerStyle {
    /// A time shown as an analogue clock face. / 以類比鐘面顯示時間。
    public static nonisolated var clock: Self { Self() }
}

/// A time shown as a row of hour, minute and second fields, each stepped with
/// minus and plus or the scroll wheel.
///
/// GtkBackend draws its own (spin buttons); every other backend draws
/// ``_SwiftRowsDatePicker``. A date, if asked for too, is a compact date button
/// before the row, as on GtkBackend.
///
/// 以一列時、分、秒欄位顯示時間，每欄以減號、加號或滾輪調整。GtkBackend 畫它自己的(spin button);其他 backend 畫
/// ``_SwiftRowsDatePicker``。若也要求日期，日期是列前面的精簡日期按鈕，與 GtkBackend 相同。
@available(iOS 14, macCatalyst 14, *)
public struct RowsDatePickerStyle: DatePickerStyle {
    public nonisolated init() {}

    public func makeView(
        selection: Binding<Date>,
        range: ClosedRange<Date>,
        components: DatePickerComponents,
        environment: EnvironmentValues
    ) -> _TimeDatePickerImplementation {
        _TimeDatePickerImplementation(
            presentation: .rows,
            selection: selection,
            range: range,
            components: components,
            native: ClockDatePickerStyle.native(.rows, environment)
        )
    }
}

@available(iOS 14, macCatalyst 14, *)
extension DatePickerStyle where Self == RowsDatePickerStyle {
    /// A time shown as a row of fields. / 以一列欄位顯示時間。
    public static nonisolated var rows: Self { Self() }
}

/// The `.clock` or `.rows` picker: the backend's own where it draws that one,
/// otherwise the face or the row in SwiftCrossUI views.
/// `.clock` 或 `.rows` 選擇器:backend 畫得出那一種就用它自己的，否則用 SwiftCrossUI view 組成的鐘面或列。
@available(iOS 14, macCatalyst 14, *)
@available(tvOS, unavailable)
public struct _TimeDatePickerImplementation: View {
    var presentation: TimePickerPresentation
    var selection: Binding<Date>
    var range: ClosedRange<Date>
    var components: DatePickerComponents
    var native: Bool

    public var body: some View {
        if native {
            // AppKit's clock is its `.graphical`; GtkBackend's row follows any
            // style, and `.compact` puts a date, if any, on a button before it.
            // AppKit 的時鐘是它的 `.graphical`;GtkBackend 的列跟隨任何樣式，`.compact` 讓日期(若有)成為列前的按鈕。
            _BuiltinDatePickerImplementation(
                style: presentation == .clock ? .graphical : .compact,
                selection: selection,
                range: range,
                components: components
            )
        } else if presentation == .clock {
            _SwiftClockDatePicker(selection: selection, range: range, components: components)
        } else {
            _SwiftRowsDatePicker(selection: selection, range: range, components: components)
        }
    }
}

/// A time's fields as a region writes them: 12 or 24 hours, the order of hour,
/// minute, second and AM/PM, and the AM/PM names. Pure, so it is tested without
/// a backend.
/// 地區書寫時間的欄位:12 或 24 小時，時、分、秒與上午/下午的順序，以及上午/下午的名稱。純函式，不需要 backend 就能測試。
struct TimeFields: Equatable {
    var twentyFour: Bool
    /// "hour", "minute", "second" and (12-hour only) "period", in order.
    /// "hour"、"minute"、"second" 與(只在 12 小時制)"period",依序。
    var order: [String]
    var am: String
    var pm: String

    init(locale: Locale, seconds: Bool) {
        let pattern = DateFormatter.dateFormat(
            fromTemplate: seconds ? "jmmss" : "jmm", options: 0, locale: locale
        ) ?? (seconds ? "h:mm:ss a" : "h:mm a")
        twentyFour = pattern.contains("H") || pattern.contains("k")
        var order = _SwiftWheelDatePicker.fieldOrder(
            pattern: pattern,
            fields: [
                "h": "hour", "H": "hour", "k": "hour", "K": "hour", "m": "minute", "s": "second",
                "a": "period", "b": "period", "B": "period",
            ]
        )
        if twentyFour { order.removeAll { $0 == "period" } }
        self.order = order
        let formatter = DateFormatter()
        formatter.locale = locale
        am = formatter.amSymbol
        pm = formatter.pmSymbol
    }

    /// `date` with one of hour, minute and second changed, inside `range`.
    /// 把 `date` 的時、分、秒之一改掉，並限制在 `range` 之內。
    static func set(
        _ date: Date, hour: Int? = nil, minute: Int? = nil, second: Int? = nil,
        range: ClosedRange<Date>
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        var parts = calendar.dateComponents([.era, .year, .month, .day, .hour, .minute, .second], from: date)
        if let hour { parts.hour = ((hour % 24) + 24) % 24 }
        if let minute { parts.minute = ((minute % 60) + 60) % 60 }
        if let second { parts.second = ((second % 60) + 60) % 60 }
        guard let moved = calendar.date(from: parts) else { return date }
        return min(max(moved, range.lowerBound), range.upperBound)
    }

    static func parts(of date: Date) -> (hour: Int, minute: Int, second: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        return (parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
    }
}

/// The date half of a `.clock` or `.rows` picker that also asks for a date: the
/// backend's calendar for `.clock`, its compact button for `.rows`, or
/// `.automatic` where it has neither.
/// 同時要求日期的 `.clock` 或 `.rows` 選擇器的日期部分:`.clock` 用 backend 的月曆,`.rows` 用它的精簡按鈕，兩者都沒有時用 `.automatic`。
@available(iOS 14, macCatalyst 14, *)
@available(tvOS, unavailable)
struct _TimePickerDatePart: View {
    var wanted: BackendDatePickerStyle
    var selection: Binding<Date>
    var range: ClosedRange<Date>
    @Environment(\.supportedDatePickerStyles) var supported

    var body: some View {
        _BuiltinDatePickerImplementation(
            style: supported.contains(wanted) ? wanted : .automatic,
            selection: selection,
            range: range,
            components: .date
        )
    }
}

/// The clock face drawn in SwiftCrossUI views, for backends without one of
/// their own. Twelve numerals, an hour and a minute hand (and a red second hand
/// for `.hourMinuteAndSecond`), AM or PM under the centre. A drag moves the hand
/// nearest to where it began; a click on AM/PM switches it; the scroll wheel
/// steps the minutes.
///
/// 以 SwiftCrossUI view 畫的鐘面，給沒有自己鐘面的 backend 用。十二個數字、時針與分針(`.hourMinuteAndSecond` 時再加
/// 紅色秒針),中心下方是上午或下午。拖曳會移動離起點最近的那根指針;點上午/下午切換;滾輪逐分鐘調整。
@available(iOS 14, macCatalyst 14, *)
@available(tvOS, unavailable)
public struct _SwiftClockDatePicker: View {
    var selection: Binding<Date>
    var range: ClosedRange<Date>
    var components: DatePickerComponents
    @Environment(\.locale) private var locale
    /// The hand a drag is moving. / 拖曳正在移動的指針。
    @State var dragging: ClockHand?
    /// Scroll travel not yet turned into a minute. / 還沒變成一分鐘的捲動量。
    @State var travel = 0.0

    static let size = 160.0

    public var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if components.contains(.date) {
                _TimePickerDatePart(wanted: .graphical, selection: selection, range: range)
            }
            if components.contains(.hourAndMinute) {
                face
            }
        }
    }

    var showsSeconds: Bool {
        #if os(iOS) || os(visionOS) || targetEnvironment(macCatalyst)
            false
        #else
            components.contains(.hourMinuteAndSecond)
        #endif
    }

    var face: some View {
        let time = TimeFields.parts(of: selection.wrappedValue)
        let fields = TimeFields(locale: locale, seconds: false)
        let angles = Self.angles(hour: time.hour, minute: time.minute, second: time.second)
        let radius = Self.size / 2
        return ZStack {
            Circle().fill(Color(white: 0.97))
            Circle().stroke(Color(white: 0.6), style: StrokeStyle(width: 5))
            ForEach(Array(1...12), id: \.self) { numeral in
                let angle = Double(numeral) / 12 * 2 * Double.pi
                Text("\(numeral)")
                    .font(.system(size: 15))
                    .foregroundColor(.black)
                    .offset(x: sin(angle) * (radius - 22), y: -cos(angle) * (radius - 22))
            }
            Text(time.hour >= 12 ? fields.pm : fields.am)
                .font(.system(size: 13))
                .foregroundColor(Color(white: 0.55))
                .offset(y: radius * 0.32)
                .onTapGesture {
                    selection.wrappedValue = TimeFields.set(
                        selection.wrappedValue, hour: time.hour + 12, range: range
                    )
                }
            _ClockHandShape(angle: angles.hour, length: 0.5, tail: 0.0)
                .stroke(.black, style: StrokeStyle(width: 4, cap: .round))
            _ClockHandShape(angle: angles.minute, length: 0.8, tail: 0.0)
                .stroke(.black, style: StrokeStyle(width: 3, cap: .round))
            if showsSeconds {
                _ClockHandShape(angle: angles.second, length: 0.82, tail: 0.15)
                    .stroke(.red, style: StrokeStyle(width: 1))
            }
            Circle().fill(.black).frame(width: 7, height: 7)
        }
        .frame(width: Self.size, height: Self.size)
        .onDragGesture(
            onChanged: { value in
                let centre = SIMD2(radius, radius)
                if dragging == nil {
                    guard let start = Self.angle(of: value.startLocation, centre: centre) else { return }
                    dragging = Self.nearestHand(
                        to: start, angles: angles, seconds: showsSeconds
                    )
                }
                guard let hand = dragging,
                    let angle = Self.angle(of: value.location, centre: centre)
                else { return }
                let moved = Self.time(
                    hand, at: angle, hour: time.hour, minute: time.minute, second: time.second
                )
                let next = TimeFields.set(
                    selection.wrappedValue, hour: moved.hour, minute: moved.minute,
                    second: moved.second, range: range
                )
                if next != selection.wrappedValue { selection.wrappedValue = next }
            },
            onEnded: { _ in dragging = nil }
        )
        .onScrollGesture(
            onChanged: { value in
                travel += value.delta.y
                let steps = Int((travel / 12).rounded(.towardZero))
                guard steps != 0 else { return }
                travel -= Double(steps) * 12
                let total = time.hour * 60 + time.minute - steps
                selection.wrappedValue = TimeFields.set(
                    selection.wrappedValue, hour: Int((Double(total) / 60).rounded(.down)),
                    minute: total, range: range
                )
            },
            onEnded: { _ in travel = 0 }
        )
    }

    /// The hands' angles in radians, clockwise from twelve. The hour hand moves
    /// with the minutes and the minute hand with the seconds, as a clock's do.
    /// 指針的角度(弧度),由十二點順時針量。時針隨分鐘移動，分針隨秒移動，與時鐘一樣。
    static func angles(hour: Int, minute: Int, second: Int) -> (hour: Double, minute: Double, second: Double) {
        let turn = 2 * Double.pi
        let seconds = Double(second)
        let minutes = Double(minute) + seconds / 60
        let hours = Double(hour % 12) + minutes / 60
        return (hours / 12 * turn, minutes / 60 * turn, seconds / 60 * turn)
    }

    /// The angle of `point` around `centre`, clockwise from twelve, or `nil` at the centre.
    /// `point` 繞 `centre` 的角度，由十二點順時針量;在中心時為 `nil`。
    static func angle(of point: SIMD2<Double>, centre: SIMD2<Double>) -> Double? {
        let offset = point - centre
        guard offset.x * offset.x + offset.y * offset.y > 16 else { return nil }
        let angle = atan2(offset.x, -offset.y)
        return angle < 0 ? angle + 2 * Double.pi : angle
    }

    static func nearestHand(
        to angle: Double, angles: (hour: Double, minute: Double, second: Double), seconds: Bool
    ) -> ClockHand {
        func distance(_ other: Double) -> Double {
            let raw = abs(other - angle).truncatingRemainder(dividingBy: 2 * Double.pi)
            return min(raw, 2 * Double.pi - raw)
        }
        var candidates: [(ClockHand, Double)] = [
            (.minute, distance(angles.minute)), (.hour, distance(angles.hour)),
        ]
        if seconds { candidates.append((.second, distance(angles.second))) }
        return candidates.min { $0.1 < $1.1 }!.0
    }

    /// The time with `hand` pointing at `angle`. The minute hand carries into
    /// the hour when it passes twelve, as turning a clock's crown does; the hour
    /// hand keeps AM or PM.
    /// `hand` 指向 `angle` 時的時間。分針越過十二點時進位到小時，與轉動時鐘的錶冠一樣;時針保持上午或下午。
    static func time(
        _ hand: ClockHand, at angle: Double, hour: Int, minute: Int, second: Int
    ) -> (hour: Int, minute: Int, second: Int) {
        let fraction = angle / (2 * Double.pi)
        switch hand {
            case .hour:
                let twelve = Int(fraction * 12) % 12
                return (twelve + (hour >= 12 ? 12 : 0), minute, second)
            case .minute:
                let next = Int((fraction * 60).rounded()) % 60
                var nextHour = hour
                if minute >= 45 && next < 15 { nextHour += 1 }
                if minute < 15 && next >= 45 { nextHour -= 1 }
                return ((nextHour + 24) % 24, next, second)
            case .second:
                return (hour, minute, Int((fraction * 60).rounded()) % 60)
        }
    }
}

/// A clock hand. / 時鐘指針。
enum ClockHand: Equatable {
    case hour, minute, second
}

/// One hand, from a little behind the centre to `length` of the radius.
/// 一根指針，從中心稍後方到半徑的 `length` 倍處。
struct _ClockHandShape: Shape {
    var angle: Double
    var length: Double
    var tail: Double

    func path(in bounds: Path.Rect) -> Path {
        let radius = min(bounds.width, bounds.height) / 2
        let centre = SIMD2(bounds.x + bounds.width / 2, bounds.y + bounds.height / 2)
        let direction = SIMD2(sin(angle), -cos(angle))
        return Path()
            .move(to: centre - direction * (tail * radius))
            .addLine(to: centre + direction * (length * radius))
    }
}

/// The row of time fields drawn in SwiftCrossUI views, for backends without one
/// of their own, laid out like GtkBackend's: each field a number with minus and
/// plus, colons between, AM/PM last (or first, where the region puts it).
///
/// 以 SwiftCrossUI view 畫的時間欄位列，給沒有自己時間列的 backend 用，版面與 GtkBackend 相同：每欄是數字加上減號與加號，
/// 中間是冒號，上午/下午在最後(或地區放的那一側)。
@available(iOS 14, macCatalyst 14, *)
@available(tvOS, unavailable)
public struct _SwiftRowsDatePicker: View {
    var selection: Binding<Date>
    var range: ClosedRange<Date>
    var components: DatePickerComponents
    @Environment(\.locale) private var locale

    var showsSeconds: Bool {
        #if os(iOS) || os(visionOS) || targetEnvironment(macCatalyst)
            false
        #else
            components.contains(.hourMinuteAndSecond)
        #endif
    }

    public var body: some View {
        let time = TimeFields.parts(of: selection.wrappedValue)
        let fields = TimeFields(locale: locale, seconds: showsSeconds)
        let date = selection.wrappedValue
        return HStack(spacing: 6) {
            if components.contains(.date) {
                _TimePickerDatePart(wanted: .compact, selection: selection, range: range)
            }
            if components.contains(.hourAndMinute) {
                ForEach(Array(fields.order.enumerated()), id: \.offset) { index, field in
                    if index > 0 && field != "period" && fields.order[index - 1] != "period" {
                        Text(":")
                    }
                    switch field {
                        case "hour":
                            _TimeRowField(
                                text: fields.twentyFour
                                    ? String(format: "%02d", time.hour)
                                    : String(format: "%02d", (time.hour + 11) % 12 + 1),
                                step: { selection.wrappedValue = TimeFields.set(date, hour: time.hour + $0, range: range) }
                            )
                        case "minute":
                            _TimeRowField(
                                text: String(format: "%02d", time.minute),
                                step: { selection.wrappedValue = TimeFields.set(date, minute: time.minute + $0, range: range) }
                            )
                        case "second":
                            _TimeRowField(
                                text: String(format: "%02d", time.second),
                                step: { selection.wrappedValue = TimeFields.set(date, second: time.second + $0, range: range) }
                            )
                        default:
                            _TimeRowPeriod(
                                text: time.hour >= 12 ? fields.pm : fields.am,
                                toggle: { selection.wrappedValue = TimeFields.set(date, hour: time.hour + 12, range: range) }
                            )
                    }
                }
            }
        }
        .fixedSize()
    }
}

extension View {
    /// The box every field in the row is drawn in. / 列中每個欄位畫在其中的框。
    func timeRowBox() -> some View {
        self
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.5, opacity: 0.12))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6).stroke(Color(white: 0.5, opacity: 0.45))
            }
    }
}

/// One field: its number, then minus and plus. The scroll wheel steps it too.
/// 一個欄位：它的數字，接著是減號與加號。滾輪也能調整它。
struct _TimeRowField: View {
    var text: String
    var step: (Int) -> Void
    @State var travel = 0.0

    var body: some View {
        HStack(spacing: 12) {
            Text(text).frame(minWidth: 22, alignment: .leading)
            Text("−").onTapGesture { step(-1) }
            Text("+").onTapGesture { step(1) }
        }
        .timeRowBox()
        // At its own width: the row squeezed the field before AM/PM and cut its
        // plus in half on AppKit (P41, 2026-10-18).
        // 用自己的寬度：列會擠壓上午/下午前面那一欄，在 AppKit 上把它的加號切掉一半(P41,2026-10-18)。
        .fixedSize()
        .onScrollGesture(onChanged: { value in
            travel += value.delta.y
            let steps = Int((travel / 12).rounded(.towardZero))
            if steps != 0 {
                travel -= Double(steps) * 12
                step(-steps)
            }
        }, onEnded: { _ in travel = 0 })
    }
}

/// AM/PM, switched with a click. / 上午/下午，點一下切換。
struct _TimeRowPeriod: View {
    var text: String
    var toggle: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
            Text("⇅").font(.system(size: 11))
        }
        .timeRowBox()
        .fixedSize()
        .onTapGesture { toggle() }
    }
}
