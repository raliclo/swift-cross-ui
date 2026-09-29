// P75: handing things to the system -- reveal a file, open a URL, choose where to
// save, close the window.
//
// Written 2026-09-30, when a feature-by-feature check of the five shipped backends
// found these four absent on UIKit, Android, or both: `revealFile` was nil on
// both, `openURL` warned once and did nothing on Android, `chooseFileSaveDestination`
// warned and returned nil on both, and `dismissWindow()` did nothing on either. No
// test app called three of the four, which is how the gaps went unseen.
//
// Every button reports what came back, so a run that did nothing is visible as a
// line that never changed rather than as an absence:
//
//   Reveal       writes a file where the platform's file manager can list it, then
//                reveals it. Pass: the file manager opens at that folder showing
//                the file, and the line reads "reveal: requested".
//   Open URL     opens https://www.iana.org/help/example-domains in the browser.
//   Save         asks for a destination, writes one known line to it and reads it
//                back. Pass: "read back: saved by P75" -- the destination was a
//                place an ordinary write reaches, not only a name.
//   Close        dismissWindow(). Pass: the window goes, and "[P75] close handler"
//                is logged if the scene graph released it.
//
// P75：把事情交給系統——顯示一個檔案、開啟一個 URL、選擇存放位置、關閉視窗。
//
// 2026-09-30 撰寫。當時對五個已發布的 backend 逐一檢查功能，發現這四項在 UIKit、Android 或兩者上
// 都不存在：`revealFile` 在兩者上都是 nil，`openURL` 在 Android 上只會警告一次、什麼也不做，
// `chooseFileSaveDestination` 在兩者上都只會警告並回傳 nil，而 `dismissWindow()` 在兩者上都沒有作用。
// 四項中有三項沒有任何測試 app 呼叫過，這正是缺口一直沒被看見的原因。
//
// 每一顆按鈕都會回報得到了什麼，所以一次「什麼都沒做」的執行，會以一行「從未改變」的文字呈現，
// 而不是以「不存在」呈現。各按鈕的通過條件見上方英文。

import DefaultBackend
import Foundation
import SwiftCrossUI

#if canImport(SwiftBundlerRuntime)
    import SwiftBundlerRuntime
#endif

enum P75Diagnostics {
    static func write(_ message: String) {
        print("[P75] \(message)")
        fflush(stdout)
    }
}

/// Where the file to reveal is written: somewhere the platform's own file manager
/// can list. On iOS that is the app's Documents, which the app template exposes
/// to Files; on Android it is the shared Download folder, because a file manager
/// cannot list another app's private storage.
///
/// 要顯示的檔案寫在哪裡：平台自己的檔案管理員能列出的地方。在 iOS 上是 app 的 Documents（app 範本
/// 已向 Files 公開）；在 Android 上是共用的 Download 資料夾，因為檔案管理員無法列出另一個 app 的
/// 私有儲存區。
func p75RevealFolder() -> URL {
    #if os(Android)
        return URL(fileURLWithPath: "/storage/emulated/0/Download")
    #elseif os(iOS)
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("P75", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    #else
        return FileManager.default.temporaryDirectory
    #endif
}

@main
@HotReloadable
struct P75SystemHandoffsApp: App {
    var body: some Scene {
        WindowGroup("P75 system hand-offs") {
            #hotReloadable {
                P75RootView()
            }
        }
        .defaultSize(width: 560, height: 420)
    }
}

struct P75RootView: View {
    @Environment(\.revealFile) var revealFile
    @Environment(\.openURL) var openURL
    @Environment(\.chooseFileSaveDestination) var chooseFileSaveDestination
    @Environment(\.dismissWindow) var dismissWindow

    @State var revealStatus = "not pressed"
    @State var openStatus = "not pressed"
    @State var saveStatus = "not pressed"
    @State var readBack = "-"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("P75: reveal, open, save, close")
            Text("backend -> \(String(describing: DefaultBackend.self))")

            Button("Reveal a file") {
                let file = p75RevealFolder().appendingPathComponent("p75-reveal.txt")
                do {
                    try "revealed by P75\n".write(to: file, atomically: false, encoding: .utf8)
                } catch {
                    revealStatus = "could not write \(file.path): \(error)"
                    P75Diagnostics.write("reveal: \(revealStatus)")
                    return
                }
                guard let revealFile else {
                    revealStatus = "revealFile is nil on this backend"
                    P75Diagnostics.write("reveal: \(revealStatus)")
                    return
                }
                // A backend's refusal is logged by RevealFileAction ("failed to
                // reveal file"), not thrown to here.
                // backend 的拒絕由 RevealFileAction 記錄（"failed to reveal file"），不會拋到這裡。
                revealFile(file)
                revealStatus = "requested for \(file.path)"
                P75Diagnostics.write("reveal: \(revealStatus)")
            }
            Text("reveal: \(revealStatus)")

            Button("Open URL") {
                let url = URL(string: "https://www.iana.org/help/example-domains")!
                openURL(url)
                openStatus = "requested"
                P75Diagnostics.write("openURL: \(openStatus)")
            }
            Text("openURL: \(openStatus)")

            Button("Save...") {
                Task {
                    guard
                        let destination = await chooseFileSaveDestination(
                            defaultFileName: "p75-saved.txt"
                        )
                    else {
                        saveStatus = "cancelled or unavailable"
                        P75Diagnostics.write("save: \(saveStatus)")
                        return
                    }
                    do {
                        try Data("saved by P75".utf8).write(to: destination)
                        saveStatus = "wrote \(destination.path)"
                        readBack = (try? String(contentsOf: destination, encoding: .utf8))
                            ?? "(could not read it back)"
                    } catch {
                        saveStatus = "could not write \(destination.path): \(error)"
                    }
                    P75Diagnostics.write("save: \(saveStatus); read back: \(readBack)")
                }
            }
            Text("save: \(saveStatus)")
            Text("read back: \(readBack)")

            Button("Close this window") {
                P75Diagnostics.write("close requested")
                dismissWindow()
            }
        }
        .padding(18)
        .onAppear {
            P75Diagnostics.write("backend \(String(describing: DefaultBackend.self))")
            P75Diagnostics.write("RENDER COMPLETE -- P75 ready")
        }
        .onDisappear {
            P75Diagnostics.write("close handler: the window's view disappeared")
        }
    }
}
