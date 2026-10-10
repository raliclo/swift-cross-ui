// P89: .offset on text inside an overlay, static, changed later, and appearing later (2026-10-10).
//
// Found in SoftPCB's tab 9: a label given .offset inside an .overlay was drawn at the overlay's corner
// while a ring (a shape) beside it, also given .offset, was drawn where asked. Everything here should
// start on the red line (x = 100): a ring, a text, a text with a background, a text whose offset is 0 at
// first and becomes 100 after two seconds, and a text that only appears after two seconds.
//
// Pass: after two seconds all five start on the red line, at y 20, 50, 80, 120, 160.
// Fail: anything starts at the panel's left edge instead.
//
// P89：overlay 裡文字的 .offset——固定的、之後才改的、之後才出現的(2026-10-10)。在 SoftPCB 的分頁 9 發現：
// overlay 裡加了 .offset 的標籤畫在 overlay 的角落，而旁邊同樣加了 .offset 的圓圈(形狀)畫在指定的位置。這裡
// 每一樣都應該從紅線(x = 100)開始。通過：兩秒後五樣都從紅線開始；失敗：有任何一樣貼在面板左緣。

import DefaultBackend
import Foundation
@_spi(Backends) import SwiftCrossUI

final class P89Model: SwiftCrossUI.ObservableObject {
    static let shared = P89Model()
    @SwiftCrossUI.Published var x = 0.0
    @SwiftCrossUI.Published var late = false
    @SwiftCrossUI.Published var state = "state: before (C at 0, D absent)"
    private var armed = false

    func arm() {
        guard !armed else { return }
        armed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.x = 100
            self.late = true
            self.state = "state: after (C moved to 100, D appeared)"
        }
    }
}

@main
struct P89App: App {
    var body: some Scene {
        WindowGroup("P89 offset in overlay") {
            #hotReloadable {
                P89View()
            }
        }
        .defaultSize(width: 440, height: 380)
    }
}

struct P89View: View {
    @ObservedObject var model = P89Model.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("P89: .offset on text inside an overlay")
            Color.gray
                .frame(width: 360, height: 240)
                .overlay(alignment: .topLeading) {
                    ZStack(alignment: .topLeading) {
                        Color.red.frame(width: 1, height: 240).padding(.leading, 100)
                        Circle()
                            .stroke(Color.white, style: StrokeStyle(width: 2))
                            .frame(width: 14, height: 14)
                            .offset(x: 100, y: 20)
                        Text("A static text").foregroundColor(.white).offset(x: 100, y: 50)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("B with background").foregroundColor(.white)
                        }
                        .padding(4)
                        .background(Color.black)
                        .offset(x: 100, y: 80)
                        Text("C offset changes").foregroundColor(.white).offset(x: model.x, y: 120)
                        if model.late {
                            Text("D appears later").foregroundColor(.white).offset(x: 100, y: 160)
                        }
                    }
                }
            Text(model.state)
            Text("all five start on the red line after two seconds")
        }
        .padding(16)
        .onAppear { P89Model.shared.arm() }
    }
}
