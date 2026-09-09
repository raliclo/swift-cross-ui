import DefaultBackend
import Foundation
import SwiftCrossUI

// P60: does the Settings scene appear, and does it appear as the right thing
// on each backend?
//
// The number was checked, not guessed: `ls testapp` gives P50..P59, and nothing
// under testapp/plan or matrix_coverage mentions P60.
//
// **THE SAME BUTTON MUST PRODUCE TWO DIFFERENT PRESENTATIONS, AND BOTH ARE
// CORRECT.** `Settings` is one scene, but how it is shown is the backend's
// answer, not the app's:
//
//     AppKit, Gtk, WinUI   a separate window titled "Settings"
//     UIKit, Android       a sheet over the window that already exists
//
// That is not a fallback added for tidiness. `AndroidBackend.createWindow`
// returns a fresh `Window()` value with a `TODO` beside it, measured 2026-09-09,
// so a window-based Settings on Android would be SILENTLY INVISIBLE -- the
// press would succeed, nothing would appear, and no log would say why. CLAUDE.md
// rules that out: a truthful report of a missing feature is not the same as a
// working feature.
//
// WHAT MAKES A CAPTURE EVIDENCE HERE. The settings content carries a counter
// that only it can change, and the main window shows the same counter. So:
//
//   - the settings view being on screen proves the scene resolved
//   - pressing "+1" inside it and seeing the main window's number change proves
//     the settings view shares the app's state rather than being a fresh copy
//
// A settings screen that renders but is wired to nothing looks identical to a
// working one in a single screenshot, which is why the second half exists.
//
// P60:Settings scene 會不會出現,以及它在各個 backend 上出現的形式對不對?
//
// 這個編號是查過的,不是猜的:`ls testapp` 給出 P50..P59,而 testapp/plan 與 matrix_coverage 底下
// 都沒有提到 P60。
//
// **同一顆按鈕必須產生兩種不同的呈現,而兩種都是對的。** `Settings` 是同一個 scene,但它怎麼被顯示,
// 是由 backend 回答的、不是由 app 回答的:AppKit、Gtk、WinUI 會開一個標題為「Settings」的獨立視窗;
// UIKit 與 Android 則在既有的視窗上蓋一個 sheet。
//
// 那不是為了整齊而補的退路。`AndroidBackend.createWindow` 回傳的是一個旁邊還留著 `TODO` 的新
// `Window()` 值(2026-09-09 實測),因此 Android 上以視窗為基礎的 Settings 會**靜默地隱形**——按下去
// 會成功、什麼都不會出現、也不會有任何 log 說明原因。CLAUDE.md 排除了這種做法:如實回報一項缺失的
// 功能,與擁有一項可運作的功能,是兩回事。
//
// 什麼使此處的擷圖成為證據。設定內容帶著一個「只有它能改變」的計數器,而主視窗顯示同一個計數器。因此:
// 設定畫面出現在螢幕上,證明那個 scene 被解析了;而在其中按下「+1」並看到主視窗的數字改變,則證明
// 那個設定畫面共用著 app 的狀態,而不是一份新的副本。
//
// 一個「畫得出來、卻沒接上任何東西」的設定畫面,在單一張截圖裡與一個能運作的完全相同——後半那一項
// 正是為此而存在。

enum P60Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P60] \(message)")

        guard let data = "P60 \(Date()) \(message)\n".data(using: .utf8) else { return }
        let url = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
                ?? FileManager.default.currentDirectoryPath
        )
        .appendingPathComponent("p60-debug-events.log")
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
        write("RENDER COMPLETE -- P60 ready for settings checks")
    }
}

/// Shared by the main window and the settings scene.
///
/// A class rather than two `@State` values, because the point of the second half
/// of this test is that the settings view is not a fresh copy. Two `@State`s
/// would make it one, and the app would then pass a test of nothing.
/// 由主視窗與設定 scene 共用。
///
/// 使用 class 而非兩個 `@State` 值，因為這項測試後半的重點正是「設定畫面不是一份新的副本」。
/// 兩個 `@State` 會讓它變成一份副本，而這支 app 就會通過一個什麼都沒測到的測試。
///
/// `SwiftCrossUI.` on both names, because `Foundation` exports an
/// `ObservableObject` and a `Published` of its own and the compiler refuses the
/// bare names here: *"'ObservableObject' is ambiguous for type lookup in this
/// context"*. Qualified rather than resolved by import order, which would work
/// until someone reorders the imports.
/// 兩個名字都加上 `SwiftCrossUI.`，因為 `Foundation` 也匯出了自己的 `ObservableObject` 與
/// `Published`，而編譯器在此處拒絕裸名：*「'ObservableObject' is ambiguous for type lookup in this
/// context」*。選擇明確限定，而不是靠 import 的順序解決——後者會一直有效，直到有人調換了 import 的
/// 順序為止。
final class P60Model: SwiftCrossUI.ObservableObject {
    @SwiftCrossUI.Published var count = 0
}

@main
@HotReloadable
struct P60SettingsApp: App {
    @State var model = P60Model()

    var body: some Scene {
        WindowGroup("P60 settings scene") {
            #hotReloadable {
                P60RootView(model: model)
            }
        }
        .defaultSize(width: 620, height: 420)

        Settings {
            #hotReloadable {
                P60SettingsView(model: model)
            }
        }
    }
}

struct P60RootView: View {
    var model: P60Model

    @Environment(\.openSettings) var openSettings
    @Environment(\.supportsMultipleWindows) var supportsMultipleWindows

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("P60: settings scene")
                .font(.system(size: 20))
            Text("backend -> \(String(describing: DefaultBackend.self))")
            Text("count: \(model.count)")

            // Said on screen, because the two presentations are both correct and
            // a reader of the capture otherwise cannot tell which one was
            // expected here.
            // 寫在畫面上，因為兩種呈現都是對的，而看擷圖的人否則無從得知此處預期的是哪一種。
            Text(
                supportsMultipleWindows
                    ? "expect: settings opens in its own window"
                    : "expect: settings appears as a sheet over this window"
            )

            Button("open settings") {
                openSettings()
                P60Diagnostics.write("openSettings() called")
            }

            Text(
                "The count above is the evidence. Pressing +1 inside settings must change it "
                    + "here too -- a settings view that renders but shares nothing looks "
                    + "identical in a single screenshot."
            )
            Text(
                "上方的計數就是證據。在設定裡按下 +1,這裡的數字也必須跟著變——一個「畫得出來、卻什麼都"
                    + "沒共用」的設定畫面,在單一張截圖裡看起來完全相同。"
            )
        }
        .padding(16)
        .onAppear {
            P60Diagnostics.write(
                "root appeared, supportsMultipleWindows=\(supportsMultipleWindows)"
            )
            P60Diagnostics.renderComplete()
            // Deliberately immediate, and this is a regression check rather
            // than a convenience. A root view's `onAppear` fires BEFORE the
            // sheet host's, so this call reaches `openSettings()` while nothing
            // can yet present -- which used to log "nothing can present
            // settings" and do nothing at all, while the identical call two
            // seconds later worked. The registry now remembers the request.
            // 刻意採「立即」而非延遲，而這是一項回歸檢查、不是為了方便。root view 的 `onAppear` 會比
            // sheet host 的**先**觸發，因此這個呼叫抵達 `openSettings()` 時，還沒有任何東西能呈現
            // ——過去它會記下「nothing can present settings」然後什麼都不做，而兩秒後完全相同的呼叫
            // 卻可以運作。現在 registry 會記住那個請求。
            if CommandLine.arguments.contains("--auto-settings") {
                openSettings()
                P60Diagnostics.write("auto-opened settings (immediately)")
            }
        }
    }
}

struct P60SettingsView: View {
    var model: P60Model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("P60 settings")
                .font(.system(size: 18))
            Text("count: \(model.count)")
            Button("+1") {
                model.count += 1
                P60Diagnostics.write("settings incremented to \(model.count)")
            }
            Text("this view lives in the app's Settings scene")
        }
        .padding(16)
        .onAppear {
            P60Diagnostics.write("settings view appeared")
        }
    }
}
