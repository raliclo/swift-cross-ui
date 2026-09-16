import AppKit
import ApplicationServices

// Reads the REAL accessibility tree of a running app from outside it.
//
// Outside is the point. An in-process walk reads the view hierarchy that feeds
// the accessibility tree, not the tree, and the two differ exactly where the
// bugs are -- a label set on a wrapper the screen reader never visits looks
// correct from inside and is absent from here.
//
// Prints AXButton and AXStaticText both, because #123 needs two kinds of
// evidence: that a name IS what was asked for, and that a hidden subtree's text
// is NOT there at all. The second cannot be shown by a dump that only lists
// buttons.
//
// 從**外部**讀取一支執行中 app 的**真正**無障礙樹。
//
// 「外部」正是重點。行程內的走訪讀到的是「餵養無障礙樹的那個 view 階層」,而不是那棵樹;而兩者的
// 差異,恰好就落在缺陷所在之處——一個設在「螢幕閱讀器從不造訪的包裝」上的標籤,從裡面看是正確的,
// 從這裡看則完全不存在。
//
// 同時列出 AXButton 與 AXStaticText,因為 #123 需要兩種證據:一個名字**就是**所要求的那個,以及
// 一棵被隱藏的子樹的文字**完全不在**那裡。後者無法由一份只列按鈕的輸出來證明。
let appPath = CommandLine.arguments[1]
func attr(_ e: AXUIElement, _ k: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(e, k as CFString, &v) == .success ? v : nil
}
func str(_ e: AXUIElement, _ k: String) -> String { (attr(e, k) as? String) ?? "" }
func kids(_ e: AXUIElement) -> [AXUIElement] {
    (attr(e, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
}
let p = Process()
p.executableURL = URL(fileURLWithPath: appPath)
p.arguments = ["--debug"]
try p.run()
sleep(3)
let app = AXUIElementCreateApplication(p.processIdentifier)
var n = 0
func walk(_ e: AXUIElement, _ d: Int) {
    // Raised from 40 to 120: P67 grew a second section and the old cap cut the
    // dump off before reaching it, which read as "those elements are missing".
    // 由 40 提高到 120:P67 多了第二節,而舊的上限會在抵達它之前就把輸出截斷——那讀起來會像是
    // 「那些元素不見了」。
    if d > 10 || n > 120 { return }
    let role = str(e, kAXRoleAttribute as String)
    if role == kAXButtonRole as String {
        n += 1
        print(
            "  AXButton title='\(str(e, kAXTitleAttribute as String))'"
                + " desc='\(str(e, kAXDescriptionAttribute as String))'"
                + " help='\(str(e, kAXHelpAttribute as String))'"
                + " value='\(str(e, kAXValueAttribute as String))'"
        )
    }
    if role == kAXStaticTextRole as String {
        n += 1
        let text = str(e, kAXValueAttribute as String)
        if !text.isEmpty { print("  AXStaticText '\(text)'") }
    }
    for c in kids(e) { walk(c, d + 1) }
}
for w in kids(app) where str(w, kAXRoleAttribute as String) == kAXWindowRole as String {
    print("window: \(str(w, kAXTitleAttribute as String))")
    walk(w, 0)
}
p.terminate()
