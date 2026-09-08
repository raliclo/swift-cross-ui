import DefaultBackend
import Foundation
import SwiftCrossUI

// P51 is the first picture of the six views that landed on 2026-09-08.
//
// `GroupBox`, `ControlGroup`, `Grid`/`GridRow`, `LazyVGrid`, `GridItem` and
// `LabelStyle` were committed in 0e2a0ffa and 6cefefb9. Both commits were
// checked by a build returning rc=0 and by driving P44 to confirm nothing
// regressed. NEITHER IS EVIDENCE THAT ANY OF THEM DRAW ANYTHING. Before this
// file, `grep -l 'GroupBox\|ControlGroup\|LazyVGrid\|GridItem\|labelStyle\|
// GridRow' testapp/*.swift` returned exactly two files, and both hits were
// prose: P34:85 lists them as "still missing" and P47:65 says LazyVGrid "is
// task #85 and is not implemented yet". Neither is a use. So the whole of the
// evidence for six new public types was "it compiled and broke nothing".
//
// The gap has a cost already measured, on the same day: `.onHover` took the
// process down on AndroidBackend, and no `testapp/P*.swift` used `.onHover`,
// so the P-suite could not have found it however many times it ran. A feature
// nobody exercises is a feature nobody finds broken.
//
// Everything on this screen is therefore arranged to be settled BY THE
// SCREENSHOT, not by the app's own account of itself:
//
//   - the LazyVGrid cells carry their column number, so a collapse to one
//     column reads as "col 1, col 2, col 3" running DOWN the page instead of
//     across it -- visible, not inferred;
//   - `.automatic` and `.titleAndIcon` are adjacent, on one label text and one
//     icon, because 6cefefb9's claim is that they are the same expression and
//     two neighbouring columns is where sameness is checkable;
//   - the `GridItem.adaptive` row is captioned as the KNOWN DIVERGENCE it is,
//     so the picture records the defect instead of being read as a pass.
//
// P51 是 2026-09-08 落地的那六個 view 的第一張圖。
//
// `GroupBox`、`ControlGroup`、`Grid`/`GridRow`、`LazyVGrid`、`GridItem` 與 `LabelStyle` 由
// 0e2a0ffa 與 6cefefb9 提交。兩個 commit 都以「建置回傳 rc=0」以及「驅動 P44 確認沒有退步」來檢查。
// **這兩者都不是任何一項會畫出東西的證據。** 在本檔之前，
// `grep -l 'GroupBox\|ControlGroup\|LazyVGrid\|GridItem\|labelStyle\|GridRow' testapp/*.swift`
// 恰好回傳兩個檔案，而兩處命中都只是文字：P34:85 把它們列為「仍然缺席」，P47:65 則說 LazyVGrid
// 「屬於任務 #85、尚未實作」。兩者都不是使用。因此六個新的 public 型別，其全部證據就是
// 「它編譯過了，而且沒有弄壞東西」。
//
// 這個缺口的代價在同一天就已經量到了：`.onHover` 在 AndroidBackend 上會讓行程終止，而沒有任何
// `testapp/P*.swift` 用到 `.onHover`，所以 P-suite 無論跑幾次都不可能找到它。沒有人演練的功能，
// 就是沒有人會發現它壞掉的功能。
//
// 因此本畫面上的一切，都安排成**由截圖判定**，而不是由 app 自己的說法判定：
//
//   - LazyVGrid 的每一格都帶著自己的欄號，因此塌縮成一欄時，讀起來會是「col 1, col 2, col 3」
//     沿著頁面**向下**而非橫向排列——那是看得見的，不是推論出來的；
//   - `.automatic` 與 `.titleAndIcon` 相鄰放置，共用同一段 label 文字與同一個圖示，因為 6cefefb9
//     的主張正是「它們是同一個表達式」，而相鄰的兩欄正是「相同」得以被檢查之處；
//   - `GridItem.adaptive` 那一列被標註為它本來的樣子——**已知的分歧**——好讓這張圖記錄下該缺陷，
//     而不是被讀成一次通過。

enum P51Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P51] \(message)")
        let data = Data("P51 \(Date()) \(message)\n".utf8)
        // SCUI_DEBUG_EVENTS_DIR when a launcher sets it, so every app's log lands
        // in one place; unset, the launch directory exactly as before. The
        // contract is documented in testapp/test_support/test_common.zsh.
        // 有 SCUI_DEBUG_EVENTS_DIR 時取自該變數，讓每支 app 的 log 集中一處；未設定時仍為啟動
        // 目錄，行為與過去完全相同。該約定記載於 testapp/test_support/test_common.zsh。
        let url = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
            ?? FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p51-debug-events.log")
        if let handle = try? FileHandle(forWritingTo: url) {
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
        write("RENDER COMPLETE -- P51 ready for grid, box and label-style checks")
    }
}

@main
@HotReloadable
struct P51ContainersApp: App {
    var body: some Scene {
        WindowGroup("P51 containers and grids") {
            #hotReloadable {
                P51RootView()
            }
        }
        // Wide and tall on purpose, and laid out in TWO columns, because every
        // one of the six has to be in ONE frame. Stacked in a single column the
        // content measures roughly 950 points, which is taller than a 1080p
        // screen leaves for a window; split in two it is about 660, and a
        // capture of the whole window then contains the whole test.
        //
        // The `ScrollView` below is for the phone-sized case, where two columns
        // of this width cannot fit. It is not a substitute for the size: on a
        // narrow window this app's screenshot is INCOMPLETE, and that is stated
        // rather than hidden. The desktop backends are where it is judged.
        //
        // 刻意做得又寬又高，並排成**兩欄**，因為那六項全部都必須落在**同一個**畫面裡。單欄堆疊時，
        // 內容約高 950 點，比 1080p 螢幕留給視窗的高度還高；分成兩欄後約為 660 點，此時擷取整個
        // 視窗就等於擷取整個測試。
        //
        // 下方的 `ScrollView` 是為了手機尺寸的情形——在那裡，兩欄這樣的寬度是放不下的。它並不能替代
        // 尺寸本身：在窄視窗下，本 app 的截圖是**不完整的**，此事在此載明而非隱藏。真正判定它的地方
        // 是桌面的各個 backend。
        .defaultSize(width: 920, height: 860)
    }
}

struct P51RootView: View {
    /// How many cells the three-column `LazyVGrid` holds. The ``ControlGroup``
    /// buttons move it, which is what makes a press visible in the picture as
    /// well as in the log: 9 cells is 3 full rows, 12 is 4.
    /// 三欄 `LazyVGrid` 中的儲存格數量。``ControlGroup`` 的按鈕會改變它，而這正是「一次按壓在圖上
    /// 與在 log 中同時可見」的原因：9 格是滿滿 3 列，12 格是 4 列。
    @State var cellCount = 9

    /// Three fixed columns, not flexible ones.
    ///
    /// `.fixed` because the width then does not depend on the content, the
    /// window or the backend's idea of a default: three columns are 3 x 96
    /// points wide and one column is 96, and those two pictures cannot be
    /// confused at any density. `.flexible` would let a one-column failure
    /// stretch to the window's width, which looks deliberate.
    ///
    /// 三個固定寬度的欄，而非彈性欄。
    ///
    /// 使用 `.fixed`，是因為如此一來寬度就不取決於內容、視窗、或 backend 對預設值的想法：三欄就是
    /// 3 x 96 點寬，一欄就是 96 點，而這兩張圖在任何 density 下都不可能被混淆。`.flexible` 會讓
    /// 「塌縮成一欄」的失敗撐滿整個視窗寬度，那看起來會像是刻意的。
    static let threeColumns = [
        GridItem(.fixed(96), spacing: 8),
        GridItem(.fixed(96), spacing: 8),
        GridItem(.fixed(96), spacing: 8),
    ]

    /// One adaptive column. See ``P51AdaptiveSection`` for why there is only one
    /// and why that is the point.
    /// 單一個 adaptive 欄。為何只有一個、以及為何那正是重點，見 ``P51AdaptiveSection``。
    static let adaptiveColumns = [GridItem(.adaptive(minimum: 96), spacing: 8)]

    var rowCount: Int {
        (cellCount + 2) / 3
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("P51: GroupBox, ControlGroup, Grid, LazyVGrid, GridItem, LabelStyle")
                    .font(.system(size: 19))
                Text("backend -> \(String(describing: DefaultBackend.self))")
                Text("Six views committed 2026-09-08. Nothing else in the P-suite draws them,")
                    .font(.system(size: 12))
                Text("so this screenshot is the whole of the evidence that they render.")
                    .font(.system(size: 12))
                Text("六個於 2026-09-08 提交的 view。P-suite 中沒有別的東西會畫出它們，因此這張截圖就是它們能繪製的全部證據。")
                    .font(.system(size: 12))

                HStack(alignment: .top, spacing: 28) {
                    VStack(alignment: .leading, spacing: 16) {
                        P51LazyVGridSection(cellCount: cellCount, rowCount: rowCount)
                        P51GridSection()
                        P51AdaptiveSection()
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        P51GroupBoxSection()
                        P51ControlGroupSection(cellCount: $cellCount, rowCount: rowCount)
                        P51LabelStyleSection()
                    }
                }
            }
            .padding(16)
        }
        .onAppear {
            P51Diagnostics.renderComplete()
        }
    }
}

// MARK: - 1. LazyVGrid

/// The three-column grid, and the one thing on this screen that a wrong
/// implementation makes look plausible.
///
/// `LazyVGrid` cannot count its own cells without ``GridCellsProviding``; 0e2a0ffa
/// says so in its own commit message, and says that without it "a three-column
/// grid would have rendered as one column". One column of nine numbered boxes is
/// a perfectly tidy picture. So the cells carry TWO labels, not one:
///
///   - `#n` -- the cell's index, so the reading order is unambiguous;
///   - `col n` -- the column it is supposed to be in.
///
/// Three columns reads `col 1  col 2  col 3` ACROSS each row, and every row
/// repeats it. One column reads `col 1`, `col 2`, `col 3`, `col 1` ... DOWN the
/// page. The failure is therefore something you see, not something you work out
/// by measuring a width.
///
/// 三欄的網格，也是本畫面上唯一一個「實作錯了卻看起來很合理」的東西。
///
/// 沒有 ``GridCellsProviding``，`LazyVGrid` 數不出自己有幾個儲存格；0e2a0ffa 在自己的 commit
/// 訊息裡就這麼說了，並指出少了它「一個三欄的網格會被畫成一欄」。九個編號方塊排成一欄，是一張
/// 相當整齊的圖。因此每一格帶的是**兩個**標籤，而不是一個：
///
///   - `#n`——該格的索引，使閱讀順序毫無歧義；
///   - `col n`——它**應該**位於的欄。
///
/// 三欄時，每一列橫著讀是 `col 1  col 2  col 3`，且每一列都重複一次。一欄時，沿頁面**向下**讀成
/// `col 1`、`col 2`、`col 3`、`col 1`……。因此這種失敗是「看到的」，而不是靠量寬度「推算出來的」。
struct P51LazyVGridSection: View {
    var cellCount: Int
    var rowCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("1. LazyVGrid -- THREE columns")
                .font(.system(size: 15))
            Text("Read the second line of each cell. Across a row it must go col 1, col 2, col 3.")
                .font(.system(size: 11))
            Text("If those run DOWN the page instead, it collapsed to one column: failure.")
                .font(.system(size: 11))
            Text("請讀每一格的第二行。沿著一列橫著讀，必須是 col 1、col 2、col 3。")
                .font(.system(size: 11))
            Text("若它們改為沿頁面向下排列，代表網格塌縮成一欄——那是失敗。")
                .font(.system(size: 11))

            LazyVGrid(columns: P51RootView.threeColumns, alignment: .leading, spacing: 8) {
                // `Array(1...n)` rather than the range itself, matching P4,
                // P11, P15 and P34. Every `ForEach` over a range in this suite
                // is written that way.
                // 使用 `Array(1...n)` 而非 range 本身，與 P4、P11、P15、P34 一致。本套件中每一個
                // 走訪 range 的 `ForEach` 都是這麼寫的。
                ForEach(Array(1...cellCount), id: \.self) { index in
                    P51Cell(index: index, column: (index - 1) % 3 + 1)
                }
            }

            Text("\(cellCount) cells / \(rowCount) rows -- the ControlGroup at right moves this")
                .font(.system(size: 11))
        }
    }
}

/// One grid cell: its index, the column it belongs to, and a border in that
/// column's colour.
///
/// Outlined rather than filled, and that is a choice, not a limitation.
/// `View.background(_:)` exists here -- `Views/Modifiers/Layout/BackgroundModifier.swift`,
/// declared `func background<Background: View>(_:)`, which is why a grep for
/// `func background(` finds nothing and the first version of this comment
/// wrongly said it was absent. A filled cell was rejected for a different
/// reason: the labels would then sit on `Color.red`/`.green`/`.blue`, whose
/// adaptive values differ between light and dark, and a cell whose text cannot
/// be read is a cell whose column number cannot be read either. The outline
/// leaves the text on the window background in both appearances.
///
/// Three boxes across, outlined red, green and blue, are three countable
/// columns; nine boxes down, cycling through the same three colours, are not.
///
/// 一個網格儲存格：它的索引、它所屬的欄，以及一圈該欄顏色的邊框。
///
/// 描邊而非填色，這是一項選擇，而非限制。`View.background(_:)` 在此是存在的——見
/// `Views/Modifiers/Layout/BackgroundModifier.swift`，其宣告為 `func background<Background: View>(_:)`，
/// 這也正是為何搜尋 `func background(` 什麼都找不到，以及本段說明的第一版為何誤稱它不存在。填色被
/// 否決的理由是另一個：那樣標籤就會坐在 `Color.red`／`.green`／`.blue` 之上，而這些 adaptive 顏色在
/// 淺色與深色外觀下並不相同，而一個文字讀不出來的儲存格，其欄號同樣讀不出來。描邊則讓文字在兩種
/// 外觀下都留在視窗背景上。
///
/// 橫排三個、以紅綠藍描邊的方塊，是三個數得出來的欄；直排九個、循環著同樣三種顏色的方塊，則不是。
struct P51Cell: View {
    var index: Int
    var column: Int

    /// Red, green, blue by column. Computed inside the view rather than in a
    /// file-scope helper because ``View`` is `@MainActor` here, so a property on
    /// a view is isolated and cannot trip the actor-isolation error that
    /// 6cefefb9 recorded hitting at `LabelStyle.swift:95:22`.
    /// 依欄別為紅、綠、藍。寫成 view 內部的計算屬性而非檔案層級的 helper，是因為此處的 ``View``
    /// 帶有 `@MainActor`，因此 view 上的屬性是被隔離的，不會踩到 6cefefb9 所記錄、發生在
    /// `LabelStyle.swift:95:22` 的 actor 隔離錯誤。
    private var accent: Color {
        switch column {
            case 1: Color.red
            case 2: Color.green
            default: Color.blue
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            Text("#\(index)")
            Text("col \(column)")
                .font(.system(size: 11))
        }
        .frame(width: 84, height: 44)
        .border(accent, width: 2)
    }
}

// MARK: - 2. Grid and GridRow

/// A 3 x 3 `Grid` of `GridRow`s, and one deliberately wide cell.
///
/// **Row 3's first cell is wider on purpose, and it will NOT line up with the
/// rows above it.** `Grid`'s own documentation states the divergence: cells are
/// not aligned into columns across rows, because a `GridRow` is an `HStack` and
/// no shared column measurement happens. Making every label the same width would
/// have produced a screenshot that reads as "columns align here", which is a
/// claim this implementation does not make.
///
/// So the ragged third row is the honest picture, and it is captioned as
/// expected rather than left for a reader to file as a bug.
///
/// 由 `GridRow` 組成的 3 x 3 `Grid`，以及一個刻意加寬的儲存格。
///
/// **第 3 列的第一格是刻意加寬的，而它不會與上方各列對齊。** `Grid` 自己的文件就載明了這項分歧：
/// 各列之間的儲存格不會對齊成欄，因為 `GridRow` 就是一個 `HStack`，其間並沒有共用的欄寬量測。若把
/// 每個標籤都做成一樣寬，產出的截圖讀起來會是「這裡的欄是對齊的」——而那是本實作並未提出的主張。
///
/// 因此參差不齊的第三列才是誠實的圖，並且被標註為預期結果，而不是留給讀者去當成 bug 記下來。
struct P51GridSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("2. Grid + GridRow -- 3 x 3")
                .font(.system(size: 15))
            Text("Nine cells, each labelled RnCn. Row 3 column 1 is wide ON PURPOSE:")
                .font(.system(size: 11))
            Text("Grid does not measure shared column widths, so row 3 will not align. Expected.")
                .font(.system(size: 11))
            Text("九格，各以 RnCn 標示。第 3 列第 1 格是刻意加寬的：Grid 不做共用欄寬量測，")
                .font(.system(size: 11))
            Text("因此第 3 列不會對齊。這是預期結果。")
                .font(.system(size: 11))

            Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    P51GridRowCell(text: "R1C1")
                    P51GridRowCell(text: "R1C2")
                    P51GridRowCell(text: "R1C3")
                }
                GridRow {
                    P51GridRowCell(text: "R2C1")
                    P51GridRowCell(text: "R2C2")
                    P51GridRowCell(text: "R2C3")
                }
                GridRow {
                    P51GridRowCell(text: "R3C1 wide")
                    P51GridRowCell(text: "R3C2")
                    P51GridRowCell(text: "R3C3")
                }
            }
        }
    }
}

/// A `Grid` cell: outlined, and sized by its text rather than to a fixed width.
///
/// No `frame` here, unlike ``P51Cell``. A fixed width would hide exactly the
/// thing the wide cell is there to show, by making every cell agree on a width
/// that `Grid` never negotiated.
///
/// `Grid` 的一個儲存格：描邊，且尺寸由其文字決定而非固定寬度。
///
/// 此處與 ``P51Cell`` 不同，沒有 `frame`。固定寬度會把「加寬那一格所要展示的東西」正好藏起來——
/// 它會讓每一格都同意一個 `Grid` 從未協商過的寬度。
struct P51GridRowCell: View {
    var text: String

    var body: some View {
        Text(text)
            .padding(6)
            .border(Color.purple, width: 2)
    }
}

// MARK: - 6. GridItem.adaptive, the known divergence

/// `GridItem.adaptive` accepted, rendered, and WRONG -- on the record.
///
/// `Views/GridItem.swift` documents it against its own `Size.adaptive` case: in
/// SwiftUI it changes the NUMBER of columns to fit the available width; here it
/// is treated as `.flexible` with the same bounds, so a grid built from one
/// adaptive item has exactly one column rather than as many as fit.
///
/// This section exists so the screenshot RECORDS that, because the alternative
/// is worse than it sounds. `LazyVGrid(columns: [GridItem(.adaptive(minimum:
/// 96))])` is correct SwiftUI, it compiles here, it runs here, and it produces a
/// tidy single column that a reader with no reason to suspect anything will read
/// as working. A divergence that only exists in a doc comment is one nobody
/// looking at the app will meet.
///
/// Four cells, so the expected-wrong picture is four boxes stacked vertically
/// where SwiftUI would have put four across.
///
/// `GridItem.adaptive` 被接受、被繪製，而且是**錯的**——並且有案可稽。
///
/// `Views/GridItem.swift` 就在它自己的 `Size.adaptive` case 上載明了這點：在 SwiftUI 中它會改變
/// **欄的數量**以填滿可用寬度；此處則以相同界限比照 `.flexible` 處理，因此由一個 adaptive item
/// 建構出的網格恰好只有一欄，而不是「能塞下幾欄就幾欄」。
///
/// 本區塊存在的目的，是讓截圖把那件事**記錄下來**，因為另一種選擇比聽起來更糟。
/// `LazyVGrid(columns: [GridItem(.adaptive(minimum: 96))])` 是正確的 SwiftUI，在此能編譯、能執行，
/// 並產出一個整齊的單欄——而一個沒有理由起疑的讀者會把它讀成運作正常。只存在於 doc comment 裡的
/// 分歧，是任何看著這支 app 的人都不會遇到的分歧。
///
/// 四格，因此「預期為錯」的那張圖，是四個方塊垂直堆疊——而 SwiftUI 會把那四個橫著排開。
struct P51AdaptiveSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("6. GridItem.adaptive -- KNOWN DIVERGENCE, not a pass")
                .font(.system(size: 15))
            Text("columns: [GridItem(.adaptive(minimum: 96))] with 4 cells.")
                .font(.system(size: 11))
            Text("SwiftUI would fit SEVERAL columns here. This draws ONE, and that is the defect,")
                .font(.system(size: 11))
            Text("documented on Size.adaptive in GridItem.swift. Four boxes stacked = expected.")
                .font(.system(size: 11))
            Text("SwiftUI 在此會塞進**數個**欄。這裡只畫出**一個**，而那就是該缺陷，")
                .font(.system(size: 11))
            Text("記載於 Views/GridItem.swift 的 Size.adaptive 上。四個方塊垂直堆疊即為預期。")
                .font(.system(size: 11))

            LazyVGrid(columns: P51RootView.adaptiveColumns, alignment: .leading, spacing: 6) {
                ForEach(Array(1...4), id: \.self) { index in
                    P51AdaptiveCell(index: index)
                }
            }
        }
    }
}

/// An adaptive-row cell, outlined in orange so it cannot be mistaken for one of
/// the three-column grid's red/green/blue cells further up the page.
/// adaptive 那一列的儲存格，以橘色描邊，如此便不會與頁面上方那個三欄網格的紅／綠／藍儲存格混淆。
struct P51AdaptiveCell: View {
    var index: Int

    var body: some View {
        Text("adaptive #\(index)")
            .frame(width: 84, height: 30)
            .border(Color.orange, width: 2)
    }
}

// MARK: - 3. GroupBox

/// A titled `GroupBox`, sitting against the window background so its own
/// decoration is what you see.
///
/// `GroupBox`'s body is `VStack { label; content }.padding(12).border(.gray)`,
/// and the order matters to what the screenshot should contain: the border is
/// OUTSIDE the padding, so there must be a visible gap of about twelve points
/// between the grey line and the text on every side. A line hugging the text
/// means the padding was dropped; no line at all means `border(_:width:)` did
/// nothing on this backend, which is a different failure with a different cause.
///
/// This is the only GREY box on the screen -- the grid cells are red, green,
/// blue and purple, the adaptive cells orange, and the label-style row is
/// deliberately unboxed -- so neither outcome can be misattributed to a
/// neighbour's frame.
///
/// 一個帶標題的 `GroupBox`，直接置於視窗背景之上，使你看見的就是它自身的裝飾。
///
/// `GroupBox` 的 body 是 `VStack { label; content }.padding(12).border(.gray)`，而其順序關係到
/// 截圖裡應該有什麼：邊框在內距的**外側**，因此灰線與文字之間四邊都必須有約十二點的可見間隙。
/// 線緊貼著文字代表內距被丟掉了；完全沒有線則代表 `border(_:width:)` 在該 backend 上什麼也沒做——
/// 那是另一種失敗、另一個成因。
///
/// 這是畫面上唯一的**灰色**方框——網格儲存格是紅、綠、藍與紫色，adaptive 儲存格是橘色，而 label
/// 樣式那一列刻意不加框——因此上述兩種結果都不會被誤算到鄰居的 frame 頭上。
struct P51GroupBoxSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("3. GroupBox")
                .font(.system(size: 15))

            GroupBox("GroupBox title") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("A grey border with roughly 12 points of padding")
                        .font(.system(size: 12))
                    Text("between the line and this text, on all four sides.")
                        .font(.system(size: 12))
                    Text("灰色邊框，線與文字之間四邊各約 12 點內距。")
                        .font(.system(size: 12))
                }
            }

            Text("No line = border() did nothing. Line hugging the text = padding was lost.")
                .font(.system(size: 11))
            Text("沒有線＝border() 什麼都沒做。線緊貼文字＝內距遺失了。")
                .font(.system(size: 11))
        }
    }
}

// MARK: - 4. ControlGroup

/// A `ControlGroup` of three buttons, and the only thing on this screen a click
/// can reach.
///
/// **These buttons are what makes P51 assertable.** Everything else here is
/// drawn at startup, and a line written at startup proves that the app launched,
/// not that anything was clicked -- which is why most Windows action files carry
/// no `# expect:` marker at all. Measured 2026-09-08, and re-derivable:
///
///     ls testapp/actions/win/*.csv | wc -l                        -> 42
///     grep -l '^# expect:' testapp/actions/win/*.csv | wc -l      -> 19
///
/// So 23 of 42 assert nothing, because their app had nothing but startup lines
/// to assert on. Each button below writes a line that exists in no other
/// circumstance, and "Add 3" also adds a fourth row to the grid at the top left,
/// so one press changes the picture as well as the log.
///
/// `ControlGroup`'s body puts its content in `HStack(spacing: 0)` deliberately,
/// so the three buttons TOUCH. That is the visual signature that separates a
/// `ControlGroup` from three buttons in an ordinary `HStack`, and it is worth
/// checking in the picture: gaps between them mean the spacing was not applied.
///
/// 一組三個按鈕的 `ControlGroup`，也是本畫面上唯一點得到的東西。
///
/// **這些按鈕正是使 P51 可被斷言的原因。** 這裡其他的一切都是啟動時畫出來的，而啟動時寫下的一行
/// 只能證明 app 啟動了，不能證明有東西被點到——這正是多數 Windows action 檔根本沒有 `# expect:`
/// 標記的理由。2026-09-08 實測，且可重新推導：
///
///     ls testapp/actions/win/*.csv | wc -l                        -> 42
///     grep -l '^# expect:' testapp/actions/win/*.csv | wc -l      -> 19
///
/// 因此 42 個之中有 23 個什麼都沒斷言，因為它們的 app 除了啟動時的訊息之外無物可斷言。下方每個
/// 按鈕都會寫下一行在任何其他情況下都不存在的訊息，而「Add 3」還會為左上角的網格加上第四列，
/// 因此一次按壓同時改變圖與 log。
///
/// `ControlGroup` 的 body 刻意把內容放進 `HStack(spacing: 0)`，所以三個按鈕是**緊貼**的。那正是
/// 區分「一個 ControlGroup」與「一般 HStack 裡的三個按鈕」的視覺特徵，而且值得在圖上檢查：
/// 它們之間若有間隙，代表該間距沒有被套用。
struct P51ControlGroupSection: View {
    @Binding var cellCount: Int
    var rowCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("4. ControlGroup -- these buttons drive the LazyVGrid on the left")
                .font(.system(size: 15))

            ControlGroup("LazyVGrid cell count") {
                Button("Add 3") {
                    cellCount += 3
                    P51Diagnostics.write(
                        "controlgroup add -- lazyvgrid cells: \(cellCount)"
                    )
                }
                Button("Remove 3") {
                    // Never below one full row. A grid of zero cells draws
                    // nothing, and "nothing" is the picture a broken LazyVGrid
                    // would also produce -- the app must not be able to reach a
                    // state it cannot tell apart from a failure.
                    // 絕不低於一整列。零格的網格什麼也不畫，而「什麼也沒有」也正是一個壞掉的
                    // LazyVGrid 會產生的畫面——這支 app 不可以有辦法走到一個「它自己分不出是不是
                    // 失敗」的狀態。
                    cellCount = max(3, cellCount - 3)
                    P51Diagnostics.write(
                        "controlgroup remove -- lazyvgrid cells: \(cellCount)"
                    )
                }
                Button("Reset to 9") {
                    cellCount = 9
                    P51Diagnostics.write(
                        "controlgroup reset -- lazyvgrid cells: \(cellCount)"
                    )
                }
            }

            Text("The three buttons must touch: ControlGroup uses HStack(spacing: 0).")
                .font(.system(size: 11))
            Text("三個按鈕必須緊貼：ControlGroup 使用 HStack(spacing: 0)。")
                .font(.system(size: 11))
            Text("now \(cellCount) cells in \(rowCount) rows")
                .font(.system(size: 11))
        }
    }
}

// MARK: - 5. LabelStyle

/// One label text and one icon, drawn four times, once per style.
///
/// **The four are in ONE `HStack`, in this order, on purpose.** 6cefefb9's claim
/// is that `.automatic` and `.titleAndIcon` are not merely similar but the same
/// expression: `DefaultLabelStyle.makeBody` calls `TitleAndIconLabelStyle`
/// rather than repeating its `HStack(spacing: 6)`, so that two copies cannot
/// drift apart silently. Adjacent columns is where that claim becomes something
/// a reader settles at a glance; put them at opposite ends of the row and
/// "identical" turns into a memory test.
///
/// What each column must show:
///
///   - `.automatic`    -> icon, then "Refresh"
///   - `.titleAndIcon` -> icon, then "Refresh"   (must match the column left of it)
///   - `.titleOnly`    -> "Refresh", no icon
///   - `.iconOnly`     -> icon, no "Refresh"
///
/// The word "Refresh" appearing in three columns and absent from the fourth is
/// the whole of the `.iconOnly` check, and its presence alone in the third is
/// the whole of `.titleOnly`.
///
/// **The title is "Refresh" and the symbol is "sync", and they must not be the
/// same word.** The icon is `SystemSymbol` `"sync"`, which on a backend with no
/// glyph for it falls back to TEXT rather than to a blank -- P47's finding --
/// and that fallback text is, verbatim, `"Sync"`
/// (`Symbols/SystemSymbol+Table.swift`, the `textFallback:` field). Titling the
/// label "Sync" therefore made `.titleOnly` and `.iconOnly` render the identical
/// word on any such backend, and `.automatic` render "Sync Sync". This file did
/// exactly that until the table was read. A different title word keeps all four
/// columns distinguishable whether the glyph resolves or falls back.
///
/// So an EMPTY icon column here is a `LabelStyle` failure, never a missing
/// symbol; and a column reading "Sync Refresh" is a symbol fallback, not a
/// duplicated title.
///
/// 同一段 label 文字與同一個圖示，畫四次，每種樣式一次。
///
/// **這四個刻意放在同一個 `HStack` 裡，並且刻意依此順序排列。** 6cefefb9 的主張是：`.automatic`
/// 與 `.titleAndIcon` 不只是相似，而是**同一個表達式**——`DefaultLabelStyle.makeBody` 呼叫
/// `TitleAndIconLabelStyle`，而不是把它的 `HStack(spacing: 6)` 抄一遍，如此兩份副本才無法悄悄
/// 漂移。相鄰的兩欄，正是該主張變成「讀者一眼就能判定」的地方；把它們擺在一列的兩端，「相同」
/// 就變成了記憶力測驗。
///
/// 每一欄必須顯示的內容：
///
///   - `.automatic`    -> 圖示，然後是「Refresh」
///   - `.titleAndIcon` -> 圖示，然後是「Refresh」（必須與其左側那一欄相同）
///   - `.titleOnly`    -> 「Refresh」，沒有圖示
///   - `.iconOnly`     -> 圖示，沒有「Refresh」
///
/// 「Refresh」這個字出現在三欄、在第四欄缺席，就是 `.iconOnly` 檢查的全部；而它單獨出現在第三欄，
/// 就是 `.titleOnly` 的全部。
///
/// **標題是「Refresh」而符號是「sync」，兩者不可以是同一個字。** 圖示是 `SystemSymbol` 的
/// `"sync"`，在沒有對應字符的 backend 上它會退回**文字**而非空白——這是 P47 的發現——而該退路文字
/// 一字不差就是 `"Sync"`（`Symbols/SystemSymbol+Table.swift` 中的 `textFallback:` 欄位）。因此把
/// label 標題取名為「Sync」，會讓 `.titleOnly` 與 `.iconOnly` 在任何這樣的 backend 上畫出完全相同
/// 的字，並讓 `.automatic` 畫成「Sync Sync」。本檔在查閱該表之前正是這麼寫的。改用不同的標題字，
/// 無論字符解析成功或退回文字，四欄都能保持可區分。
///
/// 因此此處若有一欄的圖示是**空的**，那是 `LabelStyle` 的失敗，絕不是缺少符號；而一欄讀作
/// 「Sync Refresh」則是符號退回文字，不是標題重複了。
struct P51LabelStyleSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("5. LabelStyle -- one Label, four styles")
                .font(.system(size: 15))
            Text("Columns 1 and 2 MUST be identical. That is 6cefefb9's claim, checkable here.")
                .font(.system(size: 11))
            Text("第 1 欄與第 2 欄**必須**完全相同。那是 6cefefb9 的主張，在此可被檢查。")
                .font(.system(size: 11))

            // Written out four times rather than driven by a helper taking the
            // style, and the repetition is deliberate. A helper is a shared
            // thing that the first two columns would both pass through, and the
            // one property being checked here is whether two INDEPENDENTLY
            // written calls come out the same. Factoring that out would make
            // them agree by construction, which is not the same claim.
            //
            // 寫成四份而非由一個接收樣式的 helper 驅動，這份重複是刻意的。helper 是一個共用的東西，
            // 而前兩欄都會通過它；此處要檢查的那一項性質，正是「兩個**各自獨立**寫出來的呼叫是否
            // 得到相同結果」。把它抽出來會讓兩者因構造而必然一致——那是另一個主張了。
            //
            // No border on these four. A grey outline here would be the same
            // grey outline the GroupBox draws two sections up, and "the only
            // grey box on the screen" is how that section is identified. The
            // captions already tie each label to its style.
            //
            // 這四欄不加邊框。此處的灰色描邊會與上方兩個區塊之外 GroupBox 所畫的灰色描邊相同，而
            // 「畫面上唯一的灰色方框」正是辨識該區塊的方式。各欄的說明文字本身已經把 label 與它的
            // 樣式綁在一起了。
            HStack(alignment: .top, spacing: 18) {
                VStack(spacing: 4) {
                    Text(".automatic")
                        .font(.system(size: 11))
                    Label("Refresh", systemImage: "sync")
                        .labelStyle(.automatic)
                }

                VStack(spacing: 4) {
                    Text(".titleAndIcon")
                        .font(.system(size: 11))
                    Label("Refresh", systemImage: "sync")
                        .labelStyle(.titleAndIcon)
                }

                VStack(spacing: 4) {
                    Text(".titleOnly")
                        .font(.system(size: 11))
                    Label("Refresh", systemImage: "sync")
                        .labelStyle(.titleOnly)
                }

                VStack(spacing: 4) {
                    Text(".iconOnly")
                        .font(.system(size: 11))
                    Label("Refresh", systemImage: "sync")
                        .labelStyle(.iconOnly)
                }
            }

            Text("automatic = titleAndIcon = icon + Refresh; titleOnly = Refresh; iconOnly = icon.")
                .font(.system(size: 11))
            Text("An icon drawn as the word Sync is a symbol fallback, not a second title.")
                .font(.system(size: 11))
            Text("圖示被畫成 Sync 這個字，是符號退回文字，不是第二個標題。")
                .font(.system(size: 11))
        }
    }
}

