import DefaultBackend
import Foundation
import SwiftCrossUI

#if canImport(UIKit)
    import UIKit
#endif

// P70: does `@FocusState` move the keyboard, and does it hear it move? (#122)
//
// The number is checked: `ls testapp` gives P50..P69, and nothing under
// testapp/plan or matrix_coverage mentions P70.
//
// **THE TWO HALVES FAIL SEPARATELY AND ONLY ONE IS EASY.** Writing `focused =
// true` and seeing a caret appear tests the half a plain `State` plus a method
// call could do. The other half is the focus moving for a reason the app did not
// cause -- Tab, a click on the other field, a screen reader -- and the property
// being written back. An implementation with only the first half looks perfect
// until the user touches anything, and then reports a focus that is not there.
//
// So this app shows BOTH fields' idea of the focus at once, and a counter of how
// many times the app was TOLD. A button-driven focus bumps the counter too, so a
// handler that never fires is visible as a counter stuck at zero while the
// caret is plainly in a field.
//
// **THE REFUSAL IS PART OF THE CONTRACT, NOT AN ERROR CASE.** `focus(_:)`
// returns `Bool` because Android in touch mode legitimately declines. The
// refusal row is a DISABLED button: disabled is the one reason every platform
// refuses for, so a `true` there is a focus that does not exist.
//
// It was a `Text` first, and on the way to this shape the Text row reported
// `yes`, which read as "AppKit lets a label hold the keyboard". It does not.
// What AppKit accepted was the `AppKitHitTestingContainer` every widget is
// wrapped in -- `makeFirstResponder` on that wrapper returned `true` while the
// text field underneath had never been asked. The Text row stayed anyway,
// reporting what each platform answers rather than asserting one, because
// "which object did the platform actually say yes to" is the question this
// whole protocol keeps turning on.
//
// P70:`@FocusState` 有沒有移動鍵盤,以及它有沒有「聽見」鍵盤被移動?(#122)
//
// 編號是查過的:`ls testapp` 給出 P50..P69,而 testapp/plan 與 matrix_coverage 底下都沒有提到 P70。
//
// **兩半會各自失敗,而只有其中一半是容易的。** 寫下 `focused = true` 然後看到游標出現,測到的是
// 「用一個普通的 `State` 加一次方法呼叫就做得到」的那一半。另一半是焦點因為 app 沒有造成的原因而移動
// ——Tab、點另一個欄位、螢幕閱讀器——並且該屬性被**寫回**。一個只有前一半的實作,在使用者碰任何東西
// 之前看起來都完美無缺;而在那之後,它回報的是一個並不存在的焦點。
//
// 因此這支 app 同時顯示兩個欄位各自對焦點的認知,以及一個「app 被**告知**過幾次」的計數器。由按鈕
// 驅動的取得焦點同樣會讓計數器加一,因此一個從不觸發的 handler,會以「游標明明在某個欄位裡、計數器卻
// 停在零」的樣子現形。
//
// **「被拒絕」是契約的一部分,不是錯誤情況。** `focus(_:)` 回傳 `Bool`,因為 Android 在 touch mode
// 下會正當地拒絕。拒絕那一列是一顆**被停用的按鈕**:「被停用」是每一個平台都會據以拒絕的那個理由,
// 因此那裡若出現 `true`,那就是一個並不存在的焦點。
//
// 它原本是一個 `Text`;而在走到現在這個形狀的途中,那一列曾回報 `yes`,讀起來像是「AppKit 允許一個
// 標籤持有鍵盤」。它並沒有。AppKit 接受的是「每個 widget 都被包上的那層 `AppKitHitTestingContainer`」
// ——對那層包裝呼叫 `makeFirstResponder` 回傳了 `true`,而底下那個文字欄位從頭到尾沒有被問過。那個
// Text 列仍然保留,改為回報每個平台各自的回答、而不是斷言其中一個;因為「平台究竟對**哪一個物件**
// 說了好」,正是整個協定一再繞回去的那個問題。

enum P70Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P70] \(message)")

        guard let data = "P70 \(Date()) \(message)\n".data(using: .utf8) else { return }
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
            .appendingPathComponent("p70-debug-events.log")
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
        write("RENDER COMPLETE -- P70 ready for focus checks")
    }
}

@main
@HotReloadable
struct P70App: App {
    var body: some Scene {
        WindowGroup("P70 focus state") {
            #hotReloadable {
                P70RootView()
            }
        }
        // 640, not 560. GTK's buttons and fields are taller than AppKit's, so at 560
        // the last two paragraphs ended in "..." on Windows and WSL while macOS
        // showed them whole (GTK three-way deck, 2026-10-23). The window is the
        // app's to size, as P6-v2 decided; the backend does not grow it.
        // 用 640 而非 560。GTK 的按鈕與欄位比 AppKit 高，所以在 560 時，最後兩段在 Windows 與 WSL 上被截成「...」,而 macOS
        // 完整顯示(GTK 三方簡報，2026-10-23)。視窗大小由 app 自己決定，與 P6-v2 的做法相同；backend 不會替它放大。
        .defaultSize(width: 560, height: 640)
    }
}

/// Which field the keyboard is in, or `nil`.
///
/// An enum rather than one `Bool` per field: two independent `Bool`s can both be
/// `true`, which is a state the keyboard cannot be in, and a test app that can
/// represent an impossible state will eventually show one.
/// 鍵盤在哪一個欄位裡;都不在時為 `nil`。
///
/// 使用 enum 而非「每個欄位一個 `Bool`」:兩個獨立的 `Bool` 可以同時為 `true`,而那是鍵盤不可能處於
/// 的狀態;一支「表示得出不可能狀態」的測試 app,遲早會顯示出一個。
enum P70Field: Hashable {
    case name
    case email
}

/// Moves the focus on a timer when `SCUI_P70_AUTOFOCUS` is set.
///
/// **For iOS, which has no input synthesiser.** `testapp/actions/ios/` is empty
/// and planned; on macOS and Android the equivalent evidence comes from real
/// clicks and taps, which is better and is what those two use. Driving from
/// inside tests less -- the moves here ARE app-caused -- but it is not nothing:
/// the counter only rises if the platform's notification came back, so a
/// handler that never fires still shows as a caret with a zero beside it.
///
/// Said plainly rather than left implied: on iOS the user-caused half is not
/// covered here. It needs a tap the harness cannot yet produce.
///
/// 當 `SCUI_P70_AUTOFOCUS` 被設定時,以計時器移動焦點。
///
/// **這是為 iOS 準備的,因為它沒有輸入合成器。** `testapp/actions/ios/` 是空的、仍在計畫中;在 macOS
/// 與 Android 上,對應的證據來自真實的點擊與觸控,那更好,而那兩者用的也正是它。從內部驅動測到的
/// 較少——這裡的移動**是** app 造成的——但它不是什麼都沒測到:那個計數器只有在「平台的通知確實回來了」
/// 時才會上升,因此一個從不觸發的 handler,仍會以「游標旁邊擺著一個零」的樣子現形。
///
/// 明說而不是留給人推論:在 iOS 上,「使用者造成的」那一半在此處**沒有**被涵蓋。它需要一次這個測試
/// 架構目前還產不出來的觸控。
func p70AutoFocusEnabled() -> Bool {
    ProcessInfo.processInfo.environment["SCUI_P70_AUTOFOCUS"] != nil
}

/// The field `-start email` (or `-start name`) asks for before the window is shown.
///
/// **The request a window opens with is the one most easily lost.** `focus(_:)`
/// returns `false` for a widget that is not in a window yet, and a modifier that
/// takes that as a refusal writes `nil` back before anyone has seen the window --
/// `@FocusState var field = .email` would open with the caret nowhere and the
/// property saying so. `email` rather than `name` on purpose: AppKit gives a new
/// window's first key view the focus by itself, so a request for the FIRST field
/// would pass whether or not it was honoured. `P70-focus-start.actions` launches
/// with it and expects `focused field: email` and `focus changes heard: 0`.
///
/// `-start email`(或 `-start name`)要求在視窗顯示之前取得焦點的欄位。
///
/// **視窗開啟時帶著的那個要求，是最容易遺失的。** 對還不在視窗裡的 widget,`focus(_:)` 回傳 `false`;
/// 把它當成拒絕的 modifier,會在任何人看到視窗之前就把 `nil` 寫回去——`@FocusState var field = .email`
/// 會以「游標不在任何地方、屬性也這麼說」的樣子開啟。刻意用 `email` 而不是 `name`:AppKit 會自己把焦點給新視窗的
/// 第一個 key view,所以對**第一個**欄位的要求不論有沒有被履行都會通過。`P70-focus-start.actions` 以它啟動，
/// 預期 `focused field: email` 與 `focus changes heard: 0`。
func p70StartField() -> P70Field? {
    guard let index = CommandLine.arguments.firstIndex(of: "-start"),
        index + 1 < CommandLine.arguments.count
    else { return nil }
    switch CommandLine.arguments[index + 1] {
    case "name": return .name
    case "email": return .email
    default: return nil
    }
}

struct P70RootView: View {
    @State var name = ""
    @State var email = ""
    @State var changes = 0
    @State var refusal = "not asked"

    @FocusState var field: P70Field? = p70StartField()

    /// A second, independent focus binding, on a view that cannot take focus.
    ///
    /// Separate from `field` on purpose: if the refusal wrote into the same
    /// property it would be indistinguishable from the user clicking away, and
    /// the point of the row is that a refusal is reported AS a refusal.
    /// 第二個獨立的 focus binding,掛在一個無法取得焦點的 view 上。
    ///
    /// 刻意與 `field` 分開:若那次拒絕寫進同一個屬性,它將與「使用者點開」無從分辨;而這一列的重點
    /// 正是:一次拒絕要**以拒絕的身分**被回報。
    @FocusState var textFocused = false
    @FocusState var disabledFocused = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("P70: focus state (#122)")
                .font(.system(size: 18))
            Text("backend -> \(String(describing: DefaultBackend.self))")

            // The app's idea of where the focus is. It is only worth anything
            // because the handler writes it -- see `changes`.
            // app 對「焦點在哪裡」的認知。它之所以有價值,完全是因為 handler 會寫入它——見 `changes`。
            Text("focused field: \(field.map(String.init(describing:)) ?? "none")")
            // How many times the app was TOLD the focus moved. Zero while a
            // caret is visible means the reporting half is missing, which is the
            // failure that otherwise looks like success.
            // app 被**告知**焦點移動過幾次。游標明明看得見而這裡是零,代表回報的那一半不存在
            // ——而那正是那種「否則看起來像成功」的失敗。
            Text("focus changes heard: \(changes)")
            Text("refusal check: \(refusal)")

            TextField("name", text: $name)
                .focused($field, equals: .name)
            TextField("email", text: $email)
                .focused($field, equals: .email)

            HStack(spacing: 8) {
                Button("focus name") { field = .name }
                Button("focus email") { field = .email }
                Button("clear focus") { field = nil }
            }

            // A disabled button. Every platform refuses focus to a disabled
            // control, which makes this the one row whose expected answer is the
            // same everywhere.
            // 一顆被停用的按鈕。每一個平台都會拒絕把焦點給一個被停用的控制項,而這讓這一列成為
            // 「預期答案在每個地方都相同」的那一列。
            Button("disabled -- must refuse focus") {}
                .disabled(true)
                .focused($disabledFocused)
            // Informational, not a claim. AppKit says yes here; the row records
            // what each platform answers.
            // 這是資訊,不是主張。AppKit 在此說「可以」;這一列記錄的是每個平台各自的回答。
            Text("a plain Text -- what does this platform say?")
                .focused($textFocused)
            Button("ask both for focus") {
                disabledFocused = true
                textFocused = true
                // Read back on the next turn: the modifier reconciles during the
                // layout pass that this state change triggers, so reading here
                // would read the value just written rather than the platform's
                // answer to it.
                // 下一輪再讀回來:這個 modifier 是在「這次狀態改變所觸發的那一次版面計算」中做調和的,
                // 因此在此處讀取,讀到的是剛剛寫下去的值,而不是平台對它的回答。
                refusal = "asked -- see next line after a redraw"
                reportAfterAsking()
            }
            Text("disabled button reports focused: \(disabledFocused ? "YES (wrong)" : "no (correct)")")
            Text("plain Text reports focused: \(textFocused ? "yes" : "no") (platform's answer)")

            Text(
                "Expected: clicking or tabbing between the two fields changes 'focused field' "
                    + "AND increases 'focus changes heard'. A counter stuck at 0 with a visible "
                    + "caret means the handler never fires."
            )
            Text(
                "預期:在兩個欄位之間點擊或按 Tab,會改變「focused field」**並且**讓「focus changes "
                    + "heard」增加。計數器停在 0 而游標看得見,代表那個 handler 從未觸發。"
            )
        }
        .padding(20)
        .onAppear {
            P70Diagnostics.write("backend \(String(describing: DefaultBackend.self))")
            P70Diagnostics.renderComplete()
            driveFocusIfAsked()
            reportStartIfAsked()
        }
        .onChange(of: field) {
            changes += 1
            P70Diagnostics.write(
                "FOCUS now \(field.map(String.init(describing:)) ?? "none") changes=\(changes)"
            )
        }
        .onChange(of: textFocused) {
            P70Diagnostics.write("TEXT FOCUS reported \(textFocused)")
        }
        .onChange(of: disabledFocused) {
            P70Diagnostics.write("DISABLED FOCUS reported \(disabledFocused)")
            refusal =
                disabledFocused
                ? "NOT refused -- a disabled control took focus (wrong)"
                : "refused (correct)"
        }
    }

    /// Three moves on a timer, each far enough apart to be legible in the log.
    /// 三次以計時器分隔的移動,間隔拉得夠開,好讓紀錄看得清楚。
    func driveFocusIfAsked() {
        guard p70AutoFocusEnabled() else { return }
        let steps: [(Double, () -> Void)] = [
            (1.5, { field = .name }),
            (3.0, { field = .email }),
            (4.5, { disabledFocused = true }),
        ]
        for (delay, step) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MainActor.assumeIsolated(step)
            }
        }
    }

    /// The verdicts the action files' `# expect: log-contains` lines look for, on
    /// stdout and in p70-debug-events.log whatever `--debug` says. Without them a
    /// sweep only knew that a replay ran and a capture was taken: a click that
    /// missed every field (Android's stale coordinates, 2026-11-24) and a start
    /// request that WinUI lost both "passed".
    /// action file 的 `# expect: log-contains` 行所找的判定，不論有沒有 `--debug`,都寫到 stdout 與
    /// p70-debug-events.log。沒有它們時，sweep 只知道重放跑完、擷圖拍到：每一下都沒點中欄位(Android 過時的座標,
    /// 2026-11-24)與 WinUI 弄丟的啟動要求，兩者都「通過」。
    func report(_ line: String) {
        print(line)
        P70Diagnostics.write(line)
    }

    /// `-start X`: one second after the window appears, the field asked for holds
    /// the focus and no change has been heard -- a refusal written back would be one.
    /// `-start X`:視窗出現一秒後，所要求的欄位持有焦點，且沒有聽到任何變化——寫回的拒絕就會是一次變化。
    func reportStartIfAsked() {
        guard let start = p70StartField() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            MainActor.assumeIsolated {
                let now = field.map(String.init(describing:)) ?? "none"
                report(
                    field == start && changes == 0
                        ? "P70 START PASS (focused \(now), 0 changes)"
                        : "P70 START FAIL (focused \(now), \(changes) changes; asked for \(start))"
                )
            }
        }
    }

    /// After "ask both for focus": at least two focus changes heard (the clicks on
    /// the two fields landed and were reported) and the disabled button refused.
    /// A tap that misses this button leaves no line at all, which fails too.
    /// 按下「ask both for focus」之後：至少聽到兩次焦點變化(點兩個欄位都點中且有回報),
    /// 且停用的按鈕拒絕了。沒點中這顆按鈕就一行都不會有，同樣算失敗。
    func reportAfterAsking() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            MainActor.assumeIsolated {
                let now = field.map(String.init(describing:)) ?? "none"
                let disabled = disabledFocused ? "disabled focused" : "disabled refused"
                report(
                    changes >= 2 && !disabledFocused
                        ? "P70 CHECK PASS (focused \(now), \(changes) changes, \(disabled))"
                        : "P70 CHECK FAIL (focused \(now), \(changes) changes, \(disabled))"
                )
            }
        }
    }
}
