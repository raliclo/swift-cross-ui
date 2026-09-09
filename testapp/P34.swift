import DefaultBackend
import Foundation
import SwiftCrossUI

// P34 lazy containers and large collections: eager row construction probe.

enum P34Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static var requestedRows: Int {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "-rows"),
            index + 1 < arguments.count,
            let rows = Int(arguments[index + 1])
        else { return 100 }
        return max(1, min(rows, 10_000))
    }

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P34] \(message)")
        let data = Data("P34 \(Date()) \(message)\n".utf8)
        // SCUI_DEBUG_EVENTS_DIR when a launcher sets it, so every app's log lands
        // in one place; unset, the launch directory exactly as before. The
        // contract is documented in testapp/test_support/test_common.zsh.
        // 有 SCUI_DEBUG_EVENTS_DIR 時取自該變數，讓每支 app 的 log 集中一處；未設定時仍為啟動
        // 目錄，行為與過去完全相同。該約定記載於 testapp/test_support/test_common.zsh。
        let url = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
            ?? FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p34-debug-events.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    static func renderComplete(rowCount: Int) {
        guard !didAnnounceRender else { return }
        didAnnounceRender = true
        write("RENDER COMPLETE -- P34 rows=\(rowCount)")
    }
}

@main
@HotReloadable
struct P34LargeCollectionsApp: App {
    var body: some Scene {
        WindowGroup("P34 large collections") {
            #hotReloadable {
                P34RootView(rowCount: P34Diagnostics.requestedRows)
            }
        }
        .defaultSize(width: 780, height: 620)
    }
}

struct P34RootView: View {
    var rowCount: Int
    @State var visibleRows = 100

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("P34: lazy containers and large collections")
                .font(.system(size: 20))
            Text("backend -> \(String(describing: DefaultBackend.self))")
            Text("requested rows: \(rowCount); showing first \(min(visibleRows, rowCount))")
            // Three states, not two, and collapsing them would lose the only
            // part that matters. LazyVStack and LazyHStack now EXIST and are
            // NOT lazy: the layout is identical to VStack/HStack, so the picture
            // is right, but every child is created up front and every onAppear
            // fires at once. Calling them "missing" is wrong; calling them done
            // is worse, because it is the claim someone would rely on when
            // deciding whether a thousand-row list is safe.
            //
            // 三種狀態而非兩種，而把它們合併會丟掉唯一重要的那一部分。LazyVStack 與 LazyHStack
            // 現已**存在**，但**不是惰性的**：版面與 VStack/HStack 完全相同，因此畫面是對的，但所有
            // 子項都會被預先建立、所有 onAppear 會同時觸發。把它們稱為「缺席」是錯的；稱為「完成」
            // 更糟，因為那正是有人在判斷「一千列的清單是否安全」時會依賴的那句話。
            Text("Present but NOT lazy: LazyVStack, LazyHStack -- all children are built up front")
                .font(.system(size: 13))
            // ~~"Still missing: LazyVGrid, LazyHGrid, Grid, ScrollViewReader,
            // ScrollViewProxy"~~ -- FOUR OF THOSE FIVE EXISTED when this was
            // last read, 2026-09-09. Checked one at a time with a control
            // (`VStack` found, `ZZZNotARealType` absent, so the pattern works):
            //   LazyVGrid        Views/LazyVGrid.swift
            //   LazyHGrid        genuinely absent
            //   Grid             Views/Grid.swift
            //   ScrollViewReader Views/ScrollViewReader.swift
            //   ScrollViewProxy  Views/ScrollViewReader.swift
            //
            // The old text is recorded here rather than simply replaced,
            // because a false claim RENDERED ON SCREEN is the worst shape a
            // stale note takes: a reader who does not go and check believes the
            // running program over the source, and the running program was
            // wrong about four fifths of its own list.
            //
            // ~~「Still missing: LazyVGrid, LazyHGrid, Grid, ScrollViewReader, ScrollViewProxy」~~
            // ——上次讀到它時(2026-09-09),那五個裡有**四個是存在的**。逐一查證並附對照(`VStack`
            // 找得到、`ZZZNotARealType` 不存在,故樣式有效):只有 `LazyHGrid` 真的缺席。
            //
            // 舊文字記錄於此而非直接取代,因為**被算繪到畫面上的**假宣稱,是過期註記最糟的一種形狀:
            // 不去查證的讀者會選擇相信執行中的程式而非原始碼,而那個執行中的程式對自己列出的清單,
            // 五分之四是錯的。
            Text("Still missing: LazyHGrid")
                .font(.system(size: 13))

            HStack(spacing: 8) {
                // Two buttons, eight points apart, that do different things to
                // the same state -- so they log DIFFERENT text. A single shared
                // message would say a button was pressed without saying which,
                // and a coordinate that drifted between them would still read as
                // a pass. Added 2026-09-04 for the Windows action file, which
                // otherwise had only the capture.
                //
                // Both are no-ops at the default rowCount of 100, because
                // visibleRows also starts at 100: min(100, 100+100) and
                // 100 = 100. Launch with `-rows 500` to make either do
                // anything. The log now says so out loud rather than leaving a
                // silent no-op to look like success.
                //
                // 兩顆相距八點的按鈕，對同一份狀態做不同的事——因此它們記錄**不同**的訊息。
                // 若共用一則訊息，就只能說明「有按鈕被按下」而說不出是哪一顆，而在兩者之間偏移
                // 的座標仍會被讀成通過。2026-09-04 為 Windows 動作檔新增，否則該檔只有擷圖可依。
                //
                // 在預設的 rowCount 100 之下兩者皆為 no-op，因為 visibleRows 起始亦為 100：
                // min(100, 100+100) 與 100 = 100。請以 `-rows 500` 啟動，任一顆才會有作用。
                // 現在 log 會直說這件事，而不是讓一個靜默的 no-op 看起來像成功。
                Button("Show +100") {
                    visibleRows = min(rowCount, visibleRows + 100)
                    P34Diagnostics.write("show plus 100 -> visibleRows=\(visibleRows)")
                }
                Button("Show all capped rows") {
                    visibleRows = rowCount
                    P34Diagnostics.write("show all -> visibleRows=\(visibleRows)")
                }
            }

            // ScrollViewReader, added 2026-09-09 so that it can be RUN.
            //
            // It landed on all five backends but nothing in this suite
            // exercised it, and "it compiles" has been separated from "it
            // works" twice in two days here: a toolbar drew correctly and did
            // nothing when pressed, and a synthesised keystroke reached a
            // GtkEntry's buffer without reaching its binding. A view nobody
            // drives is not evidence.
            //
            // The assertion is the LOG LINE, not the picture. Scrolling to row
            // 50 looks, in a screenshot, almost exactly like scrolling to row 48
            // -- and a `scrollTo` that silently did nothing would leave the view
            // at row 0, which is also what a failed CLICK leaves. The log says
            // which of those happened.
            //
            // ScrollViewReader，2026-09-09 加入，目的是讓它**能被執行**。
            //
            // 它已在五個 backend 上落地，但本套件中沒有任何東西驅動它；而「編得過」與「會動」在這裡
            // 兩天內已經被分開過兩次：一條工具列畫得正確、按下去毫無反應；一個合成的按鍵抵達了
            // GtkEntry 的 buffer、卻抵達不了它的 binding。**沒有人驅動的 view 不構成證據。**
            //
            // 斷言的對象是 **log 行**，不是畫面。捲到第 50 列，在截圖上與捲到第 48 列幾乎一模一樣
            // ——而一個「靜默地什麼都沒做」的 `scrollTo` 會把視圖留在第 0 列，那也正是**點擊失敗**時
            // 的樣子。log 說得出發生的是哪一種。
            ScrollViewReader { proxy in
                Button("Scroll to row 50") {
                    proxy.scrollTo(50, anchor: .top)
                    P34Diagnostics.write("scrollTo row 50 requested, anchor top")
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(0..<min(visibleRows, rowCount)), id: \.self) { index in
                            Text("Row \(index): eager VStack child")
                                .id(index)
                        }
                    }
                    .padding(8)
                }
                .frame(height: 360)
            }
        }
        .padding(18)
        .onAppear {
            P34Diagnostics.write("backend \(String(describing: DefaultBackend.self))")
            P34Diagnostics.renderComplete(rowCount: rowCount)
        }
    }
}
