import DefaultBackend
import Foundation
import SwiftCrossUI

#if canImport(CGtk)
    import CGtk
    import GtkCHelpers
#endif
#if os(Windows)
    import WinSDK
#endif

// P118 Window icon: Scene.windowIcon(_:) (todo "Window icon API", 2026-11-15).
//
// Writes two 256x256 PNGs at launch -- a: blue with an orange centre, b: green
// with a white centre -- and steps the scene's icon a, b, none, a. A second
// after each step it reads the icon back FROM THE PLATFORM, not from the
// backend:
//   GTK      the window's icon-name, whether the icon theme finds it, and the
//            decoration-layout of its header bar (must lead with "icon")
//   Windows  WM_GETICON on the HWND (GTK and WinUI builds alike), drawn at
//            32x32 and its centre pixel compared with the icon's centre
// Each step logs "P118 icon <x>: match" or "MISMATCH (...)" to
// p118-debug-events.log (SCUI_DEBUG_EVENTS_DIR) and stdout. With
// P118_SEQUENCE=1 the steps run by themselves and the app exits 0 when every
// step matched, 1 otherwise; without it the buttons step by hand.
//
// P118 視窗圖示:Scene.windowIcon(_:)(todo「Window icon API」,2026-11-15)。啟動時寫出兩張 256x256 PNG——a:藍底橘色中心,
// b:綠底白色中心——並把 scene 的圖示依序切成 a、b、無、a。每一步一秒後**從平台**讀回圖示，而不是問 backend:GTK 讀視窗的
// icon-name、圖示主題找不找得到它、header bar 的 decoration-layout(必須以 "icon" 開頭);Windows 對 HWND 送 WM_GETICON
// (GTK 與 WinUI 建置皆然),以 32x32 畫出後比對中心像素與圖示中心的顏色。每一步在 p118-debug-events.log
// (SCUI_DEBUG_EVENTS_DIR)與 stdout 記下「P118 icon <x>: match」或「MISMATCH (...)」。設 P118_SEQUENCE=1 時自動執行，
// 每一步都相符則以 0 結束，否則 1;不設時用按鈕手動切換。
//
// Build this file as a standalone app target.

enum P118 {
    static let title = "P118 Window icon"

    /// (outer, centre) colours as RGB. / (外圍、中心)顏色,RGB。
    static let colours: [String: ((UInt8, UInt8, UInt8), (UInt8, UInt8, UInt8))] = [
        "a": ((0x1E, 0x5A, 0xA8), (0xF0, 0x8C, 0x1E)),
        "b": ((0x2E, 0x9E, 0x4A), (0xFF, 0xFF, 0xFF)),
    ]

    static let directory: URL = {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("scui-p118", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (key, colour) in colours {
            let png = P118PNG.make(size: 256, outer: colour.0, centre: colour.1)
            try? png.write(to: directory.appendingPathComponent("scui-p118-\(key).png"))
        }
        return directory
    }()

    static func url(for choice: String) -> URL? {
        colours[choice] == nil ? nil : directory.appendingPathComponent("scui-p118-\(choice).png")
    }

    static func log(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
        let path = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["SCUI_DEBUG_EVENTS_DIR"]
                ?? FileManager.default.currentDirectoryPath
        ).appendingPathComponent("p118-debug-events.log")
        let data = Data("\(Date()) \(message)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: path) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: path)
        }
    }

    static func hex(_ c: (UInt8, UInt8, UInt8)) -> String {
        String(format: "#%02X%02X%02X", c.0, c.1, c.2)
    }

    /// Reads the icon back from the platform and says whether it is `choice`.
    /// 從平台讀回圖示，判斷它是不是 `choice`。
    @MainActor
    static func check(_ choice: String) -> Bool {
        var problems: [String] = []
        let expected = colours[choice]
        #if canImport(CGtk)
            let gtk = gtkReadback()
            let expectedName = expected == nil ? nil : "scui-p118-\(choice)"
            log("readback gtk: name=\(gtk.name ?? "none") found=\(gtk.found) layout=\(gtk.layout ?? "none") x11-icon=\(gtk.x11)")
            if gtk.name != expectedName {
                problems.append("icon-name \(gtk.name ?? "none")")
            }
            if let expectedName, gtkIconSizeCount(expectedName) == 0 {
                problems.append("no theme sizes, so no platform icon")
            }
            if expectedName != nil && !gtk.found {
                problems.append("theme cannot find it")
            }
            let leadsWithIcon = gtk.layout?.hasPrefix("icon") ?? false
            if leadsWithIcon != (expectedName != nil) {
                problems.append("layout \(gtk.layout ?? "none")")
            }
            // -1 off X11. On X11 the window manager must hold the icon too.
            // X11 以外為 -1。X11 上視窗管理員也必須拿到圖示。
            if gtk.x11 >= 0 && (gtk.x11 > 0) != (expectedName != nil) {
                problems.append("_NET_WM_ICON length \(gtk.x11)")
            }
        #endif
        #if os(Windows)
            let centre = win32Centre()
            log("readback win32: centre=\(centre.map(hex) ?? "no icon")")
            if let expected {
                if centre == nil || !close(centre!, expected.1) {
                    problems.append("win32 centre is not the icon's")
                }
            } else if let centre, colours.values.contains(where: { close(centre, $0.1) }) {
                problems.append("win32 still shows a P118 icon")
            }
        #endif
        let verdict = problems.isEmpty ? "match" : "MISMATCH (\(problems.joined(separator: "; ")))"
        log("P118 icon \(expected == nil ? "none" : choice): \(verdict)")
        return problems.isEmpty
    }

    static func close(_ a: (UInt8, UInt8, UInt8), _ b: (UInt8, UInt8, UInt8)) -> Bool {
        abs(Int(a.0) - Int(b.0)) <= 8 && abs(Int(a.1) - Int(b.1)) <= 8 && abs(Int(a.2) - Int(b.2)) <= 8
    }

    #if canImport(CGtk)
        /// How many sizes the icon theme declares for `name`. GTK builds the
        /// icon it hands the platform (WM_SETICON, _NET_WM_ICON) from these,
        /// so zero means the taskbar gets no icon even when the titlebar has one.
        /// 圖示主題為 `name` 宣告的尺寸數。GTK 交給平台的圖示(WM_SETICON、_NET_WM_ICON)由這些尺寸建立，所以 0 表示
        /// 即使標題列有圖示，工作列也拿不到。
        @MainActor
        static func gtkIconSizeCount(_ name: String) -> Int {
            guard let display = gdk_display_get_default(), let theme = gtk_icon_theme_get_for_display(display),
                let sizes = gtk_icon_theme_get_icon_sizes(theme, name)
            else { return 0 }
            var count = 0
            while sizes[count] != 0 {
                count += 1
            }
            g_free(sizes)
            return count
        }

        @MainActor
        static func gtkReadback() -> (name: String?, found: Bool, layout: String?, x11: Int) {
            var result: (name: String?, found: Bool, layout: String?, x11: Int) = (nil, false, nil, -1)
            let toplevels = gtk_window_list_toplevels()
            var node = toplevels
            while let current = node {
                if let raw = current.pointee.data {
                    let window = raw.assumingMemoryBound(to: GtkWindow.self)
                    if let windowTitle = gtk_window_get_title(window), String(cString: windowTitle) == title {
                        result.name = gtk_window_get_icon_name(window).map { String(cString: $0) }
                        result.x11 = Int(scui_window_x11_icon_length(UnsafeMutablePointer<GtkWidget>(OpaquePointer(window))))
                        if let name = result.name, let display = gdk_display_get_default(),
                            let theme = gtk_icon_theme_get_for_display(display)
                        {
                            result.found = gtk_icon_theme_has_icon(theme, name) != 0
                        }
                        var child = gtk_widget_get_first_child(
                            UnsafeMutablePointer<GtkWidget>(OpaquePointer(window)))
                        while let widget = child {
                            if g_type_check_instance_is_a(
                                UnsafeMutablePointer(OpaquePointer(widget)), gtk_header_bar_get_type()) != 0
                            {
                                result.layout = gtk_header_bar_get_decoration_layout(OpaquePointer(widget))
                                    .map { String(cString: $0) }
                            }
                            child = gtk_widget_get_next_sibling(widget)
                        }
                    }
                }
                node = current.pointee.next
            }
            g_list_free(toplevels)
            return result
        }
    #endif

    #if os(Windows)
        /// Every top-level window of this process with P118's title. Not
        /// FindWindowW: it returns one window of that title from any process.
        /// 本行程中標題為 P118 的每個頂層視窗。不用 FindWindowW:它回傳任何行程中同標題的其中一個視窗。
        static func ownWindows() -> [HWND] {
            var found: [HWND] = []
            withUnsafeMutablePointer(to: &found) { pointer in
                _ = EnumWindows(
                    { hwnd, parameter in
                        guard let hwnd else { return true }
                        var pid: DWORD = 0
                        GetWindowThreadProcessId(hwnd, &pid)
                        var buffer = [WCHAR](repeating: 0, count: 256)
                        let count = Int(GetWindowTextW(hwnd, &buffer, 256))
                        if pid == GetCurrentProcessId(),
                            String(decoding: buffer[0..<count], as: UTF16.self) == P118.title
                        {
                            UnsafeMutablePointer<[HWND]>(bitPattern: Int(parameter))!.pointee.append(hwnd)
                        }
                        return true
                    }, LPARAM(Int(bitPattern: pointer)))
            }
            return found
        }

        /// The centre pixel of the big icon of one of those windows, drawn at
        /// 32x32, or nil when none has an icon.
        /// 那些視窗之一的大圖示以 32x32 畫出後的中心像素；都沒有圖示時為 nil。
        static func win32Centre() -> (UInt8, UInt8, UInt8)? {
            let windows = ownWindows()
            var icon: HICON?
            for hwnd in windows {
                let big = SendMessageW(hwnd, UINT(WM_GETICON), WPARAM(ICON_BIG), 0)
                let small = SendMessageW(hwnd, UINT(WM_GETICON), WPARAM(ICON_SMALL), 0)
                log("readback win32: window \(UInt(bitPattern: Int(bitPattern: hwnd))) WM_GETICON big=\(big != 0) small=\(small != 0)")
                if icon == nil, big != 0 {
                    icon = HICON(bitPattern: Int(big))
                }
            }
            if windows.isEmpty {
                log("readback win32: no window of this process titled \(title)")
            }
            guard let icon else { return nil }
            let screen = GetDC(nil)
            defer { ReleaseDC(nil, screen) }
            guard let dc = CreateCompatibleDC(screen), let bitmap = CreateCompatibleBitmap(screen, 32, 32) else {
                return nil
            }
            defer { DeleteDC(dc) }
            let old = SelectObject(dc, bitmap)
            defer {
                SelectObject(dc, old)
                DeleteObject(bitmap)
            }
            guard DrawIconEx(dc, 0, 0, icon, 32, 32, 0, nil, UINT(DI_NORMAL)) else { return nil }
            let colour = GetPixel(dc, 16, 16)
            return (UInt8(colour & 0xFF), UInt8(colour >> 8 & 0xFF), UInt8(colour >> 16 & 0xFF))
        }
    #endif
}

/// A minimal PNG writer: RGBA, no filter, zlib stored blocks.
/// 最小的 PNG 寫入器:RGBA、不濾波、zlib 未壓縮區塊。
enum P118PNG {
    static func make(size: Int, outer: (UInt8, UInt8, UInt8), centre: (UInt8, UInt8, UInt8)) -> Data {
        var raw: [UInt8] = []
        raw.reserveCapacity(size * (size * 4 + 1))
        for y in 0..<size {
            raw.append(0)
            for x in 0..<size {
                let inside = x >= size / 4 && x < size * 3 / 4 && y >= size / 4 && y < size * 3 / 4
                let c = inside ? centre : outer
                raw += [c.0, c.1, c.2, 255]
            }
        }
        var zlib: [UInt8] = [0x78, 0x01]
        var offset = 0
        repeat {
            let count = min(65535, raw.count - offset)
            let length = UInt16(count)
            zlib.append(offset + count >= raw.count ? 1 : 0)
            zlib += [UInt8(length & 0xFF), UInt8(length >> 8), UInt8(~length & 0xFF), UInt8(~length >> 8)]
            zlib += raw[offset..<offset + count]
            offset += count
        } while offset < raw.count
        var a: UInt32 = 1
        var b: UInt32 = 0
        for byte in raw {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        zlib += bigEndian(b << 16 | a)

        var png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        png += chunk("IHDR", bigEndian(UInt32(size)) + bigEndian(UInt32(size)) + [8, 6, 0, 0, 0])
        png += chunk("IDAT", zlib)
        png += chunk("IEND", [])
        return Data(png)
    }

    static func bigEndian(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }

    static func chunk(_ type: String, _ body: [UInt8]) -> [UInt8] {
        let typed = Array(type.utf8) + body
        return bigEndian(UInt32(body.count)) + typed + bigEndian(crc32(typed))
    }

    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
        }
        return ~crc
    }
}

@main
struct P118App: App {
    @State var choice = "a"

    var body: some Scene {
        WindowGroup(P118.title) {
            P118View(choice: $choice)
        }
        .windowIcon(P118.url(for: choice))
        .defaultSize(width: 520, height: 320)
    }
}

struct P118View: View {
    @Binding var choice: String
    @State var started = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("P118: Scene.windowIcon(_:) -- icon \(choice)")
            Text("a: blue, orange centre. b: green, white centre.")
            HStack(spacing: 8) {
                Button("Icon A") { step("a") }
                Button("Icon B") { step("b") }
                Button("No icon") { step("none") }
                Button("Read back") { _ = P118.check(choice) }
            }
        }
        .padding(16)
        .onAppear {
            guard !started else { return }
            started = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard ProcessInfo.processInfo.environment["P118_SEQUENCE"] == "1" else {
                    _ = P118.check(choice)
                    return
                }
                var failures = 0
                for next in ["a", "b", "none", "a"] {
                    choice = next
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if !P118.check(next) {
                        failures += 1
                    }
                }
                P118.log("P118 sequence: \(failures == 0 ? "all matched" : "\(failures) mismatched")")
                exit(failures == 0 ? 0 : 1)
            }
        }
    }

    func step(_ next: String) {
        choice = next
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            _ = P118.check(next)
        }
    }
}
