import DefaultBackend
import Foundation
import SwiftCrossUI

// P132 blendMode(_:): how a view's pixels combine with what is drawn behind it.
//
// A grid of 21 cells, one per BlendMode, each labelled with its mode. In every cell
// a horizontal gradient from yellow (255, 217, 26) to blue (26, 77, 230) is drawn
// first, and a pink square (230, 51, 128) is drawn over it with the cell's blend
// mode; the square's right and bottom edges stick out past the gradient onto the
// window background. "normal" is the control: the plain pink square.
//
// A last row of four cells covers what the grid's opaque backdrop cannot show
// (P132Extra): in "½ multiply", "½ plusLighter" and "½ plusDarker" the gradient is
// half transparent and the cell is drawn as a group (opacity 0.99), so the backdrop
// the square blends with is translucent -- the multiply square is half transparent
// as well -- and "op½ multiply" is `.opacity(0.5)` and `.blendMode(.multiply)` in one
// container, `visualEffect(VisualEffect(opacity: 0.5, blendMode: .multiply))`, over
// the opaque gradient.
//
// The screenshot is the check for the colours -- see the action files' header for
// what each cell should look like. The app also measures every blended square
// against the plain one and logs "P132 PASS" when they are all the same size (a
// blend mode never changes layout) or "P132 FAIL (...)", to p132-debug-events.log
// (SCUI_DEBUG_EVENTS_DIR) and stdout, a second after it appears.
//
// P132 blendMode(_:):view 的像素如何與其後方已畫好的內容結合。
//
// 21 格的格狀排列，每種 BlendMode 一格，並標上模式名稱。每一格先畫一條由黃(255, 217, 26)到藍(26, 77, 230)
// 的水平漸層，再以該格的混合模式在其上畫一個粉紅方塊(230, 51, 128);方塊的右緣與下緣超出漸層，落在視窗背景上。
// 「normal」是對照組：一般的粉紅方塊。
//
// 最後一列四格涵蓋格狀排列的不透明背景無法呈現的情況(P132Extra):「½ multiply」、「½ plusLighter」與
// 「½ plusDarker」的漸層半透明，且整格以群組繪製(opacity 0.99),因此方塊所混合的背景是半透明的——multiply 的
// 方塊本身也半透明;「op½ multiply」則是同一個容器中的 `.opacity(0.5)` 與 `.blendMode(.multiply)`,即
// `visualEffect(VisualEffect(opacity: 0.5, blendMode: .multiply))`,畫在不透明的漸層上。
//
// 顏色由截圖檢查——每格應有的樣子見動作檔開頭的說明。app 也會把每個混合後的方塊與一般方塊比較尺寸，全部相同時
// (混合模式從不改變版面)在出現一秒後於 p132-debug-events.log(SCUI_DEBUG_EVENTS_DIR)與 stdout 記下
// 「P132 PASS」,否則記下「P132 FAIL (...)」。
//
// Build this file as a standalone app target.

enum P132 {
    static let title = "P132 Blend mode"

    @MainActor static var sizes: [String: ViewSize] = [:]

    static func log(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
        let path = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
                ?? FileManager.default.currentDirectoryPath
        ).appendingPathComponent("p132-debug-events.log")
        let data = Data("\(Date()) \(message)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: path) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: path)
        }
    }

    @MainActor static func verdict() -> String {
        guard let plain = sizes["normal"] else {
            return "P132 FAIL (normal not measured)"
        }
        log("P132 normal: \(plain.width)x\(plain.height)")
        var failures: [String] = []
        let names = BlendMode.allCases.filter { $0 != .normal }.map { "\($0)" }
            + P132Extra.allCases.map(\.rawValue)
        for name in names {
            guard let size = sizes[name] else {
                failures.append("\(name) not measured")
                continue
            }
            if size.width != plain.width || size.height != plain.height {
                failures.append("\(name) is \(size.width)x\(size.height)")
            }
        }
        return failures.isEmpty ? "P132 PASS" : "P132 FAIL (\(failures.joined(separator: "; ")))"
    }
}

@main
struct P132App: App {
    var body: some Scene {
        WindowGroup(P132.title) {
            P132View()
        }
        .defaultSize(width: 420, height: 760)
    }
}

struct P132Recorder: View {
    var name: String
    var size: ViewSize

    var body: some View {
        P132.sizes[name] = size
        return Color.clear
    }
}

/// One cell: the gradient, the square over it with `mode`, and the mode's name.
/// 一格：漸層、以 `mode` 疊在其上的方塊，以及模式名稱。
struct P132Cell: View {
    var mode: BlendMode

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: [
                        Color(red: 1, green: 0.85, blue: 0.1),
                        Color(red: 0.1, green: 0.3, blue: 0.9),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 64, height: 36)
                Color(red: 0.9, green: 0.2, blue: 0.5)
                    .frame(width: 36, height: 36)
                    .blendMode(mode)
                    .background(
                        GeometryReader { proxy in
                            P132Recorder(name: "\(mode)", size: proxy.size)
                        }
                    )
                    .padding(.leading, 36)
                    .padding(.top, 14)
            }
            .frame(width: 72, height: 50, alignment: .topLeading)
            Text("\(mode)").font(.caption)
        }
        .frame(width: 80, alignment: .leading)
    }
}

/// The last row: a translucent backdrop, and opacity with a blend mode in one container.
/// 最後一列：半透明的背景，以及同一容器中的 opacity 與混合模式。
enum P132Extra: String, CaseIterable {
    /// A half-transparent square multiplied over the half-transparent gradient.
    /// 半透明的方塊以 multiply 疊在半透明的漸層上。
    case halfMultiply = "½ multiply"
    /// The opaque square, plusLighter, over the half-transparent gradient.
    /// 不透明的方塊以 plusLighter 疊在半透明的漸層上。
    case halfPlusLighter = "½ plusLighter"
    /// The opaque square, plusDarker, over the half-transparent gradient.
    /// 不透明的方塊以 plusDarker 疊在半透明的漸層上。
    case halfPlusDarker = "½ plusDarker"
    /// The opaque square at opacity 0.5 with multiply, in one container, over the
    /// opaque gradient. / 不透明的方塊在同一容器中設 opacity 0.5 與 multiply,疊在不透明的漸層上。
    case opacityMultiply = "op½ multiply"

    var translucentBackdrop: Bool { self != .opacityMultiply }

    var effect: VisualEffect {
        switch self {
            case .halfMultiply: VisualEffect(blendMode: .multiply)
            case .halfPlusLighter: VisualEffect(blendMode: .plusLighter)
            case .halfPlusDarker: VisualEffect(blendMode: .plusDarker)
            case .opacityMultiply: VisualEffect(opacity: 0.5, blendMode: .multiply)
        }
    }

    var squareOpacity: Double { self == .halfMultiply ? 0.5 : 1 }
}

/// A cell of the last row, laid out as P132Cell.
/// 最後一列的一格，版面與 P132Cell 相同。
struct P132ExtraCell: View {
    var extra: P132Extra

    var body: some View {
        let backdrop = extra.translucentBackdrop ? 0.5 : 1
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: [
                        Color(red: 1, green: 0.85, blue: 0.1).opacity(backdrop),
                        Color(red: 0.1, green: 0.3, blue: 0.9).opacity(backdrop),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 64, height: 36)
                Color(red: 0.9, green: 0.2, blue: 0.5).opacity(extra.squareOpacity)
                    .frame(width: 36, height: 36)
                    .visualEffect(extra.effect)
                    .background(
                        GeometryReader { proxy in
                            P132Recorder(name: extra.rawValue, size: proxy.size)
                        }
                    )
                    .padding(.leading, 36)
                    .padding(.top, 14)
            }
            .frame(width: 72, height: 50, alignment: .topLeading)
            // A group below 1, so the square's backdrop is the translucent gradient
            // alone rather than the window behind it.
            // 小於 1 的群組，讓方塊的背景只有半透明的漸層，而不是其後方的視窗。
            .opacity(extra.translucentBackdrop ? 0.99 : 1)
            Text(extra.rawValue).font(.caption)
        }
        .frame(width: 80, alignment: .leading)
    }
}

struct P132View: View {
    @State var verdict = "Measuring"

    /// Four modes to a row, in BlendMode's order, so a phone shows all 21 at once (seven
    /// ran off an Android screen after the third, CI run 45505727478).
    /// 每列四種模式，依 BlendMode 的順序，讓手機一次顯示全部 21 種(七種時 Android 畫面在第三種之後就超出，CI run 45505727478)。
    var rows: [[BlendMode]] {
        let modes = BlendMode.allCases
        return stride(from: 0, to: modes.count, by: 4).map {
            Array(modes[$0..<min($0 + 4, modes.count)])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(P132.title)
            Text(verdict)
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { mode in
                        P132Cell(mode: mode)
                    }
                }
            }
            HStack(spacing: 6) {
                ForEach(P132Extra.allCases, id: \.self) { extra in
                    P132ExtraCell(extra: extra)
                }
            }
        }
        .padding(20)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let result = P132.verdict()
                P132.log(result)
                verdict = result
            }
        }
    }
}
