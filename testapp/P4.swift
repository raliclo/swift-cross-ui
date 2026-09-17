import DefaultBackend
import Foundation
import SwiftCrossUI

#if canImport(WinUIBackend)
    import UWP
    import WinUI
    import WinUIBackend
#endif

#if canImport(GtkBackend)
    import Gtk
    import GtkBackend
#endif

// P4 Windows exploration app:
// - #190 Store callbacks in subclasses instead of global hashmaps.
// - #156 Needs for WinUI / WinUI-specific escape hatches.
// - #204 Update to latest stable WinUI.
// - #470 Regenerate WinUI bindings with latest swift-winrt.
//
// Build this file as a standalone app target.

@main
@HotReloadable
struct P4WinUISpecificAndStressApp: App {
    @State var rowCount = 80
    @State var updateTick = 0

    var body: some Scene {
        WindowGroup("P4 WinUI native and callback stress") {
            #hotReloadable {
                P4WinUISpecificAndStressView(rowCount: $rowCount, updateTick: $updateTick)
            }
        }
        .defaultSize(width: 840, height: 760)
    }
}

struct P4WinUISpecificAndStressView: View {
    @SwiftCrossUI.Binding var rowCount: Int
    @SwiftCrossUI.Binding var updateTick: Int

    @State var selectedRow: Int? = nil
    @State var callbackCount = 0
    @State var text = "Native WinUI inspection should be visible on Windows."
    @State var windowStart = 0

    var batchSize: Int { 25 }
    var windowSize: Int { 50 }
    var windowEnd: Int { min(rowCount, windowStart + windowSize) }

    /// `--inspect-containers`: drive the `.inspect` overloads of `List` and
    /// `NavigationSplitView`.
    ///
    /// Queue M8 repaired the overloads that cast a view's widget straight to the
    /// control it names, after `TextField(...).inspect` trapped at launch on
    /// three backends. These two were left as they were on both Windows
    /// backends, and nothing here had ever run them: GtkBackend still reaches
    /// for `scrolled.getChild() as! Gtk.ListBox` and `fixed.children[0] as!
    /// Gtk.Paned`, which is the same shape that trapped. Opt-in, because P4's
    /// action files are measured against its current layout.
    ///
    /// `--inspect-containers`:驅動 `List` 與 `NavigationSplitView` 的 `.inspect` overload。
    ///
    /// queue M8 修好的是那些「把 view 的 widget 直接轉型成它所命名之控制項」的 overload——起因是
    /// `TextField(...).inspect` 在三個 backend 上一啟動就 trap。這兩個在兩個 Windows backend 上都維持原樣,
    /// 而且從來沒有任何東西跑過它們:GtkBackend 至今仍是 `scrolled.getChild() as! Gtk.ListBox` 與
    /// `fixed.children[0] as! Gtk.Paned`,正是當初 trap 的那個形狀。做成 opt-in,因為 P4 的動作檔是依現行版面量的。
    static let inspectsContainers = CommandLine.arguments.contains("--inspect-containers")
    @State var listSelection: String? = nil

    static func report(_ message: String) {
        FileHandle.standardError.write(Data("P4 inspect: \(message)\n".utf8))
    }

    var body: some View {
        VStack(spacing: 14) {
            if Self.inspectsContainers {
                List(["row A", "row B"], id: \.self, selection: $listSelection) { value in
                    Text(value)
                }
                // `.inspect` FIRST, and the closure's parameter type written out.
                // Both matter, and both were measured on 2026-09-18.
                // `List.inspect` is declared on `List`, so after `.frame(...)`
                // the receiver is a modifier and only the generic
                // `View.inspect` applies: with the frame first, an un-annotated
                // closure reported `Canvas` three times, and the same code with
                // the type written out did not compile
                // ("cannot convert value of type '@Sendable (ListView) -> ()'").
                // 兩件事都重要,而且都是 2026-09-18 量到的:`.inspect` 要在前面,閉包參數型別要寫出來。
                // `List.inspect` 宣告在 `List` 上,因此接在 `.frame(...)` 之後時接收者已是 modifier、只剩通用的
                // `View.inspect` 適用:frame 在前時,未標註型別的閉包回報了三次 `Canvas`,而把型別寫出來的同一段
                // 程式碼則編不過(「cannot convert value of type '@Sendable (ListView) -> ()'」)。
                #if canImport(WinUIBackend)
                    .inspect(.afterUpdate) { (native: WinUI.ListView) in
                        Self.report("List -> \(type(of: native))")
                    }
                    .frame(width: 220, height: 70)
                #elseif canImport(GtkBackend)
                    // `Gtk.ListView` since #117 made a List one; the overload
                    // still said `Gtk.ListBox` and trapped when this first ran it.
                    // 自 #117 起 List 就是 `Gtk.ListView`;那個 overload 仍寫著 `Gtk.ListBox`,於是在這裡第一次
                    // 真的執行到它時就 trap 了。
                    .inspect(.afterUpdate) { (native: Gtk.ListView) in
                        Self.report("List -> \(type(of: native))")
                    }
                    .frame(width: 220, height: 70)
                #else
                    .frame(width: 220, height: 70)
                #endif

                NavigationSplitView {
                    Text("sidebar")
                } detail: {
                    Text("detail")
                }
                #if canImport(WinUIBackend)
                    .inspect(.afterUpdate) { (native: WinUI.SplitView) in
                        Self.report("NavigationSplitView -> \(type(of: native))")
                    }
                    .frame(width: 320, height: 90)
                #elseif canImport(GtkBackend)
                    .inspect(.afterUpdate) { (native: Gtk.Paned) in
                        Self.report("NavigationSplitView -> \(type(of: native))")
                    }
                    .frame(width: 320, height: 90)
                #else
                    .frame(width: 320, height: 90)
                #endif
            }

            Text("P4: WinUI-specific APIs and callback stress")
                .font(.system(size: 18))

            HStack {
                Button("Fewer rows") {
                    rowCount = max(10, rowCount - 25)
                    windowStart = min(windowStart, max(0, rowCount - windowSize))
                    updateTick += 1
                }

                Button("More rows") {
                    rowCount += 25
                    updateTick += 1
                }

                Button("Force update") {
                    updateTick += 1
                }

                Button("Run last") {
                    selectedRow = max(0, rowCount - 1)
                    callbackCount += 1
                    windowStart = max(0, rowCount - windowSize)
                }

                Button("Rows 250") {
                    rowCount = 250
                    windowStart = min(windowStart, max(0, 250 - windowSize))
                    updateTick += 1
                }
            }

            Text(
                "Rows: \(rowCount), rows \(windowStart)-\(max(windowStart, windowEnd - 1)), update tick: \(updateTick), callbacks: \(callbackCount)"
            )

            #if canImport(WinUIBackend)
                P4NativeWinUIBanner(text: text, tick: updateTick)
                    .frame(height: 60)
            #else
                Text("WinUI native banner only appears when WinUIBackend is available.")
                    .frame(height: 60)
            #endif

            TextField("Native inspection text", text: $text)
                .inspect(.afterUpdate) { textField in
                    #if canImport(WinUIBackend)
                        let brush = WinUI.SolidColorBrush()
                        brush.color = UWP.Color(a: 255, r: 20, g: 70, b: 120)
                        textField.borderBrush = brush
                    #endif
                }

            HStack {
                Button("Load next rows") {
                    windowStart = min(max(0, rowCount - windowSize), windowStart + batchSize)
                }

                Text("Scrolling near the bottom or top slides the row window on Windows.")
            }

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(Array(windowStart..<windowEnd), id: \.self) { row in
                        HStack {
                            Button("Run \(row)") {
                                selectedRow = row
                                callbackCount += 1
                            }

                            Text("Callback row \(row)")

                            Spacer()
                        }
                        .padding(4)
                    }
                }
                .padding(8)
            }
            #if canImport(WinUIBackend)
                .inspect(.afterUpdate) { scrollViewer in
                    hookScrollAutoLoad(scrollViewer)
                }
            #endif
            .frame(height: 340)

            Text("Selected row: \(selectedRow.map(String.init) ?? "none")")
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(
                "Expected: banner updates with tick/text, scrolling slides the row window, and row callbacks respond quickly even when row count is large."
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .inspectWindow { window in
            #if canImport(WinUIBackend)
                window.appWindow.titleBar.backgroundColor = UWP.Color(
                    a: 255,
                    r: 30,
                    g: 90,
                    b: 120
                )
            #endif
        }
    }

    #if canImport(WinUIBackend)
        // Hooks viewChanged once per ScrollViewer: scrolling near the bottom or
        // top slides the row window, and changeView compensates the scroll
        // offset so the content stays visually continuous.
        func hookScrollAutoLoad(_ scrollViewer: WinUI.ScrollViewer) {
            let identifier = ObjectIdentifier(scrollViewer)
            P4ScrollAutoLoad.hookedScrollViewers = P4ScrollAutoLoad.hookedScrollViewers
                .filter { $0.value.scrollViewer != nil }

            guard P4ScrollAutoLoad.hookedScrollViewers[identifier] == nil else {
                return
            }
            P4ScrollAutoLoad.hookedScrollViewers[identifier] = P4WeakScrollViewer(scrollViewer)

            scrollViewer.viewChanged.addHandler { [weak scrollViewer] _, _ in
                guard let scrollViewer else { return }
                let offset = scrollViewer.verticalOffset
                let viewport = scrollViewer.viewportHeight
                let extent = scrollViewer.extentHeight
                let renderedCount = windowEnd - windowStart
                guard renderedCount > 0, extent > 0 else { return }

                // Rows have uniform height, so estimate it from the total
                // extent and use it to compensate the scroll offset by the
                // amount the window slides.
                let rowHeight = extent / Double(renderedCount)
                let remainingBelow = extent - (offset + viewport)

                if remainingBelow < 60, windowEnd < rowCount {
                    let advance = min(batchSize, rowCount - windowEnd)
                    windowStart += advance
                    _ = try? scrollViewer.changeView(
                        nil,
                        max(0, offset - Double(advance) * rowHeight),
                        nil,
                        true
                    )
                } else if offset < 60, windowStart > 0 {
                    let retreat = min(batchSize, windowStart)
                    windowStart -= retreat
                    _ = try? scrollViewer.changeView(
                        nil,
                        offset + Double(retreat) * rowHeight,
                        nil,
                        true
                    )
                }
            }
        }
    #endif
}

#if canImport(WinUIBackend)
    final class P4WeakScrollViewer {
        weak var scrollViewer: WinUI.ScrollViewer?

        init(_ scrollViewer: WinUI.ScrollViewer) {
            self.scrollViewer = scrollViewer
        }
    }

    enum P4ScrollAutoLoad {
        nonisolated(unsafe) static var hookedScrollViewers: [ObjectIdentifier: P4WeakScrollViewer] = [:]
    }
#endif

#if canImport(WinUIBackend)
    struct P4NativeWinUIBanner: WinUIElementRepresentable {
        var text: String
        var tick: Int

        func makeWinUIElement(context: Context) -> WinUI.Border {
            let border = WinUI.Border()
            border.cornerRadius = .init(topLeft: 6, topRight: 6, bottomRight: 6, bottomLeft: 6)
            border.padding = .init(left: 12, top: 8, right: 12, bottom: 8)
            return border
        }

        func updateWinUIElement(_ border: WinUI.Border, context: Context) {
            let block = WinUI.TextBlock()
            block.text = "\(text) Tick \(tick)"
            block.textWrapping = .wrap

            let foreground = WinUI.SolidColorBrush()
            foreground.color = UWP.Color(a: 255, r: 10, g: 35, b: 65)
            block.foreground = foreground

            let background = WinUI.SolidColorBrush()
            background.color = UWP.Color(a: 255, r: 230, g: 242, b: 255)
            border.background = background

            let borderBrush = WinUI.SolidColorBrush()
            borderBrush.color = UWP.Color(a: 255, r: 45, g: 95, b: 150)
            border.borderBrush = borderBrush
            border.borderThickness = .init(left: 1, top: 1, right: 1, bottom: 1)
            border.child = block
        }
    }
#endif
