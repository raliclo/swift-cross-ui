import DefaultBackend
import Foundation
import SwiftCrossUI

// P18 file dialogs, for comparing WinUIBackend against GtkBackend.
//
// GtkBackend moved from GtkFileChooserNative, which the GIR marks
// deprecated="1", to GtkFileDialog. The old API also failed to close its dialog
// on Wayland when no xdg-desktop-portal was installed, as under WSLg: the
// response arrived and the app received the file, but the window stayed on
// screen. A stock GTK4 app using GtkFileDialog closed correctly in the same
// session, which is what identified the API rather than our use of it.
//
// The migration rewrote four code paths and only one of them, a plain single
// file open, had ever been executed. This app exists to run the rest.
//
// Modelled on the GTK4 demos in the sense that each control does one thing and
// reports what came back, rather than being part of a larger scenario. What is
// interesting here is the comparison: the same build under both backends should
// return the same kind of result for the same action.
//
// What it cannot cover: multiple selection. GtkBackend has a code path for it,
// but PresentSingleFileOpenDialogAction hardcodes allowMultipleSelections to
// false, so no app can reach it through the public API. That branch stays
// untested until either the action gains the option or a backend-level test
// exists.
//
// P18 檔案對話框，用於比較 WinUIBackend 與 GtkBackend。
//
// GtkBackend 已從 GIR 標記 deprecated="1" 的 GtkFileChooserNative 遷移至
// GtkFileDialog。舊 API 在未安裝 xdg-desktop-portal 的 Wayland（例如 WSLg）下還有一個
// 實際缺陷：response 有送出、app 也收到了檔案，但對話框視窗不會離開畫面。同一個工作階段
// 中，使用 GtkFileDialog 的原生 GTK4 app 卻能正常關閉——這正是判定問題出在 API 本身而非
// 我們用法的依據。
//
// 該遷移改寫了四條程式路徑，而其中只有「單檔開啟」執行過。本 app 的存在就是為了跑其餘幾條。
//
// 形式上參考 GTK4 的官方範例：每個控制項只做一件事並回報結果，而不是構成一個較大的情境。
// 此處真正有意義的是對照——同一份建置在兩個 backend 下，對同一個動作應回傳同一類結果。
//
// 無法涵蓋的部分：多重選取。GtkBackend 有對應的程式路徑，但
// PresentSingleFileOpenDialogAction 將 allowMultipleSelections 寫死為 false，因此任何
// app 都無法經由公開 API 觸達。該分支在該 action 提供選項、或出現 backend 層級測試之前，
// 都將維持未測狀態。
//
// Build this file as a standalone app target.

enum P18Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P18] \(message)")

        guard let data = "P18 \(Date()) \(message)\n".data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p18-debug-events.log")
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

    // Logged in one shape for every dialog so the two backends' logs can be
    // diffed directly rather than read side by side.
    // 所有對話框以同一格式記錄，讓兩個 backend 的日誌可直接 diff，而非逐項對照閱讀。
    static func result(_ dialog: String, _ url: URL?) {
        write("\(dialog): \(url.map { "selected \($0.path)" } ?? "cancelled")")
    }

    static func renderComplete() {
        guard !didAnnounceRender else { return }
        didAnnounceRender = true
        write("RENDER COMPLETE -- P18 ready for file dialog checks")
    }
}

@main
@HotReloadable
struct P18FileDialogsApp: App {
    var body: some Scene {
        WindowGroup("P18 file dialogs") {
            #hotReloadable {
                P18RootView()
            }
        }
        .defaultSize(width: 720, height: 520)
    }
}

struct P18RootView: View {
    @Environment(\.chooseFile) var chooseFile
    @Environment(\.chooseFileSaveDestination) var chooseFileSaveDestination

    @State var lastOpen = "nothing yet"
    @State var lastFolder = "nothing yet"
    @State var lastSave = "nothing yet"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("P18: file dialogs")
                .font(.system(size: 20))

            Text(
                "Each button opens one dialog and reports what came back. "
                    + "The dialog closing is itself part of the result."
            )

            // Single file open. This is the one path the migration had already
            // been run through, kept here so all three sit in one place.
            // 單檔開啟。這是遷移後唯一執行過的路徑，放在此處讓三者集中於一處。
            VStack(alignment: .leading, spacing: 4) {
                Button("Open a file") {
                    Task {
                        let url = await chooseFile(
                            title: "P18: choose any file",
                            defaultButtonLabel: "Open"
                        )
                        lastOpen = url?.path ?? "cancelled"
                        P18Diagnostics.result("open", url)
                    }
                }
                Text("open -> \(lastOpen)")
            }

            // Directory selection. GtkBackend routes this to
            // gtk_file_dialog_select_folder, a different call from the file
            // open, and one that had never been executed.
            // 目錄選取。GtkBackend 會導向 gtk_file_dialog_select_folder，與檔案開啟是不同
            // 的呼叫，且從未被執行過。
            VStack(alignment: .leading, spacing: 4) {
                Button("Choose a folder") {
                    Task {
                        let url = await chooseFile(
                            title: "P18: choose a folder",
                            defaultButtonLabel: "Select",
                            allowSelectingFiles: false,
                            allowSelectingDirectories: true
                        )
                        lastFolder = url?.path ?? "cancelled"
                        P18Diagnostics.result("folder", url)
                    }
                }
                Text("folder -> \(lastFolder)")
            }

            // Save destination. Routes to gtk_file_dialog_save and is the only
            // path that carries a default file name, so it also checks that
            // set_initial_name survived the migration.
            // 儲存目的地。導向 gtk_file_dialog_save，且是唯一帶有預設檔名的路徑，因此同時
            // 檢驗 set_initial_name 是否在遷移後仍然有效。
            VStack(alignment: .leading, spacing: 4) {
                Button("Choose a save destination") {
                    Task {
                        let url = await chooseFileSaveDestination(
                            title: "P18: choose where to save",
                            defaultButtonLabel: "Save",
                            defaultFileName: "p18-example.txt"
                        )
                        lastSave = url?.path ?? "cancelled"
                        P18Diagnostics.result("save", url)
                    }
                }
                Text("save -> \(lastSave)")
            }

            Text(
                "Expected on both backends: the dialog closes on Open/Select/Save "
                    + "and on Cancel, and the line above updates."
            )
        }
        .padding(18)
        .onAppear {
            P18Diagnostics.write("backend \(type(of: DefaultBackend.self))")
            P18Diagnostics.renderComplete()
        }
    }
}
