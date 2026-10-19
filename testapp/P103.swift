// P103: the api18 "interested places" list as SwiftCrossUI components --
// EmojiKeywordListButton (the 📍 pin), EmojiKeywordList (the table),
// EmojiToggleButton (tap: on/off; long press: the picker) and EmojiPicker,
// on BackendFeatures.TapAndLongPressGestures.
//
// Top to bottom, at fixed sizes:
//   PIN     the 📍 button, open at launch; below it the list with three rows
//           (停車場 🅿 on, 便利商店 🏪 on, 加油站 ⛽ off), a field and Add.
//   SOLO    one EmojiToggleButton on its own (☕, keyword 咖啡, off).
//   PICKER  an EmojiPicker inline, keyword 咖啡, with its filter field.
//
// Every change is logged to p103-emoji.log and stdout:
//   ROW <keyword> on|off            a tap on a row's emoji
//   ROW <keyword> picker            a long press opened the row's picker
//   ROW <keyword> emoji <e>         chosen in the long-press picker
//   ROW added <keyword> <color>     Add
//   ROW removed <keyword>           ✕
//   SOLO on|off, SOLO picker, SOLO emoji <e>
//   PICKER chose <e>
//   PIN open|closed
//   CSV <one line per row, ; joined>   after every row change
// Pass, driven by testapp/actions/<platform>/P103-*.actions or by hand:
//   - a click on 停車場's 🅿: "ROW 停車場 off", and the circle turns grey;
//   - a long press on 便利商店's 🏪: "ROW 便利商店 picker", a sheet with the
//     picker, 🏪 first and purple; NO "ROW 便利商店 off" line (a long press
//     is not a tap);
//   - choosing in it: "ROW 便利商店 emoji <e>" and the sheet closes;
//   - typing 咖啡 and Add: "ROW added 咖啡 #8e24aa" (fourth palette colour);
//   - ✕ on 加油站: "ROW removed 加油站";
//   - the 📍 closes and reopens the list: "PIN closed", "PIN open".
//
// P103:api18「感興趣的地點」清單的 SwiftCrossUI 元件版——EmojiKeywordListButton(📍 釘選鈕)、EmojiKeywordList
// (表格)、EmojiToggleButton(點：開關;長按：選擇器)與 EmojiPicker,建立在 BackendFeatures.TapAndLongPressGestures
// 上。每個變化都記錄到 p103-emoji.log 與 stdout。通過條件見上方英文;重點是長按只叫出選擇器、不會切換開關。

import DefaultBackend
import Foundation
@_spi(Backends) import SwiftCrossUI

enum P103Log {
    /// Appends a line to p103-emoji.log and stdout. / 在 p103-emoji.log 與 stdout 加一行。
    static func write(_ line: String) {
        print("[P103] \(line)")
        let directory =
            ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
            ?? {
                #if os(iOS) || os(tvOS)
                    return NSHomeDirectory() + "/Documents"
                #else
                    return FileManager.default.currentDirectoryPath
                #endif
            }()
        let url = URL(fileURLWithPath: directory).appendingPathComponent("p103-emoji.log")
        guard let data = "P103 \(Date()) \(line)\n".data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    /// The lines describing how `old` became `new`. / 描述 `old` 如何變成 `new` 的各行。
    static func changes(from old: [EmojiKeywordItem], to new: [EmojiKeywordItem]) -> [String] {
        var lines: [String] = []
        for item in new {
            guard let before = old.first(where: { $0.id == item.id }) else {
                lines.append("ROW added \(item.keyword) \(item.color)")
                continue
            }
            if before.isOn != item.isOn { lines.append("ROW \(item.keyword) \(item.isOn ? "on" : "off")") }
            if before.emoji != item.emoji { lines.append("ROW \(item.keyword) emoji \(item.emoji)") }
        }
        for item in old where !new.contains(where: { $0.id == item.id }) {
            lines.append("ROW removed \(item.keyword)")
        }
        return lines
    }
}

@main
@HotReloadable
struct P103App: App {
    var body: some Scene {
        WindowGroup("P103 emoji") {
            #hotReloadable {
                P103RootView()
            }
        }
        .defaultSize(width: 480, height: 960)
    }
}

struct P103RootView: View {
    @Environment(\.self) var environment
    @State var items = [
        EmojiKeywordItem(keyword: "停車場", emoji: "🅿", color: "#1e88e5"),
        EmojiKeywordItem(keyword: "便利商店", emoji: "🏪", color: "#43a047"),
        EmojiKeywordItem(keyword: "加油站", emoji: "⛽", color: "#e53935", isOn: false),
    ]
    @State var listOpen = true
    @State var soloEmoji = "☕"
    @State var soloOn = false
    @State var picked = "📍"
    @State var status = "ready"

    func log(_ line: String) {
        status = line
        P103Log.write(line)
    }

    var loggedItems: Binding<[EmojiKeywordItem]> {
        Binding(
            get: { items },
            set: { new in
                let lines = P103Log.changes(from: items, to: new)
                items = new
                for line in lines { log(line) }
                if !lines.isEmpty {
                    let csv = EmojiKeywordItem.csv(new).split(separator: "\n").joined(separator: " ; ")
                    P103Log.write("CSV \(csv)")
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("P103: emoji keyword list").font(.system(size: 20))
            Text("last: \(status)")

            Text("PIN -- 📍 opens the list; tap an emoji to switch, hold it to change")
                .foregroundColor(.gray)
            EmojiKeywordListButton(
                items: loggedItems,
                isOpen: Binding(
                    get: { listOpen },
                    set: { open in
                        listOpen = open
                        log("PIN \(open ? "open" : "closed")")
                    }
                ),
                onPickerPresented: { item in log("ROW \(item.keyword) picker") }
            )

            Divider()
            HStack(spacing: 10) {
                Text("SOLO")
                EmojiToggleButton(
                    emoji: Binding(
                        get: { soloEmoji },
                        set: { soloEmoji = $0; log("SOLO emoji \($0)") }
                    ),
                    isOn: Binding(
                        get: { soloOn },
                        set: { soloOn = $0; log("SOLO \($0 ? "on" : "off")") }
                    ),
                    keyword: "咖啡",
                    onPickerPresented: { log("SOLO picker") }
                )
                Text(soloOn ? "on" : "off")
            }

            Divider()
            Text("PICKER -- keyword 咖啡, picked \(picked)")
            EmojiPicker(
                selection: Binding(get: { picked }, set: { picked = $0 }),
                keyword: "咖啡"
            ) { emoji in
                log("PICKER chose \(emoji)")
            }
            // 420 wide on a desktop or tablet; a phone takes the picker's own six-column width, as 420 is wider than its screen.
            // 桌面或平板上寬 420;手機用選擇器自己的六欄寬度，因為 420 比它的螢幕還寬。
            .frame(width: environment.deviceClass == .phone ? nil : 420)
        }
        .padding(16)
        // Top-aligned, so a row added or the list closed does not move everything else: the action files use fixed points.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            P103Log.write("RENDER COMPLETE rows \(items.count)")
        }
    }
}
