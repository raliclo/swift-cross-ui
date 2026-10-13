import AppKit
import SwiftCrossUI

extension AppKitBackend: BackendFeatures.FocusableTargets {
    public func createFocusableTarget(wrapping child: Widget) -> Widget {
        NSFocusableTarget(wrapping: child)
    }

    public func updateFocusableTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        isFocusable: Bool
    ) {
        (target as! NSFocusableTarget).isFocusable = isFocusable && environment.isEnabled
    }
}

/// `.focusable()` on AppKit: a container that accepts first responder.
///
/// It is a key view, so Tab reaches it; a mouse-down that its content lets
/// through makes it first responder on the way past; and AppKit draws its focus
/// ring around the bounds. Tab and Shift-Tab are handled here, because an
/// `NSKeyEventTarget` further up the responder chain reports every key it is
/// given and passes none on.
///
/// AppKit 上的 `.focusable()`:一個接受 first responder 的容器。它是 key view,所以 Tab 到得了;內容放過的
/// mouse-down 經過時讓它成為 first responder;AppKit 沿著 bounds 畫焦點環。Tab 與 Shift-Tab 在這裡處理，
/// 因為 responder chain 上方的 `NSKeyEventTarget` 會回報它收到的每個按鍵、一個也不往上傳。
final class NSFocusableTarget: NSView {
    var isFocusable = true {
        didSet {
            guard isFocusable != oldValue else { return }
            if !isFocusable, window?.firstResponder === self {
                window?.makeFirstResponder(nil)
            }
            noteFocusRingMaskChanged()
        }
    }

    init(wrapping child: NSView) {
        super.init(frame: .zero)
        focusRingType = .exterior
        addSubview(child)
        child.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: leadingAnchor),
            child.topAnchor.constraint(equalTo: topAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { isFocusable }
    override var canBecomeKeyView: Bool { isFocusable }

    override func drawFocusRingMask() {
        bounds.fill()
    }

    override var focusRingMaskBounds: NSRect { bounds }

    override func mouseDown(with event: NSEvent) {
        if isFocusable { window?.makeFirstResponder(self) }
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        // 48 is the Tab key. 48 是 Tab 鍵。
        guard event.keyCode == 48, let window else {
            super.keyDown(with: event)
            return
        }
        // The window keeps no key view loop of its own here, so `selectNextKeyView`
        // from this view found nothing and Tab stayed put (P91, 2026-10-13).
        // 這裡的視窗沒有自己維護 key view loop,所以從這個 view 呼叫 `selectNextKeyView` 找不到東西，Tab 原地不動。
        window.recalculateKeyViewLoop()
        if event.modifierFlags.contains(.shift) {
            window.selectKeyView(preceding: self)
        } else {
            window.selectKeyView(following: self)
        }
    }

    /// Whether `view` holds a focusable target: a key target around one waits
    /// for the focus instead of taking it.
    /// `view` 裡是否有可聚焦的 target:包著它的按鍵 target 會等焦點，而不是自己拿。
    static func isHeld(by view: NSView) -> Bool {
        view.subviews.contains { $0 is NSFocusableTarget || isHeld(by: $0) }
    }
}
