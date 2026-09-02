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
        // Tall enough for every row. The grid is three columns, so the tenth
        // sample started a fourth row that fell outside the old 620 and was
        // never laid out -- and a cell that is never laid out never applies its
        // effect, so `hueRotation 120` simply vanished from the backend's log
        // while the nine visible cells all looked correct. Nothing reported it:
        // the window was not clipped, it was just short.
        // 高度足以容納每一列。此格線為三欄，因此第十個樣本開啟了第四列，而它落在原本的 620
        // 之外、從未被配置——未被配置的格子不會套用它的效果，於是 `hueRotation 120` 就這樣
        // 從 backend 的記錄中消失，而可見的九格看起來全都正確。沒有任何東西回報這件事：
        // 視窗並沒有被裁切，它只是不夠高。
        .defaultSize(width: 860, height: 780)
    }
}

struct P39RootView: View {
    static let samples: [(String, VisualEffect)] = [
        ("none (control)", .identity),
        ("opacity 0.35", VisualEffect(opacity: 0.35)),
        ("blur 3", VisualEffect(blurRadius: 3)),
        ("saturation 0", VisualEffect(saturation: 0)),
        // The midpoint, and the reason it is here: 0 and 2.5 alone leave the
        // whole range between them unguarded. WinUIBackend used to hand
        // saturation to Win2D's SaturationEffect, whose scale is its own and
        // was never checked against SwiftCrossUI's -- where 1 means unchanged.
        // A wrong midpoint would have drawn something plausible in every cell
        // this app had, so nothing would have reported it. Read this one as
        // roughly halfway between the grey cell and the control.
        // 中間點，而它存在的理由是：只有 0 與 2.5 時，兩者之間的整段區間無人看守。
        // WinUIBackend 過去把飽和度交給 Win2D 的 SaturationEffect，那個效果自有其刻度，
        // 而它與 SwiftCrossUI 的刻度（1 表示不變）是否一致從未被檢查過。中段若對應錯誤，
        // 在這支 app 原有的每一格裡都會畫出看似合理的結果，因此不會有任何東西回報它。
        // 請把這一格讀成介於灰色那格與對照組之間、大約一半的位置。
        ("saturation 0.5", VisualEffect(saturation: 0.5)),
        ("saturation 2.5", VisualEffect(saturation: 2.5)),
        ("brightness 0.4", VisualEffect(brightness: 0.4)),
        ("contrast 0.3", VisualEffect(contrast: 0.3)),
        ("grayscale 1", VisualEffect(grayscale: 1)),
        ("hueRotation 120", VisualEffect(hueRotation: .degrees(120))),
    ]

    /// The samples in rows of three, however many there are.
    ///
    /// Keyed by first label so `ForEach` has a stable identity; the index alone
    /// would do, but a label makes a diagnostic readable.
    /// 將樣本每三個一列，不論總共有幾個。
    ///
    /// 以第一個標籤作為鍵，使 `ForEach` 具有穩定的識別；僅用索引也可行，但標籤能讓診斷訊息
    /// 易於閱讀。
    static var rows: [(String, [(String, VisualEffect)])] {
        stride(from: 0, to: samples.count, by: 3).map { start in
            let row = Array(samples[start..<min(start + 3, samples.count)])
            return (row[0].0, row)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("P39: visual effects")
                .font(.system(size: 20))

            Text("backend -> \(String(describing: DefaultBackend.self))")

            Text("Compare every cell against the first. Identical to it means the effect did nothing.")

            // Rows derived from the sample count, not three hard-coded slices.
            // It used to read samples[0..<3], [3..<6], [6..<9], so adding a
            // tenth sample dropped it: no error, no warning, no gap on screen
            // -- the cell simply was not there, and because an un-laid-out cell
            // never applies its effect, the backend's log lost an entry too.
            // The window was made taller first, on the theory that the row had
            // fallen outside it; the extra height changed nothing and only the
            // count in the diagnostic showed the run was still short.
            // 各列由樣本數推導，而非三個寫死的切片。
            // 原本寫的是 samples[0..<3]、[3..<6]、[6..<9]，因此加入第十個樣本時它被丟掉了：
            // 沒有錯誤、沒有警告、畫面上也沒有缺口——那一格根本不存在，而由於未被配置的格子
            // 不會套用效果，backend 的記錄也少了一筆。當初曾先把視窗加高，以為那一列落到了
            // 視窗之外；加高之後毫無變化，只有診斷裡的計數顯示這一輪仍然不完整。
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Self.rows, id: \.0) { row in
                    P39Row(samples: row.1)
                }
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
