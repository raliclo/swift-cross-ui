import DefaultBackend
import Foundation
import SwiftCrossUI

// P8 Linux (GtkBackend) repro app: scroll views.
//
// - #417 Giving a ScrollView a cornerRadius does not affect its children, so
//   content shows through the rounded corners instead of being clipped by
//   them.
// - #426 A horizontal ScrollView swallows scroll wheel input that belongs to
//   the vertical ScrollView it sits inside, so the outer view stops scrolling
//   whenever the pointer is over the inner one.
//
// The colours are deliberately loud: #417 is only visible where the child's
// background meets the corner, so a pale child on a pale background would hide
// it.
//
// Build this file as a standalone app target.
//
// Run with `--debug` to write geometry and render readiness to
// `p8-debug-events.log`. The dry-run script waits for that marker instead of
// guessing with a fixed sleep.

enum P8Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")

    nonisolated(unsafe) private static var lastReported: [String: String] = [:]
    nonisolated(unsafe) private static var measuredRoles: Set<P8Probe.Role> = []
    nonisolated(unsafe) private static var hasAnnouncedRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P8] \(message)")

        guard let data = "P8 \(Date()) \(message)\n".data(using: .utf8) else { return }
        let logURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p8-debug-events.log")
        if FileManager.default.fileExists(atPath: logURL.path),
            let handle = try? FileHandle(forWritingTo: logURL)
        {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: logURL)
        }
    }

    static func record(role: P8Probe.Role, size: ViewSize) {
        guard isEnabled else { return }

        let line = String(format: "%.0fx%.0f", size.width, size.height)
        guard lastReported[role.rawValue] != line else { return }
        lastReported[role.rawValue] = line
        measuredRoles.insert(role)
        write("\(role.rawValue): \(line)")

        if measuredRoles.isSuperset(of: Set(P8Probe.Role.allCases)),
            !hasAnnouncedRender
        {
            hasAnnouncedRender = true
            write("RENDER COMPLETE -- all P8 probes measured, safe to capture")
        }
    }
}

struct P8Probe: View {
    enum Role: String, CaseIterable {
        case cornerScroll
        case redChild
        case outerScroll
        case innerStrip
    }

    init(role: Role, size: ViewSize) {
        P8Diagnostics.record(role: role, size: size)
    }

    var body: some View {
        EmptyView()
    }
}

@main
@HotReloadable
struct P8ScrollViewsApp: App {
    var body: some Scene {
        WindowGroup("P8 scroll views") {
            #hotReloadable {
                P8RootView()
            }
        }
        .defaultSize(width: 640, height: 560)
    }
}

struct P8RootView: View {
    @State var outerScrollNote = "Scroll the outer view: the row numbers should move."

    var body: some View {
        VStack(spacing: 10) {
            Text("P8: scroll views")
                .font(.system(size: 20))
            Text(outerScrollNote)

            // #417: the child fills the ScrollView, so its corners are the
            // only place the rounding can be judged. If the red reaches a
            // square corner, the child was not clipped.
            VStack(alignment: .leading, spacing: 4) {
                Text("#417 cornerRadius(20) with a red child")
                ScrollView {
                    Color.red
                        .frame(width: 260, height: 300)
                        .overlay(alignment: .topLeading) {
                            GeometryReader { proxy in
                                P8Probe(role: .redChild, size: proxy.size)
                            }
                        }
                }
                .frame(width: 260, height: 120)
                .cornerRadius(20)
                .overlay(alignment: .topLeading) {
                    GeometryReader { proxy in
                        P8Probe(role: .cornerScroll, size: proxy.size)
                    }
                }
            }

            // #426: the outer vertical ScrollView contains a horizontal one.
            // Scrolling with the pointer over the inner strip should still
            // move the outer view once the inner one has nowhere left to go.
            VStack(alignment: .leading, spacing: 4) {
                Text("#426 horizontal strip inside a vertical scroll view")
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(Array(0..<12)) { row in
                            if row == 4 {
                                ScrollView(.horizontal) {
                                    HStack(spacing: 8) {
                                        ForEach(Array(0..<14)) { column in
                                            Text("H\(column)")
                                                .padding(8)
                                        }
                                    }
                                }
                                .frame(height: 48)
                                .overlay(alignment: .topLeading) {
                                    GeometryReader { proxy in
                                        P8Probe(role: .innerStrip, size: proxy.size)
                                    }
                                }
                            } else {
                                Text("Outer row \(row)")
                                    .padding(6)
                            }
                        }
                    }
                }
                .frame(width: 420, height: 220)
                .overlay(alignment: .topLeading) {
                    GeometryReader { proxy in
                        P8Probe(role: .outerScroll, size: proxy.size)
                    }
                }
            }
        }
        .padding(12)
    }
}
