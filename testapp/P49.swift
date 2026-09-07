import DefaultBackend
import Foundation
import SwiftCrossUI

// P49 exercises the presentation modifiers of task #36.
//
// A presentation is the one kind of view whose absence is invisible from the
// call site: `.fullScreenCover(isPresented:)` on a backend that ignored it
// compiles, runs, sets the binding, and shows nothing -- and the button that
// set the binding looks like a button that did nothing. So each control here
// also writes a line into the page behind it, and the two together say whether
// the presentation appeared or only the state changed.
//
// P49 演練任務 #36 的呈現修飾詞。
//
// 呈現是「其缺席從呼叫端完全看不出來」的那一類 view:`.fullScreenCover(isPresented:)` 在一個忽略它的
// backend 上編得過、跑得動、也會設定 binding,然後什麼都不顯示——而設定該 binding 的那顆按鈕,看起來
// 就像一顆沒有作用的按鈕。因此此處每一個控制項也會在它背後的頁面上寫下一行,兩者合起來才能說出
// 「呈現出現了」還是「只有狀態改變了」。

enum P49Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P49] \(message)")
    }

    static func renderComplete() {
        guard !didAnnounceRender else { return }
        didAnnounceRender = true
        write("RENDER COMPLETE -- P49 ready for presentation checks")
    }
}

@main
@HotReloadable
struct P49PresentationApp: App {
    var body: some Scene {
        WindowGroup("P49 presentations") {
            #hotReloadable {
                P49RootView()
            }
        }
        .defaultSize(width: 780, height: 620)
    }
}

struct P49RootView: View {
    @State var coverShown = false
    @State var sheetShown = false
    @State var coverOpens = 0
    @State var coverDismissals = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("P49: presentation modifiers")
                .font(.system(size: 20))
            Text("backend -> \(String(describing: DefaultBackend.self))")

            // The counters are what make "pressed and nothing happened" legible.
            // A cover that never appears and a button that never fired look the
            // same on screen; only the count separates them.
            // 這些計數器讓「按了沒反應」變得可讀。一個從未出現的 cover 與一顆從未觸發的按鈕在畫面上
            // 完全相同,唯一能分辨它們的是計數。
            Text("cover opens: \(coverOpens), dismissals: \(coverDismissals)")
            Text("coverShown = \(coverShown), sheetShown = \(sheetShown)")

            Text("1. fullScreenCover -- must fill the window, with no drag indicator")
            Button("Show the cover") {
                coverOpens += 1
                coverShown = true
                P49Diagnostics.write("cover requested, opens=\(coverOpens)")
            }

            Text("2. sheet, for comparison -- the same content, presented as a sheet")
            Button("Show the sheet") {
                sheetShown = true
                P49Diagnostics.write("sheet requested")
            }

            Text(
                "Expected: the cover covers the whole window and the sheet does not. "
                    + "If both look the same, fullScreenCover fell back to sheet options."
            )
            Text(
                "預期:cover 覆蓋整個視窗,而 sheet 不會。若兩者看起來相同,表示 fullScreenCover "
                    + "退回了 sheet 的選項。"
            )
        }
        .padding(16)
        .fullScreenCover(
            isPresented: $coverShown,
            onDismiss: {
                coverDismissals += 1
                P49Diagnostics.write("cover dismissed, dismissals=\(coverDismissals)")
            }
        ) {
            P49PresentedContent(
                title: "FULL SCREEN COVER",
                detail: "This must fill the window. No drag indicator, no rounded corners.",
                onClose: { coverShown = false }
            )
        }
        .sheet(isPresented: $sheetShown) {
            P49PresentedContent(
                title: "SHEET",
                detail: "This is the comparison. It is presented as the backend's own sheet.",
                onClose: { sheetShown = false }
            )
        }
        .onAppear {
            P49Diagnostics.write("backend \(String(describing: DefaultBackend.self))")
            P49Diagnostics.write("modifiers fullScreenCover sheet")
            P49Diagnostics.renderComplete()
        }
    }
}

/// What both presentations show, so that the only difference between them is
/// the presentation itself.
/// 兩種呈現所顯示的內容,如此兩者之間唯一的差異就是呈現方式本身。
struct P49PresentedContent: View {
    let title: String
    let detail: String
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 22))
            Text(detail)
            Button("Close") {
                onClose()
            }
        }
        .padding(20)
    }
}
