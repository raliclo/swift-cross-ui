import CGtk
import Foundation

extension Calendar {
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
}
