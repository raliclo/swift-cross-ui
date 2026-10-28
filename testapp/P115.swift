// P115: Toggle and Link take view labels -- `Toggle(isOn:label:)` in the switch,
// checkbox and button styles, and `Link(destination:label:)` -- as in SwiftUI.
//
// Each label is two views (a coloured mark and a Text), so it is a view label
// and not a string. A string-label button toggle sits beside them for
// comparison. The Link's URL goes to an `openURL` handler installed with
// `.environment(\.openURL, OpenURLAction { ... })`, which logs it and returns
// `.handled`, so no browser opens on the test machine.
//
// The action files press each control by the text inside its label
// (`taplabel`), i.e. they click the label itself: "Switch label",
// "Checkbox label", "Button label", "Link label". Each press is logged as
// `[P115] switch -> true` and so on, and the state line on screen follows.
//
// Pass: after the replay the log has `switch -> true`, `checkbox -> true`,
// `button -> true` and `link opened p115://link-label`, in that order, and the
// final capture shows the switch and checkbox on, the button toggle filled
// with its on colour around its two-part label, and "link presses: 1".
//
// P115:Toggle 與 Link 接受 view 標籤——switch、checkbox 與按鈕樣式的 `Toggle(isOn:label:)`,以及
// `Link(destination:label:)`——與 SwiftUI 相同。每個標籤是兩個 view(一個色塊與一個 Text)。Link 的 URL 交給以
// `.environment(\.openURL, ...)` 安裝的 handler,它記錄後回傳 `.handled`,因此測試機上不會開啟瀏覽器。動作檔以標籤裡的
// 文字點擊每個控制項(`taplabel`),也就是點擊標籤本身。通過條件見上方英文說明。

import DefaultBackend
import Foundation
import SwiftCrossUI

enum P115Log {
    /// Appends a line to p115-debug-events.log and stdout.
    /// 在 p115-debug-events.log 與 stdout 加一行。
    static func write(_ line: String) {
        print("[P115] \(line)")
        let directory =
            ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
            ?? {
                #if os(iOS) || os(tvOS)
                    return NSHomeDirectory() + "/Documents"
                #else
                    return FileManager.default.currentDirectoryPath
                #endif
            }()
        let url = URL(fileURLWithPath: directory).appendingPathComponent("p115-debug-events.log")
        guard let data = "P115 \(Date()) \(line)\n".data(using: .utf8) else { return }
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
struct P115App: App {
    var body: some Scene {
        WindowGroup("P115 view labels") {
            #hotReloadable {
                P115RootView()
            }
        }
        .defaultSize(width: 480, height: 460)
    }
}

/// A small coloured square in front of a label's text.
/// 標籤文字前的一個小色塊。
struct P115Mark: View {
    var color: Color

    var body: some View {
        color.frame(width: 12, height: 12)
    }
}

struct P115RootView: View {
    @State var switchOn = false
    @State var checkboxOn = false
    @State var buttonOn = false
    @State var stringOn = false
    @State var linkPresses = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("P115: view labels on Toggle and Link")
                .font(.system(size: 16))

            Toggle(isOn: $switchOn.onChange { P115Log.write("switch -> \($0)") }) {
                HStack(spacing: 6) {
                    P115Mark(color: .blue)
                    Text("Switch label")
                }
            }
            .toggleStyle(.switch)

            Toggle(isOn: $checkboxOn.onChange { P115Log.write("checkbox -> \($0)") }) {
                HStack(spacing: 6) {
                    P115Mark(color: .green)
                    Text("Checkbox label")
                }
            }
            .toggleStyle(.checkbox)

            HStack(spacing: 12) {
                Toggle(isOn: $buttonOn.onChange { P115Log.write("button -> \($0)") }) {
                    HStack(spacing: 6) {
                        P115Mark(color: .orange)
                        Text("Button label")
                    }
                }
                .toggleStyle(.button)

                Toggle("String button", isOn: $stringOn.onChange { P115Log.write("string -> \($0)") })
                    .toggleStyle(.button)
            }

            Link(destination: URL(string: "p115://link-label")!) {
                HStack(spacing: 6) {
                    P115Mark(color: .purple)
                    Text("Link label")
                }
            }

            Text(
                "switch \(switchOn), checkbox \(checkboxOn), button \(buttonOn), "
                    + "string \(stringOn), link presses: \(linkPresses)"
            )
        }
        .padding(16)
        .environment(
            \.openURL,
            OpenURLAction { url in
                linkPresses += 1
                P115Log.write("link opened \(url.absoluteString)")
                return .handled
            }
        )
        .onAppear {
            P115Log.write("RENDER COMPLETE -- P115 ready")
        }
    }
}
