import DefaultBackend
import Foundation
import SwiftCrossUI

#if canImport(UIKit)
    import UIKit
#endif

#if canImport(WinUI)
    import WinUI
    import WinUIBackend

    /// Reads the four accessibility properties back off the live WinUI tree.
    ///
    /// **In-process, and that limit is the same one the UIKit path states.** It
    /// reads the properties this backend SET, not what a screen reader would
    /// resolve -- `AutomationProperties.getName` returns what was attached, and
    /// a real client walks the UI Automation tree from outside the process. So a
    /// pass here says "the backend attached what the modifier asked for", which
    /// is the half #123 owns, and says nothing about Narrator.
    ///
    /// The tree is reached through an embedded element rather than a global: a
    /// `WinUIElementRepresentable` puts a real `Canvas` in the view tree, and
    /// `VisualTreeHelper` walks up from it to the root and back down. That is
    /// the same door P6 uses to reach a native element.
    ///
    /// 從活的 WinUI 樹上把那四個無障礙屬性讀回來。
    ///
    /// **在行程內讀,而這個限制與 UIKit 那條路所聲明的是同一個。** 它讀的是這個 backend **所設定**的
    /// 屬性,而不是螢幕閱讀器最終會解析出來的東西——`AutomationProperties.getName` 回傳的是被掛上去的
    /// 那個值,而真正的用戶端是從行程外走 UI Automation 樹。因此此處的通過,說的是「backend 掛上了
    /// 那個 modifier 所要求的東西」——那是 #123 該負責的那一半——而它對朗讀程式一句話都沒說。
    ///
    /// 取得那棵樹的方式是透過一個嵌入的元素、而非某個全域物件:`WinUIElementRepresentable` 會在 view
    /// 樹中放進一個真正的 `Canvas`,再由 `VisualTreeHelper` 從它往上走到 root、然後往下走。
    /// 那與 P6 用來取得原生元素的是同一扇門。
    struct P69WinUIProbe: WinUIElementRepresentable {
        typealias WinUIElementType = WinUI.Canvas

        func makeWinUIElement(context: Context) -> WinUI.Canvas {
            let canvas = WinUI.Canvas()
            // Deferred, for the reason the UIKit path gives: the controls exist
            // by now but their properties are attached during this same layout
            // pass, and reading mid-pass reports a half-built tree.
            // 延後執行,理由與 UIKit 那條路所述相同:那些控制項此刻已經存在,但它們的屬性是在**這同一次**
            // 版面計算中被掛上的,而在中途讀取,得到的是一棵建到一半的樹。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                MainActor.assumeIsolated { P69WinUIProbe.readBack(from: canvas) }
            }
            return canvas
        }

        func updateWinUIElement(_ element: WinUI.Canvas, context: Context) {}

        @MainActor
        static func readBack(from element: WinUI.FrameworkElement) {
            var root: WinUI.DependencyObject = element
            while let parent = VisualTreeHelper.getParent(root) {
                root = parent
            }
            var collected: [String] = []
            walk(root, into: &collected)
            for line in collected { P69Diagnostics.write(line) }
            P69Diagnostics.write("ACCESSIBILITY READ")
        }

        /// Only elements that carry at least one of the four are reported.
        ///
        /// A WinUI tree is mostly plumbing -- borders, presenters, panels -- and
        /// printing every node would bury the four lines this app exists to
        /// show. An element with nothing set is not evidence of anything.
        ///
        /// 只回報**至少帶有四者之一**的元素。
        ///
        /// 一棵 WinUI 樹大部分是管路——border、presenter、panel——而把每個節點都印出來,會把這支 app
        /// 存在的理由(那四行)給埋掉。一個什麼都沒設定的元素,不構成任何證據。
        @MainActor
        static func walk(_ node: WinUI.DependencyObject, into collected: inout [String]) {
            let name = AutomationProperties.getName(node)
            let hint = AutomationProperties.getHelpText(node)
            let value = AutomationProperties.getItemStatus(node)
            let view = AutomationProperties.getAccessibilityView(node)
            if !name.isEmpty || !hint.isEmpty || !value.isEmpty || view == .raw {
                collected.append(
                    "AX \(type(of: node)) label=\(name.isEmpty ? "-" : name)"
                        + " hint=\(hint.isEmpty ? "-" : hint)"
                        + " value=\(value.isEmpty ? "-" : value)"
                        + " hidden=\(view == .raw)"
                )
            }
            let count = VisualTreeHelper.getChildrenCount(node)
            for index in 0..<count {
                guard let child = VisualTreeHelper.getChild(node, index) else { continue }
                walk(child, into: &collected)
            }
        }
    }
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
            // Zero-sized, and present only so the WinUI readback has a real
            // element to walk the tree from. It reads; it does not render.
            // 尺寸為零,存在的唯一目的是讓 WinUI 的讀回有一個真正的元素可據以走訪那棵樹。
            // 它只負責讀取,不負責算繪。
            #if canImport(WinUI)
                P69WinUIProbe()
                    .frame(width: 0, height: 0)
            #endif
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

            // The same override on plain text rather than a control. Only iOS
            // had been asked this; on a backend whose Text widget is a wrapper
            // the label can land on the wrapper and the reader still says
            // "12:30". Absence of "12:30" is the half that proves it.
            // 同一個覆寫,改加在純文字而非控制項上。此前只在 iOS 上問過;在 Text 的 widget 是外包層的
            // backend 上,標籤可能落在外包層,而閱讀器仍唸 "12:30"。"12:30" 不出現,才是證明的那一半。
            Text("12:30")
                .accessibilityLabel("Half past twelve")

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
                    + "'Half past twelve' appears and '12:30' does not; "
                    + "'decorative' appears nowhere. This text is the claim, not the evidence."
            )
            Text(
                "外部探針的預期:出現 'Close' 而不出現 'X';'Delete' 帶有那個提示;'Volume' 的值是 "
                    + "'40 percent';'Half past twelve' 出現而 '12:30' 不出現;'decorative' 完全不出現。"
                    + "這段文字是**主張**,不是證據。"
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
        #elseif canImport(WinUI)
            // The WinUI readback runs from `P69WinUIProbe`, which is embedded in
            // the view body so it has a real element to walk the tree from.
            // Nothing to do here, and saying so beats an empty branch that reads
            // like an oversight.
            // WinUI 的讀回由 `P69WinUIProbe` 執行,它被嵌入在 view body 中,好讓它有一個真正的元素
            // 可以據以走訪那棵樹。此處無事可做——而把這件事寫出來,勝過留下一個「看起來像疏漏」的空分支。
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
