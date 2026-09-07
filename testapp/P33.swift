import DefaultBackend
import Foundation
import SwiftCrossUI

// P33 missing views: compileable approximations beside the missing SwiftUI names.

enum P33Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P33] \(message)")
        let data = Data("P33 \(Date()) \(message)\n".utf8)
        // SCUI_DEBUG_EVENTS_DIR when a launcher sets it, so every app's log lands
        // in one place; unset, the launch directory exactly as before. The
        // contract is documented in testapp/test_support/test_common.zsh.
        // 有 SCUI_DEBUG_EVENTS_DIR 時取自該變數，讓每支 app 的 log 集中一處；未設定時仍為啟動
        // 目錄，行為與過去完全相同。該約定記載於 testapp/test_support/test_common.zsh。
        let url = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
            ?? FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p33-debug-events.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    static func renderComplete() {
        guard !didAnnounceRender else { return }
        didAnnounceRender = true
        write("RENDER COMPLETE -- P33 ready for missing-view checks")
    }
}

@main
@HotReloadable
struct P33MissingViewsApp: App {
    var body: some Scene {
        WindowGroup("P33 missing views") {
            #hotReloadable {
                P33RootView()
            }
        }
        .defaultSize(width: 820, height: 620)
    }
}

struct P33RootView: View {
    @State var stepperValue = 0
    @State var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("P33: missing views")
                .font(.system(size: 20))
            Text("backend -> \(String(describing: DefaultBackend.self))")
            // These two lines were a list of nine missing names until 2026-09-04,
            // when seven of them were implemented. They are now the record of
            // what P33 was FOR, and the two that are still absent. P46 exercises
            // the real views; P33 keeps the hand-built shapes beside them so the
            // approximation and the implementation can be compared.
            //
            // The wording was NOT trimmed to fit. Every string here is a
            // different length from what it replaced, so P33-hide-details.csv's
            // measured coordinates had to be re-measured in the same change --
            // shortening a wrapped line lifts everything below it, and a click
            // that then lands on empty space raises nothing and still reports a
            // pass.
            //
            // 這兩行在 2026-09-04 之前是一份「九個缺失名稱」的清單，當天其中七個被實作了。它們現在
            // 記錄的是 P33 當初的用途，以及仍然缺席的那兩個。P46 演練真正的 view；P33 則保留手工搭出
            // 的形狀放在旁邊，使近似做法與實作可以互相對照。
            //
            // 措辭**並未**為了遷就版面而修剪。此處每個字串的長度都與被取代者不同，因此
            // P33-hide-details.csv 的量測座標必須在同一次改動中重新量測——縮短一行換行文字會把它
            // 下方的一切往上抬，而屆時落在空白處的點擊不會引發任何東西，卻仍會回報通過。
            Text("Hand-built shapes, kept for comparison. The real views now exist -- see P46.")

            Text("Still missing: Label(systemImage:) and ColorPicker. Both need backend work, not composition.")
                .font(.system(size: 13))

            Divider()
            Text("Stepper approximation")
            HStack(spacing: 8) {
                Button("-") { stepperValue -= 1 }
                Text("value \(stepperValue)")
                Button("+") { stepperValue += 1 }
            }

            Text("DisclosureGroup approximation")
            Button(expanded ? "Hide details" : "Show details") {
                expanded.toggle()
                // Names the new value, so an action file has something better
                // than a picture to check. Added 2026-09-04: the Windows action
                // file for this button had to rest on the capture alone, and an
                // unchanged log after a click is then expected rather than
                // evidence -- the two are indistinguishable without this line.
                // 指出新的值，使動作檔有比截圖更可靠的東西可以檢查。2026-09-04 新增：此按鈕的
                // Windows 動作檔原本只能依靠擷圖，而在那種情況下「點擊後 log 沒有變化」是預期
                // 行為而非證據——少了這一行，兩者無從分辨。
                P33Diagnostics.write("details expanded=\(expanded)")
            }
            if expanded {
                Text("Details are plain conditional content, not a DisclosureGroup.")
            }

            Text("LabeledContent approximation")
            HStack(spacing: 12) {
                Text("Label")
                Text("Value")
            }
        }
        .padding(18)
        .onAppear {
            P33Diagnostics.write("backend \(String(describing: DefaultBackend.self))")
            // A log line is a claim like any other, and this one was false from
            // the moment the seven views landed. It is inside .onAppear rather
            // than on screen, which is exactly why it would have gone on being
            // read as current: nothing shows it to anyone until they grep.
            // 一行 log 與其他任何陳述一樣是一項主張，而這一行自那七個 view 落地的那一刻起就是假的。
            // 它位於 .onAppear 之內而非畫面上，這正是它會被繼續當成現況讀下去的原因：在有人 grep
            // 之前，沒有任何東西會把它呈現給任何人。
            P33Diagnostics.write("still missing Label(systemImage:) ColorPicker -- the other seven are implemented, see P46")
            P33Diagnostics.renderComplete()
        }
    }
}
