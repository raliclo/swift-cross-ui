import DefaultBackend
import Foundation
import SwiftCrossUI

// P38 web view: does a page actually render, and does navigation report back?
//
// Split out of P27 on 2026-08-27. P27 asks only whether laying a `WebView` out
// aborts the process -- a question its window answers whether or not a page
// appears. This app asks the next question, and it needs its own window because
// the failure mode is an empty rectangle, which is indistinguishable from "no
// web view here" unless something around it says what should have been drawn.
//
// What is known going in, measured on Windows/WinUIBackend at 25 s with the
// Edge WebView2 runtime 151.0.4129.107 installed and the frame pointed at
// google.com: the frame stayed empty while four `msedgewebview2.exe` processes
// were running. So the control initialises and the browser host starts; what is
// missing is paint, not the runtime. That is why this app draws a border and a
// caption around the frame -- without them a blank area cannot be told apart
// from a frame that was never laid out.
//
// GtkBackend has no WebKitGTK and substitutes a labelled placeholder, so on
// Linux and on Windows `-gtk4` the expected result is that text, not a page.
// Whether to take on `webkitgtk-6.0` as a system dependency is an open
// decision, not a defect.
//
//     zsh testapp/run.zsh P38                       example.com, the default
//     zsh testapp/run.zsh P38 -url https://www.google.com
//     zsh testapp/run.zsh P38 --debug               report each navigation
//
// P38 網頁檢視：頁面真的有被繪製嗎？導覽會不會回報？
//
// 於 2026-08-27 自 P27 分出。P27 只問「把 `WebView` 排版出來會不會使行程中止」——無論頁面是否
// 出現，它的視窗都能回答那個問題。本 app 問的是下一個問題，而它需要自己的視窗，因為其失敗樣態是
// 一個空白矩形；若周圍沒有任何東西說明「本來應該畫出什麼」，空白矩形與「這裡根本沒有 web view」
// 是無法區分的。
//
// 開始之前的已知事實，於 Windows/WinUIBackend 上等待 25 秒實測（Edge WebView2 runtime
// 151.0.4129.107 已安裝，框內指向 google.com）：該框保持空白，同時有四個 `msedgewebview2.exe`
// 行程正在執行。因此控制項完成了初始化、瀏覽器主機也已啟動；缺少的是繪製，而非 runtime。這正是
// 本 app 要在框的周圍畫上邊框與說明文字的理由——少了它們，空白區域無法與「從未被排版的框」區分。
//
// GtkBackend 沒有 WebKitGTK，改以帶文字的佔位取代，因此在 Linux 與 Windows `-gtk4` 上，預期看到
// 的是那段文字而非網頁。是否要引入 `webkitgtk-6.0` 作為系統相依，是一個尚未拍板的決定，而非缺陷。
//
// Build this file as a standalone app target.

/// The page the web view opens, `-url <URL>` or `https://example.com`.
///
/// A flag rather than a constant because "does the control paint at all" and
/// "does it render a real site" are different questions, and only the second
/// needs a page with scripts, images and a redirect on it. `example.com` stays
/// the default: it is a fixed, tiny document, so a blank frame there means the
/// control failed rather than the network being slow.
///
/// 網頁檢視所開啟的頁面，來自 `-url <URL>`，預設為 `https://example.com`。
///
/// 之所以做成旗標而非常數：「控制項究竟有沒有繪製」與「它能不能呈現一個真實網站」是兩個不同的
/// 問題，而只有後者需要一個帶有 script、圖片與轉址的頁面。預設仍為 `example.com`——它是一份固定
/// 且極小的文件，因此該處若是空白，代表控制項失敗，而非網路太慢。
enum P38WebPage {
    static let url: URL = {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "-url"),
            arguments.index(after: flag) < arguments.endIndex,
            let parsed = URL(string: arguments[arguments.index(after: flag)])
        else {
            return URL(string: "https://example.com")!
        }
        return parsed
    }()
}

enum P38Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")

    static func report(_ message: String) {
        guard isEnabled else { return }
        print("[P38] \(message)")
    }
}

@main
@HotReloadable
struct P38WebViewApp: App {
    var body: some Scene {
        WindowGroup("P38 web view") {
            #hotReloadable {
                P38RootView()
            }
        }
        .defaultSize(width: 820, height: 660)
    }
}

struct P38RootView: View {
    // WebView takes a Binding, not a URL -- it reports navigations back through
    // it, which is the second half of what this app tests.
    // WebView 接受的是 Binding 而非 URL——它會透過該綁定回報導覽，而那正是本 app 所測試的後半部。
    @State var url = P38WebPage.url

    // Every URL this view has been told about, newest last. A count rather than
    // a flag: one navigation is the one we asked for, and any further ones are
    // redirects the page itself performed, which is the interesting case and is
    // invisible if only the latest is shown.
    // 本 view 被告知過的每一個 URL，最新者在後。此處記錄的是次數而非旗標：第一次導覽是我們要求的
    // 那一次，其後的任何一次都是頁面自身執行的轉址——那才是有意思的情形，而若只顯示最新的一筆，
    // 它就看不見了。
    @State var visited: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("P38: web view")
                .font(.system(size: 20))

            Text("backend -> \(String(describing: DefaultBackend.self))")

            Text("Requested: \(P38WebPage.url.absoluteString)")

            // The navigation report. `WebView` writes back through its binding,
            // so this line moving is the proof that the binding is wired even
            // when nothing is painted -- the two failures look identical in a
            // screenshot otherwise.
            // 導覽回報。`WebView` 會透過其綁定回寫，因此這一行有變動，即證明綁定確實接通——即使
            // 什麼都沒有被畫出來也是如此；否則這兩種失敗在截圖上看起來一模一樣。
            Text("Navigations reported: \(visited.count)")

            Text(visited.isEmpty ? "  (none yet)" : "  " + visited.joined(separator: "\n  "))

            Text("The framed area below should be the page, not empty space.")

            // The frame is the instrument, not decoration. A `WebView` that
            // renders nothing and a `WebView` that was never given a size both
            // show blank; only something drawn around it separates them,
            // because that is drawn by SwiftCrossUI at the size the layout
            // system chose.
            //
            // Built from `padding` over a `background` rather than `.border`,
            // which SwiftCrossUI does not have -- 0 declarations, checked
            // 2026-08-27 with `grep -rn 'func border' Sources/SwiftCrossUI/`.
            // The two points of padding are the visible edge.
            //
            // 這個外框是量測工具而非裝飾。「什麼都沒繪製的 WebView」與「從未被賦予尺寸的
            // WebView」都呈現空白；能區分兩者的只有畫在它周圍的東西，因為那是由 SwiftCrossUI 以
            // 版面系統所選定的尺寸繪製出來的。
            //
            // 此處以 `padding` 疊加 `background` 組成，而非使用 `.border`——SwiftCrossUI 並沒有這個
            // 修飾符（0 個宣告，於 2026-08-27 以
            // `grep -rn 'func border' Sources/SwiftCrossUI/` 查證）。那兩點的 padding 即是可見的邊。
            WebView($url)
                .frame(width: 760, height: 420)
                .padding(2)
                .background(Color.gray)
                .onChange(of: url) {
                    visited.append(url.absoluteString)
                    P38Diagnostics.report("navigated to \(url.absoluteString)")
                }
        }
        .padding(18)
    }
}
