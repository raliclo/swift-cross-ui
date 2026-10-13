// P91: .focusable() -- a view that is not a control takes the keyboard focus (2026-10-13).
//
// Three coloured panels in a row. A and B are `.focusable()`, "off" is `.focusable(false)`.
// Each has `.focused($field, equals:)` and `.onKeyPress` after it, and its own "heard" line.
//
// Pass:
//   1 pressing panel A shows "focused: a"; typing then adds to "A heard" and to no other line
//   2 pressing panel B moves it: "focused: b", and typing adds to "B heard"
//   3 the "focus A" button moves the focus from code; "focus none" clears it
//   4 Tab from A reaches B (desktop, and iPad or Android with a keyboard)
//   5 "focus off" is refused: "refusal check: refused (correct)", and "off heard" stays empty
//   6 "focus changes heard" rises with every move
//   7 a key typed while "focused: none" is heard by no panel (AppKit focuses the first panel
//     when the window opens, and says so: "focused: a")
// Fail: pressing a panel changes nothing, keys reach the wrong panel or none, Tab stays on A,
// or the off panel takes the focus.
//
// P91:.focusable()——讓一個不是控制項的 view 取得鍵盤焦點(2026-10-13)。
// 一列三個色塊。A 與 B 是 `.focusable()`,「off」是 `.focusable(false)`;各自後面接 `.focused($field, equals:)`
// 與 `.onKeyPress`,也各有一行「heard」。通過條件見上:按 A 顯示 focused: a,打字只加到 A heard;按 B 移過去;
// 按鈕能從程式移動與清除焦點;Tab 從 A 到 B;「focus off」被拒絕且 off heard 維持空白;每次移動 focus changes heard
// 都增加;聚焦之前什麼都聽不到。失敗:按色塊沒反應、按鍵到了錯的色塊或哪裡都沒到、Tab 留在 A,或 off 取得焦點。

import DefaultBackend
@_spi(Backends) import SwiftCrossUI

enum P91Field: Hashable {
    case a
    case b
    case off
}

@main
struct P91App: App {
    var body: some Scene {
        WindowGroup("P91 focusable") {
            #hotReloadable {
                P91View()
            }
        }
        .defaultSize(width: 420, height: 520)
    }
}

struct P91View: View {
    @Environment(\.backend) var backend
    @FocusState var field: P91Field?
    @State var heardA = ""
    @State var heardB = ""
    @State var heardOff = ""
    @State var changes = 0
    @State var refusal = "not asked"
    /// Set by "focus off": from then on the refusal line follows where the focus is.
    /// 由「focus off」設定:之後 refusal 那一行跟著焦點所在而變。
    @State var askedOff = false
    @State var name = ""

    static func typed(_ press: KeyPress) -> String {
        // Key-downs that type something; Tab moves the focus and is not text.
        // 只取有打出字的 key-down;Tab 是移動焦點，不是文字。
        guard press.phase == .down, press.characters != "\t" else { return "" }
        return press.characters
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("P91: .focusable() on a plain view")
            Text(
                "focusable supported: \(backend is any BackendFeatures.FocusableTargets ? "yes" : "NO")"
            )
            Text("focused: \(field.map(String.init(describing:)) ?? "none")")
            Text("focus changes heard: \(changes)")
            HStack(spacing: 14) {
                Color.blue
                    .frame(width: 110, height: 70)
                    .focusable()
                    .focused($field, equals: .a)
                    .onKeyPress { heardA += Self.typed($0) }
                Color.green
                    .frame(width: 110, height: 70)
                    .focusable()
                    .focused($field, equals: .b)
                    .onKeyPress { heardB += Self.typed($0) }
                Color.gray
                    .frame(width: 110, height: 70)
                    .focusable(false)
                    .focused($field, equals: .off)
                    .onKeyPress { heardOff += Self.typed($0) }
            }
            Text("blue = A · green = B · grey = off (.focusable(false))")
            Text("A heard: \(heardA)")
            Text("B heard: \(heardB)")
            Text("off heard: \(heardOff)")
            HStack(spacing: 8) {
                Button("focus A") { field = .a }
                Button("focus B") { field = .b }
                Button("focus none") { field = nil }
            }
            Button("focus off") {
                askedOff = true
                field = .off
            }
            Text("refusal check: \(refusal)")
            TextField("a text field, the next Tab stop", text: $name)
                .frame(width: 300)
            Text("1 press A, type · 2 press B, type · 3 buttons move it")
            Text("4 Tab goes A to B · 5 off refuses · 6 changes rise")
        }
        .padding(16)
        .onChange(of: field) {
            changes += 1
            if askedOff {
                refusal =
                    field == .off
                        ? "NOT refused -- the off panel took the focus (wrong)"
                        : "refused (correct)"
            }
        }
    }
}
