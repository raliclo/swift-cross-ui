import DefaultBackend
import Foundation
import SwiftCrossUI

// P17 cross-backend layout comparison: ideal sizing, picker sizing, and two
// documented layout edge cases.
//
// - #264 frame(idealWidth:idealHeight:) sets only the view's full idealSize,
//   not its idealWidthForHeight / idealHeightForWidth. Those are what
//   fixedSize(horizontal:vertical:) reads, so asking for an ideal width and
//   then fixing the horizontal axis does not produce the requested width.
//   SwiftUI does set it for basic cases such as frame(idealWidth: 100) on a
//   text view.
// - #161 Some backends size a Picker from its currently selected item, others
//   from its largest item. Upstream wants this consistent, and leans towards
//   sizing by the largest item.
// - #266 Two layout edge cases upstream wrote down while specifying the layout
//   algorithm, both of which must keep working after any ScrollView or stack
//   optimisation:
//     (a) A constant-aspect-ratio view inside a ScrollView that is slightly too
//         short. The scroll bar has to be shown, but showing it narrows the
//         content, which shortens it via the aspect ratio, which can make the
//         scroll bar look unnecessary. Upstream reports SwiftUI flickering here
//         and believes SwiftCrossUI handles it correctly but inefficiently.
//     (b) An ideal-width VStack given a proposed height. Each child should take
//         its ideal width, the stack should take the widest child's width, and
//         the other children should then expand to match.
//
// Unlike P7-P16 this app is not aimed at one backend. Every check here is a
// comparison: the same build is run under GtkBackend and WinUIBackend and the
// numbers are compared. For #161 that comparison *is* the issue -- it is about
// backends disagreeing, so a single-backend result cannot answer it.
//
// Build this file as a standalone app target.

enum P17Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false
    nonisolated(unsafe) private static var lastReported: [String: String] = [:]

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P17] \(message)")

        guard let data = "P17 \(Date()) \(message)\n".data(using: .utf8) else { return }
        // SCUI_DEBUG_EVENTS_DIR when a launcher sets it, so every app's log lands
        // in one place; unset, the launch directory exactly as before. The
        // contract is documented in testapp/test_support/test_common.zsh.
        // 有 SCUI_DEBUG_EVENTS_DIR 時取自該變數，讓每支 app 的 log 集中一處；未設定時仍為啟動
        // 目錄，行為與過去完全相同。該約定記載於 testapp/test_support/test_common.zsh。
        let url = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
            ?? FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p17-debug-events.log")
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

    static func record(label: String, size: ViewSize) {
        guard isEnabled else { return }
        let line = "\(label): \(Int(size.width)) x \(Int(size.height))"
        guard lastReported[label] != line else { return }
        lastReported[label] = line
        write(line)
    }

    static func renderComplete() {
        guard !didAnnounceRender else { return }
        didAnnounceRender = true
        write("RENDER COMPLETE -- P17 ready for #264, #161, and #266 checks")
    }
}

@main
@HotReloadable
struct P17LayoutComparisonApp: App {
    var body: some Scene {
        WindowGroup("P17 cross-backend layout") {
            #hotReloadable {
                P17RootView()
            }
        }
        .defaultSize(width: 900, height: 760)
    }
}

// Deliberately very different lengths. If the picker is sized from the
// selected item its width changes as the selection moves; if it is sized from
// the largest item the width stays put.
let p17Options = [
    "S",
    "A medium option",
    "An extremely long option label that dwarfs the others",
]

struct P17RootView: View {
    @State var selection: String? = "S"
    @State var scrollHeight = 120.0
    @State var stackHeight = 140.0
    @State var status = "Run this on both backends and compare the numbers."

    /// One character per button pressed, in order.
    ///
    /// The action file presses Longest and then Shortest, which returns the
    /// picker to the value it started at. A capture taken afterwards is
    /// identical to one taken from an app nobody touched, so without this the
    /// first two rows cannot be verified from a photograph at all -- and a row
    /// that lands nowhere raises nothing either. The trail distinguishes "these
    /// four presses arrived, in this order" from "the file ran and missed".
    ///
    /// 每按下一顆按鈕記一個字元,依順序排列。
    ///
    /// 動作檔會按下 Longest、接著按下 Shortest,而那會讓 picker 回到它一開始的值。事後拍下的畫面
    /// 與「一支沒有人碰過的 app」完全相同,因此少了這一行,前兩列根本無法從照片上驗證——而一次落在
    /// 空處的點擊同樣不會引發任何東西。這條軌跡能分辨「這四次按下都抵達了,而且是這個順序」與
    /// 「檔案跑完了但全部落空」。
    @State var trail = ""


    var body: some View {
        VStack(spacing: 14) {
            Text("P17: cross-backend layout comparison")
                .font(.system(size: 20))

            Text(status)
                .frame(width: 840, alignment: .leading)
            // Centred, not leading, while every other line here is leading.
            //
            // P17's content is about 880 pt wide and the window is 393, so a
            // left-aligned line sits at x 0 and is off screen for the whole of
            // an action file that has to scroll right to reach the buttons --
            // the one line whose job is to say what happened would be the one
            // line the photograph cannot show.
            //
            // 置中而非靠左,而此處其他每一行都是靠左的。
            //
            // P17 的內容約 880 點寬而視窗為 393 點,因此一個靠左對齊的行會位於 x 0——對於一份「必須
            // 先向右捲動才碰得到按鈕」的動作檔而言,它在整個過程中都在畫面之外。那樣一來,唯一負責
            // 說明「發生了什麼」的那一行,就會是照片唯一拍不到的那一行。
            Text("presses: \(trail.isEmpty ? "(none)" : trail)")
                .frame(width: 840, alignment: .center)

            // ---- #264 -------------------------------------------------------
            VStack(alignment: .leading, spacing: 6) {
                Text("Ideal width and fixedSize (#264)")

                HStack(spacing: 16) {
                    // The subject: an ideal width, then the horizontal axis
                    // fixed. Its width should come out near 160.
                    VStack(alignment: .leading, spacing: 2) {
                        Text("idealWidth 160 + fixedSize(h:)")
                        P17Measured(label: "subject") {
                            Text("A sentence long enough that its ideal width matters here")
                                .frame(idealWidth: 160)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }

                    // The control: same text, same ideal width, no fixedSize.
                    // Any difference between the two is what #264 is about.
                    VStack(alignment: .leading, spacing: 2) {
                        Text("idealWidth 160 only")
                        P17Measured(label: "control") {
                            Text("A sentence long enough that its ideal width matters here")
                                .frame(idealWidth: 160)
                        }
                    }
                }
            }

            // ---- #161 -------------------------------------------------------
            VStack(alignment: .leading, spacing: 6) {
                Text("Picker sizing (#161)")

                Text("Selected: \(selection ?? "none")")

                P17Measured(label: "picker") {
                    Picker(of: p17Options, selection: $selection)
                }

                HStack(spacing: 8) {
                    Button("Shortest") {
                        selection = p17Options[0]
                        trail += "S"
                        status = "Picker set to the shortest option."
                    }
                    Button("Medium") {
                        selection = p17Options[1]
                        trail += "M"
                        status = "Picker set to the medium option."
                    }
                    Button("Longest") {
                        selection = p17Options[2]
                        trail += "L"
                        status = "Picker set to the longest option."
                    }
                }

                Text("Width changing with the selection means it is sized from")
                Text("the selected item; a constant width means the largest item.")
            }

            // ---- #266 (a) ---------------------------------------------------
            VStack(alignment: .leading, spacing: 6) {
                Text("Aspect ratio inside a ScrollView (#266a)")

                // A 2:1 view inside a scroll view whose height is adjustable in
                // small steps, so the height where the scroll bar appears can
                // be walked over rather than guessed.
                ScrollView {
                    // Teal, not purple. GtkBackend renders `Color.purple` as
                    // #db34f2, which reads as pink at a glance and collides
                    // with the hotpink a GTK transform node paints when the
                    // renderer cannot draw it -- a defect signal this project
                    // counts pixels of. This block is large and fills a scroll
                    // view, so it is the worst place in the suite to put that
                    // hue. See the same change in P16.swift for the measurement.
                    //
                    // 用 teal，不用 purple。GtkBackend 把 `Color.purple` 繪為 #db34f2，一眼望去
                    // 就是粉色，而它與「GTK 在 renderer 無法繪製 transform node 時所畫的 hotpink」
                    // 相衝——後者是本專案會逐像素計數的缺陷訊號。這個色塊面積大又填滿整個 scroll
                    // view，是全套件中最不該放上該色相之處。量測見 P16.swift 的同一項改動。
                    Color.teal
                        .aspectRatio(2.0, contentMode: .fit)
                }
                .frame(width: 300, height: scrollHeight)

                HStack(spacing: 8) {
                    Button("Shorter (\(Int(scrollHeight)))") {
                        trail += "-"
                        scrollHeight = max(40, scrollHeight - 5)
                        status = "Scroll view height \(Int(scrollHeight))."
                    }
                    Button("Taller") {
                        trail += "+"
                        scrollHeight = min(240, scrollHeight + 5)
                        status = "Scroll view height \(Int(scrollHeight))."
                    }
                }

                Text("Step through the heights. The scroll bar may appear and")
                Text("disappear, but it must settle rather than flicker.")
            }

            // ---- #266 (b) ---------------------------------------------------
            VStack(alignment: .leading, spacing: 6) {
                Text("Ideal-width VStack with a proposed height (#266b)")

                // Children of different natural widths, in a stack given a
                // fixed height. All three should end up the width of the
                // widest, and the reported widths say whether they did.
                P17Measured(label: "stack") {
                    VStack(spacing: 2) {
                        Text("Short")
                            .background(Color.blue)
                        Text("A somewhat longer line")
                            .background(Color.green)
                        Text("Mid length")
                            .background(Color.orange)
                    }
                    .frame(height: stackHeight)
                }

                HStack(spacing: 8) {
                    Button("Less height (\(Int(stackHeight)))") {
                        trail += "<"
                        stackHeight = max(40, stackHeight - 20)
                        status = "Stack height \(Int(stackHeight))."
                    }
                    Button("More height") {
                        trail += ">"
                        stackHeight = min(300, stackHeight + 20)
                        status = "Stack height \(Int(stackHeight))."
                    }
                }

                Text("The three coloured bands should all end up the same width.")
            }
        }
        .padding(16)
        .onAppear {
            P17Diagnostics.renderComplete()
        }
    }
}

// Reports the size of the view it wraps, so a result can be written down and
// compared between backends instead of being described.
//
// The reader goes in an overlay, which is the only arrangement here that
// measures the subject rather than something else. OverlayModifier lays the
// content out against the original proposal first and then proposes exactly
// that size to the overlay, and a GeometryReader takes the size proposed to it
// and no more -- so the reader reports the subject's own size, and cannot grow
// the result while doing it. Putting the reader beside the subject in an HStack
// would only ever report the reader's own slot, and wrapping the subject in one
// would replace the subject's sizing with the reader's.
//
// The readout is drawn on top of the subject on purpose. What is under test is
// the subject's box, not its contents, and the coloured background makes the
// box visible where the text is covered.
struct P17Measured<Content: View>: View {
    var label: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background(Color.blue)
            .overlay(alignment: .topLeading) {
                GeometryReader { proxy in
                    let _ = P17Diagnostics.record(label: label, size: proxy.size)
                    // Opaque, so the two texts do not interleave glyph by
                    // glyph. Without it the readout and the sentence underneath
                    // render into the same pixels and the result --
                    // "Auhiedentt5e9lon22en..." -- is neither of them.
                    //
                    // The label stays an OVERLAY. It was moved below the box in
                    // a VStack once, which read better and made the app's
                    // layout depend on the readout's own height: three
                    // consecutive runs reported the subject box as 159 x 22,
                    // 169 x 22 and 159 x 66, and the action file's coordinates
                    // missed every button that had moved. An overlay
                    // contributes no size, which is why this app was written
                    // with one.
                    //
                    // 不透明,好讓兩段文字不再一個字一個字地互相穿插。少了它,這段讀數與底下那句話
                    // 會繪製進同一批像素,而其結果——「Auhiedentt5e9lon22en…」——兩者都不是。
                    //
                    // 這個標籤維持為 **overlay**。它曾被移到框下方的一個 VStack 中,那樣比較好讀,
                    // 也讓這支 app 的版面取決於讀數本身的高度:連續三次執行分別把 subject 那格回報為
                    // 159 x 22、169 x 22 與 159 x 66,而動作檔的座標錯過了每一顆位置改變過的按鈕。
                    // overlay 不貢獻任何尺寸,而那正是這支 app 當初以 overlay 寫成的原因。
                    Text("\(label): \(Int(proxy.size.width)) x \(Int(proxy.size.height))")
                        .background(Color.white)
                }
            }
    }
}
