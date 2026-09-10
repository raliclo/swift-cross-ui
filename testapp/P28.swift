import DefaultBackend
import Foundation
import SwiftCrossUI

// P28 macOS hit-testing: a disabled overlay must let clicks reach the button
// underneath it. This covers AppKitBackend's allowsHitTesting implementation.
//
// P28 macOS hit-testing：停用的 overlay 必須讓點擊穿透至下方按鈕。本 app 覆蓋
// AppKitBackend 的 allowsHitTesting 實作。

enum P28Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P28] \(message)")
        let data = Data("P28 \(Date()) \(message)\n".utf8)
        // SCUI_DEBUG_EVENTS_DIR when a launcher sets it, so every app's log lands
        // in one place; unset, the launch directory exactly as before. The
        // contract is documented in testapp/test_support/test_common.zsh.
        // 有 SCUI_DEBUG_EVENTS_DIR 時取自該變數，讓每支 app 的 log 集中一處；未設定時仍為啟動
        // 目錄，行為與過去完全相同。該約定記載於 testapp/test_support/test_common.zsh。
        let url = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
            ?? FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p28-debug-events.log")
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
        write("RENDER COMPLETE -- P28 ready for hit-testing checks")
    }
}

@main
@HotReloadable
struct P28HitTestingApp: App {
    var body: some Scene {
        WindowGroup("P28 hit testing") {
            #hotReloadable {
                P28RootView()
            }
        }
        .defaultSize(width: 680, height: 420)
    }
}

struct P28RootView: View {
    @State var clicks = 0

    /// When the button's action ran, so the body can say how long it waited.
    ///
    /// **Reported 2026-09-10: about a second passes between the click and the
    /// number changing.** A stopwatch held by a person cannot separate the three
    /// things that could be slow -- the event reaching the button, the state
    /// change reaching the body, and the body reaching the screen -- so this
    /// stamps the first and the body prints the gap to the second. What is left
    /// unmeasured is the backend's commit, which is the part after the body.
    ///
    /// A `static` rather than an instance property: this view is reconstructed
    /// on every update, so an instance value would be reset by the very update
    /// being measured.
    ///
    /// 按鈕的 action 執行的時刻，好讓 body 說出它等了多久。
    ///
    /// **2026-09-10 回報：從點擊到數字改變，大約要一秒。** 人手持碼錶分不出三件可能很慢的事
    /// ——事件抵達按鈕、狀態改變抵達 body、body 抵達螢幕——因此此處記下第一個時刻，並由 body 印出
    /// 到第二個時刻的間隔。未被量到的是 backend 的 commit，也就是 body 之後的那一段。
    ///
    /// 使用 `static` 而非實例屬性：這個 view 在每次更新時都會被重新建構，因此實例上的值會被
    /// 「正在被量測的那一次更新」本身重設掉。
    nonisolated(unsafe) static var lastClickAt: Double?

    /// How long the body waited after the click, in words.
    /// body 在該次點擊之後等了多久，以文字表示。
    static func latencyDescription() -> String {
        guard let lastClickAt else { return "click latency: (no click yet)" }
        let elapsed = ProcessInfo.processInfo.systemUptime - lastClickAt
        let text = String(format: "click to body: %.0f ms", elapsed * 1000)
        P28Diagnostics.write(text)
        return text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("P28: AppKit allowsHitTesting")
                .font(.system(size: 20))
            Text("Click the visible button through the blue overlay.")
            Text("Clicks received: \(clicks)")
            // Printed from inside the body, which is the point: it runs as part
            // of the update the click caused.
            // 由 body 內部印出，而那正是重點：它是在「該次點擊所引發的更新」之中執行的。
            Text(P28RootView.latencyDescription())

            ZStack {
                Button("Clickable button underneath") {
                    Self.lastClickAt = ProcessInfo.processInfo.systemUptime
                    // The absolute uptime, so an outside observer can align its
                    // own clock with this one. A wall-clock timestamp has one
                    // second of resolution here, which cannot answer a question
                    // about half a second.
                    // 絕對的 uptime，好讓外部的觀察者能把自己的時鐘與這裡對齊。此處的牆上時鐘
                    // 時間戳解析度是一秒，回答不了「半秒」這種問題。
                    P28Diagnostics.write(
                        String(format: "click at uptime %.3f", Self.lastClickAt ?? 0)
                    )
                    clicks += 1
                    P28Diagnostics.write("underlying button clicked count=\(clicks)")
                }
                .frame(width: 300, height: 90)

                Color(red: 0.15, green: 0.35, blue: 0.85)
                    .frame(width: 300, height: 90)
                    .allowsHitTesting(false)
            }

            Text("Expected: the blue overlay stays visible and every click increments the counter.")
                .font(.system(size: 13))
        }
        .padding(18)
        .onAppear {
            P28Diagnostics.renderComplete()
        }
    }
}
