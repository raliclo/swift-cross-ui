import DefaultBackend
import Foundation
import SwiftCrossUI

// P15 Linux (GtkBackend) repro app: colour scheme and window minimum height.
//
// - #386 Dark mode is not supported. Upstream's screenshots show text keeping
//   its light-mode colours against a dark background, so the text ends up
//   near-invisible. Reported on Fedora 43.
// - #289 The window's minimum height is set incorrectly on distributions where
//   Gtk draws its own title bar (client-side decorations) instead of letting
//   the window manager do it. Upstream suspects the decoration height is not
//   accounted for in the minimum sizing code, though it is elsewhere.
//
// Two things worth knowing before reading the results, both checked in the
// source rather than assumed:
//
// - GtkBackend now declares `canOverrideWindowColorScheme = true`, so the
//   scheme buttons below do change what is drawn. Superseded 2026-08-27; the
//   text kept below is what this header said until then, because it is the
//   reason the app prints a `Requested:`/`Resolved:` pair at all and that line
//   is still what makes a dead click distinguishable from an honoured one.
//
//       "GtkBackend.swift declares `canOverrideWindowColorScheme = false` [...]
//        So the scheme buttons below are expected to do nothing on GtkBackend.
//        They are here as the control: the same build on WinUIBackend does
//        honour them, which separates 'the override is missing' from 'the
//        colours are wrong'."
//
// - The ambient theme is still worth testing separately, since no click can set
//   it:
//
//       GTK_THEME=Adwaita:dark ./testapp/output/P15
//
//   That makes Gtk render dark without the app asking, which is the situation
//   the upstream screenshots were taken in.
//
// - Press Light and then Dark, in that order. Pressing Dark alone under a dark
//   desktop proves nothing, because the window was already dark. The round trip
//   is what found the bug: until 2026-08-27, GtkBackend compared the request
//   against the *ambient* scheme, so returning to the ambient value wrote
//   nothing and left Gtk in the overridden theme -- dark text colours over a
//   light window.
//
// 讀結果之前值得知道的兩件事，皆查證於原始碼而非臆測：
//
// - GtkBackend 現在宣告 `canOverrideWindowColorScheme = true`，因此下方的配色按鈕確實會改變繪製
//   結果。此處於 2026-08-27 被取代；上方保留的引文是在那之前本表頭的說法，因為它正是本 app 會
//   印出 `Requested:`／`Resolved:` 這一組值的理由，而該行至今仍是「無效點擊」與「已被遵從的
//   點擊」之間唯一的區別。
//
// - 環境主題仍值得單獨測試，因為沒有任何點擊能設定它（指令同上）。
//
// - 請依序按下 Light 再按 Dark。在深色桌面下單獨按 Dark 什麼也證明不了，因為視窗本來就是深色的。
//   真正找出問題的是這趟來回：在 2026-08-27 之前，GtkBackend 是拿要求值與「環境」配色比較，
//   因此「回到環境值」不會寫入任何東西，Gtk 便停留在被覆寫後的主題——深色的文字配色畫在淺色
//   視窗上。
//
// WSLg runs a Wayland compositor, and Gtk draws client-side decorations under
// Wayland, so #289's precondition holds here. That is not the same as Fedora
// with GNOME, so a negative result bounds the bug rather than closing it.
//
// Build this file as a standalone app target.

enum P15Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")
    nonisolated(unsafe) private static var didAnnounceRender = false

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P15] \(message)")

        guard let data = "P15 \(Date()) \(message)\n".data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("p15-debug-events.log")
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

    static func renderComplete() {
        guard !didAnnounceRender else { return }
        didAnnounceRender = true
        write("RENDER COMPLETE -- P15 ready for #386 and #289 checks")
    }
}

@main
@HotReloadable
struct P15ThemeAndSizingApp: App {
    @State var scheme: ColorScheme?

    var body: some Scene {
        WindowGroup("P15 colour scheme and window height") {
            #hotReloadable {
                P15RootView(scheme: $scheme)
            }
        }
        .defaultSize(width: 720, height: 560)
    }
}

struct P15RootView: View {
    @Binding var scheme: ColorScheme?

    // What the view tree actually resolved to, which is not necessarily what
    // the buttons asked for. On GtkBackend the two are expected to disagree.
    @Environment(\.colorScheme) var resolvedScheme

    @State var text = "Editable text"
    @State var toggleOn = true
    @State var showsTallContent = false
    @State var status = "Shrink the window vertically as far as it will go."

    var body: some View {
        VStack(spacing: 12) {
            Text("P15: colour scheme and window height")
                .font(.system(size: 20))

            Text(status)

            // ---- #386 ------------------------------------------------------
            VStack(alignment: .leading, spacing: 6) {
                Text("Colour scheme (#386)")

                Text("Requested: \(requestedName)   Resolved: \(resolvedName)")

                HStack(spacing: 8) {
                    Button("System") {
                        scheme = nil
                        status = "Requested the system scheme."
                    }
                    Button("Light") {
                        scheme = .light
                        status = "Requested light. The window should follow, chrome included."
                    }
                    Button("Dark") {
                        scheme = .dark
                        status = "Requested dark. The window should follow, chrome included."
                    }
                }

                // Unstyled controls, so each one takes whatever foreground
                // colour the backend picks. #386 is that these stay dark on a
                // dark background rather than following the theme.
                VStack(alignment: .leading, spacing: 4) {
                    Text("Plain text on the default background")
                    Text("Text with an explicit colour").foregroundColor(.blue)
                    TextField("Text field", text: $text)
                        .frame(width: 260)
                    Toggle("Toggle", isOn: $toggleOn)
                        .frame(width: 260)
                    Button("Button") {}
                }
                .padding(6)
            }

            // ---- #289 ------------------------------------------------------
            VStack(alignment: .leading, spacing: 6) {
                Text("Window minimum height (#289)")

                // The content height is reported rather than eyeballed, so a
                // result can be written down and compared between sessions.
                GeometryReader { proxy in
                    Text("Content area: \(Int(proxy.size.width)) x \(Int(proxy.size.height))")
                }
                .frame(width: 300, height: 24)

                Button(showsTallContent ? "Use short content" : "Use tall content") {
                    showsTallContent.toggle()
                    status = showsTallContent
                        ? "Content is taller: the window minimum should grow to match."
                        : "Content is shorter: the window should now shrink further."
                }

                if showsTallContent {
                    VStack(spacing: 2) {
                        ForEach(Array(1...6), id: \.self) { row in
                            Text("Extra row \(row) of 6")
                        }
                    }
                }

                Text("Drag the bottom edge up until the window stops shrinking.")
                Text("Nothing should be cut off at the smallest height it allows.")
            }
        }
        .padding(14)
        .preferredColorScheme(scheme)
        .onAppear {
            P15Diagnostics.renderComplete()
        }
    }

    var requestedName: String {
        switch scheme {
            case .none: "system"
            case .some(.light): "light"
            case .some(.dark): "dark"
        }
    }

    var resolvedName: String {
        switch resolvedScheme {
            case .light: "light"
            case .dark: "dark"
        }
    }
}
