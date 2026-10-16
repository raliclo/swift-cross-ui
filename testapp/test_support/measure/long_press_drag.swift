import AppKit

// A real long-press drag on macOS: a left-button press through the HID event
// tap, held still, then dragged in steps and released -- what P102's
// longPressTextSelection() is driven with.
//
//   long_press_drag <window-owner> <x0> <y0> <x1> <y1> [hold-seconds] [title-bar]
//
// x/y are points in the window's CONTENT, top-left origin (the window is found
// by owner name in CGWindowList; title-bar defaults to 28, macOS's standard
// title bar). hold defaults to 0.8 s, past the 0.5 s long-press delay; pass 0.1
// for the control, an ordinary drag. Needs Accessibility permission for the
// terminal: without it CGEvent.post delivers nothing and says nothing
// (measure/README.md, real_mouse_latency.swift).
//
// 在 macOS 上做一次真正的長按拖曳：經由 HID event tap 按下左鍵、靜止按住、分步拖曳後放開——P102 的
// longPressTextSelection() 就是用它驅動的。x/y 是視窗**內容**中的點，左上為原點(以 owner 名稱在
// CGWindowList 找視窗;標題列預設 28 點)。按住時間預設 0.8 秒，超過 0.5 秒的長按延遲;傳 0.1 就是對照組
// ——一次普通拖曳。終端機需要輔助使用權限：沒有它,CGEvent.post 什麼都送不出去也不說。

let arguments = CommandLine.arguments
guard arguments.count >= 6,
    let x0 = Double(arguments[2]), let y0 = Double(arguments[3]),
    let x1 = Double(arguments[4]), let y1 = Double(arguments[5])
else {
    print("usage: long_press_drag <window-owner> <x0> <y0> <x1> <y1> [hold-seconds] [title-bar]")
    exit(2)
}
let owner = arguments[1]
let hold = arguments.count > 6 ? Double(arguments[6]) ?? 0.8 : 0.8
let titleBar = arguments.count > 7 ? Double(arguments[7]) ?? 28 : 28

guard AXIsProcessTrusted() else {
    print("not trusted for Accessibility: CGEvent.post would deliver nothing")
    exit(3)
}

func area(_ window: [String: Any]) -> Double {
    guard let dictionary = window[kCGWindowBounds as String],
        let rect = CGRect(dictionaryRepresentation: dictionary as! CFDictionary)
    else { return 0 }
    return Double(rect.width * rect.height)
}

let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
guard
    // The largest of its normal-layer windows: AppKit opens a small window of
    // its own (about 53 x 48) beside a text view that has focus, and the first
    // match was that one on 2026-10-17.
    // 它在一般層級的視窗中最大的那個:AppKit 會在取得焦點的文字視圖旁開一個自己的小視窗(約 53 x 48),
    // 2026-10-17 第一個符合的就是它。
    let window = windows.filter({
        ($0[kCGWindowOwnerName as String] as? String) == owner
            && ($0[kCGWindowLayer as String] as? Int) == 0
    }).max(by: { area($0) < area($1) }),
    let boundsDictionary = window[kCGWindowBounds as String],
    let bounds = CGRect(dictionaryRepresentation: boundsDictionary as! CFDictionary)
else {
    print("no on-screen window owned by \(owner)")
    exit(4)
}

// Bring it forward first, so the press lands on it and not on a window above.
// 先把它帶到前面，讓按壓落在它身上，而不是上面的視窗。
if let pid = window[kCGWindowOwnerPID as String] as? pid_t {
    NSRunningApplication(processIdentifier: pid)?.activate()
    usleep(400_000)
}

func screen(_ x: Double, _ y: Double) -> CGPoint {
    CGPoint(x: bounds.origin.x + x, y: bounds.origin.y + titleBar + y)
}

func post(_ type: CGEventType, _ at: CGPoint) {
    let event = CGEvent(
        mouseEventSource: CGEventSource(stateID: .hidSystemState),
        mouseType: type, mouseCursorPosition: at, mouseButton: .left
    )!
    event.post(tap: .cghidEventTap)
}

let start = screen(x0, y0)
let end = screen(x1, y1)
post(.mouseMoved, start)
usleep(100_000)
post(.leftMouseDown, start)
usleep(useconds_t(hold * 1_000_000))
let steps = 12
for step in 1...steps {
    let t = Double(step) / Double(steps)
    post(.leftMouseDragged, CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
    usleep(40_000)
}
usleep(150_000)
post(.leftMouseUp, end)
print(
    "long-press drag in \(owner): content (\(Int(x0)),\(Int(y0))) -> (\(Int(x1)),\(Int(y1))),"
        + " held \(hold) s, window at (\(Int(bounds.origin.x)),\(Int(bounds.origin.y)))"
)
