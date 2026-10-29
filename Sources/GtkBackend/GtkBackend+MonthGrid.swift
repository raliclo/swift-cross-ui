import CGtk
import Foundation
import Gtk

/// The month grid of GtkBackend's graphical and compact date pickers, drawn
/// from a Foundation `Calendar` rather than by a `GtkCalendar`.
///
/// `GtkCalendar` could not follow `environment.locale`. Its month and weekday
/// names are computed once per process, by the first calendar created, from
/// the C locale (`default_monthname`, `default_abbreviated_dayname`,
/// gtkcalendar.c:303-304, filled at :703-747), and its first day of the week
/// is a private field written only in `gtk_calendar_init` (:246, :656-699),
/// with no property to change it. So a picker set to ja_JP kept English names
/// and a Sunday start, and two pickers in different locales could not differ
/// (checked against the GTK 4.24.1 source, 2026-10-30). The same widget also
/// kept the browsed month in the selection's field, had no range and was
/// Gregorian only; see ``DatePickerWidget``.
///
/// Here every name comes from the calendar: the title from a `DateFormatter`
/// with the "yMMMM" template, the weekday header from
/// `shortStandaloneWeekdaySymbols` starting at `firstWeekday`, and the day
/// numbers from a "d" formatter, so a locale with its own digits gets them.
/// The browsed month is kept apart from the selection, so a layout pass that
/// writes the same date back leaves a user's browsing alone; days outside the
/// range are insensitive.
///
/// GtkBackend 的 graphical 與 compact 日期選擇器的月曆格，由 Foundation 的 `Calendar` 畫出，而不是
/// `GtkCalendar`。
///
/// `GtkCalendar` 跟不上 `environment.locale`:它的月份與星期名稱在每個行程只算一次，由第一個建立的月曆依
/// C locale 算出(`default_monthname`、`default_abbreviated_dayname`,gtkcalendar.c:303-304,於 :703-747
/// 填入),而一週的第一天是私有欄位，只在 `gtk_calendar_init` 寫入(:246、:656-699),沒有屬性可以改。所以設成
/// ja_JP 的選擇器仍是英文名稱、週日開始，兩個不同 locale 的選擇器也無法不同(依 GTK 4.24.1 原始碼核對,
/// 2026-10-30)。同一個元件還把瀏覽中的月份放在選取的欄位裡、沒有範圍、只有公曆；見 ``DatePickerWidget``。
///
/// 這裡每個名稱都來自 calendar:標題來自以「yMMMM」範本建立的 `DateFormatter`,星期列來自從 `firstWeekday`
/// 起算的 `shortStandaloneWeekdaySymbols`,日期數字來自「d」格式器，因此有自己數字的 locale 會拿到它們。
/// 瀏覽中的月份與選取分開保存，因此把同一個日期寫回的版面配置不會打斷使用者的瀏覽；範圍外的日子不可點選。
final class MonthGrid: Box {
    /// A day the user clicked, as the start of that day in the grid's calendar.
    /// Not called for a selection applied by ``show(selection:range:calendar:)``.
    /// 使用者點的日子，以 grid 的 calendar 中那一天的開始表示。``show(selection:range:calendar:)`` 套用的選取不會呼叫它。
    var onPick: ((Date) -> Void)?

    private let previousButton = Button(iconName: "go-previous-symbolic")
    private let nextButton = Button(iconName: "go-next-symbolic")
    private let title = Gtk.Label(string: "")
    private let days = Grid()
    private var weekdayLabels: [Gtk.Label] = []
    private var dayButtons: [Button] = []
    /// The day each button shows, by button index.
    /// 每個按鈕顯示的日子，依按鈕索引。
    private var cellDays: [Date] = Array(repeating: .distantPast, count: 42)

    private var calendar: Foundation.Calendar?
    private var range = Date.distantPast...Date.distantFuture
    /// The start of the selected day, or nil before the first ``show``.
    /// 選取那一天的開始；第一次 ``show`` 之前為 nil。
    private var selection: Date?
    /// The start of the month on screen. Moves with the arrows and with a new
    /// selection, not with a layout pass that writes the same date back.
    /// 畫面上那個月的開始。隨箭頭與新的選取移動，不隨把同一個日期寫回的版面配置移動。
    private var shownMonth = Date()
    private var titleFormatter = DateFormatter()
    private var dayFormatter = DateFormatter()

    init() {
        super.init(gtk_box_new(GTK_ORIENTATION_VERTICAL, 6))
        gtk_widget_add_css_class(widgetPointer, "scui-month-grid")

        let header = Box(orientation: .horizontal, spacing: 6)
        title.expandHorizontally = true
        gtk_widget_add_css_class(previousButton.widgetPointer, "flat")
        gtk_widget_add_css_class(nextButton.widgetPointer, "flat")
        // Handlers before adding: adding is what registers the signal (see
        // Widget.parentWidget).
        // 先設 handler 再加入：加入才會註冊訊號(見 Widget.parentWidget)。
        previousButton.clicked = { [weak self] _ in self?.browse(by: -1) }
        nextButton.clicked = { [weak self] _ in self?.browse(by: 1) }
        header.add(previousButton)
        header.add(title)
        header.add(nextButton)
        add(header)

        days.columnHomogeneous = true
        days.rowHomogeneous = true
        days.columnSpacing = 2
        days.rowSpacing = 2
        for column in 0..<7 {
            let label = Gtk.Label(string: "")
            gtk_widget_add_css_class(label.widgetPointer, "dim-label")
            days.attach(child: label, left: column, top: 0, width: 1, height: 1)
            weekdayLabels.append(label)
        }
        for index in 0..<42 {
            let button = Button(label: "")
            gtk_widget_add_css_class(button.widgetPointer, "flat")
            button.clicked = { [weak self] _ in self?.picked(index) }
            days.attach(child: button, left: index % 7, top: 1 + index / 7, width: 1, height: 1)
            dayButtons.append(button)
        }
        add(days)
    }

    /// Shows `selection` in `calendar`. The weekday names, the title and the
    /// first day of the week follow `calendar.locale` and `firstWeekday`; the
    /// browsed month jumps to the selection only when the selected day changes.
    /// 在 `calendar` 中顯示 `selection`。星期名稱、標題與一週的第一天依 `calendar.locale` 與
    /// `firstWeekday`;只有選取的日子改變時，瀏覽中的月份才跳到選取處。
    func show(selection date: Date, range: ClosedRange<Date>, calendar: Foundation.Calendar) {
        if calendar != self.calendar {
            self.calendar = calendar
            relabel(for: calendar)
            // The same instant can be another day in another calendar or time zone.
            // 同一個瞬間在另一個 calendar 或時區可能是另一天。
            selection = nil
        }
        self.range = range
        let day = calendar.startOfDay(for: date)
        if day != selection {
            selection = day
            shownMonth = monthStart(of: day, in: calendar)
        }
        render()
    }

    private func relabel(for calendar: Foundation.Calendar) {
        let locale = calendar.locale ?? .current
        titleFormatter = DateFormatter()
        titleFormatter.calendar = calendar
        titleFormatter.locale = locale
        titleFormatter.timeZone = calendar.timeZone
        titleFormatter.setLocalizedDateFormatFromTemplate("yMMMM")
        dayFormatter = DateFormatter()
        dayFormatter.calendar = calendar
        dayFormatter.locale = locale
        dayFormatter.timeZone = calendar.timeZone
        dayFormatter.dateFormat = "d"

        let symbols = calendar.shortStandaloneWeekdaySymbols
        for (column, label) in weekdayLabels.enumerated() {
            label.label = symbols[(calendar.firstWeekday - 1 + column) % symbols.count]
        }
    }

    private func monthStart(of date: Date, in calendar: Foundation.Calendar) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? date
    }

    private func browse(by months: Int) {
        guard
            let calendar,
            let moved = calendar.date(byAdding: .month, value: months, to: shownMonth)
        else { return }
        shownMonth = monthStart(of: moved, in: calendar)
        render()
    }

    private func picked(_ index: Int) {
        let day = cellDays[index]
        guard let calendar, isInRange(day, calendar) else { return }
        selection = day
        shownMonth = monthStart(of: day, in: calendar)
        render()
        onPick?(day)
    }

    private func isInRange(_ day: Date, _ calendar: Foundation.Calendar) -> Bool {
        // Whole days: the first day of the range is clickable even when the
        // range starts in the middle of it.
        // 以整天計：範圍的第一天即使從當天中途開始，也可以點。
        guard let end = calendar.date(byAdding: .day, value: 1, to: day) else { return false }
        return end > range.lowerBound && day <= range.upperBound
    }

    private func render() {
        guard let calendar else { return }
        title.label = titleFormatter.string(from: shownMonth)

        // Days of the previous month fill the first row up to the month's first
        // weekday, counted from the locale's first day of the week.
        // 前一個月的日子補滿第一列，直到本月第一天的星期，從 locale 的一週第一天起算。
        let weekday = calendar.component(.weekday, from: shownMonth)
        let lead = (weekday - calendar.firstWeekday + 7) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -lead, to: shownMonth) else {
            return
        }
        let month = calendar.component(.month, from: shownMonth)
        for (index, button) in dayButtons.enumerated() {
            guard let day = calendar.date(byAdding: .day, value: index, to: gridStart) else {
                continue
            }
            cellDays[index] = day
            button.label = dayFormatter.string(from: day)
            setClass("dim-label", on: button, calendar.component(.month, from: day) != month)
            // Filled for the selection: on a flat button `suggested-action` only
            // tints the text, which read as a link rather than a choice (WSLg,
            // 2026-10-30).
            // 選取的那天要填滿：在 flat 按鈕上 `suggested-action` 只會把文字染色，看起來像連結而不是選取(WSLg,2026-10-30)。
            setClass("flat", on: button, day != selection)
            setClass("suggested-action", on: button, day == selection)
            button.sensitive = isInRange(day, calendar)
        }
    }

    private func setClass(_ name: String, on widget: Widget, _ present: Bool) {
        if present {
            gtk_widget_add_css_class(widget.widgetPointer, name)
        } else {
            gtk_widget_remove_css_class(widget.widgetPointer, name)
        }
    }
}
