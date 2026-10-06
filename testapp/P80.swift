import DefaultBackend
import Foundation
import SwiftCrossUI

// P80: cursors, a context menu, key events and scroll gestures, on one screen.
//
// The number was checked: `ls testapp` gives P0..P79.
//
// Written 2026-10-06, when GtkBackend gained `Cursors`, `ContextMenus`,
// `KeyEvents` and `ScrollGestures` -- AppKit, UIKit and Android had them, and
// the only app exercising them, P72, is built around a Mesh3DView that GTK
// does not have yet. Every readout is on screen, so one capture after an
// action says whether it arrived:
//
//   - hover each cursor row: the pointer changes (seen, not captured);
//   - right-click (or long-press) the menu box: "menu picked: Second" after
//     choosing Second;
//   - type: "last key" shows the key, its phase and the modifiers;
//   - scroll over the scroll box: "scroll" shows the translation, and "ended"
//     counts the gestures.
//
// P80:游標、內容選單、按鍵事件與捲動手勢，放在同一個畫面。編號查過:`ls testapp` 給出 P0..P79。
// 2026-10-06 撰寫，當時 GtkBackend 加入了 `Cursors`、`ContextMenus`、`KeyEvents` 與 `ScrollGestures`——
// AppKit、UIKit 與 Android 都已經有了，而唯一測它們的 P72 是以 GTK 尚未支援的 Mesh3DView 為中心。每個
// 讀數都在畫面上，所以每個動作後擷一張圖，就看得出它有沒有送到。

@main
@HotReloadable
struct P80InputTargetsApp: App {
    var body: some Scene {
        WindowGroup("P80 input targets") {
            #hotReloadable {
                P80RootView()
            }
        }
        .defaultSize(width: 560, height: 520)
    }
}

struct P80RootView: View {
    @State var picked = "nothing"
    @State var lastKey = "none"
    @State var keyCount = 0
    @State var translation = SIMD2<Double>(0, 0)
    @State var scrollEnds = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("P80: input targets")
                .font(.system(size: 18))
            Text("backend -> \(String(describing: DefaultBackend.self))")

            Text("cursors -- hover each:")
            HStack(spacing: 6) {
                Text(" hand ").border(.gray).cursor(.pointingHand)
                Text(" cross ").border(.gray).cursor(.crosshair)
                Text(" text ").border(.gray).cursor(.text)
                Text(" ↔ ").border(.gray).cursor(.resizeHorizontal)
                Text(" ↕ ").border(.gray).cursor(.resizeVertical)
                Text(" no ").border(.gray).cursor(.notAllowed)
            }

            Text("menu picked: \(picked)")
            Text("  right-click or long-press here for a menu  ")
                .padding(8)
                .border(.gray)
                .contextMenu {
                    Button("First") { picked = "First" }
                    Button("Second") { picked = "Second" }
                }

            Text("last key: \(lastKey)  (\(keyCount) events)")
            Text("scroll: \(Int(translation.x)), \(Int(translation.y))   ended: \(scrollEnds)")
            Text("  scroll over this box  ")
                .frame(width: 260, height: 80)
                .border(.gray)
                .onScrollGesture(
                    onChanged: { value in translation = value.translation },
                    onEnded: { _ in scrollEnds += 1 }
                )
        }
        .padding(16)
        .onKeyPress { press in
            keyCount += 1
            let key = press.key.map { String($0.character.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined()) } ?? "modifier"
            lastKey = "\(press.characters.isEmpty ? key : press.characters) \(press.phase) mods=\(press.modifiers.rawValue)"
        }
    }
}
