import DefaultBackend
import Foundation
import SwiftCrossUI

#if canImport(UIKit)
    import UIKit
#endif

// P67: what does a screen reader hear when it lands on each of these buttons?
//
// The number is checked: `ls testapp` gives P50..P66.
//
// **FOUR BUTTON SHAPES, because the bug this app exists for was a shape bug.**
// Both Apple backends named a button by reaching for one exact subview at one
// exact index. That works for `Button("Save") {}` and silently produces nothing
// for a label wrapped in anything -- and nothing reports a missing accessibility
// name, so the failure is invisible on screen and in every test that looks at
// pixels.
//
// So the shapes are: a plain label, a label inside a padding, two texts side by
// side, and an image-only button. The first three must be named. The fourth must
// NOT be, and it is here to keep the fix honest: a fix that named it would be
// guessing, and `.accessibilityLabel(_:)` (#123) is the thing that will name it
// properly.
//
// P67:螢幕閱讀器落在這幾顆按鈕上時,各會聽到什麼?
//
// 編號是查過的:`ls testapp` 給出 P50..P66。
//
// **四種按鈕形狀,因為這支 app 所為之存在的那個缺陷,正是一個「形狀」缺陷。** 兩個 Apple backend
// 都是靠「伸手取某個精確索引上的某個精確子視圖」來為按鈕命名的。那對 `Button("Save") {}` 有效,而對
// 一個「標籤被任何東西包住」的按鈕則靜默地什麼都產不出來——而「缺少 accessibility 名稱」不會有任何
// 東西回報,因此那個失敗在畫面上看不見,在每一個「看像素」的測試裡也看不見。
//
// 因此那些形狀是:一個純標籤、一個被 padding 包住的標籤、兩段並排的文字,以及一顆純圖示按鈕。
// 前三個**必須**有名字。第四個**必須沒有**——它在這裡是為了讓這次修正保持誠實:一個會為它命名的修法
// 是在猜,而 `.accessibilityLabel(_:)`(#123)才是那個會好好為它命名的東西。

enum P67Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P67] \(message)")

        guard let data = "P67 \(Date()) \(message)\n".data(using: .utf8) else { return }
        let directory =
            ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
            ?? {
                #if os(iOS) || os(tvOS)
                    return NSHomeDirectory() + "/Documents"
                #else
                    return FileManager.default.currentDirectoryPath
                #endif
            }()
        let url = URL(fileURLWithPath: directory)
            .appendingPathComponent("p67-debug-events.log")
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
        write("RENDER COMPLETE -- P67 ready for accessibility checks")
    }
}

@main
@HotReloadable
struct P67App: App {
    var body: some Scene {
        WindowGroup("P67 accessibility names") {
            #hotReloadable {
                P67RootView()
            }
        }
        .defaultSize(width: 520, height: 400)
    }
}

/// Collected here so the NAMES CAN BE SHOWN, which on iOS is the only way to
/// read them.
///
/// The log file a test app writes lands inside the simulator's container and
/// neither the harness nor the system log picks it up -- P63 and P64 both hit
/// that. A value on screen is read by the same screenshot the harness already
/// takes.
///
/// 收集在此處，好讓那些**名字能被顯示出來**——在 iOS 上，那是讀到它們的唯一方式。
///
/// 一支測試 app 所寫的日誌檔會落在模擬器的容器裡，而 harness 與系統日誌都撿不到它——P63 與 P64 都
/// 撞上過。一個顯示在畫面上的值，由 harness 本來就會拍的那張截圖讀取。
@MainActor
final class P67Names: SwiftCrossUI.ObservableObject {
    static let shared = P67Names()
    @SwiftCrossUI.Published var summary = "not dumped yet"
}

struct P67RootView: View {
    @State var presses = 0
    @ObservedObject var names = P67Names.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("P67: accessibility names (#123)")
                .font(.system(size: 18))
            Text("backend -> \(String(describing: DefaultBackend.self))")
            Text("presses: \(presses)")
            Text(names.summary)

            Button("plain label") { presses += 1 }

            Button {
                presses += 1
            } label: {
                Text("padded label")
                    .padding(8)
            }

            Button {
                presses += 1
            } label: {
                HStack(spacing: 4) {
                    Text("two")
                    Text("texts")
                }
            }

            Button {
                presses += 1
            } label: {
                Color(red: 0.2, green: 0.5, blue: 0.9)
                    .frame(width: 24, height: 24)
            }

            Text("Expected names: plain label / padded label / two / (none)")
            Text("預期的名字:plain label / padded label / two /(無)")
        }
        .padding(20)
        .onAppear {
            P67Diagnostics.write("backend \(String(describing: DefaultBackend.self))")
            dumpNames()
            P67Diagnostics.renderComplete()
        }
    }

    /// Asks the PLATFORM what each button is called, not the framework.
    ///
    /// On UIKit the app can walk its own view tree; on AppKit the equivalent
    /// walk is `testapp/test_support/measure/ax_dump.swift`, which attaches from
    /// outside and reads the real accessibility tree rather than the view
    /// hierarchy that feeds it. Outside is the better vantage point and iOS does
    /// not offer it, so this half is in-process and says so.
    ///
    /// 去問**平台**每一顆按鈕叫什麼名字，而不是問框架。
    ///
    /// 在 UIKit 上，這支 app 可以走它自己的 view 樹;在 AppKit 上，對應的走訪是
    /// `testapp/test_support/measure/ax_dump.swift`——它從外部附著、讀的是**真正的** accessibility
    /// 樹，而不是餵養那棵樹的 view 階層。外部是比較好的觀察點，而 iOS 不提供它，因此這一半是行程內的，
    /// 並且把這件事說出來。
    func dumpNames() {
        #if canImport(UIKit)
            // Deferred one runloop turn: the buttons exist by `onAppear` but
            // their labels are attached during the same layout pass, and reading
            // in the middle of it reports the tree half-built.
            // 延後一個 runloop:那些按鈕在 `onAppear` 時已經存在，但它們的標籤是在同一次版面計算中
            // 被掛上的，而在那中途讀取，得到的是一棵建到一半的樹。
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    var found = 0
                    var collected: [String] = []
                    for window in UIApplication.shared.connectedScenes
                        .compactMap({ $0 as? UIWindowScene })
                        .flatMap(\.windows)
                    {
                        walk(window, depth: 0, found: &found, collected: &collected)
                    }
                    P67Diagnostics.write("BUTTONS FOUND \(found)")
                    P67Diagnostics.write("ACCESSIBILITY DUMPED")
                    P67Names.shared.summary =
                        "names: " + collected.map { "'\($0)'" }.joined(separator: " ")
                }
            }
        #else
            P67Diagnostics.write(
                "macOS: run testapp/test_support/measure/ax_dump.swift against this app"
            )
            P67Diagnostics.write("ACCESSIBILITY DUMPED")
        #endif
    }

    #if canImport(UIKit)
        func walk(_ view: UIView, depth: Int, found: inout Int, collected: inout [String]) {
            if let button = view as? UIControl {
                found += 1
                let name = button.accessibilityLabel ?? ""
                collected.append(name)
                P67Diagnostics.write("BUTTON name='\(name)'")
            }
            for subview in view.subviews {
                walk(subview, depth: depth + 1, found: &found, collected: &collected)
            }
        }
    #endif
}
