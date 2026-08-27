import DefaultBackend
import Foundation
import SwiftCrossUI

// P13 layout and view-graph repro app: ForEach identity, scroll view text
// clipping, split view minimum width, and Group inside ZStack.
//
// - #415 The message list benchmark crashes with AppKitBackend. Upstream traced
//   it to the fallback codepath for non-Identifiable ForEach elements handing
//   the backend duplicate child views; making the element Identifiable works
//   around it.
// - #595 Text inside a ScrollView is cut off when it should not be.
//   `.fixedSize()` works around it. Introduced between 0.3.0 and 0.4.0.
// - #291 NavigationSplitView deduces its minimum width correctly but never
//   moves the split to honour it. Upstream reports AppKitBackend affected and
//   GtkBackend not.
// - #158 A Group inside a ZStack lays its children out along the container's
//   orientation instead of the z axis.
//
// #415 crashes on purpose, so it is behind a button rather than on the launch
// path: everything else stays testable in the same run.
//
// Build this file as a standalone app target.

enum P13Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P13] \(message)")

        guard let data = "P13 \(Date()) \(message)\n".data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p13-debug-events.log")
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
        write("RENDER COMPLETE -- P13 ready for #415, #595, #291, and #158 checks")
    }
}

@main
@HotReloadable
struct P13LayoutApp: App {
    var body: some Scene {
        WindowGroup("P13 layout and view graph") {
            #hotReloadable {
                P13RootView()
            }
        }
        .defaultSize(width: 900, height: 760)
    }
}

// Deliberately NOT Identifiable: this is the type that drives #415 down the
// fallback path. P13IdentifiableMessage below is the control.
struct P13Message {
    var author: String
    var body: String
}

struct P13IdentifiableMessage: Identifiable {
    var id: Int
    var author: String
    var body: String
}

/// One square of the z-order check.
///
/// `Identifiable` on purpose. `ForEach` reaches the backend's
/// `swap(childAt:withChildAt:in:)` through its identity-diffing path; the
/// fallback for non-`Identifiable` elements is the one #415 above is about, and
/// it hands the backend duplicate child views instead of reordering them. A
/// check of reordering has to take the path that reorders.
///
/// z 順序檢查中的一個方塊。
///
/// 刻意採用 `Identifiable`。`ForEach` 是經由其身分比對（identity diffing）路徑觸達 backend 的
/// `swap(childAt:withChildAt:in:)`；而非 `Identifiable` 元素所走的退路，正是上方 #415 所述的那一條
/// ——它交給 backend 的是重複的子 view，而非重新排序。要檢查「重新排序」，就必須走真正會重新排序的
/// 那條路徑。
struct P13ZSquare: Identifiable {
    let id: String
    let color: SwiftCrossUI.Color
    let side: Int

    /// Descending size, so the last one drawn is the smallest and sits fully
    /// visible in the middle. That is what makes "which colour is in the
    /// middle" a direct reading of "which child is on top".
    /// 尺寸遞減，因此最後被繪製的最小、且完整可見地位於中央。這正是使「中央是什麼顏色」成為
    /// 「哪個子元件在最上層」之直接讀數的原因。
    static let forward = [
        P13ZSquare(id: "red", color: .red, side: 150),
        P13ZSquare(id: "green", color: .green, side: 100),
        P13ZSquare(id: "blue", color: .blue, side: 50),
    ]

    static let reversed = Array(forward.reversed())
}

struct P13RootView: View {
    @State var showsUnidentifiedList = false
    @State var duplicateCount = 3
    @State var splitWidth = 400.0
    @State var status = "Ready. #415 is behind a button because it crashes."
    @State var zOrderIsReversed = false

    // Every element is identical, which is what makes the non-Identifiable
    // fallback produce duplicate child views.
    var duplicatedMessages: [P13Message] {
        (0..<duplicateCount).map { _ in
            P13Message(author: "Same", body: "Identical message")
        }
    }

    var identifiableMessages: [P13IdentifiableMessage] {
        (0..<duplicateCount).map {
            P13IdentifiableMessage(id: $0, author: "Same", body: "Identical message")
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            Text("P13: layout and view graph")
                .font(.system(size: 20))

            Text(status)
                .frame(width: 840, alignment: .leading)

            // ---- #415 ------------------------------------------------------
            VStack(alignment: .leading, spacing: 6) {
                Text("ForEach identity (#415)")

                HStack(spacing: 10) {
                    Button("More duplicates (\(duplicateCount))") {
                        duplicateCount += 1
                        status = "Now \(duplicateCount) identical elements."
                    }

                    Button(showsUnidentifiedList ? "Hide unidentified list" :
                        "Show unidentified list (may crash)")
                    {
                        showsUnidentifiedList.toggle()
                        status = showsUnidentifiedList
                            ? "Rendering non-Identifiable ForEach: this is the #415 path."
                            : "Unidentified list hidden."
                    }
                }

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Identifiable (control)")
                        ForEach(identifiableMessages) { message in
                            Text("\(message.author): \(message.body)")
                        }
                    }
                    .frame(width: 260, alignment: .leading)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Non-Identifiable (#415)")
                        if showsUnidentifiedList {
                            // The fallback codepath: no id keypath, and every
                            // element compares equal. That init is deprecated,
                            // so this line warns at build time on purpose --
                            // adding `id:` to silence the warning takes the
                            // Identifiable path and removes the repro.
                            ForEach(duplicatedMessages) { message in
                                Text("\(message.author): \(message.body)")
                            }
                        } else {
                            Text("(hidden)")
                        }
                    }
                    .frame(width: 260, alignment: .leading)
                }
            }

            // ---- #595 ------------------------------------------------------
            VStack(alignment: .leading, spacing: 6) {
                Text("Text clipping inside a ScrollView (#595)")

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Plain (#595)")
                        ScrollView {
                            Text(
                                "This sentence is long enough that it has to wrap, "
                                    + "and it must not be cut off at the bottom."
                            )
                            .padding(4)
                        }
                        .frame(width: 300, height: 80)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("With .fixedSize() (workaround)")
                        ScrollView {
                            Text(
                                "This sentence is long enough that it has to wrap, "
                                    + "and it must not be cut off at the bottom."
                            )
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(4)
                        }
                        .frame(width: 300, height: 80)
                    }
                }
            }

            // ---- #291 ------------------------------------------------------
            VStack(alignment: .leading, spacing: 6) {
                Text("NavigationSplitView minimum width (#291)")

                HStack(spacing: 10) {
                    Button("Narrower (\(Int(splitWidth)))") {
                        splitWidth = max(120, splitWidth - 60)
                        status = "Split view frame is now \(Int(splitWidth)) px wide."
                    }

                    Button("Wider") {
                        splitWidth = min(760, splitWidth + 60)
                        status = "Split view frame is now \(Int(splitWidth)) px wide."
                    }
                }

                NavigationSplitView {
                    VStack(alignment: .leading) {
                        Text("Sidebar")
                        Text("Has its own minimum")
                    }
                    .padding(6)
                } detail: {
                    VStack(alignment: .leading) {
                        Text("Detail")
                        Text("Should stay visible as the frame shrinks")
                    }
                    .padding(6)
                }
                .frame(width: splitWidth, height: 120)
            }

            // ---- #158 ------------------------------------------------------
            VStack(alignment: .leading, spacing: 6) {
                Text("Group inside ZStack (#158)")

                // The three colours should stack along z and overlap, so only
                // the smallest stays fully visible on top. Laid out side by
                // side or vertically instead means the Group took the
                // container's orientation.
                ZStack {
                    Group {
                        Color.red.frame(width: 180, height: 90)
                        Color.green.frame(width: 120, height: 60)
                        Color.blue.frame(width: 60, height: 30)
                    }
                }
                .frame(width: 220, height: 110)
            }

            // ---- z-order after a ForEach reorder --------------------------
            //
            // The static ZStack above cannot catch this: it never reorders, so
            // the backend's `swap(childAt:withChildAt:in:)` is never called.
            // That method is reached only from `ForEach`, and only shows on
            // screen when the reordered children overlap -- so a ForEach inside
            // a ZStack is the one arrangement that can see it.
            //
            // GtkBackend used to swap only SwiftCrossUI's own bookkeeping array
            // and leave GTK's sibling order alone, with a comment saying
            // overlapping widgets "may end up with unexpected z ordering". The
            // squares are sized so the answer is unambiguous: the last one in
            // the array is drawn on top and is the smallest, so whichever
            // colour is fully visible in the middle names the topmost child.
            //
            // Press Reverse. The middle square must change colour. If it does
            // not, the array was swapped and the widgets were not.
            //
            // ---- ForEach 重新排序之後的 z 順序 ----
            //
            // 上方的靜態 ZStack 抓不到這件事：它從不重新排序，因此 backend 的
            // `swap(childAt:withChildAt:in:)` 永遠不會被呼叫。該方法只會由 `ForEach` 觸達，且唯有
            // 在被重排的子元件彼此重疊時才會顯現於畫面上——所以「ZStack 裡放 ForEach」是唯一看得見
            // 它的排列方式。
            //
            // GtkBackend 過去只交換 SwiftCrossUI 自己的記帳陣列，完全不動 GTK 的兄弟順序，其註解
            // 寫著重疊的 widget「可能得到非預期的 z 順序」。此處方塊的尺寸刻意使答案毫無歧義：陣列
            // 中最後一個會畫在最上層，而它也是最小的，因此「中央完整可見的顏色」即指出了最上層的
            // 子元件是誰。
            //
            // 按下 Reverse，中央方塊必須換色。若沒有換，代表陣列被交換了，而 widget 沒有。
            VStack(alignment: .leading, spacing: 6) {
                Text("z-order after a ForEach reorder")
                Text("Top of the stack: \(zOrderIsReversed ? "red" : "blue")")

                ZStack {
                    ForEach(zOrderIsReversed ? P13ZSquare.reversed : P13ZSquare.forward) { square in
                        square.color.frame(width: square.side, height: square.side)
                    }
                }
                .frame(width: 220, height: 110)

                Button("Reverse") {
                    zOrderIsReversed.toggle()
                    P13Diagnostics.write(
                        "z-order reversed -- top should now be "
                            + (zOrderIsReversed ? "red" : "blue")
                    )
                }
            }
        }
        .padding(18)
        .onAppear {
            P13Diagnostics.renderComplete()
        }
    }
}
