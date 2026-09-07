import DefaultBackend
import Foundation
import SwiftCrossUI

// P47 draws every symbol in the table, on whatever backend it was built for.
//
// The app exists because the symbol feature's correctness is not a property of
// any one backend: it is the claim that the same 36 names produce something
// visible on all five, and that claim cannot be checked by building. GTK 4
// carries 138 icons and the desktop theme supplies the rest; Segoe Fluent Icons
// is absent from a default Windows 10; an SF Symbol catalogued from a recent
// macOS may not exist on an older one. Every one of those failures draws a blank
// rectangle unless something asks first -- so the screenshots this app produces
// on each backend ARE the test, and a symbol that fell back to text is a pass,
// not a defect.
//
// The last row is the one that would otherwise never be exercised: a name that
// is in no table at all. It must draw itself. A view that quietly occupies zero
// points is the single outcome the whole feature was shaped to make
// unreachable, and it is also the one that looks like nothing being wrong.
//
// P47 把表中的每一個符號畫出來，畫在它被建置的那一個 backend 上。
//
// 這支 app 存在的理由是：符號功能的正確性並不是任何單一 backend 的性質——它主張的是「同樣的 36 個
// 名稱在五個 backend 上都能產生看得見的東西」，而該主張無法靠建置來檢查。GTK 4 內建 138 個圖示、
// 其餘由桌面主題提供；預設安裝的 Windows 10 沒有 Segoe Fluent Icons；從較新 macOS 編目而來的
// SF Symbol，在較舊的系統上可能並不存在。上述每一種失敗，若沒有人事先詢問，畫出來的都是一個空白
// 矩形——因此本 app 在各 backend 上產出的截圖**就是**那項測試，而一個退回文字的符號是通過，不是缺陷。
//
// 最後一列是「否則永遠不會被演練到」的那一項：一個不在任何表中的名稱。它必須畫出它自己。一個安靜地
// 佔據零點的 view，是整項功能的形狀所要使其無從發生的唯一結果，而它同時也是「看起來像什麼都沒出錯」
// 的那一個。

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
        write("RENDER COMPLETE -- P47 ready for symbol checks")
    }
}

@main
@HotReloadable
struct P47SymbolsApp: App {
    var body: some Scene {
        WindowGroup("P47 symbols") {
            #hotReloadable {
                P47RootView()
            }
        }
        .defaultSize(width: 900, height: 720)
    }
}

struct P47RootView: View {
    /// Six per row, because 36 divides by it and a row of six stays inside the
    /// default width on every backend. Not a grid: `LazyVGrid` is task #85 and
    /// is not implemented yet, and using it here would make this app's failures
    /// ambiguous between two features.
    /// 每列六個，因為 36 可被它整除，且六個一列在每個 backend 上都容得下預設寬度。此處不使用 grid：
    /// `LazyVGrid` 屬於任務 #85、尚未實作，而在此使用它會使本 app 的失敗在兩項功能之間變得含糊。
    static let columns = 6

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("P47: system symbols")
                    .font(.system(size: 20))
                Text("backend -> \(String(describing: DefaultBackend.self))")
                Text("\(SystemSymbol.all.count) symbols. A symbol drawn as text is a pass:")
                Text("it means this platform has no glyph and the fallback column was used.")
                Text("一個被畫成文字的符號是通過：那表示此平台沒有該字符，因而使用了退路欄位。")

                ForEach(Self.rows) { row in
                    HStack(spacing: 18) {
                        ForEach(row.symbols, id: \.name) { symbol in
                            VStack(spacing: 2) {
                                Image(systemName: symbol.name)
                                Text(symbol.name)
                                    .font(.system(size: 10))
                            }
                        }
                    }
                }

                Text("Label(_:systemImage:), the SwiftUI spelling:")
                HStack(spacing: 18) {
                    Label("Add", systemImage: "plus")
                    Label("Delete", systemImage: "trash")
                    Label("Search", systemImage: "magnifyingglass")
                }

                // The name below is in no table. It must appear, spelled out.
                // If this line shows a gap, the fallback is broken -- and that
                // is the failure that no other row on this screen can reveal.
                // 下方這個名稱不在任何表中。它必須以其字面出現。若這一行顯示出一個空缺，則退路是壞的
                // ——而那正是本畫面上其他任何一列都無法揭露的那一種失敗。
                Text("An unknown name must draw itself:")
                HStack(spacing: 8) {
                    Image(systemName: "definitely.not.a.symbol")
                    Label("unknown", systemImage: "definitely.not.a.symbol")
                }
            }
            .padding(16)
        }
        .onAppear {
            P47Diagnostics.write("backend \(String(describing: DefaultBackend.self))")
            P47Diagnostics.write("symbols \(SystemSymbol.all.count)")
            P47Diagnostics.write(
                "names " + SystemSymbol.all.map(\.name).joined(separator: " ")
            )
            P47Diagnostics.renderComplete()
        }
    }
}

extension P47RootView {
    /// The symbols split into rows, each row tagged so `ForEach` can identify it.
    /// 把符號切成數列，每一列都帶有標籤，以便 `ForEach` 能辨識它。
    static var rows: [P47Row] {
        stride(from: 0, to: SystemSymbol.all.count, by: columns).map { start in
            P47Row(
                id: start,
                symbols: Array(
                    SystemSymbol.all[start..<min(start + columns, SystemSymbol.all.count)]
                )
            )
        }
    }
}

struct P47Row: Identifiable {
    let id: Int
    let symbols: [SystemSymbol]
}
