import DefaultBackend
import Foundation
import SwiftCrossUI

// P48 exercises LazyVGrid, the first of the three views task #33 still listed as
// missing.
//
// A grid is the one layout whose correctness a screenshot can actually settle,
// and the reason is that its failure modes are all visible and none of them
// raise anything. Columns that resolve too wide push their last cell off the
// edge; columns that resolve too narrow leave a gutter; a wrong modulo puts the
// fourth cell under the first instead of beside the third; and an adaptive
// column that computes its count from the wrong width silently becomes a
// one-column list. Every one of those compiles, runs, and returns.
//
// So this app draws three grids whose expected shapes differ from each other in
// exactly the way the three GridItem sizes differ, and each cell is numbered so
// that the order the grid filled them in is readable off the picture rather
// than inferred.
//
// P48 演練 LazyVGrid,即任務 #33 仍列為缺失的三個 view 中的第一個。
//
// 格線是「其正確性真的能由一張截圖判定」的那種版面,理由是它的失敗形式全部看得見,而且沒有一種會
// 引發任何錯誤。欄位解析得太寬,會把最後一格擠出邊界;解析得太窄,會留下一條空隙;取餘數取錯,會
// 讓第四格跑到第一格底下而不是第三格旁邊;而一個「以錯誤寬度計算欄數」的 adaptive 欄,會靜默地變成
// 一個單欄清單。上述每一種都編得過、跑得動、也會正常返回。
//
// 因此本 app 畫出三個格線,它們的預期形狀彼此之間的差異,正好就是三種 GridItem 尺寸之間的差異;
// 而每一格都有編號,好讓「格線是以什麼順序填入的」能從圖上讀出來,而不是被推測出來。

enum P48Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P48] \(message)")
    }

    static func renderComplete() {
        guard !didAnnounceRender else { return }
        didAnnounceRender = true
        write("RENDER COMPLETE -- P48 ready for grid checks")
    }
}

@main
@HotReloadable
struct P48GridApp: App {
    var body: some Scene {
        WindowGroup("P48 lazy grids") {
            #hotReloadable {
                P48RootView()
            }
        }
        .defaultSize(width: 820, height: 720)
    }
}

struct P48RootView: View {
    // Seeded to a colour that is none of the primaries, so a picker that
    // silently resets its binding is visible as a change rather than as a
    // colour that happened to already be there.
    // 起始值刻意不是任何一個原色,如此「靜默重置了自己 binding 的選擇器」會表現為一次改變,
    // 而不是一個「碰巧本來就是那個顏色」的顏色。
    @State var chosen = Color(red: 0.85, green: 0.45, blue: 0.20)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("P48: LazyVGrid")
                    .font(.system(size: 20))
                Text("backend -> \(String(describing: DefaultBackend.self))")

                // Three flexible columns share whatever is left over equally, so
                // the eight cells must read 1 2 3 / 4 5 6 / 7 8 with the last
                // row short and left-aligned rather than spread.
                // 三個 flexible 欄平均分配剩餘空間,因此八格必須讀作 1 2 3 / 4 5 6 / 7 8,
                // 且最後一列是短的、靠左,而不是被撐開。
                Text("1. three flexible columns -- expect 1 2 3 / 4 5 6 / 7 8")
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible()), count: 3),
                    spacing: 8
                ) {
                    ForEach(Array(1...8), id: \.self) { n in
                        P48Cell(number: n)
                    }
                }

                // Fixed columns ignore the proposed width entirely, so these
                // must stay 90 points wide no matter how the window is sized --
                // the check a flexible column would fail by growing.
                // fixed 欄完全忽略被建議的寬度,因此無論視窗多大,它們都必須維持 90 點寬
                // ——而那正是 flexible 欄會因為變寬而失敗的那一項檢查。
                Text("2. two fixed 90pt columns -- expect a narrow two-wide block")
                LazyVGrid(
                    columns: [GridItem(.fixed(90)), GridItem(.fixed(90))],
                    spacing: 8
                ) {
                    ForEach(Array(1...6), id: \.self) { n in
                        P48Cell(number: n)
                    }
                }

                // One adaptive item, which becomes as many columns as fit. On
                // an 820 point window that is more than two, so a result of one
                // column would mean the count was computed from a width the
                // grid never received.
                // 一個 adaptive 項目,它會變成塞得下的欄數。在 820 點寬的視窗上那多於兩欄,
                // 因此若結果是單欄,就表示欄數是用「格線從未收到的寬度」算出來的。
                Text("3. one adaptive column, minimum 120pt -- expect several per row")
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 120))],
                    spacing: 8
                ) {
                    ForEach(Array(1...9), id: \.self) { n in
                        P48Cell(number: n)
                    }
                }
                Text("4. ColorPicker -- expect a swatch, an Edit button, and three sliders")
                ColorPicker("Accent", selection: $chosen)
                Text("chosen -> rgb")
                ColorPickerReadout(color: chosen)
            }
            .padding(16)
        }
        .onAppear {
            P48Diagnostics.write("backend \(String(describing: DefaultBackend.self))")
            P48Diagnostics.write("grids flexible-3 fixed-90x2 adaptive-120")
            P48Diagnostics.renderComplete()
        }
    }
}

/// A numbered cell with a visible edge.
///
/// The border is the point of it: a grid that lays out correctly and a grid that
/// stacks every cell at the origin both draw the same numbers, and only the
/// edges tell them apart.
///
/// 一個帶有可見邊界的編號儲存格。
///
/// 邊界正是它的意義所在:一個正確佈局的格線,與一個把每格都疊在原點的格線,畫出來的數字完全相同,
/// 唯一分得出來的是邊界。
struct P48Cell: View {
    let number: Int

    var body: some View {
        Text("cell \(number)")
            .padding(8)
            .background(Color(red: 0.30, green: 0.42, blue: 0.55))
            .cornerRadius(6)
    }
}

/// Prints the chosen colour's components beside the picker.
///
/// The picker's own sliders show the same three numbers, so this is the check
/// that the binding actually reaches the app rather than only the control:
/// a ColorPicker that edited a copy would leave this line unchanged while its
/// own sliders moved, and those two are the same picture from inside the
/// control.
///
/// 在選擇器旁邊印出所選顏色的各分量。
///
/// 選擇器自身的 slider 顯示的是同樣的三個數字,因此這一行檢查的是「該 binding 真的抵達了 app」,
/// 而不只是抵達了那個控制項:一個「編輯的是副本」的 ColorPicker 會讓這一行維持不變、而它自己的
/// slider 照樣移動——從控制項內部看,那兩者是同一幅畫面。
struct ColorPickerReadout: View {
    let color: Color

    @Environment(\.self) var environment

    var body: some View {
        // One expression, no `return`. A body written as
        //     let r = color.resolve(in: environment)
        //     return Text("...\(r.red)...")
        // renders NOTHING here -- it compiles, the body runs, and the view is
        // silently absent. Reduced to a minimal case with no environment and no
        // resolve: `let n = 7; return Text("n=\(n)")` is blank while
        // `Text("marker")` is not. See testapp/plan/explicit-return-body.md.
        //
        // 單一運算式,不使用 `return`。若把 body 寫成
        //     let r = color.resolve(in: environment)
        //     return Text("...\(r.red)...")
        // 在此處什麼都不會畫——它編得過、body 也確實執行,而該 view 靜默地不存在。已化約為一個
        // 不含 environment、不含 resolve 的最小案例:`let n = 7; return Text("n=\(n)")` 是空白的,
        // 而 `Text("marker")` 不是。見 testapp/plan/explicit-return-body.md。
        Text(
            "app sees r=\(color.resolve(in: environment).red) "
                + "g=\(color.resolve(in: environment).green) "
                + "b=\(color.resolve(in: environment).blue)"
        )
    }
}
