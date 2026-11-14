import DefaultBackend
import Foundation
import SwiftCrossUI

// P117 TextEditor sizing on GtkBackend: reproduces todo item 16, GTK's
// "Widget reports min width of 4 for height of 18, but overall min width of
// 10" warning, which SoftPCB-UI prints 22 times on its tab 8.
//
// The suspect is SoftPCB-UI's TextEditor (CrossleaderPane.swift:284): empty
// text, `.frame(height: 80)` with no width, `.background` and
// `.cornerRadius(6)`, in a leading VStack with spacing 6. P2's TextEditor,
// with a fixed width of 560 and text in it, prints nothing. GTK prints the
// warning (gtksizerequestcache.c, a G_ENABLE_DEBUG build such as C:/gtk4)
// when a widget's minimum width for a given height is smaller than its
// minimum width for no height, so the width the editor is given matters.
//
// P117_VARIANT picks one shape, so a warning can be pinned to it; unset shows
// all four:
//   a  SoftPCB-UI's: empty, height 80, background, corner radius
//   b  a without the background and corner radius
//   c  a with text in it
//   d  a with a fixed width of 560, as P2 (the control)
//   e  SoftPCB-UI's BubbleText: one Text per paragraph, " " and "." among
//      them, each .frame(width: 640) -- the shape that warned
// Count the warnings in the app's stderr.
//
// P117 GtkBackend 上的 TextEditor 尺寸：重現 todo 第 16 項,GTK 的「Widget reports min width of 4 for height of 18, but overall
// min width of 10」警告,SoftPCB-UI 在 tab 8 印出 22 次。嫌疑是 SoftPCB-UI 的 TextEditor(CrossleaderPane.swift:284):空文字、
// 只有 `.frame(height: 80)` 沒有寬度、`.background` 與 `.cornerRadius(6)`,放在 spacing 6 的靠左 VStack 裡。P2 的 TextEditor
// 寬度固定 560 且有文字，什麼都沒印。GTK 在 widget 給定高度時的最小寬度小於不限高度時的最小寬度時印出這個警告
// (gtksizerequestcache.c,需 G_ENABLE_DEBUG 建置，例如 C:/gtk4),所以 editor 拿到的寬度是關鍵。P117_VARIANT 選一種形狀，好把
// 警告歸到它身上；不設時四種都顯示:a 是 SoftPCB-UI 的形狀(空、高 80、背景、圓角),b 是 a 去掉背景與圓角,c 是 a 加上文字，
// d 是 a 加上固定寬度 560(與 P2 相同，對照組)。到 app 的 stderr 數警告。
//
// Build this file as a standalone app target.

@main
struct P117App: App {
    var body: some Scene {
        WindowGroup("P117 TextEditor sizing") {
            P117View()
        }
        .defaultSize(width: 760, height: 620)
    }
}

struct P117View: View {
    static let variant = ProcessInfo.processInfo.environment["P117_VARIANT"] ?? "all"

    @State var emptyA = ""
    @State var emptyB = ""
    @State var filledC = "Some prompt text\nover two lines"
    @State var emptyD = ""
    static let paragraphs = ["First paragraph of a reply", " ", "Second paragraph", ".", "x"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("P117: TextEditor sizing (todo item 16), variant \(Self.variant)")
                    .padding(.bottom, 8)
                if Self.shows("a") {
                    section("a: empty, height 80, background, corner radius") {
                        TextEditor(text: $emptyA)
                            .frame(height: 80)
                            .background(Color.gray)
                            .cornerRadius(6)
                    }
                }
                if Self.shows("b") {
                    section("b: empty, height 80") {
                        TextEditor(text: $emptyB)
                            .frame(height: 80)
                    }
                }
                if Self.shows("c") {
                    section("c: text, height 80, background, corner radius") {
                        TextEditor(text: $filledC)
                            .frame(height: 80)
                            .background(Color.gray)
                            .cornerRadius(6)
                    }
                }
                if Self.shows("d") {
                    section("d: empty, 560 x 80, background, corner radius (control)") {
                        TextEditor(text: $emptyD)
                            .frame(width: 560, height: 80)
                            .background(Color.gray)
                            .cornerRadius(6)
                    }
                }
                if Self.shows("e") {
                    // SoftPCB-UI's BubbleText: one Text per paragraph, a blank
                    // paragraph as " ", each in a fixed-width frame. The one that
                    // reproduced (SoftPCB-W11, 2026-11-14).
                    // SoftPCB-UI 的 BubbleText:每段一個 Text,空段落是 " ",每個都放在固定寬度的框裡。重現出來的就是這個
                    // (SoftPCB-W11,2026-11-14)。
                    section("e: one Text per paragraph, \" \" and \".\" among them, 640 wide") {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(Self.paragraphs.enumerated()), id: \.offset) { item in
                                Text(item.element)
                                    .frame(width: 640, alignment: .leading)
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
        .onAppear {
            print("P117 ready variant=\(Self.variant)")
        }
    }

    static func shows(_ name: String) -> Bool {
        variant == "all" || variant == name
    }

    /// One SoftPCB-shaped block: a caption, the editor, a row of buttons.
    /// 一個 SoftPCB 形狀的區塊：說明、editor、一列按鈕。
    func section<Editor: View>(_ title: String, @ViewBuilder editor: () -> Editor) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            editor()
            HStack(spacing: 8) {
                Button("Send") {}
                Button("Stop") {}
            }
        }
        .padding(.bottom, 12)
    }
}
