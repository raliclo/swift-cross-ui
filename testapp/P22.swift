import DefaultBackend
import Foundation
import SwiftCrossUI

// P22 text styles, for comparing WinUIBackend against GtkBackend.
//
// Modelled on the Text Styles panel in gtk4-widget-factory: a size scale from
// large title down to caption, shown together so the steps between them can be
// compared rather than each size in isolation.
//
// This one is worth doing early because font metrics are the measuring stick
// for every other layout comparison. A backend whose text is systematically
// wider will produce different results in P17's sizing checks, in P7's split
// view ratios and in anything else measured in pixels, and without this app
// that difference gets attributed to the layout code instead of the font.
//
// Each sample reports the size the layout system gave it, so the comparison is
// numbers rather than an impression of the screenshots.
//
// P22 文字排版，用於比較 WinUIBackend 與 GtkBackend。
//
// 形式參考 gtk4-widget-factory 的 Text Styles 面板：從大標題到說明文字的字級階梯，並列
// 呈現，使各級之間的級距可供比較，而非孤立地看單一字級。
//
// 這一項值得優先進行，因為字型度量是其他所有版面比較的量尺。若某個 backend 的文字系統性
// 地較寬，它會在 P17 的尺寸檢查、P7 的 split view 比例，以及任何以像素量測的項目中產生
// 不同結果；少了這支 app，該差異會被歸咎於版面程式碼而非字型。
//
// 每個樣本都會回報 layout 系統給予它的尺寸，因此比較的是數字，而非對截圖的印象。
//
// Build this file as a standalone app target.

enum P22Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false
    nonisolated(unsafe) private static var lastReported: [String: String] = [:]

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P22] \(message)")

        guard let data = "P22 \(Date()) \(message)\n".data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p22-debug-events.log")
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

    // Only logged when it changes. A size that is reported on every layout pass
    // buries the one line that matters under hundreds of identical ones.
    // 僅在變動時記錄。若每次 layout 都回報尺寸，真正重要的那一行會被數百行相同內容淹沒。
    /// Same guard as P23's, for the same reason: `Int(_:)` traps on infinity
    /// and NaN, and a proposed size can be unbounded. P22's samples are all
    /// bounded today, so this has never fired here -- it is here because the
    /// identical line in P23 did, and leaving one of a pair unfixed is how it
    /// comes back.
    /// 與 P23 相同的防護，理由相同：`Int(_:)` 對無限大與 NaN 會 trap，而提出的尺寸可能無上限。
    /// P22 目前的樣本都是有界的，因此此處從未觸發——它存在的理由是 P23 中完全相同的那一行確實
    /// 觸發過，而修了一對中的其中一個，正是它捲土重來的方式。
    private static func describe(_ value: Double) -> String {
        value.isFinite ? "\(Int(value))" : "unbounded"
    }

    // Stored, not written. A GeometryReader's closure runs on every layout
    // pass, and the layout system probes each view's flexibility by proposing
    // it width 0 and width infinity before the real layout. Under those probes
    // the wrapping sample text collapses to a tall thin strip or stretches wide,
    // so writing on every change produced two contradictory lines per sample --
    // one real, one degenerate. P22 exists to compare the real widths, and two
    // numbers per sample leave nothing to compare.
    //
    // Keeping only the latest value per label and flushing once, after the
    // window has settled, reports the committed layout: the real distribution
    // runs after the flexibility probes, so the last size recorded for a label
    // is the one on screen.
    //
    // 只儲存、不即時寫入。GeometryReader 的 closure 在每一次 layout pass 都會執行，而 layout
    // 系統會在真正布局之前，以寬度 0 與寬度無限大探測每個 view 的彈性。在這些探測之下，會換行的
    // 樣本文字會塌縮成細高長條或被拉寬，因此「每次變動就寫入」會使每個樣本產生兩行互相矛盾的結果
    // ——一行真實、一行退化。P22 的目的是比較真實寬度，而每個樣本兩個數字等於沒有東西可比。
    //
    // 只保留每個 label 的最新值、並於視窗穩定後一次輸出，即可回報已提交的布局：真正的分配發生於
    // 彈性探測之後，因此某個 label 最後被記錄的尺寸，正是螢幕上的那一個。
    static func record(label: String, size: ViewSize) {
        guard isEnabled else { return }
        lastReported[label] = "\(describe(size.width)) x \(describe(size.height))"
    }

    // Deferred, because onAppear fires before layout has recorded anything.
    // onAppear runs when the view is added, and the sample sizes are recorded
    // during the layout passes that follow -- so flushing immediately reported
    // an empty set. A second is long after the window has settled; by then each
    // label holds its committed size.
    // 延後執行，因為 onAppear 在 layout 記錄任何內容之前就會觸發。onAppear 在 view 被加入時執行，
    // 而樣本尺寸是在其後的 layout pass 中記錄的——因此立即輸出會回報一組空值。一秒遠在視窗穩定
    // 之後；屆時每個 label 都已持有其已提交的尺寸。
    static func renderComplete() {
        guard !didAnnounceRender else { return }
        didAnnounceRender = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            for label in lastReported.keys.sorted() {
                write("\(label): \(lastReported[label]!)")
            }
            write("RENDER COMPLETE -- P22 ready for text style checks")
        }
    }
}

@main
@HotReloadable
struct P22TextStylesApp: App {
    var body: some Scene {
        WindowGroup("P22 text styles") {
            #hotReloadable {
                P22RootView()
            }
        }
        .defaultSize(width: 760, height: 700)
    }
}

// The same string at every size, so a width difference is the font and nothing
// else. Mixed content would make it ambiguous.
// 每個字級都使用同一個字串，如此寬度差異就只可能來自字型。若內容不同，差異的來源便無法確定。
let p22Sample = "Hamburgefonstiv 123"

struct P22RootView: View {
    @State var wrapWidth = 300.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("P22: text styles")
                    .font(.system(size: 20))

                Text("backend -> \(String(describing: DefaultBackend.self))")

                Text(
                    "The same string at each size. Compare the reported widths "
                        + "across backends, not the appearance."
                )

                Divider()

                P22Sample(label: "34 large title", size: 34)
                P22Sample(label: "28 title 1", size: 28)
                P22Sample(label: "22 title 2", size: 22)
                P22Sample(label: "20 title 3", size: 20)
                P22Sample(label: "17 body", size: 17)
                P22Sample(label: "15 subheadline", size: 15)
                P22Sample(label: "13 footnote", size: 13)
                P22Sample(label: "11 caption", size: 11)

                Divider()

                // Wrapping at a fixed width. Where the break lands is decided by
                // the font's metrics, so this is the same question as the sizes
                // above asked a different way.
                // 於固定寬度換行。斷行位置由字型度量決定，因此這與上方的字級問題是同一件事
                // 的另一種問法。
                Text("Wrapping at \(Int(wrapWidth))pt")
                P22Measured(label: "wrapped") {
                    Text(
                        "The quick brown fox jumps over the lazy dog while the "
                            + "typesetter counts every advance width."
                    )
                    .frame(width: wrapWidth)
                }

                HStack(spacing: 8) {
                    Button("Narrower") { wrapWidth = max(150, wrapWidth - 50) }
                    Button("Wider") { wrapWidth = min(600, wrapWidth + 50) }
                }

                Divider()

                Text("Alignment inside a fixed width")
                VStack(spacing: 4) {
                    Text("leading").frame(width: 320, alignment: .leading)
                    Text("center").frame(width: 320, alignment: .center)
                    Text("trailing").frame(width: 320, alignment: .trailing)
                }

                // One view rather than the three this section wants to be
                // (divider, caption, ladder). The enclosing VStack was already
                // at 19 children and SwiftCrossUI's ViewBuilder stops at 20, so
                // adding three produced `extra arguments at positions #21, #22`
                // -- an error that names the call and not the limit.
                // 此處收成一個 view，而非本段落原本想要的三個（分隔線、標題、階梯）。外層 VStack
                // 原已有 19 個子項，而 SwiftCrossUI 的 ViewBuilder 上限為 20，因此加入三個會得到
                // `extra arguments at positions #21, #22`——這個錯誤訊息指出的是呼叫本身，而非上限。
                // Both sections in one child. The enclosing VStack is at the
                // ViewBuilder's 20-argument limit, and exceeding it reports
                // `extra argument in call` against the call rather than naming
                // the limit -- which is what adding the second section did.
                // 兩個段落合為一個子項。外層 VStack 已達 ViewBuilder 的 20 個引數上限，而超過時的
                // 錯誤是針對該呼叫回報「extra argument in call」，並不會指出上限為何——加入第二個
                // 段落時得到的正是這個訊息。
                VStack(alignment: .leading, spacing: 10) {
                    P22Weights()
                    P22LineLimit()
                }
            }
            .padding(18)
        }
        .onAppear {
            P22Diagnostics.write("backend \(String(describing: DefaultBackend.self))")
            P22Diagnostics.renderComplete()
        }
    }
}

/// All nine font weights, one per row, heaviest last.
///
/// Added 2026-08-27. Same argument as the size scale above it: a weight is only
/// judgeable against its neighbours. Nothing in `testapp/` rendered a single
/// `fontWeight` before this, which is why GtkBackend mapping `.semibold` and
/// `.bold` onto the same CSS number went unnoticed -- there was no picture in
/// which they sat next to each other.
///
/// Read it as a ladder: every row must be at least as heavy as the one above,
/// and no two adjacent rows may be identical. Two rows that match exactly is the
/// defect. Note that a family without a face at some weight rounds to the
/// nearest one it has, so identical rows do not by themselves prove the table is
/// wrong -- they prove this platform cannot show a difference there, which is
/// worth knowing either way.
///
/// The name sits in a fixed-width column at a fixed weight and only the sample
/// carries the row's weight, so every row renders the *same glyphs*. The first
/// version of this put the name inside the styled text, which reads well and
/// measures nothing: "semibold — Hamburgefonstiv 123" is a longer string than
/// "bold — ...", so the semibold row came out 242px wide against bold's 209px
/// and the two could not be compared by width at all. Same glyphs in every row
/// means equal width is equal weight, which a screenshot can be measured for
/// rather than squinted at.
///
/// 全部九種字重，每列一種，最重者在最後。
///
/// 於 2026-08-27 加入。理由與其上方的尺寸級距相同：字重唯有與其鄰居並列才判斷得出來。在此之前，
/// `testapp/` 裡沒有任何地方繪製過哪怕一次 `fontWeight`，這正是 GtkBackend 把 `.semibold` 與
/// `.bold` 對映到同一個 CSS 數值卻無人察覺的原因——不存在一張讓它們彼此相鄰的畫面。
///
/// 判讀方式視為階梯：每一列都必須至少與其上一列同重，且相鄰兩列不得完全相同。兩列完全一致即是
/// 缺陷。但請注意，若字族在某個字重上沒有對應的字面，會退到它最接近的那一個，因此「兩列相同」
/// 本身並不足以證明對照表有錯——它證明的是「本平台在該處顯示不出差異」，而那無論如何都值得知道。
///
/// 名稱置於固定寬度、固定字重的欄位中，只有樣本本身帶有該列的字重，因此每一列繪製的都是**同一組
/// 字形**。本段落的第一個版本把名稱寫在已套用樣式的文字之內——那樣好讀，卻量不出任何東西：
/// 「semibold — Hamburgefonstiv 123」比「bold — ...」更長，於是 semibold 那列量得 242px、bold 那列
/// 209px，兩者根本無法以寬度相比。每列都是同一組字形，才能讓「等寬即等重」成立，也才能對截圖進行
/// 量測，而非瞇著眼睛猜。
struct P22Weights: View {
    static let ladder: [(String, Font.Weight)] = [
        ("ultraLight", .ultraLight),
        ("thin", .thin),
        ("light", .light),
        ("regular", .regular),
        ("medium", .medium),
        ("semibold", .semibold),
        ("bold", .bold),
        ("heavy", .heavy),
        ("black", .black),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()

            Text("Weights (all nine, heaviest last)")

            VStack(alignment: .leading, spacing: 2) {
                ForEach(Self.ladder, id: \.0) { row in
                    HStack(spacing: 0) {
                        Text(row.0)
                            .font(.system(size: 13))
                            .frame(width: 90, alignment: .leading)
                        Text(p22Sample)
                            .font(.system(size: 15))
                            .fontWeight(row.1)
                    }
                }
            }
        }
    }
}

/// The same text under the same line limit at two very different font sizes.
///
/// A discriminator for finding 10 of `testapp/gtk-silent-noops.md`, which
/// suspects that GtkBackend computes the line-limit height cap at GTK's default
/// font size whatever font was asked for. The cap is measured through a
/// `measurementCustomLabel` that is created and never added to a window, and
/// this backend has already measured -- twice, for the ambient colour scheme and
/// for the scrollbar width -- that GTK resolves style only for a widget with a
/// root. Whether that extends to the per-widget CSS provider is the open part.
///
/// **How to read it.** Both rows are capped at two lines. Two lines of 30pt text
/// must be taller than two lines of 13pt text. If the two reported heights come
/// out EQUAL, the cap was computed at one font size for both and the defect is
/// real. If they differ roughly in proportion to the font sizes, it is not.
///
/// Nothing in `testapp/` used `lineLimit` before this, which is why the question
/// had stayed open with a `[?]` against it.
///
/// 同一段文字、同樣的行數限制，在兩種差異極大的字級之下。
///
/// 這是 `testapp/gtk-silent-noops.md` 第 10 條發現的判別器——該條懷疑 GtkBackend 無論被要求何種
/// 字型，都以 GTK 的預設字級計算行數限制的高度上限。該上限是透過一個「建立後從未加入任何視窗」
/// 的 `measurementCustomLabel` 量測的，而本 backend 已經量測過兩次——環境配色與捲軸寬度——確認
/// GTK 只會為具有 root 的 widget 解析樣式。這是否也適用於 per-widget 的 CSS provider，才是尚未
/// 確認的部分。
///
/// **判讀方式。** 兩列都被限制為兩行。兩行 30pt 的文字必然高於兩行 13pt 的文字。若回報的兩個高度
/// **相等**，代表上限是以同一個字級為兩者計算的，缺陷屬實；若兩者大致依字級比例不同，則否。
///
/// 在此之前 `testapp/` 中沒有任何地方使用過 `lineLimit`，這正是該問題一直掛著 `[?]` 的原因。
struct P22LineLimit: View {
    static let paragraph = """
        The quick brown fox jumps over the lazy dog while the typesetter counts \
        every advance width and then keeps going for long enough to wrap.
        """

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()

            Text("Line limit at two font sizes (equal heights = finding 10 confirmed)")

            P22Measured(label: "lineLimit2-13pt") {
                Text(Self.paragraph)
                    .font(.system(size: 13))
                    .lineLimit(2)
                    .frame(width: 300)
            }

            P22Measured(label: "lineLimit2-30pt") {
                Text(Self.paragraph)
                    .font(.system(size: 30))
                    .lineLimit(2)
                    .frame(width: 300)
            }
        }
    }
}

struct P22Sample: View {
    var label: String
    var size: Double

    var body: some View {
        P22Measured(label: label) {
            Text("\(label): \(p22Sample)")
                .font(.system(size: size))
        }
    }
}

// The same measuring wrapper P17 uses: a GeometryReader in an overlay, which
// reports the size the layout system actually gave the content. There is no
// onResize modifier in SwiftCrossUI -- assuming one existed cost a compile
// error here.
// 與 P17 相同的量測包裝：置於 overlay 中的 GeometryReader，回報 layout 系統實際給予內容的
// 尺寸。SwiftCrossUI 並沒有 onResize 這類 modifier——先前誤以為存在，代價是此處一個編譯
// 錯誤。
struct P22Measured<Content: View>: View {
    var label: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .overlay(alignment: .topTrailing) {
                GeometryReader { proxy in
                    let _ = P22Diagnostics.record(label: label, size: proxy.size)
                    EmptyView()
                }
            }
    }
}
