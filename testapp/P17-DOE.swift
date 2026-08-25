import DefaultBackend
import Foundation
import SwiftCrossUI

// P17-DOE: a design-of-experiments app for the #389 image-clipping fix.
//
// #389 is that GtkBackend never clipped an oversized child to its frame -- the
// one backend whose setCornerRadius only styled and never clipped. There are two
// candidate fixes ("directions"), and this app puts them side by side so the
// better one can be chosen by looking rather than by argument:
//
//   Control     no clip. The oversized block overflows its frame -- the bug.
//   Direction A cornerRadius(0). Clipping made a side effect of rounding, which
//               is what SwiftUI's cornerRadius does, and what P3 already uses, so
//               it fixes P3 with no change to the app.
//   Direction B clipped(). A new, explicit modifier that clips to bounds without
//               rounding, matching SwiftUI's .clipped(). More API, but says what
//               it means and does not overload cornerRadius.
//
// Each column frames a small grey viewport and centres a larger orange block in
// it. If the fix clips, only the viewport-sized orange shows; if not, the orange
// spills past the grey box. Both directions use the same GTK mechanism
// (overflow: hidden) reached through different modifiers, so the experiment is
// really about which API to expose, not whether the pixels differ.
//
// P17-DOE：針對 #389 圖片裁切修正的 design-of-experiments app。
//
// #389 是 GtkBackend 從不將超框的子元件裁切至其 frame——唯一一個 setCornerRadius 只設樣式、
// 從不裁切的 backend。有兩個候選修法(direction),本 app 將它們並排,使較佳者可以「看」出來
// 而非用「辯」的:
//
//   Control     不裁切。超框方塊溢出其 frame——即該 bug。
//   Direction A cornerRadius(0)。裁切作為圓角的副作用,這正是 SwiftUI 的 cornerRadius 行為,
//               也是 P3 已在用的,因此可在不改動 app 的情況下修好 P3。
//   Direction B clipped()。一個新的顯式 modifier,裁切至邊界但不圓角,對齊 SwiftUI 的
//               .clipped()。API 較多,但語意明確,且不會讓 cornerRadius 承載過多職責。
//
// 每一欄框出一個灰色小 viewport,並於其中置中一個較大的橘色方塊。若修法有裁切,只會顯示
// viewport 大小的橘色;若無,橘色會溢出灰框。兩個 direction 都用相同的 GTK 機制
// (overflow: hidden)、但經由不同 modifier,因此此實驗真正比較的是「該暴露哪種 API」,
// 而非「像素是否不同」。
//
// Build this file as a standalone app target.

enum P17DOEDiagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func renderComplete() {
        guard isEnabled, !didAnnounceRender else { return }
        didAnnounceRender = true
        print("[P17-DOE] RENDER COMPLETE -- clipping directions ready for comparison")
    }
}

@main
@HotReloadable
struct P17DOEApp: App {
    var body: some Scene {
        WindowGroup("P17-DOE clipping directions") {
            #hotReloadable {
                P17DOERootView()
            }
        }
        .defaultSize(width: 760, height: 480)
    }
}

struct P17DOERootView: View {
    // The viewport each column is supposed to show, and the oversized block that
    // should be clipped to it. The block is narrower than the viewport but much
    // taller, so it overflows vertically only: a clip leaves a blue viewport with
    // an orange stripe contained inside it, while no clip lets the stripe spill
    // above and below the blue box. Vertical overflow keeps the three columns
    // from bleeding into each other horizontally.
    let viewportWidth = 180
    let viewportHeight = 120
    let blockWidth = 100
    let blockHeight = 280

    var body: some View {
        VStack(spacing: 14) {
            Text("P17-DOE: #389 image-clipping directions")
                .font(.system(size: 20))

            Text("Orange should stay inside the grey box. If it spills out, the frame did not clip.")

            HStack(spacing: 40) {
                column("Control (no clip)") { viewport() }
                column("A: cornerRadius(0)") { viewport().cornerRadius(0) }
                column("B: clipped()") { viewport().clipped() }
            }
        }
        .padding(20)
        .onAppear {
            P17DOEDiagnostics.renderComplete()
        }
    }

    // A grey viewport with a larger orange block centred in it. Without a clip
    // the orange overflows the grey box.
    // 一個灰色 viewport,中央置一個較大的橘色方塊。若無裁切,橘色會溢出灰框。
    func viewport() -> some View {
        ZStack {
            Color(red: 0.20, green: 0.45, blue: 0.85)
            Color(red: 0.95, green: 0.55, blue: 0.15)
                .frame(width: blockWidth, height: blockHeight)
        }
        .frame(width: viewportWidth, height: viewportHeight)
    }

    func column<Content: View>(
        _ label: String,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.system(size: 13))
            content()
        }
    }
}
