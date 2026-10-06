import DefaultBackend
import Foundation
import SwiftCrossUI

// P78: does `.onOpenURL` hear the URL an app is opened with, and the ones sent
// to it while it runs?
//
// The number was checked: `ls testapp` gives P0..P77.
//
// **The screen shows every URL received, with a count, not just the last.** A
// handler that fired twice for one URL, or once for two, would look correct
// with only the last one shown. On Android the two cases come from different
// places -- the launch intent, and `onNewIntent` -- so both must be sent:
//
//     adb shell am force-stop dev.swiftcrossui.testapp.p78
//     adb shell am start -a android.intent.action.VIEW \
//         -d scui-testapp://launch dev.swiftcrossui.testapp.p78
//     (then, with the app in front)
//     adb shell am start -a android.intent.action.VIEW \
//         -d scui-testapp://running dev.swiftcrossui.testapp.p78
//
// `scui-testapp` is the scheme Bundler.android.toml declares for every test app.
//
// Expected: "received 2", launch then running. Written 2026-10-06, when
// AndroidBackend gained `BackendFeatures.IncomingURLs`.
//
// P78:`.onOpenURL` 是否收得到 app 被開啟時帶的 URL,以及執行中送來的 URL?
//
// 編號查過:`ls testapp` 給出 P0..P77。
//
// **畫面顯示收到的每一個 URL 與計數，而不只最後一個。** 一個對同一 URL 觸發兩次、或對兩個 URL 只觸發一次的
// 處理器，只顯示最後一個時看起來都對。在 Android 上兩種情況來自不同地方——啟動 intent 與 `onNewIntent`——
// 所以兩者都要送。預期：「received 2」,先 launch 再 running。2026-10-06 撰寫，當時 AndroidBackend 加入了
// `BackendFeatures.IncomingURLs`。

enum P78Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P78] \(message)")

        guard let data = "P78 \(Date()) \(message)\n".data(using: .utf8) else { return }
        let url = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
                ?? FileManager.default.currentDirectoryPath
        )
        .appendingPathComponent("p78-debug-events.log")
        if FileManager.default.fileExists(atPath: url.path),
            let handle = try? FileHandle(forWritingTo: url)
        {
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
        write("RENDER COMPLETE -- P78 ready for incoming URLs")
    }
}

@main
@HotReloadable
struct P78IncomingURLsApp: App {
    var body: some Scene {
        WindowGroup("P78 incoming URLs") {
            #hotReloadable {
                P78RootView()
            }
        }
        .defaultSize(width: 560, height: 360)
    }
}

struct P78RootView: View {
    @State var received: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("P78: incoming URLs")
                .font(.system(size: 18))
            Text("backend -> \(String(describing: DefaultBackend.self))")
            Text("received \(received.count)")
            ForEach(Array(received.enumerated()), id: \.offset) { item in
                Text("\(item.offset + 1). \(item.element)")
            }
            Text("Expected after a launch link and a second link: received 2, in that order.")
            Text("預期：一個啟動連結再加第二個連結之後:received 2,依此順序。")
        }
        .padding(16)
        .onOpenURL { url in
            received.append(url.absoluteString)
            P78Diagnostics.write("received \(received.count): \(url.absoluteString)")
        }
        .onAppear {
            P78Diagnostics.renderComplete()
        }
    }
}
