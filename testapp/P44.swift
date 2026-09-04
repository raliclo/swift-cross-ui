import DefaultBackend
import Foundation
import SwiftCrossUI

// P44 clipping: does `clipped()` cut a child down to its frame?
//
// Written 2026-09-04 because nothing exercised `BackendFeatures.Clipping` on
// Android, and AndroidBackend did not implement it -- so `clipped()` went
// through `@CastBackend` and would have taken the process down. A missing
// conformance that no app reaches is a gap nobody can see; this app is the one
// that reaches it.
//
// The three cells are the whole test and they have to be read together:
//
//   1. no clipped()  -- the control. The oversized child MUST spill past the
//      frame. If this one is cut, the backend is clipping something it was
//      never asked to clip, which is the defect P40 found on Android and is a
//      different bug from the one below. If it is the frame's size WITH its
//      blue corner still showing, it was resized rather than clipped, which is
//      a third outcome again -- see `P44Child`.
//   2. clipped()     -- MUST be cut to exactly the frame.
//   3. toggled       -- follows the button, so one press turns one cell from
//      the first case into the second while the other two stand still.
//
// A backend that conformed and did nothing would draw all three the same, and
// cell 1 is what makes that legible: three identical spilling cells is a
// failure, not a pass.
//
// P44 裁切：`clipped()` 會把子元件裁到它的 frame 之內嗎？
//
// 於 2026-09-04 撰寫，因為在 Android 上沒有任何東西用到 `BackendFeatures.Clipping`，而
// AndroidBackend 並未實作它——因此 `clipped()` 會走 `@CastBackend`，並會讓整個行程終止。一個
// 「沒有任何 app 會抵達」的缺失 conformance，是一個沒有人看得見的缺口；本 app 就是抵達它的那一個。
//
// 三個格位就是整個測試，而且必須一起讀：
//
//   1. no clipped()  ——對照組。過大的子元件**必須**溢出 frame。若這一格被裁切了，代表該 backend
//      裁切了它從未被要求裁切的東西——那是 P40 在 Android 上發現的缺陷，與下方那一個是不同的 bug。
//   2. clipped()     ——**必須**被裁切到恰好等於 frame。
//   3. toggled       ——跟隨按鈕，因此一次按壓會讓其中一格從第一種情況變成第二種，而另外兩格不動。
//
// 一個「符合 conformance 卻什麼都不做」的 backend 會把三格畫成一樣，而第 1 格正是讓那件事可被讀出
// 的關鍵：三格都同樣溢出是失敗，不是通過。

enum P44Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P44] \(message)")
        let data = Data("P44 \(Date()) \(message)\n".utf8)
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p44-debug-events.log")
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
        write("RENDER COMPLETE -- P44 ready for clipping checks")
    }
}

@main
@HotReloadable
struct P44ClippingApp: App {
    var body: some Scene {
        WindowGroup("P44 clipping") {
            #hotReloadable {
                P44RootView()
            }
        }
        .defaultSize(width: 420, height: 620)
    }
}

/// The frame every cell clips to, and the child that overflows it.
///
/// The child is wider *and* taller, because a backend can clip on one axis and
/// not the other -- a `ScrollView` does exactly that -- and a square overflow
/// would hide it.
///
/// The numbers are round in points so a screenshot can be checked by hand at
/// any density: 120 x 60 for the frame, 200 x 100 for the child.
///
/// 每一格所裁切到的 frame，以及溢出它的那個子元件。
///
/// 該子元件同時更寬**也**更高，因為一個 backend 有可能只在其中一個軸向上裁切——`ScrollView` 正是
/// 如此——而正方形的溢出會把那件事藏起來。
///
/// 這些數字在點上是整數，因此任何 density 下的截圖都可以用手核對：frame 為 120 x 60，
/// 子元件為 200 x 100。
private enum P44Metrics {
    static let frameWidth = 120
    static let frameHeight = 60
    static let childWidth = 200
    static let childHeight = 100
}

struct P44RootView: View {
    @State var clipThirdCell = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("P44: clipped()")
                .font(.system(size: 20))
            Text("backend -> \(String(describing: DefaultBackend.self))")
            Text(
                "The frame is \(P44Metrics.frameWidth) x \(P44Metrics.frameHeight); "
                    + "the orange child is \(P44Metrics.childWidth) x \(P44Metrics.childHeight)."
            )

            Button(clipThirdCell ? "Unclip the third cell" : "Clip the third cell") {
                clipThirdCell.toggle()
                P44Diagnostics.write(
                    "third cell clipped: \(clipThirdCell)"
                )
            }

            Text("third cell: \(clipThirdCell ? "clipped()" : "no clipped()")")

            // Stacked down the page, not across it, and spaced further apart
            // than the child overflows.
            //
            // Across the page these three would need 360 points of cells plus
            // gaps wide enough that a spilling child could not reach its
            // neighbour, and a phone window is 411. Overlap would make "which
            // cell is this orange in?" a question the screenshot could not
            // answer, and running off the edge would make it one the screenshot
            // could not ask.
            //
            // 沿著頁面向下排列，而非橫向排列，且間距大於子元件溢出的幅度。
            //
            // 橫向排列時，這三格需要 360 點的格位，再加上「足以讓溢出的子元件碰不到鄰格」的間距，
            // 而手機視窗只有 411 點。重疊會讓「這塊橘色屬於哪一格？」成為截圖無法回答的問題，
            // 而超出邊緣則會讓它成為截圖無法提出的問題。
            VStack(spacing: 80) {
                P44Cell(label: "no clipped()", clipped: false)
                P44Cell(label: "clipped()", clipped: true)
                P44Cell(label: "toggled", clipped: clipThirdCell)
            }

            Text(
                "Cell 1 must spill, cell 2 must be cut to the frame, and one press "
                    + "must move cell 3 from the first to the second."
            )
            Text("第 1 格必須溢出，第 2 格必須被裁到 frame，而一次按壓必須讓第 3 格從前者變成後者。")

            Spacer()
        }
        .padding(16)
        .onAppear {
            P44Diagnostics.renderComplete()
        }
    }
}

/// One cell: an oversized orange child inside a smaller frame.
///
/// **One colour, and the check is the orange's measured size.** The first
/// version of this file drew a blue rectangle at the frame's size behind the
/// child, so that the frame's edges would stay visible; they never did. The
/// child covers the frame exactly when it is clipped and more than covers it
/// when it is not, so the blue was invisible in both cases -- a marker that
/// marks nothing, justified by a paragraph that had not been checked against
/// what it drew.
///
/// So the boundary is a number instead: clipped, the orange must measure
/// 120 x 60 points; unclipped, 200 x 100. Those are exact, and a screenshot
/// settles them at any density.
///
/// 一格：一個過大的橘色子元件，位於一個較小的 frame 之內。
///
/// **只有一個顏色，而檢查的是橘色被量到的尺寸。** 本檔的第一版在子元件後方以 frame 的尺寸畫了一個
/// 藍色矩形，好讓 frame 的邊界保持可見；它們從來沒有可見過。被裁切時，子元件恰好完全覆蓋該 frame；
/// 未被裁切時，覆蓋得更多——因此藍色在兩種情況下都是看不見的：一個什麼也沒標記的標記，而支持它的
/// 是一段從未對照它所畫出的東西檢查過的說明文字。
///
/// 因此邊界改為一個數字：被裁切時，橘色必須量得 120 x 60 點；未被裁切時，200 x 100。這些數值是
/// 精確的，而任何 density 下的截圖都能判定它們。
struct P44Cell: View {
    var label: String
    var clipped: Bool

    var body: some View {
        VStack(spacing: 6) {
            Text(label)

            P44Child()
                .frame(
                    width: P44Metrics.frameWidth,
                    height: P44Metrics.frameHeight
                )
                .conditionallyClipped(clipped)
        }
    }
}

/// The oversized child: orange, with a blue square in its top-left corner.
///
/// **The corner is what separates the two ways a cell can come out the frame's
/// size.** A uniformly orange child cannot: clipped to the centre of the frame
/// it measures 120 x 60, and resized to the frame it also measures 120 x 60,
/// and the picture is identical. That was this file's first design, and macOS
/// found the blind spot immediately -- all three cells measured 120 x 60 there,
/// which the app could report and not explain.
///
/// The marker is 40 x 40 at the top-left of a 200 x 100 child. The outer frame
/// centres its child, so clipping to 120 x 60 keeps the middle and throws away
/// 40 points from each side and 20 from the top and bottom -- the whole marker.
/// Resizing keeps it, smaller. So:
///
/// - orange only, 120 x 60  -> the child was CLIPPED
/// - blue corner present    -> the child was RESIZED, not clipped
///
/// The orange's outer measurements are unchanged by this, so the Android
/// numbers already recorded against this app still stand.
///
/// 過大的子元件：橘色，左上角有一個藍色方塊。
///
/// **那個角落，正是用來區分「一格為何量起來等於 frame 尺寸」的兩種可能的東西。** 一個純橘色的子
/// 元件做不到這件事：被裁切到 frame 中央時量得 120 x 60，被縮小到 frame 時也量得 120 x 60，而畫面
/// 完全相同。那是本檔的第一版設計，而 macOS 立刻找出了這個盲點——在那裡三格都量得 120 x 60，而這支
/// app 報得出來、卻解釋不了。
///
/// 該標記為 40 x 40，位於 200 x 100 子元件的左上角。外層 frame 會把子元件置中，因此裁切到 120 x 60
/// 會保留中間、丟掉左右各 40 點與上下各 20 點——也就是整個標記。縮小則會保留它，只是變小。所以：
///
/// - 只有橘色、120 x 60  -> 該子元件被**裁切**了
/// - 藍色角落仍在        -> 該子元件被**縮小**了，而非被裁切
///
/// 橘色的外圍量測不因此改變，因此已針對本 app 記錄的 Android 數字依然成立。
struct P44Child: View {
    private static let marker = 40

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.blue
                    .frame(width: Self.marker, height: Self.marker)
                Color.orange
                    .frame(
                        width: P44Metrics.childWidth - Self.marker,
                        height: Self.marker
                    )
            }
            Color.orange
                .frame(
                    width: P44Metrics.childWidth,
                    height: P44Metrics.childHeight - Self.marker
                )
        }
        .frame(width: P44Metrics.childWidth, height: P44Metrics.childHeight)
    }
}

extension View {
    /// `clipped()` under a condition, in one place.
    ///
    /// **The branch still swaps view types, and that matters when reading cell
    /// 3.** `@ViewBuilder` gives the two arms different types, so toggling
    /// rebuilds that cell rather than adding a clip to a cell that stays put --
    /// what a press proves there is "the clipped version draws cut", not
    /// "clipping was applied in place". Cells 1 and 2 are the ones that isolate
    /// clipping itself, because neither ever rebuilds and they differ in
    /// exactly this modifier.
    ///
    /// A helper rather than an `if` in the body only so the two arms are
    /// written once; it does not avoid the type change and is not trying to.
    ///
    /// 有條件的 `clipped()`，集中在一處。
    ///
    /// **這個分支仍然會改變 view 的型別，而那件事在讀第 3 格時很重要。** `@ViewBuilder` 使兩個分支
    /// 具有不同的型別，因此切換會使該格被重建，而不是在一個原地不動的格位上加上裁切——因此在那裡，
    /// 一次按壓所證明的是「被裁切的那個版本畫出來是被切的」，而不是「裁切被就地套用了」。真正把
    /// 裁切本身隔離出來的是第 1 與第 2 格，因為它們從不重建，而兩者恰好只差這一個 modifier。
    ///
    /// 寫成 helper 而非在 body 中使用 `if`，僅僅是為了讓兩個分支只寫一次；它並不避免型別改變，
    /// 也無意如此。
    @ViewBuilder
    func conditionallyClipped(_ clipped: Bool) -> some View {
        if clipped {
            self.clipped()
        } else {
            self
        }
    }
}
