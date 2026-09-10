import AppKit
import ApplicationServices
import Foundation

// P28 的兩條未量路徑：真實滑鼠事件走完整的事件佇列，以及「啟動後的第一次點擊、未預熱」。
// 兩端都用 ProcessInfo.systemUptime，那是機器層級的時鐘，因此不需要對齊任何東西。

let logPath = CommandLine.arguments[1]
let appPath = CommandLine.arguments[2]

func attr(_ e: AXUIElement, _ k: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(e, k as CFString, &v) == .success ? v : nil
}
func children(_ e: AXUIElement) -> [AXUIElement] {
    (attr(e, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
}
/// 找那顆按鈕，靠的是「它後面緊接著它的標籤」，而不是靠它的 AX title。
///
/// SwiftCrossUI 在 AppKit 上把 Button 的文字做成一個**獨立的** AXStaticText，
/// 於是那顆 AXButton 的 title 與 description 都是空的。2026-09-10 的 AX 樹傾印如此顯示，
/// 而 `AppKitBackend+Button.swift:130` 的註解說它會自動採用標籤文字。
func findButton(_ e: AXUIElement, depth: Int = 0) -> AXUIElement? {
    if depth > 12 { return nil }
    let kids = children(e)
    for (i, c) in kids.enumerated() {
        let role = attr(c, kAXRoleAttribute as String) as? String
        if role == kAXButtonRole as String, i + 1 < kids.count,
            let next = attr(kids[i + 1], kAXValueAttribute as String) as? String,
            next.contains("Clickable button")
        {
            return c
        }
    }
    for c in kids { if let f = findButton(c, depth: depth + 1) { return f } }
    return nil
}

try? FileManager.default.removeItem(atPath: logPath)
let p = Process()
p.executableURL = URL(fileURLWithPath: appPath)
p.arguments = ["--debug"]
var env = ProcessInfo.processInfo.environment
env["SCUI_DEBUG_EVENTS_DIR"] = (logPath as NSString).deletingLastPathComponent
p.environment = env
try p.run()

// 等視窗出現（而不是等一個固定秒數）
let axApp = AXUIElementCreateApplication(p.processIdentifier)
var button: AXUIElement?
let deadline = Date().addingTimeInterval(20)
while Date() < deadline, button == nil {
    usleep(100_000)
    for w in children(axApp) { if let b = findButton(w) { button = b; break } }
}
if button == nil {
    print("NO BUTTON FOUND -- dumping the AX tree")
    func dump(_ e: AXUIElement, _ d: Int) {
        if d > 6 { return }
        let role = (attr(e, kAXRoleAttribute as String) as? String) ?? "?"
        let title = (attr(e, kAXTitleAttribute as String) as? String) ?? ""
        let desc = (attr(e, kAXDescriptionAttribute as String) as? String) ?? ""
        let value = (attr(e, kAXValueAttribute as String) as? String) ?? ""
        print(String(repeating: "  ", count: d) + role + "  title=\'" + title + "\' desc=\'" + desc + "\' value=\'" + value.prefix(30) + "\'")
        for c in children(e) { dump(c, d + 1) }
    }
    dump(axApp, 0)
    print("windows attr:", (attr(axApp, kAXWindowsAttribute as String) as? [AXUIElement])?.count ?? -1)
    p.terminate(); exit(1)
}
let btn = button!

var posV = attr(btn, kAXPositionAttribute as String)!
var sizeV = attr(btn, kAXSizeAttribute as String)!
var pos = CGPoint.zero, size = CGSize.zero
AXValueGetValue(posV as! AXValue, .cgPoint, &pos)
AXValueGetValue(sizeV as! AXValue, .cgSize, &size)
let target = CGPoint(x: pos.x + size.width / 2, y: pos.y + size.height / 2)  // AX 已是左上原點

// 讓 P28 成為前景視窗，否則真的點擊會落到別的 app 上
NSRunningApplication(processIdentifier: p.processIdentifier)?.activate(options: [.activateAllWindows])
usleep(400_000)

func readClickUptimes() -> [Double] {
    guard let s = try? String(contentsOfFile: logPath, encoding: .utf8) else { return [] }
    return s.split(separator: "\n").compactMap { line in
        guard let r = line.range(of: "click at uptime ") else { return nil }
        return Double(line[r.upperBound...].prefix(while: { $0.isNumber || $0 == "." }))
    }
}

func click(_ label: String) {
    let before = readClickUptimes().count
    let t0 = ProcessInfo.processInfo.systemUptime
    for type in [CGEventType.leftMouseDown, .leftMouseUp] {
        let e = CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState),
                        mouseType: type, mouseCursorPosition: target, mouseButton: .left)!
        e.post(tap: .cghidEventTap)
    }
    let waitUntil = Date().addingTimeInterval(3)
    var got: Double?
    while Date() < waitUntil {
        let u = readClickUptimes()
        if u.count > before { got = u.last; break }
        usleep(2000)
    }
    if let got {
        print(String(format: "%-28s real mouse -> body  %6.1f ms", (label as NSString).utf8String!, (got - t0) * 1000))
    } else {
        print("\(label): the click did NOT arrive within 3 s")
    }
}

click("first click, no warm-up")
for i in 1...5 { usleep(500_000); click("warmed click \(i)") }
p.terminate()
