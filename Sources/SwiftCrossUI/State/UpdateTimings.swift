import Dispatch
import Foundation

/// Per-update timings for comparing one app across platforms.
///
/// Off unless `SCUI_UPDATE_STATS=1`. When on, every UI update that
/// ``Publisher/observeAsUIUpdater(backend:action:)`` runs is timed, and once
/// updates have been quiet for 1.5 s a cumulative line goes to stderr:
///
///     update-stats: count=412 median_ms=4.1 p95_ms=9.8 max_ms=31.0
///
/// Cumulative, so the last such line in a run's log is the run's total; the
/// sweeps read that one. Printed on quiet rather than at exit because Android
/// and iOS apps under test are killed, not quit, and an exit hook would never
/// run. stderr because it is the one channel every backend already carries:
/// AndroidBackend routes it to logcat, iOS runs read the app's pty, macOS logs
/// it beside the replay.
///
/// Until this existed only P52, P64 and P66 reported numbers, each its own
/// way, so a regression in any other app could only be seen, not measured.
///
/// 用來在各平台之間比較同一支 app 的每次更新耗時。除非 `SCUI_UPDATE_STATS=1`,否則關閉。開啟時，
/// ``Publisher/observeAsUIUpdater(backend:action:)`` 執行的每一次 UI 更新都會計時，更新安靜 1.5 秒後在
/// stderr 印出一行累計值。是累計值，所以一次執行的 log 中最後一行就是該次總計；sweep 讀的就是它。在安靜時
/// 印、而不是在結束時印，因為受測的 Android 與 iOS app 是被殺掉而非正常結束，結束掛勾不會執行。用 stderr,
/// 因為那是每個 backend 本來就帶得出來的管道。在這之前只有 P52、P64、P66 會回報數字，各用各的方式，因此
/// 其他 app 的退化只能用看的，量不出來。
enum UpdateTimings {
    /// `SCUI_UPDATE_STATS=1`, or `--update-stats` among the arguments for the
    /// platforms where the environment does not reach the app: an Android app
    /// is started by `am start`, and its arguments arrive as an intent extra.
    /// Read on first use, after AndroidBackend has filled in the arguments.
    /// `SCUI_UPDATE_STATS=1`,或在環境變數到不了 app 的平台上用參數 `--update-stats`:Android app 由
    /// `am start` 啟動，參數以 intent extra 傳入。第一次使用時才讀，那時 AndroidBackend 已填好參數。
    static let enabled =
        ProcessInfo.processInfo.environment["SCUI_UPDATE_STATS"] == "1"
        || CommandLine.arguments.contains("--update-stats")

    private static let lock = NSLock()
    nonisolated(unsafe) private static var samples: [Double] = []
    nonisolated(unsafe) private static var generation = 0
    nonisolated(unsafe) private static var lastReport = ProcessInfo.processInfo.systemUptime
    private static let reportQueue = DispatchQueue(label: "SwiftCrossUI.UpdateTimings")

    /// Records one update's duration in seconds and schedules the report.
    ///
    /// Reported 1.5 s after the last update, and also at most every 5 s while
    /// updates keep coming: an app that animates without pause (P64, P66) is
    /// never quiet, and would otherwise never report at all.
    ///
    /// 記下一次更新的耗時(秒),並排定回報。最後一次更新 1.5 秒後回報；更新持續不斷時，也至多每 5 秒回報一次：
    /// 不停在跑動畫的 app(P64、P66)永遠不會安靜，否則就永遠不會回報。
    static func record(_ seconds: Double) {
        guard enabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        samples.append(seconds)
        generation += 1
        let mine = generation
        let overdue = now - lastReport >= 5
        if overdue { lastReport = now }
        let sortedNow = overdue ? samples.sorted() : []
        lock.unlock()
        if overdue {
            FileHandle.standardError.write(Data((summary(of: sortedNow) + "\n").utf8))
        }
        reportQueue.asyncAfter(deadline: .now() + 1.5) {
            lock.lock()
            guard mine == generation else {
                lock.unlock()
                return
            }
            lastReport = ProcessInfo.processInfo.systemUptime
            let sorted = samples.sorted()
            lock.unlock()
            FileHandle.standardError.write(Data((summary(of: sorted) + "\n").utf8))
        }
    }

    /// The line itself, from durations sorted ascending.
    /// 那一行本身，由遞增排序的耗時算出。
    static func summary(of sorted: [Double]) -> String {
        guard !sorted.isEmpty else { return "update-stats: count=0" }
        func ms(_ seconds: Double) -> String { String(format: "%.1f", seconds * 1000) }
        func rank(_ fraction: Double) -> Double {
            sorted[min(sorted.count - 1, Int((Double(sorted.count - 1) * fraction).rounded()))]
        }
        return "update-stats: count=\(sorted.count) median_ms=\(ms(rank(0.5))) "
            + "p95_ms=\(ms(rank(0.95))) max_ms=\(ms(sorted[sorted.count - 1]))"
    }
}
