import DefaultBackend
import SwiftCrossUI

// P2 Windows repro app:
// - #449 WinUIBackend Picker option updating code.
// - #471 WinUIBackend TextEditor has a thin border when not focused.
// - #401 Disable full screen button when window resizing is disabled.
// - #390 Disabled buttons do not appear disabled.
//
// Build this file as a standalone app target.

@main
@HotReloadable
struct P2ControlsAndStylingWinUIApp: App {
    @State var windowResizable = false

    var body: some Scene {
        WindowGroup("P2 WinUI controls and styling") {
            #hotReloadable {
                P2ControlsAndStylingView(windowResizable: $windowResizable)
                    .windowResizeBehavior(windowResizable ? .enabled : .disabled)
            }
        }
        .defaultSize(width: 620, height: 520)
    }
}

struct P2ControlsAndStylingView: View {
    @Binding var windowResizable: Bool

    @State var useExpandedPickerOptions = false
    @State var selectedFlavor: String? = "Vanilla"
    @State var pickerChangeCount = 0
    @State var text = """
        Click outside this TextEditor.
        On WinUI, the unfocused TextEditor should not show a thin border.
        """
    @State var enabled = false

    var pickerOptions: [String] {
        if useExpandedPickerOptions {
            return ["Vanilla", "Chocolate", "Strawberry", "Mint", "Coffee"]
        } else {
            return ["Vanilla", "Chocolate"]
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("P2: control updates and visual states")
                .font(.system(size: 18))

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Use expanded Picker options", isOn: $useExpandedPickerOptions)

                HStack(spacing: 8) {
                    Text("Flavor")
                        .frame(width: 70, alignment: .leading)

                    Picker(of: pickerOptions, selection: $selectedFlavor)
                        .pickerStyle(.menu)
                        .frame(width: 220, height: 32)

                    Button("Reset") {
                        selectedFlavor = "Vanilla"
                        pickerChangeCount = 0
                    }
                }

                Text(
                    "Selected: \(selectedFlavor ?? "nil"), options: \(pickerOptions.count), changes: \(pickerChangeCount)"
                )
                Text("Expected: dropdown stays open, selected flavor changes, and options update after toggling.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: selectedFlavor) {
                pickerChangeCount += 1
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("TextEditor border check")

                HStack {
                    Button("Set 12345") {
                        text = "12345"
                    }

                    Button("Clear") {
                        text = ""
                    }

                    Text("Length: \(text.count)")
                }

                TextEditor(text: $text)
                    .frame(width: 560, height: 150, alignment: .leading)
                Text("Expected: no thin border when unfocused, no missed keystrokes, caret remains usable.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Enable button row", isOn: $enabled)

                HStack {
                    Button("Disabled action") {}
                        .disabled(!enabled)

                    Button("Always enabled") {}

                    Toggle("Disabled toggle", isOn: $enabled)
                        .disabled(true)
                }

                Text("Expected: disabled controls should be visibly distinct.")

                // Button roles, added 2026-08-28. Two buttons with the same
                // label, differing only in role, so the platform's warning
                // styling is the only thing that can distinguish them -- on GTK
                // the `destructive-action` class, which Adwaita paints red.
                //
                // The plain one is the control, and it is what makes this a
                // test: a red button alone proves nothing, since the theme could
                // be painting every button that way.
                //
                // A backend with no notion of roles draws two identical buttons,
                // and that is the correct degradation rather than a failure --
                // the action still works, only the warning colour is missing.
                //
                // 按鈕 role，於 2026-08-28 加入。兩個標籤相同、僅 role 不同的按鈕，如此平台的示警
                // 樣式就是唯一能區分它們的東西——在 GTK 上是 `destructive-action` 類別，Adwaita 會
                // 把它畫成紅色。
                //
                // 那個沒有 role 的是對照組，也正是讓這成為一項測試的關鍵：單獨一顆紅色按鈕什麼也
                // 證明不了，因為主題有可能把每一顆按鈕都畫成那樣。
                //
                // 沒有 role 概念的 backend 會畫出兩顆一模一樣的按鈕，而那是正確的降級而非失敗——
                // 動作照常運作，缺少的只是警示色。
                HStack {
                    Button("Delete") {}

                    Button("Delete", role: .destructive) {}

                    Button("Cancel", role: .cancel) {}
                }

                Text("Expected: the second Delete warns; the first and Cancel do not.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Allow window resizing", isOn: $windowResizable)
                Text("Expected: disabled resizing should also disable the full screen button.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
    }
}
