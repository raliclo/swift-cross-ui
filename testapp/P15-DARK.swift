import DefaultBackend
import SwiftCrossUI

// P15-DARK: does preferredColorScheme(.dark) actually take effect? (#386)
//
// A fixed request rather than P15's buttons, because clicking a specific small
// button through synthesised input is unreliable under client-side decorations
// (the window origin includes the invisible shadow margin, so window-relative
// coordinates land slightly off). Asking for dark unconditionally removes the
// input step from the measurement: launch it under a light theme, and if the
// override works the window comes up dark.
//
// P15-DARK：preferredColorScheme(.dark) 是否確實生效？（#386）
//
// 採用固定的要求而非 P15 的按鈕，因為在 client-side decoration 之下，以合成輸入點擊某個小按鈕並
// 不可靠（視窗原點包含不可見的陰影邊界，因此視窗相對座標會略微偏移）。無條件要求 dark 可將輸入
// 這一步自量測中移除：在淺色主題下啟動它，若 override 有效，視窗便會以深色呈現。
//
// Build this file as a standalone app target.

@main
@HotReloadable
struct P15DarkApp: App {
    var body: some Scene {
        WindowGroup("P15-DARK preferredColorScheme") {
            #hotReloadable {
                P15DarkView()
            }
        }
        .defaultSize(width: 560, height: 300)
    }
}

struct P15DarkView: View {
    @Environment(\.colorScheme) var resolved

    var body: some View {
        VStack(spacing: 12) {
            Text("P15-DARK: preferredColorScheme(.dark)")
                .font(.system(size: 18))

            Text("Requested: dark   Resolved: \(resolved == .dark ? "dark" : "light")")

            Text("Plain text on the default background")
            Button("A button") {}
            Text("Expected under a light theme: this window is dark and readable.")
        }
        .padding(20)
        .preferredColorScheme(.dark)
    }
}
