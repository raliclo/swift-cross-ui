import AppKit
// 在指定的螢幕座標上做一次真正的滑鼠拖曳。
let sx = Double(CommandLine.arguments[1])!, sy = Double(CommandLine.arguments[2])!
let ex = Double(CommandLine.arguments[3])!, ey = Double(CommandLine.arguments[4])!
func post(_ type: CGEventType, _ at: CGPoint) {
    let e = CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState),
                    mouseType: type, mouseCursorPosition: at, mouseButton: .left)!
    e.post(tap: .cghidEventTap)
    usleep(30_000)
}
let start = CGPoint(x: sx, y: sy), end = CGPoint(x: ex, y: ey)
post(.mouseMoved, start)
post(.leftMouseDown, start)
for step in 1...8 {
    let t = Double(step) / 8
    post(.leftMouseDragged, CGPoint(x: sx + (ex - sx) * t, y: sy + (ey - sy) * t))
}
post(.leftMouseUp, end)
print("dragged \(Int(sx)),\(Int(sy)) -> \(Int(ex)),\(Int(ey))")
