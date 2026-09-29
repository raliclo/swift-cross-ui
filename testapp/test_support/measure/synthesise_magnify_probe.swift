import AppKit

// SUPERSEDED 2026-09-30: this probe's route (a type-30 event wrapped in NSEvent and
// posted in-process) stays closed, but the gesture CAN be synthesised: a type-29
// gesture event with field 110 = 8 (zoom) or 5 (rotation), 113/114 the value and
// 132 the phase, posted through the HID tap with the pointer over the view. See
// AppKitSynthesiser.postGesture, measured with P65 (magnify 1.500, rotate 0.524 rad).
// 已被取代(2026-09-30):本探針的途徑仍是封閉的,但手勢**可以**合成——見 AppKitSynthesiser.postGesture。
//
// 一支只做一件事的探針:試著合成一個 magnify 手勢,看 NSMagnificationGestureRecognizer 會不會觸發。
final class D: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var fired = 0
    var lastMagnification = 0.0

    func applicationDidFinishLaunching(_ n: Notification) {
        window = NSWindow(contentRect: NSRect(x: 300, y: 300, width: 320, height: 200),
                          styleMask: [.titled], backing: .buffered, defer: false)
        let view = NSView(frame: window.contentView!.bounds)
        view.addGestureRecognizer(
            NSMagnificationGestureRecognizer(target: self, action: #selector(hit(_:))))
        window.contentView!.addSubview(view)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.attempt() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            print("RESULT fired=\(self.fired) lastMagnification=\(self.lastMagnification)")
            NSApp.terminate(nil)
        }
    }

    func attempt() {
        // 途徑 1:以 CGEvent 建一個 type 30(NSEventTypeMagnify)的事件，設定 magnification 欄位，
        // 再包成 NSEvent 投遞進本行程。兩者都是公開 API;未公開的是「哪一個欄位帶著倍率」。
        guard let cg = CGEvent(source: CGEventSource(stateID: .hidSystemState)) else {
            print("could not create a CGEvent at all"); return
        }
        guard let magnifyType = CGEventType(rawValue: 30) else { print("no type 30"); return }
        cg.type = magnifyType
        cg.location = NSPoint(x: 460, y: 400)
        // 常見說法是欄位 113 帶著 magnification。這是本探針要測的那個猜測。
        cg.setDoubleValueField(CGEventField(rawValue: 113)!, value: 0.5)
        if let ns = NSEvent(cgEvent: cg) {
            print("built an NSEvent of type \(ns.type.rawValue)")
            NSApp.postEvent(ns, atStart: false)
        } else {
            print("CGEvent could not be wrapped as an NSEvent -- route 1 is closed")
        }
    }

    @objc func hit(_ g: NSMagnificationGestureRecognizer) {
        fired += 1
        lastMagnification = Double(g.magnification)
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let d = D(); app.delegate = d; app.run()
