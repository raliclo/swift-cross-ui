// P88: onContinuousHover -- where the pointer is, and which modifier keys are held (2026-10-10).
//
// Written for SoftPCB's 3D view: hold Command over the model to read the value of the nearest
// node, without clicking the view first. The blue panel has both .onDragGesture and
// .onContinuousHover, because the hover wrapper must not take the drag from the view.
//
// Pass:
//   1 "pointer" follows the mouse over the panel, in points from its top left
//   2 holding Command shows (cmd) at once, also without moving (AppKit; elsewhere at the next move)
//   3 "last with cmd" keeps where Command was last held
//   4 dragging across the panel still counts drags (the wrapper takes no clicks)
//   5 leaving the panel shows "ended"
//   6 touch screens: a finger held still (iOS 0.5 s, Android the long-press timeout) then moved
//     reports hover; "last active" keeps where it was, and lifting shows "ended" (2026-10-15)
//   7 the panel is orange while hovered, blue again once the hover ends
// Fail: nothing changes (no hover), (cmd) never appears, or drags stay at 0.
//
// P88:onContinuousHover——指標在哪裡、按住了哪些修飾鍵(2026-10-10)。為 SoftPCB 的三維檢視而寫：在模型上
// 按住 Command 讀最近節點的值，而不必先點那個 view。藍色面板同時有 .onDragGesture 與 .onContinuousHover,
// 因為 hover 的包裝不得搶走 view 的拖曳。通過條件見上；失敗：完全不變(沒有 hover)、從不出現 (cmd),
// 或拖曳次數停在 0。

import DefaultBackend
@_spi(Backends) import SwiftCrossUI

final class P88Model: SwiftCrossUI.ObservableObject {
    static let shared = P88Model()
    @SwiftCrossUI.Published var pointer = "pointer: not yet"
    @SwiftCrossUI.Published var lastCommand = "last with cmd: never"
    /// Kept after `.ended`, so a capture after a finger lifts still shows where the hold was.
    /// `.ended` 之後仍保留，手指放開後的擷圖仍看得到按住時在哪裡。
    @SwiftCrossUI.Published var lastActive = "last active: never"
    /// The panel is orange while hovered and blue otherwise. / 被 hover 時面板是橘色，否則是藍色。
    @SwiftCrossUI.Published var hovering = false
    @SwiftCrossUI.Published var drags = 0
    /// The control: a panel with the same drag and no hover wrapper. / 對照組：同樣的拖曳、沒有 hover 包裝的面板。
    @SwiftCrossUI.Published var controlDrags = 0
    @SwiftCrossUI.Published var reports = 0
    @SwiftCrossUI.Published var stillChange = "modifier change without moving: not seen"
    private var previous: (SIMD2<Double>, EventModifiers)?

    static func keys(_ modifiers: EventModifiers) -> String {
        var names: [String] = []
        if modifiers.contains(.command) { names.append("cmd") }
        if modifiers.contains(.shift) { names.append("shift") }
        if modifiers.contains(.option) { names.append("option") }
        if modifiers.contains(.control) { names.append("control") }
        return names.isEmpty ? "" : " (\(names.joined(separator: "+")))"
    }

    func hover(_ phase: PointerHoverPhase) {
        reports += 1
        switch phase {
            case .active(let location, let modifiers):
                let at = "x=\(Int(location.x.rounded())) y=\(Int(location.y.rounded()))"
                pointer = "pointer: \(at)\(Self.keys(modifiers))"
                lastActive = "last active: \(at)"
                hovering = true
                if modifiers.contains(.command) { lastCommand = "last with cmd: \(at)" }
                if let (place, keys) = previous, place == location, keys != modifiers, !modifiers.isEmpty {
                    stillChange = "modifier change without moving: seen\(Self.keys(modifiers))"
                }
                previous = (location, modifiers)
            case .ended:
                pointer = "pointer: ended"
                hovering = false
                previous = nil
        }
    }
}

@main
struct P88App: App {
    var body: some Scene {
        WindowGroup("P88 pointer hover") {
            #hotReloadable {
                P88View()
            }
        }
        .defaultSize(width: 440, height: 520)
    }
}

struct P88View: View {
    @Environment(\.backend) var backend
    @ObservedObject var model = P88Model.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("P88: onContinuousHover (pointer + modifier keys)")
            Text(
                "pointer hover supported: \(backend is any BackendFeatures.PointerHover ? "yes" : "NO")"
            )
            (model.hovering ? Color.orange : Color.blue)
                .frame(width: 360, height: 240)
                .onDragGesture { _ in
                } onEnded: { _ in
                    P88Model.shared.drags += 1
                }
                .onContinuousHover { phase in P88Model.shared.hover(phase) }
            Color.green
                .frame(width: 360, height: 60)
                .onDragGesture { _ in
                } onEnded: { _ in
                    P88Model.shared.controlDrags += 1
                }
            Text(model.pointer)
            Text(model.lastActive)
            Text(model.lastCommand)
            Text(model.stillChange)
            Text("drags: \(model.drags) · control drags: \(model.controlDrags) · hover reports: \(model.reports)")
            Text("1 pointer follows · 2 (cmd) while held · 3 last cmd kept")
            Text("4 drags still count · 5 leaving shows ended")
        }
        .padding(16)
    }
}
