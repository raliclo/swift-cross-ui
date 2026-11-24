import DefaultBackend
import Foundation
@_spi(Backends) import SwiftCrossUI

#if canImport(CGtk)
    import CGtk
    import Gtk
    import GtkBackend
#endif
#if os(Android)
    import AndroidBackend
    import AndroidKit
#endif
#if !canImport(CGtk) && canImport(UIKitBackend)
    import UIKit
    import UIKitBackend
#elseif !canImport(CGtk) && canImport(AppKitBackend)
    import AppKit
    import AppKitBackend
#endif

// P127 .focusDisabled() and .focusEffectDisabled(), checked by the app itself.
// Ported in spirit from upstream's Examples/Sources/ControlFocusabilityTest.
//
// Four `.focusable()` panels in a column: "before"; a row holding a text field
// and an "inside" panel, under `.focusDisabled()`; "after"; and "ring off",
// under `.focusEffectDisabled()`. The app runs the checks itself and logs
// "P127 PASS" or "P127 FAIL (...)" to p127-debug-events.log
// (SCUI_DEBUG_EVENTS_DIR) and stdout:
//
//   1 one second after the window appears it asks for the focus on the text
//     field inside the disabled row: the request must be refused -- the
//     binding written back, the field not focused
//   2 then it focuses "before" from code: the binding must read "before"
//   3 it waits for ONE Tab, which the action file presses: the focus must land
//     on "after", stepping over both stops in the disabled row
//   4 it reads the focus ring off the native views: "after" must draw one and
//     "ring off" must not -- with "ring off" focused from code to look
//   5 it ends with the focus on "after", so the capture shows its ring.
//     P127-focus-effect-off.actions presses Tab once more, onto "ring off",
//     and its capture shows that panel focused with no ring
//
// No Tab within 40 seconds is a FAIL. A backend that does not implement
// BackendFeatures.FocusEffects or FocusDisabledContainers fails by name.
//
// P127 .focusDisabled() 與 .focusEffectDisabled(),由 app 自己檢查。精神上移植自上游的
// Examples/Sources/ControlFocusabilityTest。一欄四個 `.focusable()` 色塊:「before」;一列在 `.focusDisabled()`
// 之下、內有一個文字欄位與「inside」色塊;「after」;以及在 `.focusEffectDisabled()` 之下的「ring off」。app 自己執行
// 檢查，並在 p127-debug-events.log(SCUI_DEBUG_EVENTS_DIR)與 stdout 記下「P127 PASS」或「P127 FAIL (...)」:
//   1 視窗出現一秒後，要求讓被停用那一列裡的文字欄位取得焦點：必須被拒絕(binding 被寫回、欄位沒有焦點)
//   2 接著從程式讓「before」取得焦點:binding 必須是「before」
//   3 等待一次 Tab(由動作檔按下):焦點必須落在「after」,跨過被停用那一列的兩個停駐點
//   4 從原生 view 讀出焦點環:「after」必須有、「ring off」必須沒有(會從程式讓「ring off」取得焦點來看)
//   5 最後焦點在「after」,擷圖會顯示它的焦點環。P127-focus-effect-off.actions 會再按一次 Tab 到「ring off」,
//     它的擷圖顯示該色塊有焦點但沒有焦點環
// 40 秒內沒有 Tab 即為 FAIL。沒有實作 BackendFeatures.FocusEffects 或 FocusDisabledContainers 的 backend 會被點名判為失敗。
//
// Build this file as a standalone app target.

enum P127Stop: Hashable, CustomStringConvertible {
    case before
    case insideField
    case insidePanel
    case after
    case ringOff

    var description: String {
        switch self {
            case .before: "before"
            case .insideField: "inside field"
            case .insidePanel: "inside panel"
            case .after: "after"
            case .ringOff: "ring off"
        }
    }
}

enum P127 {
    static let title = "P127 Focus disabling and focus effects"

    /// Reads whether a panel draws a focus ring now, from its native view.
    /// 從原生 view 讀出某個色塊此刻是否畫出焦點環。
    @MainActor static var ringProbes: [String: @MainActor () -> Bool] = [:]

    static func log(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
        let path = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
                ?? FileManager.default.currentDirectoryPath
        ).appendingPathComponent("p127-debug-events.log")
        let data = Data("\(Date()) \(message)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: path) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: path)
        }
    }
}

@main
struct P127App: App {
    var body: some Scene {
        WindowGroup(P127.title) {
            P127View()
        }
        .defaultSize(width: 440, height: 600)
    }
}

extension SwiftCrossUI.View {
    /// Records how to read this panel's focus ring off its native view.
    /// 記下如何從這個色塊的原生 view 讀出焦點環。
    func p127RingProbe(_ name: String) -> some SwiftCrossUI.View {
        #if canImport(CGtk)
            // The class GtkBackend puts on a widget under .focusEffectDisabled, and
            // the ring area a .focusable() target draws its ring in (its last child).
            // GtkBackend 在 .focusEffectDisabled 之下的 widget 上加的 class,以及 .focusable() target 畫焦點環
            // 的那塊區域(它的最後一個子 widget)。
            return inspect(.afterUpdate) { (native: Gtk.Widget) in
                let pointer = native.widgetPointer
                P127.ringProbes[name] = {
                    let disabled = gtk_widget_has_css_class(pointer, "scui-no-focus-effect") != 0
                    let ringShown = gtk_widget_get_last_child(pointer).map {
                        gtk_widget_get_visible($0) != 0
                    } ?? false
                    return !disabled && ringShown
                }
            }
        #elseif os(Android)
            return inspect(.afterUpdate) { (native: AndroidKit.View) in
                P127.ringProbes[name] = { native.getDefaultFocusHighlightEnabled() }
            }
        #elseif canImport(UIKitBackend)
            // UIKitBackend draws a .focusable() target's ring as a 2-point border
            // layer, shown while it is first responder.
            // UIKitBackend 以 2 點寬的邊框 layer 畫 .focusable() target 的焦點環，成為 first responder 時顯示。
            return inspect(.afterUpdate) { (native: UIView) in
                P127.ringProbes[name] = { [weak native] in
                    native?.layer.sublayers?.contains {
                        $0.borderWidth == 2 && !$0.isHidden
                    } ?? false
                }
            }
        #elseif canImport(AppKitBackend)
            return inspect(.afterUpdate) { (native: NSView) in
                P127.ringProbes[name] = { [weak native] in
                    (native?.focusRingType ?? .none) != .none
                }
            }
        #else
            return self
        #endif
    }
}

struct P127View: SwiftCrossUI.View {
    @SwiftCrossUI.Environment(\.backend) var backend
    @FocusState var stop: P127Stop?
    @State var text = ""
    @State var phase = "starting"
    @State var verdict = "P127 waiting"
    @State var failures: [String] = []
    @State var awaitingTab = false
    @State var done = false

    func panel(_ name: String, _ color: SwiftCrossUI.Color) -> some SwiftCrossUI.View {
        ZStack {
            color
            Text(name)
        }
        .frame(width: 150, height: 40)
    }

    var body: some SwiftCrossUI.View {
        VStack(alignment: .leading, spacing: 14) {
            Text(P127.title)
            Text(verdict)
            Text("focus: \(stop.map(String.init(describing:)) ?? "none") -- \(phase)")

            panel("before", .blue)
                .focusable()
                .focused($stop, equals: .before)

            HStack(spacing: 12) {
                TextField("inside field", text: $text)
                    .focused($stop, equals: .insideField)
                    .frame(width: 140)
                panel("inside", .gray)
                    .focusable()
                    .focused($stop, equals: .insidePanel)
            }
            .padding(8)
            .focusDisabled()

            panel("after", .green)
                .focusable()
                .focused($stop, equals: .after)
                .p127RingProbe("after")

            panel("ring off", .orange)
                .focusable()
                .focused($stop, equals: .ringOff)
                .p127RingProbe("ring off")
                .focusEffectDisabled()

            Text("Tab from before must reach after; the grey row is .focusDisabled()")
            Text("after draws a ring; ring off (.focusEffectDisabled) does not")
        }
        .padding(16)
        .onChange(of: stop) {
            guard awaitingTab, let stop, stop != .before else { return }
            awaitingTab = false
            P127.log("P127 Tab from before landed on \(stop)")
            if stop != .after {
                failures.append("Tab from before went to \(stop), expected after")
            }
            after(0.6) { checkRings() }
        }
        .onAppear {
            P127.log("P127 started on \(type(of: backend))")
            if !(backend is any BackendFeatures.FocusEffects) {
                failures.append("\(type(of: backend)) has no BackendFeatures.FocusEffects")
            }
            if !(backend is any BackendFeatures.FocusDisabledContainers) {
                failures.append("\(type(of: backend)) has no BackendFeatures.FocusDisabledContainers")
            }
            after(1.0) { askInside() }
            after(40) {
                if !done { finish(extra: "no Tab arrived within 40 s") }
            }
        }
    }

    func after(_ seconds: Double, _ action: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            MainActor.assumeIsolated { action() }
        }
    }

    /// Step 1: a request into the disabled row must be refused.
    /// 步驟 1:對被停用那一列的要求必須被拒絕。
    func askInside() {
        phase = "asking for the field inside the disabled row"
        stop = .insideField
        after(0.6) {
            P127.log("P127 focus request into the disabled row: binding now \(stop.map(String.init(describing:)) ?? "none")")
            if stop == .insideField {
                failures.append("the field inside .focusDisabled took the focus from code")
            }
            askBefore()
        }
    }

    /// Step 2: focus from code. 步驟 2:從程式聚焦。
    func askBefore() {
        phase = "focusing before from code"
        stop = .before
        after(0.6) {
            P127.log("P127 focus request for before: binding now \(stop.map(String.init(describing:)) ?? "none")")
            if stop != .before {
                failures.append("focus from code did not reach before")
            }
            phase = "press Tab"
            awaitingTab = true
            P127.log("P127 waiting for Tab")
        }
    }

    /// Step 4: the rings, read off the native views.
    /// 步驟 4:從原生 view 讀出焦點環。
    func checkRings() {
        let afterRing = P127.ringProbes["after"]?()
        P127.log("P127 ring on after (focused, effect on): \(afterRing.map(String.init) ?? "not probed")")
        if afterRing != true {
            failures.append("after draws no focus ring (\(afterRing.map(String.init) ?? "not probed"))")
        }
        phase = "focusing ring off from code"
        stop = .ringOff
        after(0.6) {
            let offRing = P127.ringProbes["ring off"]?()
            P127.log("P127 ring on ring off (focused, effect disabled): \(offRing.map(String.init) ?? "not probed")")
            if stop != .ringOff {
                failures.append("ring off could not be focused from code")
            }
            if offRing != false {
                failures.append("ring off draws a focus ring (\(offRing.map(String.init) ?? "not probed"))")
            }
            stop = .after
            finish(extra: nil)
        }
    }

    func finish(extra: String?) {
        guard !done else { return }
        done = true
        var all = failures
        if let extra { all.append(extra) }
        let result = all.isEmpty ? "P127 PASS" : "P127 FAIL (\(all.joined(separator: "; ")))"
        P127.log(result)
        verdict = result
        phase = "done"
    }
}
