import DefaultBackend
import SwiftCrossUI

// P113: window behaviours -- windowDismissBehavior, windowResizeBehavior and
// preferredWindowMinimizeBehavior (BackendFeatures.WindowBehaviors).
//
// Both windows start not closable and not resizable, and minimizable. Each
// behaviour is a toggle in the window it applies to, and every change is
// printed, so a log shows what the backend was told and when.
//
// Pass, per platform: with "closable" off, the platform's close gesture does
// not close the window -- the close button on a desktop, Back (key or gesture)
// on Android; with "resizable" off, the user cannot resize the window; with
// "minimizable" off, the window cannot be minimized (on Android the system
// asks to pin the app). Turning a toggle back on restores the platform's
// behaviour. On Android, actions/android/P113-back.actions presses Back (`key
// back`); testapp/test_support/p113_back_android.zsh adds the back gesture.
//
// P113:視窗行為——windowDismissBehavior、windowResizeBehavior 與 preferredWindowMinimizeBehavior
// (BackendFeatures.WindowBehaviors)。
//
// 兩個視窗一開始都不可關閉、不可縮放，但可最小化。每項行為是其所屬視窗中的一個開關，每次改變都會印出，
// 所以 log 顯示 backend 被告知了什麼、在何時。
//
// 各平台的通過條件:「closable」關閉時，平台的關閉手勢不會關閉視窗——桌面上的關閉鈕、Android 上的返回(按鍵或手勢);
//「resizable」關閉時，使用者無法縮放視窗;「minimizable」關閉時，視窗無法最小化(Android 上系統會詢問是否固定 app)。
// 把開關打開即恢復平台原本的行為。Android 上由 actions/android/P113-back.actions 按返回(`key back`),
// testapp/test_support/p113_back_android.zsh 再加上返回手勢。

@main
@HotReloadable
struct P113WindowBehaviorsApp: App {
    var body: some Scene {
        WindowGroup("P113 window behaviors") {
            #hotReloadable {
                P113BehaviorPanel(name: "main")
            }
        }
        // Narrower than a phone (411 pt on the api36b AVD): a wider default size is laid out
        // as asked and scrolls sideways on Android, which put the switches off screen.
        // 比手機窄(api36b AVD 為 411 pt):較寬的預設尺寸在 Android 上會照要求排版並可橫向捲動，開關因此跑到畫面外。
        .defaultSize(width: 360, height: 420)

        Window("P113 second window", id: "p113-second") {
            #hotReloadable {
                P113BehaviorPanel(name: "second")
            }
        }
        .defaultSize(width: 360, height: 360)
        .defaultLaunchBehavior(.suppressed)
    }
}

struct P113BehaviorPanel: View {
    let name: String

    @State var closable = false
    // `--p113-resizable` starts resizable, so a window can be put in a free-form window first
    // and then made non-resizable while it is there.
    // `--p113-resizable` 讓視窗一開始可縮放，才能先放進自由視窗，再在那裡改成不可縮放。
    @State var resizable = CommandLine.arguments.contains("--p113-resizable")
    @State var minimizable = true

    @Environment(\.openWindow) var openWindow
    @Environment(\.supportsMultipleWindows) var supportsMultipleWindows

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("P113: \(name) window behaviors")
                .font(.system(size: 18))

            Toggle("closable", isOn: $closable)
            Toggle("resizable", isOn: $resizable)
            Toggle("minimizable", isOn: $minimizable)

            // Short lines: a Toggle spans the widest line, and a long one pushed the
            // switches off a phone screen.
            // 短行:Toggle 會撐滿最寬的那一行，太長的一行曾把開關推出手機螢幕外。
            Text("closable -> \(closable)")
            Text("resizable -> \(resizable)")
            Text("minimizable -> \(minimizable)")

            if name == "main" && supportsMultipleWindows {
                Button("open second window") {
                    openWindow(id: "p113-second")
                    print("[P113] asked to open p113-second")
                }
            }

            Text("Expected: closable off, closing (Back on Android) leaves it open.")
        }
        .padding(16)
        .windowDismissBehavior(closable ? .enabled : .disabled)
        .windowResizeBehavior(resizable ? .enabled : .disabled)
        .preferredWindowMinimizeBehavior(minimizable ? .enabled : .disabled)
        .onAppear { report() }
        .onChange(of: closable) { report() }
        .onChange(of: resizable) { report() }
        .onChange(of: minimizable) { report() }
    }

    func report() {
        print(
            "[P113] \(name) closable=\(closable) resizable=\(resizable) minimizable=\(minimizable)"
        )
    }
}
