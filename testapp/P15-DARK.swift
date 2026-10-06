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
    // Counted in the button's own label, so "it must respond" can be read off a
    // capture; the action was empty. 計數寫在按鈕自己的標籤裡,「它必須有反應」才能從擷圖讀出;
    // 它的動作原本是空的。
    @State var presses = 0
    @State var text = ""
    @State var isOn = false

    var body: some View {
        VStack(spacing: 12) {
            Text("P15-DARK: preferredColorScheme(.dark)")
                .font(.system(size: 18))

            Text("Requested: dark   Resolved: \(resolved == .dark ? "dark" : "light")")

            Text("Plain text on the default background")
            Button("A button (\(presses))") {
                presses += 1
            }
            // System controls, not drawn by SwiftCrossUI: they follow the
            // preference only if the WINDOW carries it. On iOS before 2026-10-06
            // the background was dark and these stayed light.
            // 系統控制項，不是 SwiftCrossUI 畫的：只有 window 本身帶著偏好，它們才會跟著。
            // 2026-10-06 之前在 iOS 上背景是暗的，而這些仍是亮的。
            TextField("A text field", text: $text)
            Toggle("A toggle", isOn: $isOn)
            Text("Expected under a light theme: this window is dark and readable.")
        }
        .padding(20)
        .preferredColorScheme(.dark)
    }
}
