import DefaultBackend
import Foundation
import SwiftCrossUI

// P27 backend feature coverage: the views whose absence used to abort the app.
//
// A missing backend conformance is not a degradation. `@CastBackend` expands to
// `fatalError("'GtkBackend' does not implement '...'")`, so an app containing a
// `WebView` aborted the moment that view was laid out, and `AngularGradient` did
// the same -- on Linux and on Windows `-gtk4` alike. An app cannot guard against
// it either: there is no way to ask a backend what it supports before using it.
//
// This app is the falsifiable version of that claim. It shows both views. If the
// window appears at all, neither aborted; if either is still unimplemented, the
// app never reaches the point of drawing anything and there is nothing to
// screenshot. That is a sharper test than inspecting the conformance list,
// because it fails the same way a user's app would.
//
// P27 backend 功能覆蓋：那些「缺席即導致 app 中止」的 view。
//
// 缺少 backend conformance 並非降級。`@CastBackend` 會展開為
// `fatalError("'GtkBackend' does not implement '...'")`，因此含有 `WebView` 的 app 會在該 view
// 進行版面配置的當下中止，`AngularGradient` 亦然——Linux 與 Windows `-gtk4` 皆是如此。app 也無法
// 對此設防：沒有任何方式可在使用某功能之前，詢問 backend 是否支援它。
//
// 本 app 是該主張的可證偽版本。它同時顯示這兩個 view。若視窗能夠出現，代表兩者皆未中止；若其中
// 任一仍未實作，app 根本到不了繪製任何東西的階段，也就沒有東西可供截圖。這比檢視 conformance
// 清單更為銳利，因為它失敗的方式與使用者的 app 完全相同。
//
// Build this file as a standalone app target.

enum P27Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func renderComplete() {
        guard isEnabled, !didAnnounceRender else { return }
        didAnnounceRender = true
        print("[P27] RENDER COMPLETE -- WebView and AngularGradient both laid out without aborting")
    }
}

@main
@HotReloadable
struct P27BackendCoverageApp: App {
    var body: some Scene {
        WindowGroup("P27 backend feature coverage") {
            #hotReloadable {
                P27RootView()
            }
        }
        .defaultSize(width: 760, height: 520)
    }
}

struct P27RootView: View {
    // WebView takes a Binding, not a URL -- it reports navigations back through
    // it. Held in state so the binding has somewhere to write.
    // WebView 接受的是 Binding 而非 URL——它會透過該綁定回報導覽。以 state 持有，使該綁定有處
    // 可寫。
    @State var url = URL(string: "https://example.com")!

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("P27: backend feature coverage")
                .font(.system(size: 20))

            Text("backend -> \(String(describing: DefaultBackend.self))")

            Text("If this window is on screen, neither view below aborted the app.")

            // All three gradient kinds side by side. Angular is the one that used
            // to abort; the other two are the control -- if all three draw, the
            // new one is not merely present but agreeing with its neighbours.
            // 三種漸層並排。angular 是先前會中止的那一個；另外兩個是對照組——若三者皆能繪製，
            // 代表新加入的那個不只是「存在」，而且與其相鄰者表現一致。
            Text("Gradients")
                .font(.system(size: 16))

            HStack(spacing: 12) {
                // The `colors:` forms, not `gradient: Gradient(colors:)`.
                // `Gradient` is public but both of its initialisers are
                // internal, so app code cannot construct one -- only these
                // convenience initialisers can. SwiftUI's `Gradient(colors:)` is
                // public; that difference is recorded as its own finding.
                // 使用 `colors:` 形式，而非 `gradient: Gradient(colors:)`。`Gradient` 雖為 public，
                // 但其兩個建構式皆為 internal，因此 app 程式碼無法建立它——只能透過這些便利建構式。
                // SwiftUI 的 `Gradient(colors:)` 是公開的；該差異另行記錄為一項發現。
                gradientSample("Linear") {
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: UnitPoint(x: 0, y: 0),
                        endPoint: UnitPoint(x: 1, y: 1)
                    )
                }
                gradientSample("Radial") {
                    RadialGradient(
                        colors: [.yellow, .red],
                        center: UnitPoint(x: 0.5, y: 0.5),
                        startRadius: 0,
                        endRadius: 80
                    )
                }
                gradientSample("Angular") {
                    AngularGradient(
                        colors: [.red, .green, .blue, .red],
                        center: UnitPoint(x: 0.5, y: 0.5),
                        angle: .degrees(0)
                    )
                }
            }

            // The three cases the row above cannot see, added 2026-08-27 with
            // the GtkBackend fixes for them. Each was drawn wrongly with no
            // diagnostic, and each looks perfectly reasonable on its own -- the
            // whole point is that they are only wrong *next to* the row above,
            // or next to another backend.
            //
            // Read them as: a ring must have a solid centre and a flat outside,
            // and both sweeps must show all four colours. A sample that fills
            // its whole 160x120 box edge to edge, or that is one flat colour,
            // is the defect rather than a bold design.
            //
            // 上排看不到的三個情形，於 2026-08-27 隨 GtkBackend 對應的修正一併加入。三者都曾被錯誤
            // 繪製且無任何診斷訊息，而且單獨看每一個都相當合理——重點正在於，它們只有「與上排並列」
            // 或「與另一個 backend 並列」時才顯得錯誤。
            //
            // 判讀方式：環必須有實心的中心與平坦的外圍，而兩個扇形都必須顯示全部四種顏色。若某個
            // 樣本填滿了整個 160x120 的方框、或呈現單一平色，那是缺陷，不是大膽的設計。
            HStack(spacing: 12) {
                gradientSample("Ring (start 30)") {
                    RadialGradient(
                        colors: [.yellow, .red],
                        center: UnitPoint(x: 0.5, y: 0.5),
                        startRadius: 30,
                        endRadius: 60
                    )
                }
                gradientSample("Ring reversed") {
                    RadialGradient(
                        colors: [.yellow, .red],
                        center: UnitPoint(x: 0.5, y: 0.5),
                        startRadius: 60,
                        endRadius: 20
                    )
                }
                gradientSample("Sweep reversed") {
                    AngularGradient(
                        colors: [.red, .green, .blue, .red],
                        center: UnitPoint(x: 0.5, y: 0.5),
                        startAngle: .degrees(270),
                        endAngle: .degrees(90)
                    )
                }
            }

            // The web view. On a backend without one this is a labelled
            // placeholder rather than a crash or a silent blank -- a blank area
            // reads as a layout bug, whereas the text names the missing feature.
            //
            // It stays here as the abort guard only: this app's question is
            // "did laying this out kill the process", and the answer is visible
            // whether or not a page appears. Whether a page actually renders is
            // P38's question, and it is a different one -- measured 2026-08-27
            // on WinUIBackend, four `msedgewebview2.exe` processes were running
            // while this frame stayed empty, so the control initialises and the
            // browser host starts and nothing is painted.
            //
            // web view。在沒有 web view 的 backend 上，此處是「有文字說明的佔位」，而非崩潰或
            // 靜默空白——空白區域看起來像版面 bug，而文字會指出缺少的是哪一個功能。
            //
            // 它留在此處僅作為「中止防護」：本 app 要問的是「把這個東西排版出來會不會殺掉行程」，
            // 而無論頁面是否出現，該問題的答案都看得見。「頁面究竟有沒有被繪製」是 P38 的問題，
            // 且是另一回事——2026-08-27 於 WinUIBackend 實測：此框保持空白的同時，有四個
            // `msedgewebview2.exe` 行程正在執行，亦即控制項完成初始化、瀏覽器主機也啟動了，
            // 但什麼都沒有被畫出來。
            Text("WebView")
                .font(.system(size: 16))

            WebView($url)
                .frame(width: 700, height: 160)
        }
        .padding(18)
        .onAppear {
            P27Diagnostics.renderComplete()
        }
    }

    func gradientSample<Content: View>(
        _ label: String,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.system(size: 13))
            content()
                .frame(width: 160, height: 120)
        }
    }
}
