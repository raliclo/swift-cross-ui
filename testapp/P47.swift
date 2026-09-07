import DefaultBackend
import Foundation
import SwiftCrossUI

// P47 toggles driven through a computed binding.
//
// Numbered 47, not 45, and the second attempt is the one that asked the right
// question. This app was written as P45 because `ls testapp/P45.swift` returned
// nothing. P46's own header reserves that number and says why: there is a
// hand-made `P45-MIN.exe` with no `.swift` source, named in
// `matrix_coverage/executable-size.md` as an artefact nobody can rebuild. That
// header also says, in as many words, that checking a number with `ls` alone is
// what lands on P45, and that a free filename and a free name are different
// questions. Both were asked for 47: no source, no artefact in output/, and no
// mention in any .md or .csv2 in the tree.
//
// 編號為 47 而非 45,而問對問題的是第二次嘗試。本 app 原本寫成 P45,因為 `ls testapp/P45.swift`
// 沒有回傳任何東西。P46 自己的檔頭保留了那個編號並說明了理由:存在一個沒有 `.swift` 原始碼的手工
// 執行檔 `P45-MIN.exe`,而 `matrix_coverage/executable-size.md` 把它列為「沒有人能重建的產物」。
// 那份檔頭還一字不差地寫著:只用 `ls` 檢查一個編號,正是會落到 P45 上的做法;而「檔名是空的」與
// 「名稱是空的」是兩個不同的問題。對 47 而言,兩個問題都問過了:沒有原始碼、output/ 中沒有產物、
// 樹中任何 .md 或 .csv2 都沒有提及。
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
// P47 以計算型 binding 驅動的 toggle。
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

enum P47Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P47] \(message)")
    }

    static func renderComplete() {
        guard !didAnnounceRender else { return }
        didAnnounceRender = true
        write("RENDER COMPLETE -- P47 ready for computed-binding checks")
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
final class P47Model: SwiftCrossUI.ObservableObject {
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
struct P47ComputedBindingApp: App {
    var body: some Scene {
        WindowGroup("P47 computed bindings") {
            #hotReloadable {
                P47RootView()
            }
        }
        .defaultSize(width: 760, height: 620)
    }
}

struct P47RootView: View {
    @ObservedObject var model = P47Model()

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
            Text("P47: toggles driven through a computed binding")
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
                        P47Diagnostics.write("honest set to \(newValue)")
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
                        P47Diagnostics.write(
                            "stubborn set to \(newValue), getter still says \(model.stubborn)"
                        )
                    }
                )
            )

            Text("4. Button calling a model method -- the reported workaround")
            Button("flip honest \(model.honest ? "✓" : "✗")") {
                presses += 1
                model.flip()
                P47Diagnostics.write("flip -> honest \(model.honest)")
            }

            Text("Set the sibling state, then press each control above.")
            HStack(spacing: 8) {
                Button("selection = 2") {
                    selection = 2
                    P47Diagnostics.write("selection=\(selection)")
                }
                Button("typed = seeded") {
                    typed = "seeded"
                    P47Diagnostics.write("typed=\(typed)")
                }
                Button("report") {
                    P47Diagnostics.write(
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
            P47Diagnostics.renderComplete()
        }
    }
}
