import DefaultBackend
import Foundation
import SwiftCrossUI

// P81: a sheet, an alert, a popover and an open dialog, from either of two
// windows -- each must appear over the window that asked for it.
//
// The number was checked: `ls testapp` gives P0..P80.
//
// Written 2026-10-07, when AndroidBackend gave each window after the first an
// activity of its own (e71a8327) and presentations still went to the first
// one. Each window says its name in every presentation, so a capture shows
// both WHERE it appeared and WHO asked for it: "sheet from window B" over
// window A is the defect.
//
// P81:從兩個視窗中任一個打開 sheet、alert、popover 與開檔對話框——每一個都必須出現在要求它的那個視窗上。
// 編號查過:`ls testapp` 給出 P0..P80。2026-10-07 撰寫：當時 AndroidBackend 已讓第一個之後的每個視窗有自己的
// activity(e71a8327),但呈現仍跑到第一個視窗。每個視窗都在每次呈現中寫出自己的名字，所以一張擷圖就看得出它
// 出現在**哪裡**、是**誰**要求的:window A 上出現「sheet from window B」就是缺陷。

@main
@HotReloadable
struct P81PresentationsApp: App {
    var body: some Scene {
        WindowGroup("P81 window A") {
            #hotReloadable {
                P81RootView(label: "window A")
            }
        }
        .defaultSize(width: 520, height: 420)

        Window("P81 window B", id: "p81-second") {
            #hotReloadable {
                P81RootView(label: "window B")
            }
        }
        .defaultSize(width: 520, height: 420)
        .defaultLaunchBehavior(.suppressed)
    }
}

struct P81RootView: View {
    var label: String
    @State var sheetShown = false
    @State var alertShown = false
    @State var popoverShown = false
    @State var opened = "-"
    @Environment(\.openWindow) var openWindow
    @Environment(\.chooseFile) var chooseFile

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("P81: \(label)")
                .font(.system(size: 18))
            Text("backend -> \(String(describing: DefaultBackend.self))")
            Button("open second window") { openWindow(id: "p81-second") }
            Button("sheet") { sheetShown = true }
            Button("alert") { alertShown = true }
            Button("popover") { popoverShown = true }
                .popover(isPresented: $popoverShown) {
                    Text("popover from \(label)").padding(12)
                }
            Button("open file") {
                Task {
                    let url = await chooseFile()
                    opened = url?.lastPathComponent ?? "cancelled"
                }
            }
            Text("open file -> \(opened)")
            Text("Expected: each presentation appears over \(label) and names it.")
            Text("預期：每個呈現都出現在 \(label) 上，並寫出它的名字。")
        }
        .padding(16)
        .sheet(isPresented: $sheetShown) {
            VStack(spacing: 12) {
                Text("sheet from \(label)")
                Button("close") { sheetShown = false }
            }
            .padding(24)
        }
        .alert("alert from \(label)", isPresented: $alertShown) {
            Button("OK") {}
        }
    }
}
