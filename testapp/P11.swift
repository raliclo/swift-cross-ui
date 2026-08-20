import DefaultBackend
import Foundation
import SwiftCrossUI

// P11 macOS (AppKitBackend) repro app: sliders, scrollbars and date pickers.
//
// - #82 Sliders jitter when two of them constrain each other. The minimum
//   slider is clamped below the maximum and vice versa, which SwiftUI absorbs
//   but AppKitBackend turns into a feedback loop.
// - #485 The scrollbar renders pointing the wrong way.
// - #473 Compact DatePicker sizing is off with Liquid Glass.
//
// #404 (window content size after View > Show Tab Bar) and #425 (window not
// focused at launch) are deliberately absent. #404 needs a menu item this app
// cannot drive from its own view tree, and #425 is described upstream as
// intermittent, so a pass/fail step would be misleading. Both are noted in the
// test plan instead.
//
// Build this file as a standalone app target.

enum P11Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P11] \(message)")

        guard let data = "P11 \(Date()) \(message)\n".data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p11-debug-events.log")
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
        write("RENDER COMPLETE -- P11 ready for #82, #485, and #473 checks")
    }
}

/// Unconditional file-based startup trace, the same instrumentation that
/// settled P7.
///
/// P11 dies with `Illegal instruction` on Windows/GtkBackend and runs fine on
/// Linux/GtkBackend, and on Windows nothing else survives: stdout and stderr
/// reach nobody, the event log records no application error, and the exit code
/// of a GUI-subsystem binary is 0 either way. Which of these lines appears says
/// how far it got.
///
/// 無條件、以檔案為基礎的啟動追蹤，與解決 P7 時所用的相同機制。
///
/// P11 在 Windows/GtkBackend 上以 `Illegal instruction` 結束，在 Linux/GtkBackend 上卻正常執行；
/// 而在 Windows 上其他證據一概留不下來：stdout 與 stderr 無人收到、事件記錄中沒有任何應用程式
/// 錯誤，且 GUI subsystem 執行檔無論成敗結束碼都是 0。此處哪幾行出現，即說明它進行到哪一步。
enum P11Startup {
    static func trace(_ stage: String) {
        let line = "P11 \(Date()) startup: \(stage)\n"
        guard let data = line.data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p11-startup.log")
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
}

@main
@HotReloadable
struct P11AppKitSizingApp: App {
    init() {
        P11Startup.trace("App.init")
    }

    // No trace in `body`. Putting one there broke P7 completely: the same
    // pattern -- a statement before an explicit `return` -- left its window
    // blank except for a single small box, with not even the title text
    // rendering, and it was reported as a severe backend defect before being
    // traced back to the trace itself. `body` is a result-builder property and
    // adding a statement to it changes how it is built, so it is not a free
    // place to observe from.
    //
    // `init` is safe and is where the one surviving trace lives.
    //
    // body 中不放追蹤。把追蹤放進 body 曾把 P7 完全弄壞：同樣的模式——在明確的 `return` 之前
    // 加入一道陳述式——使其視窗除了一個小方塊之外一片空白，連標題文字都沒有繪製，並且在被追溯到
    // 追蹤本身之前，一度被回報為嚴重的 backend 缺陷。`body` 是 result-builder 屬性，往其中加入
    // 陳述式會改變它的建構方式，因此它並不是一個可以隨意觀察的位置。
    //
    // `init` 是安全的，也是唯一保留的追蹤所在之處。
    var body: some Scene {
        WindowGroup("P11 sliders, scrollbars and pickers") {
            #hotReloadable {
                P11RootView()
            }
        }
        .defaultSize(width: 760, height: 620)
    }
}

struct P11RootView: View {
    // The two values constrain each other exactly as RandomNumberGeneratorExample
    // does, which is what #82 reports as jittering.
    @State var minimum = 0.0
    @State var maximum = 100.0

    // Counts how often each binding is written. A clean drag should move one of
    // them monotonically; a feedback loop shows up as both climbing together
    // while the values themselves barely change.
    @State var minimumWrites = 0
    @State var maximumWrites = 0

    @State var date = Date()
    @State var status = "Ready. Drag a slider past the other to test #82."

    /// What the active backend actually offers. Read rather than assumed, for
    /// the reason spelled out at the DatePicker below.
    /// 目前 backend 實際提供的項目。採取讀取而非假設，理由詳見下方 DatePicker 處的說明。
    @Environment(\.supportedDatePickerStyles) var supportedDatePickerStyles

    var body: some View {
        VStack(spacing: 14) {
            Text("P11: AppKitBackend sliders, scrollbars and pickers")
                .font(.system(size: 20))

            Text(status)
                .frame(width: 700, alignment: .leading)

            // ---- #82 -------------------------------------------------------
            VStack(alignment: .leading, spacing: 6) {
                Text("Mutually clamped sliders (#82)")

                Text(
                    "minimum \(Int(minimum))  /  maximum \(Int(maximum))"
                        + "   writes: min \(minimumWrites), max \(maximumWrites)"
                )

                Slider(
                    value: $minimum.onChange { value in
                        minimumWrites += 1
                        // The clamp that upstream reports as the trigger.
                        if value > maximum {
                            minimum = maximum
                        }
                    },
                    in: 0...100
                )
                .frame(width: 700)

                Slider(
                    value: $maximum.onChange { value in
                        maximumWrites += 1
                        if value < minimum {
                            maximum = minimum
                        }
                    },
                    in: 0...100
                )
                .frame(width: 700)

                HStack(spacing: 10) {
                    Button("Reset counters") {
                        minimumWrites = 0
                        maximumWrites = 0
                        status = "Counters reset. Drag one slider past the other."
                    }

                    Button("Separate them") {
                        minimum = 20
                        maximum = 80
                        status = "Sliders separated; neither clamp is active."
                    }

                    Button("Collide them") {
                        minimum = 50
                        maximum = 50
                        status = "Both at 50: any further drag hits the clamp."
                    }
                }
            }

            // ---- #485 ------------------------------------------------------
            VStack(alignment: .leading, spacing: 6) {
                Text("Scrollbar direction (#485)")

                // Tall content in a short frame, so the vertical scrollbar has a
                // small thumb near the top: easy to see which way it points.
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(1...40), id: \.self) { index in
                            Text("Row \(index) of 40")
                        }
                    }
                    .padding(6)
                }
                .frame(width: 340, height: 130)
            }

            // ---- #473 ------------------------------------------------------
            VStack(alignment: .leading, spacing: 6) {
                Text("Compact DatePicker sizing (#473)")

                HStack(spacing: 10) {
                    // The issue names the compact style specifically. AppKitBackend
                    // currently maps .automatic and .compact to the same
                    // NSDatePicker style, so this is explicit for the sake of the
                    // repro rather than because it changes anything today.
                    // Bisecting the Windows/GtkBackend crash. P11 reaches
                    // App.init, App.body and RootView.body and then dies with
                    // Illegal instruction while the view tree is turned into
                    // widgets, so the fault is in one of these subviews. Pass
                    // -no-datepicker to take this one out of the tree.
                    // 用於二分 Windows/GtkBackend 上的崩潰。P11 會到達 App.init、App.body 與
                    // RootView.body，隨後在 view tree 轉換為 widget 的過程中以 Illegal
                    // instruction 結束，因此問題出在其中某個子視圖。傳入 -no-datepicker 可將
                    // 此項自樹中移除。
                    // Asks the backend before requesting the style.
                    //
                    // `.compact` killed this app on Windows/GtkBackend and left
                    // it fine on Linux/GtkBackend, which looked like a platform
                    // difference and was not. GtkBackend supports
                    // `[.automatic, .graphical]`, and `datePickerStyle` calls
                    // `assertionFailure` before falling back to `.automatic`.
                    // An assertion traps in a debug build and is a no-op in
                    // release -- and this project builds debug on Windows and
                    // release on Linux. Same code, same backend; our own build
                    // configuration decided whether it was fatal.
                    //
                    // An app cannot know at compile time which styles a backend
                    // has, so asking is what a real one does. The `.compact`
                    // request is still made wherever it is available, which is
                    // what #473 is about.
                    //
                    // 在請求該樣式之前先詢問 backend。
                    //
                    // `.compact` 使本 app 在 Windows/GtkBackend 上死亡，在 Linux/GtkBackend 上
                    // 卻正常，看起來像平台差異，實則不然。GtkBackend 支援的是
                    // `[.automatic, .graphical]`，而 `datePickerStyle` 會先呼叫
                    // `assertionFailure`，之後才回退為 `.automatic`。assertion 在 debug build
                    // 會 trap，在 release build 則是空操作——而本專案在 Windows 上建 debug、
                    // 在 Linux 上建 release。相同的程式碼、相同的 backend；決定它是否致命的是
                    // 我們自己的建置組態。
                    //
                    // app 無法在編譯期得知某個 backend 支援哪些樣式，因此「詢問」才是真實 app
                    // 的做法。在支援之處仍會請求 `.compact`，而那正是 #473 所要測試的。
                    if supportedDatePickerStyles.contains(.compact) {
                        DatePicker("Pick a date", selection: $date)
                            .datePickerStyle(.compact)
                    } else {
                        DatePicker("Pick a date", selection: $date)
                    }

                    // A plain button as a height reference: the picker should
                    // not be visibly taller or shorter than neighbouring
                    // controls, and should not clip its own text.
                    Button("Reference") {
                        status = "Reference button height is the comparison baseline."
                    }
                }
                .frame(width: 700, alignment: .leading)
            }
        }
        .padding(18)
        .onAppear {
            P11Diagnostics.renderComplete()
        }
    }
}
