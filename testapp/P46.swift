import DefaultBackend
import Foundation
import SwiftCrossUI

// P46 exercises the SwiftUI-parity views and state wrappers added on
// 2026-09-04. All of them are composed from existing primitives or from the
// existing state machinery, so they behave identically on all five backends --
// which is why they were done before the protocol-level parity items.
//
// It is a SEPARATE app rather than an extension of P33 on purpose. P33's Windows
// action file (P33-hide-details.csv) carries measured pixel coordinates, and
// adding rows above or around its controls moves every one of them -- the replay
// would then click empty space and report a pass, because a click that lands
// nowhere raises nothing. A new app costs one file; re-measuring an action file
// costs a launch, a capture, and a careful reading of both.
//
// Numbered 46. P43 (gradient fills clipped to shapes) and P44 are existing apps,
// and 45 was skipped here on the grounds that `testapp/output/P45-MIN.exe`
// exists with no `.swift` source and `matrix_coverage/executable-size.md` names
// it as an artefact nobody can rebuild.
//
// **That reservation was overruled on 2026-09-07 and P45.swift now exists.**
// `P45-MIN` and `P45` are different names, the size document's sentence is about
// the first and stays true, and a hole in the numbering costs more than a shared
// prefix. Recorded here rather than deleted, because a later reader finding
// P45.swift beside a comment reserving 45 would have to work out which one won.
//
// That is not a stylistic note. Write was first pointed at P43.swift on the
// strength of the highest number mentioned in a task list, and it silently
// replaced 185 lines of a tracked file, reporting success. See mistakes.csv2,
// 2026-09-04. The number was then checked against `ls` alone, which is what
// would have landed on P45. A free filename and a free NAME are different
// questions, and both have to be asked.
//
// P46 演練 2026-09-04 新增的 SwiftUI parity view 與狀態包裝器。它們全部由既有原語、或既有的狀態
// 機制組合而成，因此在五個 backend 上的行為完全相同——這正是它們先於協定層級的 parity 項目被
// 完成的理由。
//
// 這裡刻意寫成**獨立的 app** 而非擴充 P33。P33 的 Windows 動作檔（P33-hide-details.csv）帶有
// 量測出來的像素座標，而在它的控制項上方或周圍加入任何一列都會移動其中每一個——replay 接著會點到
// 空白處並回報通過，因為一次落在空處的點擊不會引發任何東西。新增一支 app 的成本是一個檔案；
// 重新量測一份動作檔的成本是一次啟動、一次擷圖，以及仔細把兩者都讀過一遍。
//
// 編號為 46，而被跳過的兩個號碼各有其理由。P43（裁進形狀內的漸層填充）與 P44 是既有的 app。
// 45 在此處被跳過的理由是：`testapp/output/P45-MIN.exe` 存在且無 `.swift` 原始碼，而
// `matrix_coverage/executable-size.md` 把它列為沒有人能重建的產物。
//
// **該保留已於 2026-09-07 被推翻，P45.swift 現已存在。** `P45-MIN` 與 `P45` 是不同的名字，尺寸
// 文件那句話講的是前者、因此依然成立；而編號留一個洞的代價，高於「一個共用前綴的名字」。此處記錄
// 而非刪除，因為日後的讀者若看到 P45.swift 與一段保留 45 的註解並存，必須自行判斷哪一邊贏了。
//
// 這不是體例上的註記。Write 最初僅憑某份任務清單中出現的最大編號就指向 P43.swift，並靜默替換掉
// 一個已被追蹤檔案的 185 行內容，還回報成功。見 mistakes.csv2，2026-09-04。之後改用 `ls` 檢查
// 號碼，而單靠 `ls` 會落在 P45 上。**檔名是否空著**與**名字是否空著**是兩個不同的問題，兩個都
// 必須問。

enum P46Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P46] \(message)")
        let data = Data("P46 \(Date()) \(message)\n".utf8)
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p46-debug-events.log")
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
        write("RENDER COMPLETE -- P46 ready for parity checks")
    }
}

/// Counts how many times it was constructed, which is the whole point of the
/// `@StateObject` half of this app.
///
/// `@StateObject` differs from `@State` in exactly one observable way: the
/// initialiser runs once instead of once per view update. That difference is
/// invisible in a screenshot, so it is counted here and written to the log --
/// otherwise "it works" would rest on the object looking the same either way,
/// which it does.
///
/// 記錄自己被建構了幾次，而這正是本 app 中 `@StateObject` 那一半存在的全部理由。
///
/// `@StateObject` 與 `@State` 只有一項可觀察的差別：初始化式只執行一次，而非每次 view 更新各
/// 執行一次。該差別在截圖上完全看不出來，因此此處把它計數並寫入 log——否則「它能用」就只能建立在
/// 「兩種寫法看起來一樣」之上，而它們確實看起來一樣。
// `SwiftCrossUI.` on both names, because Foundation re-exports Combine's
// `ObservableObject` and `Published` on Apple platforms and the two are then
// ambiguous. Unqualified, this app builds on Android, Windows and WSL and fails
// on macOS and iOS with "'ObservableObject' is ambiguous for type lookup in this
// context" -- which is why it has no macOS row in the matrix and no iOS action
// file. Found 2026-09-07 while renaming P47 back to P45, by building P46 on a
// Mac for the first time.
//
// 兩個名稱都加上 `SwiftCrossUI.`,因為在 Apple 平台上 Foundation 會再匯出 Combine 的
// `ObservableObject` 與 `Published`,於是兩者變得有歧義。不加限定時,本 app 在 Android、Windows
// 與 WSL 上建得起來,而在 macOS 與 iOS 上會以「'ObservableObject' is ambiguous for type lookup in
// this context」失敗——這正是它在矩陣中沒有 macOS 那一列、也沒有 iOS 動作檔的原因。2026-09-07 在把
// P47 改回 P45 的過程中,第一次於 Mac 上建置 P46 時發現。
final class P46Model: SwiftCrossUI.ObservableObject {
    nonisolated(unsafe) static var constructionCount = 0

    @SwiftCrossUI.Published var count = 0

    init() {
        P46Model.constructionCount += 1
        P46Diagnostics.write("P46Model constructed, total=\(P46Model.constructionCount)")
    }
}

@main
@HotReloadable
struct P46ParityViewsApp: App {
    var body: some Scene {
        WindowGroup("P46 parity views") {
            #hotReloadable {
                P46RootView()
            }
        }
        .defaultSize(width: 860, height: 700)
    }
}

struct P46RootView: View {
    @State var quantity = 3
    @State var detailsExpanded = true
    @StateObject var model = P46Model()

    var body: some View {
        Form {
            Text("P46: SwiftUI parity views")
                .font(.system(size: 20))
            Text("backend -> \(String(describing: DefaultBackend.self))")

            Section("Stepper and Gauge") {
                Stepper("Quantity", value: $quantity, in: 0...10)
                Text("quantity = \(quantity)")
                Gauge("Filled", value: Double(quantity), in: 0...10)
            }

            Section("LabeledContent") {
                LabeledContent("Backend", value: String(describing: DefaultBackend.self))
                LabeledContent("Quantity", value: "\(quantity)")
            }

            DisclosureGroup("Details", isExpanded: $detailsExpanded) {
                Text("This content is inside a real DisclosureGroup.")
                Text("Toggling the marker above hides and shows it.")
            }

            Section("StateObject and ObservedObject") {
                // The construction count is the evidence. Declared @State this
                // would climb on every update; with @StateObject it stays at 1
                // for the life of the window.
                // 建構次數就是證據。若宣告為 @State，它會隨每次更新攀升；使用 @StateObject 時，
                // 它在視窗的整個生命週期中維持為 1。
                Text("P46Model constructions: \(P46Model.constructionCount)")
                Text("model.count = \(model.count)")
                Button("Increment model") {
                    model.count += 1
                    P46Diagnostics.write(
                        "model.count=\(model.count) constructions=\(P46Model.constructionCount)"
                    )
                }
                P46ChildView(model: model)
            }

            Section("Link and Label") {
                Link(
                    "swift-cross-ui on GitHub",
                    destination: URL(string: "https://github.com/stackotter/swift-cross-ui")!
                )
                Label(title: { Text("Label with an empty icon") }, icon: { EmptyView() })
            }

            Section("LazyVStack") {
                LazyVStack(alignment: .leading, spacing: 4) {
                    Text("lazy row 1")
                    Text("lazy row 2")
                    Text("lazy row 3")
                }
            }
        }
        .onAppear {
            P46Diagnostics.write("backend \(String(describing: DefaultBackend.self))")
            P46Diagnostics.write(
                "views Form Section Stepper Gauge LabeledContent DisclosureGroup Link Label LazyVStack"
            )
            P46Diagnostics.write("wrappers StateObject ObservedObject")
            P46Diagnostics.renderComplete()
        }
    }
}

/// Receives the model rather than creating it, which is what `@ObservedObject`
/// is for.
///
/// The check this view carries is the one a plain stored property fails: press
/// "Increment model" above and this line must change too. It shares no `@State`
/// with the parent, so if it updates, that is because the object's publisher
/// reached it.
///
/// 接收 model 而非建立它，這正是 `@ObservedObject` 的用途。
///
/// 此 view 所承擔的檢查，正是一個普通儲存屬性會失敗的那一項：按下上方的「Increment model」後，
/// 這一行也必須改變。它與父層不共用任何 `@State`，因此若它更新了，那是因為該物件的 publisher
/// 傳達到了它。
struct P46ChildView: View {
    @ObservedObject var model: P46Model

    var body: some View {
        Text("observed child sees count = \(model.count)")
    }
}
