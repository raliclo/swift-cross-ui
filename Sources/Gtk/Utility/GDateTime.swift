import CGtk
import Foundation

public class GDateTime {
    public let pointer: OpaquePointer

    public init(_ pointer: OpaquePointer) {
        self.pointer = pointer
    }

    public init?(_ pointer: OpaquePointer?) {
        guard let pointer else { return nil }
        self.pointer = pointer
    }

    public convenience init?(unixEpoch: Int) {
        // g_date_time_new_from_unix_local_usec appears to be too new
        self.init(g_date_time_new_from_unix_local(gint64(unixEpoch)))
    }

    public convenience init?(
        timeZone: GTimeZone,
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        second: Double
    ) {
        self.init(
            g_date_time_new(
                timeZone.pointer,
                gint(year),
                gint(month),
                gint(day),
                gint(hour),
                gint(minute),
                second
            )
        )
    }

    /// Create a GDateTime in the user's current timezone from a Foundation Date, discarding
    /// fractional seconds.
    /// Falls back to UTC when the local-time constructor fails.
    ///
    /// `g_date_time_new_from_unix_local` needs GLib to resolve the local time
    /// zone and returns NULL when it cannot. This is an `init!`, so a NULL there
    /// produced a nil that trapped at the first use -- which on Windows meant
    /// P11 dying with `Illegal instruction` immediately after its view tree was
    /// built, with no message, no event log entry and an exit code of 0. Every
    /// other app in the sweep ran; removing the single `DatePicker` from P11
    /// made it run too.
    ///
    /// UTC is wrong by the machine's offset, which is visible and can be
    /// reported. A trap is neither.
    ///
    /// 當本地時間的建構函式失敗時，回退為 UTC。
    ///
    /// `g_date_time_new_from_unix_local` 需要 GLib 解析本地時區，無法解析時會回傳 NULL。由於
    /// 此處是 `init!`，該 NULL 會產生一個在首次使用時即觸發 trap 的 nil——在 Windows 上，這表現
    /// 為 P11 於 view tree 建構完成後隨即以 `Illegal instruction` 結束，沒有訊息、事件記錄中沒有
    /// 任何項目、結束碼為 0。該次掃描中其他每一支 app 都能執行；而把 P11 中唯一的 `DatePicker`
    /// 移除後，它也能執行了。
    ///
    /// UTC 會有相當於本機時差的偏移，但那是看得見、也可被回報的；trap 兩者皆非。
    public convenience init!(_ date: Date) {
        // The C functions directly, not through GDateTime(unixEpoch:). Wrapping
        // the local attempt in a temporary object would have that object unref
        // the pointer when it deinits, so the survivor would need a matching
        // ref -- a dance with nothing to gain when the call is one line.
        // 直接呼叫 C 函式，而非經由 GDateTime(unixEpoch:)。若以暫時物件包裝本地時間的嘗試，
        // 該物件解構時會 unref 該指標，因而必須另行補上對應的 ref——在呼叫本身只有一行的情況
        // 下，這種周旋毫無收穫。
        let epoch = gint64(date.timeIntervalSince1970)

        if let local = g_date_time_new_from_unix_local(epoch) {
            self.init(local)
            return
        }

        // UTC rather than nil. The offset is wrong by the machine's time zone,
        // which is visible on screen and can be reported; a trap is neither.
        // 回退為 UTC 而非 nil。其偏移量等同於本機時區，這在畫面上看得見、也可被回報；
        // 而 trap 兩者皆非。
        print("Gtk: g_date_time_new_from_unix_local returned NULL, using UTC")
        guard let utc = g_date_time_new_from_unix_utc(epoch) else {
            return nil
        }
        self.init(utc)
    }

    deinit {
        g_date_time_unref(pointer)
    }

    public func toDate() -> Date {
        let offset = g_date_time_to_unix(pointer)
        return Date(timeIntervalSince1970: Double(offset))
    }
}
