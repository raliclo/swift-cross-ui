import DefaultBackend
import Foundation
import SwiftCrossUI
#if canImport(UIKitBackend)
    import UIKitBackend
#endif

// P82: does Button(role: .destructive) look destructive, the platform's way?
//
// The number was checked: `ls testapp` gives P0..P81.
//
// Written 2026-10-07. Until then the role reached every backend and none used
// it: on GtkBackend "button, destructive" drew like any other button. The user
// chose each platform's own destructive style -- the system red label on AppKit
// and UIKit, the theme's colorError on Android, GTK's destructive-action class,
// the critical system colour on WinUI.
//
// Pass: the three "destructive" buttons are in the platform's warning colour,
// the disabled one dimmed; "save" and "cancel" are not; "destructive, blue set"
// is blue, because an app's colour wins.
//
// P82:Button(role: .destructive) 看起來是否以平台自己的方式呈現危險?編號查過:`ls testapp` 給出 P0..P81。
// 2026-10-07 撰寫。在那之前 role 送到每個 backend,但沒有一個使用它。使用者選了各平台自己的危險樣式。
// 通過：三顆「destructive」按鈕是平台的警示色，停用的那顆變淡;「save」與「cancel」不是;「destructive, blue set」
// 是藍色，因為 app 指定的顏色優先。

@main
@HotReloadable
struct P82DestructiveApp: App {
    @State var pressed = "nothing"
    @State var note = ""

    var body: some Scene {
        WindowGroup("P82 destructive buttons") {
            #hotReloadable {
                VStack(alignment: .leading, spacing: 10) {
                    Text("P82: destructive buttons")
                        .font(.system(size: 18))
                    Text("backend -> \(String(describing: DefaultBackend.self))")
                    Text("pressed: \(pressed)")

                    Button("save") { pressed = "save" }
                    Button("destructive, bordered", role: .destructive) {
                        pressed = "destructive, bordered"
                    }
                    .buttonStyle(.bordered)
                    Button("destructive, borderless", role: .destructive) {
                        pressed = "destructive, borderless"
                    }
                    .buttonStyle(.borderless)
                    Button("destructive, disabled", role: .destructive) {}
                        .disabled(true)
                    Button("destructive, blue set", role: .destructive) {
                        pressed = "destructive, blue set"
                    }
                    .foregroundColor(.blue)
                    Button("cancel", role: .cancel) { pressed = "cancel" }
                    #if canImport(UIKitBackend)
                        // Compiles only if `.foregroundColor` inside a toolbar still
                        // picks the ToolbarItem overload (see KeyboardToolbar.swift).
                        TextField("keyboard toolbar check", text: $note)
                            .keyboardToolbar {
                                Button("done") {}.foregroundColor(.red)
                            }
                    #endif

                    Text("pass: the destructive ones in the warning colour, the disabled one dimmed;")
                    Text("save and cancel ordinary; blue set stays blue.")
                }
                .padding(20)
            }
        }
        .defaultSize(width: 480, height: 460)
    }
}
