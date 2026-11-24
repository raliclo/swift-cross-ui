import DefaultBackend
import Foundation
import SwiftCrossUI

// P132 blendMode(_:): how a view's pixels combine with what is drawn behind it.
//
// A grid of 21 cells, one per BlendMode, each labelled with its mode. In every cell
// a horizontal gradient from yellow (255, 217, 26) to blue (26, 77, 230) is drawn
// first, and a pink square (230, 51, 128) is drawn over it with the cell's blend
// mode; the square's right and bottom edges stick out past the gradient onto the
// window background. "normal" is the control: the plain pink square. The
// screenshot is the check for the colours -- see the action files' header for
// what each cell should look like. The app also measures every blended square
// against the plain one and logs "P132 PASS" when they are all the same size (a
// blend mode never changes layout) or "P132 FAIL (...)", to p132-debug-events.log
// (SCUI_DEBUG_EVENTS_DIR) and stdout, a second after it appears.
//
// P132 blendMode(_:):view 的像素如何與其後方已畫好的內容結合。
//
// 21 格的格狀排列，每種 BlendMode 一格，並標上模式名稱。每一格先畫一條由黃(255, 217, 26)到藍(26, 77, 230)
// 的水平漸層，再以該格的混合模式在其上畫一個粉紅方塊(230, 51, 128);方塊的右緣與下緣超出漸層，落在視窗背景上。
// 「normal」是對照組：一般的粉紅方塊。顏色由截圖檢查——每格應有的樣子見動作檔開頭的說明。app 也會把每個混合後的
// 方塊與一般方塊比較尺寸，全部相同時(混合模式從不改變版面)在出現一秒後於 p132-debug-events.log
// (SCUI_DEBUG_EVENTS_DIR)與 stdout 記下「P132 PASS」,否則記下「P132 FAIL (...)」。
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
        for mode in BlendMode.allCases where mode != .normal {
            let name = "\(mode)"
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
        .defaultSize(width: 860, height: 560)
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
                .frame(width: 90, height: 50)
                Color(red: 0.9, green: 0.2, blue: 0.5)
                    .frame(width: 50, height: 50)
                    .blendMode(mode)
                    .background(
                        GeometryReader { proxy in
                            P132Recorder(name: "\(mode)", size: proxy.size)
                        }
                    )
                    .padding(.leading, 50)
                    .padding(.top, 20)
            }
            .frame(width: 100, height: 70, alignment: .topLeading)
            Text("\(mode)")
        }
        .frame(width: 110, alignment: .leading)
    }
}

struct P132View: View {
    @State var verdict = "Measuring"

    /// Seven modes to a row, in BlendMode's order. / 每列七種模式，依 BlendMode 的順序。
    var rows: [[BlendMode]] {
        let modes = BlendMode.allCases
        return stride(from: 0, to: modes.count, by: 7).map {
            Array(modes[$0..<min($0 + 7, modes.count)])
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
