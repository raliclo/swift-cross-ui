// P74: every picker style, side by side, each with its own readout.
//
// Written 2026-09-29, when the four styles turned out to be implemented on no two
// of the Apple and Android backends alike: AppKit had no `.wheel`, UIKit no
// `.radioGroup` and Android no `.segmented`. An unsupported style was downgraded
// to `.automatic` by the modifier, with a warning only in a debug build, and a
// backend that reached `createPicker` with it terminated -- so an app could ask for
// a style and silently get a different control, or no window. All three are now
// implemented, and this app is what shows each one exists and answers a choice.
//
// Each picker writes its own state, so a readout that changes proves that picker,
// not a neighbour. The options differ per picker for the same reason.
//
// P74:所有 picker 樣式並排,各自有讀數。2026-09-29 寫成,當時發現四種樣式在 Apple 與 Android 的 backend 上沒有
// 任何兩個實作得一樣:AppKit 沒有 `.wheel`、UIKit 沒有 `.radioGroup`、Android 沒有 `.segmented`。不支援的樣式會被
// modifier 降級為 `.automatic`,只有 debug 建置才會警告,而以它抵達 `createPicker` 的 backend 會被終止——所以 app 可能
// 要了一種樣式卻默默拿到別的控制項,或者根本沒有視窗。三者現在都已實作,而這支 app 就是用來證明每一種都存在、
// 也會回應選擇。每個 picker 寫自己的狀態,所以改變的讀數證明的是那一個 picker,不是隔壁的。

import DefaultBackend
import Foundation
import SwiftCrossUI

enum P74Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug")

    static func write(_ message: String) {
        guard isEnabled else { return }
        print("[P74] \(message)")
        fflush(stdout)
    }
}

@main
@HotReloadable
struct P74PickerStylesApp: App {
    var body: some Scene {
        WindowGroup("P74 picker styles") {
            #hotReloadable {
                P74RootView()
            }
        }
        .defaultSize(width: 520, height: 620)
    }
}

struct P74RootView: View {
    @State var menu: String? = "Apple"
    @State var segmented: String? = "One"
    @State var radio: String? = "Red"
    @State var wheel: String? = "Mon"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("P74: picker styles")
                    .font(.system(size: 18))
                Text("backend -> \(String(describing: DefaultBackend.self))")

                Text("menu -> \(menu ?? "nil")")
                Picker(of: ["Apple", "Banana", "Cherry"], selection: $menu)
                    .pickerStyle(.menu)

                Text("segmented -> \(segmented ?? "nil")")
                Picker(of: ["One", "Two", "Three"], selection: $segmented)
                    .pickerStyle(.segmented)

                Text("radioGroup -> \(radio ?? "nil")")
                Picker(of: ["Red", "Green", "Blue"], selection: $radio)
                    .pickerStyle(.radioGroup)

                Text("wheel -> \(wheel ?? "nil")")
                Picker(of: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], selection: $wheel)
                    .pickerStyle(.wheel)

                Text("Disabled radioGroup (must look dimmed and refuse input):")
                Picker(of: ["Red", "Green", "Blue"], selection: $radio)
                    .pickerStyle(.radioGroup)
                    .disabled(true)
            }
            .padding(16)
        }
        .onChange(of: menu) { P74Diagnostics.write("menu=\(menu ?? "nil")") }
        .onChange(of: segmented) { P74Diagnostics.write("segmented=\(segmented ?? "nil")") }
        .onChange(of: radio) { P74Diagnostics.write("radioGroup=\(radio ?? "nil")") }
        .onChange(of: wheel) { P74Diagnostics.write("wheel=\(wheel ?? "nil")") }
        .onAppear {
            P74Diagnostics.write("backend \(String(describing: DefaultBackend.self))")
            P74Diagnostics.write("RENDER COMPLETE -- P74 ready for picker style checks")
        }
    }
}
