import DefaultBackend
import Foundation
import SwiftCrossUI

// P55: does a real press flip `configuration.isPressed`?
//
// The number was checked, not guessed. `ls testapp` gives P50..P54, `git ls-files`
// has no P55, and nothing under matrix_coverage, mistakes or testapp/plan mentions
// the name. A free filename and a free NAME are different questions -- see P46's
// header for what happens when only the first is asked.
//
// **ButtonStyle, PrimitiveButtonStyle and BackendFeatures.ButtonPressState have
// been implemented on all five backends since 2026-09-08. Not one press has been
// shown to reach them.** P52 exercises the same machinery and deliberately does
// NOT press anything -- it is a benchmark, and its own header says driving
// presses from an action file would time the harness rather than the style. So
// `configuration.isPressed` has been read by nobody but the compiler.
//
// This app is the missing half. It is the smallest thing that can fail: one
// button, one custom style, and a count of the times that style has been asked
// to draw with `isPressed` true.
//
// **Why a count rather than a colour.** The obvious test is a style that turns
// the button orange while held, and a screenshot of it mid-press. That
// screenshot cannot be taken: an action file's click is press-and-release, the
// capture happens afterwards, and the button is back to its resting colour by
// then. A photograph of an unpressed button is exactly what a broken
// `isPressed` also produces. The counter survives the release, so
// `pressed draws: 0` and `pressed draws: 2` are different pictures.
//
// P55:一次真實的按壓會不會讓 `configuration.isPressed` 翻轉?
//
// 這個編號是查過的,不是猜的。`ls testapp` 給出 P50..P54,`git ls-files` 中沒有 P55,而
// matrix_coverage、mistakes 與 testapp/plan 底下都沒有提到這個名字。「檔名是空的」與「名稱是空的」
// 是兩個不同的問題——只問了第一個會發生什麼事,見 P46 的檔頭。
//
// **`ButtonStyle`、`PrimitiveButtonStyle` 與 `BackendFeatures.ButtonPressState` 自 2026-09-08 起就
// 在五個 backend 上都實作了。而沒有任何一次按壓被證明抵達過它們。** P52 演練的是同一套機制,而且
// **刻意不按任何東西**——它是效能基準,其檔頭明說「以動作檔驅動按壓,量到的會是測試工具而不是 style」。
// 因此 `configuration.isPressed` 除了編譯器之外沒有人讀過。
//
// 這支 app 就是缺掉的那一半。它是「能夠失敗」的最小形式:一顆按鈕、一個自訂 style,以及「該 style
// 被要求以 `isPressed` 為 true 繪製過幾次」的計數。
//
// **為何用計數而不是顏色。** 最直覺的測試是:一個「按住時變橘色」的 style,加上一張按壓中的截圖。
// 那張截圖拍不到:動作檔的點擊是「按下再放開」,擷取發生在那之後,而那時按鈕早已回到靜止的顏色。
// 一張「未被按下的按鈕」的照片,正是一個壞掉的 `isPressed` 同樣會產出的東西。計數會在放開之後
// 存活下來,因此 `pressed draws: 0` 與 `pressed draws: 2` 是兩張不同的圖。

enum P55Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P55] \(message)")
    }

    static func renderComplete() {
        guard !didAnnounceRender else { return }
        didAnnounceRender = true
        write("RENDER COMPLETE -- P55 ready for press checks")
    }
}

/// Counts the draws that saw `isPressed` true.
///
/// A global rather than app state, because a `ButtonStyle` is a value the
/// framework copies and `makeBody` is not a place to own state from. The count
/// is read back into the view through a `@State` that a timer-free redraw
/// picks up -- the button's own press already causes that redraw, which is the
/// point.
///
/// 記錄「看見 `isPressed` 為 true」的繪製次數。
///
/// 使用全域而非 app 狀態,因為 `ButtonStyle` 是一個會被框架複製的值,而 `makeBody` 不是一個適合
/// 持有狀態的地方。這個計數會透過一個 `@State` 被讀回 view 中,由一次不需計時器的重繪取得——而按鈕
/// 自身的按壓本來就會引發那次重繪,那正是重點。
enum P55PressLog {
    nonisolated(unsafe) static var pressedDraws = 0
    nonisolated(unsafe) static var totalDraws = 0
}

/// A style that records instead of only decorating.
///
/// It still colours the button, because a style that only counted would leave
/// nothing to look at on a platform where the counter turned out to be right
/// for the wrong reason. Both are here so they can disagree.
///
/// 一個「會記錄」而不只是「會裝飾」的 style。
///
/// 它仍然會替按鈕上色,因為一個只做計數的 style,在某個「計數碰巧正確、但理由是錯的」平台上,會讓人
/// 無從觀看。兩者並存,好讓它們有機會彼此矛盾。
struct P55RecordingButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let _ = record(configuration.isPressed)
        return configuration.label
            .padding(10)
            .background(configuration.isPressed ? Color.orange : Color.gray)
    }

    private func record(_ isPressed: Bool) {
        P55PressLog.totalDraws += 1
        if isPressed {
            P55PressLog.pressedDraws += 1
            P55Diagnostics.write("draw with isPressed=true, total \(P55PressLog.pressedDraws)")
        }
    }
}

@main
@HotReloadable
struct P55ButtonStyleApp: App {
    var body: some Scene {
        WindowGroup("P55 button style") {
            #hotReloadable {
                P55RootView()
            }
        }
        .defaultSize(width: 640, height: 460)
    }
}

struct P55RootView: View {
    @State var clicks = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("P55: ButtonStyle isPressed")
                .font(.system(size: 20))
            Text("backend -> \(String(describing: DefaultBackend.self))")

            // Read on every redraw, and the button's own press causes one. If
            // the backend never reports a press, `clicks` still rises -- the
            // action fires either way -- and `pressed draws` stays at 0, which
            // is precisely the failure this app exists to name.
            // 每一次重繪都會讀取,而按鈕自身的按壓就會引發一次重繪。若該 backend 從未回報按壓,
            // `clicks` 仍然會增加——那個 action 無論如何都會觸發——而 `pressed draws` 會停在 0,
            // 那正是這支 app 存在要指出的那個失敗。
            Text("clicks: \(clicks)")
            Text("pressed draws: \(P55PressLog.pressedDraws)   total draws: \(P55PressLog.totalDraws)")

            Button("Press me") {
                clicks += 1
                P55Diagnostics.write("click \(clicks)")
            }
            .buttonStyle(P55RecordingButtonStyle())

            Text(
                "Expected: pressing the button raises BOTH counters. clicks rising while "
                    + "pressed draws stays at 0 means the action is wired and the press state "
                    + "is not -- the button works and every custom ButtonStyle in the framework "
                    + "is decoration."
            )
            Text(
                "預期:按下該按鈕會讓**兩個**計數器都增加。若 clicks 增加而 pressed draws 停在 0,"
                    + "代表 action 接上了、而按壓狀態沒有——按鈕能用,但框架裡每一個自訂 ButtonStyle "
                    + "都只是裝飾。"
            )
            Text(
                "The colour is the same evidence in a form nobody can photograph: the button is "
                    + "orange only while held, and a capture taken after the release shows grey "
                    + "whether or not isPressed ever became true."
            )
            Text(
                "那個顏色是同一份證據,只是以「沒有人拍得到」的形式存在:按鈕只在被按住時是橘色,"
                    + "而放開之後所擷取的畫面,無論 isPressed 曾否為 true 都會是灰色。"
            )
        }
        .padding(16)
        .onAppear {
            P55Diagnostics.write("backend \(String(describing: DefaultBackend.self))")
            P55Diagnostics.renderComplete()
        }
    }
}
