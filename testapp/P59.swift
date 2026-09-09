import DefaultBackend
import Foundation
import SwiftCrossUI

// P59: does @SceneStorage keep two windows apart, and does @AppStorage not?
//
// The number was checked, not guessed: `ls testapp` gives P50..P58, and nothing
// under testapp/plan or matrix_coverage mentions P59.
//
// **BOTH WRAPPERS ARE ON SCREEN AT ONCE, AND THAT IS THE WHOLE DESIGN.** A
// window showing only its own @SceneStorage value proves nothing: the value
// would look correct whether the storage were per-window or app-wide, because
// there is nothing to compare it against. So each window shows the same key
// stored both ways, side by side:
//
//     scene draft   @SceneStorage("draft")  -- must differ between windows
//     app draft     @AppStorage("draft")    -- must be identical in both
//
// Type into one window and the app row changes in BOTH windows while the scene
// row changes in ONE. A @SceneStorage that had silently fallen back to app-wide
// storage would make the two rows move together, which is visible in a single
// screenshot of two windows.
//
// WHY A SECOND WINDOW AT ALL. `@SceneStorage` is scoped by the window id that
// `WindowReference` hands to `createWindow(withDefaultSize:id:)`. With one
// window there is one id, and one id cannot demonstrate scoping. The second
// window is opened by `openWindow(id:)`, which on a backend without multiple
// windows warns and does nothing -- so on iOS and Android this app degrades to
// showing one window, and says so on screen rather than looking broken.
//
// P59:`@SceneStorage` 有沒有把兩個視窗分開,而 `@AppStorage` 有沒有不分開?
//
// 這個編號是查過的,不是猜的:`ls testapp` 給出 P50..P58,而 testapp/plan 與 matrix_coverage 底下
// 都沒有提到 P59。
//
// **兩個 wrapper 同時出現在畫面上,而那正是全部的設計。** 一個只顯示自己 `@SceneStorage` 值的視窗
// 什麼都證明不了:無論那份儲存是「每個視窗一份」還是「整個 app 一份」,那個值看起來都會是對的,因為
// 沒有東西可以拿來對照。因此每個視窗都把**同一個 key** 以兩種方式儲存並排顯示:
//
//     scene draft   @SceneStorage("draft")  —— 兩個視窗之間必須**不同**
//     app draft     @AppStorage("draft")    —— 兩個視窗之間必須**相同**
//
// 在其中一個視窗打字,app 那一列會在**兩個**視窗一起變,而 scene 那一列只有**一個**視窗會變。
// 若某個 `@SceneStorage` 靜默地退回了 app 層級的儲存,這兩列就會一起動——而那在一張「拍下兩個視窗」
// 的截圖裡看得見。
//
// 為什麼需要第二個視窗。`@SceneStorage` 的範圍,來自 `WindowReference` 交給
// `createWindow(withDefaultSize:id:)` 的那個視窗 id。只有一個視窗時就只有一個 id,而一個 id 無法
// 展示「分範圍」這件事。第二個視窗由 `openWindow(id:)` 開啟,而在不支援多視窗的 backend 上它會警告
// 並且什麼都不做——因此在 iOS 與 Android 上,這支 app 會退化成只有一個視窗,並在畫面上說出這件事,
// 而不是看起來像壞掉。

enum P59Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P59] \(message)")

        guard let data = "P59 \(Date()) \(message)\n".data(using: .utf8) else { return }
        let url = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
                ?? FileManager.default.currentDirectoryPath
        )
        .appendingPathComponent("p59-debug-events.log")
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
        write("RENDER COMPLETE -- P59 ready for scene storage checks")
    }
}

@main
@HotReloadable
struct P59SceneStorageApp: App {
    var body: some Scene {
        WindowGroup("P59 scene storage") {
            #hotReloadable {
                P59RootView(label: "window A")
            }
        }
        .defaultSize(width: 560, height: 460)

        // A second, separately identified window rather than a second instance
        // of the group. Two instances of a WindowGroup get different generated
        // ids and would demonstrate the same thing, but `openWindow(id:)` needs
        // a name to open, and a named `Window` scene is the one that has one.
        // 使用一個「另有其名」的第二視窗，而不是同一個 group 的第二個實例。WindowGroup 的兩個實例
        // 會拿到不同的生成 id、也能展示同一件事，但 `openWindow(id:)` 需要一個名字才能開啟，
        // 而具名的 `Window` scene 才有那個名字。
        Window("P59 second window", id: "p59-second") {
            #hotReloadable {
                P59RootView(label: "window B")
            }
        }
        .defaultSize(width: 560, height: 460)
        .defaultLaunchBehavior(.suppressed)
    }
}

struct P59RootView: View {
    let label: String

    /// Per window. Two windows, two drafts.
    /// 每個視窗一份。兩個視窗，兩份草稿。
    @SceneStorage("draft") var sceneDraft = ""

    /// App-wide, and deliberately under the SAME key name. The two namespaces
    /// do not collide because only the scene one is prefixed -- if they did,
    /// this app would show one value in both rows and the bug would be visible
    /// here rather than found later.
    /// 整個 app 一份，而且**刻意使用同一個 key 名稱**。兩個命名空間不會相撞，因為只有 scene 那一個
    /// 帶前綴——若它們會相撞，這支 app 會讓兩列顯示同一個值，於是那個缺陷會在此處被看見，而不是
    /// 事後才被發現。
    @AppStorage("draft") var appDraft = ""

    @Environment(\.openWindow) var openWindow
    @Environment(\.supportsMultipleWindows) var supportsMultipleWindows

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("P59: \(label)")
                .font(.system(size: 20))
            Text("backend -> \(String(describing: DefaultBackend.self))")

            Text("scene draft (@SceneStorage): \(sceneDraft.isEmpty ? "(empty)" : sceneDraft)")
            Text("app draft   (@AppStorage):   \(appDraft.isEmpty ? "(empty)" : appDraft)")

            HStack(spacing: 8) {
                Button("append A") { append("A") }
                Button("append B") { append("B") }
                Button("clear") {
                    sceneDraft = ""
                    appDraft = ""
                    P59Diagnostics.write("\(label) cleared both")
                }
            }

            if supportsMultipleWindows {
                Button("open second window") {
                    openWindow(id: "p59-second")
                    P59Diagnostics.write("asked to open p59-second")
                }
            } else {
                // Said on screen, because a missing button on a phone reads as a
                // layout problem and this is a backend capability.
                // 在畫面上說出來，因為在手機上「少了一顆按鈕」讀起來像版面問題，而這其實是 backend
                // 的能力差異。
                Text("this backend has one window; the two-window check needs a desktop backend")
            }

            Text(
                "Expected: pressing a button changes the app row in BOTH windows and the "
                    + "scene row in ONLY this one. Both rows moving together means the scene "
                    + "storage fell back to app-wide, which is the failure this app exists for."
            )
            Text(
                "預期:按下按鈕會讓 app 那一列在**兩個**視窗都改變,而 scene 那一列只有**這一個**視窗會改變。"
                    + "兩列一起動,代表 scene 儲存退回了 app 層級——而那正是這支 app 存在所要抓的失敗。"
            )
        }
        .padding(16)
        .onAppear {
            P59Diagnostics.write(
                "\(label) scene=\(sceneDraft.isEmpty ? "(empty)" : sceneDraft) "
                    + "app=\(appDraft.isEmpty ? "(empty)" : appDraft)"
            )
            P59Diagnostics.renderComplete()
        }
    }

    func append(_ suffix: String) {
        sceneDraft += suffix
        appDraft += suffix
        P59Diagnostics.write("\(label) appended \(suffix) -- scene=\(sceneDraft) app=\(appDraft)")
    }
}
