import DefaultBackend
import Foundation
import SwiftCrossUI

#if canImport(UIKit)
    import UIKit
#endif

// P69: do the four `.accessibility*` modifiers reach the screen reader? (#123)
//
// The number is checked: `ls testapp` gives P50..P68, and nothing under
// testapp/plan or matrix_coverage mentions P69.
//
// **SEPARATE FROM P67, AND THE SPLIT IS THE POINT.** P67 asks what a screen
// reader hears when nobody has said anything -- the name a button DERIVES from
// its own text. This one asks what happens when the author overrides that. The
// two fail differently and would mask each other in one app: P67's derivation
// producing the right name is exactly what makes a broken override invisible,
// because the button still announces something plausible.
//
// **EVERY CASE IS ONE WHERE THE PLATFORM'S OWN ANSWER IS WRONG, NOT MERELY
// ABSENT.** A modifier tested on a view whose default already matches would
// pass whether or not it ran. So the button here shows "X" and must be heard as
// "Close"; the hidden group's child carries text that must not be announced.
// Both readings are impossible to get by accident.
//
// **WHAT READS THE RESULT IS NOT THIS APP, ON macOS.** The on-screen text below
// is a description of what should be true, not evidence that it is -- an
// accessibility property is invisible in a screenshot, which is the whole
// difficulty. The evidence comes from outside:
//
//   macOS    swift testapp/test_support/measure/ax_dump.swift testapp/output/P69
//   Android  adb shell uiautomator dump  (content-desc and hint attributes)
//   iOS      the in-process walk below, because iOS offers no outside vantage
//
// P69:那四個 `.accessibility*` modifier 有沒有真的抵達螢幕閱讀器?(#123)
//
// 編號是查過的:`ls testapp` 給出 P50..P68,而 testapp/plan 與 matrix_coverage 底下都沒有提到 P69。
//
// **與 P67 分開,而這個切分正是重點。** P67 問的是「沒有人說任何話時,螢幕閱讀器聽到什麼」——也就是
// 一顆按鈕從它自己的文字**推導**出的名字。這一支問的是「作者覆寫它之後會怎樣」。兩者的失敗方式不同,
// 放在同一支 app 裡會互相遮蔽:正因為 P67 的推導給出了正確的名字,一個壞掉的覆寫才會是隱形的——
// 那顆按鈕仍然宣讀出某個看起來合理的東西。
//
// **每一個案例都是「平台自己的答案是錯的」,而不只是「缺席」。** 一個在「預設值本來就相符」的 view
// 上受測的 modifier,無論有沒有執行都會通過。因此這裡的按鈕顯示 "X" 而必須被聽成 "Close";被隱藏
// 那一組的子元件帶著「不得被宣讀」的文字。這兩個讀數都不可能碰巧出現。
//
// **在 macOS 上,讀出結果的不是這支 app。** 下方畫面上的文字是「應該為真的事」的描述,不是「它為真」
// 的證據——一個無障礙屬性在截圖裡是看不見的,而那正是這件事的全部難處。證據來自外部:
//
//   macOS    swift testapp/test_support/measure/ax_dump.swift testapp/output/P69
//   Android  adb shell uiautomator dump(content-desc 與 hint 屬性)
//   iOS      下方的行程內走訪,因為 iOS 不提供外部的觀察點

enum P69Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P69] \(message)")

        guard let data = "P69 \(Date()) \(message)\n".data(using: .utf8) else { return }
        let directory =
            ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
            ?? {
                #if os(iOS) || os(tvOS)
                    return NSHomeDirectory() + "/Documents"
                #else
                    return FileManager.default.currentDirectoryPath
                #endif
            }()
        let url = URL(fileURLWithPath: directory)
            .appendingPathComponent("p69-debug-events.log")
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
        write("RENDER COMPLETE -- P69 ready for accessibility checks")
    }
}

/// Carries the in-process reading back to the screen, on the platform that has
/// one.
///
/// A shared instance rather than a per-view value: `@ObservedObject var x = X()`
/// rebuilds the object on every update, which is the defect P64 was fixed for.
/// 把行程內讀到的結果帶回畫面上——在有這種讀法的那個平台上。
///
/// 使用共用實例而非逐 view 的值:`@ObservedObject var x = X()` 會在每次更新時重建該物件,那正是
/// P64 修掉的缺陷。
final class P69Readings: SwiftCrossUI.ObservableObject {
    @MainActor static let shared = P69Readings()
    @SwiftCrossUI.Published var summary = "not read yet"
}

@main
@HotReloadable
struct P69App: App {
    var body: some Scene {
        WindowGroup("P69 accessibility modifiers") {
            #hotReloadable {
                P69RootView()
            }
        }
        .defaultSize(width: 560, height: 620)
    }
}

struct P69RootView: View {
    @State var presses = 0
    @ObservedObject var readings = P69Readings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("P69: accessibility modifiers (#123)")
                .font(.system(size: 18))
            Text("backend -> \(String(describing: DefaultBackend.self))")
            Text("presses: \(presses)")
            Text(readings.summary)

            // Visible "X", spoken "Close". The default here is the character
            // itself, which a screen reader reads as the letter x -- so this
            // reading cannot be arrived at by the modifier not running.
            // 看到的是 "X",唸出來的是 "Close"。此處的預設值是那個字元本身,而螢幕閱讀器會把它讀成
            // 字母 x——因此這個讀數不可能是「modifier 沒有執行」所能得到的。
            Button("X") { presses += 1 }
                .accessibilityLabel("Close")

            // A name the platform already gets right, plus a hint it has no way
            // to know: what pressing it will do. Label and hint are read at
            // different times and a screen reader may skip hints entirely,
            // which is why they are not one string.
            // 一個平台本來就給對的名字,加上一個它無從得知的提示:按下去會發生什麼事。標籤與提示
            // 被讀出的時機不同,而螢幕閱讀器可能完全跳過提示——這正是它們不是同一個字串的原因。
            Button("Delete") { presses += 1 }
                .accessibilityHint("Removes the file permanently")

            // Label and value are different strings for the same control. A
            // single `accessibilityLabel` cannot express this: "Volume" names
            // it and "40 percent" is what it currently says.
            // 對同一個控制項來說,標籤與值是兩個不同的字串。單一個 `accessibilityLabel` 表達不了
            // 這件事:"Volume" 是它的名字,而 "40 percent" 是它此刻所說的內容。
            Button("Volume") { presses += 1 }
                .accessibilityValue("40 percent")

            // Decorative, and its CHILD is what proves the point: hiding only
            // the container would leave "decorative" behind to be announced,
            // which is the failure that looks like success.
            // 裝飾性的;而**它的子元件**才是關鍵:只藏容器,會把 "decorative" 留在原地被宣讀——
            // 那正是那種「看起來像成功」的失敗。
            HStack(spacing: 4) {
                Text("decorative")
            }
            .accessibilityHidden()

            Text(
                "Expected from the OUTSIDE probe: 'Close' appears and 'X' does not; "
                    + "'Delete' carries the hint; 'Volume' has value '40 percent'; "
                    + "'decorative' appears nowhere. This text is the claim, not the evidence."
            )
            Text(
                "外部探針的預期:出現 'Close' 而不出現 'X';'Delete' 帶有那個提示;'Volume' 的值是 "
                    + "'40 percent';'decorative' 完全不出現。這段文字是**主張**,不是證據。"
            )
        }
        .padding(20)
        .onAppear {
            P69Diagnostics.write("backend \(String(describing: DefaultBackend.self))")
            readBack()
            P69Diagnostics.renderComplete()
        }
    }

    /// Asks the PLATFORM what it would announce, on the platform where the app
    /// is the only thing that can ask.
    ///
    /// iOS has no counterpart to macOS's `AXUIElementCreateApplication`, which
    /// attaches from another process and reads the real tree. In-process is
    /// second best -- it reads the view hierarchy that FEEDS the tree rather
    /// than the tree -- and saying so is the point of this comment.
    ///
    /// 在「只有這支 app 自己問得到」的平台上,去問**平台**它會宣讀什麼。
    ///
    /// iOS 沒有 macOS `AXUIElementCreateApplication` 的對應物——後者從另一個行程附著、讀取真正的
    /// 那棵樹。行程內是次佳的做法:它讀的是**餵養**那棵樹的 view 階層,而不是那棵樹——而把這件事
    /// 說出來,正是這段註解的用意。
    func readBack() {
        #if canImport(UIKit)
            // Deferred one runloop turn: the controls exist by `onAppear`, but
            // their properties are attached during the same layout pass, and
            // reading in the middle of it reports the tree half-built.
            // 延後一個 runloop:那些控制項在 `onAppear` 時已經存在,但它們的屬性是在同一次版面計算中
            // 被掛上的,而在那中途讀取,得到的是一棵建到一半的樹。
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    var collected: [String] = []
                    for window in UIApplication.shared.connectedScenes
                        .compactMap({ $0 as? UIWindowScene })
                        .flatMap(\.windows)
                    {
                        walk(window, collected: &collected)
                    }
                    for line in collected { P69Diagnostics.write(line) }
                    P69Diagnostics.write("ACCESSIBILITY READ")
                    P69Readings.shared.summary = collected.joined(separator: " | ")
                }
            }
        #else
            P69Diagnostics.write(
                "macOS: run testapp/test_support/measure/ax_dump.swift against this app"
            )
            P69Diagnostics.write("ACCESSIBILITY READ")
        #endif
    }

    #if canImport(UIKit)
        func walk(_ view: UIView, collected: inout [String]) {
            // A hidden subtree must not be walked into. Reporting the boundary
            // rather than silently stopping is what makes the absence below it
            // evidence instead of an empty result.
            // 被隱藏的子樹不得被走訪。回報這個邊界、而不是靜默地停下來,才讓「它底下什麼都沒有」
            // 成為證據,而不是一個空結果。
            if view.accessibilityElementsHidden {
                collected.append("HIDDEN")
                return
            }
            if let control = view as? UIControl {
                collected.append(
                    "'\(control.accessibilityLabel ?? "")'"
                        + "/h'\(control.accessibilityHint ?? "")'"
                        + "/v'\(control.accessibilityValue ?? "")'"
                )
            }
            for subview in view.subviews {
                walk(subview, collected: &collected)
            }
        }
    #endif
}
