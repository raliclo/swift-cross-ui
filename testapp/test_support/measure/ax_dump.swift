import AppKit
import ApplicationServices
let appPath = CommandLine.arguments[1]
func attr(_ e: AXUIElement, _ k: String) -> CFTypeRef? {
    var v: CFTypeRef?; return AXUIElementCopyAttributeValue(e, k as CFString, &v) == .success ? v : nil
}
func kids(_ e: AXUIElement) -> [AXUIElement] { (attr(e, kAXChildrenAttribute as String) as? [AXUIElement]) ?? [] }
let p = Process(); p.executableURL = URL(fileURLWithPath: appPath); p.arguments = ["--debug"]
try p.run(); sleep(3)
let app = AXUIElementCreateApplication(p.processIdentifier)
var n = 0
func walk(_ e: AXUIElement, _ d: Int) {
    if d > 8 || n > 40 { return }
    let role = (attr(e, kAXRoleAttribute as String) as? String) ?? "?"
    if role == kAXButtonRole as String {
        n += 1
        let t = (attr(e, kAXTitleAttribute as String) as? String) ?? ""
        let desc = (attr(e, kAXDescriptionAttribute as String) as? String) ?? ""
        print("  AXButton title='\(t)' desc='\(desc)'")
    }
    for c in kids(e) { walk(c, d + 1) }
}
for w in kids(app) where (attr(w, kAXRoleAttribute as String) as? String) == kAXWindowRole as String {
    print("window: \((attr(w, kAXTitleAttribute as String) as? String) ?? "")")
    walk(w, 0)
}
p.terminate()
