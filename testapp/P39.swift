import DefaultBackend
import Foundation
import SwiftCrossUI

// P39 visual effects: opacity, blur and the colour adjustments.
//
// The first app for BackendFeatures.VisualEffects, added 2026-08-27 with the
// protocol itself. Before it, SwiftCrossUI had no .opacity, .blur, .saturation,
// .brightness, .contrast, .grayscale or .hueRotation at all -- not unimplemented
// on some backend, absent from the framework.
//
// Every cell draws the same two things: a full colour wheel and a line of text.
// Both are needed, and neither is decoration. The wheel is the only source here
// that carries every hue at once, so saturation, grayscale and hueRotation have
// something to act on; a flat colour would leave hueRotation looking like a
// no-op. The text is the only thing with edges, so blur has something to soften;
// a gradient blurs into something almost identical to itself.
//
// The first cell applies VisualEffect.identity and is the control. Read every
// other cell against it, not against expectation -- "this looks blurred" is not
// a judgement anyone can make from one picture, and the whole family of defects
// this app exists to catch is the effect silently doing nothing.
//
// P39 視覺效果：不透明度、模糊，以及各種色彩調整。
//
// 這是 BackendFeatures.VisualEffects 的第一個測試 app，於 2026-08-27 與該 protocol 一同加入。在此
// 之前，SwiftCrossUI 完全沒有 .opacity、.blur、.saturation、.brightness、.contrast、.grayscale 或
// .hueRotation——不是「某個 backend 沒實作」，而是整個框架裡不存在。
//
// 每個格子都繪製相同的兩樣東西：一個完整色輪與一行文字。兩者都必要，且都不是裝飾。色輪是此處唯一
// 同時具備所有色相的來源，saturation、grayscale 與 hueRotation 才有作用對象；若用單一平色，
// hueRotation 看起來就會像什麼都沒做。文字則是唯一具有邊緣的東西，blur 才有可柔化的對象；漸層被
// 模糊後幾乎與自身無異。
//
// 第一格套用的是 VisualEffect.identity，作為對照組。請拿其餘每一格與它相比，而非與心中的預期相比
// ——「這看起來像模糊了」不是任何人能從單一張圖做出的判斷，而本 app 所要捕捉的整類缺陷，正是
// 「效果靜默地什麼也沒做」。
//
//     zsh testapp/run.zsh P39
//     zsh testapp/run.zsh P39 --debug
//
// Build this file as a standalone app target.

enum P39Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")

    static func report(_ message: String) {
        guard isEnabled else { return }
        print("[P39] \(message)")
    }
}

@main
@HotReloadable
struct P39VisualEffectsApp: App {
    var body: some Scene {
        WindowGroup("P39 visual effects") {
            #hotReloadable {
                P39RootView()
            }
        }
        .defaultSize(width: 860, height: 620)
    }
}

struct P39RootView: View {
    static let samples: [(String, VisualEffect)] = [
        ("none (control)", .identity),
        ("opacity 0.35", VisualEffect(opacity: 0.35)),
        ("blur 3", VisualEffect(blurRadius: 3)),
        ("saturation 0", VisualEffect(saturation: 0)),
        ("saturation 2.5", VisualEffect(saturation: 2.5)),
        ("brightness 0.4", VisualEffect(brightness: 0.4)),
        ("contrast 0.3", VisualEffect(contrast: 0.3)),
        ("grayscale 1", VisualEffect(grayscale: 1)),
        ("hueRotation 120", VisualEffect(hueRotation: .degrees(120))),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("P39: visual effects")
                .font(.system(size: 20))

            Text("backend -> \(String(describing: DefaultBackend.self))")

            Text("Compare every cell against the first. Identical to it means the effect did nothing.")

            VStack(alignment: .leading, spacing: 10) {
                P39Row(samples: Array(Self.samples[0..<3]))
                P39Row(samples: Array(Self.samples[3..<6]))
                P39Row(samples: Array(Self.samples[6..<9]))
            }
        }
        .padding(18)
        .onAppear {
            P39Diagnostics.report("backend \(String(describing: DefaultBackend.self))")
            P39Diagnostics.report("\(Self.samples.count) samples, first is the control")
        }
    }
}

struct P39Row: View {
    var samples: [(String, VisualEffect)]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(samples, id: \.0) { sample in
                P39Cell(label: sample.0, effect: sample.1)
            }
        }
    }
}

struct P39Cell: View {
    var label: String
    var effect: VisualEffect

    var body: some View {
        VStack(spacing: 4) {
            // The label sits outside the effect on purpose. Blurring or fading
            // the caption along with the sample would make the cell harder to
            // identify exactly when the effect is working.
            // 標籤刻意置於效果之外。若讓說明文字隨樣本一起模糊或淡出，反而會在效果正常運作時
            // 使人更難辨認該格是哪一個。
            Text(label)
                .font(.system(size: 12))

            VStack(spacing: 0) {
                AngularGradient(
                    colors: [.red, .yellow, .green, .blue, .purple, .red],
                    center: UnitPoint(x: 0.5, y: 0.5),
                    angle: .degrees(0)
                )
                .frame(width: 200, height: 90)

                Text("Hamburgefonstiv 123")
                    .font(.system(size: 15))
            }
            .visualEffect(effect)
        }
    }
}
