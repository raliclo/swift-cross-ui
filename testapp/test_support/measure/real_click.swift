// real_click X Y OWNER: one real left click (HID event tap) at screen point X,Y,
// only if the frontmost on-screen window under that point belongs to OWNER.
import CoreGraphics
import Foundation

let a = CommandLine.arguments
let x = Double(a[1])!, y = Double(a[2])!, owner = a[3]
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
var topOwner = "none"
for info in list {
    let layer = info[kCGWindowLayer as String] as? Int ?? 0
    guard layer == 0, let b = info[kCGWindowBounds as String] as? [String: Double] else { continue }
    let r = CGRect(x: b["X"]!, y: b["Y"]!, width: b["Width"]!, height: b["Height"]!)
    if r.contains(CGPoint(x: x, y: y)) {
        topOwner = info[kCGWindowOwnerName as String] as? String ?? "?"
        break
    }
}
guard topOwner == owner else {
    print("refused: the window under \(x),\(y) belongs to \(topOwner), not \(owner)")
    exit(1)
}
let p = CGPoint(x: x, y: y)
let src = CGEventSource(stateID: .hidSystemState)
CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
usleep(100_000)
CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
usleep(80_000)
CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
print("clicked \(x),\(y) on \(owner)")
