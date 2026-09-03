import DefaultBackend
import Foundation
import SwiftCrossUI

// P5 Windows repro app:
// - #675 WinUIBackend: support displaying multiple alerts at once.
//
// Verifies that alerts on separate windows can be shown simultaneously
// (instead of queuing behind a single app-wide dialog), and that stacking
// several alerts on the same window restores each earlier alert once the
// one on top of it is dismissed.
//
// Build this file as a standalone app target.

/// Writes what happened to a file, because #675's claim is about ORDER.
///
/// `eventLog` on screen holds one line and each event overwrites the last, so a
/// capture taken at the end can only ever show the final state. The claim under
/// test is "A, then B, then C, each restored as the one above it closes" -- a
/// sequence, which a single overwritten line cannot carry and three separate
/// captures can only carry if every one of them is taken at the right moment.
///
/// Added 2026-09-04, once the synthesiser could click inside a dialog at all.
/// Before that this app could not be driven past opening an alert, and the
/// action file said so.
///
/// 把事情經過寫進檔案，因為 #675 的主張關乎**順序**。
///
/// 畫面上的 `eventLog` 只有一行，每個事件都會覆蓋前一個，因此最後所取的擷圖只能顯示最終狀態。
/// 待驗的主張是「A、然後 B、然後 C，各自在其上者關閉時還原」——那是一個**序列**，一行會被覆蓋的
/// 文字承載不了它，而三張各別的擷圖也只有在每一張都恰好取在正確時刻時才承載得了。
///
/// 2026-09-04 新增，在合成器終於能點擊對話框內部之後。在此之前，本 app 無法被驅動到「開啟
/// alert」之後的任何一步，而動作檔當時就是這麼寫的。
enum P5Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P5] \(message)")
        let data = Data("P5 \(Date()) \(message)\n".utf8)
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p5-debug-events.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}

@main
@HotReloadable
struct P5MultiWindowAlertsApp: App {
    var body: some Scene {
        WindowGroup("P5 multi-window alerts", id: "p5-main") {
            #hotReloadable {
                P5AlertWindowView(windowLabel: "Main")
            }
        }
        .defaultSize(width: 480, height: 380)

        WindowGroup("P5 secondary window", id: "p5-secondary") {
            #hotReloadable {
                P5AlertWindowView(windowLabel: "Secondary")
            }
        }
        .defaultSize(width: 480, height: 380)
        .defaultLaunchBehavior(.suppressed)
    }
}

struct P5AlertWindowView: View {
    var windowLabel: String

    @State var showAlertA = false
    @State var showAlertB = false
    @State var showAlertC = false
    @State var eventLog = "Ready."

    @Environment(\.openWindow) var openWindow

    /// The one place an event is recorded, so the screen and the log cannot
    /// disagree. Two call sites writing the same sentence twice is how a run
    /// ends up with a capture that says one thing and a log that says another,
    /// and there is no way to tell afterwards which was the truth.
    /// 記錄事件的唯一入口，使畫面與 log 不可能各說各話。同一句話由兩處分別寫出，正是「擷圖說一套、
    /// log 說另一套」的成因，而事後無從判斷哪一邊才是真的。
    func note(_ message: String) {
        eventLog = "\(windowLabel): \(message)"
        P5Diagnostics.write("\(windowLabel): \(message)")
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("P5: \(windowLabel) window")
                .font(.system(size: 18))

            Text(
                "Verifies #675 (Fixed): alerts on different windows should show at the same time instead of queuing, and alerts stacked on the same window should restore the earlier alert once the later one closes."
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Open another window") {
                openWindow(id: "p5-secondary")
            }

            HStack {
                Button("Show Alert A") {
                    note("showing Alert A")
                    showAlertA = true
                }

                Button("Show Alert B (stacks on A)") {
                    note("showing Alert B")
                    showAlertB = true
                }

                Button("Show Alert C (stacks on A+B)") {
                    note("showing Alert C")
                    showAlertC = true
                }
            }

            // Requests all three in one action, so all three isPresented are
            // true in the same update. A modal backend cannot show a second
            // alert while the first is up, so this is the only way to exercise
            // the queue from the UI: A shows, B and C wait, and each appears as
            // the one above it is dismissed.
            // 一個動作同時請求三個,使三個 isPresented 在同一次更新中皆為真。modal backend 無法在
            // 第一個顯示時再顯示第二個,因此這是從 UI 驅動佇列的唯一方式:A 顯示,B 與 C 等待,並在
            // 其上者關閉時各自出現。
            Button("Show A+B+C at once") {
                note("requesting A, B and C together")
                showAlertA = true
                showAlertB = true
                showAlertC = true
            }

            Text(eventLog)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .alert("Alert A (\(windowLabel))", isPresented: $showAlertA) {
            Button("OK") {
                note("Alert A dismissed")
            }
        }
        .alert("Alert B (\(windowLabel))", isPresented: $showAlertB) {
            Button("OK") {
                note("Alert B dismissed")
            }
        }
        .alert("Alert C (\(windowLabel))", isPresented: $showAlertC) {
            Button("OK") {
                note("Alert C dismissed")
            }
        }
    }
}
