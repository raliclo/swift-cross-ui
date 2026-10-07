import DefaultBackend
import Foundation
import SwiftCrossUI

// P83: does .listStyle(.sidebar) change how a List is drawn?
//
// The number was checked: `ls testapp` gives P0..P82.
//
// Written 2026-10-08. GTK (navigation-sidebar) and WinUI (the NavigationView
// pane) honoured the style; AppKit, UIKit and Android drew both lists the same.
// Two lists with the same rows and the same selection, side by side: the left
// one default, the right one .sidebar. Pass: the right list looks like the
// platform's sidebar (its background, its selection) and the left does not.
// Fail: the two are identical.
//
// P83:.listStyle(.sidebar) 是否改變 List 的畫法?編號查過:`ls testapp` 給出 P0..P82。2026-10-08 撰寫。
// 兩個列相同、選取相同的清單左右並排：左邊預設，右邊 .sidebar。通過：右邊看起來是平台的側邊欄，左邊不是。
// 失敗：兩者一模一樣。

@main
@HotReloadable
struct P83ListStyleApp: App {
    @State var left: String? = "Inbox"
    @State var right: String? = "Inbox"
    let rows = ["Inbox", "Drafts", "Sent", "Archive"]

    var body: some Scene {
        WindowGroup("P83 list styles") {
            #hotReloadable {
                VStack(alignment: .leading, spacing: 10) {
                    Text("P83: list styles").font(.system(size: 18))
                    Text("backend -> \(String(describing: DefaultBackend.self))")
                    Text("left: \(left ?? "none")   right: \(right ?? "none")")
                    HStack(spacing: 16) {
                        VStack(alignment: .leading) {
                            Text("default")
                            List(rows, id: \.self, selection: $left) { Text($0) }
                                .frame(width: 180, height: 200)
                        }
                        VStack(alignment: .leading) {
                            Text(".sidebar")
                            List(rows, id: \.self, selection: $right) { Text($0) }
                                .listStyle(.sidebar)
                                .frame(width: 180, height: 200)
                        }
                    }
                    Text("pass: the right list is drawn as the platform's sidebar; fail: both alike.")
                }
                .padding(20)
            }
        }
        .defaultSize(width: 480, height: 400)
    }
}
