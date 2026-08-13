import DefaultBackend
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
// - GtkBackend.swift declares `canOverrideWindowColorScheme = false`, and
//   GtkBackend.swift:200 carries a `TODO(stackotter): Support
//   preferredColorScheme`. So the scheme buttons below are expected to do
//   nothing on GtkBackend. They are here as the control: the same build on
//   WinUIBackend does honour them, which separates "the override is missing"
//   from "the colours are wrong".
// - The real #386 test is therefore the ambient theme, not the override:
//
//       GTK_THEME=Adwaita:dark ./testapp/output/P15
//
//   That makes Gtk render dark without the app asking, which is the situation
//   the upstream screenshots were taken in.
//
// WSLg runs a Wayland compositor, and Gtk draws client-side decorations under
// Wayland, so #289's precondition holds here. That is not the same as Fedora
// with GNOME, so a negative result bounds the bug rather than closing it.
//
// Build this file as a standalone app target.

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
                        status = "Requested light. GtkBackend is expected to ignore this."
                    }
                    Button("Dark") {
                        scheme = .dark
                        status = "Requested dark. GtkBackend is expected to ignore this."
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
