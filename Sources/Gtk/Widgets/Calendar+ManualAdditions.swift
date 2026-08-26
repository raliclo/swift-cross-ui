import CGtk
import Foundation

extension Calendar {
    /// The instant the calendar is holding.
    ///
    /// Beware that a `GtkCalendar` is a day picker wearing a `GDateTime`, and
    /// only the year, month and day survive a round trip. Measured on GTK
    /// 4.22.4 and confirmed in `gtk/gtkcalendar.c`:
    ///
    /// - The setter is a no-op unless the year, month or day differs
    ///   (`calendar_select_day_internal` returns early), so setting the same
    ///   day at a different time, or in a different time zone, silently does
    ///   nothing at all.
    /// - Clicking a day rebuilds the value as
    ///   `g_date_time_new_local(year, month, day, 0, 0, 0)`
    ///   (`calendar_select_and_focus_day`), discarding the time of day and
    ///   forcing the machine's time zone whatever was set.
    ///
    /// Use ``selectedDay`` and ``selectDay(year:month:day:)`` where the time of
    /// day or the time zone matters; they say what the widget can actually
    /// store, so nothing goes missing without the caller deciding it should.
    public var date: Date {
        get {
            GDateTime(gtk_calendar_get_date(opaquePointer)).toDate()
        }
        set {
            // Tolerates a nil rather than trapping on the implicit unwrap.
            // GDateTime's Date initialiser is an `init!`, and the pair of this
            // and that unwrap is what killed P11 on Windows: no message, no
            // event log entry, exit code 0, and every other app in the sweep
            // running fine.
            //
            // Not setting the date leaves the calendar on today, which is wrong
            // and visible. Trapping takes the whole app with it.
            //
            // 容忍 nil，而非在隱式解包時觸發 trap。GDateTime 接受 Date 的建構函式是 `init!`，
            // 而它與此處的解包這一組合，正是 P11 在 Windows 上死亡的原因：沒有訊息、事件記錄
            // 中沒有任何項目、結束碼為 0，而該次掃描中其他 app 全都正常。
            //
            // 不設定日期會讓月曆停留在今天，那是錯的但看得見；trap 則會讓整個 app 一起消失。
            guard let gDateTime = GDateTime(newValue) else {
                print("Gtk: could not convert \(newValue) to GDateTime, calendar left unchanged")
                return
            }
            withExtendedLifetime(gDateTime) {
                gtk_calendar_select_day(opaquePointer, gDateTime.pointer)
            }
        }
    }

    /// The day the calendar is showing, with the month numbered from 1 as
    /// `Foundation.DateComponents` numbers it. GTK's own `month` property
    /// counts from zero, which is the off-by-one this exists to contain.
    ///
    /// This is the whole of what a `GtkCalendar` stores that can be trusted;
    /// see ``date`` for what happens to the rest.
    public var selectedDay: DateComponents {
        DateComponents(year: year, month: month + 1, day: day)
    }

    /// Shows `year`-`month`-`day`, with the month numbered from 1.
    ///
    /// Builds the value exactly the way GTK builds it for a click on a day
    /// (`g_date_time_new_local`, midnight), so a date set from code and a date
    /// the user picked leave the widget in identical states.
    ///
    /// Emits `day-selected` if the day changes, the same as a click does --
    /// GTK draws no distinction, so a caller that needs one has to draw it
    /// itself.
    public func selectDay(year: Int, month: Int, day: Int) {
        guard
            let gDateTime = GDateTime(
                g_date_time_new_local(gint(year), gint(month), gint(day), 0, 0, 0)
            )
        else {
            print("Gtk: could not build a GDateTime for \(year)-\(month)-\(day), ignoring")
            return
        }
        withExtendedLifetime(gDateTime) {
            gtk_calendar_select_day(opaquePointer, gDateTime.pointer)
        }
    }
}
