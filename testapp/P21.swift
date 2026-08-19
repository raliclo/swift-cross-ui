import DefaultBackend
import Foundation
import SwiftCrossUI

// P21 input controls, for comparing WinUIBackend against GtkBackend.
//
// The widest uncovered surface. ToggleSwitch, ToggleButton and Checkbox appear
// in no other test app at all, and the rest are only touched incidentally by
// apps aimed at something else.
//
// Every control appears twice, enabled and disabled. Disabled is where backends
// usually part company: one greys the label, another dims the whole widget, a
// third leaves it looking live and simply ignores input. That last case is the
// one worth catching, because it looks correct in a screenshot.
//
// ContentUnavailableView is folded in here rather than given its own app; its
// surface is one view and it would not fill one.
//
// P21 輸入控制項，用於比較 WinUIBackend 與 GtkBackend。
//
// 目前未涵蓋範圍中最廣的一塊。ToggleSwitch、ToggleButton 與 Checkbox 完全沒有出現在任何
// 其他測試 app 中，其餘幾項也只是被以其他目的為主的 app 順帶碰到。
//
// 每個控制項都出現兩次：啟用與停用。停用狀態正是各 backend 最容易分歧之處：有的把標籤變灰、
// 有的讓整個 widget 變暗、也有的外觀完全不變而僅忽略輸入。最後一種最值得抓出來，因為它在
// 截圖上看起來完全正確。
//
// ContentUnavailableView 併入此處而非另闢一支 app；它只有一個視圖，不足以獨立成篇。
//
// Build this file as a standalone app target.

enum P21Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P21] \(message)")

        guard let data = "P21 \(Date()) \(message)\n".data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p21-debug-events.log")
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
        write("RENDER COMPLETE -- P21 ready for input control checks")
    }
}

@main
@HotReloadable
struct P21InputControlsApp: App {
    var body: some Scene {
        WindowGroup("P21 input controls") {
            #hotReloadable {
                P21RootView()
            }
        }
        .defaultSize(width: 820, height: 720)
    }
}

struct P21RootView: View {
    @State var toggleState = false
    @State var switchState = true
    @State var buttonToggleState = false
    @State var checkboxState = false
    @State var sliderValue = 0.4
    @State var text = "editable"
    @State var secret = "hunter2"
    @State var editorText = "multi-line\ntext"
    @State var clicks = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Split into groups because a ViewBuilder takes at most 20
                // children and this screen has 34. Grouping by control family
                // is also how the sections read.
                // 分組是因為 ViewBuilder 最多接受 20 個子視圖，而本畫面有 34 個。依控制項
                // 類別分組，也正好符合各段落的閱讀方式。
                Text("P21: input controls")
                    .font(.system(size: 20))

                Text("backend -> \(String(describing: DefaultBackend.self))")

                Text(
                    "Each control appears enabled then disabled. Compare both "
                        + "states across backends, and check that a disabled "
                        + "control actually refuses input rather than only looking "
                        + "disabled."
                )

                Divider()

                // Buttons. The click counter is what proves a disabled button
                // refuses input: if the second button raises it, the disable is
                // cosmetic.
                // 按鈕。點擊計數器可證明停用的按鈕確實拒絕輸入：若第二個按鈕會使計數增加，
                // 表示該停用只是外觀上的。
                Group {
                Text("Button — clicks: \(clicks)")
                HStack(spacing: 10) {
                    Button("Enabled") { clicks += 1 }
                    Button("Disabled") { clicks += 1 }
                        .disabled(true)
                }

                Divider()

                Text("Toggle — \(toggleState)")
                HStack(spacing: 10) {
                    Toggle("Enabled", isOn: $toggleState)
                    Toggle("Disabled", isOn: $toggleState).disabled(true)
                }

                Text("ToggleSwitch style — \(switchState)")
                HStack(spacing: 10) {
                    Toggle("Enabled", isOn: $switchState).toggleStyle(.switch)
                    Toggle("Disabled", isOn: $switchState)
                        .toggleStyle(.switch)
                        .disabled(true)
                }

                Text("Toggle button style — \(buttonToggleState)")
                HStack(spacing: 10) {
                    Toggle("Enabled", isOn: $buttonToggleState).toggleStyle(.button)
                    Toggle("Disabled", isOn: $buttonToggleState)
                        .toggleStyle(.button)
                        .disabled(true)
                }

                Text("Checkbox style — \(checkboxState)")
                HStack(spacing: 10) {
                    Toggle("Enabled", isOn: $checkboxState).toggleStyle(.checkbox)
                    Toggle("Disabled", isOn: $checkboxState)
                        .toggleStyle(.checkbox)
                        .disabled(true)
                }

                Divider()

                // `init(value:in:)`. The `minimum:`/`maximum:` form is
                // deprecated and takes an unlabelled first argument, which is
                // what the earlier attempt here got wrong.
                // 使用 `init(value:in:)`。`minimum:`/`maximum:` 的形式已標記淘汰，且其第一個
                // 引數無標籤，先前此處正是寫錯了這一點。
                }

                Group {
                Text("Slider — \(String(format: "%.2f", sliderValue))")
                Slider(value: $sliderValue, in: 0...1)
                Slider(value: $sliderValue, in: 0...1).disabled(true)

                // The determinate form needs a label; the label-less
                // initialisers are the spinner and one taking a `Progress`.
                // 確定進度的形式需要標籤；無標籤的建構式只有轉圈指示器，以及接受 `Progress`
                // 的那一個。
                Text("ProgressView, same value")
                ProgressView(Text("determinate"), value: sliderValue)
                Text("ProgressView, indeterminate")
                ProgressView()

                Divider()

                Text("TextField — \(text)")
                TextField("Type here", text: $text)
                TextField("Disabled", text: $text).disabled(true)

                Text("SecureField")
                SecureField("Password", text: $secret)

                Text("TextEditor")
                TextEditor(text: $editorText)
                    .frame(height: 70)

                Divider()

                // Every part is a view builder; there is no string convenience.
                // 各部分皆為 view builder，並沒有接受字串的簡便形式。
                Text("ContentUnavailableView")
                ContentUnavailableView {
                    Text("Nothing here")
                } description: {
                    Text("The description line")
                }
                .frame(height: 110)
                }
            }
            .padding(18)
        }
        .onAppear {
            P21Diagnostics.write("backend \(String(describing: DefaultBackend.self))")
            P21Diagnostics.renderComplete()
        }
    }
}
