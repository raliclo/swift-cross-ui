import DefaultBackend
import Foundation
import SwiftCrossUI

#if canImport(CGtk)
    import CGtk
#endif
#if os(Android)
    import Android
    import AndroidBackend
    import AndroidKit
    import SwiftJava
#endif
#if canImport(UIKit)
    import UIKit
#endif
#if !canImport(CGtk) && canImport(UIKitBackend)
    import UIKitBackend
#elseif !canImport(CGtk) && canImport(AppKitBackend)
    import AppKit
    import AppKitBackend
#endif

// P119 Root widget teardown: a regression guard for 77be6665.
//
// GtkCustomRootWidget had no dispose, so it was freed with its child still
// attached. GTK printed "Finalizing GtkCustomRootWidget ..., but it still has
// children left" and the child kept a parent pointer into freed memory;
// SoftPCB-UI later died in gtk_widget_get_ancestor (2026-11-18).
//
// The app needs no input. It opens and closes a sheet, adds and removes a split
// view (two root widgets), and changes a picker's colour, which reloads a
// display-wide CSS provider. A GLib log writer counts the warning. The verdict
// goes to p119-debug-events.log (SCUI_DEBUG_EVENTS_DIR), stdout and the window.
// With P119_SEQUENCE=1, or the launch argument --sequence for iOS and Android, whose
// apps get no environment variables, the app exits 0 on PASS or SKIP and 1 on FAIL.
//
// The guard watches the warning, not the crash: the access violation depends on
// what reuses the freed memory, and it did not reproduce in 6 runs of the unfixed
// code, while the warning appeared on every removal of a split view.
//
// GTK counts the widget's warning. UIKit, AppKit and Android put a native probe in each sheet and split pane, and check that every backend container removed with it was released and holds no child (2026-11-19). WinUI reports SKIP until it has a probe.
//
// P119 Root widget 拆除：77be6665 的回歸防護。
//
// GtkCustomRootWidget 沒有 dispose，因此釋放時子元件仍掛在上面。GTK 印出「Finalizing GtkCustomRootWidget ...,
// but it still has children left」，子元件的 parent 指標指向已釋放的記憶體；SoftPCB-UI 後來在 gtk_widget_get_ancestor
// 當機(2026-11-18)。
//
// 這支 app 不需要任何輸入。它開關 sheet、加入並移除分割視圖(兩個 root widget)、改變 picker 的顏色(會重新載入 display
// 範圍的 CSS provider)，並以 GLib log writer 計算這則警告。結果寫到 p119-debug-events.log(SCUI_DEBUG_EVENTS_DIR)、
// stdout 與視窗。設 P119_SEQUENCE=1，或使用給 iOS 與 Android 的啟動參數 --sequence(它們的 app 收不到環境變數)時，
// PASS 或 SKIP 以 0 結束、FAIL 以 1 結束。
//
// 防護看的是警告而不是當機：存取違規取決於誰重複使用了那塊已釋放的記憶體，未修正的程式碼跑 6 次都沒有重現，而警告在每次移除
// 分割視圖時都會出現。
//
// GTK 計算這個 widget 的警告。UIKit、AppKit 與 Android 在每個 sheet 與分割視圖窗格放一個原生探針，檢查與它一起被移除的每個 backend 容器都已釋放、且沒有掛著子元件(2026-11-19)。WinUI 在有探針之前仍回報 SKIP。
//
// Build this file as a standalone app target.

enum P119 {
    static let title = "P119 Root widget teardown"
    static let cycles = 20
    /// The sheet toggles once per cycle, starting closed.
    /// sheet 每個循環切換一次，一開始是關閉的。
    static let sheetsOpened = (cycles + 1) / 2
    static let runsSequence =
        ProcessInfo.processInfo.environment["P119_SEQUENCE"] == "1" || CommandLine.arguments.contains("--sequence")

    #if canImport(UIKit)
        @MainActor static var sheetIsPresented: Bool {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .contains { $0.rootViewController?.presentedViewController != nil }
        }
    #endif

    static func log(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
        let path = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
                ?? FileManager.default.currentDirectoryPath
        ).appendingPathComponent("p119-debug-events.log")
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

#if canImport(CGtk)
    /// Counts GLib log messages on their way to the default writer.
    /// 在 GLib 訊息送往預設 writer 的途中計數。
    enum P119Log {
        static let probeText = "P119 log writer probe"
        nonisolated(unsafe) static var leftChildren = 0
        nonisolated(unsafe) static var probes = 0

        /// Installed before the backend starts, because GLib allows one writer per
        /// process and it has to see every teardown.
        /// 在 backend 啟動前安裝：GLib 每個行程只允許一個 writer，而它必須看到每一次拆除。
        static func install() {
            g_log_set_writer_func(
                { level, fields, count, data in
                    if let fields {
                        for index in 0..<Int(count) {
                            let field = fields[index]
                            guard let key = field.key, String(cString: key) == "MESSAGE",
                                let value = field.value
                            else { continue }
                            let text = String(cString: value.assumingMemoryBound(to: CChar.self))
                            if text.contains("GtkCustomRootWidget"), text.contains("still has children left") {
                                P119Log.leftChildren += 1
                            }
                            if text == P119Log.probeText {
                                P119Log.probes += 1
                            }
                        }
                    }
                    return g_log_writer_default(level, fields, count, data)
                },
                nil,
                nil
            )
        }

        /// Sends one message through GLib. If the writer never sees it, a count of
        /// zero warnings would mean nothing, so the run fails instead of passing.
        /// 經由 GLib 送出一則訊息。writer 若沒看到它，「零則警告」就毫無意義，因此這次執行判為失敗，而不是通過。
        static func sendProbe() {
            "MESSAGE".withCString { key in
                probeText.withCString { value in
                    var field = GLogField(key: key, value: UnsafeRawPointer(value), length: -1)
                    g_log_structured_array(GLogLevelFlags(rawValue: 1 << 5), &field, 1)
                }
            }
        }
    }
#endif

#if !canImport(CGtk) && (canImport(UIKitBackend) || canImport(AppKitBackend))
    #if canImport(UIKitBackend)
        typealias P119NativeView = UIView
    #else
        typealias P119NativeView = NSView
    #endif

    /// What GTK's "still has children left" stands for under ARC, where nothing is freed
    /// while referenced: a removed container that stays alive, and a child still attached
    /// to one. Each probe sits in a sheet or a split view pane; the backend containers
    /// above it are held weakly, and after the teardown none may be alive off screen.
    /// GTK 的「still has children left」在 ARC 下對應的失敗(ARC 不會釋放仍被引用的物件):被移除的容器仍活著，
    /// 以及子元件仍掛在這種容器上。每個探針放在 sheet 或分割視圖的窗格裡；它上方的 backend 容器以 weak 參照記下，
    /// 拆除之後不可以有任何一個在畫面外仍活著。
    @MainActor enum P119Teardown {
        @MainActor final class Entry {
            weak var object: AnyObject?
            let name: String

            init(_ object: AnyObject) {
                self.object = object
                name = String(describing: type(of: object))
            }
        }

        static var probes: [Entry] = []
        static var containers: [ObjectIdentifier: Entry] = [:]

        static var recorded: Int { containers.count }

        /// ARC frees on the last release; there is nothing to ask for.
        /// ARC 在最後一次 release 時就釋放，沒有東西需要要求。
        static func collect() {}

        /// Only the backend's own objects: UIKit and AppKit keep some of theirs for reuse.
        /// 只記 backend 自己的物件:UIKit 與 AppKit 會留下一些自己的物件以便重用。
        static func record(_ object: AnyObject) {
            let module = String(reflecting: type(of: object))
            guard module.hasPrefix("UIKitBackend.") || module.hasPrefix("AppKitBackend.") else { return }
            let id = ObjectIdentifier(object)
            if containers[id]?.object == nil {
                containers[id] = Entry(object)
            }
        }

        /// Records the containers above every probe that is on screen now.
        /// 記下目前在畫面上每個探針上方的容器。
        static func sample() {
            for probe in probes {
                var current = (probe.object as? P119NativeView)?.superview
                while let ancestor = current {
                    record(ancestor)
                    #if canImport(UIKitBackend)
                        if let controller = ancestor.next as? UIViewController {
                            record(controller)
                        }
                    #else
                        if let window = ancestor.window {
                            record(window)
                        }
                    #endif
                    current = ancestor.superview
                }
            }
        }

        static func onScreen(_ object: AnyObject) -> Bool {
            #if canImport(UIKitBackend)
                if let view = object as? UIView {
                    return view.window != nil
                }
                if let controller = object as? UIViewController {
                    return controller.viewIfLoaded?.window != nil
                }
            #else
                if let view = object as? NSView {
                    return view.window?.isVisible == true
                }
                if let window = object as? NSWindow {
                    return window.isVisible
                }
            #endif
            return false
        }

        /// Containers that left the screen and are still alive.
        /// 已離開畫面卻仍活著的容器。
        static var leaked: [String] {
            containers.values.compactMap { entry in
                guard let object = entry.object, !onScreen(object) else { return nil }
                return entry.name
            }
        }

        /// Probes that left the screen and are still attached to a container.
        /// 已離開畫面卻仍掛在容器上的探針。
        static var attached: Int {
            probes.filter { entry in
                guard let view = entry.object as? P119NativeView else { return false }
                return view.superview != nil && !onScreen(view)
            }.count
        }
    }

    #if canImport(UIKitBackend)
        struct P119Probe: UIViewRepresentable {
            func makeUIView(context: Context) -> UIView {
                let view = UIView()
                P119Teardown.probes.append(P119Teardown.Entry(view))
                return view
            }

            func updateUIView(_ uiView: UIView, context: Context) {}
        }
    #else
        struct P119Probe: NSViewRepresentable {
            func makeNSView(context: Context) -> NSView {
                let view = NSView()
                P119Teardown.probes.append(P119Teardown.Entry(view))
                return view
            }

            func updateNSView(_ nsView: NSView, context: Context) {}
        }
    #endif
#endif


#if os(Android)
    /// The same check for Android, where the garbage collector frees what nothing
    /// references. Weak global references stand in for Swift's weak: after a collection
    /// a removed backend container may be neither alive nor holding a probe.
    /// Android 上的同一項檢查：垃圾回收器釋放沒有被引用的物件。以 weak global reference 代替 Swift 的 weak:
    /// 回收之後，被移除的 backend 容器既不可以仍活著，也不可以仍掛著探針。
    @MainActor enum P119Teardown {
        final class Entry {
            let reference: jweak
            let name: String

            init(reference: jweak, name: String) {
                self.reference = reference
                self.name = name
            }
        }

        static var environment: JNIEnvironment?
        static var probes: [Entry] = []
        static var containers: [Int32: [Entry]] = [:]

        static var recorded: Int {
            containers.values.reduce(0) { $0 + $1.count }
        }

        static func weakEntry(_ view: AndroidKit.View, name: String) -> Entry? {
            guard let environment else { return nil }
            guard let reference = environment.interface.NewWeakGlobalRef(environment, view.javaThis) else { return nil }
            return Entry(reference: reference, name: name)
        }

        /// The object, or nil once it has been collected.
        /// 物件本身；被回收之後為 nil。
        static func view(_ entry: Entry) -> AndroidKit.View? {
            guard let environment,
                let local = environment.interface.NewLocalRef(environment, entry.reference)
            else { return nil }
            defer { environment.interface.DeleteLocalRef(environment, local) }
            return AndroidKit.View(javaThis: local, environment: environment)
        }

        /// Only the backend's own classes: the framework keeps some of its views.
        /// 只記 backend 自己的類別：框架會留下一些它自己的 view。
        static func record(_ view: AndroidKit.View) {
            guard let environment else { return }
            let name = view.getClass().getName()
            guard name.hasPrefix("dev.swiftcrossui.") else { return }
            let hash = view.hashCode()
            for entry in containers[hash] ?? [] {
                if environment.interface.IsSameObject(environment, entry.reference, view.javaThis) != 0 {
                    return
                }
            }
            if let entry = weakEntry(view, name: String(name.split(separator: ".").last ?? "")) {
                containers[hash, default: []].append(entry)
            }
        }

        static func sample() {
            for probe in probes {
                guard let view = view(probe) else { continue }
                var parent = view.getParent()?.as(AndroidKit.View.self)
                while let ancestor = parent {
                    record(ancestor)
                    parent = ancestor.getParent()?.as(AndroidKit.View.self)
                }
            }
        }

        /// Asks for a collection, so that what is unreferenced is gone before the count.
        /// 要求一次回收，讓沒有被引用的物件在計數前消失。
        static func collect() {
            guard let environment,
                let system = environment.interface.FindClass(environment, "java/lang/System")
            else { return }
            defer { environment.interface.DeleteLocalRef(environment, system) }
            for method in ["gc", "runFinalization"] {
                if let id = environment.interface.GetStaticMethodID(environment, system, method, "()V") {
                    environment.interface.CallStaticVoidMethodA(environment, system, id, nil)
                }
            }
        }

        static var leaked: [String] {
            containers.values.flatMap { $0 }.compactMap { entry in
                guard let view = view(entry), !view.isAttachedToWindow() else { return nil }
                return entry.name
            }
        }

        static var attached: Int {
            probes.filter { entry in
                guard let view = view(entry) else { return false }
                return view.getParent() != nil && !view.isAttachedToWindow()
            }.count
        }
    }

    struct P119Probe: AndroidViewRepresentable {
        func makeAndroidView(context: Self.Context) -> AndroidKit.View {
            P119Teardown.environment = context.environment.jniEnv
            let view = AndroidKit.View(context.environment.androidActivity, environment: context.environment.jniEnv)
            if let entry = P119Teardown.weakEntry(view, name: "P119Probe") {
                P119Teardown.probes.append(entry)
            }
            return view
        }

        func updateAndroidView(_ view: AndroidKit.View, context: Self.Context) {}
    }
#endif
@main
struct P119App: App {
    init() {
        #if canImport(CGtk)
            P119Log.install()
        #endif
    }

    var body: some Scene {
        WindowGroup(P119.title) {
            P119View()
        }
        .defaultSize(width: 520, height: 420)
    }
}

/// A probe on the backends that have one, nothing elsewhere.
/// 有探針的 backend 放一個探針，其餘什麼都不放。
struct P119ProbeSlot: SwiftCrossUI.View {
    @ViewBuilder var body: some SwiftCrossUI.View {
        #if !canImport(CGtk) && (canImport(UIKitBackend) || canImport(AppKitBackend) || os(Android))
            P119Probe().frame(width: 1, height: 1)
        #else
            EmptyView()
        #endif
    }
}

struct P119View: SwiftCrossUI.View {
    @State var cycle = 0
    @State var sheetShown = false
    @State var splitShown = true
    @State var selection: String? = "a"
    @State var verdict = "running"
    @State var sheetsClosed = 0

    var body: some SwiftCrossUI.View {
        VStack(spacing: 8) {
            Text(P119.title)
            Text("Cycle \(cycle) of \(P119.cycles): \(verdict)")
            Picker(of: ["a", "b"], selection: $selection)
                .foregroundColor(cycle % 2 == 0 ? Color.red : Color.blue)
            if splitShown {
                NavigationSplitView {
                    VStack { Text("Sidebar \(cycle)"); P119ProbeSlot() }
                } detail: {
                    VStack { Text("Detail \(cycle)"); P119ProbeSlot() }
                }
                .frame(height: 160)
            }
        }
        .padding(16)
        .sheet(isPresented: $sheetShown, onDismiss: { sheetsClosed += 1 }) {
            VStack { Text("Sheet \(cycle)"); P119ProbeSlot() }
                .padding(40)
        }
        .task {
            await run()
        }
    }

    @MainActor func sampleTeardown() {
        #if !canImport(CGtk) && (canImport(UIKitBackend) || canImport(AppKitBackend) || os(Android))
            P119Teardown.sample()
        #endif
    }

    @MainActor func run() async {
        for step in 1...P119.cycles {
            try? await Task.sleep(nanoseconds: 150_000_000)
            sheetShown.toggle()
            try? await Task.sleep(nanoseconds: 150_000_000)
            sampleTeardown()
            splitShown.toggle()
            try? await Task.sleep(nanoseconds: 150_000_000)
            sampleTeardown()
            cycle = step
        }

        // A root is freed after the update that removed it, so let the last ones go.
        // root 在移除它的那次更新之後才釋放，所以等最後幾個釋放完。
        sheetShown = false
        splitShown = false
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        // Every sheet opened has to be closed by now. On iOS a sheet closed during its
        // transition used to stay up, stacked under the next one (9798d0f8, 2026-11-19).
        // 開過的每一張 sheet 此時都必須已關閉。iOS 上在轉場中關閉的 sheet 曾經留在畫面上，疊在下一張底下(9798d0f8，2026-11-19)。
        for _ in 0..<100 where sheetsClosed < P119.sheetsOpened {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        var sheetsGone = sheetsClosed == P119.sheetsOpened
        #if canImport(UIKit)
            sheetsGone = sheetsGone && !P119.sheetIsPresented
        #endif
        if !sheetsGone {
            P119.log("P119 FAIL: \(P119.sheetsOpened) sheets opened, \(sheetsClosed) closed, one is left on screen")
        }

        var passed = sheetsGone
        #if canImport(CGtk)
            P119Log.sendProbe()
            let warnings = P119Log.leftChildren
            passed = passed && warnings == 0 && P119Log.probes == 1
            verdict = passed ? "PASS" : "FAIL"
            P119.log(
                "P119 \(verdict): \(warnings) root widgets freed with children left, "
                    + "log writer probes seen \(P119Log.probes) of 1, cycles \(cycle)"
            )
        #elseif canImport(UIKitBackend) || canImport(AppKitBackend) || os(Android)
            // Releasing can wait for a transition or the next turn of the run loop.
            // 釋放可能要等轉場結束，或等下一輪 run loop。
            for _ in 0..<50 where !P119Teardown.leaked.isEmpty || P119Teardown.attached > 0 {
                P119Teardown.collect()
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            let leaked = P119Teardown.leaked
            let attached = P119Teardown.attached
            let recorded = P119Teardown.recorded
            passed = passed && recorded > 0 && leaked.isEmpty && attached == 0
            verdict = passed ? "PASS" : "FAIL"
            P119.log(
                "P119 \(verdict): \(recorded) backend containers recorded, \(leaked.count) still alive off screen, "
                    + "\(attached) probes still attached, cycles \(cycle)"
                    + (leaked.isEmpty ? "" : " (\(Dictionary(grouping: leaked, by: { $0 }).map { "\($0.key) \($0.value.count)" }.sorted().joined(separator: ", ")))")
            )
        #else
            verdict = passed ? "SKIP" : "FAIL"
            if passed { P119.log("P119 SKIP: this backend has no GtkCustomRootWidget, cycles \(cycle)") }
        #endif

        // One line for PASS and SKIP alike: testapp/actions/win and actions/mac are
        // replayed by more than one backend, and `# expect:` takes a single text.
        // PASS 與 SKIP 共用一行:testapp/actions/win 與 actions/mac 會由不只一個 backend 重放，而 `# expect:` 只能寫一段文字。
        if passed {
            P119.log("P119 finished without a failure")
        }

        if P119.runsSequence {
            #if os(Android)
                // exit() runs the static destructors while the HWUI render threads are
                // still using them: SIGABRT, "pthread_mutex_lock called on a destroyed
                // mutex", on every run (2026-11-19). _exit() skips them. stdout reaches
                // logcat through a pipe another thread reads, so give the verdict time.
                // exit() 會執行靜態解構，而 HWUI 繪圖執行緒還在使用它們：每次都 SIGABRT,
                //「pthread_mutex_lock called on a destroyed mutex」(2026-11-19)。_exit() 不執行解構。
                // stdout 經由另一條執行緒讀取的 pipe 才到 logcat，所以留時間讓判定送達。
                try? await Task.sleep(nanoseconds: 500_000_000)
                _exit(passed ? 0 : 1)
            #else
                exit(passed ? 0 : 1)
            #endif
        }
    }
}
