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

            // The web view. On a backend without one this is a labelled
            // placeholder rather than a crash or a silent blank -- a blank area
            // reads as a layout bug, whereas the text names the missing feature.
            // web view。在沒有 web view 的 backend 上，此處是「有文字說明的佔位」，而非崩潰或
            // 靜默空白——空白區域看起來像版面 bug，而文字會指出缺少的是哪一個功能。
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
