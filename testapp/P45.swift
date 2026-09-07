import DefaultBackend
import Foundation
import SwiftCrossUI

// P45 toggles driven through a computed binding.
//
// Numbered 45, after a round trip through 47, and the number was a decision
// rather than a deduction.
//
// P46's header reserves 45 on the grounds that `testapp/output/P45-MIN.exe`
// exists with no `.swift` source and `matrix_coverage/executable-size.md` names
// it as an artefact nobody can rebuild. That reasoning was followed and this app
// was renamed to 47 -- and then the reservation was overruled, because the two
// names are different: `P45-MIN` is not `P45`, that sentence stays true with
// this file here, and a gap in the numbering costs more than a name that shares
// a prefix.
//
// What the round trip is worth keeping is the question P46's header asks, which
// still applies to any new number: a free filename and a free NAME are separate,
// and `ls` answers only the first. Checked for 45 before this landed -- no other
// artefact in `output/`, no row in `results.csv2`, and the only mention anywhere
// is `P45-MIN` in the size document, which is a different name.
//
// 編號為 45,中間繞經 47 一趟,而這個編號是一項決定,不是一項推論。
//
// P46 的檔頭以「`testapp/output/P45-MIN.exe` 存在且無 `.swift` 原始碼、而
// `matrix_coverage/executable-size.md` 把它列為沒有人能重建的產物」為由保留 45。該理由曾被採納,
// 本 app 也因此改名為 47——隨後該保留被推翻,因為那是兩個不同的名字:`P45-MIN` 不是 `P45`,即使本檔
// 位於此處那句話依然成立,而編號留一個洞的代價,高於「一個共用前綴的名字」。
//
// 這趟往返值得留下的,是 P46 檔頭所提的那個問題——它對任何新編號仍然適用:「檔名是空的」與「名稱是
// 空的」是兩件事,而 `ls` 只回答得了第一件。45 在本檔落地之前查過:`output/` 中沒有其他產物、
// `results.csv2` 中沒有任何一列、而全樹唯一的提及是尺寸文件中的 `P45-MIN`,那是另一個名字。
//
// Reported from a SoftPCB build on macOS: a `Toggle` whose `isOn` is a
// `Binding(get:set:)` over a model resets the whole tab when pressed -- another
// control's selection returns to its first item and a field disappears -- and
// on screen that reads as "pressed and nothing happened", not as a crash.
// Replacing it with a Button that calls a model method behaved normally.
//
// **Nothing in this tree covered that combination.** All 46 apps bind every
// Toggle to `@State` through `$`; `Binding(get:set:)` appears in none of them.
// So the report could be neither confirmed nor denied from the code, and
// reading `Toggle.body` produced a plausible mechanism that turned out not to
// apply: it wraps its style's output in `AnyView`, and `AnyView` rebuilds its
// child node only when the concrete type changes, which a fixed toggle style
// never does.
//
// This app varies one thing at a time. Four controls write the same model
// field, and beside them sit two pieces of sibling state -- a selection and an
// entered string -- that a subtree rebuild would reset. If pressing the
// computed-binding toggle clears those and pressing the `@State` toggle does
// not, the report is a framework bug and this app says so in one line.
//
// The counters are what make the "nothing happened" case legible. A toggle that
// sets a value the getter then contradicts looks identical to a toggle that was
// never pressed; `writes` counts the setter calls, so the two are told apart.
//
// P45 以計算型 binding 驅動的 toggle。
//
// 來自 SoftPCB 在 macOS 上的回報:一個 `isOn` 為 `Binding(get:set:)`(讀寫某個 model)的 `Toggle`,
// 按下去會重置整個分頁——另一個控制項的選取回到第一項、一個欄位消失——而畫面上那看起來像是
// 「按了沒反應」,不像當掉。改成呼叫 model 方法的 Button 就正常。
//
// **這棵樹裡沒有任何東西涵蓋那個組合。** 全部 46 支 app 的每一個 Toggle 都是以 `$` 綁 `@State`;
// `Binding(get:set:)` 一次都沒出現。因此該回報無法僅憑讀碼確認或否定;而閱讀 `Toggle.body` 得到的
// 一個看似合理的機制,查證後並不適用:它把 style 的產出包在 `AnyView` 中,而 `AnyView` 只在具體
// 型別改變時才重建子節點——固定的 toggle style 永遠不會改變型別。
//
// 本 app 一次只變動一個因素。四個控制項寫入同一個 model 欄位,而它們旁邊放著兩份「兄弟狀態」——
// 一個選取與一個輸入字串——那是子樹被重建時會被清掉的東西。若按下計算型 binding 的 toggle 會清掉
// 它們、而按下 `@State` 的 toggle 不會,那麼該回報就是一個框架缺陷,而本 app 會以一行說出來。
//
// 那些計數器正是讓「按了沒反應」這個情況變得可讀的東西。一個「設了值、而 getter 隨即否定它」的
// toggle,看起來與一個從未被按過的 toggle 完全相同;`writes` 計算 setter 的呼叫次數,兩者因而分得開。

enum P45Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P45] \(message)")
    }

    static func renderComplete() {
        guard !didAnnounceRender else { return }
        didAnnounceRender = true
        write("RENDER COMPLETE -- P45 ready for computed-binding checks")
    }
}

/// The source of truth the computed bindings read and write.
///
/// A class, because the reported case had one: the setter reaches a model that
/// outlives the view, which is the whole reason a `Binding(get:set:)` was
/// written instead of `@State`.
///
/// 那些計算型 binding 所讀寫的真實來源。
///
/// 使用 class,因為被回報的案例就是如此:setter 觸及的是一個生命週期長於 view 的 model,而那正是
/// 當初寫 `Binding(get:set:)` 而非 `@State` 的全部理由。
// `SwiftCrossUI.` on both, because Foundation exports Combine's
// `ObservableObject` and `Published` on Apple platforms and the two names are
// then ambiguous -- the build says exactly that, four times, and it is a
// compile error rather than a silent choice.
// 兩者都加上 `SwiftCrossUI.`,因為在 Apple 平台上 Foundation 會匯出 Combine 的 `ObservableObject`
// 與 `Published`,於是這兩個名稱變得有歧義——建置會明確地這麼說四次,而且那是編譯錯誤,不是一個
// 默默做出的選擇。
final class P45Model: SwiftCrossUI.ObservableObject {
    @SwiftCrossUI.Published var honest = false
    @SwiftCrossUI.Published var writes = 0

    /// A field whose getter does **not** return what the setter was given.
    ///
    /// `Binding`'s documentation states the invariant plainly: calling `get`
    /// immediately after `set` should return the same value, and "views will
    /// not update as you expect" otherwise. This is that invariant broken on
    /// purpose, so the app can show what breaking it looks like beside a
    /// binding that keeps it. Without the honest one next to it, a failure here
    /// would be indistinguishable from the framework being at fault.
    ///
    /// 一個「getter 不回傳 setter 所收到的值」的欄位。
    ///
    /// `Binding` 的文件把這個不變式講得很清楚:在 `set` 之後立即呼叫 `get`,應該回傳相同的值,否則
    /// 「views will not update as you expect」。此處是刻意破壞該不變式,好讓本 app 能把「破壞它會是
    /// 什麼樣子」與「遵守它的 binding」並排呈現。少了旁邊那個誠實的版本,此處的失敗就無法與
    /// 「框架有問題」區分開來。
    @SwiftCrossUI.Published var stubbornStorage = false
    var stubborn: Bool {
        get { false }
        set {
            stubbornStorage = newValue
            writes += 1
        }
    }

    func flip() {
        honest.toggle()
        writes += 1
    }
}

@main
@HotReloadable
struct P45ComputedBindingApp: App {
    var body: some Scene {
        WindowGroup("P45 computed bindings") {
            #hotReloadable {
                P45RootView()
            }
        }
        .defaultSize(width: 760, height: 620)
    }
}

struct P45RootView: View {
    @ObservedObject var model = P45Model()

    // The sibling state a subtree rebuild would clear. Both start at a value
    // that is not their default, so "was reset" and "was never touched" are
    // different pictures.
    // 子樹重建時會被清掉的兄弟狀態。兩者的起始值都不是其預設值,如此「被重置了」與「從未被碰過」
    // 才會是兩幅不同的畫面。
    @State var selection = 0
    @State var typed = ""
    @State var stateToggle = false
    @State var presses = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("P45: toggles driven through a computed binding")
                .font(.system(size: 20))
            Text("backend -> \(String(describing: DefaultBackend.self))")

            Text(
                "sibling state -- selection: \(selection), typed: "
                    + (typed.isEmpty ? "(empty)" : "\"\(typed)\"")
            )
            Text("model -- honest: \(model.honest), stubbornStorage: \(model.stubbornStorage)")
            Text("setter writes: \(model.writes), button presses: \(presses)")

            Text("1. Toggle on @State, the shape every other Pn uses")
            Toggle("stateToggle \(stateToggle ? "✓" : "✗")", isOn: $stateToggle)

            Text("2. Toggle on Binding(get:set:) that keeps the invariant")
            Toggle(
                "honest \(model.honest ? "✓" : "✗")",
                isOn: Binding(
                    get: { model.honest },
                    set: { newValue in
                        model.honest = newValue
                        model.writes += 1
                        P45Diagnostics.write("honest set to \(newValue)")
                    }
                )
            )

            Text("3. Toggle on Binding(get:set:) whose getter contradicts the setter")
            Toggle(
                "stubborn \(model.stubbornStorage ? "✓" : "✗")",
                isOn: Binding(
                    get: { model.stubborn },
                    set: { newValue in
                        model.stubborn = newValue
                        P45Diagnostics.write(
                            "stubborn set to \(newValue), getter still says \(model.stubborn)"
                        )
                    }
                )
            )

            Text("4. Button calling a model method -- the reported workaround")
            Button("flip honest \(model.honest ? "✓" : "✗")") {
                presses += 1
                model.flip()
                P45Diagnostics.write("flip -> honest \(model.honest)")
            }

            Text("Set the sibling state, then press each control above.")
            HStack(spacing: 8) {
                Button("selection = 2") {
                    selection = 2
                    P45Diagnostics.write("selection=\(selection)")
                }
                Button("typed = seeded") {
                    typed = "seeded"
                    P45Diagnostics.write("typed=\(typed)")
                }
                Button("report") {
                    P45Diagnostics.write(
                        "REPORT selection=\(selection) typed=\(typed.isEmpty ? "(empty)" : typed) "
                            + "honest=\(model.honest) stubbornStorage=\(model.stubbornStorage) "
                            + "writes=\(model.writes) presses=\(presses)"
                    )
                }
            }

            Text(
                "Expected: pressing any of the four leaves selection at 2 and typed at "
                    + "\"seeded\". Control 3 is expected to look unchanged -- its getter says so -- "
                    + "while \"setter writes\" still climbs, which is how a refused write is told "
                    + "apart from a press that never arrived."
            )
            Text(
                "預期:按下四者中的任何一個,selection 都應維持 2、typed 都應維持 \"seeded\"。"
                    + "控制項 3 預期看起來不會改變——它的 getter 就是這麼說的——但「setter writes」"
                    + "仍會增加,而那正是「被拒絕的寫入」與「從未抵達的按下」之間的分辨方式。"
            )
        }
        .padding(16)
        .onAppear {
            P45Diagnostics.renderComplete()
        }
    }
}
