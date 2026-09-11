@_spi(Backends) import SwiftCrossUI

import DefaultBackend
import Foundation

// P68: what does `-GPU N` do on this backend?
//
// The number is checked: `ls testapp` gives P50..P67.
//
// **THE ADAPTERS ARE SHOWN, not just the outcome.** `-GPU 2` printing "using
// AMD Radeon Pro" is only meaningful beside the list it chose from: on a machine
// with one GPU, every request resolves to the same card and the feature looks
// like it works no matter what it does. The list is what makes the choice
// checkable.
//
// P68:`-GPU N` 在這個 backend 上做了什麼?
//
// 編號是查過的:`ls testapp` 給出 P50..P67。
//
// **會把那些介面卡列出來,而不只是結果。** `-GPU 2` 印出「using AMD Radeon Pro」,只有在「它所選自
// 的那份清單」旁邊才有意義:在一台只有一張 GPU 的機器上,每一種要求都會解析到同一張卡,於是無論這個
// 功能實際做了什麼,它看起來都像是正常的。那份清單才是讓這個選擇可被檢查的東西。

enum P68Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P68] \(message)")
        guard let data = "P68 \(Date()) \(message)\n".data(using: .utf8) else { return }
        let directory =
            ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
            ?? FileManager.default.currentDirectoryPath
        let url = URL(fileURLWithPath: directory)
            .appendingPathComponent("p68-debug-events.log")
        if FileManager.default.fileExists(atPath: url.path),
            let handle = try? FileHandle(forWritingTo: url)
        {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}

@main
@HotReloadable
struct P68App: App {
    var body: some Scene {
        WindowGroup("P68 graphics adapters") {
            #hotReloadable {
                P68RootView()
            }
        }
        .defaultSize(width: 620, height: 320)
    }
}

struct P68RootView: View {
    @Environment(\.backend) var backend
    @State var lines: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("P68: graphics adapters (-GPU N)")
                .font(.system(size: 18))
            Text("backend -> \(String(describing: DefaultBackend.self))")

            ForEach(lines, id: \.self) { line in
                Text(line)
            }
        }
        .padding(20)
        .onAppear {
            var collected: [String] = []
            if let adapters = backend as? any BackendFeatures.GraphicsAdapters {
                let list = adapters.availableAdapters
                collected.append("adapters: \(list.count)")
                for adapter in list {
                    collected.append(
                        "  \(adapter.name)"
                            + (adapter.isRemovable ? " [removable]" : "")
                            + (adapter.isLowPower ? " [low power]" : "")
                    )
                }
            } else {
                collected.append(
                    "\(type(of: backend)) does not implement GraphicsAdapters"
                )
            }
            let requested =
                CommandLine.arguments.firstIndex(of: "-GPU").map {
                    CommandLine.arguments.count > $0 + 1 ? CommandLine.arguments[$0 + 1] : "?"
                } ?? "(not given, so 1)"
            collected.append("-GPU requested: \(requested)")
            collected.append("The outcome line is on stderr, printed by the framework.")
            lines = collected
            for line in collected {
                P68Diagnostics.write(line)
            }
            P68Diagnostics.write("RENDER COMPLETE -- P68 listed the adapters")
        }
    }
}
